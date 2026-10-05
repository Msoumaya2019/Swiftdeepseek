// AppViewModel.swift
// Chef d'orchestre de l'application : authentification, état, synchronisation.
//
// Correspondance : `src/App.tsx` côté React Native, qui tient le même rôle.
// Les vues ne parlent jamais directement à Supabase ni au stockage : elles
// passent par ici.

import Combine
import SwiftUI

@MainActor
public final class AppViewModel: ObservableObject {

    @Published public private(set) var state: AppState
    @Published public var selectedTab: MainTab = .home
    @Published public var notice: String?

    /// Les réglages de répétition audio — **locaux**, et jamais dans `user_state`
    /// (`LOCAL_DATA_MIGRATION.md` §4 a)).
    ///
    /// Ils vivent ici, et non dans la vue, pour une raison précise :
    /// `LocalStore` savait lire et écrire `audio-repeat-preferences.json` depuis
    /// le début, mais **personne ne l'appelait** — les réglages n'étaient donc
    /// persistés nulle part, et l'écran `AudioRepeatSettingsView` n'avait rien à
    /// lire. Le modèle est désormais le seul écrivain.
    @Published public private(set) var repeatPreferences: AudioRepeatPreferences

    public let auth: AuthService
    public let repository: AppStateRepository
    public let sync: StateSyncService
    public let connectivity: ConnectivityService
    public let audio: AudioService
    public let sources: QuranSourceService
    public let social: SocialService
    public let coran1441: Coran1441DownloadService
    /// Les rappels **locaux** — la seule partie des notifications qui
    /// touche l'appareil. Le jeton APNs et la table `push_devices` ne sont
    /// pas portés ; voir `Services/LocalNotificationScheduler.swift`.
    public let notifications: LocalNotificationService

    private let store: LocalStore
    private let client: SupabaseRESTClient
    private var cancellables = Set<AnyCancellable>()
    /// La dernière écriture des réglages de répétition, pour les **enchaîner**.
    private var preferencesWrite: Task<Void, Never>?

    public init() {
        let client = SupabaseRESTClient(
            baseURL: AppConfig.supabaseURL,
            publishableKey: AppConfig.supabasePublishableKey
        )
        let store = LocalStore()
        let auth = AuthService(client: client)
        let repository = AppStateRepository(store: store)

        self.client = client
        self.store = store
        self.auth = auth
        self.repository = repository
        self.sync = StateSyncService(client: client, auth: auth, store: store, repository: repository)
        self.connectivity = ConnectivityService()
        self.audio = AudioService(store: store)
        self.sources = QuranSourceService()
        self.social = SocialService(client: client)
        self.coran1441 = Coran1441DownloadService()
        self.notifications = LocalNotificationService(scheduler: UserNotificationsScheduler())
        self.state = repository.state
        // `LocalStore` est un **acteur** : sa lecture ne peut pas se faire ici,
        // dans un `init` synchrone — le compilateur répond « call to
        // actor-isolated instance method in a synchronous main actor-isolated
        // context ». C'est exactement ce que le run #45 a relevé. Les valeurs par
        // défaut tiennent donc jusqu'au chargement réel, qui a lieu dans
        // `start()`, quelques microsecondes après le lancement.
        self.repeatPreferences = .defaults

        // Les vues observent ce modèle ; on répercute les changements du dépôt.
        repository.$state
            .sink { [weak self] value in self?.state = value }
            .store(in: &cancellables)

        // Les services sont des objets observables SÉPARÉS du modèle. Sans ce
        // relais, une vue qui lit `model.audio.isPlaying` ou
        // `model.connectivity.isOffline` ne serait jamais réévaluée quand la
        // valeur change : le bouton lecture/pause du mini-lecteur resterait figé,
        // la mise en évidence du verset en cours de récitation ne suivrait pas,
        // et une bannière « hors ligne » n'apparaîtrait jamais. Le défaut est
        // silencieux — la vue s'affiche, simplement elle ne se met plus à jour.
        //
        // `coran1441` est dans la liste pour la même raison : sans lui, la barre
        // de progression du téléchargement resterait à zéro du début à la fin,
        // alors que l'installation avancerait réellement.
        for publisher in [
            audio.objectWillChange,
            sync.objectWillChange,
            connectivity.objectWillChange,
            coran1441.objectWillChange
        ] {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        audio.select(reciter: Reciter.find(repository.state.audioPreferences?.reciterId))
    }

    // MARK: Démarrage

    public func start() async {
        // Les réglages de répétition sont **locaux** : les lire ne dépend ni du
        // réseau ni de la session. C'est ce qui permet à l'application de
        // s'ouvrir hors ligne avec les réglages de l'utilisateur, et non avec
        // ceux par défaut. Un fichier absent, illisible ou d'une forme
        // inattendue rend les valeurs par défaut — jamais une erreur.
        repeatPreferences = await store.loadAudioPreferences()
        // Le lecteur reçoit les réglages **avant** toute lecture : sans cela le
        // silence et la vitesse choisis seraient ignorés au premier lancement, et
        // la vitesse ne s'appliquerait qu'à partir du premier changement.
        audio.setPreferences(repeatPreferences)
        await auth.restore()
        connectivity.start { [weak self] in
            await self?.sync.flush()
        }
        if auth.userId != nil {
            await sync.syncOnSignIn()
            audio.select(reciter: Reciter.find(repository.state.audioPreferences?.reciterId))
        }
        await sync.refreshPendingCount()
    }

    /// Ouvre l'application sur la dernière page lue — comportement de reprise
    /// de l'application actuelle (`state.lastRead`).
    public var resumePage: Int {
        repository.state.lastRead?.page ?? 1
    }

    /// L'édition que le lecteur **affiche**.
    ///
    /// Ce n'est pas toujours celle qui est enregistrée : une édition que cette
    /// version ne sait pas rendre est remplacée à l'affichage, sans que la
    /// préférence soit touchée — voir `QuranEdition.displayed(stored:)`.
    public var edition: QuranEdition {
        QuranEdition.displayed(stored: repository.state.reader?.mushaf)
    }

    /// La préférence d'affichage **telle qu'elle est enregistrée**, y compris
    /// quand cette version ne sait pas la rendre.
    ///
    /// Écrit en deux temps, et non `reader?.mushaf.flatMap { … }` : sur une
    /// chaîne, `flatMap` se résout sur `Sequence` — celle des `Character` — et
    /// non sur `Optional`. Le compilateur refuse alors le `Character` reçu, ce
    /// qui est heureux, mais le message parle de types qui n'ont rien à voir
    /// avec l'intention.
    public var storedEdition: QuranEdition? {
        guard let stored = repository.state.reader?.mushaf else { return nil }
        return QuranEdition(rawValue: stored)
    }

    /// L'édition demandée par l'utilisateur que cette version ne sait pas
    /// afficher, s'il y en a une.
    ///
    /// Sert à le **dire** dans le lecteur. Substituer une édition en silence
    /// ferait passer une limite de cette version pour un choix ignoré.
    public var substitutedEdition: QuranEdition? {
        guard let stored = storedEdition, !stored.isAvailable else { return nil }
        return stored
    }

    // MARK: Connexion

    /// Jeton d'accès à jour pour les appels sociaux. Rafraîchit la session si
    /// elle est près d'expirer — l'application React Native fait de même
    /// (`supabase.auth.getSession()` avant chaque requête).
    public func socialAccessToken() async -> String? {
        try? await auth.validAccessToken()
    }

    /// Une tentative de connexion ou d'inscription, et le texte à en dire.
    ///
    /// Rend le texte au lieu de le poser dans `notice`, parce que les deux
    /// appelants ne le montrent pas de la même façon. `SignInView` est une
    /// **porte** : il affiche l'échec à côté de ses champs, et un succès le fait
    /// disparaître puisque la session change d'écran. La carte du profil, elle,
    /// annonce aussi les succès, par l'avis global. Poser `notice` ici ferait
    /// apparaître « Tes données de ce compte ont été retrouvées. » en rouge sur
    /// l'écran de connexion, qui traite tout avis comme une erreur.
    ///
    /// La décision est celle de `ProfileOptions` : `outcome(register:hasSession:)`
    /// puis `notice(for:)`, et `failedNotice(_:)` pour le repli de l'échec. Rien
    /// n'est décidé ici — cette méthode appelle le service, puis traduit.
    ///
    /// `hasSession` est la valeur rendue par le service, et c'est elle qui
    /// distingue les quatre issues : `signUp` rend `nil` quand la confirmation
    /// par courriel est exigée (`mailer_autoconfirm` est faux sur ce projet), et
    /// ce `nil` n'est pas une erreur.
    public func authenticate(
        email: String,
        password: String,
        register: Bool
    ) async -> (outcome: ProfileOptions.AuthOutcome, notice: String) {
        do {
            let session: SupabaseSession?
            if register {
                session = try await auth.signUp(email: email, password: password)
            } else {
                session = try await auth.signIn(email: email, password: password)
            }
            let outcome = ProfileOptions.outcome(register: register, hasSession: session != nil)
            if session != nil {
                await sync.syncOnSignIn()
                audio.select(reciter: Reciter.find(repository.state.audioPreferences?.reciterId))
            }
            return (outcome, ProfileOptions.notice(for: outcome))
        } catch {
            return (.failed, ProfileOptions.failedNotice(error.localizedDescription))
        }
    }

    public func signOut() async {
        await auth.signOut()
        await repository.load(userId: nil)
        selectedTab = .home
        // L'avis survit au changement d'écran : il est monté au-dessus de la
        // porte, dans `App/ContentView.swift`, et non dans les onglets.
        notice = ProfileOptions.signedOutNotice
    }

    // MARK: Profil

    /// Enregistre le prénom — `App.tsx:309`.
    ///
    /// La garde et l'écriture viennent de `ProfileOptions`, et les deux textes
    /// aussi. Cette méthode ne décide rien : elle pose l'avis, ce que le modèle
    /// ne peut pas faire.
    ///
    /// Les deux moitiés — `savedFirstName` puis `settingFirstName` — plutôt que
    /// `savingFirstName`, qui les compose : `update` applique sa transformation à
    /// l'état **courant**, au moment de l'écriture, et c'est cet état-là qui
    /// décide quel sexe poser quand le profil est absent. Composer l'état ici
    /// l'aurait figé à l'instant du clic. Les tests, eux, vérifient que la
    /// composition `savingFirstName` rend bien la même décision que ces deux
    /// appels.
    public func saveFirstName(_ raw: String) {
        guard let value = ProfileOptions.savedFirstName(raw) else {
            notice = ProfileOptions.firstNameInvalidNotice
            return
        }
        update { ProfileOptions.settingFirstName($0, value) }
        notice = ProfileOptions.firstNameSavedNotice
    }

    /// « Synchroniser maintenant » — `App.tsx:322`.
    ///
    /// L'original appelle `pushState(state)` et montre le message de l'erreur tel
    /// quel — pas le repli de la connexion. `pushCurrent` est son équivalent :
    /// il écrit le document courant **sans fusion**, ce qui est le geste demandé
    /// par ce bouton ; la fusion, elle, appartient à la file d'attente.
    public func syncNow() async {
        do {
            try await sync.pushCurrent()
            notice = ProfileOptions.syncedNotice
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: Mutations

    /// Toute modification passe par ici : écriture locale immédiate, puis
    /// synchronisation en tâche de fond. C'est ce qui rend l'application
    /// utilisable sans réseau.
    public func update(_ transform: @escaping (AppState) -> AppState) {
        Task {
            await repository.mutate(transform)
            await sync.flush()
        }
    }

    /// « Reprendre » une marque-page — `App.tsx:492`.
    ///
    /// Rend la page à ouvrir, ET date la marque-page : `Bookmark.use` écrit
    /// `lastUsedAt`, ce qui fait vivre le badge « Dernière reprise » de la liste.
    /// Sans lui, reprendre une marque-page ne laisserait aucune trace, et le
    /// badge resterait sur l'entrée précédente.
    ///
    /// La règle vit ICI, et non dans les deux écrans qui l'appellent — le lecteur
    /// et l'onglet Coran. C'est ce qui garantit que la page annoncée par la liste
    /// et celle que la reprise ouvre sont la même : deux copies divergeraient.
    ///
    /// `nil` veut dire « page indéterminée » ; les deux appelants gardent alors
    /// leur page courante au lieu d'en inventer une.
    ///
    /// L'original remet aussi à zéro le panneau de séance et sélectionne le
    /// verset ; ni l'un ni l'autre n'existent dans ce portage.
    @discardableResult
    public func resumeBookmark(_ verseID: Int) -> Int? {
        let stored = state.bookmarks?[String(verseID)]
        let target = QuranSourceNavigation.versePage(
            edition,
            verseID: verseID,
            current: stored?.sourcePages?[edition.rawValue]
        )
        update { Bookmark.use($0, verseID: verseID, page: target) }
        return target
    }

    /// Enregistre la page atteinte à la fermeture du lecteur.
    public func recordReading(page: Int) {
        let verseID = Quran.pageRange(page)?.start
        update { state in
            var next = state
            var readPages = next.readPages ?? []
            if !readPages.contains(page) { readPages.append(page) }
            next.readPages = readPages.sorted()
            next.lastRead = LastRead(
                page: page,
                verseId: verseID ?? state.lastRead?.verseId ?? 1,
                readAt: DateKeys.iso(Date())
            )
            if next.reader?.mushaf == "coranTest" {
                next.reader?.testPage = page
            }
            return next
        }
    }

    /// Enregistre l'édition choisie.
    ///
    /// La règle d'écriture vit dans `QuranDisplayOptions.settingEdition` — avec
    /// celles du fond et du suivi audio, qui posent un défaut différent sur
    /// `reader.mushaf`. Les recopier ici ferait trois copies d'un contrat qui
    /// décide de ce que l'application React Native relira.
    public func setEdition(_ edition: QuranEdition) {
        update { QuranDisplayOptions.settingEdition($0, edition) }
    }

    /// Enregistre le fond du Coran (`state.reader.paper`) —
    /// `App.tsx:330`, `quranPaperOptions`.
    ///
    /// Le fond n'est consommé que par l'édition rendue en WebView, absente de ce
    /// portage : la préférence est donc stockée et affichée, mais elle ne colore
    /// encore rien ici. Voir l'en-tête de `Core/QuranDisplayOptions.swift`.
    public func setPaper(_ paper: String) {
        update { QuranDisplayOptions.settingPaper($0, paper) }
    }

    /// Enregistre le suivi automatique de la récitation —
    /// `App.tsx:330` et `App.tsx:445`.
    ///
    /// Comme le fond, il n'est pas encore appliqué : le lecteur de ce portage
    /// n'enchaîne pas encore sur la page du verset récité. La préférence est
    /// stockée pour que les deux applications s'accordent.
    public func setFollowAudio(_ value: Bool) {
        update { QuranDisplayOptions.settingFollowAudio($0, value) }
    }

    // MARK: Notifications

    /// Écrit une préférence de notification — `App.tsx:306`.
    ///
    /// La règle vit dans `NotificationOptions.setting` : elle **matérialise** le
    /// défaut quand `notifications` est absent, exactement comme la carte de
    /// l'affichage du Coran. La recopier ici en ferait une seconde copie d'un
    /// contrat que l'application React Native relit.
    ///
    /// Le rappel quotidien est ensuite synchronisé — et **seulement** si un compte
    /// est connecté et le questionnaire terminé (`App.tsx:173`). Le garde est dans
    /// le modèle ; ce n'est pas un oubli, et l'annulation d'un rappel déjà
    /// programmé en dépend.
    public func setNotification(_ key: String, to value: Bool) {
        update { NotificationOptions.setting($0, key, to: value) }
        guard key == "learning" else { return }
        let current = state
        guard NotificationOptions.canSyncLearningReminder(
            account: current.userId != nil,
            onboardingDone: current.onboardingDone
        ) else { return }
        Task { await notifications.syncLearningReminder(enabled: value) }
    }

    /// `App.tsx:305` — l'effet de montage de la carte.
    ///
    /// Prédicat de la **carte** — `cardAllows`, qui ne retient pas `EPHEMERAL` —
    /// puis écriture du drapeau si la permission est acquise. La demande système
    /// n'est **pas** envoyée ici : l'original lit seulement.
    public func syncDeviceNotificationPermission() async -> Bool {
        let result = await notifications.ensurePermission(prompt: false)
        let allowed = NotificationOptions.cardAllows(result)
        if allowed { markPermissionExplainedFromCard() }
        return allowed
    }

    /// `App.tsx:335` — le bouton « Autoriser les notifications sur ce téléphone ».
    ///
    /// Prédicat du **service** — `serviceAllows`, qui retient `EPHEMERAL` — donc
    /// pas le même que l'effet de montage, et c'est **mesuré** : les deux
    /// prédicats de l'original diffèrent, et les confondre ferait diverger la
    /// porte d'autorisation de l'application React Native.
    public func requestDeviceNotificationPermission() async -> Bool {
        let result = await notifications.ensurePermission(prompt: true)
        let allowed = NotificationOptions.serviceAllows(result)
        if allowed { markPermissionExplainedFromCard() }
        return allowed
    }

    /// `App.tsx:305,335` — l'écriture de la carte, avec son retour anticipé : le
    /// drapeau déjà posé rend l'état **inchangé**.
    public func markPermissionExplainedFromCard() {
        update { NotificationOptions.markingPermissionExplainedFromCard($0) }
    }

    /// `App.tsx:345` — la notification de test, programmée cinq secondes plus
    /// tard. Rend `true` si elle est programmée, `false` si la permission manque.
    public func testLocalNotification() async -> Bool {
        await notifications.testLocalNotification()
    }

    /// `App.tsx:346` — le texte de l'avis des rappels programmés. Le composer dans
    /// la vue ferait une seconde copie des accords entre parenthèses.
    public func scheduledReminderNotice() async -> String {
        await notifications.countsNotice()
    }

    // MARK: Apparence (thème et couleur d'accent)

    /// Le thème choisi — `update(touch({...state, theme}))`,
    /// `src/ui/AppearanceScreen.tsx:6`.
    ///
    /// Aucune validation en amont, et c'est délibéré : `Theme.palette(named:)`
    /// et `AppearanceOptions` replient déjà un thème inconnu sur « white ».
    /// Refuser la valeur ici priverait le sous-titre de la ligne « Apparence »
    /// de son cas « aucun nom », qui est celui de l'original — une version plus
    /// ancienne peut avoir stocké une clé que celle-ci ne connaît plus.
    public func setTheme(_ theme: String) {
        update { state in
            var next = state
            next.theme = theme
            return Program.touch(next)
        }
    }

    /// L'accent choisi — `update(touch({...state, accent}))`.
    ///
    /// L'accent **stocké** décide du rond coché
    /// (`AppearanceOptions.displayedAccent`) ; la palette suit une règle
    /// voisine mais distincte, portée par `palette` plus bas : elle n'applique
    /// l'accent que s'il est donné ou si le thème est blanc.
    public func setAccent(_ accent: String) {
        update { state in
            var next = state
            next.accent = accent
            return Program.touch(next)
        }
    }

    public func selectReciter(_ reciter: Reciter) {
        audio.select(reciter: reciter)
        update { state in
            var next = state
            next.audioPreferences = AudioPreferences(reciterId: reciter.id)
            return next
        }
    }

    // MARK: Programme et connaissances

    /// Ce qui suit une modification des connaissances : rien pendant
    /// l'assistant, une régénération du programme après.
    ///
    /// C'est la règle de `src/App.tsx:364`, recopiée telle quelle :
    ///
    ///     const updateKnowledge = next =>
    ///       update(state.onboardingDone ? generateProgram(seedInitialRevisions(next)) : next);
    ///
    /// Pendant l'assistant, `onboardingDone` est faux : régénérer à chaque case
    /// cochée écraserait un programme que l'utilisateur est justement en train
    /// de définir. Après l'assistant, la régénération est au contraire ce qui
    /// fait qu'une connaissance nouvellement déclarée **retire** les séances
    /// correspondantes — sans elle, l'application continuerait de proposer
    /// d'apprendre ce qu'on vient de déclarer su.
    ///
    /// `static` à dessein : les fermetures passées à `update` sont échappantes,
    /// et une méthode d'instance y capturerait `self` sans nécessité.
    private static func afterKnowledgeChange(_ state: AppState, _ next: AppState) -> AppState {
        guard state.onboardingDone else { return next }
        return Program.generateProgram(Program.seedInitialRevisions(next))
    }

    /// Marque une plage entière comme connue — ou comme à apprendre, quand
    /// `mastery` vaut `.learning`. `markKnowledge`, `src/core/program.ts:101`.
    ///
    /// `.learning` **efface** aussi la date de mémorisation et l'échéance de
    /// révision de chaque verset (`program.ts:106`) : retirer une connaissance
    /// ne laisse donc pas de trace de révision derrière elle. C'est le modèle
    /// qui le fait, pas la vue.
    public func setKnowledge(_ range: VerseRange, mastery: Mastery) {
        update { state in
            Self.afterKnowledgeChange(
                state,
                Program.markKnowledge(state, range: range, mastery: mastery)
            )
        }
    }

    /// Bascule « connu / à apprendre » d'une plage — `toggleKnownRange`,
    /// `src/core/program.ts:115`. C'est l'action des cases à cocher de
    /// « Modifier mes connaissances » : sourates, juz’, hizb.
    public func toggleKnownRange(_ range: VerseRange) {
        update { state in
            Self.afterKnowledgeChange(state, Program.toggleKnownRange(state, range: range))
        }
    }

    /// Enregistre objectif, rythme et jours d'apprentissage, puis reconstruit le
    /// programme.
    ///
    /// C'est la sauvegarde de `GoalScreen` (`src/ui/GoalScreen.tsx:16`) :
    ///
    ///     update(generateProgram(seedInitialRevisions(touch(draft))))
    ///
    /// Elle ne dépend PAS de `onboardingDone` : l'utilisateur vient explicitement
    /// de valider un objectif, le programme doit donc être refait — même si
    /// l'assistant n'a jamais été terminé.
    ///
    /// `finishingOnboarding` ajoute ce que fait la dernière étape de l'assistant
    /// (`src/App.tsx:390`) : `onboardingDone = true` et `onboardingStep` effacé.
    /// C'est un drapeau explicite plutôt qu'une seconde méthode, pour qu'il
    /// n'existe **qu'un seul** chemin d'écriture du programme.
    public func saveProgram(
        goal: Goal,
        pace: Pace,
        learningDays: [Int],
        finishingOnboarding: Bool = false
    ) {
        update { state in
            var next = state
            next.goal = goal
            next.pace = pace.rawValue
            next.learningDays = learningDays
            if finishingOnboarding {
                next.onboardingDone = true
                next.onboardingStep = nil
            }
            return Program.generateProgram(Program.seedInitialRevisions(Program.touch(next)))
        }
    }

    /// L'aperçu du programme qu'un objectif produirait — **sans rien écrire**.
    ///
    /// `GoalScreen` calcule le même aperçu sur un état brouillon
    /// (`src/ui/GoalScreen.tsx:13`) : `generateProgram(draft).sessions.find(
    /// s => s.status === 'todo')`. La vue n'a donc pas à connaître la
    /// génération : elle demande l'aperçu et affiche la plage.
    ///
    /// Comme dans l'original, le premier `todo` peut être une séance **déjà**
    /// planifiée plutôt qu'une séance neuve : l'aperçu est le début du
    /// programme tel qu'il serait, pas la première séance ajoutée.
    public func previewProgram(goal: Goal, pace: Pace, learningDays: [Int]) -> Session? {
        var draft = state
        draft.goal = goal
        draft.pace = pace.rawValue
        draft.learningDays = learningDays
        return Program.generateProgram(draft).sessions.first { $0.status == .todo }
    }

    /// Remet à zéro l'apprentissage et les révisions, en conservant le compte,
    /// le profil, les marque-pages et les préférences — `resetAllProgress`,
    /// `src/core/program.ts:90`. Voir la note sur les deux valeurs par défaut
    /// divergentes dans `Core/ProgramGoal.swift`.
    public func resetProgress() {
        update { Program.resetAllProgress($0) }
    }

    // MARK: Réglages de répétition audio (locaux)

    /// Enregistre les réglages de répétition et les écrit sur disque.
    ///
    /// L'original écrit **à chaque changement**, une fois les préférences lues
    /// (`PassageAudioPlayer.tsx:184`). Le fichier reste local : il n'est pas dans
    /// `user_state`, donc les deux applications ne partagent pas ces réglages.
    public func setRepeatPreferences(_ updated: AudioRepeatPreferences) {
        guard updated != repeatPreferences else { return }
        repeatPreferences = updated
        // Le lecteur est prévenu **tout de suite** : changer la vitesse pendant
        // une récitation doit s'entendre sans relancer la lecture
        // (`PassageAudioPlayer.tsx:227`). C'est `setPreferences` qui décide des
        // effets qui en découlent — et rien n'en découle tant que la vitesse n'a
        // pas changé.
        audio.setPreferences(updated)
        // `LocalStore` est un acteur : l'écriture est donc asynchrone. Les tâches
        // sont **enchaînées** — deux pastilles touchées coup sur coup ne doivent
        // pas laisser sur disque la valeur la plus ancienne. Des tâches non
        // structurées ne sont pas garanties de démarrer dans l'ordre de création,
        // et l'erreur serait silencieuse : le fichier resterait lisible.
        let previous = preferencesWrite
        preferencesWrite = Task { [store] in
            _ = await previous?.value
            try? await store.saveAudioPreferences(updated)
        }
    }

    /// Lance la lecture d'un passage.
    ///
    /// L'ordre est celui de `PassageAudioPlayer.tsx:176` : la plage est résolue
    /// **avant** le refus du compte — une plage invalide se plaint donc de la
    /// plage, même quand le compte est refusé lui aussi. Rend le message d'échec,
    /// ou `nil` quand la lecture a commencé.
    ///
    /// Les deux refus sont refaits par la machine, et c'est elle qui fait foi.
    /// Les répéter ici n'est pas une seconde décision : c'est ce qui permet de
    /// rendre le message à l'appelant, puisque `begin` ne rend que des effets.
    ///
    /// La **boucle** est désormais branchée :
    /// `Services/PassageAudioExecutor.swift` exécute les effets de
    /// `Core/PassageAudioEngine.swift`. Ce point démarre donc la plage entière —
    /// répétitions, silence choisi entre les versets, reprise enchaînée et arrêt
    /// automatique compris — et non plus seulement son premier verset.
    public func launchAudioPassage(_ requested: VerseRange) throws -> String? {
        let range = try PassageAudio.range(start: requested.start, end: requested.end)
        if let refusal = repeatPreferences.launchError { return refusal.message }
        audio.playPassage(range, preferences: repeatPreferences)
        return nil
    }

    // MARK: Indicateurs pour les vues

    public var progress: (quran: Double, goal: Double, goalKnown: Int, goalTotal: Int) {
        state.progress()
    }

    public var stats: WeeklyProgress.SessionStats {
        WeeklyProgress.stats(state)
    }

    public var weekly: WeeklyProgress.Summary {
        WeeklyProgress.weeklyProgress(state)
    }

    public var upcoming: [Session] {
        WeeklyProgress.upcomingSessions(state)
    }

    public var todaySessions: [Session] {
        let today = DateKeys.today()
        return state.sessions
            .filter { WeeklyProgress.scheduledDate($0) == today && $0.status == .todo }
            .sorted { $0.start < $1.start }
    }

    public var palette: Palette {
        var base = Theme.palette(named: state.theme)
        if let accentName = state.accent, let accent = Theme.accents[accentName] {
            base.green = accent.primary
            base.green2 = accent.primary
            base.selected = accent.soft
            base.surahBadge = accent.soft
            base.progress = accent.soft
        } else if state.theme == "white" || state.theme == nil {
            let accent = Theme.accents["prune"]!
            base.green = accent.primary
            base.green2 = accent.primary
            base.selected = accent.soft
            base.surahBadge = accent.soft
            base.progress = accent.soft
        }
        return base
    }
}

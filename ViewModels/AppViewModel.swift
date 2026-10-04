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
        self.audio = AudioService()
        self.sources = QuranSourceService()
        self.social = SocialService(client: client)
        self.coran1441 = Coran1441DownloadService()
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

    public func signIn(email: String, password: String) async {
        do {
            _ = try await auth.signIn(email: email, password: password)
            await sync.syncOnSignIn()
            audio.select(reciter: Reciter.find(repository.state.audioPreferences?.reciterId))
        } catch {
            notice = error.localizedDescription
        }
    }

    public func signOut() async {
        await auth.signOut()
        await repository.load(userId: nil)
        selectedTab = .home
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

    public func setEdition(_ edition: QuranEdition) {
        update { state in
            var next = state
            var reader = next.reader ?? ReaderPreferences(mushaf: edition.rawValue, followAudio: true)
            reader.mushaf = edition.rawValue
            next.reader = reader
            return next
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

    // MARK: Réglages de répétition audio (locaux)

    /// Enregistre les réglages de répétition et les écrit sur disque.
    ///
    /// L'original écrit **à chaque changement**, une fois les préférences lues
    /// (`PassageAudioPlayer.tsx:184`). Le fichier reste local : il n'est pas dans
    /// `user_state`, donc les deux applications ne partagent pas ces réglages.
    public func setRepeatPreferences(_ updated: AudioRepeatPreferences) {
        guard updated != repeatPreferences else { return }
        repeatPreferences = updated
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
    /// Ce qui reste : la **boucle**. `Core/PassageAudioEngine.swift` décide des
    /// transitions, mais rien ne les exécute encore — la couche AVFoundation n'est
    /// pas branchée. Ce point démarre donc le **premier** verset de la plage.
    public func launchAudioPassage(_ requested: VerseRange) throws -> String? {
        let range = try PassageAudio.range(start: requested.start, end: requested.end)
        if let refusal = repeatPreferences.launchError { return refusal.message }
        audio.play(verseID: range.start)
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

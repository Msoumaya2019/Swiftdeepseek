// NotificationOptions.swift
// Les notifications — les sept interrupteurs de la carte de réglages, la
// décision d'afficher une notification, et le routage d'un appui.
//
// Correspondance : la carte « Notifications » de `src/App.tsx:331-348`, la
// demande d'autorisation automatique de `src/App.tsx:110-122`, le gestionnaire
// de présentation et les fonctions de `src/services/notifications.ts`, et les
// émetteurs SQL `supabase/social-v2.sql:93,116` et
// `supabase/admin-notifications.sql:81`.
//
// POURQUOI CE FICHIER
//   `Features/Settings/SettingsView.swift` énonce la règle du dossier : un écran
//   ne calcule rien. Or la carte des notifications porte six décisions qui, si
//   elles vivaient dans une vue, divergeraient en silence :
//
//     1. la carte propose SEPT interrupteurs, alors que
//        `NotificationPreferences` porte HUIT clés : `revision` est déclarée
//        (`src/core/program.ts:19`) et n'apparaît dans aucune carte — c'est le
//        rappel de révision, programmé par le service, pas par l'utilisateur ;
//     2. écrire un interrupteur MATÉRIALISE le défaut : l'original part de
//        `state.notifications ?? {messages:true, learning:false}` puis remplace
//        la clé (`App.tsx:304,306`). Un appui sur un interrupteur, sur une
//        installation neuve, écrit donc AUSSI `messages:true` et
//        `learning:false`. Même asymétrie que la carte de l'affichage du Coran,
//        et même raison : c'est le contrat que l'application React Native relit ;
//     3. `permissionExplained` a DEUX écritures qui ne posent pas la même chose.
//        Celle de l'effet automatique (`App.tsx:119`) force `learning:false` et
//        recalcule `messages` par `!== false` ; celle de la carte
//        (`App.tsx:305`) ajoute seulement le drapeau au défaut matérialisé. Les
//        deux se gardent par un retour anticipé si le drapeau est déjà posé ;
//     4. la permission a TROIS prédicats, et deux d'entre eux divergent. L'effet
//        automatique (`App.tsx:112`) et `ensureNotificationPermission`
//        (`notifications.ts:61`) retiennent `EPHEMERAL` ; la carte
//        (`App.tsx:305`) ne le retient PAS. Ce portage garde les deux, sous deux
//        noms distincts, plutôt que d'en choisir un en silence ;
//     5. la décision d'afficher compte SEPT portes, et l'une d'elles repose sur
//        une comparaison d'égalité stricte où `null === null` vaut `true`. Un
//        message de groupe porte `linkId: null` (`social-v2.sql:93` sérialise
//        `new.link_id`, nullable) : au premier plan et sans conversation
//        ouverte, `null === null` rend `true` et la notification est
//        SUPPRIMÉE. C'est pourquoi les champs de charge utile sont modélisés
//        avec trois états — absent, `null`, chaîne — et non deux ;
//     6. le registre des identifiants déjà affichés se vide ENTIER au-delà de
//        200 entrées (`notifications.ts:37`), y compris l'identifiant qui vient
//        d'y être ajouté. Ce n'est pas un oubli à réparer : c'est le
//        comportement à reproduire.
//
// CE QUI N'EST PAS APPLIQUÉ, ET POURQUOI C'EST DIT
//   Les notifications PUSH réelles (jeton APNs, table `push_devices`, diagnostic
//   de livraison) ne sont pas portées : elles demandent un appareil, un compte
//   Apple Developer et le déploiement des fonctions côté serveur. Le rappel
//   quotidien LOCAL, lui, est porté — voir
//   `Services/LocalNotificationScheduler.swift`. Les préférences sont donc
//   stockées, affichées et vérifiées dans les deux applications dès maintenant,
//   ce qui est la condition de la compatibilité.

import Foundation

public enum NotificationOptions {

    // MARK: - Les genres de notification

    /// Les valeurs de la clé `kind` d'une charge utile. Elles viennent du SQL,
    /// jamais du client : `social-v2.sql:93,116`, `notifications.sql:64`,
    /// `admin-notifications.sql:81`.
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case learningReminder = "learning-reminder"
        case revisionReminder = "revision-reminder"
        case message = "private-message"
        case progress = "friend-progress"
        case correction = "recitation-corrected"
        case admin = "admin-reminder"
        case notificationTest = "notification-test"
        case quizDaily = "quiz-daily"
        case quizChallenge = "quiz-challenge"
        case quizResult = "quiz-result"
        case friendRequest = "friend-request"
        case friendAccepted = "friend-accepted"
    }

    /// La valeur d'un champ de charge utile telle que le JSON la porte.
    ///
    /// Trois états, et non deux : `notifications.ts:30` compare
    /// `data?.linkId === activeLinkId`, où `null === null` vaut `true` et
    /// `undefined === null` vaut `false`. Un `String?` confondrait les deux, et
    /// changerait la décision pour les messages de groupe.
    public enum PayloadString: Equatable, Sendable {
        case missing
        case null
        case string(String)

        /// La chaîne, ou `nil` — c'est le test `typeof x === 'string'` de
        /// l'original, employé par le routage et par `uniqueId`.
        public var string: String? {
            if case .string(let value) = self { return value }
            return nil
        }
    }

    // MARK: - Les sept interrupteurs, dans l'ordre de la carte

    /// Un interrupteur de la carte, tel que `notificationSwitch`
    /// (`App.tsx:307`) le construit : un libellé, une clé, et le repli employé
    /// quand la clé est absente.
    ///
    /// Le repli n'est pas une décoration : `notificationPrefs[key] ?? fallback`
    /// décide de l'état affiché d'une installation neuve. Pour `messages` et
    /// `learning`, il coïncide avec le défaut matérialisé (`messages: true`,
    /// `learning: false`) ; pour les cinq autres, il vient de l'appel.
    public struct Switch: Identifiable, Equatable, Sendable {
        /// La clé écrite dans `state.notifications`.
        public var id: String
        public var label: String
        public var fallback: Bool
    }

    /// Les sept interrupteurs, dans l'ordre de `App.tsx:337-343`. L'ordre est
    /// une donnée : le recopier dans la vue ferait diverger les deux écrans.
    public static let switches: [Switch] = [
        Switch(id: "learning", label: "Rappel quotidien d’apprentissage à 19 h", fallback: false),
        Switch(id: "messages", label: "Messages privés", fallback: true),
        Switch(id: "friendRequests", label: "Demandes d’amis", fallback: true),
        Switch(id: "sharedProgress", label: "Progression partagée par les amis", fallback: false),
        Switch(id: "corrections", label: "Corrections de mes récitations", fallback: true),
        Switch(id: "adminMessages", label: "Rappels personnels du professeur", fallback: true),
        Switch(id: "messagePreview", label: "Afficher le contenu des messages", fallback: true),
    ]

    /// Les huit clés du type `NotificationPreferences` (`program.ts:19`), dans
    /// l'ordre de la déclaration.
    ///
    /// `revision` est la huitième : elle n'est dans **aucune** des deux cartes de
    /// l'original. Elle est écrite par le service (rappel de révision) et non par
    /// l'utilisateur. La porter ici évite qu'un futur écran l'oublie — et la
    /// distinguer de `switches` évite qu'il l'ajoute par symétrie.
    public static let allKeys: [String] = [
        "messages", "learning", "friendRequests", "sharedProgress",
        "revision", "corrections", "adminMessages", "messagePreview",
    ]

    /// La clé portée par le type mais proposée par aucune carte.
    public static let revisionKey = "revision"

    /// `state.notifications ?? {messages:true, learning:false}` — le défaut
    /// matérialisé par la carte (`App.tsx:304`).
    ///
    /// Il coïncide avec `Program.defaultState().notifications`, et c'est
    /// vérifié : deux endroits qui portent la même vérité sans pouvoir se lire
    /// doivent être tenus d'accord par un test.
    public static let materializedDefault = NotificationPreferences(
        messages: true,
        learning: false
    )

    /// Le sous-titre de la ligne de `SettingsView`. L'original n'en a pas : sa
    /// carte ne porte qu'un titre, « Notifications ». L'écran des réglages,
    /// lui, est une liste de lignes, et chaque ligne dit ce qu'elle contient —
    /// d'où ce décompte, qui se lit dans l'état et ne s'invente pas.
    public static func cardDetail(_ state: AppState) -> String {
        let active = switches.filter { value(state, $0.id) }.count
        return "\(active) sur \(switches.count) réglages activés"
    }

    // MARK: - Lire et écrire une préférence

    /// `notificationPrefs[key] ?? fallback` (`App.tsx:307`) : la valeur affichée
    /// par un interrupteur.
    ///
    /// Une clé inconnue rend `false`, comme `undefined ?? fallback` rendrait le
    /// repli — mais aucun appelant n'en produit, `switches` étant la seule
    /// source.
    public static func value(_ state: AppState, _ key: String) -> Bool {
        guard let fallback = switches.first(where: { $0.id == key })?.fallback else {
            return false
        }
        guard let stored = stored(state, key) else { return fallback }
        return stored
    }

    /// La valeur **stockée**, ou `nil` si la clé est absente — la distinction
    /// dont `value` a besoin pour appliquer son repli.
    public static func stored(_ state: AppState, _ key: String) -> Bool? {
        guard let prefs = state.notifications else { return nil }
        switch key {
        case "messages": return prefs.messages
        case "learning": return prefs.learning
        case "friendRequests": return prefs.friendRequests
        case "sharedProgress": return prefs.sharedProgress
        case "revision": return prefs.revision
        case "corrections": return prefs.corrections
        case "adminMessages": return prefs.adminMessages
        case "messagePreview": return prefs.messagePreview
        default: return nil
        }
    }

    /// `setNotification` — `App.tsx:306`.
    ///
    ///     update(touch({...state, notifications:{...notificationPrefs, [key]:value}}))
    ///
    /// Deux choses à ne pas manquer :
    ///
    ///   - `notificationPrefs` est le défaut **matérialisé** quand
    ///     `state.notifications` est absent : écrire une clé sur une installation
    ///     neuve écrit donc aussi `messages:true` et `learning:false` ;
    ///   - la fonction est **pure** — elle ne pose pas `updatedAt`. Toute
    ///     écriture est horodatée une fois par `AppStateRepository.mutate`. Le
    ///     `touch` visible dans l'original est le rôle de ce dépôt ici.
    ///
    /// Une clé inconnue rend l'état **inchangé**. L'original ne peut pas en
    /// produire : sa signature est une union de huit littéraux. Refuser plutôt
    /// qu'écrire une clé que le type Swift ne sait pas relire.
    public static func setting(_ state: AppState, _ key: String, to value: Bool) -> AppState {
        guard allKeys.contains(key) else { return state }
        var next = state
        var prefs = state.notifications ?? materializedDefault
        switch key {
        case "messages": prefs.messages = value
        case "learning": prefs.learning = value
        case "friendRequests": prefs.friendRequests = value
        case "sharedProgress": prefs.sharedProgress = value
        case "revision": prefs.revision = value
        case "corrections": prefs.corrections = value
        case "adminMessages": prefs.adminMessages = value
        case "messagePreview": prefs.messagePreview = value
        default: return state
        }
        next.notifications = prefs
        return next
    }

    // MARK: - `permissionExplained`, et ses deux écritures

    /// L'écriture de l'effet automatique — `App.tsx:117-121`.
    ///
    ///     if(current.notifications?.permissionExplained) return current;
    ///     touch({...current, notifications:{...current.notifications,
    ///       messages: current.notifications?.messages !== false,
    ///       learning: false, permissionExplained: true}})
    ///
    /// Deux traits que la carte n'a pas, et qui ne se devinent pas :
    ///
    ///   - le retour anticipé : le drapeau déjà posé rend l'état **inchangé**,
    ///     sans nouvel horodatage ;
    ///   - `learning` est forcé à `false`. Poser le drapeau ÉTEINT donc le rappel
    ///     quotidien, quel qu'il fût. C'est le comportement de l'original, et il
    ///     est silencieux.
    public static func markingPermissionExplained(_ state: AppState) -> AppState {
        if state.notifications?.permissionExplained == true { return state }
        var next = state
        var prefs = state.notifications ?? materializedDefault
        prefs.messages = state.notifications?.messages != false
        prefs.learning = false
        prefs.permissionExplained = true
        next.notifications = prefs
        return next
    }

    /// L'écriture de la carte — `App.tsx:305`, quand la permission est déjà
    /// accordée.
    ///
    ///     update(touch({...state, notifications:{...notificationPrefs,
    ///       permissionExplained:true}}))
    ///
    /// Elle ne force **pas** `learning`, et elle matérialise le défaut. Les deux
    /// écritures se gardent par le même retour anticipé, mais ne laissent pas le
    /// même document.
    public static func markingPermissionExplainedFromCard(_ state: AppState) -> AppState {
        if state.notifications?.permissionExplained == true { return state }
        var next = state
        var prefs = state.notifications ?? materializedDefault
        prefs.permissionExplained = true
        next.notifications = prefs
        return next
    }

    // MARK: - La permission système

    /// `Notifications.IosAuthorizationStatus` d'`expo-notifications`. Les
    /// valeurs numériques sont celles de `UNAuthorizationStatus` : le même ordre,
    /// donc la même lecture des deux côtés.
    public enum AuthorizationStatus: Int, Equatable, Sendable {
        case notDetermined = 0
        case denied = 1
        case authorized = 2
        case provisional = 3
        case ephemeral = 4
    }

    /// Ce que `getPermissionsAsync()` rend, réduit à ce que la décision lit.
    public struct PermissionResult: Equatable, Sendable {
        public var granted: Bool
        public var status: AuthorizationStatus

        public init(granted: Bool, status: AuthorizationStatus) {
            self.granted = granted
            self.status = status
        }
    }

    /// Le prédicat de la **carte** — `App.tsx:305` :
    /// `granted || status === PROVISIONAL`. Il ne retient **pas** `EPHEMERAL`.
    public static func cardAllows(_ result: PermissionResult) -> Bool {
        result.granted || result.status == .provisional
    }

    /// Le prédicat du **service** — `App.tsx:112` et `notifications.ts:61` :
    /// `granted || status === PROVISIONAL || status === EPHEMERAL`.
    ///
    /// La divergence avec `cardAllows` est réelle et mesurée : un statut
    /// `EPHEMERAL` — l'autorisation d'une seule journée, que iOS accorde aux
    /// demandes provisoires — laisse le service envoyer, et la carte afficher la
    /// porte d'autorisation.
    public static func serviceAllows(_ result: PermissionResult) -> Bool {
        result.granted || result.status == .provisional || result.status == .ephemeral
    }

    /// `prompt && !granted && status ∉ {PROVISIONAL, EPHEMERAL}` —
    /// `notifications.ts:59`. Autrement dit : on ne redemande pas quand iOS a
    /// déjà accordé quelque chose.
    public static func needsRequest(_ result: PermissionResult, prompt: Bool) -> Bool {
        guard prompt, !result.granted else { return false }
        return result.status != .provisional && result.status != .ephemeral
    }

    // MARK: - Le registre des identifiants déjà affichés

    /// `displayedMessages` — `notifications.ts:24,37`.
    ///
    /// Le plafond est **200**, et le dépassement vide l'ensemble **entier** :
    /// l'identifiant qui vient d'être ajouté part avec les autres. Ce n'est pas
    /// une erreur à corriger — c'est ce que l'original fait, et le reproduire est
    /// la seule façon d'afficher la même chose.
    public struct DisplayedLedger: Equatable, Sendable {
        public private(set) var ids: Set<String>
        public static let limit = 200

        public init(ids: Set<String> = []) {
            self.ids = ids
        }

        public func contains(_ id: String) -> Bool {
            ids.contains(id)
        }

        /// `if(uniqueId){add; if(size>200) clear()}` — l'ajout est ignoré pour un
        /// identifiant vide, et l'enregistrement a lieu **même quand la
        /// notification n'est pas affichée**.
        public mutating func record(_ id: String) {
            guard !id.isEmpty else { return }
            ids.insert(id)
            if ids.count > Self.limit { ids.removeAll() }
        }
    }

    // MARK: - La décision d'afficher

    /// La charge utile d'une notification, réduite aux champs que la décision lit.
    public struct Presentation: Equatable, Sendable {
        public var kind: Kind
        public var messageId: PayloadString
        public var linkId: PayloadString
        public var recitationId: PayloadString
        public var revision: PayloadString
        public var notificationId: PayloadString
        /// Le champ `challengeId`, lu par le seul routage du quiz.
        public var challengeId: PayloadString

        public init(
            kind: Kind,
            messageId: PayloadString = .missing,
            linkId: PayloadString = .missing,
            recitationId: PayloadString = .missing,
            revision: PayloadString = .missing,
            notificationId: PayloadString = .missing,
            challengeId: PayloadString = .missing
        ) {
            self.kind = kind
            self.messageId = messageId
            self.linkId = linkId
            self.recitationId = recitationId
            self.revision = revision
            self.notificationId = notificationId
            self.challengeId = challengeId
        }
    }

    /// L'état de l'application au moment de la décision — les variables de
    /// module de `notifications.ts` et l'état de l'application.
    public struct PresentationContext: Equatable, Sendable {
        /// `activeLinkId` : la conversation ouverte, ou `nil` — jamais
        /// « absente ». `setActiveConversation(linkId: string|null)`.
        public var activeLinkId: String?
        public var appIsActive: Bool
        public var recitationsVisible: Bool
        public var messagesEnabled: Bool
        public var progressEnabled: Bool
        public var correctionsEnabled: Bool
        public var adminMessagesEnabled: Bool

        public init(
            activeLinkId: String? = nil,
            appIsActive: Bool = false,
            recitationsVisible: Bool = false,
            messagesEnabled: Bool = true,
            progressEnabled: Bool = false,
            correctionsEnabled: Bool = true,
            adminMessagesEnabled: Bool = true
        ) {
            self.activeLinkId = activeLinkId
            self.appIsActive = appIsActive
            self.recitationsVisible = recitationsVisible
            self.messagesEnabled = messagesEnabled
            self.progressEnabled = progressEnabled
            self.correctionsEnabled = correctionsEnabled
            self.adminMessagesEnabled = adminMessagesEnabled
        }
    }

    /// `messageId || correctionId || adminId` — `notifications.ts:28-33`.
    ///
    /// `correctionId` vaut `"<recitationId>:<revision ?? ''>"` : le `?? ''` fait
    /// qu'une `revision` absente **ou** nulle donne la même chaîne. `messageId` et
    /// `notificationId` exigent une chaîne (`typeof === 'string'`) : un `null`
    /// explicite rend `''`.
    public static func uniqueId(for presentation: Presentation) -> String {
        if let messageId = presentation.messageId.string, !messageId.isEmpty {
            return messageId
        }
        if presentation.kind == .correction, let recitationId = presentation.recitationId.string {
            return recitationId + ":" + (presentation.revision.string ?? "")
        }
        if presentation.kind == .admin, let notificationId = presentation.notificationId.string {
            return notificationId
        }
        return ""
    }

    /// `sameChat` — `notifications.ts:30` :
    /// `isChat && data?.linkId === activeLinkId && currentState === 'active'`.
    ///
    /// L'égalité est **stricte**, et c'est le cœur du piège : `null === null`
    /// vaut `true`, `undefined === null` vaut `false`. Un message de groupe porte
    /// `linkId: null` ; au premier plan, sans conversation ouverte, la
    /// notification est donc supprimée.
    public static func sameChat(
        _ presentation: Presentation,
        context: PresentationContext
    ) -> Bool {
        let isChat = presentation.kind == .message || presentation.kind == .progress
        guard isChat, context.appIsActive else { return false }
        switch presentation.linkId {
        case .missing:
            return false
        case .null:
            return context.activeLinkId == nil
        case .string(let value):
            return value == context.activeLinkId
        }
    }

    /// `sameRecitations` — `notifications.ts:35` :
    /// `kind === correctionKind && recitationsVisible && active`.
    public static func sameRecitations(
        _ presentation: Presentation,
        context: PresentationContext
    ) -> Bool {
        presentation.kind == .correction && context.recitationsVisible && context.appIsActive
    }

    /// `show` — `notifications.ts:36`, les **sept** portes.
    ///
    ///     show = !(sameChat || sameRecitations || duplicate
    ///       || (message && !messagesEnabled)
    ///       || (progress && !progressEnabled)
    ///       || (correction && !correctionsEnabled)
    ///       || (admin && !adminMessagesEnabled))
    ///
    /// La fonction ne touche pas au registre : c'est `record` qui l'écrit, et il
    /// l'écrit **même quand `show` est faux**. Séparer les deux rend la décision
    /// pure et éprouvable.
    public static func shouldPresent(
        _ presentation: Presentation,
        context: PresentationContext,
        ledger: DisplayedLedger
    ) -> Bool {
        if sameChat(presentation, context: context) { return false }
        if sameRecitations(presentation, context: context) { return false }
        let id = uniqueId(for: presentation)
        if !id.isEmpty, ledger.contains(id) { return false }
        switch presentation.kind {
        case .message: return context.messagesEnabled
        case .progress: return context.progressEnabled
        case .correction: return context.correctionsEnabled
        case .admin: return context.adminMessagesEnabled
        default: return true
        }
    }

    // MARK: - Le routage d'un appui

    /// `notificationDestination` — `notifications.ts:159-169`.
    public enum Destination: Equatable, Sendable {
        case quiz(challengeId: String?)
        case program
        case reviews
        case recitation(recitationId: String)
        case conversation(linkId: String)
    }

    /// L'écran qu'un appui doit ouvrir, ou `nil`.
    ///
    /// L'ordre des tests est celui de l'original : un genre qui satisfait deux
    /// branches prend la première. `challengeId` et `linkId` passent le test
    /// `typeof === 'string'` : un `null` explicite ne produit **pas** de
    /// destination, alors qu'il pouvait supprimer l'affichage.
    public static func destination(for presentation: Presentation) -> Destination? {
        switch presentation.kind {
        case .quizDaily, .quizChallenge, .quizResult:
            return .quiz(challengeId: presentation.challengeId.string)
        case .admin, .learningReminder:
            return .program
        case .revisionReminder:
            return .reviews
        case .correction:
            guard let recitationId = presentation.recitationId.string else { return nil }
            return .recitation(recitationId: recitationId)
        case .message, .progress, .friendRequest, .friendAccepted:
            guard let linkId = presentation.linkId.string else { return nil }
            return .conversation(linkId: linkId)
        case .notificationTest:
            return nil
        }
    }

    // MARK: - Les rappels locaux

    /// Le rappel quotidien est posé à **19 h 00**, et l'original l'écrit en deux
    /// nombres (`notifications.ts:140`). Le libellé de la carte le dit aussi
    /// (« à 19 h ») : les trois doivent s'accorder, d'où une seule source.
    public static let reminderHour = 19
    public static let reminderMinute = 0

    /// La notification de test part **5 secondes** après l'appui
    /// (`notifications.ts:147`).
    public static let testDelaySeconds = 5

    /// Les deux genres que `cancelAutomaticReminders` annule
    /// (`notifications.ts:67`). Un rappel posé à la main — la notification de
    /// test — survit, et c'est voulu.
    public static let automaticReminderKinds: [Kind] = [.learningReminder, .revisionReminder]

    /// Un rappel programmé sur l'appareil, réduit à ce que les décisions lisent.
    ///
    /// `kind` est **facultatif** : une notification programmée par une version
    /// antérieure, ou par un autre outil, peut ne pas porter de genre. L'original
    /// le traite par `String(item.content.data?.kind)`, qui rend la chaîne
    /// `"undefined"` — jamais égale à l'un des deux genres, donc jamais annulée.
    public struct ScheduledReminder: Equatable, Sendable {
        public var id: String
        public var kind: Kind?

        public init(id: String, kind: Kind?) {
            self.id = id
            self.kind = kind
        }
    }

    /// `cancelAutomaticReminders` — `notifications.ts:64-72` : seuls les rappels
    /// dont le genre est l'un des deux automatiques sont annulés. Un genre
    /// inconnu — ou absent — n'est **pas** annulé.
    public static func automaticReminderIds(_ scheduled: [ScheduledReminder]) -> [String] {
        scheduled.compactMap { item in
            guard let kind = item.kind, automaticReminderKinds.contains(kind) else {
                return nil
            }
            return item.id
        }
    }

    /// `scheduledReminderCounts` — `notifications.ts:150-157`. Le compte porte
    /// sur **tous** les rappels programmés, pas seulement les automatiques.
    public static func reminderCounts(
        _ scheduled: [ScheduledReminder]
    ) -> (learning: Int, revision: Int) {
        (
            learning: scheduled.filter { $0.kind == .learningReminder }.count,
            revision: scheduled.filter { $0.kind == .revisionReminder }.count
        )
    }

    /// `syncLearningReminder` — `notifications.ts:139` :
    /// `if(!enabled || !await ensureNotificationPermission()) return`.
    ///
    /// La permission est lue par le prédicat du **service** — celui qui retient
    /// `EPHEMERAL` —, sans demande : programmer ne demande jamais rien.
    public static func shouldScheduleLearningReminder(
        enabled: Bool,
        permission: PermissionResult
    ) -> Bool {
        enabled && serviceAllows(permission)
    }

    /// `testLocalNotification` — `notifications.ts:146` : la demande est
    /// **explicite** (`prompt: true`), donc un statut `notDetermined` déclenche
    /// la demande système.
    public static func shouldScheduleTestNotification(
        permission: PermissionResult
    ) -> Bool {
        serviceAllows(permission)
    }

    // MARK: - Les drapeaux de présentation, dérivés de l'état

    /// Les quatre drapeaux de présentation — `App.tsx:169-172`.
    ///
    /// Deux formules, et ce n'est pas un détail de style :
    ///
    ///     messages      : prefs.messages      !== false
    ///     progress      : prefs.sharedProgress === true
    ///     corrections   : prefs.corrections    !== false
    ///     admin         : prefs.adminMessages  !== false
    ///
    /// `!== false` et `=== true` ne se confondent que sur une valeur **présente**.
    /// Sur une clé absente — ou nulle —, la première rend `true` et la seconde
    /// `false`. La progression partagée est donc la seule éteinte par défaut, ce
    /// qui est exactement le repli que la carte affiche pour son interrupteur.
    public static func presentationFlags(_ state: AppState) -> (
        messages: Bool,
        progress: Bool,
        corrections: Bool,
        admin: Bool
    ) {
        let prefs = state.notifications
        return (
            messages: prefs?.messages != false,
            progress: prefs?.sharedProgress == true,
            corrections: prefs?.corrections != false,
            admin: prefs?.adminMessages != false
        )
    }

    /// `App.tsx:173` :
    /// `if(!account || !state.onboardingDone) return; syncLearningReminder(state.notifications?.learning === true)`.
    ///
    /// Le garde ne porte **que** sur le compte et le questionnaire : il ne dépend
    /// pas de la valeur. C'est essentiel — éteindre l'interrupteur doit
    /// **annuler** le rappel, donc appeler la synchronisation avec `false`. Un
    /// garde qui exigerait `enabled` laisserait le rappel en place.
    ///
    /// Conséquence à connaître : sans compte connecté, éteindre l'interrupteur
    /// n'annule **rien**. C'est le comportement de l'original.
    public static func canSyncLearningReminder(
        account: Bool,
        onboardingDone: Bool
    ) -> Bool {
        account && onboardingDone
    }

    /// La préférence **telle qu'elle est miroitée côté serveur** —
    /// `App.tsx:177`, table `notification_preferences`.
    ///
    /// Deux traits que la carte n'a pas :
    ///
    ///   - `revision` est écrite **`false` en dur** : la colonne
    ///     `revision_reminders_enabled` reçoit toujours `false`, quel que soit
    ///     l'état local. Le rappel de révision n'est donc jamais demandé au
    ///     serveur ;
    ///   - `messagePreview` et `learning` n'y sont pas, alors que la carte les
    ///     propose : ils restent locaux.
    ///
    /// Ce portage **n'écrit pas** cette table — elle demanderait une vérification
    /// de son existence côté serveur, et la charte du projet interdit d'ajouter
    /// une migration sans le demander. La dérivation est portée et vérifiée pour
    /// que le contrat reste visible, et pour qu'un futur écran ne l'invente pas.
    public static func mirroredPreferences(_ state: AppState) -> (
        messages: Bool,
        friendRequests: Bool,
        sharedProgress: Bool,
        revision: Bool,
        corrections: Bool,
        adminMessages: Bool,
        messagePreview: Bool
    ) {
        let prefs = state.notifications
        return (
            messages: prefs?.messages != false,
            friendRequests: prefs?.friendRequests != false,
            sharedProgress: prefs?.sharedProgress == true,
            revision: false,
            corrections: prefs?.corrections != false,
            adminMessages: prefs?.adminMessages != false,
            messagePreview: prefs?.messagePreview != false
        )
    }

    /// `App.tsx:178` : l'enregistrement du jeton push est tenté quand le drapeau
    /// de permission est posé **et** qu'au moins une des cinq préférences
    /// « poussables » est active.
    ///
    /// `learning` et `messagePreview` n'en font pas partie : la première est un
    /// rappel **local**, la seconde ne change que l'**affichage**.
    public static func shouldRegisterPushDevice(_ state: AppState) -> Bool {
        guard state.notifications?.permissionExplained == true else { return false }
        let mirrored = mirroredPreferences(state)
        return mirrored.messages
            || mirrored.friendRequests
            || mirrored.sharedProgress
            || mirrored.corrections
            || mirrored.adminMessages
    }

    public static let reminderTitle = "Ton programme du Coran"
    public static let reminderBody = "Retrouve ton passage du jour et prends un moment pour apprendre."
    public static let testTitle = "Test des notifications"
    public static let testBody = "Les notifications sont autorisées sur ce téléphone."

    // MARK: - Les textes de la carte

    public static let cardTitle = "Notifications"
    public static let permissionDetail = "Les notifications t’avertissent des messages, invitations, corrections et rappels personnels envoyés par le professeur."
    public static let permissionAction = "Autoriser les notifications sur ce téléphone"
    public static let cardFooter = "Le rappel quotidien est facultatif et programmé sur ce téléphone. Le professeur peut aussi envoyer des notifications personnalisées."
    public static let testAction = "Tester une notification sur ce téléphone"
    public static let countsAction = "Vérifier les rappels programmés"
    public static let diagnosticAction = "Vérifier le jeton push"

    public static let grantedNotice = "Notifications autorisées."
    public static let deniedNotice = "Autorisation refusée. Tu peux la modifier dans les réglages du téléphone."
    public static let unavailableNotice = "Les notifications sont indisponibles sur ce téléphone."
    public static let testScheduledNotice = "Notification locale de test programmée dans 5 secondes."

    /// Le message du refus du bouton de test — `notifications.ts:146` :
    /// `throw new Error('Autorise les notifications dans les réglages du
    /// téléphone.')`. Il est distinct de `deniedNotice`, qui est l'avis de la
    /// porte de permission : le refus d'un test n'est pas le refus de la porte.
    public static let testPermissionNotice = "Autorise les notifications dans les réglages du téléphone."

    /// `${counts.learning} ancien(s) rappel(s) quotidien(s) et ${counts.revision}
    /// rappel(s) de révision programmés sur ce téléphone.` (`App.tsx:346`).
    ///
    /// Les accords entre parenthèses sont ceux de l'original : les recopier tels
    /// quels est la seule façon d'afficher le même texte.
    public static func countsNotice(learning: Int, revision: Int) -> String {
        "\(learning) ancien(s) rappel(s) quotidien(s) et \(revision) rappel(s) de révision programmés sur ce téléphone."
    }

    public static func testFailureNotice(_ message: String) -> String {
        "Test local impossible : \(message)"
    }

    public static func countsFailureNotice(_ message: String) -> String {
        "Vérification impossible : \(message)"
    }

    public static func diagnosticFailureNotice(_ message: String) -> String {
        "Push indisponible : \(message)"
    }
}

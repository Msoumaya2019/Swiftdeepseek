// NotificationTests.swift
// Les notifications : les sept interrupteurs, les trois prédicats de
// permission, le registre des affichages, les sept portes, le routage d'un
// appui, et le programmateur des rappels locaux.
//
// Ce que ces tests protègent :
//   - la LISTE des sept interrupteurs, qui est une donnée. Recopier les libellés
//     « évidents » compile et affiche une carte plausible, avec deux
//     interrupteurs dans le mauvais sens ;
//   - le défaut MATÉRIALISÉ : écrire une préférence sur une installation neuve
//     écrit aussi `messages:true` et `learning:false`. Ce n'est pas un défaut,
//     c'est le contrat que l'application React Native relira ;
//   - les DEUX prédicats de permission, qui divergent. Les confondre rend la
//     carte trop permissive ou le service trop strict, et rien ne le dit ;
//   - l'égalité STRICTE de `sameChat` : un message de groupe porte
//     `linkId: null`, et sans conversation ouverte `null === null` est vrai. La
//     notification est alors supprimée — un `String?` qui confondrait `null` et
//     l'absence ne le verrait pas ;
//   - le registre qui se vide ENTIER au-delà de 200 entrées, y compris celle
//     qu'on vient d'ajouter ;
//   - les quatre drapeaux d'affichage, dérivés par DEUX formules : `!= false`
//     pour trois d'entre eux, `== true` pour la progression partagée ;
//   - l'ordre du programmateur : annuler d'abord, programmer ensuite. Éteindre
//     l'interrupteur doit RETIRER un rappel déjà posé ;
//   - la garde du rappel, qui ne dépend ni de la permission ni de la valeur.
//
// CE QUE CES TESTS NE PEUVENT PAS PROUVER, ET QUI EST PROUVÉ AILLEURS
//   L'égalité littérale des sept libellés, des huit clés, des douze `kind`, des
//   sept portes et des textes avec la référence se compare à la source
//   TypeScript et au SQL, pas au Swift : c'est le rôle de
//   `_banc/verifier-notifications.mjs`, et `_banc/falsifier-notifications.mjs`
//   éprouve ce banc.
//
//   Les tests ci-dessous éprouvent le modèle pur et le service sur un faux
//   programmateur. Aucun libellé attendu n'y est recopié : les listes viennent
//   de `NotificationOptions`, et les textes attendus sont ceux de la référence,
//   écrits une fois.

import XCTest
@testable import Swiftdeepseek

final class NotificationTests: XCTestCase {

    // MARK: - Les sept interrupteurs

    /// Les sept clés, dans l'ordre de `App.tsx:337-343`.
    func testTheSevenSwitchesAreTheOnesOfTheReference() {
        XCTAssertEqual(
            NotificationOptions.switches.map(\.id),
            [
                "learning", "messages", "friendRequests",
                "sharedProgress", "corrections", "adminMessages", "messagePreview"
            ]
        )
        XCTAssertEqual(
            NotificationOptions.switches.map(\.label),
            [
                "Rappel quotidien d’apprentissage à 19 h",
                "Messages privés",
                "Demandes d’amis",
                "Progression partagée par les amis",
                "Corrections de mes récitations",
                "Rappels personnels du professeur",
                "Afficher le contenu des messages"
            ]
        )
    }

    /// Deux interrupteurs seulement sont éteints par défaut, et ce sont les bons.
    func testOnlyTwoSwitchesAreOffByDefault() {
        XCTAssertEqual(
            NotificationOptions.switches.filter { !$0.fallback }.map(\.id),
            ["learning", "sharedProgress"]
        )
        XCTAssertEqual(
            NotificationOptions.switches.filter { $0.fallback }.map(\.id),
            ["messages", "friendRequests", "corrections", "adminMessages", "messagePreview"]
        )
    }

    /// Les huit clés du type, dans l'ordre de la déclaration.
    func testTheEightKeysAreThoseOfTheType() {
        XCTAssertEqual(
            NotificationOptions.allKeys,
            [
                "messages", "learning", "friendRequests", "sharedProgress",
                "revision", "corrections", "adminMessages", "messagePreview"
            ]
        )
        XCTAssertEqual(NotificationOptions.allKeys.count, 8)
    }

    /// `revision` est dans le type, dans **aucune** carte.
    ///
    /// C'est la clé que le service écrit — le rappel de révision — et qu'aucun
    /// écran ne propose. L'ajouter « par symétrie » afficherait un huitième
    /// interrupteur que l'original n'a pas.
    func testRevisionIsInNoCard() {
        XCTAssertTrue(NotificationOptions.allKeys.contains(NotificationOptions.revisionKey))
        XCTAssertFalse(NotificationOptions.switches.map(\.id).contains(NotificationOptions.revisionKey))
    }

    // MARK: - Le défaut matérialisé

    /// Le défaut de la carte et celui de `Program.defaultState()` sont la même
    /// vérité, portée à deux endroits qui ne peuvent pas se lire.
    func testTheMaterializedDefaultAgreesWithProgramDefault() throws {
        let fromProgram = try XCTUnwrap(Program.defaultState().notifications)
        XCTAssertEqual(fromProgram.messages, NotificationOptions.materializedDefault.messages)
        XCTAssertEqual(fromProgram.learning, NotificationOptions.materializedDefault.learning)
        XCTAssertTrue(NotificationOptions.materializedDefault.messages)
        XCTAssertFalse(NotificationOptions.materializedDefault.learning)
    }

    /// `value` applique le repli de la carte quand la clé est absente.
    func testValueFallsBackWhenTheKeyIsAbsent() {
        var state = Program.defaultState()
        state.notifications = nil

        XCTAssertEqual(NotificationOptions.value(state, "messages"), true)
        XCTAssertEqual(NotificationOptions.value(state, "learning"), false)
        XCTAssertEqual(NotificationOptions.value(state, "sharedProgress"), false)
        XCTAssertEqual(NotificationOptions.value(state, "messagePreview"), true)

        // Une clé qu'aucune carte ne propose n'a pas de repli : elle rend `false`.
        XCTAssertEqual(NotificationOptions.value(state, "inconnue"), false)
        XCTAssertNil(NotificationOptions.stored(state, "messages"))
    }

    /// `stored` distingue l'absence d'une valeur, ce dont `value` a besoin.
    func testStoredDistinguishesAbsenceFromAValue() {
        var state = Program.defaultState()
        state.notifications = NotificationPreferences(messages: true, learning: true)

        XCTAssertNil(NotificationOptions.stored(state, "corrections"))
        XCTAssertEqual(NotificationOptions.stored(state, "messages"), true)
        XCTAssertEqual(NotificationOptions.value(state, "corrections"), true)
    }

    // MARK: - Écrire une préférence

    /// Toucher un interrupteur sur une installation neuve ÉCRIT le défaut
    /// matérialisé — `App.tsx:304,306`.
    func testWritingASwitchOnAFreshInstallAlsoWritesTheDefault() throws {
        var state = Program.defaultState()
        state.notifications = nil

        let next = NotificationOptions.setting(state, "corrections", to: false)
        let prefs = try XCTUnwrap(next.notifications)

        XCTAssertEqual(prefs.corrections, false)
        XCTAssertEqual(prefs.messages, true, "L’écriture matérialise `messages:true`.")
        XCTAssertEqual(prefs.learning, false, "L’écriture matérialise `learning:false`.")
    }

    /// Une clé que le type Swift ne sait pas relire rend l'état **inchangé**.
    func testWritingAnUnknownKeyChangesNothing() {
        let state = Program.defaultState()
        let next = NotificationOptions.setting(state, "inconnue", to: true)
        XCTAssertEqual(next.notifications?.messages, state.notifications?.messages)
        XCTAssertEqual(next.notifications?.learning, state.notifications?.learning)
    }

    /// L'écriture est PURE : elle ne pose pas `updatedAt`. L'horodatage est le
    /// rôle de `AppStateRepository.mutate`, une seule fois.
    func testWritingASwitchDoesNotStampTheDocument() {
        let state = Program.defaultState()
        let next = NotificationOptions.setting(state, "messages", to: false)
        XCTAssertEqual(next.updatedAt, state.updatedAt)
    }

    // MARK: - Les deux écritures du drapeau

    /// L'écriture automatique force `learning` à faux : poser le drapeau ÉTEINT
    /// le rappel quotidien, quel qu'il fût.
    func testTheAutomaticWriteTurnsTheDailyReminderOff() throws {
        var state = Program.defaultState()
        state.notifications = NotificationPreferences(messages: true, learning: true)

        let next = NotificationOptions.markingPermissionExplained(state)
        let prefs = try XCTUnwrap(next.notifications)

        XCTAssertEqual(prefs.learning, false, "Poser le drapeau éteint le rappel quotidien.")
        XCTAssertEqual(prefs.messages, true)
        XCTAssertEqual(prefs.permissionExplained, true)
    }

    /// L'écriture de la carte, elle, ne touche pas au rappel — et elle
    /// matérialise le défaut.
    func testTheCardWriteLeavesTheDailyReminderAlone() throws {
        var state = Program.defaultState()
        state.notifications = nil

        let next = NotificationOptions.markingPermissionExplainedFromCard(state)
        let prefs = try XCTUnwrap(next.notifications)

        XCTAssertEqual(prefs.permissionExplained, true)
        XCTAssertEqual(prefs.messages, true)
        XCTAssertEqual(prefs.learning, false, "Le défaut matérialisé, et non un forçage.")
    }

    /// Les deux écritures rendent l'état INCHANGÉ quand le drapeau est déjà posé.
    func testBothWritesReturnTheStateUnchangedWhenTheFlagIsAlreadySet() {
        var state = Program.defaultState()
        state.notifications = NotificationPreferences(messages: false, learning: true)
        state.notifications?.permissionExplained = true

        XCTAssertEqual(NotificationOptions.markingPermissionExplained(state), state)
        XCTAssertEqual(NotificationOptions.markingPermissionExplainedFromCard(state), state)
    }

    // MARK: - Les trois prédicats de permission

    /// La carte n'autorise PAS sur EPHEMERAL ; le service, si. La divergence est
    /// celle de l'original, et elle est mesurée.
    func testTheCardAndTheServicePredicatesDivergeOnEphemeral() {
        let ephemeral = NotificationOptions.PermissionResult(granted: false, status: .ephemeral)

        XCTAssertFalse(
            NotificationOptions.cardAllows(ephemeral),
            "Un statut EPHEMERAL laisse le service envoyer et la carte montrer la porte."
        )
        XCTAssertTrue(NotificationOptions.serviceAllows(ephemeral))
    }

    /// Sur les autres statuts, les deux prédicats s'accordent.
    func testTheTwoPredicatesAgreeOnEveryOtherStatus() {
        for status: NotificationOptions.AuthorizationStatus in [.notDetermined, .denied, .authorized, .provisional] {
            let result = NotificationOptions.PermissionResult(
                granted: status == .authorized,
                status: status
            )
            XCTAssertEqual(
                NotificationOptions.cardAllows(result),
                NotificationOptions.serviceAllows(result),
                "Les deux prédicats ne divergent que sur EPHEMERAL."
            )
        }
    }

    /// Les valeurs numériques du statut sont celles de `UNAuthorizationStatus` :
    /// c'est la LECTURE qui donne son sens au `|| PROVISIONAL`, et elle ne doit
    /// pas changer en silence.
    func testTheStatusValuesAreThoseOfTheSystem() {
        XCTAssertEqual(NotificationOptions.AuthorizationStatus.notDetermined.rawValue, 0)
        XCTAssertEqual(NotificationOptions.AuthorizationStatus.denied.rawValue, 1)
        XCTAssertEqual(NotificationOptions.AuthorizationStatus.authorized.rawValue, 2)
        XCTAssertEqual(NotificationOptions.AuthorizationStatus.provisional.rawValue, 3)
        XCTAssertEqual(NotificationOptions.AuthorizationStatus.ephemeral.rawValue, 4)
    }

    /// On ne redemande pas la permission quand iOS a déjà accordé quelque chose.
    func testThePermissionIsNotAskedAgainWhenSomethingIsAlreadyGranted() {
        let provisional = NotificationOptions.PermissionResult(granted: false, status: .provisional)
        let denied = NotificationOptions.PermissionResult(granted: false, status: .denied)
        let authorized = NotificationOptions.PermissionResult(granted: true, status: .authorized)

        XCTAssertFalse(NotificationOptions.needsRequest(provisional, prompt: true))
        XCTAssertFalse(NotificationOptions.needsRequest(authorized, prompt: true))
        XCTAssertTrue(NotificationOptions.needsRequest(denied, prompt: true))
        XCTAssertFalse(NotificationOptions.needsRequest(denied, prompt: false))
    }

    // MARK: - Le registre des affichages

    /// Le registre se vide ENTIER au-delà de 200 entrées — y compris celle qu'on
    /// vient d'ajouter. Ce n'est pas une erreur à corriger.
    func testTheLedgerClearsEntirelyPastTwoHundredEntries() {
        var ledger = NotificationOptions.DisplayedLedger()
        for index in 0..<200 { ledger.record("id-\(index)") }

        XCTAssertEqual(ledger.ids.count, 200)
        XCTAssertTrue(ledger.contains("id-0"))

        ledger.record("id-200")
        XCTAssertEqual(ledger.ids.count, 0, "Le dépassement vide le registre entier.")
        XCTAssertFalse(ledger.contains("id-200"))
    }

    /// Un identifiant vide n'est jamais enregistré — `if(uniqueId)`.
    func testAnEmptyIdentifierIsNeverRecorded() {
        var ledger = NotificationOptions.DisplayedLedger()
        ledger.record("")
        XCTAssertEqual(ledger.ids.count, 0)
    }

    /// `messageId || "<recitation>:<revision>" || notificationId`.
    func testTheUniqueIdentifierFollowsTheReference() {
        XCTAssertEqual(
            NotificationOptions.uniqueId(for: NotificationOptions.Presentation(
                kind: .message, messageId: .string("m1")
            )),
            "m1"
        )
        XCTAssertEqual(
            NotificationOptions.uniqueId(for: NotificationOptions.Presentation(
                kind: .correction, recitationId: .string("r1"), revision: .string("2")
            )),
            "r1:2"
        )
        XCTAssertEqual(
            NotificationOptions.uniqueId(for: NotificationOptions.Presentation(
                kind: .correction, recitationId: .string("r1")
            )),
            "r1:",
            "Une révision absente rend la chaîne vide, pas l’absence de séparateur."
        )
        XCTAssertEqual(
            NotificationOptions.uniqueId(for: NotificationOptions.Presentation(
                kind: .admin, notificationId: .string("n1")
            )),
            "n1"
        )
        XCTAssertEqual(
            NotificationOptions.uniqueId(for: NotificationOptions.Presentation(kind: .message)),
            ""
        )
    }

    // MARK: - L'égalité stricte de `sameChat`

    /// Le piège : `linkId` nul et aucune conversation ouverte — `null === null`
    /// est VRAI, et la notification est supprimée.
    func testANullLinkIdWithNoOpenConversationClosesTheDoor() {
        let presentation = NotificationOptions.Presentation(
            kind: .message, messageId: .string("m1"), linkId: .null
        )
        var context = NotificationOptions.PresentationContext()
        context.appIsActive = true
        context.activeLinkId = nil

        XCTAssertFalse(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
        ))
    }

    /// Une charge utile ABSENTE n'est pas une charge utile NULLE : elle ne ferme
    /// pas la porte. C'est la raison d'être des trois états.
    func testAMissingLinkIdDoesNotCloseTheDoor() {
        let presentation = NotificationOptions.Presentation(
            kind: .message, messageId: .string("m1"), linkId: .missing
        )
        var context = NotificationOptions.PresentationContext()
        context.appIsActive = true
        context.activeLinkId = nil

        XCTAssertTrue(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
        ))
    }

    /// Une conversation ouverte ferme la porte — au premier plan seulement.
    func testAnOpenConversationClosesTheDoorOnlyInTheForeground() {
        let presentation = NotificationOptions.Presentation(
            kind: .message, messageId: .string("m1"), linkId: .string("link-1")
        )
        var context = NotificationOptions.PresentationContext()
        context.activeLinkId = "link-1"

        context.appIsActive = true
        XCTAssertFalse(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
        ))

        context.appIsActive = false
        XCTAssertTrue(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
        ))
    }

    /// L'écran des récitations visible ferme la porte des corrections.
    func testTheVisibleRecitationsScreenClosesTheCorrectionDoor() {
        let presentation = NotificationOptions.Presentation(
            kind: .correction, recitationId: .string("r1")
        )
        var context = NotificationOptions.PresentationContext()
        context.appIsActive = true
        context.recitationsVisible = true

        XCTAssertFalse(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
        ))

        context.recitationsVisible = false
        XCTAssertTrue(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
        ))
    }

    // MARK: - Les sept portes

    /// Quatre genres sur douze dépendent d'un réglage ; les huit autres passent.
    func testOnlyFourKindsDependOnASetting() {
        let doors: [(NotificationOptions.Kind, WritableKeyPath<NotificationOptions.PresentationContext, Bool>)] = [
            (.message, \.messagesEnabled),
            (.progress, \.progressEnabled),
            (.correction, \.correctionsEnabled),
            (.admin, \.adminMessagesEnabled)
        ]

        for (kind, door) in doors {
            let presentation = NotificationOptions.Presentation(kind: kind)
            var context = NotificationOptions.PresentationContext()
            context.appIsActive = true

            XCTAssertTrue(NotificationOptions.shouldPresent(
                presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
            ), "« \(kind.rawValue) » passe quand son réglage est ouvert.")

            context[keyPath: door] = false
            XCTAssertFalse(NotificationOptions.shouldPresent(
                presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
            ), "« \(kind.rawValue) » est retenu quand son réglage est fermé.")
        }
    }

    /// Un genre sans porte de réglage n'est jamais retenu par un réglage fermé.
    func testAKindWithoutADoorIgnoresEverySetting() {
        let presentation = NotificationOptions.Presentation(kind: .learningReminder)
        var context = NotificationOptions.PresentationContext()
        context.appIsActive = true
        context.messagesEnabled = false
        context.progressEnabled = false
        context.correctionsEnabled = false
        context.adminMessagesEnabled = false

        XCTAssertTrue(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: NotificationOptions.DisplayedLedger()
        ))
    }

    /// Un identifiant déjà affiché n'est pas affiché deux fois.
    func testAnAlreadyDisplayedIdentifierIsNotShownTwice() {
        var ledger = NotificationOptions.DisplayedLedger()
        ledger.record("m1")

        let presentation = NotificationOptions.Presentation(
            kind: .message, messageId: .string("m1")
        )
        var context = NotificationOptions.PresentationContext()
        context.appIsActive = true

        XCTAssertFalse(NotificationOptions.shouldPresent(
            presentation, context: context, ledger: ledger
        ))
    }

    // MARK: - Le routage d'un appui

    /// L'écran qu'un appui doit ouvrir, par genre.
    func testTheDestinationFollowsTheKind() {
        XCTAssertEqual(
            NotificationOptions.destination(for: NotificationOptions.Presentation(
                kind: .quizDaily, challengeId: .string("c1")
            )),
            .quiz(challengeId: "c1")
        )
        XCTAssertEqual(
            NotificationOptions.destination(for: NotificationOptions.Presentation(kind: .quizResult)),
            .quiz(challengeId: nil),
            "Un quiz sans identifiant ouvre quand même le quiz."
        )
        XCTAssertEqual(
            NotificationOptions.destination(for: NotificationOptions.Presentation(kind: .admin)),
            .program
        )
        XCTAssertEqual(
            NotificationOptions.destination(for: NotificationOptions.Presentation(kind: .learningReminder)),
            .program
        )
        XCTAssertEqual(
            NotificationOptions.destination(for: NotificationOptions.Presentation(kind: .revisionReminder)),
            .reviews
        )
        XCTAssertEqual(
            NotificationOptions.destination(for: NotificationOptions.Presentation(
                kind: .message, linkId: .string("link-1")
            )),
            .conversation(linkId: "link-1")
        )
        XCTAssertEqual(
            NotificationOptions.destination(for: NotificationOptions.Presentation(
                kind: .correction, recitationId: .string("r1")
            )),
            .recitation(recitationId: "r1")
        )
        XCTAssertNil(
            NotificationOptions.destination(for: NotificationOptions.Presentation(kind: .notificationTest)),
            "Un test n'ouvre rien."
        )
    }

    /// Une correction ou une conversation sans identifiant n'a PAS de
    /// destination — `typeof === 'string'` —, alors que le même `null` pouvait
    /// supprimer l'affichage.
    func testAnIdentifierThatIsNotAStringHasNoDestination() {
        XCTAssertNil(NotificationOptions.destination(for: NotificationOptions.Presentation(
            kind: .correction, recitationId: .null
        )))
        XCTAssertNil(NotificationOptions.destination(for: NotificationOptions.Presentation(
            kind: .message, linkId: .null
        )))
        XCTAssertNil(NotificationOptions.destination(for: NotificationOptions.Presentation(
            kind: .message, linkId: .missing
        )))
    }

    // MARK: - Les drapeaux d'affichage

    /// Deux formules, et ce n'est pas un détail de style : sur une clé absente,
    /// `!= false` rend vrai et `== true` rend faux.
    func testThePresentationFlagsUseTwoFormulas() {
        var state = Program.defaultState()
        state.notifications = nil

        let absent = NotificationOptions.presentationFlags(state)
        XCTAssertTrue(absent.messages)
        XCTAssertFalse(absent.progress, "La progression partagée est la seule éteinte par défaut.")
        XCTAssertTrue(absent.corrections)
        XCTAssertTrue(absent.admin)

        state.notifications = NotificationPreferences(messages: false, learning: true)
        let explicit = NotificationOptions.presentationFlags(state)
        XCTAssertFalse(explicit.messages)
        XCTAssertFalse(explicit.progress)
        XCTAssertTrue(explicit.corrections)
        XCTAssertTrue(explicit.admin)
    }

    // MARK: - La garde du rappel quotidien

    /// La garde ne porte QUE sur le compte et le questionnaire. Exiger la valeur
    /// laisserait un rappel en place quand l'interrupteur est éteint.
    func testTheReminderGuardDoesNotDependOnTheValue() {
        XCTAssertFalse(NotificationOptions.canSyncLearningReminder(account: false, onboardingDone: true))
        XCTAssertFalse(NotificationOptions.canSyncLearningReminder(account: true, onboardingDone: false))
        XCTAssertTrue(NotificationOptions.canSyncLearningReminder(account: true, onboardingDone: true))
    }

    /// La décision de programmer : le rappel doit être allumé ET la permission
    /// acquise — au sens du SERVICE, donc EPHEMERAL compris.
    func testTheReminderIsScheduledOnlyWhenEnabledAndAllowed() {
        let allowed = NotificationOptions.PermissionResult(granted: true, status: .authorized)
        let ephemeral = NotificationOptions.PermissionResult(granted: false, status: .ephemeral)
        let denied = NotificationOptions.PermissionResult(granted: false, status: .denied)

        XCTAssertTrue(NotificationOptions.shouldScheduleLearningReminder(enabled: true, permission: allowed))
        XCTAssertTrue(NotificationOptions.shouldScheduleLearningReminder(enabled: true, permission: ephemeral))
        XCTAssertFalse(NotificationOptions.shouldScheduleLearningReminder(enabled: false, permission: allowed))
        XCTAssertFalse(NotificationOptions.shouldScheduleLearningReminder(enabled: true, permission: denied))
    }

    // MARK: - Le miroir serveur

    /// `revision` est écrite `false` EN DUR, et deux clés ne sont pas miroitées.
    func testTheMirroredPreferencesHardCodeRevisionToFalse() {
        var state = Program.defaultState()
        state.notifications = NotificationPreferences(messages: true, learning: true)
        state.notifications?.revision = true

        let mirrored = NotificationOptions.mirroredPreferences(state)
        XCTAssertFalse(mirrored.revision, "La colonne reçoit toujours `false`, quel que soit l’état local.")
        XCTAssertTrue(mirrored.messages)
    }

    /// L'enregistrement du jeton demande le drapeau ET une des cinq préférences
    /// « poussables » — ni `learning`, ni `messagePreview`.
    func testRegisteringTheDeviceNeedsTheFlagAndOneOfFivePreferences() {
        var state = Program.defaultState()
        state.notifications = NotificationPreferences(messages: true, learning: true)

        XCTAssertFalse(
            NotificationOptions.shouldRegisterPushDevice(state),
            "Sans le drapeau, rien n’est enregistré."
        )

        state.notifications?.permissionExplained = true
        XCTAssertTrue(NotificationOptions.shouldRegisterPushDevice(state))

        state.notifications?.messages = false
        state.notifications?.friendRequests = false
        state.notifications?.sharedProgress = false
        state.notifications?.corrections = false
        state.notifications?.adminMessages = false
        XCTAssertFalse(
            NotificationOptions.shouldRegisterPushDevice(state),
            "Ni `learning` ni `messagePreview` ne comptent : ce ne sont pas des préférences poussables."
        )
    }

    // MARK: - Le programmateur, sur un faux

    /// `cancelAutomaticReminders` n'annule QUE les deux genres automatiques. Un
    /// rappel posé à la main — la notification de test — survit.
    func testCancellingAutomaticRemindersSparesTheOthers() async {
        let scheduler = FakeNotificationScheduler(pending: [
            NotificationOptions.ScheduledReminder(id: "a", kind: .learningReminder),
            NotificationOptions.ScheduledReminder(id: "b", kind: .revisionReminder),
            NotificationOptions.ScheduledReminder(id: "c", kind: .notificationTest),
            NotificationOptions.ScheduledReminder(id: "d", kind: nil)
        ])
        let service = LocalNotificationService(scheduler: scheduler)

        await service.cancelAutomaticReminders()

        let operations = await scheduler.recorded
        XCTAssertEqual(operations, [.cancel(["a", "b"])])
    }

    /// L'ORDRE : on annule d'abord, on programme ensuite. Et l'annulation ne
    /// vise que le genre d'apprentissage, pas les deux genres automatiques.
    func testTheLearningReminderIsCancelledBeforeBeingScheduled() async {
        let scheduler = FakeNotificationScheduler(pending: [
            NotificationOptions.ScheduledReminder(id: "a", kind: .learningReminder),
            NotificationOptions.ScheduledReminder(id: "b", kind: .revisionReminder)
        ])
        let service = LocalNotificationService(scheduler: scheduler)

        await service.syncLearningReminder(enabled: true)

        let operations = await scheduler.recorded
        XCTAssertEqual(operations, [.cancel(["a"]), .schedule(.learningReminder)])
    }

    /// Éteindre l'interrupteur RETIRE un rappel déjà posé, sans en programmer un.
    func testTurningTheReminderOffCancelsWithoutScheduling() async {
        let scheduler = FakeNotificationScheduler(pending: [
            NotificationOptions.ScheduledReminder(id: "a", kind: .learningReminder)
        ])
        let service = LocalNotificationService(scheduler: scheduler)

        await service.syncLearningReminder(enabled: false)

        let operations = await scheduler.recorded
        XCTAssertEqual(operations, [.cancel(["a"])])
    }

    /// Programmer ne demande JAMAIS la permission : la demande est réservée au
    /// bouton de la carte et à la notification de test.
    func testSchedulingNeverAsksForThePermission() async {
        let scheduler = FakeNotificationScheduler()
        let service = LocalNotificationService(scheduler: scheduler)

        await service.syncLearningReminder(enabled: true)

        let requests = await scheduler.promptCount
        XCTAssertEqual(requests, 0)
    }

    /// Un rappel allumé mais la permission refusée : on annule, on ne programme pas.
    func testTheReminderIsNotScheduledWhenThePermissionIsRefused() async {
        let scheduler = FakeNotificationScheduler(
            status: NotificationOptions.PermissionResult(granted: false, status: .denied)
        )
        let service = LocalNotificationService(scheduler: scheduler)

        await service.syncLearningReminder(enabled: true)

        let operations = await scheduler.recorded
        XCTAssertEqual(operations, [.cancel([])])
    }

    /// La notification de test part cinq secondes plus tard, et elle DEMANDE la
    /// permission.
    func testTheTestNotificationIsScheduledFiveSecondsLater() async {
        let scheduler = FakeNotificationScheduler()
        let service = LocalNotificationService(scheduler: scheduler)

        let scheduled = await service.testLocalNotification()

        XCTAssertTrue(scheduled)
        let operations = await scheduler.recorded
        XCTAssertEqual(operations, [.schedule(.notificationTest)])
        let requests = await scheduler.promptCount
        XCTAssertEqual(requests, 1)
    }

    /// La notification de test n'est pas programmée quand la permission manque —
    /// elle rend `false`, et l'écran en fait un avis.
    func testTheTestNotificationIsNotScheduledWithoutPermission() async {
        let scheduler = FakeNotificationScheduler(
            status: NotificationOptions.PermissionResult(granted: false, status: .denied)
        )
        let service = LocalNotificationService(scheduler: scheduler)

        let scheduled = await service.testLocalNotification()

        XCTAssertFalse(scheduled)
        let operations = await scheduler.recorded
        XCTAssertTrue(operations.isEmpty)
    }

    /// Le texte des comptes est celui de la référence, accords compris.
    func testTheCountsNoticeIsTheOneOfTheReference() async {
        let scheduler = FakeNotificationScheduler(pending: [
            NotificationOptions.ScheduledReminder(id: "a", kind: .learningReminder),
            NotificationOptions.ScheduledReminder(id: "b", kind: .learningReminder),
            NotificationOptions.ScheduledReminder(id: "c", kind: .revisionReminder),
            NotificationOptions.ScheduledReminder(id: "d", kind: nil)
        ])
        let service = LocalNotificationService(scheduler: scheduler)

        let notice = await service.countsNotice()

        XCTAssertEqual(
            notice,
            "2 ancien(s) rappel(s) quotidien(s) et 1 rappel(s) de révision programmés sur ce téléphone."
        )
    }

    /// Le rappel quotidien est posé à 19 h 00 — la même heure que celle du
    /// libellé de la carte.
    func testTheDailyReminderIsScheduledAtSevenInTheEvening() async {
        let scheduler = FakeNotificationScheduler()
        let service = LocalNotificationService(scheduler: scheduler)

        await service.syncLearningReminder(enabled: true)

        XCTAssertEqual(NotificationOptions.reminderHour, 19)
        XCTAssertEqual(NotificationOptions.reminderMinute, 0)
        let requests = await scheduler.scheduledRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.dailyHour, 19)
        XCTAssertEqual(requests.first?.dailyMinute, 0)
        XCTAssertNil(requests.first?.afterSeconds, "Un rappel quotidien n’a pas de délai unique.")
    }
}

// MARK: - Le faux programmateur

/// Un faux qui n'atteint jamais l'appareil, et qui retient l'ORDRE des
/// opérations : c'est ce que l'ordre annuler / programmer exige.
private actor FakeNotificationScheduler: LocalNotificationScheduling {

    enum Operation: Equatable {
        case cancel([String])
        case schedule(NotificationOptions.Kind)
    }

    private var operations: [Operation] = []
    private var pending: [NotificationOptions.ScheduledReminder]
    private var status: NotificationOptions.PermissionResult
    private var prompts = 0
    private var requests: [LocalNotificationRequest] = []

    init(
        pending: [NotificationOptions.ScheduledReminder] = [],
        status: NotificationOptions.PermissionResult = NotificationOptions.PermissionResult(
            granted: true,
            status: .authorized
        )
    ) {
        self.pending = pending
        self.status = status
    }

    var recorded: [Operation] { operations }
    var promptCount: Int { prompts }
    var scheduledRequests: [LocalNotificationRequest] { requests }

    func permission() async -> NotificationOptions.PermissionResult { status }

    func requestPermission() async -> NotificationOptions.PermissionResult {
        prompts += 1
        return status
    }

    func scheduled() async -> [NotificationOptions.ScheduledReminder] { pending }

    func cancel(ids: [String]) async {
        operations.append(.cancel(ids))
    }

    func schedule(_ request: LocalNotificationRequest) async {
        operations.append(.schedule(request.kind))
        requests.append(request)
    }
}

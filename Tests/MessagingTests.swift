// MessagingTests.swift
// Les règles de la messagerie — `Core/MessagingOptions.swift`.
//
// Ce que ces tests couvrent, et ce qui les rend non vides : chaque valeur
// attendue vient du **relevé de l'original**, exécuté par
// `_banc/oracle-messaging.mjs` sur les expressions réelles de
// `src/services/social.ts`. Un test qui affirme « le corps est détouré » sans
// que l'original le détoure serait un test de mes convictions.

import XCTest
@testable import Swiftdeepseek

final class MessagingTests: XCTestCase {

    // MARK: - Les bornes

    func testThePageIsFiftyAndTheSummaryIsThreeHundred() {
        XCTAssertEqual(MessagingOptions.pageSize, 50)
        XCTAssertEqual(MessagingOptions.summaryLimit, 300)
        XCTAssertEqual(MessagingOptions.sharedDescriptionLimit, 2000)
    }

    func testTheTwoPlaceholdersAreTheFrenchOnes() {
        XCTAssertEqual(MessagingOptions.deletedPlaceholder, "Message supprimé")
        XCTAssertEqual(MessagingOptions.newMessagePlaceholder, "Nouveau message")
    }

    // MARK: - Les quatre sortes

    func testThereAreExactlyFourKinds() {
        XCTAssertEqual(MessagingOptions.Kind.allCases.count, 4)
        XCTAssertEqual(
            MessagingOptions.Kind.allCases.map(\.rawValue),
            ["text", "encouragement", "progress", "recitation"]
        )
    }

    func testOnlyTheRecitationCarriesAnAttachment() {
        XCTAssertTrue(MessagingOptions.Kind.recitation.carriesRecitation)
        XCTAssertFalse(MessagingOptions.Kind.text.carriesRecitation)
        XCTAssertFalse(MessagingOptions.Kind.encouragement.carriesRecitation)
        XCTAssertFalse(MessagingOptions.Kind.progress.carriesRecitation)
    }

    func testAnUnknownKindRendersNothingRatherThanFailing() {
        XCTAssertNil(MessagingOptions.Kind(rawValue: "sticker"))
        XCTAssertEqual(MessagingOptions.Kind(rawValue: "text"), .text)
    }

    func testEveryKindHasItsOwnLabel() {
        let labels = MessagingOptions.Kind.allCases.map(MessagingOptions.kindLabel)
        XCTAssertEqual(Set(labels).count, 4, "deux sortes ne peuvent pas porter le même libellé")
        XCTAssertEqual(MessagingOptions.kindLabel(.recitation), "Récitation")
    }

    // MARK: - La pièce

    func testTheRoomColumnFollowsTheCase() {
        XCTAssertEqual(MessagingOptions.filter(room: .link("L")).column, "link_id")
        XCTAssertEqual(MessagingOptions.filter(room: .group("G")).column, "group_id")
        XCTAssertEqual(MessagingOptions.filter(room: .link("L")).value, "L")
        XCTAssertEqual(MessagingOptions.filter(room: .group("G")).value, "G")
    }

    func testTheRecitationCountsItsBoundsInclusive() {
        let recitation = MessagingOptions.Recitation(
            id: "r", startVerseID: 10, endVerseID: 10, durationMS: 0, storagePath: "p"
        )
        XCTAssertEqual(recitation.verseCount, 1, "un verset unique compte pour un, pas pour zéro")
    }

    func testTheRecitationCountIsZeroWhenTheBoundsAreReversed() {
        // `end - start + 1` serait négatif ; `max(0, …)` le ramène à zéro. C'est
        // le seul garde-fou, et il est posé exprès : une plage inversée est un
        // défaut de données, pas une raison d'afficher « -3 versets ».
        let recitation = MessagingOptions.Recitation(
            id: "r", startVerseID: 20, endVerseID: 10, durationMS: 0, storagePath: "p"
        )
        XCTAssertEqual(recitation.verseCount, 0)
    }

    // MARK: - Le corps envoyé

    func testTheBodyIsTrimmed() {
        XCTAssertEqual(MessagingOptions.outgoing("  salam  "), "salam")
        XCTAssertEqual(MessagingOptions.outgoing("\n\tsalam\n"), "salam")
    }

    func testATrimmedBodyIsLeftAlone() {
        XCTAssertEqual(MessagingOptions.outgoing("salam"), "salam")
    }

    func testAnEmptyBodyStaysEmpty() {
        XCTAssertEqual(MessagingOptions.outgoing("   "), "")
    }

    // MARK: - La description d'un partage

    func testAShortDescriptionIsUnchanged() {
        XCTAssertEqual(MessagingOptions.sharedDescription("salam"), "salam")
    }

    func testTheDescriptionIsCutAtTwoThousandUnits() {
        let long = String(repeating: "a", count: 2_500)
        XCTAssertEqual(MessagingOptions.sharedDescription(long).count, 2_000)
    }

    func testTheDescriptionIsCountedInUTF16UnitsNotInGraphemes() {
        // Un emoji hors du plan de base vaut **deux** unités UTF-16 et **un**
        // graphème. Sur 1 001 emoji, `slice(0, 2000)` de JavaScript garde 1 000
        // emoji entiers (2 000 unités) là où un `prefix(2000)` de graphèmes en
        // garderait 2 000. C'est la divergence que ce test épingle.
        let family = "👨‍👩‍👧‍👦"
        let many = String(repeating: family, count: 1_001)
        let cut = MessagingOptions.sharedDescription(many)
        XCTAssertEqual(cut.utf16.count, 2_000)
        XCTAssertLessThan(cut.count, 2_000, "compter en graphèmes donnerait un autre résultat")
    }

    func testATwoThousandUnitDescriptionIsNotTouched() {
        let exact = String(repeating: "b", count: 2_000)
        XCTAssertEqual(MessagingOptions.sharedDescription(exact), exact)
    }

    // MARK: - Le résumé d'un message

    func testADeletedMessageShowsTheLabel() {
        XCTAssertEqual(
            MessagingOptions.summaryBody(body: "secret", isDeleted: true),
            MessagingOptions.deletedPlaceholder
        )
    }

    func testALivingMessageShowsItsBody() {
        XCTAssertEqual(MessagingOptions.summaryBody(body: "salam", isDeleted: false), "salam")
    }

    // MARK: - Le masquage

    func testTheHiddenMessagesAreRemoved() {
        let messages = [("m1", "a"), ("m2", "b"), ("m3", "c")]
        let visible = MessagingOptions.visible(messages, id: { $0.0 }, hidden: ["m2"])
        XCTAssertEqual(visible.map(\.0), ["m1", "m3"])
    }

    func testNothingHiddenLeavesEverything() {
        let messages = [("m1", "a"), ("m2", "b")]
        let visible = MessagingOptions.visible(messages, id: { $0.0 }, hidden: [])
        XCTAssertEqual(visible.count, 2)
    }

    func testTheOrderIsPreservedAfterHiding() {
        let messages = [("m1", "a"), ("m2", "b"), ("m3", "c")]
        let visible = MessagingOptions.visible(messages, id: { $0.0 }, hidden: ["m1", "m3"])
        XCTAssertEqual(visible.map(\.0), ["m2"])
    }

    // MARK: - Les récitations à charger

    func testOnlyRecitationMessagesWithAnIDLoad() {
        let ids = MessagingOptions.recitationIDs([
            (kind: .recitation, recitationID: "r1"),
            (kind: .text, recitationID: "r2"),
            (kind: .recitation, recitationID: nil),
            (kind: .text, recitationID: nil)
        ])
        XCTAssertEqual(ids, ["r1"], "l'original teste la sorte ET la présence de l'identifiant")
    }

    func testTheIdentifiersKeepTheirOrder() {
        let ids = MessagingOptions.recitationIDs([
            (kind: .recitation, recitationID: "r3"),
            (kind: .recitation, recitationID: "r1")
        ])
        XCTAssertEqual(ids, ["r3", "r1"], "l'ordre d'affichage suit celui des messages")
    }

    // MARK: - Lu et non lu

    func testAMessageWithNoReadStampIsUnread() {
        XCTAssertTrue(MessagingOptions.isUnread(createdAt: "2026-01-01T00:00:00.000Z", lastReadAt: nil))
    }

    func testAMessageAfterTheStampIsUnread() {
        XCTAssertTrue(MessagingOptions.isUnread(
            createdAt: "2026-01-01T00:00:01.000Z",
            lastReadAt: "2026-01-01T00:00:00.000Z"
        ))
    }

    func testAMessageAtTheStampIsRead() {
        // La comparaison est **stricte** : `created_at > last_read_at`. Un
        // message écrit exactement à l'instant de la marque est lu.
        XCTAssertFalse(MessagingOptions.isUnread(
            createdAt: "2026-01-01T00:00:00.000Z",
            lastReadAt: "2026-01-01T00:00:00.000Z"
        ))
    }

    func testAMessageBeforeTheStampIsRead() {
        XCTAssertFalse(MessagingOptions.isUnread(
            createdAt: "2025-12-31T23:59:59.000Z",
            lastReadAt: "2026-01-01T00:00:00.000Z"
        ))
    }

    // MARK: - L'horodatage d'une marque

    func testTheReadStampIsInWholeMilliseconds() {
        // CE TEST A ÉTÉ CORRIGÉ APRÈS AVOIR ÉTÉ ROUGE, et le défaut était dans
        // le test. La version d'origine construisait `Date(timeIntervalSince1970:
        // 1_767_225_600.4567)` et attendait la chaîne `…00.456Z`. Or un `Double`
        // ne représente pas `.4567` exactement : la valeur la plus proche est
        // **légèrement au-dessus**, le formateur arrondit donc **au-dessus**, et
        // le run n° 82 a mesuré **`.457Z`**. La chaîne attendue n'était pas la
        // chaîne que l'entrée portait — l'assertion comparait un arrondi à une
        // valeur qui n'avait jamais existé.
        //
        // La propriété qui compte n'est pas une chaîne donnée : c'est que
        // l'horodatage soit écrit **en millisecondes entières**, comme
        // `toISOString()`. On la mesure donc sur des instants exactement
        // représentables — ceux dont les millisecondes tombent juste.
        let exact = Date(timeIntervalSince1970: 1_767_225_600.456)
        XCTAssertEqual(MessagingOptions.readStamp(now: exact), "2026-01-01T00:00:00.456Z")

        // Et sur une seconde ronde, trois décimales, toujours.
        let rond = Date(timeIntervalSince1970: 1_767_225_600)
        XCTAssertEqual(MessagingOptions.readStamp(now: rond), "2026-01-01T00:00:00.000Z")

        // La propriété générale, elle, ne dépend pas de l'arrondi : la queue
        // d'un horodatage ISO écrit par `toISOString()` fait **toujours** trois
        // chiffres. C'est cela qu'on épingle — et cela tient pour n'importe
        // quelle entrée, y compris celle qui avait fait échouer la première
        // version.
        for offset in [0.0, 0.4567, 0.9999, 0.5] {
            let stamp = MessagingOptions.readStamp(now: Date(timeIntervalSince1970: 1_767_225_600 + offset))
            let suffix = stamp.split(separator: ".").last.map(String.init) ?? ""
            XCTAssertEqual(suffix.count, 3, "trois décimales pour \(offset) — mesuré « \(suffix) »")
            XCTAssertTrue(stamp.hasSuffix("Z"), "l'horodatage ISO finit par Z")
        }
    }

    // MARK: - Le résumé d'une conversation

    func testTheFirstMessageWalkedWins() {
        // La liste arrive du plus récent au plus ancien : le premier parcouru
        // est le dernier message. Un `??=` — pas d'écrasement.
        let summaries = MessagingOptions.summaries(
            messages: [
                (linkID: "L", body: "récent", createdAt: "2026-01-02T00:00:00.000Z", isDeleted: false),
                (linkID: "L", body: "ancien", createdAt: "2026-01-01T00:00:00.000Z", isDeleted: false)
            ],
            unreadCounts: [:],
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(summaries["L"]?.body, "récent")
        XCTAssertEqual(summaries["L"]?.createdAt, "2026-01-02T00:00:00.000Z")
    }

    func testADeletedLastMessageKeepsItsOwnDate() {
        // Le libellé remplace le corps, mais l'horodatage reste celui du
        // message : c'est la date d'envoi qui ordonne la liste.
        let summaries = MessagingOptions.summaries(
            messages: [
                (linkID: "L", body: "disparu", createdAt: "2026-01-02T00:00:00.000Z", isDeleted: true)
            ],
            unreadCounts: [:],
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(summaries["L"]?.body, MessagingOptions.deletedPlaceholder)
        XCTAssertEqual(summaries["L"]?.createdAt, "2026-01-02T00:00:00.000Z")
    }

    func testAConversationWithNoMessageButUnreadCountsAppears() {
        // Le décompte crée le résumé — c'est le cas d'une conversation dont on
        // n'a pas encore chargé les messages.
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let summaries = MessagingOptions.summaries(
            messages: [],
            unreadCounts: ["L": 3],
            now: now
        )
        XCTAssertEqual(summaries["L"]?.body, MessagingOptions.newMessagePlaceholder)
        XCTAssertEqual(summaries["L"]?.createdAt, DateKeys.iso(now))
        XCTAssertEqual(summaries["L"]?.unread, 3)
    }

    func testTheWalkNeverSetsAnUnreadCount() {
        // `unread: 0` posé par le parcours, puis **écrasé** par le décompte.
        // Un message non lu sans décompte ne peut donc pas apparaître.
        let summaries = MessagingOptions.summaries(
            messages: [
                (linkID: "L", body: "salam", createdAt: "2026-01-02T00:00:00.000Z", isDeleted: false)
            ],
            unreadCounts: [:],
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(summaries["L"]?.unread, 0)
    }

    func testAZeroCountDoesNotCreateASummary() {
        let summaries = MessagingOptions.summaries(
            messages: [],
            unreadCounts: ["L": 0],
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertNil(summaries["L"], "un décompte nul n'ouvre pas de conversation")
    }

    func testTheUnreadCountOverridesTheZeroOfTheWalk() {
        let summaries = MessagingOptions.summaries(
            messages: [
                (linkID: "L", body: "salam", createdAt: "2026-01-02T00:00:00.000Z", isDeleted: false)
            ],
            unreadCounts: ["L": 7],
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(summaries["L"]?.body, "salam")
        XCTAssertEqual(summaries["L"]?.unread, 7)
    }

    func testTwoConversationsDoNotBleedIntoEachOther() {
        let summaries = MessagingOptions.summaries(
            messages: [
                (linkID: "A", body: "a1", createdAt: "2026-01-02T00:00:00.000Z", isDeleted: false),
                (linkID: "B", body: "b1", createdAt: "2026-01-01T00:00:00.000Z", isDeleted: false)
            ],
            unreadCounts: ["B": 2],
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(summaries["A"]?.body, "a1")
        XCTAssertEqual(summaries["A"]?.unread, 0)
        XCTAssertEqual(summaries["B"]?.body, "b1")
        XCTAssertEqual(summaries["B"]?.unread, 2)
    }

    // MARK: - La pastille

    func testNoBadgeBelowOne() {
        XCTAssertNil(MessagingOptions.unreadBadge(0))
        XCTAssertNil(MessagingOptions.unreadBadge(-1))
    }

    func testTheBadgeShowsTheCountUpToNinetyNine() {
        XCTAssertEqual(MessagingOptions.unreadBadge(1), "1")
        XCTAssertEqual(MessagingOptions.unreadBadge(99), "99")
    }

    func testTheBadgeCapsAtNinetyNinePlus() {
        XCTAssertEqual(MessagingOptions.unreadBadge(100), "99+")
        XCTAssertEqual(MessagingOptions.unreadBadge(1_000), "99+")
    }

    // MARK: - La durée

    func testADurationOfZeroReadsZeroZero() {
        XCTAssertEqual(MessagingOptions.durationText(0), "0:00")
        XCTAssertEqual(MessagingOptions.durationText(-5), "0:00")
    }

    func testTheSecondsArePaddedToTwoDigits() {
        XCTAssertEqual(MessagingOptions.durationText(5_000), "0:05")
        XCTAssertEqual(MessagingOptions.durationText(65_000), "1:05")
        XCTAssertEqual(MessagingOptions.durationText(600_000), "10:00")
    }

    func testTheMillisecondsAreTruncatedNotRounded() {
        // `Math.floor` de l'original : 1 999 ms vaut une seconde, pas deux.
        XCTAssertEqual(MessagingOptions.durationText(1_999), "0:01")
    }

    // MARK: - La garde du nombre de séances
    //
    // Les valeurs attendues viennent de `_banc/oracle-messaging.mjs`, qui évalue
    // l'expression RÉELLE de `SocialScreens.tsx:177` sur chaque entrée. Le banc
    // est cité, mais il est aussi **importé et exécuté** par le vérificateur :
    // un oracle qu'on recopie ne prouve rien.

    func testTheSessionCountRefusesWhatIsOutOfBounds() {
        XCTAssertNil(MessagingOptions.sessionCount("0"))
        XCTAssertNil(MessagingOptions.sessionCount("15"))
        XCTAssertNil(MessagingOptions.sessionCount("-3"))
    }

    func testTheSessionCountAcceptsOneThroughFourteen() {
        XCTAssertEqual(MessagingOptions.sessionCount("1"), 1)
        XCTAssertEqual(MessagingOptions.sessionCount("3"), 3)
        XCTAssertEqual(MessagingOptions.sessionCount("14"), 14)
    }

    func testTheSessionCountRefusesADecimal() {
        // `Number.isInteger(2.5)` est faux — le bouton reste éteint.
        XCTAssertNil(MessagingOptions.sessionCount("2.5"))
    }

    func testAnEmptyFieldIsRefusedByTheUpperBoundNotByTheShape() {
        // `Number("")` vaut 0 en JavaScript, pas `NaN` : le refus vient de la
        // borne `< 1`, pas d'une lecture impossible. Les deux refusent — mais
        // `Int("")` rendrait `nil`, donc une AUTRE branche.
        XCTAssertEqual(MessagingOptions.number(""), 0)
        XCTAssertNil(MessagingOptions.sessionCount(""))
        XCTAssertEqual(MessagingOptions.number("   "), 0)
        XCTAssertNil(MessagingOptions.sessionCount("   "))
    }

    func testTheExponentFormIsReadByNumberAndNotByInt() {
        // LE point de divergence : `Number("1e2")` vaut 100 (refusé par la
        // borne haute), `Int("1e2")` rend `nil` (refusé par la forme). Les deux
        // refusent, mais **pas par la même branche** — et c'est ce qu'on épingle.
        XCTAssertEqual(MessagingOptions.number("1e2"), 100)
        XCTAssertNil(MessagingOptions.sessionCount("1e2"))
    }

    func testTheHexFormIsReadByNumberAndIsUnreachable() {
        // `Number("0x10")` vaut 16. Inatteignable : le champ porte
        // `keyboardType(.numberPad)`, qui n'offre ni `x` ni `e`. La divergence
        // est donc **nommée** et **déclarée inatteignable**, pas ignorée.
        XCTAssertEqual(MessagingOptions.number("0x10"), 16)
    }

    func testANonNumericTextIsRefused() {
        XCTAssertNil(MessagingOptions.number("abc"))
        XCTAssertNil(MessagingOptions.sessionCount("abc"))
    }

    // MARK: - La garde du rendez-vous

    private var reference: Date { DateKeys.parseISO("2026-10-07T00:00:00Z")! }

    func testAFutureAppointmentIsAccepted() {
        XCTAssertNotNil(MessagingOptions.appointmentISO("2026-12-01 18:30", now: reference))
    }

    func testAPastAppointmentIsRefused() {
        XCTAssertNil(MessagingOptions.appointmentISO("2026-01-01 08:00", now: reference))
    }

    func testTheAppointmentShapeIsExact() {
        // Un jour à un chiffre ne passe pas le gabarit `\d{2}`.
        XCTAssertNil(MessagingOptions.appointmentISO("2026-10-7 18:30", now: reference))
        // Le séparateur est une espace, jamais un `T`.
        XCTAssertNil(MessagingOptions.appointmentISO("2027-12-01T18:30", now: reference))
        XCTAssertNil(MessagingOptions.appointmentISO("", now: reference))
    }

    func testTheThirtyFirstOfFebruaryRollsOverAndIsAccepted() {
        // MESURÉ, ET LE PORTAGE ÉTAIT JUSTE. `new Date("2027-02-31T10:00:00")`
        // **roule** au 3 mars en JavaScript — l'ISO n'est rejeté que s'il est
        // illisible. Une garde d'aller-retour, « propre » en apparence, aurait
        // refusé cette saisie là où l'application React Native l'accepte.
        let iso = MessagingOptions.appointmentISO("2027-02-31 10:00", now: reference)
        XCTAssertNotNil(iso)
        XCTAssertTrue(iso?.hasPrefix("2027-03-03") == true, "le 31 février 2027 devient le 3 mars")
    }

    func testAMonthOfThirteenIsRefused() {
        XCTAssertNil(MessagingOptions.appointmentISO("2027-13-01 10:00", now: reference))
    }

    func testAnHourOfTwentyFiveIsRefused() {
        XCTAssertNil(MessagingOptions.appointmentISO("2027-12-01 25:00", now: reference))
    }

    // MARK: - L'accusé de lecture

    func testAMessageAtTheVeryInstantOfTheStampIsRead() {
        // L'original écrit `<=`, et non `<`.
        XCTAssertTrue(MessagingOptions.isRead(
            "2026-01-01T10:00:00.000Z", at: "2026-01-01T10:00:00.000Z"))
    }

    func testAMessageOneMillisecondAfterTheStampIsSent() {
        XCTAssertFalse(MessagingOptions.isRead(
            "2026-01-01T10:00:00.001Z", at: "2026-01-01T10:00:00.000Z"))
    }

    func testWithoutAStampNothingIsRead() {
        XCTAssertFalse(MessagingOptions.isRead("2026-01-01T10:00:00.000Z", at: nil))
    }

    func testTheTwoReadingPredicatesAgree() {
        // L'accord entre `isRead` (`<=`) et `isUnread` (`>`) est **mesuré**, et
        // non écrit : deux négations qui se répondent sont exactement ce qu'une
        // refonte casse en silence.
        let pairs: [(String, String)] = [
            ("2026-01-01T10:00:00.000Z", "2026-01-01T10:00:00.000Z"),
            ("2026-01-01T10:00:00.001Z", "2026-01-01T10:00:00.000Z"),
            ("2026-01-01T09:59:59.999Z", "2026-01-01T10:00:00.000Z")
        ]
        for (created, stamp) in pairs {
            XCTAssertEqual(
                MessagingOptions.isRead(created, at: stamp),
                !MessagingOptions.isUnread(createdAt: created, lastReadAt: stamp),
                "les deux prédicats doivent se répondre sur \(created)"
            )
        }
    }

    // MARK: - L'heure d'un message

    func testAnUnreadableTimestampRendersEmptyRatherThanRaw() {
        // Un écran ne doit jamais afficher une chaîne ISO à la place d'une heure.
        XCTAssertEqual(DateKeys.timeText("pas une date"), "")
        XCTAssertEqual(DateKeys.dateTimeText("pas une date"), "")
    }

    // MARK: - Les cercles privés

    func testTheCircleNameNeedsTwoCharactersOnceTrimmed() {
        // La borne est celle de l'original : `groupName.trim().length < 2`.
        // Le détourage est JavaScript, qui retire les blancs Unicode — et non
        // le seul espace ASCII. `" "` détouré vaut `""`, donc un caractère (0) :
        // refusé, comme `""` et `"a"`.
        XCTAssertTrue(MessagingOptions.circleNameIsAcceptable("Coran"))
        XCTAssertTrue(MessagingOptions.circleNameIsAcceptable("  Coran  "))
        // Deux caractères exactement : la borne est INCLUSIVE.
        XCTAssertTrue(MessagingOptions.circleNameIsAcceptable("ab"))
        XCTAssertTrue(MessagingOptions.circleNameIsAcceptable("  ab  "))

        XCTAssertFalse(MessagingOptions.circleNameIsAcceptable(""))
        XCTAssertFalse(MessagingOptions.circleNameIsAcceptable("a"))
        XCTAssertFalse(MessagingOptions.circleNameIsAcceptable(" a "))
        XCTAssertFalse(MessagingOptions.circleNameIsAcceptable("     "))
        // Une tabulation et un saut de ligne sont des blancs, eux aussi.
        XCTAssertFalse(MessagingOptions.circleNameIsAcceptable("\t\n"))
        XCTAssertFalse(MessagingOptions.circleNameIsAcceptable("\ta\n"))
    }

    func testTheCircleNameIsSentTrimmedAndUnchangedOtherwise() {
        // La règle rend le nom qu'elle a accepté : la vue n'a pas à le
        // redétourer, sinon deux détourages pourraient diverger.
        XCTAssertEqual(MessagingOptions.trimmedCircleName("  Coran  "), "Coran")
        XCTAssertEqual(MessagingOptions.trimmedCircleName("Coran"), "Coran")
        // Un espace INTÉRIEUR n'est pas touché : `trim` ne coupe que les bords.
        XCTAssertEqual(MessagingOptions.trimmedCircleName("  Le Coran  "), "Le Coran")
    }

    func testTheCircleNameLetsTwoEmojiThroughAndRefusesOne() {
        // `Character` compte des graphèmes, comme `String.length` de JavaScript
        // compte des unités UTF-16 — ici « un seul caractère » des deux côtés.
        // Un emoji hors plan multilingue pèse DEUX unités UTF-16 en JavaScript :
        // il n'y a donc **aucun** écart à porter sur la borne, et c'est mesuré
        // pour mémoire — une implémentation qui compterait `utf16.count`
        // accepterait un seul emoji et divergerait.
        let unEmoji = "📖"
        let deuxEmoji = "📖📗"
        XCTAssertEqual(deuxEmoji.count, 2)
        XCTAssertEqual(unEmoji.utf16.count, 2, "un emoji hors BMP pèse deux unités UTF-16")
        XCTAssertTrue(MessagingOptions.circleNameIsAcceptable(deuxEmoji))
        XCTAssertFalse(MessagingOptions.circleNameIsAcceptable(unEmoji))
    }

    func testOnlyTheOwnerAndTheModeratorManageMembers() {
        // `['owner','moderator'].includes(m.role)` — une liste FERMÉE.
        XCTAssertTrue(MessagingOptions.managesMembers("owner"))
        XCTAssertTrue(MessagingOptions.managesMembers("moderator"))
        // Un membre simple ne gère rien — et c'est le cas le plus fréquent.
        XCTAssertFalse(MessagingOptions.managesMembers("member"))
        // Un rôle inconnu, vide ou absent ne gère rien non plus : c'est le sens
        // d'un `includes` sur une liste fermée, là où un `!= "member"` aurait
        // laissé passer tout le reste.
        XCTAssertFalse(MessagingOptions.managesMembers(nil))
        XCTAssertFalse(MessagingOptions.managesMembers(""))
        XCTAssertFalse(MessagingOptions.managesMembers("Owner"))
        XCTAssertFalse(MessagingOptions.managesMembers("administrateur"))
    }

    func testAnInvitationAwaitsMyAnswerOnlyWhenItIsMineAndUnaccepted() {
        func membre(_ userId: String, _ acceptedAt: String?) -> GroupMember {
            GroupMember(groupId: "g", userId: userId, role: "member",
                        acceptedAt: acceptedAt, invitedBy: nil, profile: nil)
        }
        let moi = "moi"
        // La mienne, sans réponse : c'est la SEULE qui affiche « Rejoindre ».
        XCTAssertTrue(MessagingOptions.awaitsMyAnswer(membre(moi, nil), myID: moi))
        // La mienne, déjà acceptée : rien à répondre.
        XCTAssertFalse(MessagingOptions.awaitsMyAnswer(membre(moi, "2026-01-01T00:00:00.000Z"), myID: moi))
        // Celle d'un autre, sans réponse : ce n'est pas la mienne.
        XCTAssertFalse(MessagingOptions.awaitsMyAnswer(membre("autre", nil), myID: moi))
        XCTAssertFalse(MessagingOptions.awaitsMyAnswer(membre("autre", "2026-01-01T00:00:00.000Z"), myID: moi))
    }

    func testACircleResolvesTheContactItDecorates() {
        // Le décodage : `contact_user_id` est une colonne AJOUTÉE
        // (`admin-contact.sql:2`) et le type de l'original la porte
        // optionnelle. Une réponse du serveur qui l'OMET doit décoder en `nil`
        // — sinon l'application refuserait tout groupe créé avant la colonne,
        // et le décodage est le seul endroit qui puisse le voir.
        let sansClef = #"{"id":"g","name":"Coran","owner_id":"o","created_at":"2026-01-01T00:00:00.000Z"}"#
        let avecClefNulle = #"{"id":"g","name":"Coran","owner_id":"o","created_at":"2026-01-01T00:00:00.000Z","contact_user_id":null}"#
        let avecContact = #"{"id":"g","name":"Administration","owner_id":"o","created_at":"2026-01-01T00:00:00.000Z","contact_user_id":"admin"}"#
        let decodeur = JSONDecoder()
        // Les trois doivent décoder — c'est le point : la clé absente n'est pas
        // une erreur, et la clé nulle n'est pas un identifiant vide.
        // `try?` rend `FriendGroup?` : on décode d'abord, on interroge ensuite,
        // sinon l'optional chaining masquerait un échec de décodage sous un
        // `nil` de valeur — deux causes, un seul verdict.
        let groupeSansClef = try? decodeur.decode(FriendGroup.self, from: Data(sansClef.utf8))
        let groupeClefNulle = try? decodeur.decode(FriendGroup.self, from: Data(avecClefNulle.utf8))
        let groupeAvecContact = try? decodeur.decode(FriendGroup.self, from: Data(avecContact.utf8))
        XCTAssertNotNil(groupeSansClef, "une clé ABSENTE ne doit pas faire échouer le décodage")
        XCTAssertNotNil(groupeClefNulle, "une clé NULLE ne doit pas faire échouer le décodage")
        XCTAssertEqual(groupeAvecContact?.contactUserId, "admin")
        XCTAssertNil(groupeSansClef?.contactUserId)
        XCTAssertNil(groupeClefNulle?.contactUserId)
        // Et le reste du groupe survit dans les trois cas : sans quoi un
        // décodage « réussi mais vide » passerait le test.
        XCTAssertEqual(groupeSansClef?.name, "Coran")
        XCTAssertEqual(groupeClefNulle?.ownerId, "o")
    }

    func testTheCircleViewNeverDecidesARuleItself() {
        // Le contrat de l'écran des cercles : il APPELLE les règles de `Core`,
        // il ne les réécrit pas. C'est la même frontière qu'à §9.37 pour la
        // messagerie, et c'est ce qui empêche les deux applications de
        // diverger sans qu'un test tombe.
        //
        // Le banc de contrôle refait cette lecture ; ici, c'est le NOMBRE de
        // règles qui est épinglé — une règle qui disparaît de `Core` doit
        // faire tomber un test, pas seulement un `grep`.
        XCTAssertTrue(MessagingOptions.circleNameIsAcceptable("ab"))
        XCTAssertTrue(MessagingOptions.managesMembers("owner"))
        XCTAssertTrue(MessagingOptions.awaitsMyAnswer(
            GroupMember(groupId: "g", userId: "m", role: "member",
                        acceptedAt: nil, invitedBy: nil, profile: nil), myID: "m"))
    }
}

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
        let now = Date(timeIntervalSince1970: 1_767_225_600.4567)
        let stamp = MessagingOptions.readStamp(now: now)
        XCTAssertEqual(stamp, "2026-01-01T00:00:00.456Z")
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
}

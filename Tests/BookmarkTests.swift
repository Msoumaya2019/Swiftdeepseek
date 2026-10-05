// BookmarkTests.swift
// Marques-pages : enregistrer, supprimer, reprendre, lister.
//
// POURQUOI CE FICHIER EXISTE
//   `Core/Bookmark.swift` portait déjà les quatre opérations, mais AUCUN test ne
//   les éprouvait : le fichier a été écrit avant que l'écran qui s'en sert
//   n'existe. C'est exactement l'état où une règle silencieuse survit à une
//   relecture — elle a l'air juste, et rien ne la contredit.
//
// TROIS RÈGLES QUE CES TESTS ÉPINGLENT, ET QU'UN PORTAGE « PROPRE » CASSERAIT
//
//   1. `save` EFFACE `lastUsedAt` ET `deletedAt`.
//      `src/core/bookmarks.ts:8` construit un objet NEUF à sept clés —
//      `verseId, surah, ayah, page, sourcePages, createdAt, updatedAt` — qui ne
//      reprend ni l'un ni l'autre. Conserver `lastUsedAt` ferait diverger
//      l'ORDRE de la liste entre les deux applications, puisqu'elle trie sur
//      `lastUsedAt ?? updatedAt` ; conserver `deletedAt` empêcherait un
//      ré-enregistrement de ressusciter une marque-page supprimée.
//
//   2. `save` ÉCRIT LA PAGE DU MOUSHAF, PAS CELLE DE LA SOURCE.
//      `page: pageOf(id)` ; la page de la source va dans `sourcePages`, sous la
//      clé de l'édition. Les confondre ferait entrer une page du Coran 1441 dans
//      le champ qui porte la pagination du Coran de Médine.
//
//   3. `visible` DÉPARTAGE LES EX ÆQUO PAR VERSET CROISSANT.
//      L'original trie sur l'horodatage SEUL, mais `Object.values` rend les clés
//      numériques dans l'ordre croissant et `Array.prototype.sort` est stable.
//      Swift ne donne ni l'un ni l'autre : sans départage explicite, l'ordre
//      divergerait sur le même document. Voir `Bookmark.visible`.
//
// LES CHIFFRES DE CE FICHIER SONT MESURÉS
//   Le verset **746** a une première page DIFFÉRENTE selon l'édition : 121 pour
//   le Coran de Médine, 120 pour le Coran 1441. C'est mesuré sur
//   `Resources/Data/bounds.json`, `coran_1441-bounds.json` et `pages.json` :
//   **56 versets sur 6236** sont dans ce cas. Sans cet écart, les tests 1, 2 et 6
//   ne distingueraient rien — `page` et la page de source vaudraient le même
//   nombre, et le test passerait pour la mauvaise raison.

import XCTest
@testable import Swiftdeepseek

final class BookmarkTests: XCTestCase {

    // MARK: - Outils

    private func stateWith(_ bookmarks: [String: VerseBookmark]) -> AppState {
        var state = Program.defaultState()
        state.bookmarks = bookmarks
        return state
    }

    private func bookmark(
        _ verseID: Int,
        page: Int? = nil,
        sourcePages: [String: Int]? = nil,
        createdAt: String = "2026-01-01T00:00:00.000Z",
        updatedAt: String = "2026-01-01T00:00:00.000Z",
        lastUsedAt: String? = nil,
        deletedAt: String? = nil
    ) -> VerseBookmark {
        let verse = Quran.verseAt(verseID)
        return VerseBookmark(
            verseId: verseID,
            surah: verse.surah,
            ayah: verse.ayah,
            page: page ?? Quran.pageOf(verseID) ?? 1,
            sourcePages: sourcePages,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt,
            deletedAt: deletedAt
        )
    }

    // MARK: - save

    /// La page du moushaf et la page de la source ne sont pas le même champ.
    func testSaveWritesTheMushafPageAndKeepsTheSourcePageSeparate() {
        let next = Bookmark.save(
            Program.defaultState(), verseID: 746, source: "coran_1441", page: 120
        )
        let item = next.bookmarks?["746"]
        // 121 : la page du Coran de Médine, mesurée dans `bounds.json`. Pas 120,
        // qui est la page qu'on vient de lire dans le Coran 1441.
        XCTAssertEqual(item?.page, 121)
        XCTAssertEqual(item?.sourcePages?["coran_1441"], 120)
        // Al Mâ'idah 77 — mesuré dans `meta.json`, jamais déduit de l'identifiant.
        XCTAssertEqual(item?.surah, 5)
        XCTAssertEqual(item?.ayah, 77)
    }

    /// Les pages des autres éditions sont conservées, pas remplacées.
    func testSaveMergesSourcePagesInsteadOfReplacingThem() {
        let state = stateWith(["746": bookmark(746, sourcePages: ["traditional": 121])])
        let next = Bookmark.save(state, verseID: 746, source: "coran_1441", page: 120)
        XCTAssertEqual(next.bookmarks?["746"]?.sourcePages?["traditional"], 121)
        XCTAssertEqual(next.bookmarks?["746"]?.sourcePages?["coran_1441"], 120)
    }

    /// `createdAt` est celui du premier enregistrement ; `updatedAt` avance.
    func testSavePreservesCreatedAtAndMovesUpdatedAt() {
        let created = "2025-05-05T05:05:05.000Z"
        let state = stateWith(["746": bookmark(746, createdAt: created, updatedAt: created)])
        let next = Bookmark.save(state, verseID: 746, source: "traditional", page: 121)
        let item = next.bookmarks?["746"]

        XCTAssertEqual(item?.createdAt, created)
        XCTAssertNotEqual(item?.updatedAt, created)
        XCTAssertEqual(item?.updatedAt, next.updatedAt)
        XCTAssertEqual(item?.updatedAt, next.lastRead?.readAt)
    }

    /// La divergence corrigée : un ré-enregistrement remet `lastUsedAt` à zéro.
    func testSaveErasesLastUsedAt() {
        let state = stateWith(["746": bookmark(746, lastUsedAt: "2026-03-03T03:03:03.000Z")])
        let next = Bookmark.save(state, verseID: 746, source: "traditional", page: 121)
        XCTAssertNil(next.bookmarks?["746"]?.lastUsedAt)
    }

    /// Enregistrer à nouveau une marque-page supprimée la fait revenir.
    func testSaveResurrectsADeletedBookmark() {
        let state = stateWith(["746": bookmark(746, deletedAt: "2026-03-03T03:03:03.000Z")])
        let next = Bookmark.save(state, verseID: 746, source: "traditional", page: 121)
        XCTAssertNil(next.bookmarks?["746"]?.deletedAt)
        XCTAssertEqual(Bookmark.visible(next).count, 1)
    }

    /// `lastRead` retient la page de la SOURCE, pas celle du moushaf.
    func testSaveSetsLastReadToTheSourcePage() {
        let next = Bookmark.save(
            Program.defaultState(), verseID: 746, source: "coran_1441", page: 120
        )
        XCTAssertEqual(next.lastRead?.page, 120)
        XCTAssertEqual(next.lastRead?.verseId, 746)
    }

    /// Un verset hors bornes : l'original LÈVE, une fonction pure rend l'état.
    func testSaveOnAnUnknownVerseLeavesTheStateUntouched() {
        let state = Program.defaultState()
        XCTAssertEqual(Bookmark.save(state, verseID: 0, source: "traditional", page: 1), state)
        XCTAssertEqual(Bookmark.save(state, verseID: 6237, source: "traditional", page: 1), state)
        XCTAssertEqual(Bookmark.save(state, verseID: -3, source: "traditional", page: 1), state)
    }

    func testSaveOnAFreshVerseStartsCreatedAtAndUpdatedAtTogether() {
        let next = Bookmark.save(Program.defaultState(), verseID: 1, source: "traditional", page: 1)
        let item = next.bookmarks?["1"]
        XCTAssertEqual(item?.createdAt, item?.updatedAt)
        XCTAssertEqual(item?.sourcePages?["traditional"], 1)
    }

    // MARK: - delete

    /// La suppression est DOUCE : elle pose une marque, elle n'efface pas.
    func testDeleteIsSoftAndKeepsEveryOtherField() {
        let state = stateWith([
            "746": bookmark(746, sourcePages: ["coran_1441": 120], createdAt: "2025-05-05T05:05:05.000Z")
        ])
        let next = Bookmark.delete(state, verseID: 746)
        let item = next.bookmarks?["746"]

        XCTAssertNotNil(item, "l'entrée doit rester : un autre appareil hors ligne la ressusciterait")
        XCTAssertNotNil(item?.deletedAt)
        XCTAssertEqual(item?.deletedAt, item?.updatedAt)
        XCTAssertEqual(item?.createdAt, "2025-05-05T05:05:05.000Z")
        XCTAssertEqual(item?.sourcePages?["coran_1441"], 120)
        XCTAssertEqual(Bookmark.visible(next).count, 0)
    }

    func testDeleteOnAMissingBookmarkLeavesTheStateUntouched() {
        let state = Program.defaultState()
        XCTAssertEqual(Bookmark.delete(state, verseID: 1), state)
    }

    // MARK: - use

    /// « Reprendre » : `lastUsedAt` est daté, et `lastRead` suit la page donnée.
    func testUseStampsLastUsedAtAndMovesLastRead() {
        let state = stateWith(["746": bookmark(746, updatedAt: "2025-05-05T05:05:05.000Z")])
        let next = Bookmark.use(state, verseID: 746, page: 120)
        let item = next.bookmarks?["746"]

        XCTAssertNotNil(item?.lastUsedAt)
        XCTAssertEqual(item?.lastUsedAt, item?.updatedAt)
        XCTAssertEqual(next.lastRead?.page, 120)
        XCTAssertEqual(next.lastRead?.verseId, 746)
        // Les pages ne bougent pas : « reprendre » ne réécrit pas le repère.
        XCTAssertEqual(item?.page, 121)
        XCTAssertNil(item?.deletedAt)
    }

    /// Sans page donnée, `lastRead` retombe sur la page du moushaf.
    func testUseWithoutAPageFallsBackToTheMushafPage() {
        let state = stateWith(["746": bookmark(746)])
        let next = Bookmark.use(state, verseID: 746)
        XCTAssertEqual(next.lastRead?.page, 121)
    }

    func testUseIgnoresADeletedBookmark() {
        let state = stateWith(["746": bookmark(746, deletedAt: "2026-03-03T03:03:03.000Z")])
        XCTAssertEqual(Bookmark.use(state, verseID: 746, page: 120), state)
    }

    func testUseIgnoresAMissingBookmark() {
        let state = Program.defaultState()
        XCTAssertEqual(Bookmark.use(state, verseID: 1, page: 1), state)
    }

    // MARK: - visible

    func testVisibleExcludesDeletedEntries() {
        let state = stateWith([
            "1": bookmark(1),
            "2": bookmark(2, deletedAt: "2026-03-03T03:03:03.000Z"),
        ])
        XCTAssertEqual(Bookmark.visible(state).map(\.verseId), [1])
    }

    /// Décroissant sur `lastUsedAt ?? updatedAt`.
    func testVisibleSortsByLastUsedAtThenUpdatedAtDescending() {
        let state = stateWith([
            "1": bookmark(1, updatedAt: "2026-01-01T00:00:00.000Z"),
            "2": bookmark(2, updatedAt: "2026-06-01T00:00:00.000Z"),
            "3": bookmark(3, updatedAt: "2026-03-01T00:00:00.000Z", lastUsedAt: "2026-09-01T00:00:00.000Z"),
        ])
        XCTAssertEqual(Bookmark.visible(state).map(\.verseId), [3, 2, 1])
    }

    /// `lastUsedAt` REMPLACE `updatedAt`, il ne s'y ajoute pas.
    func testVisiblePrefersLastUsedAtOverANewerUpdatedAt() {
        let state = stateWith([
            "1": bookmark(1, updatedAt: "2026-09-01T00:00:00.000Z"),
            "2": bookmark(2, updatedAt: "2026-01-01T00:00:00.000Z", lastUsedAt: "2026-02-01T00:00:00.000Z"),
        ])
        XCTAssertEqual(Bookmark.visible(state).map(\.verseId), [1, 2])
    }

    /// L'égalité est départagée par le verset croissant — la règle silencieuse.
    func testVisibleBreaksTiesByAscendingVerseId() {
        let same = "2026-04-04T04:04:04.000Z"
        let state = stateWith([
            "9": bookmark(9, updatedAt: same),
            "3": bookmark(3, updatedAt: same),
            "7": bookmark(7, updatedAt: same),
        ])
        XCTAssertEqual(Bookmark.visible(state).map(\.verseId), [3, 7, 9])
    }

    /// Et le badge de la liste suit la même règle : le plus petit verset gagne.
    func testVisibleTieOrderDecidesWhichEntryCarriesTheLastUsedBadge() {
        let same = "2026-04-04T04:04:04.000Z"
        let state = stateWith([
            "9": bookmark(9, lastUsedAt: same),
            "3": bookmark(3, lastUsedAt: same),
        ])
        let items = Bookmark.visible(state).filter { $0.lastUsedAt != nil }
        let badge = items.max { ($0.lastUsedAt ?? "") < ($1.lastUsedAt ?? "") }?.verseId
        XCTAssertEqual(badge, 3)
    }

    // MARK: - merge

    func testMergeFallsBackWhenOneSideIsMissing() {
        let side: [String: VerseBookmark] = ["1": bookmark(1)]
        XCTAssertEqual(Bookmark.merge(nil, side), side)
        XCTAssertEqual(Bookmark.merge(side, nil), side)
        XCTAssertNil(Bookmark.merge(nil, nil))
    }

    func testMergeKeepsTheMostRecentlyUpdated() {
        let older = bookmark(1, updatedAt: "2026-01-01T00:00:00.000Z")
        let newer = bookmark(1, updatedAt: "2026-06-01T00:00:00.000Z")
        XCTAssertEqual(Bookmark.merge(["1": older], ["1": newer])?["1"], newer)
        XCTAssertEqual(Bookmark.merge(["1": newer], ["1": older])?["1"], newer)
    }

    /// À `updatedAt` égal, le PREMIER l'emporte : la comparaison est stricte.
    func testMergeKeepsTheFirstOnEqualUpdatedAt() {
        let same = "2026-01-01T00:00:00.000Z"
        let first = bookmark(1, page: 2, updatedAt: same)
        let second = bookmark(1, page: 3, updatedAt: same)
        XCTAssertEqual(Bookmark.merge(["1": first], ["1": second])?["1"]?.page, 2)
        XCTAssertEqual(Bookmark.merge(["1": second], ["1": first])?["1"]?.page, 3)
    }
}

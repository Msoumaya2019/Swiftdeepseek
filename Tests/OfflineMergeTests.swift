// OfflineMergeTests.swift
// Le fichier le plus important du projet pour la compatibilité.
//
// Les deux applications écrivent le même document `user_state.data`. Si cette
// fusion divergeait de celle de React Native, l'une des deux perdrait
// silencieusement des données. Chaque cas ci-dessous correspond à une règle de
// `src/core/offlineMerge.ts`.
//
// Vocabulaire : base = dernière version synchronisée connue, local = ce que cet
// appareil a fait hors ligne, remote = ce que le serveur contient maintenant.

import XCTest
@testable import Swiftdeepseek

final class OfflineMergeTests: XCTestCase {

    private func object(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }
    private func row(_ id: String, _ extra: [String: JSONValue] = [:]) -> JSONValue {
        .object(["id": .string(id)].merging(extra) { _, new in new })
    }

    // MARK: Règles de base

    func testUnchangedLocalTakesRemote() {
        let base = object(["theme": .string("white")])
        let local = object(["theme": .string("white")])
        let remote = object(["theme": .string("night")])
        XCTAssertEqual(
            OfflineMerge.merge(base: base, local: local, remote: remote, path: ""),
            remote
        )
    }

    func testLocalChangeWins() {
        let base = object(["theme": .string("white")])
        let local = object(["theme": .string("lilac")])
        let remote = object(["theme": .string("white")])
        XCTAssertEqual(
            OfflineMerge.merge(base: base, local: local, remote: remote, path: "")?["theme"]?.stringValue,
            "lilac"
        )
    }

    func testConcurrentChangeOfTheSameFieldKeepsLocal() {
        // Les deux ont changé le même champ : la modification locale l'emporte,
        // c'est la règle du fichier d'origine.
        let base = object(["theme": .string("white")])
        let local = object(["theme": .string("lilac")])
        let remote = object(["theme": .string("night")])
        XCTAssertEqual(
            OfflineMerge.merge(base: base, local: local, remote: remote, path: "")?["theme"]?.stringValue,
            "lilac"
        )
    }

    func testDifferentFieldsAreBothKept() {
        let base = object(["theme": .string("white"), "accent": .string("prune")])
        let local = object(["theme": .string("lilac"), "accent": .string("prune")])
        let remote = object(["theme": .string("white"), "accent": .string("gold")])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "")
        XCTAssertEqual(merged?["theme"]?.stringValue, "lilac")
        XCTAssertEqual(merged?["accent"]?.stringValue, "gold")
    }

    // MARK: Point d'arrêt d'une séance

    func testThroughKeepsTheFurthestProgress() {
        // Un appareil s'est arrêté au verset 5, l'autre au 9 : on garde 9.
        let base = object(["through": .number(3), "end": .number(10)])
        let local = object(["through": .number(5), "end": .number(10)])
        let remote = object(["through": .number(9), "end": .number(10)])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "")
        XCTAssertEqual(merged?["through"]?.intValue, 9)
        XCTAssertEqual(merged?["status"]?.stringValue, "partial")
    }

    func testStatusBecomesCompletedWhenThroughReachesEnd() {
        let base = object(["through": .number(3), "end": .number(10)])
        let local = object(["through": .number(10), "end": .number(10)])
        let remote = object(["through": .number(4), "end": .number(10)])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "")
        XCTAssertEqual(merged?["through"]?.intValue, 10)
        XCTAssertEqual(merged?["status"]?.stringValue, "completed")
    }

    func testStatusDoneAlwaysWins() {
        // base, local et remote diffèrent tous les trois : on descend donc
        // jusqu'à la règle du champ `status`, qui privilégie « done ».
        let base = object(["status": .string("todo")])
        let local = object(["status": .string("postponed")])
        let remote = object(["status": .string("done")])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "")
        XCTAssertEqual(merged?["status"]?.stringValue, "done")
    }

    // MARK: Tableaux d'objets identifiés

    func testIdKeyedArraysAreMergedNotReplaced() {
        // Chaque appareil a créé une séance différente hors ligne : les deux
        // doivent survivre. Un remplacement en perdrait une.
        let base = object(["sessions": .array([row("a")])])
        let local = object(["sessions": .array([row("a"), row("b")])])
        let remote = object(["sessions": .array([row("a"), row("c")])])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "")
        let ids = (merged?["sessions"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
        XCTAssertEqual(Set(ids), ["a", "b", "c"])
    }

    func testLocallyDeletedRowIsNotResurrected() {
        // Suppression locale d'une ligne que le serveur connaît encore : elle ne
        // doit pas revenir. C'est le rôle de la pierre tombale.
        let base = object(["bookmarks": .array([row("a"), row("b")])])
        let local = object(["bookmarks": .array([row("a")])])
        let remote = object(["bookmarks": .array([row("a"), row("b")])])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "")
        let ids = (merged?["bookmarks"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
        XCTAssertEqual(ids, ["a"])
    }

    func testDoneRowFromServerSurvivesLocalDeletion() {
        // Exception voulue : une séance terminée côté serveur est conservée même
        // si cet appareil ne la connaît pas.
        let base = object(["sessions": .array([row("a")])])
        let local = object(["sessions": .array([])])
        let remote = object(["sessions": .array([row("a", ["status": .string("done")])])])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "")
        let ids = (merged?["sessions"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
        XCTAssertEqual(ids, ["a"])
    }

    // MARK: Journaux et listes

    func testValidationLogsAreUnionedWithoutDuplicates() {
        let entry = object(["start": .number(1), "end": .number(3), "date": .string("2026-10-01")])
        let other = object(["start": .number(4), "end": .number(6), "date": .string("2026-10-02")])
        // Les trois arguments sont les TABLEAUX eux-mêmes : `merge` fusionne le
        // nœud qu'on lui passe, et `path` décrit ce nœud. Passer l'objet parent
        // tout en nommant l'enfant dans `path` faisait lire `.arrayValue` sur un
        // objet — donc `nil`, quelle que soit la fusion.
        //
        // `base` vide à dessein : `local` et `remote` diffèrent alors tous deux
        // de `base`, ce qui exerce réellement l'union. Avec `base == local`, le
        // raccourci « aucun changement local » rend `remote` directement, sans
        // jamais dédupliquer.
        let base = JSONValue.array([])
        let local = JSONValue.array([entry])
        let remote = JSONValue.array([entry, other])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "x.validations")
        XCTAssertEqual(merged?.arrayValue?.count, 2)
    }

    func testReadPagesAreUnionedAndSortedNumerically() {
        // Tri numérique, pas alphabétique : sans cela « 10 » passerait avant « 9 ».
        let base = JSONValue.array([.number(1)])
        let local = JSONValue.array([.number(10)])
        let remote = JSONValue.array([.number(9)])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "x.readPages")
        XCTAssertEqual(merged?.arrayValue?.compactMap { $0.intValue }, [9, 10])
    }

    func testCompletedVersesAreUnioned() {
        let base = JSONValue.array([.number(1)])
        let local = JSONValue.array([.number(1), .number(2)])
        let remote = JSONValue.array([.number(1), .number(3)])
        let merged = OfflineMerge.merge(base: base, local: local, remote: remote, path: "cycle.completed")
        XCTAssertEqual(merged?.arrayValue?.compactMap { $0.intValue }, [1, 2, 3])
    }

    // MARK: Point d'entrée complet

    func testMergeOfflineStateRefusesADifferentAccount() {
        // Garde-fou : on ne fusionne jamais les documents de deux comptes
        // différents. Sans cela, un changement de compte écraserait les données.
        let base = object(["userId": .string("A")])
        let local = object(["userId": .string("B"), "theme": .string("lilac")])
        let remote = object(["userId": .string("A"), "theme": .string("night")])
        let merged = OfflineMerge.mergeOfflineState(base: base, local: local, remote: remote)
        XCTAssertEqual(merged["userId"]?.stringValue, "B")
        XCTAssertEqual(merged["theme"]?.stringValue, "lilac")
    }

    func testMergeOfflineStateRespectsAnExplicitReset() {
        // L'utilisateur a remis sa progression à zéro : le document local est
        // renvoyé tel quel, sans réintroduire l'ancienne progression du serveur.
        let base = object(["userId": .string("A"), "onboardingDone": .bool(true)])
        let local = object(["userId": .string("A"), "onboardingDone": .bool(false)])
        let remote = object(["userId": .string("A"), "onboardingDone": .bool(true)])
        let merged = OfflineMerge.mergeOfflineState(base: base, local: local, remote: remote)
        XCTAssertEqual(merged["onboardingDone"]?.boolValue, false)
    }

    func testMergeOfflineStateWithoutRemoteKeepsLocal() {
        let local = object(["userId": .string("A"), "theme": .string("lilac")])
        XCTAssertEqual(
            OfflineMerge.mergeOfflineState(base: nil, local: local, remote: nil)["theme"]?.stringValue,
            "lilac"
        )
    }

    func testMergeOfflineStateAdvancesUpdatedAt() throws {
        let base = object(["userId": .string("A")])
        let local = object([
            "userId": .string("A"),
            "updatedAt": .string("2026-01-01T00:00:00.000Z"),
            "theme": .string("lilac")
        ])
        let remote = object([
            "userId": .string("A"),
            "updatedAt": .string("2026-06-01T00:00:00.000Z")
        ])
        let merged = OfflineMerge.mergeOfflineState(base: base, local: local, remote: remote)
        let result = try XCTUnwrap(merged["updatedAt"]?.stringValue.flatMap(DateKeys.parseISO))
        let remoteDate = try XCTUnwrap(DateKeys.parseISO("2026-06-01T00:00:00.000Z"))
        XCTAssertGreaterThan(result, remoteDate)
    }

    func testUnknownKeysSurviveTheMerge() {
        // Une clé ajoutée plus tard par React Native doit traverser la fusion
        // intacte : c'est toute la raison d'être de JSONValue.
        // `remote` porte volontairement une autre clé, pour que la fusion
        // descende réellement dans l'objet au lieu de prendre un raccourci.
        let base = object(["userId": .string("A"), "theme": .string("white")])
        let local = object([
            "userId": .string("A"),
            "theme": .string("white"),
            "cleInconnue": object(["profondeur": .number(42)])
        ])
        let remote = object([
            "userId": .string("A"),
            "theme": .string("white"),
            "accent": .string("gold")
        ])
        let merged = OfflineMerge.mergeOfflineState(base: base, local: local, remote: remote)
        XCTAssertEqual(merged["cleInconnue"]?["profondeur"]?.intValue, 42)
        XCTAssertEqual(merged["accent"]?.stringValue, "gold")
    }
}

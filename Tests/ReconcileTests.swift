// ReconcileTests.swift
// La réconciliation : laquelle des deux applications gagne, sur un même document.
//
// Chaque cas ci-dessous correspond à une règle de `reconcileState` /
// `accountState` — `src/core/program.ts:65-89`. Ce sont ces règles qui
// décident, à la connexion, quel document partagé l'emporte ; une divergence
// ferait perdre à l'un des deux clients ce que l'autre a écrit.
//
// Vocabulaire : local = le cache de CE compte sur cet appareil, remote = ce que
// le serveur contient maintenant. `shouldPush` dit si le résultat doit repartir
// vers le serveur.

import XCTest
@testable import Swiftdeepseek

final class ReconcileTests: XCTestCase {

    // MARK: Outils

    private func document(at iso: String, _ pairs: [String: JSONValue] = [:]) -> JSONValue {
        var fields = pairs
        fields["updatedAt"] = .string(iso)
        return .object(fields)
    }

    /// Un lecteur déjà à jour : sans lui, `migrateRaw` en ajouterait un et
    /// changerait le document sous le test.
    private let cleanReader: JSONValue = .object([
        "mushaf": .string("coranTest"),
        "followAudio": .bool(true)
    ])

    private func bookmark(_ verseID: Int, at iso: String, deleted: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "verseId": .number(Double(verseID)),
            "updatedAt": .string(iso)
        ]
        if let deleted { fields["deletedAt"] = .string(deleted) }
        return .object(fields)
    }

    // MARK: 1. Pas de distant

    func testNoRemoteKeepsTheLocalDocumentAndPushes() {
        // Le local est MIGRÉ **avant** le retour anticipé : la référence écrit
        // `local = migrateReaderState(local)` avant `if (!remote)`. Un lecteur
        // ABSENT est donc CRÉÉ — `{...undefined}` vaut `{}` en JavaScript, et
        // `undefined !== false` vaut `true`. Attendre `local` tel quel est faux,
        // et c'est ce que ce test faisait : le run n° 74 l'a mesuré.
        let local = document(at: "2024-01-01T00:00:00.000Z", ["theme": .string("night")])
        let outcome = Reconcile.reconcile(local: local, remote: nil)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "night")
        XCTAssertEqual(outcome.document["reader"]?["mushaf"]?.stringValue, "coranTest")
        XCTAssertEqual(outcome.document["reader"]?["followAudio"]?.boolValue, true)
        XCTAssertTrue(outcome.shouldPush)
    }

    // MARK: 2. La migration du lecteur, sur le document brut

    func testTheLegacyMushafKeysBecomeTheMedineSource() {
        for legacy in ["tawjeed_test_2", "tajweed_test_2", "medine_test"] {
            let local = document(at: "2024-01-01T00:00:00.000Z", [
                "reader": .object(["mushaf": .string(legacy), "followAudio": .bool(true)])
            ])
            let migrated = Reconcile.migrateRaw(local)
            XCTAssertEqual(migrated.document["reader"]?["mushaf"]?.stringValue, "coran_1441", legacy)
            XCTAssertTrue(migrated.changed, legacy)
        }
    }

    func testASessionWithoutAScheduledDateTakesItsOwnDate() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "sessions": .array([
                .object(["id": .string("a"), "date": .string("2024-03-01")]),
                .object([
                    "id": .string("b"),
                    "date": .string("2024-03-02"),
                    "scheduledDate": .string("2024-02-01")
                ])
            ])
        ])
        let migrated = Reconcile.migrateRaw(local).document
        let sessions = migrated["sessions"]?.arrayValue
        XCTAssertEqual(sessions?.count, 2)
        XCTAssertEqual(sessions?.first?["scheduledDate"]?.stringValue, "2024-03-01")
        // Une séance qui PORTE déjà sa date prévue ne bouge pas : c'est la
        // garantie produit, une séance faite en avance ne change jamais sa date.
        XCTAssertEqual(sessions?.last?["scheduledDate"]?.stringValue, "2024-02-01")
    }

    func testAnEmptyScheduledDateIsReplacedToo() {
        // Le test de l'original est celui de la VÉRITÉ, pas de la présence :
        // une chaîne vide est donc remplacée comme une clé absente.
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "sessions": .array([
                .object([
                    "id": .string("a"),
                    "date": .string("2024-03-01"),
                    "scheduledDate": .string("")
                ])
            ])
        ])
        let sessions = Reconcile.migrateRaw(local).document["sessions"]?.arrayValue
        XCTAssertEqual(sessions?.first?["scheduledDate"]?.stringValue, "2024-03-01")
    }

    func testAMissingReaderFallsBackToCoranTest() {
        let migrated = Reconcile.migrateRaw(document(at: "2024-01-01T00:00:00.000Z", [:]))
        XCTAssertEqual(migrated.document["reader"]?["mushaf"]?.stringValue, "coranTest")
        XCTAssertEqual(migrated.document["reader"]?["followAudio"]?.boolValue, true)
        XCTAssertTrue(migrated.changed)
    }

    func testFollowAudioStaysFalseOnlyWhenItWasExactlyFalse() {
        let explicit = Reconcile.migrateRaw(document(at: "2024-01-01T00:00:00.000Z", [
            "reader": .object(["followAudio": .bool(false)])
        ])).document
        XCTAssertEqual(explicit["reader"]?["followAudio"]?.boolValue, false)

        // `followAudio !== false` : un `null` n'est PAS `false`, donc il repasse
        // à `true`.
        let nulled = Reconcile.migrateRaw(document(at: "2024-01-01T00:00:00.000Z", [
            "reader": .object(["followAudio": .null])
        ])).document
        XCTAssertEqual(nulled["reader"]?["followAudio"]?.boolValue, true)
    }

    func testAnAlreadyCleanReaderIsLeftUntouched() {
        let local = document(at: "2024-01-01T00:00:00.000Z", ["reader": cleanReader])
        let migrated = Reconcile.migrateRaw(local)
        XCTAssertEqual(migrated.document, local)
        XCTAssertFalse(migrated.changed)
    }

    func testAnExplicitTajweedPagesReaderIsReplacedToo() {
        // `tajweedPages` est une préférence qui existe vraiment côté React
        // Native, et l'original la remplace : la garde est
        // `mushaf && mushaf !== 'tajweedPages'`, donc cette valeur-là tombe.
        let migrated = Reconcile.migrateRaw(document(at: "2024-01-01T00:00:00.000Z", [
            "reader": .object(["mushaf": .string("tajweedPages"), "followAudio": .bool(false)])
        ]))
        XCTAssertEqual(migrated.document["reader"]?["mushaf"]?.stringValue, "coranTest")
        XCTAssertTrue(migrated.changed)
    }

    // MARK: 3. Les marques-pages se fusionnent toujours

    func testBookmarksFromBothSidesAreUnionedAndTheNewestWins() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "bookmarks": .object(["1": bookmark(1, at: "2024-01-01T00:00:00.000Z")])
        ])
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "bookmarks": .object([
                "1": bookmark(1, at: "2024-05-01T00:00:00.000Z"),
                "2": bookmark(2, at: "2024-05-02T00:00:00.000Z")
            ])
        ])
        let bookmarks = Reconcile.reconcile(local: local, remote: remote).document["bookmarks"]
        XCTAssertEqual(
            bookmarks?["1"]?["updatedAt"]?.stringValue,
            "2024-05-01T00:00:00.000Z",
            "la version la plus récente du verset 1 est celle du serveur"
        )
        XCTAssertEqual(bookmarks?["2"]?["verseId"]?.intValue, 2, "le verset 2 n'existe que côté serveur")
    }

    func testADeletionMarkerSurvivesTheMerge() {
        // Le point de `mergeBookmarks` : une suppression laisse une marque, et
        // cette marque doit survivre même quand le document distant est plus
        // récent — sinon un appareil ressusciterait le verset.
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "bookmarks": .object([
                "7": bookmark(7, at: "2024-06-01T00:00:00.000Z", deleted: "2024-06-01T00:00:00.000Z")
            ])
        ])
        let remote = document(at: "2024-07-01T00:00:00.000Z", [
            "bookmarks": .object(["7": bookmark(7, at: "2024-05-01T00:00:00.000Z")])
        ])
        let bookmarks = Reconcile.reconcile(local: local, remote: remote).document["bookmarks"]
        XCTAssertEqual(bookmarks?["7"]?["deletedAt"]?.stringValue, "2024-06-01T00:00:00.000Z")
    }

    func testTheNotNewerRemoteStillGivesItsBookmarks() {
        // Le premier retour anticipé rend le LOCAL — mais avec les marques-pages
        // fusionnées, jamais celles du seul local.
        let local = document(at: "2024-06-01T00:00:00.000Z", [
            "bookmarks": .object(["1": bookmark(1, at: "2024-06-01T00:00:00.000Z")])
        ])
        let remote = document(at: "2024-01-01T00:00:00.000Z", [
            "bookmarks": .object(["2": bookmark(2, at: "2024-01-01T00:00:00.000Z")])
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertNotNil(outcome.document["bookmarks"]?["1"])
        XCTAssertNotNil(outcome.document["bookmarks"]?["2"])
        XCTAssertTrue(outcome.shouldPush)
    }

    // MARK: 4. Le premier retour anticipé, et son exception

    func testTheLocalWinsWhenTheRemoteIsNotNewer() {
        let local = document(at: "2024-06-01T00:00:00.000Z", [
            "theme": .string("night"),
            "knowledge": .object(["1": .string("perfect")])
        ])
        let remote = document(at: "2024-01-01T00:00:00.000Z", ["theme": .string("white")])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "night")
        XCTAssertEqual(outcome.document["knowledge"]?["1"]?.stringValue, "perfect")
        XCTAssertTrue(outcome.shouldPush)
    }

    func testAnEqualTimestampAlsoLetsTheLocalWin() {
        // La comparaison est `<=`, pas `<` : à horodatage ÉGAL, c'est le local
        // qui gagne. Sans cela, deux appareils se renverraient le document.
        let local = document(at: "2024-06-01T00:00:00.000Z", ["theme": .string("night")])
        let remote = document(at: "2024-06-01T00:00:00.000Z", ["theme": .string("white")])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "night")
        XCTAssertTrue(outcome.shouldPush)
    }

    func testTheOnboardingExceptionLetsTheRemoteWin() {
        // Un compte déjà installé ailleurs : le local n'a pas terminé
        // l'installation, le distant si. Le premier retour tombe, donc le
        // distant est adopté — et rien n'a besoin d'être poussé.
        let local = document(at: "2024-06-01T00:00:00.000Z", [
            "onboardingDone": .bool(false),
            "theme": .string("night")
        ])
        let remote = document(at: "2024-01-01T00:00:00.000Z", [
            "onboardingDone": .bool(true),
            "theme": .string("white")
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "white")
        XCTAssertFalse(outcome.shouldPush)
    }

    func testTheAdoptedRemoteCarriesTheEnrichedKeys() {
        // Le document rendu est le distant ENRICHI : `readPages` y est toujours
        // écrit, et `studyProgress` retombe sur `{}`. Ces deux clés n'étaient
        // pas dans le document reçu.
        let local = document(at: "2024-06-01T00:00:00.000Z", ["onboardingDone": .bool(false)])
        let remote = document(at: "2024-01-01T00:00:00.000Z", ["onboardingDone": .bool(true)])
        let document = Reconcile.reconcile(local: local, remote: remote).document
        XCTAssertEqual(document["readPages"]?.arrayValue?.count, 0)
        XCTAssertNotNil(document["studyProgress"])
    }

    // MARK: 5. Les métadonnées récupérées du local

    func testAnAbsentAppearanceKeyIsRecoveredFromTheLocal() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "uiFont": .string("elegant"),
            "accent": .string("gold")
        ])
        let remote = document(at: "2024-06-01T00:00:00.000Z", [:])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["uiFont"]?.stringValue, "elegant")
        XCTAssertEqual(outcome.document["accent"]?.stringValue, "gold")
        XCTAssertTrue(outcome.shouldPush, "une métadonnée récupérée doit repartir vers le serveur")
    }

    func testAnAbsentStudyProgressIsRecoveredFromTheLocal() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "studyProgress": .object(["learning:a": .object(["through": .number(3)])])
        ])
        let remote = document(at: "2024-06-01T00:00:00.000Z", [:])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["studyProgress"]?["learning:a"]?["through"]?.intValue, 3)
        XCTAssertTrue(outcome.shouldPush)
    }

    func testAnEmptyStudyProgressOnTheRemoteIsNotAnAbsentOne() {
        // `remote.studyProgress === undefined` : une carte VIDE n'est pas une
        // clé absente, donc rien n'est récupéré et rien ne force la poussée.
        let local = document(at: "1970-01-01T00:00:00.000Z", [
            "studyProgress": .object(["learning:a": .object(["through": .number(3)])])
        ])
        let remote = document(at: "1970-01-02T00:00:00.000Z", [
            "studyProgress": .object([:]),
            "reader": cleanReader
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["studyProgress"]?.objectValue?.count, 0)
        XCTAssertFalse(outcome.shouldPush)
    }

    // MARK: 6. `reviewCycle` : le ternaire qui distingue `null` d'absent

    func testANullReviewCycleIsNotAnAbsentOne() {
        // LE piège du bloc. Partout ailleurs la famille emploie `??`, qui
        // remplacerait un `null` distant par la valeur locale ; ici l'original
        // écrit `remote.reviewCycle === undefined ? local.reviewCycle : remote.reviewCycle`.
        // Un cycle remis à `null` doit donc RESTER `null`.
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "reviewCycle": .object(["index": .number(3)])
        ])
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "reviewCycle": .null,
            "reader": cleanReader
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["reviewCycle"]?.isNull, true)
    }

    func testAnAbsentReviewCycleIsRecoveredFromTheLocal() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "reviewCycle": .object(["index": .number(3)])
        ])
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "reader": cleanReader
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["reviewCycle"]?["index"]?.intValue, 3)
        XCTAssertTrue(outcome.shouldPush)
    }

    // MARK: 7. `reader.testPage`

    func testTestPageIsRecoveredOnlyWhenTheRemoteLacksIt() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "reader": .object([
                "mushaf": .string("coran_1441"),
                "followAudio": .bool(true),
                "testPage": .number(42)
            ])
        ])
        let without = document(at: "2024-06-01T00:00:00.000Z", [
            "reader": .object(["mushaf": .string("coran_1441"), "followAudio": .bool(true)])
        ])
        let recovered = Reconcile.reconcile(local: local, remote: without)
        XCTAssertEqual(recovered.document["reader"]?["testPage"]?.intValue, 42)
    }

    func testTestPageIsNotRecoveredWhenTheRemoteHasOne() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "reader": .object([
                "mushaf": .string("coran_1441"),
                "followAudio": .bool(true),
                "testPage": .number(42)
            ])
        ])
        let with = document(at: "2024-06-01T00:00:00.000Z", [
            "reader": .object([
                "mushaf": .string("coran_1441"),
                "followAudio": .bool(true),
                "testPage": .number(7)
            ])
        ])
        let kept = Reconcile.reconcile(local: local, remote: with)
        XCTAssertEqual(kept.document["reader"]?["testPage"]?.intValue, 7)
    }

    // MARK: 8. `readPages`

    func testReadPagesAreAlwaysUnionedAndWritten() {
        let local = document(at: "2024-01-01T00:00:00.000Z", [
            "readPages": .array([.number(1), .number(2)])
        ])
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "readPages": .array([.number(2)]),
            "reader": cleanReader
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        // L'ordre est celui de `Array.from(new Set([...remote, ...local]))` :
        // d'abord les pages du serveur, puis celles que le local ajoute.
        XCTAssertEqual(
            outcome.document["readPages"]?.arrayValue?.compactMap { $0.intValue },
            [2, 1]
        )
        XCTAssertTrue(outcome.shouldPush)
    }

    func testReadPagesIsWrittenEvenWhenNeitherSideHasIt() {
        let local = document(at: "1970-01-01T00:00:00.000Z", ["reader": cleanReader])
        let remote = document(at: "1970-01-02T00:00:00.000Z", ["reader": cleanReader])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["readPages"]?.arrayValue?.count, 0)
    }

    // MARK: 9. Le seul cas qui ne pousse rien

    func testAnIdenticalButOlderLocalIsNotPushed() {
        // Le distant est STRICTEMENT plus récent et contient déjà tout ce que le
        // local porte : aucune métadonnée n'est récupérée, donc rien ne part.
        // C'est le seul chemin qui rend `shouldPush: false`.
        let local = document(at: "1970-01-01T00:00:00.000Z", ["reader": cleanReader])
        let remote = document(at: "1970-01-02T00:00:00.000Z", ["reader": cleanReader])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertFalse(outcome.shouldPush)
        XCTAssertEqual(outcome.document["reader"]?["mushaf"]?.stringValue, "coranTest")
    }

    // MARK: 10. L'horodatage

    func testTheNewTimestampIsStrictlyGreaterThanBoth() {
        // Le local doit porter quelque chose que le distant N'A PAS — ici une
        // police. `theme` ne conviendrait pas : le distant l'emporte toujours
        // (`remote.theme ?? local.theme`), donc la comparaison des quinze
        // champs serait vraie et le retour anticipé « rien à pousser » tomberait
        // AVANT que l'horodatage soit recalculé.
        let local = document(at: "1970-01-01T00:00:00.000Z", ["uiFont": .string("elegant")])
        let remote = document(at: "1970-01-02T00:00:00.000Z", [
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let stamp = Reconcile.reconcile(local: local, remote: remote)
            .document["updatedAt"]?.stringValue
        XCTAssertNotNil(stamp)
        XCTAssertEqual(Reconcile.utf16Compare(stamp!, "1970-01-02T00:00:00.000Z"), 1)
        XCTAssertEqual(Reconcile.utf16Compare(stamp!, "1970-01-01T00:00:00.000Z"), 1)
    }

    func testTheNewTimestampIsOneMillisecondPastAFutureRemote() {
        // `Math.max(now, remote + 1, local + 1)` : un distant daté du futur
        // donne `remote + 1` milliseconde, et non « maintenant ».
        //
        // Le local porte une police que le distant n'a pas : c'est ce qui fait
        // tomber le retour anticipé « rien à pousser », donc ce qui fait
        // RECALCULER l'horodatage. Sans elle, le test mesurerait la valeur brute
        // du distant — et l'oracle du banc l'a montré.
        let local = document(at: "1970-01-01T00:00:00.000Z", ["uiFont": .string("elegant")])
        let remote = document(at: "2999-01-01T00:00:00.000Z", [
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let stamp = Reconcile.reconcile(local: local, remote: remote)
            .document["updatedAt"]?.stringValue
        XCTAssertEqual(stamp, "2999-01-01T00:00:00.001Z")
    }

    func testAnUnparseableTimestampIsIgnored() {
        // DIVERGENCE ASSUMÉE, et elle est ici pour être vue : l'original fait
        // `Date.parse(remote.updatedAt)` et lève un `RangeError` sur une date
        // illisible — `Math.max(now, NaN)` vaut NaN, et `new Date(NaN)`
        // n'a pas d'ISO. Le portage ignore l'horodatage illisible. Le reste de
        // la réconciliation est identique, et c'est ce que ce test épingle.
        let local = document(at: "1970-01-01T00:00:00.000Z", ["theme": .string("night")])
        let remote = document(at: "pas-une-date", [
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "white")
        XCTAssertEqual(
            Reconcile.utf16Compare(
                outcome.document["updatedAt"]?.stringValue ?? "",
                "1970-01-01T00:00:00.000Z"
            ),
            1
        )
    }

    // MARK: 11. Une clé sans valeur disparaît, elle ne devient pas `null`

    func testAKeyWithoutAValueIsRemovedRatherThanNulled() {
        // `profile: null` d'un côté, absent de l'autre : `null ?? undefined`
        // vaut `undefined`, et une clé `undefined` ne se sérialise pas.
        let local = document(at: "1970-01-01T00:00:00.000Z", [:])
        let remote = document(at: "1970-01-02T00:00:00.000Z", [
            "profile": .null,
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertNil(outcome.document["profile"])
        XCTAssertNil(outcome.document["uiFont"], "l'enrichissement ne crée pas de clé vide")
    }

    func testANullFromTheLocalIsWrittenAsIs() {
        // L'opérande DROIT de `??` est rendu verbatim : si le distant n'a rien
        // et que le local vaut `null`, c'est `null` qui s'écrit.
        let local = document(at: "1970-01-01T00:00:00.000Z", ["profile": .null])
        let remote = document(at: "1970-01-02T00:00:00.000Z", [
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let outcome = Reconcile.reconcile(local: local, remote: remote)
        XCTAssertEqual(outcome.document["profile"]?.isNull, true)
    }

    // MARK: 12. Le document par défaut

    func testTheDefaultDocumentCarriesTheTwentyFourKeysOfTheReference() {
        let keys = Set(Reconcile.defaultDocument().objectValue?.keys ?? [:].keys)
        XCTAssertEqual(keys.count, 24)
        XCTAssertEqual(
            keys,
            Set([
                "schema", "onboardingDone", "updatedAt", "knowledge", "goal", "pace",
                "learningDays", "sessions", "revisions", "memorizedAt", "reviewSettings",
                "reviewHistory", "reviewDue", "difficultyMarkers", "difficultyHistory",
                "reviewCycle", "reviewConsolidations", "reviewPriorityDue",
                "reviewCycleHistory", "consolidationHistory", "studyProgress",
                "theme", "notifications", "reader"
            ])
        )
        XCTAssertEqual(Reconcile.defaultDocument()["pace"]?.stringValue, "verse3")
        XCTAssertEqual(Reconcile.defaultDocument()["reader"]?["mushaf"]?.stringValue, "coranTest")
        XCTAssertEqual(Reconcile.defaultDocument()["reviewCycle"]?.isNull, true)
        XCTAssertEqual(
            Reconcile.defaultDocument()["updatedAt"]?.stringValue,
            "1970-01-01T00:00:00.000Z"
        )
    }

    func testTheRawDefaultIsNotTheTypedDefault() throws {
        // La sérialisation de `Program.defaultState()` **OMET** une propriété
        // optionnelle nulle — `Codable` synthétisé passe par `encodeIfPresent`
        // —, là où l'original ÉCRIT `reviewCycle: null`. La distinction décide :
        // `reconcileState` teste `remote.reviewCycle === undefined`, donc une clé
        // ABSENTE est remplacée par la valeur locale, et un `null` explicite est
        // CONSERVÉ. C'est le document brut, et lui seul, qui écrit ce `null`.
        //
        // Le run n° 74 a mesuré le CONTRAIRE de ce que ce test affirmait : le
        // typé n'écrit aucun `null`. Les deux attentes sont donc retournées.
        let typed = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(Program.defaultState())
        )
        XCTAssertNil(typed["uiFont"], "le typé n'écrit pas une clé optionnelle nulle")
        XCTAssertNil(typed["reviewCycle"], "le typé OMET le `null` de l'original")
        XCTAssertEqual(
            Reconcile.defaultDocument()["reviewCycle"]?.isNull,
            true,
            "le document brut ÉCRIT le `null` de l'original"
        )
        XCTAssertNil(Reconcile.defaultDocument()["uiFont"], "et il n'ajoute pas les clés absentes")
        XCTAssertNotEqual(typed, Reconcile.defaultDocument())
    }

    // MARK: 13. Le compte

    func testAccountStateIgnoresACacheFromAnotherAccount() {
        let cache = document(at: "2024-01-01T00:00:00.000Z", [
            "userId": .string("autre"),
            "theme": .string("night")
        ])
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "userId": .string("moi"),
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let outcome = Reconcile.accountState(userId: "moi", cache: cache, remote: remote)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "white")
        XCTAssertEqual(outcome.document["userId"]?.stringValue, "moi")
        XCTAssertFalse(outcome.shouldPush)
    }

    func testAccountStateAdoptsAForeignRemoteWhenThereIsNoCache() {
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "userId": .string("moi"),
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let outcome = Reconcile.accountState(userId: "moi", cache: nil, remote: remote)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "white")
        XCTAssertFalse(outcome.shouldPush)
    }

    func testAccountStateIgnoresARemoteFromAnotherAccount() {
        let cache = document(at: "2024-06-01T00:00:00.000Z", [
            "userId": .string("moi"),
            "theme": .string("night"),
            "reader": cleanReader
        ])
        let remote = document(at: "2024-07-01T00:00:00.000Z", [
            "userId": .string("autre"),
            "theme": .string("white")
        ])
        let outcome = Reconcile.accountState(userId: "moi", cache: cache, remote: remote)
        XCTAssertEqual(outcome.document["theme"]?.stringValue, "night")
        XCTAssertEqual(outcome.document["userId"]?.stringValue, "moi")
    }

    func testAccountStatePushesARemoteThatDoesNotCarryTheUserId() {
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "theme": .string("white"),
            "reader": cleanReader
        ])
        let outcome = Reconcile.accountState(userId: "moi", cache: nil, remote: remote)
        XCTAssertEqual(outcome.document["userId"]?.stringValue, "moi")
        XCTAssertTrue(outcome.shouldPush)
    }

    func testAccountStatePushesWhenTheRemoteNeededMigrating() {
        // `safeRemote !== remote` : la migration a construit un objet neuf, donc
        // le document rendu n'est pas celui du serveur — il faut le pousser.
        let remote = document(at: "2024-06-01T00:00:00.000Z", [
            "userId": .string("moi"),
            "theme": .string("white")
        ])
        let outcome = Reconcile.accountState(userId: "moi", cache: nil, remote: remote)
        XCTAssertEqual(outcome.document["reader"]?["mushaf"]?.stringValue, "coranTest")
        XCTAssertTrue(outcome.shouldPush)
    }

    // MARK: 14. La comparaison de chaînes

    func testTheStringComparisonCountsUTF16CodeUnits() {
        XCTAssertEqual(Reconcile.utf16Compare("a", "a"), 0)
        XCTAssertEqual(Reconcile.utf16Compare("a", "b"), -1)
        XCTAssertEqual(Reconcile.utf16Compare("b", "a"), 1)
        XCTAssertEqual(Reconcile.utf16Compare("a", "ab"), -1, "un préfixe est plus petit")
        XCTAssertEqual(Reconcile.utf16Compare("2024-01-01", "2024-01-01T00:00:00.000Z"), -1)
        // En TEXTE, « 9 » vient après « 10 » : c'est la comparaison de l'original,
        // qui compare deux chaînes et non deux dates.
        XCTAssertEqual(Reconcile.utf16Compare("9", "10"), 1)
        XCTAssertEqual(Reconcile.utf16Compare("\u{2019}", "'"), 1)
    }

    // MARK: 15. `truthy` et `nullish`

    func testTheJavaScriptTruthiness() {
        XCTAssertFalse(Reconcile.truthy(nil))
        XCTAssertFalse(Reconcile.truthy(.null))
        XCTAssertFalse(Reconcile.truthy(.bool(false)))
        XCTAssertFalse(Reconcile.truthy(.number(0)))
        XCTAssertFalse(Reconcile.truthy(.string("")))
        XCTAssertTrue(Reconcile.truthy(.bool(true)))
        XCTAssertTrue(Reconcile.truthy(.number(1)))
        XCTAssertTrue(Reconcile.truthy(.string("x")))
        XCTAssertTrue(Reconcile.truthy(.object([:])))
        XCTAssertTrue(Reconcile.truthy(.array([])))
    }

    func testTheNullishFallbackTriggersOnNullAndOnAbsence() {
        XCTAssertNil(Reconcile.nullish(nil))
        XCTAssertNil(Reconcile.nullish(.null))
        XCTAssertEqual(Reconcile.nullish(.string("x"))?.stringValue, "x")
        // `coalesce` rend l'opérande droit TEL QUEL — c'est ce qui fait écrire
        // un `null` local là où `nullish` l'aurait effacé.
        XCTAssertNil(Reconcile.coalesce(nil, nil))
        XCTAssertEqual(Reconcile.coalesce(.null, .null)?.isNull, true)
        XCTAssertEqual(Reconcile.coalesce(.string("gauche"), .string("droite"))?.stringValue, "gauche")
    }

    // MARK: 16. L'accord entre les deux jumelles

    /// Deux implémentations de la MÊME règle coexistent : `Bookmark.merge`, sur
    /// les structs, et `Reconcile.mergeBookmarksRaw`, sur le document.
    ///
    /// La seconde est celle que la réconciliation emploie : elle ne ré-encode
    /// pas un document qu'elle s'apprête à écrire, et elle préserve les champs
    /// d'une entrée qu'une version future ajouterait — là où passer par les
    /// structs les supprimerait silencieusement. Les tenir en accord est le seul
    /// moyen qu'elles ne divergent pas, et c'est le rôle de ce test.
    func testTheRawBookmarkMergeAgreesWithTheTypedOne() throws {
        let pairs: [(first: [String: VerseBookmark]?, second: [String: VerseBookmark]?)] = [
            (nil, nil),
            (nil, [:]),
            ([:], nil),
            (["1": model(1, at: "2024-01-01T00:00:00.000Z")], nil),
            (
                ["1": model(1, at: "2024-01-01T00:00:00.000Z")],
                [
                    "1": model(1, at: "2024-05-01T00:00:00.000Z"),
                    "2": model(2, at: "2024-05-02T00:00:00.000Z")
                ]
            ),
            (
                ["7": model(7, at: "2024-06-01T00:00:00.000Z", deleted: "2024-06-01T00:00:00.000Z")],
                ["7": model(7, at: "2024-05-01T00:00:00.000Z")]
            )
        ]
        var compared = 0
        for pair in pairs {
            let typed = Bookmark.merge(pair.first, pair.second)
            let raw = Reconcile.mergeBookmarksRaw(try encode(pair.first), try encode(pair.second))
            compared += 1
            XCTAssertEqual(try decodeBookmarks(raw), typed)
        }
        XCTAssertEqual(compared, pairs.count, "aucune paire comparée : le test serait vide")
    }

    /// Même accord, sur `migrateReaderState` : `Program.migrateReaderState`
    /// opère sur les structs, `Reconcile.migrateRaw` sur le document brut.
    ///
    /// C'est ce test qui a fait voir le défaut corrigé dans `Program` : la
    /// version typée ne CRÉAIT pas le lecteur quand il manquait, là où
    /// l'original — et la version brute — le créent.
    ///
    /// Un `reader` sans `mushaf` ne figure pas ci-dessous : `mushaf` est une
    /// `String` NON optionnelle du modèle typé, donc un tel document ne décode
    /// pas et n'atteint jamais `Program.migrateReaderState`.
    func testTheRawReaderMigrationAgreesWithTheTypedOne() throws {
        let base = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(Program.defaultState())
        )
        let readers: [JSONValue?] = [
            .object(["mushaf": .string("tawjeed_test_2"), "followAudio": .bool(true)]),
            .object(["mushaf": .string("tajweed_test_2"), "followAudio": .bool(false)]),
            .object(["mushaf": .string("tajweedPages"), "followAudio": .bool(false)]),
            .object(["mushaf": .string("coran_1441"), "followAudio": .bool(false)]),
            .object(["mushaf": .string("coranTest"), "followAudio": .bool(true)]),
            .null,
            nil
        ]
        var compared = 0
        for reader in readers {
            var input = base
            input["reader"] = reader
            guard let typed = AppState.decode(from: input) else { continue }
            compared += 1
            let migrated = Reconcile.migrateRaw(input).document
            XCTAssertEqual(
                AppState.decode(from: migrated),
                Program.migrateReaderState(typed),
                "désaccord sur le lecteur \(String(describing: reader))"
            )
        }
        XCTAssertEqual(compared, readers.count, "aucun document comparé : le test serait vide")
    }

    // MARK: Outils des tests d'accord

    private func model(_ verseID: Int, at iso: String, deleted: String? = nil) -> VerseBookmark {
        VerseBookmark(
            verseId: verseID,
            surah: 1,
            ayah: verseID,
            page: 1,
            sourcePages: nil,
            createdAt: iso,
            updatedAt: iso,
            lastUsedAt: nil,
            deletedAt: deleted
        )
    }

    private func encode(_ bookmarks: [String: VerseBookmark]?) throws -> JSONValue? {
        guard let bookmarks else { return nil }
        return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(bookmarks))
    }

    private func decodeBookmarks(_ value: JSONValue?) throws -> [String: VerseBookmark]? {
        guard let value else { return nil }
        return try JSONDecoder().decode(
            [String: VerseBookmark].self,
            from: JSONEncoder().encode(value)
        )
    }
}

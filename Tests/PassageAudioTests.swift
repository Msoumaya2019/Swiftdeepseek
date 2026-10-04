// PassageAudioTests.swift
// Le moteur de répétition d'un passage, et la lecture d'une sourate entière.
//
// POURQUOI CES TESTS EXISTENT
//   `src/core/audio.ts` tient la répétition dans une fonction de quinze lignes
//   (`nextAudioPosition`) dont trois règles sont **silencieuses** : s'y tromper
//   ne lève aucune erreur, cela répète seulement un passage une fois de trop, ou
//   l'arrête une fois trop tôt.
//     1. le nombre de répétitions est normalisé **ailleurs**, dans
//        `PassageAudioPlayer.tsx:79` — jamais dans `nextAudioPosition`, dont le
//        plancher interne est donc inatteignable depuis l'interface ;
//     2. en mode « passage », avancer d'un verset **conserve** le compteur de
//        répétition : une répétition compte des **passages entiers**, pas des
//        versets ;
//     3. en mode « verset par verset », `continuous` ne fait **jamais** avancer
//        le verset.
//
//   Et l'attente avant de rejouer (`PassageAudioPlayer.tsx:194-196`) en cache une
//   quatrième : la marge technique de 200 ms est un **plancher**, et le silence
//   choisi par l'utilisateur ne s'y ajoute QUE sur un redémarrage de passage ou
//   sur un verset répété — jamais entre deux versets qui s'enchaînent.
//
// LES VALEURS ATTENDUES SONT MESURÉES, PAS DÉDUITES DU CODE
//   Tous les nombres de ce fichier viennent de `_banc/oracle-audio.mjs`. Ce banc
//   ne réécrit pas l'original : il l'**empaquette** avec `esbuild` — résolution
//   des imports comprise, `quran.ts` et les fichiers JSON inclus — et il le fait
//   tourner. Puis il compare, cas par cas, la formulation du portage à celle de
//   l'original : 560 cas pour la table de décision, 96 pour l'attente, 90 pour
//   l'avance d'affichage. Les deux règles qui vivent HORS de `core/audio.ts`
//   (la normalisation et l'attente) sont extraites **textuellement** du fichier
//   `PassageAudioPlayer.tsx`, avec un garde-fou qui refuse de compter si la
//   forme change.
//
//   Le banc vérifie enfin que les lignes décisives du portage sont bien
//   présentes dans `Core/PassageAudio.swift`, et **dans l'ordre** : c'est le seul
//   contrôle qui relie la translittération du banc au Swift, deux sources qui ne
//   peuvent pas se lire l'une l'autre. `_banc/falsifier-audio.mjs` montre que le
//   banc devient rouge sur neuf mutations, dont cinq du Swift et trois de sa
//   translittération.
//
//   Les dériver du code testé reviendrait à comparer le code à lui-même.

import XCTest
@testable import Swiftdeepseek

final class PassageAudioTests: XCTestCase {

    // MARK: Outils

    /// La plage de référence des mesures figées : les trois premiers versets.
    private let range = VerseRange(start: 1, end: 3)

    private func position(_ verseID: Int, _ repetition: Int) -> AudioPosition {
        AudioPosition(verseID: verseID, repetition: repetition)
    }

    /// Un fichier `audio_file` bien formé : `audio_url` en `https`, et un
    /// horodatage par verset d'Al-Fâtiha.
    ///
    /// Le littéral est annoté `[String: Any]` : sans l'annotation, Swift
    /// inférerait `[String: String]` pour un dictionnaire à une seule clé, et
    /// `JSONValue.from` ne verrait plus un objet.
    private func chapterFile(
        _ entries: [[String: Any]],
        url: String = "https://example.invalid/1.mp3"
    ) -> JSONValue {
        JSONValue.from(["audio_url": url, "timestamps": entries] as [String: Any])
    }

    private func alFatihaEntries() -> [[String: Any]] {
        (1...7).map { verse -> [String: Any] in
            [
                "verse_key": "1:\(verse)",
                "timestamp_from": (verse - 1) * 1000,
                "timestamp_to": verse * 1000,
            ]
        }
    }

    private func messageOf(_ body: () throws -> Void) -> String? {
        do { try body(); return nil } catch let error as PassageAudioError { return error.message } catch { return "\(error)" }
    }

    // MARK: Les trois règles silencieuses de `nextAudioPosition`

    /// Règle 2 : en mode « passage », avancer d'un verset **conserve** la
    /// répétition. Une répétition compte donc des passages entiers.
    func testThePassageModeAdvancesTheVerseAndKeepsTheRepetition() throws {
        let next = try PassageAudio.next(
            range: range, current: position(1, 2), mode: .passage, count: .times(3)
        )
        XCTAssertEqual(next, position(2, 2))
    }

    /// Le corollaire, mesuré : revenir au premier verset est ce qui **incrémente**
    /// le compteur. Avec un compte de 3 et un seul passage fait, le prochain
    /// passage est le deuxième.
    func testInPassageModeTheCounterCountsWholePassages() throws {
        XCTAssertEqual(
            try PassageAudio.next(range: range, current: position(3, 1), mode: .passage, count: .times(3)),
            position(1, 2)
        )
    }

    /// Règle 3 : en mode « verset par verset », `continuous` ne change **jamais**
    /// de verset — même après quarante répétitions.
    func testInVerseModeContinuousNeverLeavesTheVerse() throws {
        XCTAssertEqual(
            try PassageAudio.next(range: range, current: position(2, 40), mode: .eachVerse, count: .continuous),
            position(2, 41)
        )
    }

    /// Le pendant : dès que le compte est atteint, le verset suivant commence à
    /// sa **première** répétition — le compteur ne se reporte pas d'un verset à
    /// l'autre, contrairement au mode « passage ».
    func testInVerseModeTheCounterAdvancesTheVerseAtTheEnd() throws {
        XCTAssertEqual(
            try PassageAudio.next(range: range, current: position(1, 3), mode: .eachVerse, count: .times(3)),
            position(2, 1)
        )
        XCTAssertEqual(
            try PassageAudio.next(range: range, current: position(2, 2), mode: .eachVerse, count: .times(3)),
            position(2, 3)
        )
    }

    // MARK: La table de décision figée

    /// Les huit lignes que le banc imprime, à la position `{v3, r3}` — le dernier
    /// verset de la plage, à sa troisième répétition. C'est là que les deux modes
    /// se séparent le plus nettement.
    func testTheEightFrozenLinesOfTheDecisionTable() throws {
        let last = position(3, 3)
        let cases: [(RepeatMode, RepeatCount, Bool, AudioPosition?)] = [
            (.passage, .times(3), true, nil),
            (.passage, .times(1), true, nil),
            (.passage, .times(3), false, position(1, 4)),
            (.passage, .continuous, true, position(1, 4)),
            (.eachVerse, .times(3), true, nil),
            (.eachVerse, .times(1), true, nil),
            (.eachVerse, .continuous, true, position(3, 4)),
            (.eachVerse, .times(3), false, position(1, 1)),
        ]
        for (mode, count, autoStop, expected) in cases {
            let next = try PassageAudio.next(
                range: range, current: last, mode: mode, count: count, autoStop: autoStop
            )
            XCTAssertEqual(next, expected, "\(mode) \(count) autoStop=\(autoStop)")
        }
    }

    /// Les lignes figées complémentaires, sur d'autres positions.
    func testTheComplementaryFrozenLines() throws {
        let cases: [(RepeatMode, RepeatCount, Bool, AudioPosition, AudioPosition?)] = [
            (.passage, .times(3), true, position(1, 2), position(2, 2)),
            (.passage, .times(2), true, position(3, 2), nil),
            (.eachVerse, .times(2), true, position(3, 2), nil),
            (.eachVerse, .times(2), false, position(3, 2), position(1, 1)),
            (.eachVerse, .continuous, false, position(2, 40), position(2, 41)),
        ]
        for (mode, count, autoStop, current, expected) in cases {
            let next = try PassageAudio.next(
                range: range, current: current, mode: mode, count: count, autoStop: autoStop
            )
            XCTAssertEqual(next, expected, "\(mode) \(count) autoStop=\(autoStop) \(current)")
        }
    }

    /// Les deux refus, avec les messages de l'original — ils remontent jusqu'à
    /// l'utilisateur.
    func testNextRejectsAPositionOutsideTheRange() {
        for current in [position(0, 1), position(4, 1), position(1, 0)] {
            let message = messageOf {
                _ = try PassageAudio.next(range: self.range, current: current, mode: .passage, count: .times(3))
            }
            XCTAssertEqual(message, "Position audio invalide.", "\(current)")
        }
    }

    func testNextRejectsAnInvalidRange() {
        let message = messageOf {
            _ = try PassageAudio.next(
                range: VerseRange(start: 3, end: 1), current: position(2, 1), mode: .passage, count: .times(3)
            )
        }
        XCTAssertEqual(message, "Choisis une plage de versets valide.")
    }

    // MARK: L'attente avant de rejouer

    /// La marge technique de 200 ms est un **plancher** : sans silence choisi,
    /// l'attente vaut 200 ms dans les trois cas, y compris un redémarrage.
    func testTheTechnicalGapIsAFloor() {
        let current = position(1, 1)
        XCTAssertEqual(
            PassageAudio.waitMilliseconds(from: current, to: position(2, 1), range: range, mode: .passage, gapSeconds: 0),
            200
        )
        XCTAssertEqual(
            PassageAudio.waitMilliseconds(from: position(3, 1), to: position(1, 2), range: range, mode: .passage, gapSeconds: 0),
            200
        )
    }

    /// Le point qu'on ne devine pas : avec un silence de 10 s, l'attente vaut
    /// 10 000 ms sur un **redémarrage** de passage et sur un **verset répété**,
    /// mais reste à 200 ms entre deux versets qui s'enchaînent.
    func testTheChosenSilenceAppliesOnlyOnARestartOrARepeatedVerse() {
        let enchainement = PassageAudio.waitMilliseconds(
            from: position(1, 1), to: position(2, 1), range: range, mode: .passage, gapSeconds: 10
        )
        let redemarrage = PassageAudio.waitMilliseconds(
            from: position(3, 1), to: position(1, 2), range: range, mode: .passage, gapSeconds: 10
        )
        let repete = PassageAudio.waitMilliseconds(
            from: position(1, 1), to: position(1, 2), range: range, mode: .eachVerse, gapSeconds: 10
        )
        XCTAssertEqual(enchainement, 200)
        XCTAssertEqual(redemarrage, 10_000)
        XCTAssertEqual(repete, 10_000)
    }

    // MARK: Le contrat réel du nombre de répétitions

    /// `normalizedCount` est la normalisation de `PassageAudioPlayer.tsx:79`, où
    /// l'original la cache. Un entier non strictement positif devient `1` ; un
    /// entier positif est laissé tel quel.
    func testTheCountNormalisationIsThePlayersContract() {
        XCTAssertEqual(PassageAudio.normalizedCount(.times(1)), .times(1))
        XCTAssertEqual(PassageAudio.normalizedCount(.times(2)), .times(2))
        XCTAssertEqual(PassageAudio.normalizedCount(.times(3)), .times(3))
        XCTAssertEqual(PassageAudio.normalizedCount(.times(0)), .times(1))
        XCTAssertEqual(PassageAudio.normalizedCount(.times(-1)), .times(1))
        XCTAssertEqual(PassageAudio.normalizedCount(.times(-2)), .times(1))
        XCTAssertEqual(PassageAudio.normalizedCount(.continuous), .continuous)
    }

    // MARK: Le parseur d'horodatages

    /// Al-Fâtiha compte sept versets, et un fichier valide est accepté avec ses
    /// bornes converties en **secondes** — l'original divise par 1000.
    func testAValidChapterFileIsAccepted() throws {
        XCTAssertEqual(Quran.surahs[0].count, 7)
        let audio = try PassageAudio.parse(file: chapterFile(alFatihaEntries()), chapter: 1)
        XCTAssertEqual(audio.url, "https://example.invalid/1.mp3")
        XCTAssertEqual(audio.verses.count, 7)
        XCTAssertEqual(audio.verses[1], ChapterAudio.Span(start: 0, end: 1))
        XCTAssertEqual(audio.verses[7], ChapterAudio.Span(start: 6, end: 7))
    }

    /// Les refus, avec les messages exacts de l'original : trois messages, et
    /// l'ordre dans lequel ils tombent.
    func testTheRejectionMessagesAreThoseOfTheOriginal() {
        let absent = "Timestamps audio absents."
        let invalid = "Timestamps audio invalides."
        let incomplete = "Timestamps incomplets."

        // Une mutation du fichier, et le message attendu.
        //
        // La fermeture est le DERNIER paramètre : une fermeture terminale se lie
        // au dernier paramètre de la fonction, et une version antérieure qui
        // plaçait `expected` après elle ne compilait pas.
        func check(_ label: String, _ expected: String, _ mutate: (inout [[String: Any]]) -> Void) {
            var entries = alFatihaEntries()
            mutate(&entries)
            let message = self.messageOf { _ = try PassageAudio.parse(file: self.chapterFile(entries), chapter: 1) }
            XCTAssertEqual(message, expected, label)
        }

        // Le fichier entier est refusé avant même de lire les horodatages.
        XCTAssertEqual(
            messageOf { _ = try PassageAudio.parse(file: self.chapterFile(alFatihaEntries(), url: "http://example.invalid/1.mp3"), chapter: 1) },
            absent, "url non https"
        )
        XCTAssertEqual(
            messageOf { _ = try PassageAudio.parse(file: JSONValue.from(["audio_url": "https://example.invalid/1.mp3"] as [String: Any]), chapter: 1) },
            absent, "timestamps absents"
        )
        XCTAssertEqual(
            messageOf { _ = try PassageAudio.parse(file: JSONValue.from(["audio_url": "https://example.invalid/1.mp3", "timestamps": [String: Any]()] as [String: Any]), chapter: 1) },
            absent, "timestamps non tableau"
        )
        XCTAssertEqual(
            messageOf { _ = try PassageAudio.parse(file: self.chapterFile(alFatihaEntries()), chapter: 115) },
            absent, "sourate inexistante"
        )

        check("clé sans deux-points", invalid) { $0[0]["verse_key"] = "1" }
        check("clé d'une autre sourate", invalid) { $0[0]["verse_key"] = "2:1" }
        check("verset hors bornes", invalid) { $0[0]["verse_key"] = "1:99" }
        check("clé dupliquée", invalid) { $0[1]["verse_key"] = "1:1" }
        check("from non décroissant", invalid) { $0[2]["timestamp_from"] = 0 }
        // `to` reçoit la valeur de `from` du MÊME enregistrement : l'extraire en
        // `Int` évite de faire passer un `Optional` dans le dictionnaire, où
        // `JSONValue.from` ne le reconnaîtrait plus comme un nombre.
        check("to <= from", invalid) { entries in
            let from = entries[3]["timestamp_from"] as? Int ?? 0
            entries[3]["timestamp_to"] = from
        }
        check("bornes manquantes", invalid) { entries in
            _ = entries[4].removeValue(forKey: "timestamp_to")
        }
        check("horodatages incomplets", incomplete) { entries in
            _ = entries.removeLast()
        }

        // Les trois messages doivent tous être atteints : un banc qui n'en
        // atteindrait qu'un ne prouverait rien des deux autres.
        XCTAssertNotEqual(absent, invalid)
        XCTAssertNotEqual(invalid, incomplete)
    }

    /// Un comportement que l'on ne devine pas : `String(t.verse_key).split(':')`
    /// puis la déstructuration `[s, a]` **ignorent** les composantes au-delà de
    /// la deuxième. Une clé à trois composantes est donc acceptée.
    func testAThreeComponentKeyIsAccepted() throws {
        var entries = alFatihaEntries()
        entries[0]["verse_key"] = "1:1:9"
        let audio = try PassageAudio.parse(file: chapterFile(entries), chapter: 1)
        XCTAssertEqual(audio.verses.count, 7)
        XCTAssertEqual(audio.verses[1], ChapterAudio.Span(start: 0, end: 1))
    }

    /// Et l'unique DIVERGENCE VOULUE du portage : `Number('1.5')` vaut 1,5, et
    /// `verseId(1, 1.5)` rend `start + 1,5 - 1 = 1,5`. L'original n'exige nulle
    /// part un entier : il accepte donc un identifiant de verset fractionnaire,
    /// et la clé `1.5` compte comme un verset de plus. Le portage, dont le type
    /// est `Int`, le refuse — un verset fractionnaire ne désigne rien.
    func testAFractionalKeyIsRejectedWhereTheOriginalAcceptsIt() {
        var entries = alFatihaEntries()
        entries[0]["verse_key"] = "1:1.5"
        let message = messageOf { _ = try PassageAudio.parse(file: self.chapterFile(entries), chapter: 1) }
        XCTAssertEqual(message, "Timestamps audio invalides.")
    }

    // MARK: Les récitateurs à horodatages de sourate

    /// `chapterIds` de `quranAudioTimeline.ts:5` : seuls **quatre** récitateurs
    /// ont un fichier de sourate horodaté. Le récitateur **par défaut** — Abu
    /// Bakr Shatri, `reciters[3]` — en fait partie ; les autres retombent sur
    /// leurs fichiers par verset.
    func testOnlyFourRecitersHaveChapterTimestamps() {
        XCTAssertEqual(PassageAudio.chapterResourceIDs.count, 4)
        XCTAssertEqual(PassageAudio.chapterResourceID(for: "ar.husary"), 6)
        XCTAssertEqual(PassageAudio.chapterResourceID(for: "ar.alafasy"), 7)
        XCTAssertEqual(PassageAudio.chapterResourceID(for: "ar.minshawi"), 9)
        XCTAssertEqual(PassageAudio.chapterResourceID(for: "ar.shaatree"), 4)
        XCTAssertNil(PassageAudio.chapterResourceID(for: "ar.ghamidi"))
        XCTAssertNotNil(PassageAudio.chapterResourceID(for: "ar.shaatree"))
    }

    // MARK: La plage

    func testTheRangeRejectsOutOfBounds() throws {
        for (start, end) in [(1, 1), (1, 6236), (6236, 6236), (2, 5)] {
            XCTAssertEqual(try PassageAudio.range(start: start, end: end), VerseRange(start: start, end: end))
        }
        for (start, end) in [(0, 5), (1, 6237), (5, 2), (-1, 1)] {
            let message = messageOf { _ = try PassageAudio.range(start: start, end: end) }
            XCTAssertEqual(message, "Choisis une plage de versets valide.", "\(start)…\(end)")
        }
    }

    // MARK: L'avance d'affichage (lecture d'une sourate entière)

    private func chapter(_ spans: [(Int, Double, Double)]) -> ChapterAudio {
        var verses: [Int: ChapterAudio.Span] = [:]
        for (identifier, start, end) in spans {
            verses[identifier] = ChapterAudio.Span(start: start, end: end)
        }
        return ChapterAudio(url: "https://example.invalid/1.mp3", verses: verses)
    }

    /// La plage borne l'avance, **même** quand les horodatages continuent
    /// au-delà : c'est le point que la falsification a mis au jour, deux bornes
    /// qui coïncidaient dans un premier banc.
    func testContinuousAdvanceStopsAtTheRangeEndEvenWhenTimestampsContinue() {
        let wider = chapter([(1, 0, 1), (2, 1, 2), (3, 2, 3), (4, 3, 4)])
        let next = PassageAudio.continuous(
            timeline: wider, range: VerseRange(start: 1, end: 2), position: position(1, 1), time: 99
        )
        XCTAssertEqual(next, position(2, 1))
    }

    /// Un trou dans les horodatages arrête l'avance : la boucle de l'original
    /// s'arrête dès que le verset suivant n'est pas dans la table.
    func testContinuousAdvanceStopsAtAHoleInTheTimestamps() {
        let holed = chapter([(1, 0, 1), (3, 2, 3)])
        let next = PassageAudio.continuous(
            timeline: holed, range: range, position: position(1, 1), time: 99
        )
        XCTAssertEqual(next, position(1, 1))
    }

    /// Et l'avance est bien gouvernée par l'horodatage : au temps 2, le verset 3
    /// est atteint ; au temps 1, on s'arrête au verset 2.
    func testContinuousAdvanceFollowsTheTimestamps() {
        let full = chapter([(1, 0, 1), (2, 1, 2), (3, 2, 3)])
        XCTAssertEqual(
            PassageAudio.continuous(timeline: full, range: range, position: position(1, 1), time: 2),
            position(3, 1)
        )
        XCTAssertEqual(
            PassageAudio.continuous(timeline: full, range: range, position: position(1, 1), time: 1),
            position(2, 1)
        )
    }

    // MARK: La validité d'un fichier de sourate en cache

    /// Un cache dont une seule borne est fausse est jeté et rechargé : c'est
    /// cette condition, et non la seule présence du fichier, qui décide.
    func testACachedChapterIsKeptOnlyWhenEverySpanIsUsable() {
        func seven() -> ChapterAudio {
            chapter((1...7).map { ($0, Double($0 - 1), Double($0)) })
        }

        XCTAssertTrue(PassageAudio.isUsableCachedChapter(seven(), verseID: 1, chapterNumber: 1))
        XCTAssertFalse(PassageAudio.isUsableCachedChapter(
            ChapterAudio(url: "http://example.invalid/1.mp3", verses: seven().verses),
            verseID: 1, chapterNumber: 1
        ), "url non https")

        var missing = seven().verses
        missing.removeValue(forKey: 1)
        XCTAssertFalse(PassageAudio.isUsableCachedChapter(
            ChapterAudio(url: "https://example.invalid/1.mp3", verses: missing),
            verseID: 1, chapterNumber: 1
        ), "verset demandé absent")

        var short = seven().verses
        short.removeValue(forKey: 7)
        XCTAssertFalse(PassageAudio.isUsableCachedChapter(
            ChapterAudio(url: "https://example.invalid/1.mp3", verses: short),
            verseID: 1, chapterNumber: 1
        ), "nombre de versets faux")

        var flat = seven().verses
        flat[3] = ChapterAudio.Span(start: 2, end: 2)
        XCTAssertFalse(PassageAudio.isUsableCachedChapter(
            ChapterAudio(url: "https://example.invalid/1.mp3", verses: flat),
            verseID: 1, chapterNumber: 1
        ), "borne nulle")

        var infinite = seven().verses
        infinite[4] = ChapterAudio.Span(start: .nan, end: 5)
        XCTAssertFalse(PassageAudio.isUsableCachedChapter(
            ChapterAudio(url: "https://example.invalid/1.mp3", verses: infinite),
            verseID: 1, chapterNumber: 1
        ), "borne non finie")

        XCTAssertFalse(PassageAudio.isUsableCachedChapter(seven(), verseID: 1, chapterNumber: 2),
                       "sourate 2 avec 7 versets")
        XCTAssertFalse(PassageAudio.isUsableCachedChapter(nil, verseID: 1, chapterNumber: 1), "cache vide")
    }

    // MARK: Le libellé d'un verset

    /// Les libellés figés aux bornes de sourate, et le seul cas où le portage
    /// **diverge** de l'original : hors bornes, l'original produit
    /// « sourate undefined, verset undefined » — le portage rend `nil`, parce
    /// qu'un libellé qui ment est pire qu'un libellé absent.
    func testTheLabelNamesTheSurahAndTheVerse() {
        XCTAssertEqual(PassageAudio.label(1), "sourate 1, verset 1")
        XCTAssertEqual(PassageAudio.label(2), "sourate 1, verset 2")
        XCTAssertEqual(PassageAudio.label(7), "sourate 1, verset 7")
        XCTAssertEqual(PassageAudio.label(8), "sourate 2, verset 1")
        XCTAssertEqual(PassageAudio.label(6236), "sourate 114, verset 6")
        XCTAssertNil(PassageAudio.label(0))
        XCTAssertNil(PassageAudio.label(6237))
    }
}

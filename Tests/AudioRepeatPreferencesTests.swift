// AudioRepeatPreferencesTests.swift
// Les six réglages de répétition audio, et ce qu'ils décident.
//
// POURQUOI CES TESTS EXISTENT
//   `PassageAudioPlayer.tsx` garde six réglages (`:55-56`) et les persiste sous
//   `audio-repeat-preferences` (`:182`, `:184`). Ce qui décide du comportement
//   n'est pas ce que l'utilisateur voit, mais ce que `:78-79` en dérive — et
//   trois règles y sont silencieuses :
//
//     1. `Number(customCount)` est le `Number()` de JavaScript, pas un entier
//        Swift : `'0x10'` vaut 16, `'1e3'` vaut 1000, `''` vaut 0, `'1,5'` ne
//        vaut rien — et tout ce qui n'est pas un entier strictement positif
//        retombe sur **1**, sans erreur ;
//     2. le nombre NORMALISÉ n'est pas le nombre VALIDÉ : `:79` accepte tout
//        entier strictement positif, `:176` refuse de **lancer** au-delà de 999.
//        Un « Autre » de 5000 donne donc un compte de 5000 ET un refus ;
//     3. la validation au chargement est **champ par champ** et en **égalité
//        stricte** : `"3"` n'est pas `3`, et un champ invalide garde son défaut
//        sans invalider les autres.
//
//   Et l'affichage ne suit pas le réglage : la case « Arrêter à la fin des
//   écoutes » se **décoche** sur « en continu » sans que `autoStop` soit réécrit,
//   tandis que le dénominateur `∞` apparaît pour deux causes distinctes —
//   « en continu », ou l'arrêt automatique décoché.
//
// LES VALEURS ATTENDUES SONT MESURÉES, PAS DÉDUITES DU CODE
//   Tous les nombres de ce fichier viennent de la section 13 de
//   `_banc/oracle-audio.mjs`. Ce banc ne réécrit pas l'original : il l'empaquette
//   avec `esbuild` et le fait tourner, puis il EXTRAIT textuellement du fichier
//   les expressions qui décident — refusant de compter si leur forme a changé —
//   et les compare à une translittération de ce portage. 70 textes pour
//   `Number()`, 84 états de compte et de refus, 56 documents pour la relecture,
//   2016 combinaisons pour l'aller-retour, 14 états d'affichage, 77 ancres
//   d'accord — et la section 15 RELIT les listes figées de ce fichier pour les
//   confronter à la référence, parce que deux valeurs écrites de mémoire y ont
//   déjà coûté un run rouge.
//
// CE QUE CE FICHIER NE PROUVE PAS
//   Pour deux textes — `1e999` et `1e-999` — la valeur brute dépend du
//   débordement de `Double(_:)`, que le banc ne peut pas exercer. Le COMPTE, lui,
//   est le même que Foundation rende l'infini, zéro ou `nil` : c'est donc la
//   seule chose qu'on y affirme. Ailleurs, la valeur brute est comparée aussi.

import XCTest
@testable import Swiftdeepseek

final class AudioRepeatPreferencesTests: XCTestCase {

    // MARK: Outils

    private func preferences(
        _ choice: AudioRepeatPreferences.CountChoice,
        custom: String = "20",
        mode: RepeatMode = .passage,
        gap: Int = 0,
        speed: Double = 1,
        autoStop: Bool = true
    ) -> AudioRepeatPreferences {
        AudioRepeatPreferences(countChoice: choice, customCount: custom,
                               repeatMode: mode, gap: gap, speed: speed, autoStop: autoStop)
    }

    /// Le compte d'un « Autre », c'est-à-dire `Number()` puis la normalisation.
    private func customCount(_ text: String) -> RepeatCount {
        preferences(.custom, custom: text).count
    }

    /// Le document tel que `LocalStore` le lit — un fichier absent ou illisible
    /// rend `nil`, donc les valeurs par défaut.
    private func decoded(_ json: String) -> AudioRepeatPreferences {
        guard let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .defaults
        }
        return AudioRepeatPreferences.decode(document)
    }

    /// Les deux formes d'assertion sur `jsNumber`, avec un `Double` déjà typé :
    /// un littéral entier comparé à un `Double?` laisse le compilateur choisir
    /// entre le littéral et l'optionnel, et ce n'est pas le sujet du test.
    private func assertNumber(_ text: String, _ expected: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(AudioRepeatPreferences.jsNumber(text), expected, text, file: file, line: line)
    }

    private func assertNotANumber(_ text: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(AudioRepeatPreferences.jsNumber(text), text, file: file, line: line)
    }

    // MARK: Les valeurs de départ et les listes

    /// Les six valeurs de `:55-56`, mesurées : `3`, `'20'`, `'passage'`, `0`,
    /// `1`, `true`.
    func testTheDefaultsAreThoseOfTheOriginal() {
        XCTAssertEqual(AudioRepeatPreferences.defaults.countChoice, .times(3))
        XCTAssertEqual(AudioRepeatPreferences.defaults.customCount, "20")
        XCTAssertEqual(AudioRepeatPreferences.defaults.repeatMode, .passage)
        XCTAssertEqual(AudioRepeatPreferences.defaults.gap, 0)
        XCTAssertEqual(AudioRepeatPreferences.defaults.speed, 1)
        XCTAssertTrue(AudioRepeatPreferences.defaults.autoStop)
    }

    /// `:14` et `:248` — sept choix, dans cet ordre ; `[0,2,5,10]` et
    /// `[0.75,1,1.25]` pour le silence et la vitesse. Les listes du chargement et
    /// des pastilles coïncident : une pastille absente de la validation serait un
    /// réglage qu'on ne peut pas enregistrer.
    func testTheChoiceListsAreThoseOfTheOriginal() {
        XCTAssertEqual(AudioRepeatPreferences.countChoices,
                       [.times(1), .times(2), .times(3), .times(5), .times(10), .custom, .continuous])
        XCTAssertEqual(AudioRepeatPreferences.gapChoices, [0, 2, 5, 10])
        XCTAssertEqual(AudioRepeatPreferences.speedChoices, [0.75, 1, 1.25])
        XCTAssertEqual(AudioRepeatPreferences.customCountRange, 1...999)
    }

    /// `:241` — la pastille de cycle rapide saute **« Autre »** : six valeurs,
    /// pas sept. L'y inclure ferait une pastille de plus, et un cycle faux.
    func testTheQuickCycleListSkipsTheCustomChoice() {
        XCTAssertEqual(AudioRepeatPreferences.quickCountChoices,
                       [.times(1), .times(2), .times(3), .times(5), .times(10), .continuous])
        XCTAssertEqual(AudioRepeatPreferences.quickCountChoices.count,
                       AudioRepeatPreferences.countChoices.count - 1)
        XCTAssertFalse(AudioRepeatPreferences.quickCountChoices.contains(.custom))
    }

    /// `:15` — `'∞'`, `'Autre'`, ou le nombre. Les sept libellés, dans l'ordre du
    /// banc : `1 2 3 5 10 Autre ∞`.
    func testTheCountLabelsAreThoseOfTheOriginal() {
        XCTAssertEqual(AudioRepeatPreferences.countLabel(.times(1)), "1")
        XCTAssertEqual(AudioRepeatPreferences.countLabel(.times(2)), "2")
        XCTAssertEqual(AudioRepeatPreferences.countLabel(.times(3)), "3")
        XCTAssertEqual(AudioRepeatPreferences.countLabel(.times(5)), "5")
        XCTAssertEqual(AudioRepeatPreferences.countLabel(.times(10)), "10")
        XCTAssertEqual(AudioRepeatPreferences.countLabel(.custom), "Autre")
        XCTAssertEqual(AudioRepeatPreferences.countLabel(.continuous), "∞")
    }

    /// `:240` — le compte affiché : `'∞'` pour « en continu », le nombre sinon.
    /// Six textes mesurés : `1 2 3 5 10 ∞`.
    func testTheCountTextShowsInfinity() {
        XCTAssertEqual(AudioRepeatPreferences.countText(.times(1)), "1")
        XCTAssertEqual(AudioRepeatPreferences.countText(.times(2)), "2")
        XCTAssertEqual(AudioRepeatPreferences.countText(.times(3)), "3")
        XCTAssertEqual(AudioRepeatPreferences.countText(.times(5)), "5")
        XCTAssertEqual(AudioRepeatPreferences.countText(.times(10)), "10")
        XCTAssertEqual(AudioRepeatPreferences.countText(.continuous), "∞")
    }

    // MARK: `Number()` de JavaScript

    /// La table figée par le banc (section 13 a), recopiée telle quelle : pour
    /// chaque texte, la valeur brute et le compte normalisé. `nil` désigne `NaN`.
    func testTheJavaScriptNumberReadsWhatTheOriginalReads() {
        let table: [(String, Double?, RepeatCount)] = [
            ("20", 20, .times(20)),
            ("3", 3, .times(3)),
            ("1", 1, .times(1)),
            ("999", 999, .times(999)),
            ("1000", 1000, .times(1000)),
            ("0", 0, .times(1)),
            ("", 0, .times(1)),
            ("   ", 0, .times(1)),
            ("\t\n", 0, .times(1)),
            ("\u{00A0}", 0, .times(1)),
            ("\u{FEFF}", 0, .times(1)),
            (" 12 ", 12, .times(12)),
            ("007", 7, .times(7)),
            ("+7", 7, .times(7)),
            ("-5", -5, .times(1)),
            ("-0", 0, .times(1)),
            ("\u{3000}", 0, .times(1)),
            ("\u{2000}", 0, .times(1)),
            ("\u{2028}", 0, .times(1)),
            ("\u{200B}", nil, .times(1)),
            ("\u{3000}7", 7, .times(7)),
            ("\u{2000}7", 7, .times(7)),
            ("\u{200B}1", nil, .times(1)),
            ("1.5", 1.5, .times(1)),
            ("1.0", 1, .times(1)),
            (".5", 0.5, .times(1)),
            ("1.", 1, .times(1)),
            ("1.e3", 1000, .times(1000)),
            ("1.2e+3", 1200, .times(1200)),
            ("1e3", 1000, .times(1000)),
            ("1E3", 1000, .times(1000)),
            ("1e-3", 0.001, .times(1)),
            (".5e2", 50, .times(50)),
            ("abc", nil, .times(1)),
            ("12abc", nil, .times(1)),
            ("1 2", nil, .times(1)),
            ("1,5", nil, .times(1)),
            (".", nil, .times(1)),
            ("+", nil, .times(1)),
            ("-", nil, .times(1)),
            ("e3", nil, .times(1)),
            ("1e", nil, .times(1)),
            ("1e+", nil, .times(1)),
            ("1e-", nil, .times(1)),
            ("1.2.3", nil, .times(1)),
            ("0x10", 16, .times(16)),
            ("0X10", 16, .times(16)),
            ("0b101", 5, .times(5)),
            ("0o17", 15, .times(15)),
            ("0x", nil, .times(1)),
            ("-0x10", nil, .times(1)),
            ("0xZZ", nil, .times(1)),
            ("0x1g", nil, .times(1)),
            ("00", 0, .times(1)),
            ("0b2", nil, .times(1)),
            ("0o8", nil, .times(1)),
            ("0B101", 5, .times(5)),
            ("0O17", 15, .times(15)),
            ("Infinity", Double.infinity, .times(1)),
            ("+Infinity", Double.infinity, .times(1)),
            ("-Infinity", -Double.infinity, .times(1)),
            ("inf", nil, .times(1)),
            ("nan", nil, .times(1)),
            ("NaN", nil, .times(1)),
            ("Infinity ", Double.infinity, .times(1)),
            ("1_000", nil, .times(1)),
            ("1e999", Double.infinity, .times(1)),
            ("1e-999", 0, .times(1)),
            ("9007199254740993", 9007199254740992, .times(9007199254740992)),
            ("99999999999999999999", 1e20, .times(1))
        ]

        // Ces deux-là dépendent du débordement de `Double(_:)`, que le banc ne
        // peut pas exercer : seule la décision y est affirmée.
        let rawNotAsserted: Set<String> = ["1e999", "1e-999"]

        XCTAssertEqual(table.count, 70)
        for (text, raw, count) in table {
            if !rawNotAsserted.contains(text) {
                if let raw {
                    XCTAssertEqual(AudioRepeatPreferences.jsNumber(text), raw, "Number(\(text))")
                } else {
                    XCTAssertNil(AudioRepeatPreferences.jsNumber(text), "Number(\(text))")
                }
            }
            XCTAssertEqual(customCount(text), count, "compte de \(text)")
        }
    }

    /// Le blanc de la spécification est plus large que l'espace ASCII : `U+00A0`
    /// (insécable), `U+2000`, `U+3000` et `U+FEFF` (sans chasse) en font partie.
    /// Une chaîne qui ne contient que du blanc vaut **0**, comme la chaîne vide —
    /// pas `NaN`. En revanche `U+200B` est une espace **sans chasse**, que
    /// JavaScript n'élague pas : `'\u{200B}1'` ne vaut rien.
    func testTheEmptyStringAndTheWhitespaceAreZero() {
        assertNumber("", 0)
        assertNumber("   ", 0)
        assertNumber("\t\n", 0)
        assertNumber("\u{00A0}", 0)
        assertNumber("\u{FEFF}", 0)
        assertNumber("\u{3000}", 0)
        assertNumber("\u{2000}", 0)
        assertNumber("\u{2028}", 0)
        assertNumber(" 12 ", 12)
        assertNumber("\u{3000}7", 7)
        assertNumber("\u{2000}7", 7)
        assertNotANumber("\u{200B}")
        assertNotANumber("\u{200B}1")
    }

    /// `0x`, `0o`, `0b` — les deux casses, et **sans signe** :
    /// `Number('-0x10')` vaut `NaN`. Un chiffre invalide pour la base invalide
    /// tout le littéral.
    func testNonDecimalIntegerLiterals() {
        assertNumber("0x10", 16)
        assertNumber("0X10", 16)
        assertNumber("0b101", 5)
        assertNumber("0B101", 5)
        assertNumber("0o17", 15)
        assertNumber("0O17", 15)
        assertNumber("00", 0)
        assertNotANumber("0x")
        assertNotANumber("-0x10")
        assertNotANumber("0xZZ")
        assertNotANumber("0x1g")
        assertNotANumber("0b2")
        assertNotANumber("0o8")
    }

    /// `'Infinity'` s'écrit en toutes lettres — `'inf'` ne vaut rien, alors que
    /// `Double('inf')` vaudrait l'infini. D'où la comparaison sur le texte.
    func testInfinityIsSpelledOutInFull() {
        assertNumber("Infinity", Double.infinity)
        assertNumber("+Infinity", Double.infinity)
        assertNumber("-Infinity", -Double.infinity)
        assertNumber("Infinity ", Double.infinity)
        assertNotANumber("inf")
        assertNotANumber("nan")
        assertNotANumber("NaN")
    }

    /// Les formes décimales que JavaScript accepte et que `Double(_:)` refuse :
    /// `'1.'`, `'.5'`, `'1.e3'`. Le portage les remet en forme canonique avant de
    /// les lui donner — sans quoi elles vaudraient `nil`, donc 1 au lieu de 1000.
    func testTheDecimalFormsJavaScriptAccepts() {
        assertNumber("1.5", 1.5)
        assertNumber("1.", 1)
        assertNumber(".5", 0.5)
        assertNumber("-.5", -0.5)
        assertNumber("1.e3", 1000)
        assertNumber("1.2e+3", 1200)
        assertNumber(".5e2", 50)
        assertNumber("1e-3", 0.001)
        assertNumber("+7", 7)
        assertNumber("007", 7)
    }

    /// La grammaire est vérifiée AVANT `Double(_:)`, qui est plus permissif sur
    /// d'autres formes (`'inf'`, `'nan'`) et plus strict sur celles-ci.
    func testTheDecimalGrammarRefusesTrailingJunk() {
        for text in ["abc", "12abc", "1 2", "1,5", ".", "+", "-", "e3", "1e",
                     "1e+", "1e-", "1.2.3", "1_000"] {
            assertNotANumber(text)
        }
    }

    // MARK: Le compte, puis le refus de lancement

    /// `:79` — la normalisation ramène à **1** tout ce qui n'est pas un entier
    /// strictement positif : `NaN`, zéro, un négatif, une fraction, l'infini.
    func testTheCountFallsBackToOne() {
        for text in ["abc", "", "0", "-5", "1.5", ".5", "Infinity", "1e-3", "1,5", "1e20"] {
            XCTAssertEqual(customCount(text), .times(1), text)
        }
        XCTAssertEqual(customCount("20"), .times(20))
        XCTAssertEqual(customCount("1"), .times(1))
        XCTAssertEqual(customCount("007"), .times(7))
        XCTAssertEqual(customCount("1e3"), .times(1000))
        XCTAssertEqual(customCount("0x10"), .times(16))
        XCTAssertEqual(customCount(".5e2"), .times(50))
        XCTAssertEqual(customCount("1.e3"), .times(1000))
    }

    /// Les deux décisions ne portent pas sur le même intervalle : `:79` accepte
    /// n'importe quel entier strictement positif, `:176` refuse de lancer
    /// au-delà de 999. Un « Autre » de 5000 produit donc **les deux**.
    func testTheLaunchRefusalIsNarrowerThanTheCount() {
        XCTAssertEqual(preferences(.custom, custom: "5000").count, .times(5000))
        XCTAssertNotNil(preferences(.custom, custom: "5000").launchError)
        XCTAssertEqual(preferences(.custom, custom: "1000").count, .times(1000))
        XCTAssertNotNil(preferences(.custom, custom: "1000").launchError)
        XCTAssertEqual(preferences(.custom, custom: "1.5").count, .times(1))
        XCTAssertNotNil(preferences(.custom, custom: "1.5").launchError)
        XCTAssertEqual(preferences(.custom, custom: "999").count, .times(999))
        XCTAssertNil(preferences(.custom, custom: "999").launchError)
    }

    /// Le refus, et son message — repris tel quel de l'original, qui le remonte
    /// jusqu'à l'utilisateur.
    func testTheLaunchRefusalAndItsMessage() {
        // Les deux listes sont RELUES par le banc (section 15 de
        // `_banc/oracle-audio.mjs`), qui confronte chaque texte au refus de
        // l'original. C'est ce contrôle qui a rattrapé `1e3` : il vaut 1000, donc
        // il est **refusé**, et le ranger parmi les acceptés était faux.
        for text in ["0", "-0", "-5", "", "abc", "1.5", "1000", "5000", "1,5", "Infinity",
                     "1e20", "1e3", "1.e3", "9007199254740993"] {
            XCTAssertNotNil(preferences(.custom, custom: text).launchError, text)
        }
        for text in ["1", "20", "999", "007", " 12 ", "0x10", ".5e2", "+7"] {
            XCTAssertNil(preferences(.custom, custom: text).launchError, text)
        }
        XCTAssertEqual(preferences(.custom, custom: "5000").launchError?.message,
                       "Choisis entre 1 et 999 écoutes.")
    }

    /// Le refus ne porte que sur « Autre » : les autres choix sont des valeurs de
    /// la liste, donc valides par construction — même avec un champ libre absurde.
    func testTheLaunchRefusalOnlyAppliesToTheCustomChoice() {
        for choice in AudioRepeatPreferences.countChoices where choice != .custom {
            XCTAssertNil(preferences(choice, custom: "0").launchError, "\(choice)")
        }
        XCTAssertNotNil(preferences(.custom, custom: "0").launchError)
    }

    /// Divergence DÉCLARÉE : au-delà de 2^53, un `Double` ne porte plus les
    /// entiers un à un, donc le portage ne peut pas les mettre dans un `Int`. Le
    /// compte de l'original vaut la valeur, celui du portage vaut 1 — mais le
    /// lancement est refusé des DEUX côtés, donc aucune lecture ne démarre jamais
    /// avec ce compte. `2^53` lui-même est encore exact, et il est accepté.
    func testBeyondTwoToTheFiftyThirdTheCountDivergesOnPurpose() {
        XCTAssertEqual(preferences(.custom, custom: "9007199254740993").count,
                       .times(9007199254740992))
        XCTAssertEqual(preferences(.custom, custom: "99999999999999999999").count, .times(1))
        XCTAssertEqual(preferences(.custom, custom: "1e20").count, .times(1))
        XCTAssertNotNil(preferences(.custom, custom: "99999999999999999999").launchError)
        XCTAssertNotNil(preferences(.custom, custom: "1e20").launchError)
    }

    // MARK: La relecture du fichier local

    /// Les six champs, chacun lu pour lui-même. Les valeurs sont celles du banc.
    func testTheDecodeReadsTheSixFieldsOfTheOriginal() {
        XCTAssertEqual(decoded("{\"countChoice\":1}"), preferences(.times(1)))
        XCTAssertEqual(decoded("{\"countChoice\":2}"), preferences(.times(2)))
        XCTAssertEqual(decoded("{\"countChoice\":3}"), preferences(.times(3)))
        XCTAssertEqual(decoded("{\"countChoice\":5}"), preferences(.times(5)))
        XCTAssertEqual(decoded("{\"countChoice\":10}"), preferences(.times(10)))
        XCTAssertEqual(decoded("{\"countChoice\":\"custom\"}"), preferences(.custom))
        XCTAssertEqual(decoded("{\"countChoice\":\"continuous\"}"), preferences(.continuous))
        XCTAssertEqual(decoded("{\"customCount\":\"42\"}"), preferences(.times(3), custom: "42"))
        XCTAssertEqual(decoded("{\"repeatMode\":\"each-verse\"}"),
                       preferences(.times(3), mode: .eachVerse))
        XCTAssertEqual(decoded("{\"repeatMode\":\"passage\"}"),
                       preferences(.times(3), mode: .passage))
        XCTAssertEqual(decoded("{\"gap\":2}"), preferences(.times(3), gap: 2))
        XCTAssertEqual(decoded("{\"gap\":5}"), preferences(.times(3), gap: 5))
        XCTAssertEqual(decoded("{\"gap\":10}"), preferences(.times(3), gap: 10))
        XCTAssertEqual(decoded("{\"gap\":2.0}"), preferences(.times(3), gap: 2))
        XCTAssertEqual(decoded("{\"speed\":0.75}"), preferences(.times(3), speed: 0.75))
        XCTAssertEqual(decoded("{\"speed\":1.25}"), preferences(.times(3), speed: 1.25))
        XCTAssertEqual(decoded("{\"autoStop\":false}"), preferences(.times(3), autoStop: false))
        XCTAssertEqual(decoded("{\"countChoice\":3,\"extra\":1}"), preferences(.times(3)))
        XCTAssertEqual(
            decoded("{\"countChoice\":\"custom\",\"customCount\":\"7\",\"repeatMode\":\"each-verse\",\"gap\":5,\"speed\":1.25,\"autoStop\":false}"),
            preferences(.custom, custom: "7", mode: .eachVerse, gap: 5, speed: 1.25, autoStop: false)
        )
    }

    /// Un champ absent, d'un autre type, ou hors de sa liste garde son défaut —
    /// et le défaut seul, sans invalider les autres. C'est le point qu'on ne
    /// devine pas : `"3"` n'est pas `3`.
    func testTheDecodeKeepsTheDefaultOfAnInvalidField() {
        let unchanged = [
            "{}",
            "{\"countChoice\":4}",
            "{\"countChoice\":0}",
            "{\"countChoice\":-1}",
            "{\"countChoice\":3.5}",
            "{\"countChoice\":\"3\"}",
            "{\"countChoice\":\"Custom\"}",
            "{\"countChoice\":null}",
            "{\"countChoice\":true}",
            "{\"countChoice\":[3]}",
            "{\"customCount\":42}",
            "{\"customCount\":null}",
            "{\"customCount\":true}",
            "{\"repeatMode\":\"verse\"}",
            "{\"repeatMode\":\"PASSAGE\"}",
            "{\"repeatMode\":null}",
            "{\"gap\":3}",
            "{\"gap\":\"2\"}",
            "{\"gap\":null}",
            "{\"speed\":1.5}",
            "{\"speed\":\"1\"}",
            "{\"speed\":2}",
            "{\"autoStop\":\"false\"}",
            "{\"autoStop\":0}",
            "{\"autoStop\":null}"
        ]
        // Cette liste est RELUE par le banc (section 15), qui vérifie que chaque
        // document rend réellement les défauts : y laisser un document qui garde
        // un champ fait tomber le banc, et non le test seul.
        for json in unchanged {
            XCTAssertEqual(decoded(json), .defaults, json)
        }

        // Un champ **gardé** n'est pas un champ inchangé. `customCount` est lu dès
        // qu'il est une CHAÎNE, quelle qu'elle soit : `"abc"` est donc conservé,
        // alors que les cinq autres champs de ce document retombent sur leur
        // défaut. C'est la règle de l'original (`typeof prefs.customCount ===
        // 'string'`), et non une tolérance du portage.
        let mixed = decoded("{\"countChoice\":4,\"customCount\":\"abc\",\"repeatMode\":\"x\",\"gap\":7,\"speed\":2,\"autoStop\":\"yes\"}")
        XCTAssertEqual(mixed.countChoice, .times(3))
        XCTAssertEqual(mixed.customCount, "abc")
        XCTAssertEqual(mixed.repeatMode, .passage)
        XCTAssertEqual(mixed.gap, 0)
        XCTAssertEqual(mixed.speed, 1)
        XCTAssertTrue(mixed.autoStop)

        // Un champ invalide n'invalide pas les autres.
        let subject = decoded("{\"countChoice\":\"custom\",\"gap\":3}")
        XCTAssertEqual(subject.countChoice, .custom)
        XCTAssertEqual(subject.gap, 0)
    }

    /// Un document qui n'est pas un objet rend les défauts. L'original lit
    /// `prefs.countChoice` : sur `null`, un nombre, une chaîne ou un tableau,
    /// cela vaut `undefined`, que `counts.includes` refuse. Un fichier absent —
    /// jamais écrit — se comporte pareil.
    func testANonObjectDocumentYieldsTheDefaults() {
        let documents: [JSONValue?] = [
            nil,
            JSONValue.null,
            JSONValue.number(3),
            JSONValue.string("passage"),
            JSONValue.bool(true),
            JSONValue.array([JSONValue.number(1), JSONValue.number(2)])
        ]
        for document in documents {
            XCTAssertEqual(AudioRepeatPreferences.decode(document), .defaults)
        }
        for text in ["", "not json", "{\"countChoice\":"] {
            XCTAssertEqual(decoded(text), .defaults, text)
        }
    }

    // MARK: Ce qui est écrit

    /// `:184` — `JSON.stringify({countChoice,customCount,repeatMode,gap,speed,autoStop})`.
    /// Six clés, et rien d'autre : aucun réglage de ces préférences n'entre dans
    /// `user_state` (`LOCAL_DATA_MIGRATION.md` §4 a).
    func testTheEncodedShapeIsTheOneOfTheOriginal() {
        let encoded = preferences(.times(3)).encoded
        guard case .object(let fields) = encoded else {
            XCTFail("la forme écrite doit être un objet")
            return
        }
        // Comparé clé par clé plutôt qu'en un `Set` littéral : le littéral
        // laisserait au compilateur le choix entre un tableau et un ensemble,
        // et ce n'est pas le sujet du test.
        XCTAssertEqual(fields.count, 6)
        for key in ["countChoice", "customCount", "repeatMode", "gap", "speed", "autoStop"] {
            XCTAssertNotNil(fields[key], "clé manquante : \(key)")
        }
        XCTAssertEqual(fields["countChoice"], JSONValue.number(3))
        XCTAssertEqual(fields["customCount"], JSONValue.string("20"))
        XCTAssertEqual(fields["repeatMode"], JSONValue.string("passage"))
        XCTAssertEqual(fields["gap"], JSONValue.number(0))
        XCTAssertEqual(fields["speed"], JSONValue.number(1))
        XCTAssertEqual(fields["autoStop"], JSONValue.bool(true))
        XCTAssertEqual(preferences(.custom).encoded["countChoice"], JSONValue.string("custom"))
        XCTAssertEqual(preferences(.continuous).encoded["countChoice"], JSONValue.string("continuous"))
        XCTAssertEqual(preferences(.times(10)).encoded["countChoice"], JSONValue.number(10))
    }

    /// L'aller-retour doit être un **point fixe** sur tout le domaine : la forme
    /// écrite par l'application est relisible telle quelle. 7 × 6 × 2 × 4 × 3 × 2
    /// = 2016 combinaisons, le compte mesuré par le banc.
    func testTheEncodedShapeRoundTrips() {
        var cases = 0
        for choice in AudioRepeatPreferences.countChoices {
            for custom in ["20", "", "abc", "1.5", "999", "5000"] {
                for mode in RepeatMode.allCases {
                    for gap in AudioRepeatPreferences.gapChoices {
                        for speed in AudioRepeatPreferences.speedChoices {
                            for autoStop in [true, false] {
                                cases += 1
                                let original = preferences(choice, custom: custom, mode: mode,
                                                           gap: gap, speed: speed, autoStop: autoStop)
                                XCTAssertEqual(AudioRepeatPreferences.decode(original.encoded), original,
                                               "\(choice) \(custom) \(mode) \(gap) \(speed) \(autoStop)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(cases, 2016)
    }

    // MARK: Le cycle rapide et les deux affichages

    /// `:241` — le cycle rapide : `values[(values.indexOf(count)+1)%6]`. Un
    /// compte HORS liste — un « Autre » de 4, de 20 ou de 5000 — donne
    /// `indexOf` = -1, donc `(0)%6` = 0, donc **1**. Ce n'est pas devinable.
    func testTheQuickCycle() {
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(1)), .times(2))
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(2)), .times(3))
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(3)), .times(5))
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(5)), .times(10))
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(10)), .continuous)
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .continuous), .times(1))
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(4)), .times(1))
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(20)), .times(1))
        XCTAssertEqual(AudioRepeatPreferences.nextQuickCount(after: .times(5000)), .times(1))
        // Jamais « Autre » : la pastille ne mène pas au champ libre.
        for count in [1, 2, 3, 5, 10, 4, 20, 5000] {
            XCTAssertNotEqual(AudioRepeatPreferences.nextQuickCount(after: .times(count)), .custom)
        }
        XCTAssertNotEqual(AudioRepeatPreferences.nextQuickCount(after: .continuous), .custom)
    }

    /// Les 14 états d'affichage, figés par le banc. Le tableau est écrit à la
    /// main : le recalculer avec la même expression que l'implémentation ne
    /// prouverait rien. `∞` apparaît pour DEUX causes distinctes — « en continu »,
    /// ou l'arrêt automatique décoché — et la case se décoche sur « en continu »
    /// alors que `autoStop` reste **vrai**.
    func testTheTwoDisplaysDifferFromTheStoredSetting() {
        let table: [(AudioRepeatPreferences.CountChoice, Bool, Bool, Bool)] = [
            (.times(1), true, true, false),
            (.times(1), false, false, true),
            (.times(2), true, true, false),
            (.times(2), false, false, true),
            (.times(3), true, true, false),
            (.times(3), false, false, true),
            (.times(5), true, true, false),
            (.times(5), false, false, true),
            (.times(10), true, true, false),
            (.times(10), false, false, true),
            (.custom, true, true, false),
            (.custom, false, false, true),
            (.continuous, true, false, true),
            (.continuous, false, false, true)
        ]
        XCTAssertEqual(table.count, 14)
        for (choice, autoStop, selected, unlimited) in table {
            let subject = preferences(choice, autoStop: autoStop)
            XCTAssertEqual(subject.showsAutoStopSelected, selected,
                           "case \(choice) autoStop=\(autoStop)")
            XCTAssertEqual(subject.displaysUnlimitedRepetition, unlimited,
                           "infini \(choice) autoStop=\(autoStop)")
        }

        // Le réglage lui-même n'est pas réécrit par l'affichage.
        let continuous = preferences(.continuous, autoStop: true)
        XCTAssertFalse(continuous.showsAutoStopSelected)
        XCTAssertTrue(continuous.autoStop)
        XCTAssertEqual(AudioRepeatPreferences.decode(continuous.encoded).autoStop, true)
    }

    // MARK: Le fichier local

    /// Le fichier écrit par l'application est relisible par l'application.
    func testTheLocalStoreKeepsThePreferences() async throws {
        let store = LocalStore(directoryName: "SwiftdeepseekStateTests-audio")
        let written = preferences(.custom, custom: "42", mode: .eachVerse,
                                  gap: 5, speed: 1.25, autoStop: false)
        try await store.saveAudioPreferences(written)
        let read = await store.loadAudioPreferences()
        XCTAssertEqual(read, written)
    }

    /// Un fichier absent rend les défauts — jamais une erreur : si l'utilisateur
    /// est déjà connecté, l'absence de réseau ou de fichier ne doit pas empêcher
    /// l'application de s'ouvrir.
    func testAnAbsentFileYieldsTheDefaults() async {
        let store = LocalStore(directoryName: "SwiftdeepseekStateTests-audio-absent")
        let read = await store.loadAudioPreferences()
        XCTAssertEqual(read, .defaults)
    }

    /// Le fichier écrit par l'application React Native est lisible tel quel : même
    /// forme, mêmes clés, mêmes types.
    func testTheFileOfTheOriginalIsReadableAsIs() async throws {
        let name = "SwiftdeepseekStateTests-audio-original"
        let store = LocalStore(directoryName: name)
        let base = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
                                                          in: .userDomainMask).first)
        let file = base.appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("audio-repeat-preferences.json")
        let written = #"{"countChoice":"continuous","customCount":"42","repeatMode":"each-verse","gap":10,"speed":0.75,"autoStop":false}"#
        try Data(written.utf8).write(to: file)
        let read = await store.loadAudioPreferences()
        XCTAssertEqual(read, preferences(.continuous, custom: "42", mode: .eachVerse,
                                         gap: 10, speed: 0.75, autoStop: false))
    }

    /// Un fichier corrompu ne fait pas échouer la lecture : il rend les défauts.
    func testACorruptFileYieldsTheDefaults() async throws {
        let name = "SwiftdeepseekStateTests-audio-corrompu"
        let store = LocalStore(directoryName: name)
        let base = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
                                                          in: .userDomainMask).first)
        let file = base.appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("audio-repeat-preferences.json")
        try Data("{ ceci n'est pas du JSON".utf8).write(to: file)
        let read = await store.loadAudioPreferences()
        XCTAssertEqual(read, .defaults)
    }
}

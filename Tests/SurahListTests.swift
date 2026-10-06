// SurahListTests.swift
// L'onglet Coran : la liste des sourates, des Juz' et des Hizb.
//
// CE QUE CE FICHIER ÉPINGLE, ET POURQUOI
//   `Core/SurahListOptions.swift` porte **deux règles de recherche différentes**,
//   un filtre qui ne s'applique qu'à une seule des trois vues, une pagination
//   qui dépend de l'édition, et une vingtaine de chaînes affichées. Aucune de
//   ces décisions ne se voit à la lecture : un portage « propre » qui unifierait
//   les deux recherches, ou qui appliquerait le filtre partout, compilerait et
//   afficherait une liste plausible — simplement, la recherche ne trouverait
//   plus les mêmes choses, et rien ne le dirait.
//
// LES CHIFFRES DE CE FICHIER SONT MESURÉS, PAS DÉDUITS
//   `_banc/oracle-liste-sourates.mjs` (et ses deux compléments) rejoue
//   `Quran.pageOf` et l'index du Coran 1441 sur `Resources/Data/meta.json`,
//   `pages.json` et `coran_1441-bounds.json`, et imprime les valeurs ci-dessous.
//   Aucun nombre n'a été recopié d'un commentaire.
//
// TROIS RÉSULTATS DE CETTE MESURE QUI ONT CORRIGÉ UNE INTUITION
//
//   1. « juz » en ASCII **trouve** les trente : c'est un préfixe de « Juz’ ».
//      Le vrai contre-exemple est l'apostrophe DROITE — « juz' » (U+0027) ne
//      trouve rien, parce que le libellé porte U+2019. Le test 12 tient les deux
//      moitiés, faute de quoi il passerait pour la mauvaise raison.
//
//   2. La recherche d'une sourate n'est pas insensible aux accents NI aux
//      espaces : « yâsîn » ne trouve rien (le nom est « Yâ Sîn », en deux mots),
//      « yâ sîn » en trouve une. Et « ouverture » en trouve deux — la sourate 1
//      (« L'ouverture ») et la 94 (même signification), écrites avec
//      l'apostrophe DROITE, là où l'interface écrit U+2019.
//
//   3. Aucune division ne change de page entre les deux éditions : les 56 versets
//      dont la première page diffère (mesuré : le premier est le 746) sont tous
//      à l'INTÉRIEUR d'un Juz' ou d'un Hizb, jamais sur une de leurs bornes. Un
//      test qui n'éprouverait la pagination que par un `pageSpan` ne
//      distinguerait donc rien ; il faut passer par `page(_:edition:)`.

import XCTest
@testable import Swiftdeepseek

final class SurahListTests: XCTestCase {

    // MARK: - Outils

    private func state(
        knowledge: [String: Mastery] = [:],
        lastRead: LastRead? = nil,
        testPage: Int? = nil
    ) -> AppState {
        var fresh = Program.defaultState()
        fresh.knowledge = knowledge
        fresh.lastRead = lastRead
        if let testPage { fresh.reader?.testPage = testPage }
        return fresh
    }

    private func rows(
        _ mode: SurahListOptions.Mode,
        query: String = "",
        filter: SurahListOptions.Filter = .all,
        edition: QuranEdition = .medine
    ) -> [SurahListOptions.Row] {
        SurahListOptions.rows(mode: mode, query: query, filter: filter, edition: edition)
    }

    /// Le Juz' 1 : versets 1 à 148, mesuré dans `meta.json`.
    private var juz1: Division { Quran.juzs[0] }

    /// Le Hizb 1 : versets 1 à 81, dérivé des rub‘ comme `Quran.hizbs`.
    private var hizb1: Division { Quran.hizbs[0] }

    /// Le premier verset dont la première page diffère selon l'édition :
    /// Al Mâ'idah 77. Médine 121, Coran 1441 120.
    private let divergentVerse = 746

    /// Contient un scalaire donné — pour éprouver un point de code sans qu'un
    /// `grep` sur le source puisse confondre deux apostrophes qui se ressemblent.
    private func containsScalar(_ text: String, _ value: UInt32) -> Bool {
        text.unicodeScalars.contains { $0.value == value }
    }

    // MARK: - Les trois vues

    /// La vue « Liste » rend les 114 sourates, dans l'ordre du moushaf.
    func testListModeRendersTheWholeMushafInOrder() {
        let items = rows(.liste)
        XCTAssertEqual(items.count, 114)
        XCTAssertEqual(items.first?.number, 1)
        XCTAssertEqual(items.last?.number, 114)
        XCTAssertEqual(items.map(\.number), Array(1...114))
        XCTAssertTrue(items.allSatisfy { $0.kind == .surah })
    }

    /// Trente Juz', soixante Hizb — mesuré : `meta.juzs` en compte 30 et
    /// `Quran.hizbs` 60 (240 rub‘ divisés par quatre).
    func testJuzAndHizbViewsCountThirtyAndSixty() {
        XCTAssertEqual(rows(.juz).count, 30)
        XCTAssertEqual(rows(.hizb).count, 60)
        XCTAssertEqual(rows(.juz).map(\.number), Array(1...30))
        XCTAssertEqual(rows(.hizb).map(\.number), Array(1...60))
        XCTAssertTrue(rows(.juz).allSatisfy { $0.kind == .division })
        XCTAssertTrue(rows(.hizb).allSatisfy { $0.kind == .division })
    }

    /// La vue fait partie de la clé, pas seulement le numéro : « Juz’ 1 » et
    /// « Hizb 1 » sont deux lignes distinctes.
    func testRowIdentifiersCarryTheModeSoThatTwoViewsNeverCollide() {
        XCTAssertEqual(rows(.liste).first?.id, "Liste-1")
        XCTAssertEqual(rows(.juz).first?.id, "Juz’-1")
        XCTAssertEqual(rows(.hizb).first?.id, "Hizb-1")
        let ids = rows(.juz).map(\.id) + rows(.hizb).map(\.id)
        XCTAssertEqual(Set(ids).count, 90)
    }

    /// Les trois libellés, et l'apostrophe de « Juz’ » est U+2019 — celle de
    /// l'original, qui entre dans la chaîne cherchée.
    func testModeLabelsCarryTheTypographicApostrophe() {
        XCTAssertEqual(SurahListOptions.Mode.allCases.count, 3)
        XCTAssertEqual(SurahListOptions.Mode.allCases.map(\.label), ["Liste", "Juz’", "Hizb"])
        XCTAssertTrue(containsScalar(SurahListOptions.Mode.juz.label, 0x2019))
        XCTAssertFalse(containsScalar(SurahListOptions.Mode.juz.label, 0x0027))
    }

    // MARK: - Le filtre

    /// Le filtre de lieu de révélation : 86 Mecquoises, 28 Médinoises — mesuré
    /// sur `meta.json`.
    func testFilterKeepsOneOriginOnly() {
        XCTAssertEqual(rows(.liste, filter: .all).count, 114)
        XCTAssertEqual(rows(.liste, filter: .meccan).count, 86)
        XCTAssertEqual(rows(.liste, filter: .medinan).count, 28)
        XCTAssertTrue(rows(.liste, filter: .meccan).allSatisfy(\.isMeccan))
        XCTAssertTrue(rows(.liste, filter: .medinan).allSatisfy { !$0.isMeccan })
    }

    /// La règle silencieuse : le filtre n'existe QUE dans la vue « Liste ».
    /// `MainScreens.tsx:31` ne le teste pas dans la branche des divisions, et le
    /// bouton de filtre n'est rendu que dans cette vue.
    func testTheFilterIsIgnoredByTheDivisionViews() {
        XCTAssertEqual(rows(.juz, filter: .meccan).count, 30)
        XCTAssertEqual(rows(.juz, filter: .medinan).count, 30)
        XCTAssertEqual(rows(.hizb, filter: .meccan).count, 60)
        XCTAssertEqual(rows(.hizb, filter: .medinan).count, 60)
        XCTAssertEqual(rows(.juz, filter: .meccan), rows(.juz, filter: .all))
        XCTAssertEqual(rows(.hizb, filter: .medinan), rows(.hizb, filter: .all))
    }

    /// La sourate 5 — Al Mâ'idah, qui porte le verset à pagination divergente —
    /// est Médinoise : le filtre la garde d'un côté et la retire de l'autre.
    func testTheFilterSeparatesTheSurahThatCarriesTheDivergentVerse() {
        let medinan = rows(.liste, filter: .medinan).map(\.number)
        let meccan = rows(.liste, filter: .meccan).map(\.number)
        XCTAssertTrue(medinan.contains(5))
        XCTAssertFalse(meccan.contains(5))
    }

    func testFilterLabelsAndCases() {
        XCTAssertEqual(SurahListOptions.Filter.allCases.count, 3)
        XCTAssertEqual(
            SurahListOptions.Filter.allCases.map { SurahListOptions.filterLabel($0) },
            ["Toutes", "Mecquoises", "Médinoises"]
        )
    }

    // MARK: - La recherche d'une sourate — quatre champs, puis le filtre

    /// Le numéro fait partie de la chaîne cherchée : « 114 » ne trouve que la
    /// dernière sourate, et « 1 » en trouve 34 (1, 10 à 19, 21, 31, … 114) —
    /// c'est un `contains`, pas une égalité.
    func testSurahSearchMatchesTheNumberAsASubstring() {
        XCTAssertEqual(rows(.liste, query: "114").map(\.number), [114])
        XCTAssertEqual(rows(.liste, query: "1").count, 34)
        XCTAssertEqual(rows(.liste, query: "2").count, 21)
    }

    /// Le nom, la signification et l'arabe sont cherchés aussi — et l'arabe
    /// trouve bien une sourate.
    func testSurahSearchLooksAtTheNameTheMeaningAndTheArabic() {
        XCTAssertEqual(rows(.liste, query: "baqarah").map(\.number), [2])
        XCTAssertEqual(rows(.liste, query: "la vache").map(\.number), [2])
        XCTAssertEqual(rows(.liste, query: "الفَاتِحة").map(\.number), [1])
        // « L'ouverture » est porté par DEUX sourates : la 1 et la 94.
        XCTAssertEqual(rows(.liste, query: "ouverture").map(\.number), [1, 94])
    }

    /// La recherche n'est ni insensible aux accents ni insensible aux espaces.
    /// « Yâ Sîn » s'écrit en deux mots : « yâsîn » ne trouve rien.
    func testSurahSearchIsNotDiacriticOrSpaceInsensitive() {
        XCTAssertTrue(rows(.liste, query: "yâsîn").isEmpty)
        XCTAssertEqual(rows(.liste, query: "yâ sîn").map(\.number), [36])
        // « Ya Sin », la signification, est écrite sans accent — et trouve.
        XCTAssertEqual(rows(.liste, query: "ya sin").map(\.number), [36])
        // « médine » avec accent ne figure nulle part dans les quatre champs.
        XCTAssertTrue(rows(.liste, query: "médine").isEmpty)
    }

    /// L'apostrophe des DONNÉES est droite (U+0027), celle de l'INTERFACE est
    /// typographique (U+2019). Chercher avec la seconde ne trouve rien là où la
    /// première trouve — la même famille de piège que « Juz’ ».
    func testSurahSearchDistinguishesTheTwoApostrophes() {
        XCTAssertEqual(rows(.liste, query: "l'ouverture").count, 2)
        XCTAssertTrue(rows(.liste, query: "l’ouverture").isEmpty)
    }

    /// Le filtre est testé APRÈS la recherche, comme le `&&` de l'original.
    func testSurahSearchAndFilterCompose() {
        XCTAssertEqual(rows(.liste, query: "al", filter: .all).count, 64)
        XCTAssertEqual(rows(.liste, query: "al", filter: .meccan).count, 46)
        XCTAssertEqual(rows(.liste, query: "al", filter: .medinan).count, 18)
        XCTAssertEqual(
            rows(.liste, query: "al", filter: .meccan).count
                + rows(.liste, query: "al", filter: .medinan).count,
            rows(.liste, query: "al", filter: .all).count
        )
    }

    /// Une recherche qui ne trouve rien rend une liste vide — l'écran, lui,
    /// affiche `emptyState`.
    func testAnUnmatchedQueryRendersNothing() {
        XCTAssertTrue(rows(.liste, query: "zzz").isEmpty)
        XCTAssertTrue(rows(.juz, query: "zzz").isEmpty)
        XCTAssertTrue(rows(.hizb, query: "zzz").isEmpty)
    }

    // MARK: - La recherche d'une division — trois champs, aucun filtre

    /// Trois champs : le numéro, le LIBELLÉ DE LA VUE, et le nom de la sourate
    /// où la division COMMENCE. La signification n'y est pas.
    func testDivisionSearchLooksAtThreeFieldsOnly() {
        XCTAssertEqual(rows(.juz, query: "juz").count, 30)
        XCTAssertEqual(rows(.hizb, query: "hizb").count, 60)
        // Le nom de la sourate d'ouverture : Al Baqarah ouvre les Juz' 2 ET 3.
        XCTAssertEqual(rows(.juz, query: "baqarah").map(\.number), [2, 3])
        XCTAssertEqual(rows(.hizb, query: "baqarah").count, 4)
        // La signification n'est pas cherchée : « pages » ne trouve rien, alors
        // que c'est le mot par lequel chaque ligne commence sa seconde étiquette.
        XCTAssertTrue(rows(.juz, query: "pages").isEmpty)
    }

    /// Le contre-exemple réel, mesuré : l'apostrophe DROITE ne trouve rien.
    /// « juz » en ASCII trouve les trente, parce que c'en est un préfixe.
    func testDivisionSearchFindsNothingWithAStraightApostrophe() {
        XCTAssertEqual(rows(.juz, query: "juz").count, 30)
        XCTAssertEqual(rows(.juz, query: "juz’").count, 30)
        XCTAssertTrue(rows(.juz, query: "juz'").isEmpty)
        XCTAssertTrue(rows(.juz, query: "Juz'").isEmpty)
    }

    /// Le numéro d'une division se cherche aussi en `contains` : « 3 » trouve
    /// les Juz' 3, 13, 23 et 30.
    func testDivisionSearchMatchesTheNumberAsASubstring() {
        XCTAssertEqual(rows(.juz, query: "3").map(\.number), [3, 13, 23, 30])
        XCTAssertEqual(rows(.juz, query: "30").map(\.number), [30])
        XCTAssertEqual(rows(.hizb, query: "60").map(\.number), [60])
    }

    /// Les noms de sourates d'ouverture viennent du PREMIER verset de la
    /// division, pas de sa fin. Mesuré sur les trente Juz'.
    func testDivisionSearchUsesTheSurahWhereTheDivisionStarts() {
        // Le Juz' 30 ouvre sur An Naba', pas sur An Nâs.
        XCTAssertEqual(rows(.juz, query: "naba").map(\.number), [30])
        XCTAssertTrue(rows(.juz, query: "nâs").isEmpty)
        // Al Fâtiha n'ouvre qu'un seul Juz' — le premier.
        XCTAssertEqual(rows(.juz, query: "fâtiha").map(\.number), [1])
    }

    /// Une recherche **vide** ramène tout — et c'est le cas NORMAL, pas un cas
    /// limite : le champ part vide, donc c'est la requête sur laquelle l'écran
    /// s'ouvre.
    ///
    /// La règle est celle de JavaScript — `''.includes('')` vaut `true` — alors
    /// que `"abc".contains("")` vaut **false** en Swift. Ce test est né d'un échec
    /// d'intégration continue : les treize tests qui lisaient `rows(…)` sans
    /// requête rendaient une liste **vide**, donc l'onglet Coran s'ouvrait vide.
    /// Le banc ne pouvait pas le voir — il relit le source, il n'exécute pas le
    /// langage — et c'est la limite qu'il déclare lui-même.
    func testAnEmptyQueryMatchesEverythingAsJavaScriptDoes() {
        XCTAssertFalse("abc".contains(""), "en Swift, un `contains` vide est faux : c'est la divergence qui a causé le défaut")
        XCTAssertEqual(rows(.liste).count, 114)
        XCTAssertEqual(rows(.juz).count, 30)
        XCTAssertEqual(rows(.hizb).count, 60)
        XCTAssertEqual(rows(.liste, query: "").count, 114)
        XCTAssertEqual(rows(.juz, query: "").count, 30)
        XCTAssertEqual(rows(.hizb, query: "").count, 60)
    }

    // MARK: - Une ligne de sourate

    /// Les champs d'une sourate traversent tels quels, sauf que `meaning` et
    /// `arabic` deviennent des chaînes vides quand la donnée est absente — ce
    /// qu'aucune des 114 n'est, mais le type le permet.
    func testASurahRowCarriesTheWholeSurah() {
        let row = rows(.liste).first { $0.number == 5 }
        XCTAssertEqual(row?.id, "Liste-5")
        XCTAssertEqual(row?.kind, .surah)
        XCTAssertEqual(row?.name, "Al Mâ'idah")
        XCTAssertEqual(row?.meaning, "La table servie")
        XCTAssertEqual(row?.arabic, "المَائدة")
        XCTAssertEqual(row?.isMeccan, false)
        XCTAssertEqual(row?.count, 120)
        XCTAssertEqual(row?.start, 670)
        XCTAssertEqual(row?.end, 789)
    }

    /// Les bornes d'une sourate s'enchaînent : `end` d'une ligne + 1 = `start`
    /// de la suivante, et `count` = `end - start + 1`. Un décalage d'un seul
    /// verset dans `meta.json` ferait basculer toutes les suivantes.
    func testSurahBoundsAreContiguous() {
        let items = rows(.liste)
        XCTAssertEqual(items.first?.start, 1)
        XCTAssertEqual(items.last?.end, 6236)
        for (index, row) in items.enumerated() {
            XCTAssertEqual(row.count, row.end - row.start + 1)
            if index > 0 {
                XCTAssertEqual(row.start, items[index - 1].end + 1)
            }
        }
    }

    /// Le badge d'origine suit `isMeccan` — 86 « Mecquoise », 28 « Médinoise ».
    func testOriginBadgeFollowsTheRevelationPlace() {
        XCTAssertEqual(SurahListOptions.originBadge(isMeccan: true), "Mecquoise")
        XCTAssertEqual(SurahListOptions.originBadge(isMeccan: false), "Médinoise")
        XCTAssertEqual(
            rows(.liste).filter(\.isMeccan).count,
            86
        )
        XCTAssertEqual(rows(.liste).first?.isMeccan, true)
        XCTAssertEqual(rows(.liste).last?.isMeccan, true)
    }

    // MARK: - Une ligne de division

    /// Quatre champs sont ÉCRASÉS après l'étalement de la division : le nom, la
    /// signification (la plage de pages), l'arabe (vidé) et le compte.
    func testADivisionRowOverwritesFourFields() {
        let row = rows(.juz).first
        XCTAssertEqual(row?.id, "Juz’-1")
        XCTAssertEqual(row?.kind, .division)
        XCTAssertEqual(row?.name, "Juz’ 1")
        XCTAssertEqual(row?.meaning, "Pages 1 – 21")
        XCTAssertEqual(row?.arabic, "")
        XCTAssertEqual(row?.isMeccan, false)
        XCTAssertEqual(row?.count, 148)
        XCTAssertEqual(row?.start, 1)
        XCTAssertEqual(row?.end, 148)
    }

    /// `isMeccan` est posé à `false` et l'arabe est vidé : c'est ce qui fait que
    /// ni le badge d'origine ni le libellé arabe ne s'affichent sur une division.
    func testNoDivisionRowCarriesAnOriginOrAnArabicLabel() {
        XCTAssertTrue((rows(.juz) + rows(.hizb)).allSatisfy { !$0.isMeccan })
        XCTAssertTrue((rows(.juz) + rows(.hizb)).allSatisfy { $0.arabic.isEmpty })
        XCTAssertTrue(rows(.juz).allSatisfy { $0.name.hasPrefix("Juz’ ") })
        XCTAssertTrue(rows(.hizb).allSatisfy { $0.name.hasPrefix("Hizb ") })
    }

    /// Le compte d'une division est `end - start + 1`. Mesuré : 148 versets pour
    /// le premier Juz', 564 pour le trentième, 81 pour le premier Hizb, et le
    /// plus petit des soixante en compte 48 — jamais un seul.
    func testDivisionCountsAreMeasured() {
        XCTAssertEqual(rows(.juz).first?.count, 148)
        XCTAssertEqual(rows(.juz).last?.count, 564)
        XCTAssertEqual(rows(.hizb).first?.count, 81)
        XCTAssertEqual(rows(.hizb).map(\.count).min(), 48)
        for row in rows(.juz) + rows(.hizb) {
            XCTAssertEqual(row.count, row.end - row.start + 1)
        }
    }

    /// Les divisions se recouvrent et se suivent : le Juz' 30 finit sur le
    /// dernier verset du moushaf, le Hizb 60 aussi.
    func testDivisionBoundsReachTheEndOfTheMushaf() {
        XCTAssertEqual(rows(.juz).last?.end, 6236)
        XCTAssertEqual(rows(.hizb).last?.end, 6236)
        XCTAssertEqual(rows(.juz).first?.start, 1)
        XCTAssertEqual(rows(.hizb).first?.start, 1)
    }

    // MARK: - Les pages d'une division

    /// « Pages X – Y », avec un CADRATIN (U+2013) et deux espaces. Un trait
    /// d'union compilerait et s'afficherait presque pareil.
    func testPageSpanUsesAnEnDash() {
        let span = SurahListOptions.pageSpan(juz1, edition: .medine)
        XCTAssertEqual(span, "Pages 1 – 21")
        XCTAssertTrue(containsScalar(span, 0x2013))
        XCTAssertFalse(span.contains("-"))
        XCTAssertFalse(containsScalar(span, 0x2014))
        XCTAssertFalse(containsScalar(span, 0x2012))
    }

    /// Les plages mesurées, édition par édition.
    func testPageSpansAreMeasured() {
        XCTAssertEqual(SurahListOptions.pageSpan(juz1, edition: .medine), "Pages 1 – 21")
        XCTAssertEqual(SurahListOptions.pageSpan(Quran.juzs[1], edition: .medine), "Pages 22 – 41")
        XCTAssertEqual(SurahListOptions.pageSpan(Quran.juzs[29], edition: .medine), "Pages 582 – 604")
        XCTAssertEqual(SurahListOptions.pageSpan(hizb1, edition: .medine), "Pages 1 – 11")
        XCTAssertEqual(SurahListOptions.pageSpan(Quran.hizbs[59], edition: .medine), "Pages 591 – 604")
    }

    /// `page(_:edition:)` est `studyPage` : la même fonction que la reprise
    /// d'une marque-page, sans page connue.
    func testPageIsTheSameFunctionAsTheBookmarkResume() {
        XCTAssertEqual(SurahListOptions.page(1, edition: .medine), 1)
        XCTAssertEqual(SurahListOptions.page(6236, edition: .medine), 604)
        XCTAssertEqual(SurahListOptions.page(5673, edition: .medine), 582)
        // `Optional(...)` des deux côtés : `page` rend un `Int` (il replie sur 1)
        // là où `versePage` rend un `Int?`. Les mettre à plat montrerait qu'ils
        // s'accordent là où l'un peut se taire.
        XCTAssertEqual(
            Optional(SurahListOptions.page(divergentVerse, edition: .medine)),
            QuranSourceNavigation.versePage(.medine, verseID: divergentVerse)
        )
        XCTAssertEqual(
            Optional(SurahListOptions.page(divergentVerse, edition: .coran1441)),
            QuranSourceNavigation.versePage(.coran1441, verseID: divergentVerse)
        )
    }

    /// Le verset 746 — Al Mâ'idah 77 — ouvre la page 121 du Coran de Médine et
    /// la page 120 du Coran 1441. C'est le PREMIER des 56 versets dans ce cas.
    func testTheDivergentVerseChangesPageWithTheEdition() {
        XCTAssertEqual(SurahListOptions.page(divergentVerse, edition: .medine), 121)
        XCTAssertEqual(SurahListOptions.page(divergentVerse, edition: .coran1441), 120)
    }

    /// Les éditions que cette version ne sait pas rendre : celles dont l'original
    /// suit la pagination du Coran de Médine retombent dessus, et `coranTest` —
    /// qui suit celle du moushaf de Tajwid — rend la page du 1441.
    ///
    /// `displayed(stored:)` remplace les deux par `.medine` pour l'AFFICHAGE, et
    /// c'est pourquoi la liste ne les reçoit jamais (`SurahListView` passe
    /// `model.edition`). Mais la fonction doit dire la vérité de l'original : le
    /// jour où l'une devient rendable, la navigation est déjà juste.
    ///
    /// Ce test affirmait l'inverse — `coranTest` à 121, comme le Médine —, et
    /// c'était la justification par les 607 polices `.woff2` qui le portait :
    /// elle appartient au RENDU, pas à la navigation. Voir §9.33.
    func testTheUnrenderedEditionsFollowTheirOwnPagination() {
        XCTAssertEqual(SurahListOptions.page(divergentVerse, edition: .coranTest), 120)
        XCTAssertEqual(SurahListOptions.page(divergentVerse, edition: .tajweed), 121)
        XCTAssertEqual(SurahListOptions.page(divergentVerse, edition: .tajweedPages), 121)
        XCTAssertEqual(
            SurahListOptions.page(divergentVerse, edition: .coranTest),
            SurahListOptions.page(divergentVerse, edition: .coran1441)
        )
        XCTAssertEqual(
            SurahListOptions.page(divergentVerse, edition: .tajweedPages),
            SurahListOptions.page(divergentVerse, edition: .medine)
        )
    }

    /// Et pourtant AUCUNE division ne change de plage selon l'édition : les 56
    /// versets divergents sont tous à l'intérieur d'un Juz' ou d'un Hizb. C'est
    /// ce qui rend le test précédent nécessaire — un `pageSpan` ne distingue
    /// rien ici.
    func testNoDivisionChangesItsSpanWithTheEdition() {
        for division in Quran.juzs + Quran.hizbs {
            XCTAssertEqual(
                SurahListOptions.pageSpan(division, edition: .medine),
                SurahListOptions.pageSpan(division, edition: .coran1441),
                "Juz'/Hizb \(division.number) : les deux éditions devraient donner la même plage"
            )
        }
    }

    /// Une division dont le premier verset n'est indexé nulle part ouvre la
    /// page 1 — le `pages[0] ?? 1` de l'original.
    func testPageFallsBackToOneWhenTheVerseIsNotIndexed() {
        XCTAssertEqual(SurahListOptions.page(0, edition: .coran1441), 1)
        XCTAssertEqual(SurahListOptions.page(6237, edition: .coran1441), 1)
    }

    // MARK: - « J'ai appris jusqu'à »

    /// Le libellé nomme la sourate et le verset du plus GRAND identifiant
    /// mémorisé — pas du plus récemment validé.
    func testLastLearnedNamesTheGreatestMemorisedVerse() {
        let s = state(knowledge: ["746": .perfect])
        XCTAssertEqual(SurahListOptions.lastLearned(s), "Al Mâ'idah • verset 77")
    }

    /// La règle discriminante : un petit verset validé PLUS RÉCEMMENT ne gagne
    /// pas. `memorizedIds` prend `Math.max(...known)`, jamais `memorizedAt`.
    func testLastLearnedTakesTheGreatestVerseAndNotTheMostRecent() {
        var s = state(knowledge: ["2": .perfect, "6000": .review])
        s.memorizedAt = [
            "2": "2026-09-01T00:00:00.000Z",
            "6000": "2019-01-01T00:00:00.000Z",
        ]
        // Le verset 2 est le plus récemment validé, et pourtant c'est le 6000
        // qui est nommé : Al Fajr 7.
        XCTAssertEqual(SurahListOptions.lastLearned(s), "Al Fajr • verset 7")
    }

    /// `perfect` ET `review` comptent ; `learning` ne compte pas.
    func testLastLearnedCountsPerfectAndReviewOnly() {
        XCTAssertEqual(
            SurahListOptions.lastLearned(state(knowledge: ["10": .learning])),
            SurahListOptions.noVerseValidated
        )
        XCTAssertEqual(
            SurahListOptions.lastLearned(state(knowledge: ["10": .learning, "9": .review])),
            "Al Baqarah • verset 2"
        )
        XCTAssertEqual(
            SurahListOptions.lastLearned(state(knowledge: ["10": .learning, "9": .perfect])),
            "Al Baqarah • verset 2"
        )
    }

    /// Aucun verset validé : le libellé de repli, et non une chaîne vide.
    func testLastLearnedOnAFreshStateSaysNothingWasValidated() {
        XCTAssertEqual(SurahListOptions.lastLearned(state()), "Aucun verset validé")
        XCTAssertEqual(SurahListOptions.lastLearned(Program.defaultState()), "Aucun verset validé")
    }

    /// Le séparateur est une PUCE (U+2022), pas le point médian des marque-pages.
    func testLastLearnedUsesABulletSeparator() {
        let label = SurahListOptions.lastLearned(state(knowledge: ["1": .perfect]))
        XCTAssertEqual(label, "Al Fâtiha • verset 1")
        XCTAssertTrue(containsScalar(label, 0x2022))
        XCTAssertFalse(containsScalar(label, 0x00B7))
    }

    // MARK: - Les deux actions de la liste

    /// « Dernière lecture » ouvre `lastRead?.verseId`, ou le verset 1.
    func testLastReadVerseFallsBackToTheFirstVerse() {
        XCTAssertEqual(SurahListOptions.lastReadVerse(state()), 1)
        let read = LastRead(page: 121, verseId: 746, readAt: "2026-05-05T05:05:05.000Z")
        XCTAssertEqual(SurahListOptions.lastReadVerse(state(lastRead: read)), 746)
    }

    /// La carte de pied ouvre la pagination du MOUSHAF sur `reader.testPage`,
    /// pas `studyPage` : c'est ce que fait l'original, qui passe ensuite la
    /// plage à `openReader`.
    func testTajweedRangeOpensTheStoredTestPage() {
        let first = SurahListOptions.tajweedRange(state())
        XCTAssertEqual(first.start, 1)
        XCTAssertEqual(first.end, 7)
        XCTAssertEqual(first, Quran.pageRange(1))

        let stored = SurahListOptions.tajweedRange(state(testPage: 121))
        XCTAssertEqual(stored.start, 746)
        XCTAssertEqual(stored.end, 751)
        XCTAssertEqual(stored, Quran.pageRange(121))
    }

    /// La carte de pied écrit `coranTest` — la préférence partagée, même si
    /// cette version ne sait pas la rendre (elle lit alors le Coran de Médine).
    func testTheTajweedCardWritesTheSharedPreference() {
        XCTAssertEqual(SurahListOptions.tajweedEdition, .coranTest)
        XCTAssertEqual(SurahListOptions.tajweedEdition.rawValue, "coranTest")
    }

    // MARK: - Les textes

    /// Les trois sous-titres du héros, et leurs deux caractères distinctifs :
    /// la PUCE (U+2022) et le guillemet simple OUVrant (U+2018), que l'original
    /// n'a jamais de fermant.
    func testHeroSubtitlesAreExact() {
        XCTAssertEqual(SurahListOptions.heroTitle, "Le Coran")
        XCTAssertEqual(
            SurahListOptions.heroSubtitle(.liste),
            "Mushaf de Médine • Hafs ‘an ‘Âsim • 604 pages"
        )
        XCTAssertEqual(SurahListOptions.heroSubtitle(.juz), "Liste des Juz’ • 30 parties")
        XCTAssertEqual(SurahListOptions.heroSubtitle(.hizb), "Liste des Hizb • 60 parties")

        for mode in SurahListOptions.Mode.allCases {
            XCTAssertTrue(containsScalar(SurahListOptions.heroSubtitle(mode), 0x2022))
        }
        XCTAssertTrue(containsScalar(SurahListOptions.heroSubtitle(.liste), 0x2018))
        XCTAssertFalse(containsScalar(SurahListOptions.heroSubtitle(.liste), 0x2019))
    }

    /// Le préfixe de la carte de progression porte U+2019 — deux fois.
    func testLearnedPrefixCarriesTheTypographicApostrophe() {
        XCTAssertEqual(SurahListOptions.learnedPrefix, "J’ai appris jusqu’à :")
        XCTAssertEqual(
            SurahListOptions.learnedPrefix.unicodeScalars.filter { $0.value == 0x2019 }.count,
            2
        )
    }

    /// L'invite du champ suit la vue : « Rechercher un Juz’ » porte l'apostrophe
    /// typographique, comme le libellé.
    func testSearchPlaceholderFollowsTheMode() {
        XCTAssertEqual(SurahListOptions.searchSurah, "Rechercher une sourate")
        XCTAssertEqual(SurahListOptions.searchPlaceholder(.liste), "Rechercher une sourate")
        XCTAssertEqual(SurahListOptions.searchPlaceholder(.juz), "Rechercher un Juz’")
        XCTAssertEqual(SurahListOptions.searchPlaceholder(.hizb), "Rechercher un Hizb")
        XCTAssertTrue(containsScalar(SurahListOptions.searchPlaceholder(.juz), 0x2019))
    }

    /// Le compte de versets est TOUJOURS au pluriel : l'original écrit
    /// `` `${item.count} versets` `` sans condition, et aucune division n'a un
    /// seul verset (le plus petit en compte 48).
    func testVerseCountIsAlwaysPlural() {
        XCTAssertEqual(SurahListOptions.verseCount(1), "1 versets")
        XCTAssertEqual(SurahListOptions.verseCount(7), "7 versets")
        XCTAssertEqual(SurahListOptions.verseCount(286), "286 versets")
    }

    func testTheRemainingTextsAreExact() {
        XCTAssertEqual(SurahListOptions.noVerseValidated, "Aucun verset validé")
        XCTAssertEqual(SurahListOptions.editKnowledge, "Modifier mes connaissances")
        XCTAssertEqual(SurahListOptions.knowledgeAlertTitle, "Mes connaissances")
        XCTAssertEqual(
            SurahListOptions.knowledgeAlertBody,
            "Modifie tes connaissances depuis ton objectif dans Programme."
        )
        XCTAssertEqual(SurahListOptions.filterButton, "Filtrer les sourates")
        XCTAssertEqual(SurahListOptions.filterAlertMessage, "Lieu de révélation")
        XCTAssertEqual(SurahListOptions.filterCancel, "Annuler")
        XCTAssertEqual(SurahListOptions.emptyState, "Aucun résultat.")
        XCTAssertEqual(SurahListOptions.tajweedTitle, "Coran avec règles de Tajwid")
        XCTAssertEqual(
            SurahListOptions.tajweedSubtitle,
            "Organisation par couleurs pour faciliter votre lecture et votre apprentissage."
        )
        XCTAssertEqual(SurahListOptions.lastReadButton, "Dernière lecture")
        XCTAssertEqual(SurahListOptions.openLabel("Al Fâtiha"), "Ouvrir Al Fâtiha")
        XCTAssertEqual(SurahListOptions.openLabel("Juz’ 1"), "Ouvrir Juz’ 1")
    }

    // MARK: - Cohérence d'ensemble

    /// Chaque ligne de chaque vue a un identifiant unique, un nom non vide, et
    /// des bornes dans le moushaf. Une seule ligne hors bornes ferait échouer
    /// `verseAt` au premier appui.
    func testEveryRowIsWellFormed() {
        let all = rows(.liste) + rows(.juz) + rows(.hizb)
        XCTAssertEqual(all.count, 114 + 30 + 60)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for row in all {
            XCTAssertFalse(row.name.isEmpty)
            XCTAssertGreaterThanOrEqual(row.start, 1)
            XCTAssertLessThanOrEqual(row.end, 6236)
            XCTAssertLessThanOrEqual(row.start, row.end)
            XCTAssertGreaterThan(row.count, 0)
        }
    }

    /// Une ligne de sourate a un arabe et une signification ; une ligne de
    /// division n'a ni l'un ni l'autre. C'est la différence que l'écran exploite
    /// pour décider s'il rend le libellé arabe.
    func testOnlySurahRowsCarryAnArabicLabel() {
        XCTAssertTrue(rows(.liste).allSatisfy { !$0.arabic.isEmpty })
        XCTAssertTrue(rows(.liste).allSatisfy { !$0.meaning.isEmpty })
        XCTAssertTrue(rows(.juz).allSatisfy { $0.arabic.isEmpty })
        XCTAssertTrue(rows(.hizb).allSatisfy { $0.arabic.isEmpty })
        XCTAssertTrue(rows(.juz).allSatisfy { !$0.meaning.isEmpty })
    }
}

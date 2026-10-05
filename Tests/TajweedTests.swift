// TajweedTests.swift
// L'édition « Lecture simplifiée » — port de `tajweedVerse`, `tajweedSpans`,
// `tajweedColor` et `frenchVerse` (`src/core/readerData.ts`) et du rendu
// « verset par verset » (`MushafPage.tsx:34-43`).
//
// CE QUE CES TESTS PROTÈGENT
//   Le texte arabe d'un verset est découpé en fragments colorés par règle de
//   Tajweed. Rien de tout cela ne se voit dans un journal : un décalage d'un
//   seul fragment décale les **couleurs** de tout ce qui suit, et le verset
//   s'affiche — simplement avec les mauvaises règles sur les mauvaises lettres.
//   Un lecteur ne peut pas le voir ; ces tests le peuvent.
//
// LA QUESTION QUI DÉCIDE DE TOUT : L'UNITÉ DE COMPTAGE
//   Les `start` / `end` des annotations indexent le texte. En JavaScript,
//   `[...verse.text]` découpe en **points de code**. En Swift, `Array(text)`
//   découpe en **graphèmes** — une lettre arabe suivie de ses harakat est UN
//   graphème pour plusieurs points de code.
//
//   Mesuré : sur les 6 236 versets, les deux découpages diffèrent **6 236 fois
//   sur 6 236**. Le verset 2:282 (identifiant 289) porte 1 173 points de code
//   pour 680 graphèmes, et sa plus grande fin d'annotation vaut **1 171** :
//   indexer en `Character` sortirait du tableau, donc **planterait** — sur le
//   plus long verset du Coran, précisément celui qu'on ouvre pour vérifier.
//   `testTheCountingUnitIsTheCodePointNotTheGrapheme` épingle les trois nombres.
//
// DEUX PIÈGES DE VÉRITÉ, ET NON DE PRÉSENCE
//   L'original teste des **valeurs** ; Swift distingue `nil` de `""`. Les deux
//   écarts sont mesurés et épinglés ici :
//
//     - `footnotes` vaut `""` sur **4 906** des 6 236 lignes, et l'original ne
//       l'affiche pas (une chaîne vide est fausse). `Translation.footnote` rend
//       donc `nil` dans ce cas — sans quoi 4 906 notes vides s'afficheraient.
//     - `annotations` vaut `[]` sur **63** lignes, et l'original rend alors
//       **un** fragment nu, pas zéro.
//
//   Et un contre-exemple, qui empêche de confondre les deux règles : le verset
//   42:2 (identifiant 4274) rend lui aussi **un seul** fragment, mais coloré —
//   trois annotations `madd_6` voisines ont fusionné. « Un fragment » ne veut
//   donc pas dire « sans règle » : c'est le **rôle** du fragment qui le dit.
//
// LES CHIFFRES SONT MESURÉS, PAS SUPPOSÉS
//   Tous viennent de `_banc/oracle-tajweed.mjs`, qui relit les trois JSON et
//   rejoue les règles de l'original en JavaScript. Le nombre de graphèmes du
//   verset 2:282 (680) vient d'`Intl.Segmenter` (ICU, UAX #29) : c'est une
//   implémentation **indépendante** de celle de Swift, donc une vraie
//   contre-mesure, et non une reformulation.
//
//   Total : 119 032 fragments, 160 au maximum pour un verset (2:282), 60 057
//   annotations, 18 règles, 1 330 notes de traduction.

import XCTest
@testable import Swiftdeepseek

final class TajweedTests: XCTestCase {

    /// Le plus long verset du Coran — Al Baqarah 282. C'est lui qui porte la
    /// plus grande fin d'annotation, et donc la seule mesure qui prouve que
    /// l'indexation en graphèmes planterait.
    private let plusLongVerset = 289

    /// Le dernier verset du Moushaf.
    private let dernierVerset = 6236

    /// Un verset sans aucune annotation — Al Kahf 85.
    private let versetSansRegle = 2225

    /// Le contre-exemple : Al Ash-Shura 2, dont les trois annotations `madd_6`
    /// voisines fusionnent en UN fragment coloré.
    private let versetFusionne = 4274

    // MARK: - Le chargement

    func testTheThreeDataFilesAreLoaded() {
        XCTAssertTrue(TajweedOptions.hasArabic, "le texte et ses règles doivent être chargés")
        XCTAssertTrue(TajweedOptions.hasTranslation, "la traduction doit être chargée")
        XCTAssertTrue(TajweedOptions.isAvailable, "l'édition doit pouvoir s'afficher dans les deux langues")
    }

    // MARK: - `tajweedVerse(id)` et sa garde

    /// La garde de concordance existe (`readerData.ts:17`) et ne se déclenche
    /// sur **aucune** des 6 236 lignes : les deux fichiers s'accordent partout
    /// sur `surah`/`ayah`. C'est la seule façon de le savoir — la garde rend
    /// `nil` en silence, et un décalage d'une ligne colorerait chaque verset avec
    /// les règles du voisin.
    func testTheGuardRendersAllSixThousandTwoHundredThirtySixVerses() {
        var rendus = 0
        for id in 1...dernierVerset where TajweedOptions.verse(id) != nil { rendus += 1 }
        XCTAssertEqual(rendus, 6236)
    }

    func testTheLastVerseIsSurahOneHundredFourteenVerseSix() {
        let verse = TajweedOptions.verse(dernierVerset)
        XCTAssertNotNil(verse)
        XCTAssertFalse(verse?.text.isEmpty ?? true)
        XCTAssertEqual(TajweedOptions.translation(dernierVerset)?.surah, 114)
        XCTAssertEqual(TajweedOptions.translation(dernierVerset)?.ayah, 6)
    }

    /// La borne d'indice est un **ajout** de Swift. En JavaScript, `tajweedText[id-1]`
    /// sur un indice hors bornes rend `undefined`, et la garde rend `undefined`
    /// aussi ; en Swift, `texts[id-1]` sortirait du tableau et **planterait**.
    /// Les trois appelants doivent donc rendre leur vide, pas mourir.
    func testAnOutOfRangeIdentifierRendersNothing() {
        for id in [0, -1, dernierVerset + 1] {
            XCTAssertNil(TajweedOptions.verse(id), "verse(\(id))")
            XCTAssertNil(TajweedOptions.translation(id), "translation(\(id))")
            XCTAssertEqual(TajweedOptions.spans(id), [], "spans(\(id))")
        }
    }

    // MARK: - L'unité de comptage

    /// **LE TEST QUI PORTE TOUT LE FICHIER.**
    ///
    /// Si `spans` indexait en `Character`, la fin d'annotation 1 171 dépasserait
    /// les 680 graphèmes de ce verset : `rule[index]` sortirait du tableau, et
    /// l'application planterait sur le plus long verset du Coran.
    func testTheCountingUnitIsTheCodePointNotTheGrapheme() {
        let verse = TajweedOptions.verse(plusLongVerset)
        XCTAssertNotNil(verse)
        let text = verse?.text ?? ""

        XCTAssertEqual(text.unicodeScalars.count, 1173, "points de code — l'unité que l'original indexe")
        XCTAssertEqual(text.count, 680, "graphèmes selon ICU (UAX #29), indépendant de Swift")

        let finMaximale = verse?.annotations.map(\.end).max() ?? 0
        XCTAssertEqual(finMaximale, 1171, "la plus grande fin d'annotation de tout le Moushaf")

        // La relation qui rend le défaut fatal, énoncée telle quelle :
        XCTAssertGreaterThan(finMaximale, text.count, "indexer en graphèmes sortirait du tableau")
        XCTAssertLessThanOrEqual(finMaximale, text.unicodeScalars.count, "indexer en scalaires reste dedans")
    }

    /// Aucune annotation ne dépasse le texte, sur aucun des 6 236 versets — et
    /// aucune n'est vide ou inversée. La troncature de `spans` est donc une
    /// ceinture : elle ne se déclenche jamais sur les données livrées.
    func testEveryAnnotationStaysInsideTheText() {
        var finMaximale = 0
        for id in 1...dernierVerset {
            guard let verse = TajweedOptions.verse(id) else { continue }
            let scalaires = verse.text.unicodeScalars.count
            for annotation in verse.annotations {
                XCTAssertGreaterThanOrEqual(annotation.start, 0, "verset \(id)")
                XCTAssertLessThan(annotation.start, annotation.end, "verset \(id)")
                XCTAssertLessThanOrEqual(annotation.end, scalaires, "verset \(id)")
                finMaximale = max(finMaximale, annotation.end)
            }
        }
        XCTAssertEqual(finMaximale, 1171)
    }

    // MARK: - `tajweedSpans(id)`

    /// Les fragments recollent exactement le texte, sur les 6 236 versets — et
    /// leur nombre total est celui qu'annonce la mesure.
    ///
    /// La recollure est l'invariant qui attrape une erreur d'indice : un
    /// fragment perdu, dupliqué ou décalé d'un scalaire le rompt, alors qu'un
    /// simple compte de fragments ne le verrait pas.
    func testTheSpansRebuildEveryVerseTextExactly() {
        var total = 0
        for id in 1...dernierVerset {
            guard let verse = TajweedOptions.verse(id) else { continue }
            let fragments = TajweedOptions.spans(id)
            XCTAssertEqual(fragments.map(\.text).joined(), verse.text, "verset \(id)")
            total += fragments.count
        }
        XCTAssertEqual(total, 119032)
    }

    func testTheLongestVerseHasTheMostSpans() {
        XCTAssertEqual(TajweedOptions.spans(plusLongVerset).count, 160)
        XCTAssertEqual(TajweedOptions.spans(262).count, 59, "2:255 — le verset du Trône")
    }

    /// Le découpage du premier verset, au fragment près : ses règles **et** les
    /// longueurs de ses fragments.
    ///
    /// La suite des règles seule ne suffirait pas : deux règles égales séparées
    /// par un fragment nu donneraient la même suite avec des frontières
    /// déplacées. Les longueurs, elles, fixent les frontières.
    func testTheFirstVerseSplitsExactlyAsTheOriginalDoes() {
        let fragments = TajweedOptions.spans(1)
        XCTAssertEqual(fragments.count, 13)
        XCTAssertEqual(
            fragments.map(\.rule),
            [nil, "hamzat_wasl", nil, "hamzat_wasl", "lam_shamsiyyah", nil,
             "madd_2", nil, "hamzat_wasl", "lam_shamsiyyah", nil, "madd_246", nil]
        )
        XCTAssertEqual(
            fragments.map { $0.text.unicodeScalars.count },
            [7, 1, 7, 1, 1, 7, 1, 3, 1, 1, 5, 1, 2]
        )
        XCTAssertEqual(fragments.map { $0.text.unicodeScalars.count }.reduce(0, +), 38)
    }

    /// **Trois annotations, un seul fragment.**
    ///
    /// Al Ash-Shura 2 porte trois annotations `madd_6` adjacentes (0→2, 2→4,
    /// 4→6). La fusion se fait sur l'**égalité de la règle**, pas sur l'identité
    /// de l'annotation : le verset rend donc un fragment, pas trois. Fusionner
    /// par annotation laisserait trois `<Text>` voisins de même couleur — visuel
    /// identique, mais la règle ne serait plus la même, et la première
    /// divergence venue les séparerait.
    func testThreeAdjacentAnnotationsOfTheSameRuleBecomeOneSpan() {
        let verse = TajweedOptions.verse(versetFusionne)
        XCTAssertEqual(verse?.annotations.count, 3)
        XCTAssertEqual(verse?.surah, 42)
        XCTAssertEqual(verse?.ayah, 2)

        let fragments = TajweedOptions.spans(versetFusionne)
        XCTAssertEqual(fragments.count, 1)
        XCTAssertEqual(fragments.first?.rule, "madd_6")
        XCTAssertEqual(fragments.first?.text, verse?.text)
    }

    /// Un verset sans annotation rend **un** fragment nu — pas zéro, pas un par
    /// lettre. Rendre `[]` laisserait la carte de verset sans texte.
    func testAVerseWithoutAnyRuleRendersOneBareSpan() {
        let verse = TajweedOptions.verse(versetSansRegle)
        XCTAssertEqual(verse?.annotations.isEmpty, true)

        let fragments = TajweedOptions.spans(versetSansRegle)
        XCTAssertEqual(fragments.count, 1)
        XCTAssertNil(fragments.first?.rule)
        XCTAssertEqual(fragments.first?.text, verse?.text)
    }

    func testSixtyThreeVersesCarryNoRuleAtAll() {
        var sans = 0
        for id in 1...dernierVerset where TajweedOptions.verse(id)?.annotations.isEmpty == true { sans += 1 }
        XCTAssertEqual(sans, 63)
    }

    /// **Un fragment ne veut pas dire « sans règle ».**
    ///
    /// Le contre-exemple du verset 42:2 ci-dessus. Ce test l'énonce contre le
    /// verset 18:85, pour qu'un futur raccourci — « `count == 1` donc nu » — se
    /// casse ici au lieu de passer inaperçu.
    func testASingleSpanDoesNotMeanRuleless() {
        XCTAssertEqual(TajweedOptions.spans(versetFusionne).count, 1)
        XCTAssertNotNil(TajweedOptions.spans(versetFusionne).first?.rule)
        XCTAssertEqual(TajweedOptions.spans(versetSansRegle).count, 1)
        XCTAssertNil(TajweedOptions.spans(versetSansRegle).first?.rule)
    }

    // MARK: - `tajweedColor(rule)`

    /// Les six branches de la table, avec le **nombre de règles** que chacune
    /// attrape sur les 18 livrées.
    ///
    /// Le compte par branche est ce qui rend le test utile : une septième
    /// couleur, ou une règle qui change de branche, déplace un de ces six
    /// nombres.
    func testTheColorTableHasExactlySixBranches() {
        var parCouleur: [String: [String]] = [:]
        for entree in TajweedOptions.ruleVocabulary {
            parCouleur[TajweedOptions.color(entree.rule), default: []].append(entree.rule)
        }
        XCTAssertEqual(parCouleur.count, 6)
        XCTAssertEqual(parCouleur["#B45375"]?.count, 5, "madd")
        XCTAssertEqual(parCouleur["#3A779B"]?.count, 3, "ikhfa et iqlab")
        XCTAssertEqual(parCouleur["#6F5FA5"]?.count, 6, "idghaam et ghunnah")
        XCTAssertEqual(parCouleur["#B05E32"]?.count, 1, "qalqalah")
        XCTAssertEqual(parCouleur["#A2A2A2"]?.count, 1, "silent")
        XCTAssertEqual(parCouleur["#A26C44"]?.count, 2, "le défaut")
    }

    /// **L'ordre des branches est la règle.** Les deux préfixes sont testés avant
    /// les égalités : `ikhfa_shafawi` commence par `ikhfa`, et
    /// `idghaam_mutanajisayn` par `idghaam`. Renverser l'ordre enverrait ces
    /// règles dans le défaut sans que rien ne le dise.
    func testThePrefixBranchesAreTestedBeforeTheEqualities() {
        XCTAssertEqual(TajweedOptions.color("ikhfa_shafawi"), "#3A779B")
        XCTAssertEqual(TajweedOptions.color("idghaam_mutanajisayn"), "#6F5FA5")
        XCTAssertEqual(TajweedOptions.color("madd_munfasil"), "#B45375")
        XCTAssertEqual(TajweedOptions.color("madd_muttasil"), "#B45375")
        XCTAssertEqual(TajweedOptions.color("iqlab"), "#3A779B")
        XCTAssertEqual(TajweedOptions.color("ghunnah"), "#6F5FA5")
    }

    /// Les deux règles les plus fréquentes du Moushaf tombent dans le **défaut**,
    /// sans le dire : `hamzat_wasl` (13 252 annotations) et `lam_shamsiyyah`
    /// (2 733). Une règle inconnue y tombe aussi — c'est le comportement de
    /// l'original, et le figer vaut mieux que le découvrir.
    func testAnUnknownRuleFallsIntoTheDefaultBranchSilently() {
        XCTAssertEqual(TajweedOptions.color("hamzat_wasl"), "#A26C44")
        XCTAssertEqual(TajweedOptions.color("lam_shamsiyyah"), "#A26C44")
        XCTAssertEqual(TajweedOptions.color("regle_qui_n_existe_pas"), "#A26C44")
        XCTAssertEqual(TajweedOptions.color(""), "#A26C44", "une règle vide est fausse en JavaScript aussi")
    }

    /// Le vocabulaire porte les 18 règles et **toutes** les annotations : la
    /// somme de ses comptes vaut 60 057, le total mesuré.
    func testTheRuleVocabularyCountsEveryAnnotation() {
        XCTAssertEqual(TajweedOptions.ruleVocabulary.count, 18)
        // Pas de `map(\.annotations)` : Swift n'a pas de chemin de clé vers un
        // élément de tuple. La fermeture, elle, compile.
        XCTAssertEqual(TajweedOptions.ruleVocabulary.map { $0.annotations }.reduce(0, +), 60057)

        let comptes = TajweedOptions.ruleVocabulary.map { $0.annotations }
        XCTAssertEqual(comptes, comptes.sorted(by: >), "trié par fréquence décroissante")
        XCTAssertEqual(TajweedOptions.ruleVocabulary.first?.rule, "hamzat_wasl")
    }

    /// Un fragment nu prend la couleur de **texte du thème**, que ce fichier ne
    /// connaît pas : elle est passée par l'écran. C'est la traduction de
    /// `` span.rule ? tajweedColor(span.rule) : colors.text `` (`MushafPage.tsx:39`).
    func testABareSpanTakesTheThemeTextColor() {
        let nu = TajweedOptions.Span(text: "x", rule: nil)
        XCTAssertEqual(TajweedOptions.color(of: nu, textColor: "#241C2B"), "#241C2B")

        let colore = TajweedOptions.Span(text: "x", rule: "madd_2")
        XCTAssertEqual(TajweedOptions.color(of: colore, textColor: "#241C2B"), "#B45375")
    }

    // MARK: - `frenchVerse(id)` et la note de bas de verset

    /// **LE PIÈGE DE VÉRITÉ.**
    ///
    /// `translation-fr-rashid.json` porte la clé `footnotes` sur les 6 236
    /// lignes, et elle vaut `""` sur 4 906 d'entre elles. L'original écrit
    /// `translation?.footnotes ? <Label> : null` : une chaîne **vide** est
    /// fausse, donc la note ne s'affiche pas. Un `if let` sur un `String?`
    /// décodé, lui, verrait `Optional("")` — non `nil` — et afficherait une note
    /// vide sous 4 906 versets.
    func testTheFootnoteIsHiddenWhenItIsAnEmptyString() {
        XCTAssertEqual(TajweedOptions.translation(3)?.footnotes, "", "la clé est présente et vide")
        XCTAssertNil(TajweedOptions.translation(3)?.footnote, "donc la note ne s'affiche pas")

        XCTAssertNotNil(TajweedOptions.translation(1)?.footnote, "1:1 porte une vraie note")
    }

    func testOneThousandThreeHundredThirtyVersesCarryANote() {
        var avecNote = 0
        for id in 1...dernierVerset where TajweedOptions.translation(id)?.footnote != nil { avecNote += 1 }
        XCTAssertEqual(avecNote, 1330)
    }

    /// Contrairement au Tajweed, la traduction ne porte **aucune** garde de
    /// concordance : l'original prend la ligne telle quelle
    /// (`readerData.ts:14`). Le test fige les deux conséquences mesurées :
    /// aucune ligne manquante, aucune traduction vide.
    func testEveryVerseHasATranslation() {
        var vides = 0
        for id in 1...dernierVerset {
            guard let translation = TajweedOptions.translation(id) else {
                XCTFail("traduction absente au verset \(id)")
                continue
            }
            if translation.translation.isEmpty { vides += 1 }
        }
        XCTAssertEqual(vides, 0)
    }

    // MARK: - L'état de la carte

    /// L'ordre des `?:` de `MushafPage.tsx:36` est une règle, pas un goût :
    /// `difficult` passe avant la sélection, qui passe avant la lecture.
    ///
    /// `.bookmarked` et `.playing` rendent la **même** couleur aujourd'hui
    /// (`colors.selected`) — c'est ce que dit l'original. Les distinguer quand
    /// même laisse le jour où l'une des deux changera, sans réécrire la règle.
    func testTheCardStateFollowsTheOrderOfTheOriginal() {
        XCTAssertEqual(TajweedOptions.CardState.of(difficult: true, bookmarked: true, playing: true), .difficult)
        XCTAssertEqual(TajweedOptions.CardState.of(difficult: false, bookmarked: true, playing: true), .bookmarked)
        XCTAssertEqual(TajweedOptions.CardState.of(difficult: false, bookmarked: false, playing: true), .playing)
        XCTAssertEqual(TajweedOptions.CardState.of(difficult: false, bookmarked: false, playing: false), .plain)
        XCTAssertEqual(TajweedOptions.CardState.of(difficult: true, bookmarked: false, playing: false), .difficult)
    }

    // MARK: - La typographie du texte arabe

    /// Les deux bornes sont des pixels **indépendants de la largeur** : en deçà
    /// de 321 pt le texte ne rétrécit plus, au-delà de 436 pt il ne grandit plus.
    /// Les quatre valeurs de ce test tombent hors de la zone proportionnelle,
    /// donc elles sont **exactes**.
    func testTheArabicTypographyIsClampedAtBothEnds() {
        XCTAssertEqual(TajweedOptions.arabicFontSize(width: 200), 25, "sous le plancher")
        XCTAssertEqual(TajweedOptions.arabicFontSize(width: 600), 34, "au-dessus du plafond")
        XCTAssertEqual(TajweedOptions.arabicLineHeight(width: 200), 48, "sous le plancher")
        XCTAssertEqual(TajweedOptions.arabicLineHeight(width: 600), 62, "au-dessus du plafond")

        // Les seuils eux-mêmes : 25 / .078 ≈ 321 pt, 34 / .078 ≈ 436 pt.
        XCTAssertEqual(TajweedOptions.arabicFontSize(width: 436), 34, "34,008 → plafonné")
        XCTAssertEqual(TajweedOptions.arabicLineHeight(width: 300), 48, "43,5 → plancher")
    }

    /// Entre les bornes, la taille suit la largeur — et le facteur de taille de
    /// texte de l'utilisateur s'applique **après** le plafonnement
    /// (`Math.min(34, ...) * textScale`, `MushafPage.tsx:39`). L'appliquer avant
    /// plafonnerait deux fois, et le grossissement ne dépasserait jamais 34.
    func testTheArabicTypographyFollowsTheWidthInBetween() {
        XCTAssertEqual(TajweedOptions.arabicFontSize(width: 400), 31.2, accuracy: 0.0001)
        XCTAssertEqual(TajweedOptions.arabicLineHeight(width: 400), 58, accuracy: 0.0001)

        XCTAssertEqual(TajweedOptions.arabicFontSize(width: 400, textScale: 2), 62.4, accuracy: 0.0001)
        XCTAssertEqual(TajweedOptions.arabicLineHeight(width: 600, textScale: 2), 124, accuracy: 0.0001)
    }

    // MARK: - Les textes

    /// Les six libellés de l'original, plus le repère de fin de verset.
    ///
    /// Le repère est vérifié par son **point de code** et non par sa lettre :
    /// `۞` est U+06DE, et une transcription fautive dans ce fichier de test
    /// passerait inaperçue si l'on comparait deux fois la même faute.
    func testTheHeadersFootersAndLabelAreTheOriginals() {
        XCTAssertEqual(TajweedOptions.header(page: 12, language: .arabic), "Lecture simplifiée · page 12")
        XCTAssertEqual(TajweedOptions.header(page: 12, language: .french), "Traduction française du sens des versets")
        XCTAssertEqual(TajweedOptions.footer(language: .arabic), "Tajweed : cpfair, CC BY 4.0 · texte Hafs Tanzil 2017")
        XCTAssertEqual(TajweedOptions.footer(language: .french), "Traduction du sens : Rachid Maach · QuranEnc")
        XCTAssertEqual(TajweedOptions.missingTranslation, "Traduction indisponible.")

        XCTAssertEqual(TajweedOptions.ornament.unicodeScalars.count, 1)
        XCTAssertEqual(TajweedOptions.ornament.unicodeScalars.first?.value, 0x06DE)
        XCTAssertEqual(TajweedOptions.ornamentGap, " ", "l'espace avant ۞ garde la couleur du texte, pas l'or")

        // L'en-tête français ignore la page — c'est ce que dit l'original.
        XCTAssertEqual(TajweedOptions.header(page: 604, language: .french), TajweedOptions.frenchHeader)

        XCTAssertEqual(TajweedOptions.verseLabel(Quran.verses[0]), "Al Fâtiha · verset 1")
        XCTAssertEqual(TajweedOptions.verseLabel(Quran.verses[1]), "Al Fâtiha · verset 2")
    }
}

// TajweedListTests.swift
// L'ÉCRAN de « Lecture simplifiée » : les cartes, leurs couleurs, et le rail de
// séance.
//
// POURQUOI UN FICHIER À PART DE `TajweedTests`
//   `TajweedTests` éprouve le **modèle** : le découpage en fragments, les
//   couleurs des règles, la vérité des notes. Ce fichier-ci éprouve ce que
//   l'écran en fait — les deux couleurs littérales d'une carte difficile, le
//   pont entre une hauteur de ligne absolue et un écart additif, et la géométrie
//   du rail. Ce sont deux responsabilités, et deux fichiers : un défaut d'écran
//   ne doit pas se cacher derrière vingt-cinq tests de données.
//
// CE QUE CES TESTS PROTÈGENT, ET QU'ON NE VERRAIT PAS
//   Les deux couleurs d'une carte difficile (`#FCE8E8`, `#D97878`) ne sont pas
//   dans la palette : l'original les écrit en clair, et ce ne sont PAS celles de
//   la mise en évidence d'une page (`#E85B5B`). Se tromper de constante ne
//   produit aucune erreur — seulement une carte de la mauvaise couleur, sur un
//   signal de difficulté. Et le rail de la liste n'a pas la règle de celui de la
//   marge : une carte, une pastille, sans regroupement. Confondre les deux règles
//   donnerait un rail plausible et faux.
//
// LA CONVERSION DES SIX COULEURS EST ÉPROUVÉE ICI
//   `TajweedOptions.color(of:textColor:)` compose la couleur d'une règle — une
//   **chaîne** — avec celle du texte du thème — une `Color`. Le pont est
//   `Theme.color(hexString:)`, qui rend `nil` sur une chaîne qui n'est pas six
//   chiffres hexadécimaux ; le repli est alors la couleur de texte, c'est-à-dire
//   un fragment **nu**. Ce repli ne doit pas se déclencher : le test ci-dessous
//   le vérifie sur les 18 règles livrées, et pas seulement sur une.

import XCTest
import SwiftUI
import UIKit
@testable import Swiftdeepseek

final class TajweedListTests: XCTestCase {

    // MARK: - Les couleurs d'une carte

    /// Les deux littérales de `MushafPage.tsx:36`, et le fait qu'elles se
    /// convertissent — sans quoi le repli silencieux de `TajweedCardStyle`
    /// peindrait la carte en papier.
    func testTheTwoDifficultColorsAreTheOriginals() {
        XCTAssertEqual(TajweedCardStyle.difficultBackgroundHex, "#FCE8E8")
        XCTAssertEqual(TajweedCardStyle.difficultBorderHex, "#D97878")

        XCTAssertEqual(
            TajweedCardStyle.difficultBackground,
            Theme.color(hexString: "#FCE8E8"),
            "la conversion doit réussir : sinon le repli se déclenche"
        )
        XCTAssertEqual(TajweedCardStyle.difficultBorder, Theme.color(hexString: "#D97878"))
    }

    /// Ce ne sont **pas** les couleurs de la mise en évidence d'une page : un
    /// verset difficile est rouge vif sur une page, et rose pâle en carte.
    func testTheCardRedIsNotThePageRed() {
        XCTAssertNotEqual(
            TajweedCardStyle.difficultBackground,
            Color(VerseHighlightStyle.difficultRed),
            "le fond de carte n'est pas le rouge de la page"
        )
        XCTAssertNotEqual(TajweedCardStyle.difficultBorder, Color(VerseHighlightStyle.difficultRed))
    }

    /// L'ordre des `?:` de `MushafPage.tsx:36` — `difficult` d'abord, puis la
    /// sélection, puis le papier. `.bookmarked` et `.playing` rendent la **même**
    /// couleur : c'est ce que dit l'original.
    func testTheCardBackgroundFollowsTheStateOrder() {
        let palette = Theme.feminine

        XCTAssertEqual(
            TajweedCardStyle.background(.difficult, palette: palette),
            TajweedCardStyle.difficultBackground
        )
        XCTAssertEqual(TajweedCardStyle.background(.bookmarked, palette: palette), palette.selected)
        XCTAssertEqual(TajweedCardStyle.background(.playing, palette: palette), palette.selected)
        XCTAssertEqual(TajweedCardStyle.background(.plain, palette: palette), palette.paper)

        XCTAssertNotEqual(TajweedCardStyle.background(.difficult, palette: palette), palette.selected)
        XCTAssertNotEqual(TajweedCardStyle.background(.plain, palette: palette), palette.selected)
    }

    /// `borderWidth: difficult ? 1 : 0`, et `borderColor` qui suit — la couleur
    /// est définie pour les quatre états, mais seule la carte difficile la peint.
    func testTheCardBorderIsDrawnOnlyForADifficultVerse() {
        let palette = Theme.classic

        XCTAssertEqual(TajweedCardStyle.borderWidth(.difficult), 1)
        XCTAssertEqual(TajweedCardStyle.borderWidth(.bookmarked), 0)
        XCTAssertEqual(TajweedCardStyle.borderWidth(.playing), 0)
        XCTAssertEqual(TajweedCardStyle.borderWidth(.plain), 0)

        XCTAssertEqual(
            TajweedCardStyle.borderColor(.difficult, palette: palette),
            TajweedCardStyle.difficultBorder
        )
        for state in [TajweedOptions.CardState.bookmarked, .playing, .plain] {
            XCTAssertEqual(TajweedCardStyle.borderColor(state, palette: palette), palette.green2)
        }
    }

    // MARK: - Le pont des couleurs

    /// Les 18 règles livrées se convertissent toutes, et aucune ne retombe sur la
    /// couleur de texte — le repli de `color(of:textColor:)`.
    ///
    /// C'est le contrôle qui manquait au banc : le banc compare les six chaînes
    /// de la table au fichier de référence, mais il ne peut pas dire si elles
    /// **se peignent**.
    func testEveryRuleColorBecomesAColorAndNoneFallsBack() {
        let texte = Theme.white.text
        var vues = Set<String>()

        for (rule, _) in TajweedOptions.ruleVocabulary {
            let hex = TajweedOptions.color(rule)
            XCTAssertNotNil(Theme.color(hexString: hex), "« \(hex) » doit se convertir")
            vues.insert(hex)

            let peint = TajweedOptions.color(
                of: TajweedOptions.Span(text: "x", rule: rule),
                textColor: texte
            )
            XCTAssertNotEqual(peint, texte, "« \(rule) » ne doit pas retomber sur le texte")
        }

        XCTAssertEqual(vues.count, 6, "les 18 règles tombent dans six couleurs")
        XCTAssertEqual(vues, ["#B45375", "#3A779B", "#6F5FA5", "#B05E32", "#A2A2A2", "#A26C44"])
    }

    /// Un fragment **nu** prend la couleur de texte, et pas la couleur du défaut
    /// de la table (`#A26C44`) : c'est la différence entre « sans règle » et
    /// « règle inconnue », et elle se voit.
    func testABareSpanTakesTheTextColorAndNotTheDefaultBranch() {
        let texte = Theme.white.text
        let nu = TajweedOptions.color(of: TajweedOptions.Span(text: "x", rule: nil), textColor: texte)

        XCTAssertEqual(nu, texte)
        XCTAssertNotEqual(nu, Theme.color(hexString: TajweedOptions.color("")))
    }

    // MARK: - La hauteur de ligne

    /// La hauteur de ligne de l'original est **absolue**, celle de SwiftUI
    /// **additive**. L'invariant qui le dit : la hauteur de ligne de la police
    /// plus l'écart retombe exactement sur la hauteur de l'original.
    func testTheLineSpacingBridgesTheAbsoluteLineHeight() {
        for (taille, hauteur) in [(CGFloat(25), CGFloat(48)), (31.2, 58), (34, 62), (16, 25)] {
            let ecart = TajweedCardStyle.lineSpacing(fontSize: taille, lineHeight: hauteur)
            let totale = UIFont.systemFont(ofSize: taille).lineHeight + ecart
            XCTAssertEqual(totale, hauteur, accuracy: 0.0001,
                           "la ligne doit faire \(hauteur) pt, comme dans l'original")
        }
    }

    /// Et l'écart du texte arabe suit les deux formules du modèle, sur toute la
    /// plage où elles s'appliquent : il est toujours **positif**, donc la borne
    /// `max(0, …)` ne se déclenche pas.
    func testTheArabicLineSpacingIsPositiveWhereTheFormulaApplies() {
        for largeur in [CGFloat(200), 320, 400, 436, 600] {
            XCTAssertGreaterThan(
                TajweedCardStyle.arabicLineSpacing(width: largeur, textScale: 1), 0,
                "largeur \(largeur)"
            )
        }
        // L'écart croît avec la largeur, comme la hauteur de ligne qu'il complète.
        XCTAssertLessThan(
            TajweedCardStyle.arabicLineSpacing(width: 200, textScale: 1),
            TajweedCardStyle.arabicLineSpacing(width: 600, textScale: 1)
        )
    }

    // MARK: - Le rail de séance

    /// Les positions telles que `onLayout` les rapporte : la boîte de la carte,
    /// marge du bas **exclue**.
    private func mesureCartes(_ ids: [Int], hauteur: CGFloat = 80, ecart: CGFloat = 88) -> [Int: CGRect] {
        var out: [Int: CGRect] = [:]
        for (rang, id) in ids.enumerated() {
            out[id] = CGRect(x: 12, y: CGFloat(rang) * ecart, width: 300, height: hauteur)
        }
        return out
    }

    /// La barre part du **haut du premier** actif et va jusqu'au **bas du
    /// dernier** — moins les 10 pt des deux côtés, qui la font finir au centre de
    /// la dernière pastille.
    func testTheRailSpansFromTheFirstActiveCardToTheBottomOfTheLast() throws {
        let positions = mesureCartes([1, 2, 3])
        let session = MarginAnnotations.Session(range: VerseRange(start: 1, end: 2), through: 1)

        let active = TajweedSessionRail.activeIDs([1, 2, 3], session: session, positions: positions)
        XCTAssertEqual(active, [1, 2])

        // Dépliée avant d'être comparée : une géométrie dérivée se compare avec
        // une tolérance, jamais à l'unité près — la leçon des runs #14 à #16.
        let bar = try XCTUnwrap(TajweedSessionRail.bar(active: active, positions: positions))
        XCTAssertEqual(bar.minX, 10, accuracy: 0.0001, "la barre passe par le centre des pastilles")
        XCTAssertEqual(bar.width, 1, accuracy: 0.0001)
        XCTAssertEqual(bar.minY, 10, accuracy: 0.0001, "10 pt sous le haut du premier actif")
        XCTAssertEqual(bar.height, 158, accuracy: 0.0001, "jusqu'au bas du dernier, moins 10 pt")
    }

    /// Un verset de la plage qui n'a **pas** de position n'est pas actif : il
    /// n'est pas sur cette page, et il n'aurait ni pastille ni place dans la
    /// barre. La barre saute alors par-dessus.
    func testTheRailSkipsVersesWhosePositionIsUnknown() {
        let positions = mesureCartes([1, 3], hauteur: 80, ecart: 88)
        let session = MarginAnnotations.Session(range: VerseRange(start: 1, end: 3), through: 0)

        let active = TajweedSessionRail.activeIDs([1, 2, 3], session: session, positions: positions)
        XCTAssertEqual(active, [1, 3], "le verset 2 n'est pas mesuré, donc pas actif")
        XCTAssertNil(TajweedSessionRail.dot(2, positions: positions))

        // La barre couvre bien jusqu'au TROISIÈME, et pas jusqu'au deuxième.
        let bar = TajweedSessionRail.bar(active: active, positions: positions)
        XCTAssertEqual(bar?.height, (88 + 80) - 10)
    }

    /// Aucun verset actif sur cette page : rien à dessiner, et surtout pas une
    /// barre de hauteur négative.
    func testThereIsNoRailWithoutAnActiveVerse() {
        let positions = mesureCartes([1, 2])
        let session = MarginAnnotations.Session(range: VerseRange(start: 5, end: 6), through: 4)

        let active = TajweedSessionRail.activeIDs([1, 2], session: session, positions: positions)
        XCTAssertEqual(active, [])
        XCTAssertNil(TajweedSessionRail.bar(active: active, positions: positions))
    }

    /// Un seul verset actif : la barre vaut la hauteur de la carte moins 10, et
    /// reste **positive** — une carte fait au moins 20 pt.
    func testTheRailHeightIsPositiveForASingleActiveCard() {
        let positions = mesureCartes([1])
        let session = MarginAnnotations.Session(range: VerseRange(start: 1, end: 1), through: 0)

        let active = TajweedSessionRail.activeIDs([1], session: session, positions: positions)
        let bar = TajweedSessionRail.bar(active: active, positions: positions)
        XCTAssertEqual(bar?.height, 70)
        XCTAssertGreaterThan(bar?.height ?? 0, 0)
    }

    /// Les pastilles : une par actif, dans l'ordre de la page, à 10 pt sous le
    /// haut de leur carte, et larges de 20.
    func testTheDotsAreOnePerActiveVerseInOrder() throws {
        let positions = mesureCartes([1, 2, 3])
        let session = MarginAnnotations.Session(range: VerseRange(start: 1, end: 3), through: 1)

        let active = TajweedSessionRail.activeIDs([1, 2, 3], session: session, positions: positions)
        XCTAssertEqual(active, [1, 2, 3])

        for (rang, id) in active.enumerated() {
            let dot = try XCTUnwrap(TajweedSessionRail.dot(id, positions: positions))
            XCTAssertEqual(dot.minX, 0, accuracy: 0.0001, "la pastille part du bord gauche")
            XCTAssertEqual(dot.width, 20, accuracy: 0.0001)
            XCTAssertEqual(dot.height, 20, accuracy: 0.0001)
            XCTAssertEqual(dot.minY, CGFloat(rang) * 88 + 10, accuracy: 0.0001)
        }
    }

    /// La pastille est remplie **jusqu'à `through` inclus** —
    /// `backgroundColor: id <= sessionThrough ? sessionColor : colors.paper`.
    func testTheDotsAreFilledUpToThroughInclusive() {
        XCTAssertTrue(TajweedSessionRail.isFilled(1, through: 1))
        XCTAssertTrue(TajweedSessionRail.isFilled(3, through: 3))
        XCTAssertFalse(TajweedSessionRail.isFilled(4, through: 3))
        XCTAssertFalse(TajweedSessionRail.isFilled(1, through: 0), "séance jamais ouverte")
        XCTAssertFalse(TajweedSessionRail.isFilled(2, through: -1))
    }

    // MARK: - L'édition est atteignable

    /// Le rendu ne sert à rien s'il est inatteignable : `displayed(stored:)` ne
    /// laisse passer que les éditions lisibles, donc cette ligne est ce qui relie
    /// `ReaderView` à la liste.
    func testTheTajweedEditionIsOfferedAndTheOtherTwoAreNot() {
        XCTAssertTrue(QuranEdition.tajweed.isAvailable)
        XCTAssertEqual(QuranEdition.tajweed.isAvailable, TajweedOptions.isAvailable)
        XCTAssertFalse(QuranEdition.tajweedPages.isAvailable)
        XCTAssertFalse(QuranEdition.coranTest.isAvailable)

        XCTAssertTrue(QuranEdition.available.contains(.tajweed))
        XCTAssertFalse(QuranEdition.available.contains(.tajweedPages))
        XCTAssertFalse(QuranEdition.available.contains(.coranTest))
    }
}

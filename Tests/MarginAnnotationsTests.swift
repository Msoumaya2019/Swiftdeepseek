// MarginAnnotationsTests.swift
// Les repères de progression de séance dans la marge du Moushaf.
//
// POURQUOI CES TESTS EXISTENT
//   Le regroupement des versets par ligne et la position du rail tiennent, dans
//   l'application d'origine, dans une fonction de sept lignes très dense
//   (`src/core/marginAnnotations.ts`) et une seule ligne d'affichage
//   (`MushafPage.tsx:53`). Trois règles y sont **silencieuses** : s'y tromper ne
//   lève aucune erreur, cela pose seulement un repère au mauvais endroit ou
//   raccourcit le rail.
//     1. un verset à cheval sur deux lignes n'apparaît qu'UNE fois, sur la
//        première ligne dans l'ordre (ligne, puis y) ;
//     2. `bottom` se calcule sur TOUTES les régions du verset, pas seulement sur
//        la ligne retenue — c'est ce qui étend le rail jusqu'au bas réel ;
//     3. le diamètre d'une pastille dépend de la place libre À GAUCHE de la
//        page, donc de la boîte de page mesurée dans la vue entière.
//
// LES VALEURS ATTENDUES SONT MESURÉES, PAS DÉDUITES DU CODE
//   Tous les nombres de ce fichier viennent de `_banc/oracle-margin.mjs`, qui
//   charge le VRAI `src/core/marginAnnotations.ts` du dépôt de référence — en
//   retirant mécaniquement ses annotations de type — et le fait tourner sur les
//   VRAIS fichiers de rectangles, page par page. Ce banc vérifie au passage que
//   la formulation retenue pour le portage donne exactement les mêmes nombres
//   que `MushafPage.tsx:53` transcrit littéralement, à trois valeurs de
//   `marginGutter` près dont deux donnent des diamètres différents.
//
//   Les dériver du code testé reviendrait à comparer le code à lui-même.
//
// LA HAUTEUR DES PASTILLES, ET CE QUE CES TESTS EN DISENT
//   La hauteur d'une pastille vaut au moins son diamètre, et grandit vers le bas
//   quand son texte passe à la ligne. La mesure du texte demande UIKit, donc
//   `MarginAnnotations` la reçoit en paramètre. Les tests ci-dessous utilisent le
//   défaut — qui rend zéro, donc `hauteur == diamètre` — parce que c'est la
//   hauteur MINIMALE, celle qui ne dépend d'aucune police. Le cas du texte replié
//   a son propre test, avec une mesure explicite.

import XCTest
@testable import Swiftdeepseek

final class MarginAnnotationsTests: XCTestCase {

    // MARK: Les deux pages de référence

    /// La vue de référence des mesures figées — un téléphone de 390 × 700.
    private let phone = CGRect(x: 0, y: 0, width: 390, height: 700)

    /// Une vue dont le ratio n'est PAS celui de la page : c'est le cas où
    /// l'ancrage sur la boîte de page se distingue de l'ancrage sur la vue.
    private let wide = CGRect(x: 0, y: 0, width: 1200, height: 3000)

    private let coran1441Size = CGSize(width: 1440, height: 2320)
    private let medineSize = CGSize(width: 1920, height: 3106)

    /// La plage de la page 1, et le `through` des mesures figées.
    private let firstPage = VerseRange(start: 1, end: 7)
    private let firstThrough = 2

    private func layout(
        _ source: VerseBounds.Source,
        page: Int = 1,
        in bounds: CGRect? = nil,
        padding: CGFloat? = nil,
        through: Int? = nil,
        textHeight: MarginAnnotations.TextHeight = { _, _, _ in 0 }
    ) -> MarginAnnotations.Layout {
        let isCoran1441 = source == .coran1441
        return MarginAnnotations.layout(
            regions: MarginAnnotations.regions(page: page, source: source),
            start: firstPage.start,
            end: firstPage.end,
            through: through ?? firstThrough,
            in: bounds ?? phone,
            imageSize: isCoran1441 ? coran1441Size : medineSize,
            padding: padding ?? (isCoran1441 ? 0 : 2),
            textHeight: textHeight
        )
    }

    private func assertClose(
        _ actual: [CGFloat],
        _ expected: [CGFloat],
        accuracy: CGFloat = 0.001,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, "\(message) — nombre d'éléments", file: file, line: line)
        for (index, pair) in zip(actual, expected).enumerated() {
            XCTAssertEqual(
                pair.0, pair.1, accuracy: accuracy,
                "\(message) — élément \(index)", file: file, line: line
            )
        }
    }

    // MARK: Le fichier est exploitable, page par page

    /// Les 604 pages des deux éditions rendent des régions, et **aucune ligne
    /// n'est écartée**.
    ///
    /// Le second point est le contrôle de garde : `regions` écarte une ligne dont
    /// le couple (sourate, verset) ne désigne aucun verset. Un `Quran.verseID`
    /// trop strict ferait disparaître des versets entiers sans rien dire — les
    /// totaux, eux, le disent.
    func testEveryPageYieldsRegionsAndNoRowIsDropped() {
        var empty: [String] = []
        var total1441 = 0
        var totalMedine = 0

        for page in 1...604 {
            let coran1441 = MarginAnnotations.regions(page: page, source: .coran1441)
            let medine = MarginAnnotations.regions(page: page, source: .medine)
            if coran1441.isEmpty { empty.append("1441:\(page)") }
            if medine.isEmpty { empty.append("medine:\(page)") }
            total1441 += coran1441.count
            totalMedine += medine.count
        }

        XCTAssertEqual(empty, [], "aucune page ne doit être vide")
        // Les totaux des fichiers de rectangles, mesurés par le banc.
        XCTAssertEqual(total1441, 13_273)
        XCTAssertEqual(totalMedine, 13_766)
    }

    /// Les fractions se rapportent à la taille de page de la SOURCE.
    ///
    /// Les deux éditions n'ont ni la même taille ni les mêmes valeurs : lire
    /// `bounds.json` pour une page du 1441 donnerait des fractions plausibles sur
    /// une page qui n'est pas la même.
    func testTheRegionsAreFractionsOfTheSourcePage() {
        let coran1441 = MarginAnnotations.regions(page: 1, source: .coran1441)
        XCTAssertEqual(coran1441.count, 7)
        // Mesuré : le verset 1 de la page 1 est sur la bande 5 (0-basée), à
        // x = 0.2445 et y = 0.321429, d'une hauteur de 0.1 — 232 / 2320.
        XCTAssertEqual(coran1441[0].id, 1)
        XCTAssertEqual(coran1441[0].ayah, 1)
        XCTAssertEqual(coran1441[0].line, 5)
        XCTAssertEqual(coran1441[0].x, 0.2445, accuracy: 0.000001)
        XCTAssertEqual(coran1441[0].y, 0.321429, accuracy: 0.000001)
        XCTAssertEqual(coran1441[0].height, 0.1, accuracy: 0.000001)

        let medine = MarginAnnotations.regions(page: 1, source: .medine)
        XCTAssertEqual(medine.count, 7)
        // La convention de ligne n'est pas la même : 1-basée ici, 0-basée pour
        // le 1441. Le regroupement n'en dépend pas, mais une confusion des deux
        // fichiers, elle, se verrait.
        XCTAssertEqual(medine[0].line, 2)
        XCTAssertEqual(medine[0].x, 0.326563, accuracy: 0.000001)
        XCTAssertEqual(medine[0].y, 0.107856, accuracy: 0.000001)
        XCTAssertEqual(medine[0].height, 0.037991, accuracy: 0.000001)
    }

    /// La taille de page du Coran 1441 est lue **page par page**.
    ///
    /// Mesuré : les 604 pages font `1440 × 2320`. Le test fige le fait, pour que
    /// le jour où le fichier de dimensions changera, on le sache ici plutôt que
    /// par un décalage à l'écran.
    func testTheCoran1441PagesAllShareTheSameSize() {
        var sizes = Set<String>()
        for page in 1...604 {
            let size = VerseBounds.imageSize(for: .coran1441, page: page)
            sizes.insert("\(Int(size.width))x\(Int(size.height))")
        }
        XCTAssertEqual(sizes, ["1440x2320"])
    }

    // MARK: Regroupement par ligne

    /// Sept versets, cinq lignes : les versets 3 et 4 partagent une pastille, et
    /// 5 et 6 une autre.
    func testVersesOnTheSameLineShareOneMarker() {
        let groups = MarginAnnotations.groups(
            MarginAnnotations.regions(page: 1, source: .coran1441),
            start: firstPage.start,
            end: firstPage.end,
            through: firstThrough
        )

        XCTAssertEqual(groups.count, 5)
        XCTAssertEqual(groups.map { $0.items.map(\.ayah) }, [[1], [2], [3, 4], [5, 6], [7]])
        // Le libellé de l'original : les numéros joints par un point médian.
        XCTAssertEqual(
            groups.map { $0.items.map { String($0.ayah) }.joined(separator: "·") },
            ["1", "2", "3·4", "5·6", "7"]
        )
    }

    /// Les groupes sont ordonnés de haut en bas.
    func testTheGroupsAreSortedTopToBottom() {
        let groups = MarginAnnotations.groups(
            MarginAnnotations.regions(page: 1, source: .coran1441),
            start: firstPage.start,
            end: firstPage.end
        )
        assertClose(groups.map(\.y), [0.321429, 0.385714, 0.45, 0.514286, 0.578571], accuracy: 0.000001)
    }

    /// Un verset à cheval sur deux lignes n'est retenu **qu'une fois**, sur la
    /// première ligne dans l'ordre (ligne, puis y).
    ///
    /// Le test est joué dans les DEUX ordres d'entrée : si la règle dépendait de
    /// l'ordre de rencontre au lieu de la ligne, l'un des deux échouerait.
    func testAVerseSpanningTwoLinesKeepsItsFirstLineOnly() {
        // `late` a un `y` plus PETIT, mais une ligne plus grande : la ligne
        // décide, et non la position verticale.
        let early = MarginAnnotations.Region(id: 1, ayah: 1, line: 2, x: 0.1, y: 0.30, height: 0.05)
        let late = MarginAnnotations.Region(id: 1, ayah: 1, line: 3, x: 0.1, y: 0.20, height: 0.05)

        for regions in [[early, late], [late, early]] {
            let groups = MarginAnnotations.groups(regions, start: 1, end: 1)
            XCTAssertEqual(groups.count, 1)
            XCTAssertEqual(groups[0].y, 0.30, accuracy: 0.000001)
        }
    }

    /// À ligne ÉGALE, c'est le `y` le plus petit qui gagne.
    func testOnTheSameLineTheHighestRegionWins() {
        let low = MarginAnnotations.Region(id: 1, ayah: 1, line: 2, x: 0.1, y: 0.30, height: 0.05)
        let high = MarginAnnotations.Region(id: 1, ayah: 1, line: 2, x: 0.1, y: 0.20, height: 0.05)

        for regions in [[low, high], [high, low]] {
            let groups = MarginAnnotations.groups(regions, start: 1, end: 1)
            XCTAssertEqual(groups[0].y, 0.20, accuracy: 0.000001)
        }
    }

    /// À `y` ET ligne égaux, c'est la région rencontrée en PREMIER qui reste.
    ///
    /// L'original écrit des comparaisons strictes (`region.line < old.line`), donc
    /// à égalité parfaite il ne remplace pas. La seule chose qui puisse le dire
    /// est un champ non utilisé par le tri : ici la hauteur.
    func testOnAFullTieTheFirstRegionEncounteredWins() {
        let thin = MarginAnnotations.Region(id: 1, ayah: 1, line: 2, x: 0.1, y: 0.20, height: 0.05)
        let thick = MarginAnnotations.Region(id: 1, ayah: 1, line: 2, x: 0.1, y: 0.20, height: 0.09)

        XCTAssertEqual(
            MarginAnnotations.groups([thin, thick], start: 1, end: 1)[0].height,
            0.05, accuracy: 0.000001
        )
        XCTAssertEqual(
            MarginAnnotations.groups([thick, thin], start: 1, end: 1)[0].height,
            0.09, accuracy: 0.000001
        )
    }

    /// `bottom` se calcule sur **toutes** les régions des versets du groupe.
    ///
    /// Mesuré sur la page 1 du 1441 : le groupe « 5·6 » tient la ligne à
    /// `y = 0.514286` d'une hauteur de `0.1`, donc `y + height = 0.614286`. Mais
    /// le verset 6 continue sur la ligne suivante, et le rail va jusqu'à
    /// `0.678571`. Lire `bottom` sur le seul groupe retenu raccourcirait le rail
    /// de six points de page — sans aucune erreur.
    func testTheBottomOfAGroupUsesEveryRegionOfItsVerses() {
        let groups = MarginAnnotations.groups(
            MarginAnnotations.regions(page: 1, source: .coran1441),
            start: firstPage.start,
            end: firstPage.end,
            through: firstThrough
        )

        XCTAssertEqual(groups[3].y, 0.514286, accuracy: 0.000001)
        XCTAssertEqual(groups[3].height, 0.1, accuracy: 0.000001)
        XCTAssertEqual(groups[3].bottom, 0.678571, accuracy: 0.000001)
        XCTAssertGreaterThan(groups[3].bottom, groups[3].y + groups[3].height)

        // Le dernier groupe déborde aussi : le verset 7 continue.
        XCTAssertEqual(groups[4].bottom, 0.807143, accuracy: 0.000001)
    }

    /// Seuls les versets de la plage demandée sont retenus.
    func testOnlyTheRequestedRangeIsKept() {
        let regions = MarginAnnotations.regions(page: 1, source: .coran1441)

        let middle = MarginAnnotations.groups(regions, start: 3, end: 4)
        XCTAssertEqual(middle.count, 1)
        XCTAssertEqual(middle[0].items.map(\.ayah), [3, 4])

        let single = MarginAnnotations.groups(regions, start: 5, end: 5)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].items.map(\.ayah), [5])

        XCTAssertTrue(MarginAnnotations.groups(regions, start: 100, end: 200).isEmpty)
    }

    /// `done` est vrai pour les identifiants **inférieurs ou égaux** à `through`.
    func testDoneFollowsTheThroughOfTheSession() {
        let regions = MarginAnnotations.regions(page: 1, source: .coran1441)

        let groups = MarginAnnotations.groups(regions, start: 1, end: 7, through: 2)
        XCTAssertEqual(
            groups.flatMap { $0.items }.map(\.done),
            [true, true, false, false, false, false, false]
        )

        // Un verset validé ne suffit pas à remplir la pastille : « 3·4 » reste
        // creuse tant que 4 n'est pas validé.
        let partial = MarginAnnotations.groups(regions, start: 1, end: 7, through: 3)
        XCTAssertEqual(partial[2].items.map(\.done), [true, false])
        XCTAssertFalse(partial[2].items.allSatisfy(\.done))

        // `through` à zéro : rien n'est validé, même le premier verset.
        let none = MarginAnnotations.groups(regions, start: 1, end: 7, through: 0)
        XCTAssertTrue(none.allSatisfy { group in group.items.allSatisfy { !$0.done } })
    }

    // MARK: Géométrie figée — Coran 1441

    /// Les nombres mesurés par l'oracle, sur un téléphone de 390 × 700.
    ///
    /// La page du 1441 fait `1440 × 2320` : dans une vue de 390 × 700, elle est
    /// limitée par la largeur et laisse `35,833333` points de vide en haut et en
    /// bas. C'est **cette boîte** qui ancre le rail, et non le coin de la vue.
    func testTheCoran1441LayoutMatchesTheMeasuredGeometry() {
        let layout = self.layout(.coran1441)

        XCTAssertEqual(layout.markers.count, 5)
        XCTAssertEqual(layout.rail.width, 1)

        // Rail : du haut du premier groupe au bas du dernier.
        XCTAssertEqual(layout.rail.minX, 10.725, accuracy: 0.001)
        XCTAssertEqual(layout.rail.minY, 237.797619, accuracy: 0.001)
        XCTAssertEqual(layout.rail.height, 305.190476, accuracy: 0.001)

        // Diamètre : `edge = 0 + 0.055 × 390 = 21.45`, donc `21.45 - 4 = 17.45`.
        assertClose(layout.markers.map { $0.rect.minX }, [2, 2, 2, 2, 2], accuracy: 0.001)
        assertClose(layout.markers.map { $0.rect.width }, [17.45, 17.45, 17.45, 17.45, 17.45], accuracy: 0.001)
        assertClose(layout.markers.map(\.cornerRadius), [8.725, 8.725, 8.725, 8.725, 8.725], accuracy: 0.001)

        assertClose(
            layout.markers.map { $0.rect.minY },
            [251.064286, 291.457143, 331.85, 372.242857, 412.635714]
        )

        // La police : `min(11, diameter × .55) = 9.5975` pour une pastille d'un
        // seul verset, `8` dès qu'il y en a plusieurs.
        assertClose(layout.markers.map(\.fontSize), [9.5975, 9.5975, 8, 8, 9.5975], accuracy: 0.000001)

        XCTAssertEqual(layout.markers.map(\.label), ["1", "2", "3·4", "5·6", "7"])
        XCTAssertEqual(layout.markers.map(\.done), [true, true, false, false, false])
        XCTAssertEqual(layout.markers.map { $0.items.map(\.ayah) }, [[1], [2], [3, 4], [5, 6], [7]])
    }

    /// Le rail va du haut du premier groupe au bas du DERNIER groupe — et ce bas
    /// n'est pas `y + height`, c'est `bottom`.
    func testTheRailSpansTheFirstGroupToTheBottomOfTheLast() {
        let layout = self.layout(.coran1441)
        let box = VerseBounds.pageBox(in: phone, imageSize: coran1441Size)

        XCTAssertEqual(layout.rail.minY, box.minY + 0.321429 * box.height, accuracy: 0.001)
        XCTAssertEqual(layout.rail.height, (0.807143 - 0.321429) * box.height, accuracy: 0.001)
        XCTAssertEqual(layout.rail.minX, layout.markers[0].rect.midX, accuracy: 0.001)
    }

    // MARK: Géométrie figée — Coran de Médine

    /// La marge intérieure de deux points n'est pas décorative : elle entre dans
    /// la boîte de page, donc dans la position du rail et le diamètre.
    func testTheMedineLayoutUsesTheTwoPointPadding() {
        let layout = self.layout(.medine)

        XCTAssertEqual(layout.markers.count, 5)
        XCTAssertEqual(layout.rail.minX, 66.607292, accuracy: 0.001)
        XCTAssertEqual(layout.rail.minY, 105.13125, accuracy: 0.001)
        XCTAssertEqual(layout.rail.height, 221.748958, accuracy: 0.001)

        // `edge = 80.607292`, donc le diamètre est PLAFONNÉ à 24.
        assertClose(layout.markers.map { $0.rect.minX }, [54.607292, 54.607292, 54.607292, 54.607292, 54.607292])
        assertClose(layout.markers.map { $0.rect.width }, [24, 24, 24, 24, 24])
        assertClose(layout.markers.map(\.cornerRadius), [12, 12, 12, 12, 12])
        assertClose(
            layout.markers.map { $0.rect.minY },
            [101.434271, 134.666458, 167.979062, 200.085417, 231.819844]
        )
        assertClose(layout.markers.map(\.fontSize), [11, 11, 8, 8, 11], accuracy: 0.000001)
        XCTAssertEqual(layout.markers.map(\.label), ["1", "2", "3·4", "5·6", "7"])

        // Sans la marge de deux points, la boîte de page change : le rail aussi.
        // Mesuré : `minX 65.421875`, `minY 102.59375`.
        let withoutPadding = self.layout(.medine, padding: 0)
        XCTAssertEqual(withoutPadding.rail.minX, 65.421875, accuracy: 0.001)
        XCTAssertEqual(withoutPadding.rail.minY, 102.59375, accuracy: 0.001)
        XCTAssertNotEqual(withoutPadding.rail.minX, layout.rail.minX)
        XCTAssertNotEqual(withoutPadding.rail.minY, layout.rail.minY)
    }

    // MARK: Ancrage sur la boîte de page

    /// Sur une vue dont le ratio n'est PAS celui de la page, les repères restent
    /// sur la page.
    ///
    /// C'est le défaut le plus silencieux de tout ce fichier : ancrer sur le coin
    /// de la vue plutôt que sur la boîte de page ne lève aucune erreur, cela pose
    /// seulement le rail 500 points trop haut sur une vue 1200 × 3000.
    func testTheLayoutStaysAnchoredWhenTheViewRatioIsWrong() {
        let layout = self.layout(.coran1441, in: wide)
        let box = VerseBounds.pageBox(in: wide, imageSize: coran1441Size)

        XCTAssertEqual(box.minY, 533.333333, accuracy: 0.001)
        XCTAssertEqual(layout.rail.minY, 1154.761905, accuracy: 0.001)
        assertClose(
            layout.markers.map { $0.rect.minY },
            [1210.428571, 1334.714286, 1459, 1583.285714, 1707.571429]
        )

        // La relation qui le garantit, et qui ne dépend pas de la taille de la
        // vue : chaque pastille tombe sur la même fraction de la boîte de page.
        for (index, expected) in [0.321429, 0.385714, 0.45, 0.514286, 0.578571].enumerated() {
            let center = (layout.markers[index].rect.midY - box.minY) / box.height
            XCTAssertEqual(center, expected + 0.1 * 0.35, accuracy: 0.000001)
        }
    }

    /// Le diamètre est borné à `[8, 24]`, et sa valeur intermédiaire est la
    /// position du bord gauche de la page moins quatre.
    func testTheDiameterIsClampedBetweenEightAndTwentyFour() {
        let square = CGSize(width: 1000, height: 1000)
        // Deux versets sur la MÊME ligne, dont la boîte commence tout à gauche.
        func syntheticRegions() -> [MarginAnnotations.Region] {
            [
                MarginAnnotations.Region(id: 1, ayah: 1, line: 0, x: 0.001, y: 0.2, height: 0.05),
                MarginAnnotations.Region(id: 2, ayah: 2, line: 0, x: 0.001, y: 0.2, height: 0.05),
            ]
        }
        func measure(_ bounds: CGRect) -> MarginAnnotations.Layout {
            MarginAnnotations.layout(
                regions: syntheticRegions(), start: 1, end: 2,
                in: bounds, imageSize: square, padding: 0
            )
        }

        // Page limitée par la largeur : le bord gauche tombe sur le coin, et
        // `edge = 0.4` donne le PLANCHER de 8.
        let floor = measure(CGRect(x: 0, y: 0, width: 400, height: 400))
        XCTAssertEqual(floor.markers[0].rect.width, 8, accuracy: 0.000001)
        XCTAssertEqual(floor.markers[0].rect.minX, -9.6, accuracy: 0.000001)

        // Page étroite dans une vue large : `edge = 300.4`, PLAFOND de 24.
        let ceiling = measure(CGRect(x: 0, y: 0, width: 1_000, height: 400))
        XCTAssertEqual(ceiling.markers[0].rect.width, 24, accuracy: 0.000001)
        XCTAssertEqual(ceiling.markers[0].rect.minX, 274.4, accuracy: 0.000001)

        // Entre les deux : `edge = 20 + 4 = 24`, donc `24 - 4 = 20`.
        let middle = measure(CGRect(x: 0, y: 0, width: 440, height: 400))
        XCTAssertEqual(middle.markers[0].rect.width, 20, accuracy: 0.000001)
        XCTAssertEqual(middle.markers[0].rect.minX, 2, accuracy: 0.000001)
    }

    /// Rien à dessiner quand la séance ne touche pas la page, ou qu'il n'y a
    /// aucune région : la vue ne doit alors rien tracer du tout.
    func testASessionThatMissesThePageDrawsNothing() {
        let regions = MarginAnnotations.regions(page: 1, source: .coran1441)

        let elsewhere = MarginAnnotations.layout(
            regions: regions, start: 100, end: 200,
            in: phone, imageSize: coran1441Size, padding: 0
        )
        XCTAssertTrue(elsewhere.isEmpty)
        XCTAssertEqual(elsewhere, .empty)

        let noRegions = MarginAnnotations.layout(
            regions: [], start: 1, end: 7,
            in: phone, imageSize: coran1441Size, padding: 0
        )
        XCTAssertEqual(noRegions, .empty)

        // Une vue de taille nulle ne doit pas produire un rail absurde.
        let noSpace = MarginAnnotations.layout(
            regions: regions, start: 1, end: 7,
            in: .zero, imageSize: coran1441Size, padding: 0
        )
        XCTAssertEqual(noSpace, .empty)
    }

    /// Un libellé qui passe à la ligne grandit la pastille **vers le bas** :
    /// `minHeight` dans l'original, et non un centrage.
    func testALabelThatWrapsGrowsTheMarkerDownwards() {
        let plain = self.layout(.coran1441)
        let wrapped = self.layout(.coran1441, textHeight: { _, _, _ in 30 })

        XCTAssertEqual(plain.markers[2].rect.height, plain.markers[2].rect.width, accuracy: 0.001)
        XCTAssertEqual(wrapped.markers[2].rect.height, 32, accuracy: 0.001)
        // Le haut ne bouge pas : seul le bas descend.
        XCTAssertEqual(wrapped.markers[2].rect.minY, plain.markers[2].rect.minY, accuracy: 0.001)
        // Et les autres pastilles ne sont pas touchées.
        XCTAssertEqual(wrapped.markers[0].rect.height, plain.markers[0].rect.height, accuracy: 0.001)
    }

    // MARK: La séance dérivée de la demande

    /// Une séance d'apprentissage avec son suivi enregistré.
    private func learningState(
        sessionStart: Int = 10,
        sessionEnd: Int = 20,
        through: Int? = nil,
        progressMode: StudyMode? = nil
    ) -> AppState {
        var state = Program.defaultState()
        state.sessions = [
            Session(
                id: "s1",
                date: "2026-10-05",
                scheduledDate: nil,
                start: sessionStart,
                end: sessionEnd,
                unit: "verse3",
                status: .todo,
                completedAt: nil,
                completedDate: nil
            )
        ]
        if let through, let mode = progressMode {
            state.studyProgress = [
                Program.studyKey(mode, "s1"): StudyProgress(
                    id: "s1",
                    mode: mode,
                    category: nil,
                    start: sessionStart,
                    end: sessionEnd,
                    through: through,
                    page: 1,
                    source: "traditional",
                    updatedAt: "2026-10-05T08:00:00.000Z",
                    status: .partial,
                    validations: []
                )
            ]
        }
        return state
    }

    private func derived(
        learning: String? = nil,
        reviewTask: String? = nil,
        consolidation: Bool = false,
        range: VerseRange? = nil,
        state: AppState
    ) -> MarginAnnotations.Session? {
        MarginAnnotations.session(
            learningSessionID: learning,
            reviewTaskID: reviewTask,
            isConsolidation: consolidation,
            requestRange: range,
            state: state
        )
    }

    /// En apprentissage, la plage de la SÉANCE enregistrée prime sur la plage
    /// demandée.
    ///
    /// Le lecteur peut être ouvert sur une plage rétrécie — « Reprendre au verset
    /// N » — alors que l'original affiche la plage entière de la séance. Prendre
    /// la plage demandée donnerait un rail qui s'arrête au milieu de la séance.
    func testALearningSessionUsesTheStoredRangeNotTheRequestedOne() {
        let session = derived(
            learning: "s1",
            range: VerseRange(start: 15, end: 20),
            state: learningState()
        )
        XCTAssertEqual(session?.range, VerseRange(start: 10, end: 20))
    }

    /// Sans séance enregistrée sous cet identifiant, la plage demandée sert.
    func testWithoutAStoredSessionTheRequestedRangeIsUsed() {
        let session = derived(
            learning: "inconnue",
            range: VerseRange(start: 15, end: 20),
            state: learningState()
        )
        XCTAssertEqual(session?.range, VerseRange(start: 15, end: 20))
    }

    /// Une séance jamais ouverte n'a aucun verset validé : `through` vaut
    /// `start - 1`, et non `start` — sinon le premier verset serait annoncé
    /// validé avant de l'avoir été.
    func testAFreshSessionMarksNothingAsDone() {
        let session = derived(learning: "s1", state: learningState())
        XCTAssertEqual(session?.through, 9)
    }

    /// `through` vient du suivi enregistré quand il existe.
    func testTheThroughComesFromTheStoredProgress() {
        let session = derived(
            learning: "s1",
            state: learningState(through: 14, progressMode: .learning)
        )
        XCTAssertEqual(session?.through, 14)
    }

    /// La clé de suivi dépend du MODE.
    ///
    /// Une révision lit `revision:<id>` ; le même identifiant en apprentissage
    /// lirait `learning:<id>`. Confondre les deux rendrait le suivi invisible, et
    /// le rail repartirait de zéro sans que rien ne le signale.
    func testARevisionReadsTheRevisionKey() {
        var state = Program.defaultState()
        state.studyProgress = [
            Program.studyKey(.revision, "t1"): StudyProgress(
                id: "t1", mode: .revision, category: nil, start: 30, end: 40,
                through: 35, page: 2, source: "traditional",
                updatedAt: "2026-10-05T08:00:00.000Z", status: .partial, validations: []
            ),
            Program.studyKey(.learning, "t1"): StudyProgress(
                id: "t1", mode: .learning, category: nil, start: 30, end: 40,
                through: 31, page: 2, source: "traditional",
                updatedAt: "2026-10-05T08:00:00.000Z", status: .partial, validations: []
            ),
        ]

        let revision = derived(
            reviewTask: "t1",
            range: VerseRange(start: 30, end: 40),
            state: state
        )
        XCTAssertEqual(revision?.through, 35)

        // Le MÊME identifiant, en apprentissage : la clé `learning:t1` porte un
        // autre `through`, et c'est celui-là qui doit sortir.
        let learning = derived(
            learning: "t1",
            range: VerseRange(start: 30, end: 40),
            state: state
        )
        XCTAssertEqual(learning?.through, 31)
    }

    /// Une lecture libre n'a pas de séance : rien à afficher dans la marge.
    func testAReadOnlyOpeningHasNoSession() {
        XCTAssertNil(derived(state: Program.defaultState()))
    }

    /// Une consolidation est une séance ouverte : elle a ses repères.
    func testAConsolidationCountsAsAFocusedSession() {
        let session = derived(
            reviewTask: "t1",
            consolidation: true,
            range: VerseRange(start: 5, end: 8),
            state: Program.defaultState()
        )
        XCTAssertEqual(session?.range, VerseRange(start: 5, end: 8))
        XCTAssertEqual(session?.through, 4)
    }

    /// Une séance ouverte sans aucune plage ne produit **pas** de repères.
    ///
    /// L'original lirait `reader.range.start` et planterait ; ici on ne dessine
    /// rien. Le cas ne devrait pas se produire — tous les appels du lecteur
    /// passent une plage — mais il ne doit pas non plus être une occasion de
    /// fermer l'application.
    func testAFocusedRequestWithoutAnyRangeHasNoSession() {
        XCTAssertNil(derived(learning: "s1", state: Program.defaultState()))
    }

    // MARK: La couleur

    /// La couleur de la séance est celle de l'original — `colors.review`,
    /// `#246B48` — et elle ne suit pas le thème.
    ///
    /// Dans `src/ui/theme.tsx:15`, `review` est ajouté APRÈS les quatre palettes
    /// (`{...palettes.white, …, review:'#246B48'}`) : la même valeur dans les
    /// quatre thèmes. C'est un signal, comme le rouge du verset difficile.
    func testTheSessionColourIsTheReviewColourOfTheOriginal() {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        VerseMarginStyle.sessionGreen.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0x24 / 255, accuracy: 0.000001)
        XCTAssertEqual(green, 0x6B / 255, accuracy: 0.000001)
        XCTAssertEqual(blue, 0x48 / 255, accuracy: 0.000001)
        XCTAssertEqual(alpha, 1, accuracy: 0.000001)

        XCTAssertEqual(VerseMarginStyle.standard.rail, VerseMarginStyle.sessionGreen)
        XCTAssertEqual(VerseMarginStyle.standard.pending, UIColor.white)
    }
}

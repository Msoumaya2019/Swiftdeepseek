// VerseBoundsTests.swift
// Les rectangles des versets sur les pages du Moushaf.
//
// POURQUOI CES TESTS EXISTENT
//   `bounds.json` a été copié dans ce dépôt au premier jour, et n'était lu par
//   aucun code : rien ne prouvait que les 604 pages étaient exploitables, ni que
//   les colonnes étaient lues dans le bon ordre. Une erreur d'ordre ne se voit
//   pas à l'œil — elle produit des rectangles plausibles mais faux, et le défaut
//   ressemble à un problème de projection. Ces tests fixent les deux.
//
// NOTE SUR LE CHARGEMENT
//   La cible de tests est **hébergée** dans l'application (`TEST_HOST` dans
//   `project.yml`) : `Bundle.main` est donc le paquet de l'application, et
//   `bounds.json` y est bien présent. Ce sont les premiers tests du projet qui
//   dépendent d'une ressource embarquée.

import XCTest
@testable import Swiftdeepseek

final class VerseBoundsTests: XCTestCase {

    // MARK: Le fichier est exploitable

    func testTheBoundsFileCoversTheWholeMushaf() throws {
        XCTAssertEqual(VerseBounds.rows(page: 1).count, 10)
        XCTAssertEqual(VerseBounds.rows(page: 604).count, 20)
        XCTAssertFalse(VerseBounds.rows(page: 300).isEmpty)
    }

    /// Une page absente rend une liste vide, sans planter : ces rectangles ne
    /// servent qu'à la mise en évidence, leur absence ne doit pas empêcher de lire.
    func testAnUnknownPageYieldsNoRowInsteadOfFailing() {
        XCTAssertTrue(VerseBounds.rows(page: 0).isEmpty)
        XCTAssertTrue(VerseBounds.rows(page: 605).isEmpty)
        XCTAssertTrue(VerseBounds.rows(page: 9_999).isEmpty)
    }

    /// Le contrôle de validité ne doit **écarter aucune** ligne du fichier.
    ///
    /// C'est le test qui attrape une erreur d'ordre de colonnes : lue comme
    /// `x1, y1, x2, y2`, plus de 6 400 lignes sur 13 766 ont une largeur ou une
    /// hauteur négative et seraient silencieusement jetées. Le total ne
    /// correspondrait alors plus.
    func testNoRowIsDroppedByTheValidityGuard() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "bounds", withExtension: "json"),
            "bounds.json doit être embarqué dans le paquet de l'application"
        )
        let raw = try JSONDecoder().decode([String: [[Int]]].self, from: Data(contentsOf: url))

        let expected = raw.values.reduce(0) { $0 + $1.count }
        let actual = raw.keys.reduce(0) { total, page in
            total + VerseBounds.rows(page: Int(page) ?? -1).count
        }

        XCTAssertEqual(expected, 13_766)
        XCTAssertEqual(actual, expected)
    }

    // MARK: Ordre des colonnes

    /// `[sourate, versetDébut, versetFin, x1, x2, y1, y2]` — et non `x1, y1, x2, y2`.
    ///
    /// La première ligne de la page 1 est `[1, 1, 2, 627, 1295, 335, 453]` : le
    /// rectangle va donc de `x=627` à `x=1295` (largeur 668) et de `y=335` à
    /// `y=453` (hauteur 118).
    func testTheFirstRowOfPageOneUsesTheDocumentedColumnOrder() {
        let row = VerseBounds.rows(page: 1)[0]

        XCTAssertEqual(row.surah, 1)
        XCTAssertEqual(row.ayahStart, 1)
        XCTAssertEqual(row.ayahEnd, 2)
        XCTAssertEqual(row.rect, CGRect(x: 627, y: 335, width: 668, height: 118))
    }

    /// Le même fichier, lu comme `x1, y1, x2, y2`, donnerait pour cette ligne
    /// `x = 627`, `y = 1295`, largeur `335 - 627 = -292`, hauteur `453 - 1295 =
    /// -842` : deux tailles négatives. C'est ce qui rend l'erreur d'ordre
    /// détectable — voir `testNoRowIsDroppedByTheValidityGuard`.
    func testReadingTheColumnsInTheWrongOrderWouldYieldNegativeSizes() {
        let raw = [1, 1, 2, 627, 1295, 335, 453]

        // Lecture documentée `x1, x2, y1, y2` : deux tailles positives.
        XCTAssertEqual(raw[4] - raw[3], 668) // largeur
        XCTAssertEqual(raw[6] - raw[5], 118) // hauteur

        // Lecture fautive `x1, y1, x2, y2` : deux tailles négatives.
        XCTAssertLessThan(raw[5] - raw[3], 0)
        XCTAssertLessThan(raw[6] - raw[4], 0)
    }

    /// Une ligne dont la largeur ou la hauteur serait nulle ou inversée est
    /// écartée plutôt que construite : `CGRect` accepte une taille négative, et
    /// le résultat serait invisible sans qu'on sache pourquoi.
    func testEveryKeptRowHasAPositiveSize() {
        for page in 1...604 {
            for row in VerseBounds.rows(page: page) {
                XCTAssertGreaterThan(row.rect.width, 0, "page \(page)")
                XCTAssertGreaterThan(row.rect.height, 0, "page \(page)")
            }
        }
    }

    // MARK: Mise en évidence

    func testNothingIsHighlightedWhenNothingIsMarked() {
        XCTAssertTrue(VerseBounds.highlights(page: 1).isEmpty)
    }

    /// Un verset difficile prime sur un signet et sur la lecture — c'est l'ordre
    /// des tests dans l'original, et c'est lui qui décide de la couleur.
    func testDifficultyWinsOverBookmarkAndPlaying() {
        let highlights = VerseBounds.highlights(page: 1, difficulty: [1], bookmarks: [1], playing: 1)
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.kind, .difficult)
        XCTAssertEqual(highlights.first?.verseID, 1)
    }

    func testBookmarkWinsOverPlaying() {
        let highlights = VerseBounds.highlights(page: 1, bookmarks: [1], playing: 1)
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.kind, .bookmark)
    }

    func testThePlayingVerseIsHighlighted() {
        let highlights = VerseBounds.highlights(page: 1, playing: 1)
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.kind, .playing)
        XCTAssertEqual(highlights.first?.rect, VerseBounds.rows(page: 1)[0].rect)
    }

    func testAVerseOnAnotherPageIsNotHighlightedHere() {
        // Le verset 8 est sur la page 1 (`[1, 7, 8, …]` se rattache au verset 7) ;
        // le verset 9 est sur la page 2.
        XCTAssertTrue(VerseBounds.highlights(page: 1, difficulty: [9]).isEmpty)
        XCTAssertFalse(VerseBounds.highlights(page: 2, difficulty: [9]).isEmpty)
    }

    /// Un verset coupé en plusieurs fragments de ligne doit être mis en évidence
    /// **en entier**. Le filtre de l'original rattache une ligne au verset qu'elle
    /// **ouvre** (`verseId(row[0], row[1])`) : trois lignes de la page 1 ouvrent
    /// le verset 7, et les trois doivent être dessinées.
    func testEveryLineFragmentOfAVerseIsHighlighted() {
        let fragments = VerseBounds.rows(page: 1).filter { $0.ayahStart == 7 }
        XCTAssertEqual(fragments.count, 3)

        let highlights = VerseBounds.highlights(page: 1, playing: 7)
        XCTAssertEqual(highlights.count, 3)
        XCTAssertTrue(highlights.allSatisfy { $0.verseID == 7 && $0.kind == .playing })
        XCTAssertEqual(Set(highlights.map(\.rect)), Set(fragments.map(\.rect)))
    }

    // MARK: Constantes reprises de l'original

    func testHighlightConstantsMatchTheOriginal() {
        XCTAssertEqual(VerseBounds.imageSize, CGSize(width: 1920, height: 3106))
        XCTAssertEqual(VerseBounds.cornerRadius, 4)
        XCTAssertEqual(VerseBounds.opacity(for: .difficult), 0.18)
        XCTAssertEqual(VerseBounds.opacity(for: .bookmark), 0.18)
        XCTAssertEqual(VerseBounds.opacity(for: .playing), 0.42)
    }

    // MARK: Projection

    /// Quand la vue est exactement au ratio de l'image, la projection ne change
    /// rien : c'est le cas qui montre que l'arithmétique est bien celle de
    /// l'original, `row[3] / sourceWidth * (width - padding * 2)`.
    func testProjectionIsTheIdentityWhenTheViewMatchesTheImage() {
        let view = CGRect(origin: .zero, size: VerseBounds.imageSize)
        for row in VerseBounds.rows(page: 1) {
            XCTAssertEqual(VerseBounds.project(row.rect, into: view), row.rect)
        }
    }

    /// `scaleAspectFit` laisse des bandes vides : la projection doit partir du
    /// coin de l'image **dessinée**, pas du coin de la vue.
    ///
    /// Ici la vue (1200 × 3000) est limitée par la largeur : l'image est centrée
    /// verticalement, avec 529,375 pt de bande vide en haut et en bas.
    func testProjectionAccountsForTheEmptyBandsOfScaleAspectFit() {
        let view = CGRect(x: 0, y: 0, width: 1200, height: 3000)
        let box = VerseBounds.project(CGRect(origin: .zero, size: VerseBounds.imageSize), into: view)

        XCTAssertEqual(box.width, 1200, accuracy: 0.001)
        XCTAssertEqual(box.height, 3106 * 0.625, accuracy: 0.001)
        XCTAssertEqual(box.minX, 0, accuracy: 0.001)
        XCTAssertEqual(box.minY, (3000 - box.height) / 2, accuracy: 0.001)

        let rect = VerseBounds.rows(page: 1)[0].rect // y = 335
        let projected = VerseBounds.project(rect, into: view)
        XCTAssertEqual(projected.minY, box.minY + 335 * 0.625, accuracy: 0.001)

        // La projection naïve, qui ignorerait la bande vide, placerait le verset
        // 400 pt trop haut : c'est exactement le décalage qu'on veut interdire.
        let naive = rect.minY / VerseBounds.imageSize.height * view.height
        XCTAssertEqual(naive, 323.6, accuracy: 0.1)
        XCTAssertGreaterThan(projected.minY - naive, 400)
    }

    func testProjectionKeepsTheImageRatio() {
        for view in [
            CGRect(x: 0, y: 0, width: 1200, height: 3000),
            CGRect(x: 0, y: 0, width: 1000, height: 1000),
            CGRect(x: 10, y: 20, width: 390, height: 700)
        ] {
            let box = VerseBounds.project(CGRect(origin: .zero, size: VerseBounds.imageSize), into: view)
            XCTAssertEqual(
                box.width / box.height,
                VerseBounds.imageSize.width / VerseBounds.imageSize.height,
                accuracy: 0.0001
            )
            XCTAssertLessThanOrEqual(box.width, view.width + 0.001)
            XCTAssertLessThanOrEqual(box.height, view.height + 0.001)
        }
    }

    /// Une vue de taille nulle ne doit pas produire un rectangle infini ou `NaN` :
    /// la mise en page passe par cet état avant la première mesure.
    func testProjectionOnAnEmptyViewYieldsZero() {
        XCTAssertEqual(VerseBounds.project(CGRect(x: 0, y: 0, width: 10, height: 10), into: .zero), .zero)
        XCTAssertEqual(
            VerseBounds.project(CGRect(x: 0, y: 0, width: 10, height: 10), into: CGRect(x: 0, y: 0, width: 0, height: 100)),
            .zero
        )
    }
}

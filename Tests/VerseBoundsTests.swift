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

    /// `[sourate, versetDébut, ligne, x1, x2, y1, y2]` — et non `x1, y1, x2, y2`.
    ///
    /// La première ligne de la page 1 est `[1, 1, 2, 627, 1295, 335, 453]` : le
    /// rectangle va donc de `x=627` à `x=1295` (largeur 668) et de `y=335` à
    /// `y=453` (hauteur 118).
    func testTheFirstRowOfPageOneUsesTheDocumentedColumnOrder() {
        let row = VerseBounds.rows(page: 1)[0]

        XCTAssertEqual(row.surah, 1)
        XCTAssertEqual(row.ayahStart, 1)
        XCTAssertEqual(row.line, 2)
        XCTAssertEqual(row.rect, CGRect(x: 627, y: 335, width: 668, height: 118))
    }

    // MARK: Les deux sources

    /// La troisième colonne est un **numéro de ligne**, pas un verset de fin.
    ///
    /// C'est la correction d'une erreur de lecture qui a survécu un moment dans
    /// ce fichier sous le nom `ayahEnd`. Deux mesures la tranchent :
    ///
    ///   - elle plafonne à **15** dans tout `bounds.json`, alors qu'un numéro de
    ///     verset atteindrait 286 (al-Baqarah) ;
    ///   - en triant les lignes d'une page par `y1`, elle ne produit **aucune
    ///     inversion** : elle suit exactement la position verticale.
    ///
    /// Les deux sources ne comptent même pas à partir du même rang : Médine est
    /// 1-basée (`1 … 15`), le Coran 1441 est 0-basé (`0 … 14`).
    func testTheThirdColumnIsALineNumberAndNotAnAyahNumber() throws {
        for source in VerseBounds.Source.allCases {
            var seen: Set<Int> = []
            for page in 1...604 {
                for row in VerseBounds.rows(page: page, source: source) {
                    seen.insert(row.line)
                }
            }

            XCTAssertEqual(
                seen.count, VerseBounds.linesPerPage,
                "\(source) : 15 lignes par page attendues"
            )
            // Aucune valeur ne peut atteindre un numéro de verset.
            XCTAssertLessThanOrEqual(seen.max() ?? 0, VerseBounds.linesPerPage)

            switch source {
            case .medine:
                XCTAssertEqual(seen.min(), 1, "le Coran de Médine compte les lignes à partir de 1")
            case .coran1441:
                XCTAssertEqual(seen.min(), 0, "le Coran 1441 compte les lignes à partir de 0")
            }
        }
    }

    /// Le même contrôle que pour Médine, appliqué au fichier du Coran 1441 : le
    /// garde-fou de validité ne doit écarter **aucune** ligne.
    ///
    /// Ce fichier porte en prime des coordonnées décimales. Décodé en `Int`, il
    /// échouerait **en entier** : toutes les mises en évidence du Coran 1441
    /// disparaîtraient, sans autre symptôme qu'un écran sans surbrillance.
    func testTheCoran1441FileIsReadWholeAndInDouble() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "coran_1441-bounds", withExtension: "json"),
            "coran_1441-bounds.json doit être embarqué dans le paquet de l'application"
        )
        let raw = try JSONDecoder().decode([String: [[Double]]].self, from: Data(contentsOf: url))

        XCTAssertEqual(raw.count, 604)

        let expected = raw.values.reduce(0) { $0 + $1.count }
        let actual = raw.keys.reduce(0) { total, page in
            total + VerseBounds.rows(page: Int(page) ?? -1, source: .coran1441).count
        }

        XCTAssertEqual(expected, 13_273)
        XCTAssertEqual(actual, expected)
    }

    /// Les rectangles du Coran 1441 sont **des rectangles de bande**.
    ///
    /// `MushafPage.tsx:48` empile quinze bandes de `1440 × 232` à pas constant
    /// `(2320 - 232) / 14`. Mesure faite sur le fichier : les **13 273** lignes
    /// ont `y1 == pas × ligne` et une hauteur de **232**, sans une exception.
    ///
    /// C'est ce qui autorise une seule fonction de projection pour les bandes et
    /// pour les mises en évidence : les deux décrivent la même géométrie.
    func testEveryCoran1441RowIsABandRectangle() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "coran_1441-bounds", withExtension: "json")
        )
        let raw = try JSONDecoder().decode([String: [[Double]]].self, from: Data(contentsOf: url))

        let step = (2320 - VerseBounds.coran1441BandHeight) / CGFloat(VerseBounds.linesPerPage - 1)

        var checked = 0
        for (page, rows) in raw {
            for values in rows {
                let line = Int(values[2])
                XCTAssertEqual(
                    values[5], step * CGFloat(line), accuracy: 0.000001,
                    "page \(page), ligne \(line) : le haut de la bande ne suit pas le pas"
                )
                XCTAssertEqual(
                    values[6] - values[5], VerseBounds.coran1441BandHeight, accuracy: 0.000001,
                    "page \(page), ligne \(line) : la hauteur n'est pas celle d'une bande"
                )
                checked += 1
            }
        }
        XCTAssertEqual(checked, 13_273)
    }

    /// Une bande et la mise en évidence du verset qu'elle porte se projettent au
    /// **même endroit**.
    ///
    /// C'est l'invariant qui compte : dans l'original, les bandes sont
    /// positionnées dans l'espace de la vue et les mises en évidence dans
    /// l'espace de l'image, si bien que les deux ne coïncident que si la vue a
    /// exactement le ratio de la page. Ici les deux passent par `VerseBounds`,
    /// donc elles coïncident toujours.
    ///
    /// ATTENTION À CE QUI COÏNCIDE, ET À CE QUI NE COÏNCIDE PAS. Une bande est la
    /// **bande** de la ligne — toute la largeur de la page. Le rectangle d'un
    /// verset n'en occupe qu'une **partie** horizontale. Le premier jet de ce
    /// test comparait aussi leurs `minX` : c'est ce qui a fait échouer le run
    /// #19, sur neuf lignes de la page 1, avec des valeurs qui se relisent
    /// exactement — `352,08 / 1440 × 390 = 95,355`. Le défaut était dans le
    /// test, pas dans le code : une bande commence au bord de la page, un verset
    /// commence là où il commence.
    ///
    /// Ce qui doit être **égal** : le haut et la hauteur. Ce qui doit être
    /// **contenu** : l'étendue horizontale.
    func testTheBandsAndTheHighlightsUseTheSameGeometry() {
        let view = CGRect(x: 0, y: 0, width: 390, height: 700)
        let size = VerseBounds.imageSize(for: .coran1441, page: 1)

        var checked = 0
        for page in [1, 2, 300, 604] {
            for row in VerseBounds.rows(page: page, source: .coran1441) {
                let band = VerseBounds.bandRect(line: row.line, in: view, imageSize: size)
                let rect = VerseBounds.project(row.rect, into: view, imageSize: size)

                XCTAssertEqual(rect.minY, band.minY, accuracy: 0.001, "page \(page), ligne \(row.line)")
                XCTAssertEqual(rect.height, band.height, accuracy: 0.001, "page \(page), ligne \(row.line)")
                XCTAssertGreaterThanOrEqual(rect.minX, band.minX - 0.001, "page \(page), ligne \(row.line)")
                XCTAssertLessThanOrEqual(rect.maxX, band.maxX + 0.001, "page \(page), ligne \(row.line)")
                checked += 1
            }
        }
        // 10 + 9 + 21 + 18 : le balayage doit porter sur toutes les lignes de ces
        // quatre pages, et pas sur moins si une page manquait au fichier.
        XCTAssertEqual(checked, 58)
    }

    /// La taille de la page est **celle de la source**, et le repli est la taille
    /// réelle — pas `1 × 1` comme dans l'original.
    func testTheImageSizeIsReadPerSource() {
        XCTAssertEqual(VerseBounds.imageSize(for: .medine, page: 1), CGSize(width: 1920, height: 3106))
        XCTAssertEqual(VerseBounds.imageSize(for: .coran1441, page: 1), CGSize(width: 1440, height: 2320))
        XCTAssertEqual(VerseBounds.imageSize(for: .coran1441, page: 604), CGSize(width: 1440, height: 2320))

        // Page absente du fichier de dimensions : repli sur la taille de la
        // source. Un repli sur `1 × 1` multiplierait toutes les coordonnées par
        // la largeur de la vue.
        XCTAssertEqual(VerseBounds.imageSize(for: .coran1441, page: 605), CGSize(width: 1440, height: 2320))
        XCTAssertEqual(VerseBounds.imageSize(for: .coran1441, page: 0), CGSize(width: 1440, height: 2320))
    }

    /// Se tromper de taille ne lève aucune erreur : cela déplace les mises en
    /// évidence. Le contrôle chiffre le décalage, pour que le défaut silencieux
    /// ait au moins un témoin.
    ///
    /// Sur une vue 1200 × 3000, la même ligne du Coran 1441 tombe à environ
    /// 1 155 pt avec la bonne taille et à environ 995 pt avec celle du Coran de
    /// Médine : plus de 150 pt d'écart.
    func testProjectingWithTheWrongImageSizeMovesTheHighlight() {
        let view = CGRect(x: 0, y: 0, width: 1200, height: 3000)
        let row = VerseBounds.rows(page: 1, source: .coran1441)[0]

        let correct = VerseBounds.project(
            row.rect,
            into: view,
            imageSize: VerseBounds.imageSize(for: .coran1441, page: 1)
        )
        let wrong = VerseBounds.project(
            row.rect,
            into: view,
            imageSize: VerseBounds.imageSize(for: .medine, page: 1)
        )

        XCTAssertGreaterThan(abs(correct.minY - wrong.minY), 100)
    }

    /// La page 1 du Coran 1441 commence à la **ligne 5** et sa première ligne est
    /// `[1, 1, 5, 352.08, 1087.92, 745.714…, 977.714…]`.
    func testTheFirstRowOfTheCoran1441PageOne() {
        let row = VerseBounds.rows(page: 1, source: .coran1441)[0]

        XCTAssertEqual(row.surah, 1)
        XCTAssertEqual(row.ayahStart, 1)
        XCTAssertEqual(row.line, 5)
        XCTAssertEqual(row.rect.minX, 352.08, accuracy: 0.000001)
        XCTAssertEqual(row.rect.width, 735.84, accuracy: 0.000001)
        XCTAssertEqual(row.rect.minY, 745.7142857142857, accuracy: 0.000001)
        XCTAssertEqual(row.rect.height, 232, accuracy: 0.000001)
    }

    /// Les deux sources ne se confondent pas : mêmes pages, contenus différents.
    func testTheTwoSourcesAreNotInterchangeable() {
        XCTAssertEqual(VerseBounds.rows(page: 1, source: .medine).count, 10)
        XCTAssertEqual(VerseBounds.rows(page: 1, source: .coran1441).count, 10)
        // Même nombre de lignes sur cette page, mais pas les mêmes versets :
        // la page 1 du Coran de Médine s'arrête à la ligne 8, celle du 1441 à
        // la ligne 11.
        XCTAssertEqual(VerseBounds.rows(page: 1, source: .medine).map(\.line).max(), 8)
        XCTAssertEqual(VerseBounds.rows(page: 1, source: .coran1441).map(\.line).max(), 11)
        XCTAssertNotEqual(
            VerseBounds.rows(page: 1, source: .medine)[0].rect,
            VerseBounds.rows(page: 1, source: .coran1441)[0].rect
        )
    }

    /// Une bande hors de la page n'existe pas : rendre `.zero` plutôt qu'un
    /// rectangle à une position inventée.
    func testABandOutsideThePageYieldsNothing() {
        let view = CGRect(x: 0, y: 0, width: 390, height: 700)
        let size = VerseBounds.imageSize(for: .coran1441, page: 1)

        XCTAssertEqual(VerseBounds.bandRect(line: -1, in: view, imageSize: size), .zero)
        XCTAssertEqual(VerseBounds.bandRect(line: 15, in: view, imageSize: size), .zero)
        XCTAssertGreaterThan(VerseBounds.bandRect(line: 14, in: view, imageSize: size).height, 0)
    }

    // MARK: Ordre des colonnes — le contrôle par l'absurde

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

        // Comparaison des TABLEAUX, dans l'ordre, et non d'ensembles : d'une part
        // `CGRect` ne conforme à `Hashable` qu'à partir d'un système plus récent
        // que la cible iOS 16 du projet, d'autre part l'ordre est ici une
        // propriété qu'on veut tenir — les rectangles doivent sortir dans l'ordre
        // du document, sinon deux fragments d'un même verset se dessineraient
        // dans un ordre arbitraire.
        XCTAssertEqual(highlights.map(\.rect), fragments.map(\.rect))
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
    ///
    /// Comparaison AVEC TOLÉRANCE, et non à l'identique : l'égalité exacte n'est
    /// pas tenable ici. `979 / 3106 * 3106` vaut `979.0000000000001` en virgule
    /// flottante — l'erreur est de 1e-13 point, soit douze ordres de grandeur
    /// sous le pixel, mais `XCTAssertEqual` sur deux `CGRect` la refuse. C'est ce
    /// qui a fait échouer le run #16.
    func testProjectionIsTheIdentityWhenTheViewMatchesTheImage() {
        let view = CGRect(origin: .zero, size: VerseBounds.imageSize)
        for row in VerseBounds.rows(page: 1) {
            let projected = VerseBounds.project(row.rect, into: view)
            XCTAssertEqual(projected.minX, row.rect.minX, accuracy: 0.001)
            XCTAssertEqual(projected.minY, row.rect.minY, accuracy: 0.001)
            XCTAssertEqual(projected.width, row.rect.width, accuracy: 0.001)
            XCTAssertEqual(projected.height, row.rect.height, accuracy: 0.001)
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

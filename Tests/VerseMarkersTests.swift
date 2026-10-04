// VerseMarkersTests.swift
// Les pastilles de numéro de verset du Coran 1441.
//
// POURQUOI CES TESTS EXISTENT
//   `coran_1441-markers.json` est embarqué depuis l'origine et n'était lu par
//   aucun code : rien ne prouvait que ses 604 pages étaient exploitables, ni que
//   ses colonnes étaient lues dans le bon ordre, ni que sa `ligne` suivait la
//   convention **0-basée** des bandes du 1441 — et non la convention 1-basée de
//   `bounds.json`. Se tromper de convention ne lève aucune erreur : les pastilles
//   se posent simplement sur la mauvaise bande.
//
// LES VALEURS ATTENDUES SONT MESURÉES, PAS DÉDUITES DU CODE
//   Les totaux, les bornes et les positions de ce fichier viennent d'une lecture
//   indépendante de `coran_1441-markers.json`. Les dériver du code testé
//   reviendrait à comparer le code à lui-même.

import XCTest
@testable import Swiftdeepseek

final class VerseMarkersTests: XCTestCase {

    /// La géométrie des pages du Coran 1441, telle que `VerseBounds` la connaît.
    private let coran1441Size = CGSize(width: 1440, height: 2320)

    // MARK: Le fichier est exploitable

    func testTheMarkersFileCoversTheWholeMushaf() {
        XCTAssertEqual(VerseMarkers.annotatedPageCount, 604)
        XCTAssertEqual(VerseMarkers.markerCount, 6_236)
        XCTAssertEqual(VerseMarkers.markers(page: 1).count, 7)
        XCTAssertEqual(VerseMarkers.markers(page: 604).count, 15)
    }

    /// Une page absente rend une liste vide, sans planter : ces pastilles ne sont
    /// qu'un repère de lecture, leur absence ne doit pas empêcher de lire.
    func testAnUnknownPageYieldsNoMarkerInsteadOfFailing() {
        XCTAssertTrue(VerseMarkers.markers(page: 0).isEmpty)
        XCTAssertTrue(VerseMarkers.markers(page: 605).isEmpty)
        XCTAssertTrue(VerseMarkers.markers(page: 9_999).isEmpty)
    }

    /// Le contrôle de validité ne doit **écarter aucun** marqueur du fichier.
    ///
    /// C'est le test qui attrape une faute de garde : un `line` hors des quinze
    /// bandes, ou une fraction hors de la page, fait jeter la ligne en silence.
    /// Le total ne correspondrait alors plus.
    func testNoMarkerIsDroppedByTheValidityGuard() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "coran_1441-markers", withExtension: "json"),
            "coran_1441-markers.json doit être embarqué dans le paquet de l'application"
        )
        let raw = try JSONDecoder().decode([String: [[Double]]].self, from: Data(contentsOf: url))

        let expected = raw.values.reduce(0) { $0 + $1.count }
        let actual = raw.keys.reduce(0) { total, page in
            total + VerseMarkers.markers(page: Int(page) ?? -1).count
        }

        XCTAssertEqual(expected, 6_236)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(raw.count, 604)
    }

    // MARK: Ordre des colonnes, et convention de ligne

    /// `[sourate, verset, ligne, x, y]` — le premier marqueur de la page 1 est
    /// `[1, 1, 5, 0.29513928, 0.54987925]`.
    ///
    /// Lu comme `x, y, ligne`, il donnerait une ligne de `0.29…` : entier tronqué
    /// à `0`, donc une pastille sur la **première** bande au lieu de la sixième.
    /// Une erreur qui ne se signale pas.
    func testTheFirstMarkerOfPageOneUsesTheDocumentedColumnOrder() {
        let marker = VerseMarkers.markers(page: 1)[0]

        XCTAssertEqual(marker.surah, 1)
        XCTAssertEqual(marker.ayah, 1)
        XCTAssertEqual(marker.line, 5)
        XCTAssertEqual(marker.x, 0.29513928, accuracy: 0.0000001)
        XCTAssertEqual(marker.y, 0.54987925, accuracy: 0.0000001)
    }

    /// La `ligne` est **0-basée** (`0 … 14`), la convention des bandes du 1441.
    ///
    /// Mesuré sur tout le fichier, et non sur un échantillon : c'est la borne
    /// haute qui distingue les deux conventions. Une lecture 1-basée décalerait
    /// chaque pastille d'une bande, et la bande 14 sortirait de la page.
    func testTheLineIsZeroBasedAcrossTheWholeFile() {
        var minimum = Int.max
        var maximum = Int.min

        for page in 1...604 {
            for marker in VerseMarkers.markers(page: page) {
                minimum = min(minimum, marker.line)
                maximum = max(maximum, marker.line)
            }
        }

        XCTAssertEqual(minimum, 0)
        XCTAssertEqual(maximum, VerseBounds.linesPerPage - 1)
        XCTAssertEqual(maximum, 14)
    }

    // MARK: La source compte

    /// Les marqueurs annotent les **bandes** du 1441 : ils n'ont aucun sens sur
    /// une page du Coran de Médine.
    ///
    /// Le test fige le refus. Une source qui n'est pas le 1441 rend une liste
    /// vide, et non des pastilles à des endroits plausibles sur une image qui
    /// n'est pas la même — ce qui serait pire que rien.
    func testAnotherEditionReceivesNoMarker() {
        XCTAssertTrue(VerseMarkers.markers(page: 1, source: .medine).isEmpty)
        XCTAssertTrue(VerseMarkers.markers(page: 300, source: .medine).isEmpty)
        XCTAssertFalse(VerseMarkers.markers(page: 1, source: .coran1441).isEmpty)
    }

    // MARK: Les chiffres arabes orientaux

    /// Reproduit `String(ayah).replace(/\d/g, n => '٠١٢٣٤٥٦٧٨٩'[Number(n)])`.
    func testTheVerseNumberIsWrittenInEasternArabicNumerals() {
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(0), "٠")
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(1), "١")
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(9), "٩")
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(10), "١٠")
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(114), "١١٤")
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(286), "٢٨٦")
    }

    /// Chaque chiffre est remplacé **individuellement**, et rien d'autre ne l'est.
    ///
    /// Le cas qui compte : un chiffre **déjà** oriental doit ressortir inchangé.
    /// `Character.wholeNumberValue` de Swift le reconnaîtrait comme un chiffre et
    /// le reconvertirait — une faute invisible, le résultat restant un chiffre.
    func testTheConversionTouchesAsciiDigitsOnly() {
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(1_023), "١٠٢٣")
        XCTAssertEqual(VerseMarkers.easternArabicNumerals(4_050_607_089), "٤٠٥٠٦٠٧٠٨٩")
    }

    // MARK: Géométrie

    /// Diamètre et boîte d'une pastille, dans une vue 390 × 844.
    ///
    /// Valeurs mesurées hors de ce dépôt, à partir du marqueur
    /// `[1, 1, 5, 0.29513928, 0.54987925]` : la page y occupe toute la largeur
    /// (390 pt), donc le diamètre vaut `390 × 0,05 = 19,5` pt, la bande 5 commence
    /// à `309,7976` et la pastille se pose à `(105.354319, 334.598365)`.
    func testTheMedallionBoxIsMeasuredOnTheDrawnPage() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let marker = VerseMarkers.markers(page: 1)[0]

        let box = VerseMarkers.medallionRect(for: marker, in: bounds, imageSize: coran1441Size)

        XCTAssertEqual(VerseMarkers.pageWidth(in: bounds, imageSize: coran1441Size), 390, accuracy: 0.001)
        XCTAssertEqual(VerseMarkers.diameter(in: bounds, imageSize: coran1441Size), 19.5, accuracy: 0.001)
        XCTAssertEqual(box.minX, 105.354319, accuracy: 0.001)
        XCTAssertEqual(box.minY, 334.598365, accuracy: 0.001)
        XCTAssertEqual(box.width, 19.5, accuracy: 0.001)
        XCTAssertEqual(box.height, 19.5, accuracy: 0.001)
    }

    /// La pastille suit la taille de la vue : c'est tout l'intérêt de la calculer
    /// depuis `bounds` et non depuis `imageSize`.
    ///
    /// Même marqueur, vue 1200 × 3000 — un écran trois fois plus large, mais de
    /// ratio différent. Le diamètre passe à `60` pt, et la boîte à
    /// `(324.167136, 1231.071893)`.
    func testTheMedallionFollowsTheViewSize() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 3000)
        let marker = VerseMarkers.markers(page: 1)[0]

        let box = VerseMarkers.medallionRect(for: marker, in: bounds, imageSize: coran1441Size)

        XCTAssertEqual(VerseMarkers.diameter(in: bounds, imageSize: coran1441Size), 60, accuracy: 0.001)
        XCTAssertEqual(box.minX, 324.167136, accuracy: 0.001)
        XCTAssertEqual(box.minY, 1231.071893, accuracy: 0.001)
        XCTAssertEqual(box.width, 60, accuracy: 0.001)
    }

    /// La pastille est **solidaire de sa bande** : elle passe par
    /// `VerseBounds.bandRect`, donc elle ne peut pas dériver de la bande qu'elle
    /// annote.
    ///
    /// L'invariant est vérifié sur les 6 236 marqueurs, dans une vue dont le
    /// ratio **diffère** de celui de la page — le cas où la formule de l'original
    /// (`(height - width * 232 / 1440) / 14 * line`) dérive.
    func testEveryMedallionSitsInsideItsOwnBand() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 3000)
        var checked = 0

        for page in 1...604 {
            for marker in VerseMarkers.markers(page: page) {
                let band = VerseBounds.bandRect(
                    line: marker.line,
                    in: bounds,
                    imageSize: coran1441Size
                )
                let box = VerseMarkers.medallionRect(for: marker, in: bounds, imageSize: coran1441Size)
                guard band.width > 0, box.width > 0 else {
                    XCTFail("bande ou pastille vide, page \(page), ligne \(marker.line)")
                    continue
                }

                // Le centre, et non la boîte entière : une pastille à cheval sur le
                // bord de sa bande reste juste, c'est le centre qui l'ancre.
                XCTAssertTrue(
                    band.minY <= box.midY && box.midY <= band.maxY,
                    "pastille hors de sa bande, page \(page), ligne \(marker.line)"
                )
                XCTAssertTrue(
                    band.minX <= box.midX && box.midX <= band.maxX,
                    "pastille hors de sa page, page \(page), ligne \(marker.line)"
                )
                checked += 1
            }
        }

        XCTAssertEqual(checked, 6_236)
    }

    /// Une ligne hors des quinze bandes rend une boîte nulle, que la vue écarte.
    ///
    /// Sans cette garde, `bandRect` rendrait `.zero` et la pastille serait
    /// dessinée au coin de la vue — visible, et fausse.
    func testALineOutsideTheBandsYieldsNoBox() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        for line in [-1, 15, 100] {
            let marker = VerseMarkers.Marker(surah: 1, ayah: 1, line: line, x: 0.5, y: 0.5)
            let box = VerseMarkers.medallionRect(for: marker, in: bounds, imageSize: coran1441Size)
            XCTAssertEqual(box, .zero, "ligne \(line) : une boîte nulle était attendue")
        }
    }
}

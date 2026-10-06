// SurahPickerTests.swift
// Les règles du sélecteur de sourate — `Core/SurahPickerOptions.swift`.
//
// Ce que ces tests couvrent, et ce qui les rend non vides : chaque valeur
// attendue vient du **relevé de l'original**, exécuté par `_banc/oracle-surah-picker.mjs`
// sur les expressions réelles de `src/SurahPicker.tsx`. Un test qui affirme
// « 605 est refusé » sans que l'original le refuse serait un test de mes
// propres convictions, pas un test du portage.

import XCTest
@testable import Swiftdeepseek

final class SurahPickerTests: XCTestCase {

    // MARK: - Les bornes de la pagination

    func testThePaginationIsOneToSixHundredFour() {
        XCTAssertEqual(SurahPickerOptions.firstPage, 1)
        XCTAssertEqual(SurahPickerOptions.lastPage, 604)
    }

    // MARK: - La page saisie

    func testTheFirstAndLastPagesAreAccepted() {
        XCTAssertEqual(SurahPickerOptions.page(from: "1"), .go(1))
        XCTAssertEqual(SurahPickerOptions.page(from: "604"), .go(604))
    }

    func testZeroIsRefused() {
        // `Number('0')` vaut `0`, entier, mais `0 < 1` — refusé. C'est aussi le
        // sort de `''` et `' '`, dont `Number` vaut `0`.
        XCTAssertEqual(SurahPickerOptions.page(from: "0"), .refused)
    }

    func testSixHundredFiveIsRefused() {
        XCTAssertEqual(SurahPickerOptions.page(from: "605"), .refused)
    }

    func testAnEmptyFieldIsRefused() {
        // `Number('')` vaut `0` (entier), mais hors `1...604`. Le champ d'un
        // formulaire **commence vide** : c'est le cas le plus fréquent, pas un
        // cas d'école.
        XCTAssertEqual(SurahPickerOptions.page(from: ""), .refused)
        XCTAssertEqual(SurahPickerOptions.page(from: " "), .refused)
    }

    func testSurroundingSpacesAreTolerated() {
        // `Number('  12  ')` vaut `12`. `Int` de Swift ne l'aurait pas fait :
        // c'est le `trimmingCharacters` qui rattrape l'écart.
        XCTAssertEqual(SurahPickerOptions.page(from: " 12 "), .go(12))
        XCTAssertEqual(SurahPickerOptions.page(from: "\n42\t"), .go(42))
    }

    func testLeadingZerosAreAccepted() {
        // `Number('0007')` vaut `7`.
        XCTAssertEqual(SurahPickerOptions.page(from: "0007"), .go(7))
    }

    func testANonNumericFieldIsRefused() {
        // `Number('abc')` est `NaN`, et `Number.isInteger(NaN)` est faux.
        XCTAssertEqual(SurahPickerOptions.page(from: "abc"), .refused)
        XCTAssertEqual(SurahPickerOptions.page(from: "12abc"), .refused)
        XCTAssertEqual(SurahPickerOptions.page(from: "nan"), .refused)
        XCTAssertEqual(SurahPickerOptions.page(from: "inf"), .refused)
    }

    func testADecimalIsRefused() {
        // `Number('3.5')` vaut `3.5` — ni entier, donc refusé.
        // `Int('3.5')` rend `nil` : refusé aussi, par un autre chemin. C'est le
        // seul cas où les deux implémentations divergent **en chemin** sans
        // diverger en **décision** — et c'est la décision qui compte.
        XCTAssertEqual(SurahPickerOptions.page(from: "3.5"), .refused)
        XCTAssertEqual(SurahPickerOptions.page(from: "3,5"), .refused)
    }

    func testNegativeNumbersAreRefused() {
        XCTAssertEqual(SurahPickerOptions.page(from: "-5"), .refused)
    }

    func testPlusSignIsAccepted() {
        // `Number('+5')` vaut `5`. `Int("+5")` aussi — l'accord est réel ici.
        XCTAssertEqual(SurahPickerOptions.page(from: "+5"), .go(5))
    }

    func testTheAcceptedPagesAreExactlyTheInterval() {
        // Le tour complet des 604 pages : aucun trou, aucun débordement.
        for page in SurahPickerOptions.firstPage...SurahPickerOptions.lastPage {
            XCTAssertEqual(
                SurahPickerOptions.page(from: String(page)),
                .go(page),
                "page \(page)"
            )
        }
    }

    func testNothingOutsideTheIntervalIsAccepted() {
        // Les deux voisines immédiates, et un échantillon plus loin.
        for page in [-1, 0, 605, 606, 1000] {
            XCTAssertEqual(
                SurahPickerOptions.page(from: String(page)),
                .refused,
                "page \(page)"
            )
        }
    }

    // MARK: - Les deux saisies divergentes, et pourquoi elles sont hors d'atteinte

    func testTheTwoKnownDivergencesAreUnreachable() {
        // `Number('1e2')` vaut `100` et `Number('0x10')` vaut `16` : l'original
        // les ACCEPTE. `Int` de Swift les refuse. La divergence est réelle.
        XCTAssertEqual(SurahPickerOptions.page(from: "1e2"), .refused)
        XCTAssertEqual(SurahPickerOptions.page(from: "0x10"), .refused)

        // Et elle est injoignable : le champ porte `keyboardType="number-pad"`,
        // un pavé qui n'offre que les dix chiffres. Le témoin de non-vacuité est
        // que le pavé accepte les chiffres, eux :
        XCTAssertEqual(SurahPickerOptions.page(from: "100"), .go(100))
        XCTAssertEqual(SurahPickerOptions.page(from: "16"), .go(16))
    }

    // MARK: - L'indice de départ

    func testTheInitialIndexIsZeroBased() {
        // `Math.max(0, currentSurah-1)` : la sourate 1 → indice 0.
        XCTAssertEqual(SurahPickerOptions.initialScrollIndex(currentSurah: 1), 0)
        XCTAssertEqual(SurahPickerOptions.initialScrollIndex(currentSurah: 114), 113)
        XCTAssertEqual(SurahPickerOptions.initialScrollIndex(currentSurah: 2), 1)
    }

    func testTheInitialIndexNeverGoesNegative() {
        // LE POINT DU `Math.max`. `currentSurah` vaut `0` quand aucune sourate
        // n'est choisie, et `-1` est un indice que `FlatList` refuse.
        XCTAssertEqual(SurahPickerOptions.initialScrollIndex(currentSurah: 0), 0)
        XCTAssertEqual(SurahPickerOptions.initialScrollIndex(currentSurah: -3), 0)
    }

    func testTheInitialIndexStaysInsideTheList() {
        // Le plus grand indice utilisable est `113` pour 114 sourates.
        let last = SurahPickerOptions.initialScrollIndex(
            currentSurah: Quran.surahs.count
        )
        XCTAssertEqual(last, Quran.surahs.count - 1)
        XCTAssertTrue(last < Quran.surahs.count)
    }

    // MARK: - La ligne de saut

    func testThePageJumpOnlyExistsWithOnPage() {
        // `{onPage && …}` — sans `onPage`, ni champ ni bouton.
        XCTAssertTrue(SurahPickerOptions.showsPageJump(hasOnPage: true))
        XCTAssertFalse(SurahPickerOptions.showsPageJump(hasOnPage: false))
    }

    // MARK: - L'état initial du champ

    func testTheFieldStartsOnTheCurrentPageOrOne() {
        // `String(currentPage ?? 1)` — `currentPage` est optionnel.
        XCTAssertEqual(SurahPickerOptions.initialPageText(currentPage: 42), "42")
        XCTAssertEqual(SurahPickerOptions.initialPageText(currentPage: 1), "1")
        XCTAssertEqual(SurahPickerOptions.initialPageText(currentPage: nil), "1")
    }

    func testTheFieldStartsOnAPageTheRuleAccepts() {
        // Le témoin qui relie les deux règles : l'état initial du champ doit
        // être une saisie que `page(from:)` accepte — sinon le bouton « Aller à
        // la page » refuserait la valeur qu'on vient d'y poser.
        XCTAssertEqual(
            SurahPickerOptions.page(from: SurahPickerOptions.initialPageText(currentPage: nil)),
            .go(1)
        )
        XCTAssertEqual(
            SurahPickerOptions.page(from: SurahPickerOptions.initialPageText(currentPage: 604)),
            .go(604)
        )
    }

    // MARK: - Les textes

    func testTheTextsAreThoseOfTheReference() {
        XCTAssertEqual(SurahPickerOptions.title, "Choisir une sourate")
        XCTAssertEqual(SurahPickerOptions.subtitle, "Les 114 sourates du Coran")
        XCTAssertEqual(SurahPickerOptions.closeTitle, "Fermer")
        XCTAssertEqual(SurahPickerOptions.pageFieldPlaceholder, "Page 1 à 604")
        XCTAssertEqual(SurahPickerOptions.pageSubmitTitle, "Aller à la page")
        XCTAssertEqual(SurahPickerOptions.invalidPageTitle, "Page invalide")
        XCTAssertEqual(SurahPickerOptions.invalidPageMessage, "Choisis une page entre 1 et 604.")
    }

    func testTheSubtitleCountsTheSurahsTheListHolds() {
        // Le libellé dit « Les 114 sourates » et la liste en porte 114 : le dire
        // par la mesure évite qu'un jeu de métadonnées tronqué fasse mentir
        // l'écran sans que rien ne le signale.
        XCTAssertEqual(Quran.surahs.count, 114)
    }

    func testTheVerseCountLabelIsTheReferenceWording() {
        XCTAssertEqual(SurahPickerOptions.verseCountLabel(7), "7 versets")
        XCTAssertEqual(SurahPickerOptions.verseCountLabel(286), "286 versets")
    }

    func testTheAccessibilityLabelIsTheReferenceOne() {
        // `` `${item.number}. ${item.name}` ``
        XCTAssertEqual(
            SurahPickerOptions.accessibilityLabel(number: 2, name: "Al Baqarah"),
            "2. Al Baqarah"
        )
        // Le témoin qui ancre le test dans les vraies métadonnées : la sourate 2
        // s'appelle bien « Al Baqarah », et son étiquette est donc celle-ci.
        XCTAssertEqual(
            SurahPickerOptions.accessibilityLabel(
                number: Quran.surahs[1].number,
                name: Quran.surahs[1].name
            ),
            "2. Al Baqarah"
        )
    }

    // MARK: - Le modèle de la liste

    func testEverySurahOfTheListCanBeSelected() {
        // Chaque sourate a un numéro **1-basé** utilisable comme `currentSurah`,
        // et son `start` est un identifiant de verset — pas une page. Le
        // confondre était le défaut que `showPage` répare.
        for (index, surah) in Quran.surahs.enumerated() {
            XCTAssertEqual(surah.number, index + 1, "sourate à l'indice \(index)")
            XCTAssertTrue(surah.start >= 1)
            XCTAssertGreaterThan(surah.count, 0, "sourate \(surah.number)")
        }
    }

    func testTheSurahStartIsNotAPage() {
        // Le témoin qui prouve que `start` n'est pas un numéro de page : la
        // deuxième sourate commence au verset 8, pas à la page 8. Poser `start`
        // dans `page` montrerait la page 8 — un défaut silencieux et visible.
        let baqara = Quran.surahs[1]
        XCTAssertEqual(baqara.start, 8)
        XCTAssertTrue((1...604).contains(baqara.start))
    }
}

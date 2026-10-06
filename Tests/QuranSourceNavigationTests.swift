// QuranSourceNavigationTests.swift
// Traduire un verset en page, pour une édition donnée — port de
// `src/core/sourceNavigation.ts`.
//
// CE QUE CES TESTS PROTÈGENT
//   « Reprendre » une marque-page doit ouvrir la page du VERSET dans l'édition
//   qu'on est en train de lire. Les deux éditions rendues ici n'ont pas la même
//   pagination : la page 121 du Coran de Médine et la page 121 du Coran 1441 ne
//   montrent pas le même passage. Se tromper de pagination n'a donc aucun
//   symptôme visible — la page s'ouvre, elle est simplement au mauvais endroit.
//
//   La fonction a DEUX appelants — la liste des marque-pages, pour écrire
//   « Page N », et la reprise, pour ouvrir —, et ces tests garantissent qu'ils
//   reçoivent la même réponse. C'est le seul moyen que l'écran n'annonce pas une
//   page que le bouton n'ouvre pas.
//
// LES CHIFFRES SONT MESURÉS, PAS SUPPOSÉS
//   `Resources/Data/bounds.json` (Coran de Médine), `coran_1441-bounds.json`
//   (Coran 1441) et `pages.json` donnent, pour chacun des 6236 versets, ses pages
//   dans les deux sources. Mesures :
//
//     - les deux éditions donnent la MÊME première page pour 6180 versets ;
//     - elles en donnent une DIFFÉRENTE pour **56** versets — le verset 746 est
//       du nombre : page 121 côté Médine, page 120 côté Coran 1441 ;
//     - aucun verset n'occupe plus d'une page, dans aucune des deux sources.
//
//   Le test 1 s'appuie sur le verset 746 : sans cet écart, il ne distinguerait
//   rien et passerait pour la mauvaise raison. Le test 6 épingle le nombre 56 —
//   s'il change un jour, c'est la DONNÉE qui a changé, et il faut le savoir.

import XCTest
@testable import Swiftdeepseek

final class QuranSourceNavigationTests: XCTestCase {

    /// Le verset témoin : Al Mâ'idah 77, la seule chose qui rende les tests 1 à 3
    /// capables de distinguer les deux paginations.
    private let verse = 746
    private let medinePage = 121
    private let coran1441Page = 120

    // MARK: - Coran de Médine

    func testTheMedineEditionReturnsTheMushafPage() {
        XCTAssertEqual(QuranSourceNavigation.versePage(.medine, verseID: verse), medinePage)
    }

    /// LA RÈGLE SILENCIEUSE : pour le Coran de Médine, la page connue est IGNORÉE.
    ///
    /// `sourceVersePage` ne lit `current` que pour les sources à pagination
    /// propre ; pour les autres il rend `pageOf(id)`, sans le regarder. Retenir
    /// `current` ici ferait diverger la reprise dès que la page enregistrée n'est
    /// pas la page d'ouverture du verset.
    func testTheMedineEditionIgnoresTheKnownPage() {
        XCTAssertEqual(
            QuranSourceNavigation.versePage(.medine, verseID: verse, current: coran1441Page),
            medinePage
        )
        XCTAssertEqual(
            QuranSourceNavigation.versePage(.medine, verseID: verse, current: medinePage),
            medinePage
        )
    }

    // MARK: - Coran 1441

    /// Une page connue QUI PORTE le verset est conservée.
    func testTheCoran1441EditionKeepsAStoredPageThatBelongsToTheVerse() {
        XCTAssertEqual(
            QuranSourceNavigation.versePage(.coran1441, verseID: verse, current: coran1441Page),
            coran1441Page
        )
    }

    /// LA DIVERGENCE CORRIGÉE : une page venue d'une AUTRE pagination est refusée.
    ///
    /// C'est le cas atteignable : une marque-page posée en lisant le Coran de
    /// Médine n'a pas de page pour le Coran 1441 dans `sourcePages`. L'ancien
    /// repli — `item.page` — ouvrait alors la page 121 du Coran 1441, soit un
    /// passage sans rapport. `zipVersePage` ne retient `current` que s'il fait
    /// partie des pages du verset, et rend sinon la première.
    func testTheCoran1441EditionRejectsAPageFromAnotherPagination() {
        XCTAssertEqual(
            QuranSourceNavigation.versePage(.coran1441, verseID: verse, current: medinePage),
            coran1441Page
        )
    }

    func testTheCoran1441EditionWithoutAKnownPageReturnsTheFirstPageOfTheVerse() {
        XCTAssertEqual(QuranSourceNavigation.versePage(.coran1441, verseID: verse), coran1441Page)
    }

    /// La page rendue est toujours dans les bornes du moushaf.
    func testTheCoran1441EditionAlwaysReturnsAPageInsideTheMushaf() {
        for id in 1...Quran.verses.count {
            let page = QuranSourceNavigation.versePage(.coran1441, verseID: id)
            XCTAssertNotNil(page, "verset \(id) : aucune page dans le Coran 1441")
            XCTAssertTrue(
                (1...QuranSourceService.totalPages).contains(page ?? -1),
                "verset \(id) : page \(page ?? -1) hors du moushaf"
            )
        }
    }

    // MARK: - Les deux éditions, sur tout le Coran

    /// Le Coran de Médine : la fonction rend EXACTEMENT `Quran.pageOf`.
    func testTheMedineEditionAgreesWithPageOfOnEveryVerse() {
        for id in 1...Quran.verses.count {
            XCTAssertEqual(
                QuranSourceNavigation.versePage(.medine, verseID: id),
                Quran.pageOf(id),
                "verset \(id)"
            )
        }
    }

    /// L'écart entre les deux paginations, ÉPINGLÉ : **56** versets sur 6236.
    ///
    /// Ce n'est pas une constante arbitraire : c'est la mesure des fichiers
    /// livrés. Un changement de ce nombre veut dire que la donnée a changé, et
    /// que la page d'une reprise de lecture a pu se déplacer.
    func testTheTwoEditionsDisagreeOnExactlyFiftySixVerses() {
        var differents: [Int] = []
        for id in 1...Quran.verses.count {
            let medine = QuranSourceNavigation.versePage(.medine, verseID: id)
            let coran1441 = QuranSourceNavigation.versePage(.coran1441, verseID: id)
            if medine != coran1441 { differents.append(id) }
        }
        XCTAssertEqual(
            differents.count, 56,
            "l'écart entre les deux paginations a changé — la donnée a changé"
        )
        XCTAssertTrue(differents.contains(verse), "le verset témoin n'est plus un écart")
    }

    /// Un `current` qui n'appartient pas au verset est refusé pour TOUS les versets.
    ///
    /// Aucun verset n'occupe deux pages dans les fichiers livrés, donc `page + 1`
    /// n'est jamais une de ses pages. C'est ce qui rend la validation observable
    /// sur l'ensemble du Coran, et pas seulement sur le verset témoin.
    func testAStoredPageThatDoesNotBelongToTheVerseIsAlwaysRejected() {
        for id in 1...Quran.verses.count {
            let page = QuranSourceNavigation.versePage(.coran1441, verseID: id)
            XCTAssertEqual(
                QuranSourceNavigation.versePage(.coran1441, verseID: id, current: (page ?? 1) + 1),
                page,
                "verset \(id)"
            )
        }
    }

    // MARK: - La branche des éditions de Tajwid

    /// Les trois éditions de Tajwid empruntent **la même** branche — celle du
    /// moushaf —, et deux d'entre elles sont inatteignables.
    ///
    /// POUR LES DEUX INATTEIGNABLES, C'EST UNE DIVERGENCE ASSUMÉE, et elle est
    /// bornée : `sourceVersePage` appellerait `testVersePage` pour `coranTest`,
    /// qui lit un index construit depuis le moushaf de Tajwid — 607 polices
    /// `.woff2` que cette application n'embarque pas. La branche est
    /// **inatteignable** pour elles : `isAvailable` est faux, et
    /// `displayed(stored:)` les remplace par `.medine`. Voir
    /// `QuranEditionTests` pour cette substitution.
    ///
    /// POUR « LECTURE SIMPLIFIÉE », LA MÊME BRANCHE EST LA BONNE, et elle est
    /// désormais ATTEIGNABLE. L'édition n'est pas un zip, donc `isZipSource` est
    /// faux, et sa page est celle du Coran de Médine : c'est la pagination que
    /// `TajweedVerseListView` reçoit, et dont elle rend les versets. Ce test
    /// affirmait l'inverse — que l'édition ne pouvait pas être atteinte —, et il
    /// aurait donc fallu le retourner pour que le rendu existe : un contrôle
    /// négatif qui survit à l'état qu'il visait ne protège plus rien, il interdit
    /// le progrès.
    func testTheTajwidEditionsShareTheMushafPageBranch() {
        XCTAssertEqual(QuranSourceNavigation.versePage(.coranTest, verseID: verse), medinePage)
        XCTAssertEqual(QuranSourceNavigation.versePage(.tajweedPages, verseID: verse), medinePage)

        // Ce qui rend la divergence inatteignable — sans quoi elle serait un
        // défaut, et pas une limite.
        XCTAssertFalse(QuranEdition.coranTest.isAvailable)
        XCTAssertFalse(QuranEdition.tajweedPages.isAvailable)
        XCTAssertEqual(QuranEdition.displayed(stored: "coranTest"), .medine)
        XCTAssertEqual(QuranEdition.displayed(stored: "tajweedPages"), .medine)

        // Et celle qui a quitté cette catégorie : même branche, mais atteinte.
        XCTAssertTrue(QuranEdition.tajweed.isAvailable)
        XCTAssertEqual(QuranEdition.displayed(stored: "tajweed"), .tajweed)
        XCTAssertEqual(QuranSourceNavigation.versePage(.tajweed, verseID: verse), medinePage)
    }
}

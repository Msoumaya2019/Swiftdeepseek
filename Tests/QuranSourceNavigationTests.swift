// QuranSourceNavigationTests.swift
// Traduire un verset en page, et une page en plage de versets, pour une édition
// donnée — port de `src/core/sourceNavigation.ts`.
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
//   La seconde moitié du fichier protège le MÊME aiguillage dans l'autre sens :
//   la PLAGE d'une page, que le panneau audio sert sous la pastille « Toute la
//   page ». Elle dépend de l'édition pour la même raison, et sur **36 pages sur
//   604** les deux paginations donnent une plage différente.
//
// LES CHIFFRES SONT MESURÉS, PAS SUPPOSÉS
//   `Resources/Data/bounds.json` (Coran de Médine), `coran_1441-bounds.json`
//   (Coran 1441) et `pages.json` donnent, pour chacun des 6236 versets, ses pages
//   dans les deux sources. Mesures :
//
//     - les deux éditions donnent la MÊME première page pour 6180 versets ;
//     - elles en donnent une DIFFÉRENTE pour **56** versets — le verset 746 est
//       du nombre : page 121 côté Médine, page 120 côté Coran 1441 ;
//     - aucun verset n'occupe plus d'une page, dans aucune des deux sources ;
//     - pour les plages, ce sont **36 pages** sur 604 qui diffèrent, et sur 33
//       d'entre elles la LONGUEUR de la plage diffère aussi.
//
//   Le test 1 s'appuie sur le verset 746 : sans cet écart, il ne distinguerait
//   rien et passerait pour la mauvaise raison. Le test 6 épingle le nombre 56, et
//   le test 16 la liste des 36 pages — s'ils changent un jour, c'est la DONNÉE
//   qui a changé, et il faut le savoir.
//
//   Les valeurs attendues de la seconde moitié viennent de
//   `_banc/oracle-source-navigation.mjs`, qui EMPAQUETTE le vrai
//   `sourceNavigation.ts` et l'exécute : elles ne sont pas déduites du code
//   testé.
//
// CE QUE LA BRANCHE `coranTest` EST DEVENUE
//   Elle était présentée comme une « divergence assumée » : `testVersePage` lit
//   un index « construit depuis le moushaf de Tajwid — 607 polices `.woff2` que
//   cette application n'embarque pas ». C'est faux, et c'était la raison même de
//   l'abandon : ces polices appartiennent à la chaîne de RENDU, pas à celle de
//   navigation, qui ne lit que des nombres (`verse-index.json` : 380 782 octets
//   de `{id, pages, lines}`, aucune police, aucune vue). La branche est donc
//   portée, et ses deux réponses sont justes. Elle reste **dormante** :
//   `isAvailable` est faux pour `.coranTest`, donc `displayed(stored:)` la
//   remplace par `.medine` et aucun écran ne la reçoit. Le test 10 épingle les
//   deux choses séparément — la réponse, et la dormance.

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

    /// `coranTest` suit la pagination du **1441**, et `tajweedPages` celle du
    /// **Médine** — deux branches différentes, et non une seule.
    ///
    /// `sourceVersePage` aiguille sur `source === 'coranTest'` en PREMIER, et
    /// `coranTest` n'est pas un zip : c'est donc `testVersePage` qui répond, et
    /// l'index de `testVersePage` est celui du moushaf de Tajwid. Le groupe
    /// précédent — `case .medine, .tajweed, .tajweedPages, .coranTest` — le
    /// faisait répondre `pageOf(id)`, c'est-à-dire la pagination du Coran de
    /// Médine : une catégorie fausse, qui rangeait l'édition au découpage de
    /// Tajwid avec celles au découpage de Médine.
    ///
    /// CE QUI JUSTIFIE DE LES RÉUNIR AVEC LE 1441 PLUTÔT QUE D'INVENTER UNE
    /// TROISIÈME BRANCHE : les deux index rendent la même réponse. Mesuré par
    /// `_banc/oracle-source-navigation.mjs` — 0 divergence sur 6 236 versets et
    /// sur 604 pages, pour les deux fonctions.
    ///
    /// ET CE QUI RESTE VRAI : la branche est DORMANTE. `isAvailable` est faux
    /// pour `.coranTest`, donc `displayed(stored:)` la remplace par `.medine` et
    /// aucun écran ne la reçoit. Les deux faits sont éprouvés séparément, pour
    /// qu'un changement de l'un ne passe pas sous le couvert de l'autre.
    func testTheTajwidEditionsFollowTheirOwnPagination() {
        // La réponse de l'original : `testVersePage`, identique à `zipVersePage`.
        XCTAssertEqual(QuranSourceNavigation.versePage(.coranTest, verseID: verse), coran1441Page)

        // Celles qui suivent bien le découpage du Coran de Médine.
        XCTAssertEqual(QuranSourceNavigation.versePage(.tajweedPages, verseID: verse), medinePage)
        XCTAssertEqual(QuranSourceNavigation.versePage(.tajweed, verseID: verse), medinePage)

        // La dormance — sans quoi le premier écart serait un défaut, pas une
        // avance.
        XCTAssertFalse(QuranEdition.coranTest.isAvailable)
        XCTAssertFalse(QuranEdition.tajweedPages.isAvailable)
        XCTAssertEqual(QuranEdition.displayed(stored: "coranTest"), .medine)
        XCTAssertEqual(QuranEdition.displayed(stored: "tajweedPages"), .medine)

        // Et celle qui est ATTEINTE : `tajweed` est lisible, et c'est bien la
        // pagination du Coran de Médine que `TajweedVerseListView` reçoit.
        XCTAssertTrue(QuranEdition.tajweed.isAvailable)
        XCTAssertEqual(QuranEdition.displayed(stored: "tajweed"), .tajweed)
    }

    /// Les deux branches se confondent sur TOUT le Coran, pas seulement sur le
    /// verset témoin. C'est cette égalité qui autorise à n'avoir qu'une branche.
    func testTheCoranTestAndCoran1441BranchesAgreeOnEveryVerse() {
        for id in 1...Quran.verses.count {
            XCTAssertEqual(
                QuranSourceNavigation.versePage(.coranTest, verseID: id),
                QuranSourceNavigation.versePage(.coran1441, verseID: id),
                "verset \(id)"
            )
        }
    }

    // MARK: - La plage d'une page

    /// `sourcePageRange` — la plage d'une page, dans la pagination de l'édition.
    ///
    /// Les trois éditions qui suivent le découpage du Coran de Médine rendent
    /// exactement `Quran.pageRange` : c'est l'aiguillage `sinon` de l'original,
    /// celui qui vaut aussi pour les identifiants inconnus.
    func testTheMedinePaginationServesThreeEditions() {
        for page in 1...QuranSourceService.totalPages {
            let expected = Quran.pageRange(page)
            XCTAssertEqual(QuranSourceNavigation.pageRange(.medine, page: page), expected, "page \(page)")
            XCTAssertEqual(QuranSourceNavigation.pageRange(.tajweed, page: page), expected, "page \(page)")
            XCTAssertEqual(QuranSourceNavigation.pageRange(.tajweedPages, page: page), expected, "page \(page)")
        }
    }

    /// Les deux éditions à pagination propre — 1441 et `coranTest` — rendent la
    /// MÊME plage, sur les 604 pages. Même mesure que pour la page d'un verset.
    func testTheCoran1441AndCoranTestPaginationAgreeOnEveryPage() {
        for page in 1...QuranSourceService.totalPages {
            XCTAssertEqual(
                QuranSourceNavigation.pageRange(.coranTest, page: page),
                QuranSourceNavigation.pageRange(.coran1441, page: page),
                "page \(page)"
            )
        }
    }

    /// La plage de chaque page est non vide, croissante, et dans le Coran — pour
    /// les cinq identifiants d'édition.
    ///
    /// L'original ne se comporte pas de la même façon sur une page hors bornes :
    /// `pageRange` lève, `zipPageRange` rend `{Infinity, -Infinity}`,
    /// `testPageRange` lève. Les trois sont inatteignables — 604 pages sur 604
    /// dans les deux fichiers —, et le `nil` du portage les dit d'un seul mot.
    func testEveryPageHasAValidRangeInEveryEdition() {
        let editions: [QuranEdition] = [.medine, .coran1441, .tajweed, .tajweedPages, .coranTest]
        for edition in editions {
            for page in 1...QuranSourceService.totalPages {
                guard let range = QuranSourceNavigation.pageRange(edition, page: page) else {
                    XCTFail("\(edition.rawValue) · page \(page) : aucune plage")
                    continue
                }
                XCTAssertTrue(
                    range.start >= 1 && range.end <= Quran.verses.count && range.start <= range.end,
                    "\(edition.rawValue) · page \(page) : plage \(range.start)…\(range.end) hors du Coran"
                )
            }
        }
    }

    /// Les pages où les deux paginations donnent une plage DIFFÉRENTE — **36** sur
    /// 604, ÉNUMÉRÉES.
    ///
    /// Le compte seul ne suffirait pas : il ne voit pas une page qui entre dans la
    /// liste quand une autre en sort. La liste est donc figée, et comparée
    /// élément par élément.
    func testTheTwoPaginationsDisagreeOnExactlyTheseThirtySixPages() {
        let divergentPages = [
            120, 121, 122, 123, 144, 145, 531, 532, 533, 534, 564, 565,
            567, 568, 569, 570, 575, 576, 583, 584, 585, 586, 587, 588,
            589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600,
        ]
        XCTAssertEqual(divergentPages.count, 36)

        var mesurees: [Int] = []
        for page in 1...QuranSourceService.totalPages {
            if QuranSourceNavigation.pageRange(.medine, page: page)
                != QuranSourceNavigation.pageRange(.coran1441, page: page) {
                mesurees.append(page)
            }
        }
        XCTAssertEqual(
            mesurees, divergentPages,
            "les pages en écart ont changé — la donnée a changé"
        )
    }

    /// Le plus grand écart entre les deux paginations, nommé : la page 597.
    ///
    /// Elle perd six versets d'un côté et en gagne sept de l'autre — 6 099…6 125
    /// au Coran de Médine contre 6 093…6 118 en 1441. Servir l'une pour l'autre
    /// annonce donc 33 versets au lieu de 26.
    func testTheWidestGapBetweenTheTwoPaginationsIsPage597() {
        XCTAssertEqual(
            QuranSourceNavigation.pageRange(.medine, page: 597),
            VerseRange(start: 6099, end: 6125)
        )
        XCTAssertEqual(
            QuranSourceNavigation.pageRange(.coran1441, page: 597),
            VerseRange(start: 6093, end: 6118)
        )
        XCTAssertEqual(
            QuranSourceNavigation.pageRange(.coranTest, page: 597),
            VerseRange(start: 6093, end: 6118),
            "coranTest suit le 1441, pas le Médine"
        )
    }

    /// Le cas atteignable, nommé : la page 121, celle que le lecteur du Coran 1441
    /// affiche quand le verset témoin y est.
    ///
    /// `verse` (746) est en page 121 au Médine et 120 en 1441 ; la page 121 du
    /// 1441 commence donc au verset 747, et non 746.
    func testTheReachableCaseIsPage121() {
        XCTAssertEqual(
            QuranSourceNavigation.pageRange(.medine, page: 121),
            VerseRange(start: 746, end: 751)
        )
        XCTAssertEqual(
            QuranSourceNavigation.pageRange(.coran1441, page: 121),
            VerseRange(start: 747, end: 752)
        )
    }

    /// Les bornes du moushaf : les deux paginations s'accordent à la première et à
    /// la dernière page, et l'union du 1441 couvre tout le Coran.
    func testTheTwoPaginationsAgreeOnTheFirstAndLastPage() {
        let premiere = VerseRange(start: 1, end: 7)
        let derniere = VerseRange(start: 6222, end: 6236)
        XCTAssertEqual(QuranSourceNavigation.pageRange(.medine, page: 1), premiere)
        XCTAssertEqual(QuranSourceNavigation.pageRange(.coran1441, page: 1), premiere)
        XCTAssertEqual(QuranSourceNavigation.pageRange(.medine, page: 604), derniere)
        XCTAssertEqual(QuranSourceNavigation.pageRange(.coran1441, page: 604), derniere)
    }

    /// Une page hors bornes rend `nil` — pour les cinq éditions, des deux côtés.
    ///
    /// L'original lève dans deux cas sur trois et rend une plage infinie dans le
    /// troisième ; le portage dit `nil` dans les trois, et l'appelant retombe
    /// alors sur sa plage de séance.
    func testAPageOutsideTheMushafHasNoRange() {
        let editions: [QuranEdition] = [.medine, .coran1441, .tajweed, .tajweedPages, .coranTest]
        for edition in editions {
            XCTAssertNil(QuranSourceNavigation.pageRange(edition, page: 0), "\(edition.rawValue) · page 0")
            XCTAssertNil(QuranSourceNavigation.pageRange(edition, page: 605), "\(edition.rawValue) · page 605")
        }
    }
}

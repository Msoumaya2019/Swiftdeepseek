// QuranEditionTests.swift
// L'édition que le lecteur ouvre **réellement**.
//
// POURQUOI CES TESTS EXISTENT
//   `defaultState()` enregistre `reader.mushaf == "coranTest"` — la valeur par
//   défaut de l'application d'origine (`src/core/program.ts:57`), donc celle de
//   **tout** utilisateur qui n'a jamais touché au choix d'affichage. Or
//   `coranTest` ne se rend pas comme une image : l'original le dessine dans une
//   page HTML chargée dans un WebView (`src/coranTest/html.ts`), avec 607
//   polices `.woff2` — une chaîne de rendu que cette application n'a pas.
//
//   Résoudre la préférence telle quelle ouvrait donc le lecteur sur une édition
//   sans images : `MushafPageViewController.load()` affichait « Cette page n'est
//   pas encore disponible hors ligne » sur **chaque** page, pour **tout**
//   utilisateur, dès la première ouverture. Aucun test ne couvrait la résolution
//   de l'édition ; le défaut n'avait donc rien pour le signaler.
//
// CE QUE CES TESTS FIXENT
//   Que l'édition **affichée** est toujours lisible, quelle que soit la
//   préférence enregistrée — et que cette préférence, elle, n'est jamais
//   réécrite, puisque c'est elle que relit l'application React Native.

import XCTest
@testable import Swiftdeepseek

final class QuranEditionTests: XCTestCase {

    /// Les préférences qu'un document synchronisé peut porter : toutes les
    /// valeurs connues, plus les formes d'absence et d'inconnu.
    ///
    /// Construit pas à pas plutôt qu'en une expression : `map { $0.rawValue }`
    /// rend un `[String]`, et l'ajout de `nil` demande un `[String?]`. La
    /// conversion est écrite ici, à un endroit, au lieu d'être laissée à
    /// l'inférence sur toute la liste.
    private var everyStoredPreference: [String?] {
        var preferences: [String?] = QuranEdition.allCases.map { Optional($0.rawValue) }
        preferences.append(nil)
        preferences.append("")
        preferences.append("nawak")
        return preferences
    }

    // MARK: La prémisse du défaut

    /// Le défaut venait de là, et les deux moitiés sont mesurables : cette
    /// valeur est le défaut des **deux** applications, et elle n'est pas lisible
    /// ici.
    func testTheStoredDefaultIsTheTajwidEditionAndItIsNotRenderable() {
        let stored = Program.defaultState().reader?.mushaf

        XCTAssertEqual(stored, "coranTest")
        XCTAssertEqual(QuranEdition(rawValue: "coranTest"), .coranTest)
        XCTAssertFalse(QuranEdition.coranTest.isAvailable)
    }

    /// La cause exacte, montrée plutôt que racontée : l'édition enregistrée par
    /// défaut ne rend **aucune** image. Le lecteur en concluait « page
    /// indisponible », ce qui était faux — c'est l'édition qui n'est pas
    /// rendue, pas la page qui manque.
    func testTheStoredDefaultRendersNoImageAtAll() {
        let service = QuranSourceService()

        XCTAssertTrue(service.imageURLs(for: .coranTest, page: 1).isEmpty)
        XCTAssertTrue(service.imageURLs(for: .tajweed, page: 1).isEmpty)
        XCTAssertTrue(service.imageURLs(for: .tajweedPages, page: 1).isEmpty)
        XCTAssertFalse(service.imageURLs(for: .medine, page: 1).isEmpty)
    }

    // MARK: Le repli

    /// Le repli, et **la seule** édition qui en a encore besoin.
    ///
    /// « Lecture simplifiée » a quitté cette liste : elle est lisible depuis que
    /// son rendu existe (`TajweedVerseListView`), donc `displayed(stored:)` la
    /// garde. L'y laisser aurait fait échouer ce test sur une édition devenue
    /// disponible — et, pire, aurait demandé au code de continuer à la
    /// remplacer.
    func testAnUnrenderablePreferenceFallsBackToTheMedineMushaf() {
        XCTAssertEqual(QuranEdition.displayed(stored: "coranTest"), .medine)
        XCTAssertEqual(QuranEdition.displayed(stored: "tajweedPages"), .medine)
    }

    func testARenderablePreferenceIsKept() {
        XCTAssertEqual(QuranEdition.displayed(stored: "traditional"), .medine)
        XCTAssertEqual(QuranEdition.displayed(stored: "coran_1441"), .coran1441)
        // `displayed(stored:)` rend l'édition **elle-même** : la préférence
        // enregistrée par l'application React Native n'est pas réécrite.
        XCTAssertEqual(QuranEdition.displayed(stored: "tajweed"), .tajweed)
        XCTAssertEqual(QuranEdition.tajweed.isAvailable, TajweedOptions.isAvailable)
    }

    func testAnAbsentOrUnknownPreferenceFallsBack() {
        XCTAssertEqual(QuranEdition.displayed(stored: nil), .medine)
        XCTAssertEqual(QuranEdition.displayed(stored: ""), .medine)
        XCTAssertEqual(QuranEdition.displayed(stored: "nawak"), .medine)
    }

    /// Le repli doit être **lui-même** affichable : se replier sur une édition
    /// non installée remplacerait un lecteur faux par un lecteur vide, ce qui
    /// ferait deux défauts au lieu d'un.
    func testTheFallbackIsItselfRenderable() {
        XCTAssertTrue(QuranEdition.fallback.isAvailable)
        XCTAssertEqual(QuranEdition.displayed(stored: nil), QuranEdition.fallback)
    }

    // MARK: L'invariant — le contrôle qui manquait

    /// Quelle que soit la préférence enregistrée, l'édition affichée est
    /// lisible, et **rendable**.
    ///
    /// C'est le contrôle qui aurait attrapé le défaut. Une édition ajoutée à
    /// `QuranEdition` sans ressource le fera échouer, au lieu de produire un
    /// lecteur muet qu'aucun test ne distingue d'un lecteur qui marche.
    ///
    /// LES DEUX FAÇONS DE RENDRE SONT VÉRIFIÉES SÉPARÉMENT, et c'est le run
    /// n° 72 qui l'a exigé. Une édition **paginée** doit savoir où sont ses
    /// versets : sans `boundsSource`, aucune mise en évidence n'est possible.
    /// « Lecture simplifiée » se rend en **cartes** : elle n'a pas de rectangles,
    /// et ne doit pas en avoir — une bande y serait posée sur une page qui
    /// n'existe pas. Ce test exigeait des rectangles de **toute** édition
    /// affichée, ce qui était vrai tant que la liste n'existait pas : l'invariant
    /// avait survécu au jour où il avait cessé d'être vrai, et il a fallu une
    /// exécution pour le dire.
    func testWhateverIsStoredTheDisplayedEditionIsRenderable() {
        for stored in everyStoredPreference {
            let displayed = QuranEdition.displayed(stored: stored)
            let quoi = "préférence « \(stored ?? "absente") » → \(displayed.rawValue)"

            XCTAssertTrue(displayed.isAvailable, "\(quoi) n'est pas lisible")
            XCTAssertTrue(displayed.isRenderable, "\(quoi) n'est pas rendable")

            if displayed.isVerseList {
                XCTAssertNil(
                    displayed.boundsSource,
                    "\(quoi) se rend en cartes : elle ne doit avoir aucun rectangle"
                )
                XCTAssertTrue(
                    TajweedOptions.isAvailable,
                    "\(quoi) n'a de rendu que si ses trois fichiers sont là"
                )
            } else {
                XCTAssertNotNil(
                    displayed.boundsSource,
                    "\(quoi) n'a pas de rectangles : aucune mise en évidence possible"
                )
            }
        }
    }

    /// Une seule édition se rend en cartes, et c'est celle-là.
    ///
    /// Le pendant du contrôle précédent : il dit **qui** a le droit de n'avoir
    /// aucun rectangle. Sans lui, une édition future pourrait perdre son
    /// `boundsSource` sans que rien ne le signale — le test ci-dessus la
    /// laisserait passer en la croyant en cartes.
    func testTheVerseListEditionIsTheOnlyOneWithoutRectangles() {
        XCTAssertTrue(QuranEdition.tajweed.isVerseList)
        XCTAssertNil(QuranEdition.tajweed.boundsSource)

        for edition in QuranEdition.allCases where edition != .tajweed {
            XCTAssertFalse(edition.isVerseList, "\(edition.rawValue) se rend en pages")
        }

        // Les deux éditions paginées reprises ont bien leurs rectangles.
        XCTAssertNotNil(QuranEdition.medine.boundsSource)
        XCTAssertNotNil(QuranEdition.coran1441.boundsSource)

        // Et les deux non reprises n'en ont pas — sans être en cartes pour
        // autant : elles ne sont pas rendues du tout.
        XCTAssertFalse(QuranEdition.tajweedPages.isRenderable)
        XCTAssertFalse(QuranEdition.coranTest.isRenderable)
    }

    /// Le vrai symptôme, mesuré au bout de la chaîne : le lecteur ouvre
    /// `imageURLs(for: edition, page: 1)`, et une liste vide fait afficher son
    /// message d'indisponibilité.
    ///
    /// Le repli, lui, est dans le paquet : c'est ce qui fait qu'une préférence
    /// non reprise n'aboutit plus à un lecteur muet. Le Coran 1441 est hors de
    /// ce contrôle — ses images s'installent, et son absence est déjà annoncée
    /// pour ce qu'elle est (`MushafPageViewController`, branche `banded`).
    func testAPreferenceThisVersionCannotRenderStillOpensOnRealPages() {
        let service = QuranSourceService()

        for stored in everyStoredPreference where QuranEdition.displayed(stored: stored) == .medine {
            let displayed = QuranEdition.displayed(stored: stored)
            XCTAssertFalse(
                service.imageURLs(for: displayed, page: 1).isEmpty,
                "préférence « \(stored ?? "absente") » → \(displayed.rawValue) n'a aucune image pour la page 1"
            )
        }
    }

    // MARK: La préférence enregistrée n'est pas réécrite

    /// Le repli est une décision d'**affichage**, pas une correction de données.
    /// Réécrire `reader.mushaf` changerait ce que voit l'application React
    /// Native, qui relit ce même document.
    func testTheStoredPreferenceSurvivesTheMigration() {
        let state = Program.defaultState()

        XCTAssertEqual(Program.migrateReaderState(state).reader?.mushaf, "coranTest")
        XCTAssertEqual(Program.touch(state).reader?.mushaf, "coranTest")
    }

    /// La migration d'origine est reproduite fidèlement : les anciennes clés
    /// partent vers le Coran 1441, et `tajweedPages` vers `coranTest`. Ces deux
    /// règles expliquent pourquoi `coranTest` est la valeur qu'on rencontre.
    func testTheLegacyKeysAreMigratedAsInTheOriginal() {
        for legacy in ["tawjeed_test_2", "tajweed_test_2", "medine_test"] {
            var state = Program.defaultState()
            state.reader?.mushaf = legacy
            XCTAssertEqual(Program.migrateReaderState(state).reader?.mushaf, "coran_1441")
        }

        var state = Program.defaultState()
        state.reader?.mushaf = "tajweedPages"
        XCTAssertEqual(Program.migrateReaderState(state).reader?.mushaf, "coranTest")
    }
}

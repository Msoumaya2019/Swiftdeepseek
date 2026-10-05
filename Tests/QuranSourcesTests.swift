// QuranSourcesTests.swift
// La carte « Sources du Coran » : des épingles, et un quirk typographique.
//
// Ces tests ne calculent rien : la carte est un texte. Leur valeur est de
// **figer** ce texte tel que la référence l'écrit, pour qu'une correction
// « bienveillante » — une apostrophe normalisée, un tiret redressé, une phrase
// raccourcie — ne passe pas en silence. C'est le même rôle que
// `testTheSevenSwitchesAreTheOnesOfTheReference` pour les notifications.
//
// Le test qui compte le plus est `testTheTwoApostrophesDiffer` : l'original
// écrit `juz’` avec une apostrophe courbe FERMANTE (U+2019) et `rub‘` avec une
// apostrophe courbe OUVRANTE (U+2018). La seconde est probablement une coquille,
// mais la corriger ferait diverger les deux applications à l'écran — donc on la
// recopie, et ce test empêche qu'on l'oublie.

import XCTest
@testable import Swiftdeepseek

final class QuranSourcesTests: XCTestCase {

    // MARK: - Les chaînes, telles que `App.tsx:350`

    func testTheTitleIsTheOneOfTheReference() {
        XCTAssertEqual(QuranSourcesCard.title, "Sources du Coran")
    }

    func testTheTextAttributionIsExact() {
        XCTAssertEqual(
            QuranSourcesCard.textAttribution,
            "Texte Uthmani Hafs : Tanzil Project, copyright 2007–2021, licence CC BY 3.0. Texte reproduit sans modification."
        )
    }

    func testTheEditionAttributionIsExact() {
        XCTAssertEqual(
            QuranSourcesCard.editionAttribution,
            "Pages Hafs 1405 issues de l’IPA fournie. Moushaf avec règles de Tajwid : polices QPC V4 et pagination originales issues de l’IPA fournie. Lecture simplifiée : annotations de cpfair sous CC BY 4.0 sur texte Tanzil Hafs 2017. Traduction française du sens : Rachid Maach, version 1.0.3, QuranEnc. Divisions juz’, hizb et rub‘ : Quran Meta. Les toumoun Hafs attendent une validation indépendante."
        )
    }

    func testTheLinkTitleCarriesTheNorthEastArrow() {
        XCTAssertEqual(QuranSourcesCard.linkTitle, "Voir Tanzil et les mises à jour \u{2197}")
    }

    // MARK: - Le lien

    func testTheLinkPointsToTanzil() {
        XCTAssertEqual(QuranSourcesCard.linkURLString, "https://tanzil.net")
        XCTAssertEqual(QuranSourcesCard.linkURL.absoluteString, "https://tanzil.net")
        XCTAssertEqual(QuranSourcesCard.linkURL.host, "tanzil.net")
    }

    // MARK: - Le quirk typographique, épinglé

    /// L'original écrit deux apostrophes courbes **différentes** dans le même
    /// paragraphe. Ce test dit lesquelles, et refuse les formes redressées :
    /// une normalisation « propre » casserait l'égalité d'affichage entre les
    /// deux applications pour une raison qui n'appartient à aucune des deux.
    func testTheTwoApostrophesDiffer() {
        let texte = QuranSourcesCard.editionAttribution
        XCTAssertTrue(texte.contains("juz\u{2019}"), "« juz’ » porte l'apostrophe courbe FERMANTE U+2019")
        XCTAssertTrue(texte.contains("rub\u{2018}"), "« rub‘ » porte l'apostrophe courbe OUVRANTE U+2018")
        XCTAssertFalse(texte.contains("juz'"), "l'original n'écrit pas « juz' » avec une apostrophe droite")
        XCTAssertFalse(texte.contains("rub'"), "l'original n'écrit pas « rub' » avec une apostrophe droite")
        XCTAssertFalse(texte.contains("rub\u{2019}"), "« rub‘ » n'est pas écrit avec l'apostrophe de « juz’ »")
    }

    /// Le tiret de « 2007–2021 » est un demi-cadratin, pas un trait d'union.
    func testTheCopyrightRangeUsesAnEnDash() {
        XCTAssertTrue(QuranSourcesCard.textAttribution.contains("2007\u{2013}2021"))
        XCTAssertFalse(QuranSourcesCard.textAttribution.contains("2007-2021"))
    }

    // MARK: - Les obligations de licence, comptées

    /// Les six sources nommées dans le second paragraphe. Un texte long recopié
    /// à la main se tronque volontiers sans que rien ne le dise : compter les
    /// noms rend la troncature visible.
    func testTheAttributionNamesEverySource() {
        let texte = QuranSourcesCard.editionAttribution
        for nom in ["Tanzil", "QPC V4", "cpfair", "Rachid Maach", "QuranEnc", "Quran Meta"] {
            XCTAssertTrue(texte.contains(nom), "l'attribution nomme « \(nom) »")
        }
    }

    /// Les licences citées — c'est une obligation, pas une décoration.
    func testTheLicencesAreCited() {
        let texte = QuranSourcesCard.textAttribution + " " + QuranSourcesCard.editionAttribution
        XCTAssertTrue(texte.contains("CC BY 3.0"), "la licence du texte (Tanzil) est citée")
        XCTAssertTrue(texte.contains("CC BY 4.0"), "la licence des annotations (cpfair) est citée")
        XCTAssertTrue(texte.contains("version 1.0.3"), "la version de la traduction est citée")
    }

    /// La mention « sans modification » fait partie de l'obligation CC BY :
    /// elle dit que le texte n'a pas été altéré.
    func testTheTextIsDeclaredUnmodified() {
        XCTAssertTrue(QuranSourcesCard.textAttribution.contains("Texte reproduit sans modification."))
    }

    /// La réserve sur les toumoun est portée, pas oubliée — c'est elle qui
    /// explique, ailleurs, pourquoi le rythme `toumoun` n'est pas proposé
    /// (`SettingsView.paceLabel`).
    func testTheReserveOnToumounIsStillThere() {
        XCTAssertTrue(
            QuranSourcesCard.editionAttribution.hasSuffix("Les toumoun Hafs attendent une validation indépendante."),
            "la réserve sur les toumoun ferme le paragraphe"
        )
    }
}

// QuranDisplayTests.swift
// L'affichage du Coran : les éditions proposées, les fonds, et les règles
// d'écriture d'un appui.
//
// Ce que ces tests protègent :
//   - la LISTE des éditions, qui n'est pas `QuranEdition.allCases`. L'onglet
//     Coran parcourait `allCases`, donc affichait cinq éditions dans un autre
//     ordre, dont `tajweedPages` (« Moushaf Tajwid ») que l'original ne propose
//     dans **aucun** de ses deux sélecteurs. Le défaut était silencieux : la
//     liste s'affichait, simplement elle n'était pas la bonne ;
//   - la décision à TROIS issues. Confondre « installer » et « sélectionner »
//     ouvrirait le lecteur sur une édition dont les 9 060 images manquent —
//     c'est-à-dire sur des pages vides, pour tout utilisateur qui touche au
//     Coran 1441 avant de l'avoir installé ;
//   - les trois règles d'écriture, qui ne posent PAS le même défaut sur
//     `reader.mushaf` : celle des éditions écrit la valeur choisie, celles du
//     fond et du suivi audio écrivent `coranTest` quand il n'y a pas encore de
//     lecteur. C'est le contrat que l'application React Native relira ;
//   - le défaut de `followAudio`, qui est `!== false` et non `|| true` : un
//     `false` stocké doit rester `false` ;
//   - la couleur d'un fond inconnu, qui est celle du PREMIER fond.
//
// CE QUE CES TESTS NE PEUVENT PAS PROUVER, ET QUI EST PROUVÉ AILLEURS
//   L'égalité littérale des quatre fonds, des quatre sous-titres et des six
//   mesures avec la référence se compare à la source TypeScript, pas au Swift :
//   c'est le rôle de `_banc/verifier-coran-affichage.mjs`.
//
//   Les tests ci-dessous éprouvent le modèle pur. Aucun nombre n'y est inventé :
//   les libellés attendus sont dérivés de `QuranEdition.label` et de
//   `QuranDisplayOptions`, jamais recopiés d'un autre fichier.

import XCTest
// `import SwiftUI` est nécessaire, et non superflu : ces tests NOMMENT `Color`
// (le tableau `seen`, et la comparaison du noir). `@testable import` donne accès
// aux types du module, pas à ceux de SwiftUI — que `Theme.swift` importe pour
// lui-même sans les réexporter. `AppearanceTests.swift` n'a pas cet import parce
// qu'il ne nomme jamais `Color` : il ne lit que des couleurs déjà construites.
import SwiftUI
@testable import Swiftdeepseek

final class QuranDisplayTests: XCTestCase {

    // MARK: - Les éditions proposées

    /// Les quatre clés, dans l'ordre de l'original — `App.tsx:515` et
    /// `App.tsx:330` énumèrent les mêmes quatre entrées.
    func testTheFourEditionsAreTheOnesOfTheReference() {
        XCTAssertEqual(
            QuranDisplayOptions.editionKeys,
            ["traditional", "coranTest", "tajweed", "coran_1441"]
        )
        XCTAssertEqual(QuranDisplayOptions.editionOptions.map(\.id), QuranDisplayOptions.editionKeys)
    }

    /// La liste proposée n'est PAS `allCases`, et `tajweedPages` n'y figure pas.
    ///
    /// C'est la divergence qui a été corrigée : l'ancien `QuranScreenView` — la
    /// vue qui occupait l'onglet Coran avant `SurahListView` — parcourait
    /// `QuranEdition.allCases` et affichait donc « Moushaf Tajwid », une édition
    /// que `migrateReaderState` réécrit vers `coranTest` à chaque chargement
    /// (`src/core/program.ts:60`) — c'est-à-dire un choix que l'original ne
    /// laisse jamais prendre, et que cette version ne saurait pas rendre.
    ///
    /// Le test exige l'écart : si la liste égale un jour `allCases`, il échoue
    /// en le disant.
    func testTheProposedListIsNotEveryKnownEdition() {
        XCTAssertNotEqual(
            QuranDisplayOptions.editionKeys,
            QuranEdition.allCases.map(\.rawValue),
            "La liste proposée ne doit pas être « toutes les éditions connues »."
        )
        XCTAssertFalse(
            QuranDisplayOptions.editionKeys.contains(QuranEdition.tajweedPages.rawValue),
            "« Moushaf Tajwid » n'est proposé par aucun des deux sélecteurs de l'original."
        )
        XCTAssertEqual(QuranEdition.allCases.count, 5)
        XCTAssertEqual(QuranDisplayOptions.editionOptions.count, 4)
    }

    /// Chaque clé se résout en une `QuranEdition`, avec un libellé et un
    /// sous-titre non vides, et sans doublon.
    ///
    /// `editionOptions` passe par `compactMap` : une clé qui ne correspondrait à
    /// aucune édition disparaîtrait silencieusement de la liste. Le compte exact
    /// est donc la seule façon de voir la perte.
    func testEveryKeyResolvesWithALabelAndASubtitle() {
        XCTAssertEqual(QuranDisplayOptions.editionOptions.count, QuranDisplayOptions.editionKeys.count)

        for option in QuranDisplayOptions.editionOptions {
            XCTAssertEqual(option.edition.rawValue, option.id)
            XCTAssertFalse(option.label.isEmpty, "libellé manquant pour « \(option.id) »")
            XCTAssertFalse(option.subtitle.isEmpty, "sous-titre manquant pour « \(option.id) »")
            // Le libellé n'est pas recopié : il vient de l'énumération.
            XCTAssertEqual(option.label, option.edition.label)
        }
        XCTAssertEqual(
            Set(QuranDisplayOptions.editionKeys).count,
            QuranDisplayOptions.editionKeys.count,
            "Une édition est proposée deux fois."
        )
    }

    // MARK: - La décision d'un appui

    /// Les trois issues, cas par cas.
    func testTheChoiceOfAnEditionHasThreeOutcomes() {
        // Lisibles tout de suite : on sélectionne, installé ou non.
        for edition in QuranEdition.available {
            XCTAssertEqual(
                QuranDisplayOptions.choice(for: edition, coran1441Installed: true),
                .select
            )
        }
        XCTAssertEqual(
            QuranDisplayOptions.choice(for: .medine, coran1441Installed: false),
            .select,
            "Le Coran de Médine est dans le paquet : il n'a rien à installer."
        )

        // Le Coran 1441, non installé : on installe, on ne sélectionne pas.
        XCTAssertEqual(
            QuranDisplayOptions.choice(for: .coran1441, coran1441Installed: false),
            .install
        )
        XCTAssertEqual(
            QuranDisplayOptions.choice(for: .coran1441, coran1441Installed: true),
            .select
        )

        // Ce que cette version ne sait pas rendre : refus, jamais d'installation
        // — l'installation ne changerait rien à l'affaire, les ressources
        // n'existant pas.
        for edition in [QuranEdition.coranTest, .tajweedPages] {
            for installed in [true, false] {
                XCTAssertEqual(
                    QuranDisplayOptions.choice(for: edition, coran1441Installed: installed),
                    .unavailable,
                    "« \(edition.rawValue) » doit être refusé, installé ou non."
                )
            }
        }

        // « Lecture simplifiée » a QUITTÉ cette liste : elle est lisible depuis
        // que son rendu existe (`TajweedVerseListView`), et elle ne s'installe
        // pas — ses trois fichiers de données sont dans le paquet, comme les
        // 604 pages du Coran de Médine. Un appui la sélectionne donc, installé
        // ou non.
        for installed in [true, false] {
            XCTAssertEqual(
                QuranDisplayOptions.choice(for: .tajweed, coran1441Installed: installed),
                .select,
                "« tajweed » doit être sélectionnable, installé ou non."
            )
        }
    }

    /// Le refus nomme l'édition refusée — l'ancien `QuranScreenView` disait la
    /// même chose avec sa propre chaîne ; elle est désormais dans le modèle.
    ///
    /// « Lecture simplifiée » n'est plus refusée : elle a quitté cette liste en
    /// même temps que la précédente, et pour la même raison.
    func testTheRefusalNamesTheEdition() {
        for edition in [QuranEdition.coranTest, .tajweedPages] {
            let notice = QuranDisplayOptions.unavailableNotice(for: edition)
            XCTAssertTrue(notice.hasPrefix(edition.label), "Le refus doit nommer « \(edition.label) ».")
        }
    }

    /// L'état d'installation n'existe que pour le Coran 1441 : les autres
    /// éditions ne s'installent pas.
    func testOnlyTheCoran1441HasAnInstallationStatus() {
        XCTAssertEqual(
            QuranDisplayOptions.installationStatus(for: .coran1441, coran1441Installed: true),
            "Installé"
        )
        XCTAssertEqual(
            QuranDisplayOptions.installationStatus(for: .coran1441, coran1441Installed: false),
            "À installer"
        )
        for edition in QuranEdition.allCases where edition != .coran1441 {
            XCTAssertNil(
                QuranDisplayOptions.installationStatus(for: edition, coran1441Installed: false),
                "« \(edition.rawValue) » ne s'installe pas, il n'a pas d'état."
            )
        }
    }

    // MARK: - Les quatre fonds

    /// Les clés, les libellés et les couleurs — `readerAppearance.ts:2-5`.
    func testTheFourPapersAreTheOnesOfTheReference() {
        XCTAssertEqual(QuranDisplayOptions.paperOptions.map(\.id), ["ivory", "rose", "sand", "sepia"])
        XCTAssertEqual(QuranDisplayOptions.paperOptions.map(\.label), ["Ivoire", "Rosé", "Sable", "Sépia"])
        XCTAssertEqual(
            QuranDisplayOptions.paperOptions.map(\.hex),
            ["#faf7f2", "#f5e1e7", "#e8dcc8", "#d7c5ad"]
        )
    }

    /// La couleur d'un fond est bien celle que porte sa chaîne, et les quatre
    /// sont distinctes.
    ///
    /// Le second point compte : deux fonds de même couleur donneraient deux
    /// pastilles indiscernables, et le choix serait impossible à faire à l'œil.
    func testEveryPaperColourIsItsHexAndTheFourAreDistinct() {
        var seen: [Color] = []
        for option in QuranDisplayOptions.paperOptions {
            XCTAssertEqual(
                option.color,
                Theme.color(hexString: option.hex),
                "La couleur de « \(option.id) » ne correspond pas à « \(option.hex) »."
            )
            XCTAssertFalse(seen.contains(option.color), "Deux fonds partagent la même couleur.")
            seen.append(option.color)
        }
        XCTAssertEqual(seen.count, 4)
    }

    /// La clé retenue quand rien n'est stocké, et le repli sur le PREMIER fond.
    ///
    /// `quranPaperColor` fait `find(...) ?? quranPaperOptions[0]` : un fond
    /// inconnu prend la couleur d'Ivoire, pas celle du thème.
    func testAnUnknownPaperFallsBackToTheFirstOne() throws {
        XCTAssertEqual(QuranDisplayOptions.defaultPaperKey, "ivory")
        XCTAssertEqual(QuranDisplayOptions.selectedPaper(stored: nil), "ivory")
        XCTAssertEqual(QuranDisplayOptions.selectedPaper(stored: "sepia"), "sepia")

        let first = try XCTUnwrap(QuranDisplayOptions.paperOptions.first)
        XCTAssertEqual(first.id, QuranDisplayOptions.defaultPaperKey)
        for unknown in [nil, "", "inconnu", "IVORY"] {
            XCTAssertEqual(
                QuranDisplayOptions.paperColor(key: unknown),
                first.color,
                "Le repli de « \(unknown ?? "aucun") » doit être la couleur du premier fond."
            )
        }
        XCTAssertEqual(QuranDisplayOptions.paperColor(key: "sepia"), QuranDisplayOptions.paperOptions[3].color)
    }

    /// Les mesures et la couleur du libellé — `App.tsx:330`.
    func testThePaperMetricsAreTheOnesOfTheReference() {
        XCTAssertEqual(QuranDisplayOptions.Paper.widthFraction, 0.47)
        XCTAssertEqual(QuranDisplayOptions.Paper.minHeight, 58)
        XCTAssertEqual(QuranDisplayOptions.Paper.cornerRadius, 14)
        XCTAssertEqual(QuranDisplayOptions.Paper.padding, 12)
        XCTAssertEqual(QuranDisplayOptions.Paper.selectedBorderWidth, 2)
        XCTAssertEqual(QuranDisplayOptions.Paper.borderWidth, 1)
        XCTAssertEqual(QuranDisplayOptions.Paper.checkmark, "✓")

        XCTAssertEqual(QuranDisplayOptions.paperLabelHex, "#342a27")
        XCTAssertEqual(QuranDisplayOptions.paperLabelColor, Theme.color(hexString: "#342a27"))
    }

    /// Les textes de la carte — `App.tsx:330`.
    func testTheCardTextsAreTheOnesOfTheReference() {
        XCTAssertEqual(QuranDisplayOptions.cardTitle, "Affichage du Coran")
        XCTAssertEqual(QuranDisplayOptions.cardDetail, "Choisis la présentation arabe des pages.")
        XCTAssertEqual(QuranDisplayOptions.paperSectionTitle, "Fond du Coran avec règles de Tajwid")
        XCTAssertEqual(
            QuranDisplayOptions.followAudioLabel,
            "Suivre automatiquement la récitation sur la page suivante"
        )
    }

    // MARK: - Le lecteur hexadécimal

    /// `Theme.color(hexString:)` lit la forme écrite par l'original, avec ou
    /// sans `#`, dans les deux casses.
    func testTheHexParserReadsTheFormOfTheReference() {
        XCTAssertEqual(Theme.color(hexString: "#faf7f2"), QuranDisplayOptions.paperOptions[0].color)
        XCTAssertEqual(Theme.color(hexString: "faf7f2"), QuranDisplayOptions.paperOptions[0].color)
        XCTAssertEqual(Theme.color(hexString: "#FAF7F2"), QuranDisplayOptions.paperOptions[0].color)
        XCTAssertEqual(Theme.color(hexString: "#ffffff"), Theme.white.paper)
        XCTAssertEqual(Theme.color(hexString: "#000000"), Color(red: 0, green: 0, blue: 0))
    }

    /// Une chaîne qui n'est pas six chiffres hexadécimaux n'a PAS de couleur :
    /// rendre du noir ferait passer une faute de frappe pour un choix.
    func testTheHexParserRefusesWhatIsNotASixDigitColour() {
        for bad in ["", "#", "zzz", "#12345", "#1234567", "#gggggg", "faf7f2 ", " #faf7f2"] {
            XCTAssertNil(Theme.color(hexString: bad), "« \(bad) » ne doit pas produire de couleur.")
        }
    }

    // MARK: - Les règles d'écriture

    /// L'écriture d'une édition : le `mushaf` choisi, et `followAudio` conservé.
    func testSettingAnEditionWritesTheChosenValue() {
        var state = Program.defaultState()
        state.reader = ReaderPreferences(mushaf: "traditional", followAudio: false)

        let next = QuranDisplayOptions.settingEdition(state, .coran1441)
        XCTAssertEqual(next.reader?.mushaf, "coran_1441")
        XCTAssertEqual(next.reader?.followAudio, false, "Un `false` stocké doit survivre au choix d'édition.")
    }

    /// Sans lecteur, l'écriture d'une édition en crée un — avec l'édition
    /// choisie et le suivi audio actif par défaut.
    func testSettingAnEditionCreatesAReaderWhenThereIsNone() {
        var state = Program.defaultState()
        state.reader = nil

        let next = QuranDisplayOptions.settingEdition(state, .medine)
        XCTAssertEqual(next.reader?.mushaf, "traditional")
        XCTAssertEqual(next.reader?.followAudio, true, "`undefined !== false` vaut `true`.")
    }

    /// Les autres clés du lecteur survivent : l'original étale `state.reader`,
    /// il ne le remplace pas.
    func testTheOtherReaderKeysSurviveAnEditionChange() {
        var state = Program.defaultState()
        var preferences = ReaderPreferences(mushaf: "traditional", followAudio: true)
        preferences.testPage = 42
        preferences.paper = "sand"
        state.reader = preferences

        let next = QuranDisplayOptions.settingEdition(state, .coran1441)
        XCTAssertEqual(next.reader?.testPage, 42)
        XCTAssertEqual(next.reader?.paper, "sand")
    }

    /// Le fond : `mushaf` est CONSERVÉ s'il existe, et posé à `coranTest`
    /// seulement s'il n'y a pas encore de lecteur.
    ///
    /// C'est le contrat de `App.tsx:330` — `mushaf: state.reader?.mushaf ??
    /// 'coranTest'`. Surprenant, mais c'est ce que l'application React Native
    /// relira : l'écrire autrement ferait diverger les deux documents.
    func testSettingAPaperKeepsTheMushafAndOnlyCreatesOneWhenMissing() {
        var state = Program.defaultState()
        var existing = ReaderPreferences(mushaf: "traditional", followAudio: false)
        existing.testPage = 7
        state.reader = existing
        let withReader = QuranDisplayOptions.settingPaper(state, "sepia")
        XCTAssertEqual(withReader.reader?.mushaf, "traditional", "Le choix du fond ne change pas l'édition.")
        XCTAssertEqual(withReader.reader?.followAudio, false)
        XCTAssertEqual(withReader.reader?.testPage, 7)
        XCTAssertEqual(withReader.reader?.paper, "sepia")

        state.reader = nil
        let withoutReader = QuranDisplayOptions.settingPaper(state, "sepia")
        XCTAssertEqual(
            withoutReader.reader?.mushaf,
            QuranDisplayOptions.defaultMushafWhenReaderIsMissing
        )
        XCTAssertEqual(withoutReader.reader?.followAudio, true)
        XCTAssertEqual(withoutReader.reader?.paper, "sepia")
    }

    /// Le suivi audio : la valeur est écrite TELLE QUELLE — c'est la seule des
    /// trois écritures qui puisse poser `false` sur un lecteur neuf.
    func testSettingFollowAudioWritesTheValueAsGiven() {
        var state = Program.defaultState()
        state.reader = ReaderPreferences(mushaf: "traditional", followAudio: true)

        XCTAssertEqual(QuranDisplayOptions.settingFollowAudio(state, false).reader?.followAudio, false)
        XCTAssertEqual(QuranDisplayOptions.settingFollowAudio(state, true).reader?.followAudio, true)

        state.reader = nil
        let created = QuranDisplayOptions.settingFollowAudio(state, false)
        XCTAssertEqual(created.reader?.followAudio, false)
        XCTAssertEqual(created.reader?.mushaf, QuranDisplayOptions.defaultMushafWhenReaderIsMissing)
    }

    /// Aucune des trois règles ne touche `updatedAt`.
    ///
    /// C'est délibéré : l'original enveloppe ses trois écritures dans `touch`
    /// (`App.tsx:330`), mais dans ce portage **toute** écriture passe par
    /// `AppStateRepository.mutate`, qui applique `Program.touch`
    /// (`Repositories/AppStateRepository.swift:113`). Le refaire ici serait un
    /// second horodatage sur le même document. Ce test fige la décision : si
    /// quelqu'un ajoute un `touch` dans une règle, il échoue.
    func testTheWriteRulesDoNotStampTheDocumentThemselves() {
        let state = Program.defaultState()
        let stamp = state.updatedAt

        XCTAssertEqual(QuranDisplayOptions.settingEdition(state, .coran1441).updatedAt, stamp)
        XCTAssertEqual(QuranDisplayOptions.settingPaper(state, "sand").updatedAt, stamp)
        XCTAssertEqual(QuranDisplayOptions.settingFollowAudio(state, false).updatedAt, stamp)
    }

    /// Les trois règles ne touchent à rien d'autre qu'au lecteur.
    ///
    /// Une règle qui écraserait `knowledge`, `goal` ou `sessions` ferait
    /// disparaître un apprentissage en changeant un fond.
    func testTheWriteRulesLeaveTheRestOfTheDocumentAlone() {
        var state = Program.defaultState()
        state.knowledge = ["1": .perfect, "2": .learning]
        state.lastRead = LastRead(page: 12, verseId: 3, readAt: "2026-01-01T00:00:00.000Z")

        for next in [
            QuranDisplayOptions.settingEdition(state, .medine),
            QuranDisplayOptions.settingPaper(state, "rose"),
            QuranDisplayOptions.settingFollowAudio(state, false)
        ] {
            XCTAssertEqual(next.knowledge, state.knowledge)
            XCTAssertEqual(next.goal, state.goal)
            XCTAssertEqual(next.sessions, state.sessions)
            XCTAssertEqual(next.lastRead, state.lastRead)
        }
    }

    // MARK: - Cohérence avec le lecteur

    /// Une préférence écrite par cette carte est relue par le lecteur : les
    /// quatre clés proposées sont des `QuranEdition` que `displayed(stored:)`
    /// sait résoudre.
    ///
    /// Les **deux** éditions non disponibles retombent sur le Coran de Médine —
    /// c'est le repli voulu, et il n'est pas une réécriture de la préférence.
    /// Elles étaient trois : « Lecture simplifiée » est lisible depuis que son
    /// rendu existe, et elle se résout maintenant en **elle-même**.
    func testEveryProposedKeyIsUnderstoodByTheReader() {
        for key in QuranDisplayOptions.editionKeys {
            let resolved = QuranEdition.displayed(stored: key)
            XCTAssertTrue(resolved.isAvailable, "« \(key) » doit se résoudre en une édition lisible.")
        }
        // Les deux que cette version ne sait pas rendre retombent sur Médine,
        // et la préférence stockée, elle, reste intacte.
        for key in ["coranTest", "tajweedPages"] {
            XCTAssertEqual(QuranEdition.displayed(stored: key), QuranEdition.fallback)
            XCTAssertNotEqual(key, QuranEdition.fallback.rawValue)
        }
        // Celle qui est lisible se résout en elle-même : c'est ce qui la rend
        // atteignable par le lecteur, et donc rendable.
        XCTAssertEqual(QuranEdition.displayed(stored: "tajweed"), .tajweed)
    }
}

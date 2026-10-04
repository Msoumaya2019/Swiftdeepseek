// AppearanceTests.swift
// L'apparence : les thèmes et les couleurs d'accent.
//
// Ce que ces tests protègent :
//   - l'ordre d'affichage des thèmes, qui n'est PAS celui de `themeOptions` :
//     l'écran montre blanc, rose, vert (`DesignSystem.tsx:17`). Inverser le vert
//     et le rose ne casse rien, ne prévient de rien, et se voit à l'œil seulement
//     si l'on connaît l'original ;
//   - l'ordre des accents, qui vient d'un `Object.keys` : un dictionnaire Swift
//     n'a pas d'ordre, donc l'ordre est une donnée — et une donnée se teste ;
//   - la PASTILLE de chaque accent, qui n'est pas sa couleur appliquée : trois
//     des quatre accents portent une pastille plus claire. Les confondre donne un
//     sélecteur faux pour trois accents sur quatre, et le code compile ;
//   - le sous-titre de la ligne « Apparence », où le séparateur est un point
//     médian (U+00B7) et l'apostrophe une apostrophe typographique (U+2019) ;
//   - le repli d'un thème inconnu : la palette retombe sur « white » et le nom
//     disparaît, au lieu d'un nom inventé.
//
// CE QUE CES TESTS NE PEUVENT PAS PROUVER, ET QUI EST PROUVÉ AILLEURS
//   L'égalité littérale de ces tables avec celles de la référence se compare à
//   la source TypeScript, pas au Swift : c'est le rôle de
//   `_banc/verifier-apparence.mjs`, qui lit les deux et exige l'accord
//   caractère par caractère (63 contrôles, falsifiés par 24 mutations).
//
//   `AppViewModel.palette` — l'endroit où l'accent est réellement APPLIQUÉ à la
//   palette — n'est pas testé ici : `state` est `private(set)`, et le poser
//   demanderait de passer par `update`, qui écrit dans un `Task` et ne rend pas
//   la main. Les tests ci-dessous éprouvent donc le modèle pur, et les FAITS qui
//   rendent l'asymétrie d'`applyTheme` visible.
//
// Aucun nombre de ce fichier n'est inventé : les ordres attendus sont dérivés de
// `Theme.themeOptions` et de `Theme.accentOrder`, jamais recopiés.

import XCTest
@testable import Swiftdeepseek

final class AppearanceTests: XCTestCase {

    // MARK: - Les cinq thèmes

    /// Les identifiants, les noms et les descriptions — `src/ui/theme.tsx:19-25`.
    func testTheFiveThemesAreTheOnesOfTheReference() {
        XCTAssertEqual(Theme.themeOptions.map(\.id), ["white", "classic", "feminine", "lilac", "night"])
        XCTAssertEqual(Theme.themeOptions.map(\.name), [
            "Thème blanc", "Thème vert", "Thème rose", "Lilas & Perle", "Bleu Nuit & Or"
        ])
        XCTAssertEqual(Theme.themeOptions.map(\.description), [
            "Simple et épuré", "Serein et naturel", "Doux et moderne",
            "Délicat et raffiné", "Sobre et élégant"
        ])
    }

    /// L'ordre d'affichage est une DÉRIVATION par indices, pas une recopie :
    /// `[themeOptions[0], themeOptions[2], themeOptions[1]]`.
    ///
    /// Le test refait la dérivation sur la table réelle. Recopier la liste
    /// littérale et la comparer à elle-même ne prouverait rien.
    func testTheDisplayedOrderIsDerivedFromTheTableAndDiffersFromIt() {
        let table = Theme.themeOptions
        let derived = [table[0].id, table[2].id, table[1].id]

        XCTAssertEqual(AppearanceOptions.primaryThemeKeys, derived)
        XCTAssertEqual(AppearanceOptions.primaryThemeKeys, ["white", "feminine", "classic"])

        // Si les deux ordres coïncidaient, le test ci-dessus serait indiscernable
        // d'une simple recopie de la table — et ne prouverait donc rien.
        XCTAssertNotEqual(
            AppearanceOptions.primaryThemeKeys,
            Array(table.prefix(3).map(\.id)),
            "L'ordre affiché doit différer de l'ordre de la table, sinon rien n'est prouvé."
        )
    }

    /// Les thèmes supplémentaires sont `themeOptions.slice(3)` — les deux
    /// derniers, dans l'ordre de la table.
    func testTheExtraThemesAreTheLastOnesOfTheTable() {
        XCTAssertEqual(AppearanceOptions.extraThemeKeys, ["lilac", "night"])
        XCTAssertEqual(AppearanceOptions.extraThemeKeys, Array(Theme.themeOptions.dropFirst(3).map(\.id)))
    }

    /// La liste affichée : trois thèmes, puis cinq quand la bascule est ouverte.
    func testTheDisplayedListGrowsFromThreeToFive() {
        let closed = AppearanceOptions.themes(showingExtras: false)
        let open = AppearanceOptions.themes(showingExtras: true)

        XCTAssertEqual(closed.count, 3)
        XCTAssertEqual(open.count, 5)
        XCTAssertEqual(closed.map(\.id), AppearanceOptions.primaryThemeKeys)
        XCTAssertEqual(open.map(\.id), AppearanceOptions.primaryThemeKeys + AppearanceOptions.extraThemeKeys)
    }

    /// Aucune clé affichée n'est orpheline : chaque thème de la liste existe dans
    /// la table, avec un nom et une description non vides.
    ///
    /// Une clé qui ne correspondrait à aucune entrée disparaîtrait de l'écran sans
    /// que rien ne le signale — la carte serait simplement absente.
    func testEveryDisplayedThemeExistsWithANameAndADescription() {
        for option in AppearanceOptions.themes(showingExtras: true) {
            XCTAssertFalse(option.name.isEmpty, "nom manquant pour « \(option.id) »")
            XCTAssertFalse(option.description.isEmpty, "description manquante pour « \(option.id) »")
        }
        XCTAssertEqual(
            AppearanceOptions.themeKeys(showingExtras: true).count,
            Set(AppearanceOptions.themeKeys(showingExtras: true)).count,
            "Un thème est listé deux fois : il apparaîtrait deux fois à l'écran."
        )
    }

    // MARK: - La bascule des thèmes supplémentaires

    /// `useState(theme === 'lilac' || theme === 'night')` : la bascule est
    /// ouverte d'emblée sur les thèmes qu'elle replie — sans quoi un utilisateur
    /// de « Lilas & Perle » ne verrait pas sa propre carte.
    func testTheToggleOpensOnExactlyTheThemesItFolds() {
        for key in AppearanceOptions.extraThemeKeys {
            XCTAssertTrue(
                AppearanceOptions.extrasShownByDefault(for: key),
                "« \(key) » est replié mais la bascule ne s'ouvre pas sur lui."
            )
        }
        for key in AppearanceOptions.primaryThemeKeys {
            XCTAssertFalse(AppearanceOptions.extrasShownByDefault(for: key), "« \(key) » n'est pas replié.")
        }
        // Un thème absent ou inconnu : bascule fermée, comme dans l'original.
        XCTAssertFalse(AppearanceOptions.extrasShownByDefault(for: nil))
        XCTAssertFalse(AppearanceOptions.extrasShownByDefault(for: "inconnu"))
    }

    /// Les deux libellés de la bascule — `DesignSystem.tsx:17`.
    func testTheToggleLabelsAreTheTwoOfTheReference() {
        XCTAssertEqual(AppearanceOptions.extrasToggleLabel(showingExtras: false), "Autres thèmes existants")
        XCTAssertEqual(AppearanceOptions.extrasToggleLabel(showingExtras: true), "Réduire")
    }

    // MARK: - Les quatre accents

    /// L'ordre d'insertion de `accents`, que `Object.keys` restitue et qu'un
    /// dictionnaire Swift ne garantit pas — `src/theme/tokens.ts:5-10`.
    func testTheFourAccentsAreInTheInsertionOrderOfTheReference() {
        XCTAssertEqual(Theme.accentOrder, ["prune", "rose", "green", "gold"])
        XCTAssertEqual(AppearanceOptions.accentOptions.map(\.id), Theme.accentOrder)
    }

    /// Aucun accent n'est perdu ni dupliqué entre la liste ordonnée et le
    /// dictionnaire : une clé de `accentOrder` absente du dictionnaire
    /// disparaîtrait du sélecteur, et un accent du dictionnaire absent de la
    /// liste ne serait jamais affiché.
    func testTheOrderedListAndTheDictionaryAgree() {
        XCTAssertEqual(AppearanceOptions.accentOptions.count, 4)
        XCTAssertEqual(Set(AppearanceOptions.accentOptions.map(\.id)), Set(Theme.accents.keys))
        for option in AppearanceOptions.accentOptions {
            XCTAssertNotNil(Theme.accents[option.id], "« \(option.id) » est listé mais absent du dictionnaire.")
        }
    }

    /// Les libellés — `tokens.ts:6-9`.
    func testTheAccentLabelsAreTheOnesOfTheReference() {
        XCTAssertEqual(AppearanceOptions.accentOptions.map(\.label), ["Prune", "Rose", "Vert", "Doré"])
    }

    /// La pastille n'est pas la couleur appliquée : trois des quatre accents
    /// diffèrent, et « prune » est le seul où les deux coïncident.
    ///
    /// C'est ce qui rend le champ `swatch` nécessaire. S'il était égal à
    /// `primary` partout, le sélecteur serait juste par accident et ce test ne
    /// prouverait rien — d'où le compte exact.
    func testThreeAccentsCarryASwatchDifferentFromTheirAppliedColour() throws {
        // On parcourt la liste ORDONNÉE, pas le dictionnaire : l'ordre du
        // dictionnaire est arbitraire, et `XCTAssertEqual` sur un tableau trié
        // par accident ne dirait pas la même chose. Un accent manquant doit
        // ÉCHOUER, pas être silencieusement ignoré — d'où `XCTUnwrap` hors d'une
        // fermeture non-`throws`, où `try?` rendrait un optionnel d'optionnel.
        var divergents: [String] = []
        for key in Theme.accentOrder {
            let accent = try XCTUnwrap(Theme.accents[key], "accent manquant : \(key)")
            if accent.swatch != accent.primary { divergents.append(key) }
        }
        XCTAssertEqual(divergents, ["rose", "green", "gold"])
        XCTAssertEqual(divergents.count, 3)

        // « Prune » : les deux coïncident, et c'est aussi le vert de la palette
        // blanche — c'est pourquoi le thème blanc « fonctionne » sans accent.
        let prune = try XCTUnwrap(Theme.accents["prune"])
        XCTAssertEqual(prune.swatch, prune.primary)
        XCTAssertEqual(Theme.white.green, prune.primary)
    }

    // MARK: - L'accent actif et l'accent affiché

    /// `activeAccent = accent ?? (classic → green, feminine → rose, sinon prune)`.
    func testTheActiveAccentFollowsTheTheme() {
        XCTAssertEqual(AppearanceOptions.activeAccent(for: "classic"), "green")
        XCTAssertEqual(AppearanceOptions.activeAccent(for: "feminine"), "rose")
        for other in ["white", "lilac", "night", nil, "inconnu"] {
            XCTAssertEqual(
                AppearanceOptions.activeAccent(for: other),
                "prune",
                "Le repli de « \(other ?? "aucun") » doit être « prune »."
            )
        }
    }

    /// `state.accent ?? accent` : l'accent stocké l'emporte ; sinon il se déduit
    /// du thème.
    func testTheStoredAccentWinsOverTheDerivedOne() {
        XCTAssertEqual(AppearanceOptions.displayedAccent(stored: "gold", theme: "classic"), "gold")
        XCTAssertEqual(AppearanceOptions.displayedAccent(stored: nil, theme: "classic"), "green")
        XCTAssertEqual(AppearanceOptions.displayedAccent(stored: nil, theme: "feminine"), "rose")
        XCTAssertEqual(AppearanceOptions.displayedAccent(stored: nil, theme: nil), "prune")
    }

    /// Le rond coché n'est pas toujours la couleur appliquée — l'asymétrie
    /// d'`applyTheme`, qui n'écrase la palette que si l'accent est donné ou si le
    /// thème est blanc (`src/ui/theme.tsx:17`).
    ///
    /// Concrètement : le thème « vert » coche l'accent « Vert » sans que sa
    /// palette devienne celle de cet accent, parce que le vert du thème vert
    /// (`#153F36`) n'est pas le vert de l'accent (`#54734E`). Un lecteur qui
    /// suppose l'inverse se trompe.
    func testTheCheckedAccentIsNotAlwaysTheAppliedOne() throws {
        let themeGreen = Theme.classic.green
        let accentGreen = try XCTUnwrap(Theme.accents["green"]).primary
        XCTAssertNotEqual(themeGreen, accentGreen, "Sans écart, l'asymétrie ne serait pas observable.")

        let themeRose = Theme.feminine.green
        let accentRose = try XCTUnwrap(Theme.accents["rose"]).primary
        XCTAssertNotEqual(themeRose, accentRose)
    }

    // MARK: - Le sous-titre de la carte

    /// Le nom affiché — `themeOptions.find(t => t.key === (state.theme ?? 'white'))?.name`.
    func testTheThemeNameFallsBackToWhite() {
        XCTAssertEqual(AppearanceOptions.themeName(for: "white"), "Thème blanc")
        XCTAssertEqual(AppearanceOptions.themeName(for: "classic"), "Thème vert")
        XCTAssertEqual(AppearanceOptions.themeName(for: "night"), "Bleu Nuit & Or")
        // `state.theme ?? 'white'` : un thème absent vaut le thème blanc.
        XCTAssertEqual(AppearanceOptions.themeName(for: nil), "Thème blanc")
    }

    /// Un thème inconnu ne rend AUCUN nom — `?.name` rend `undefined`, et JSX
    /// n'affiche alors rien. Inventer un nom serait plus grave que l'absence.
    func testAnUnknownThemeHasNoName() {
        XCTAssertEqual(AppearanceOptions.themeName(for: "inconnu"), "")
        XCTAssertEqual(AppearanceOptions.themeName(for: ""), "")
    }

    /// Le sous-titre, caractère par caractère — `src/App.tsx:329`.
    ///
    /// Le séparateur est ` · ` (point médian U+00B7 entouré d'espaces) et
    /// l'apostrophe de `d’accent` est typographique (U+2019). Une apostrophe
    /// droite passerait inaperçue à la lecture et serait fausse.
    func testTheCardDetailIsTheOneOfTheReference() {
        let detail = AppearanceOptions.cardDetail(for: "white")
        XCTAssertEqual(detail, "Thème blanc · couleur d’accent")
        XCTAssertTrue(detail.contains("\u{00B7}"), "Le séparateur doit être un point médian (U+00B7).")
        XCTAssertTrue(detail.contains("\u{2019}"), "L'apostrophe de « d’accent » doit être typographique (U+2019).")
        XCTAssertFalse(detail.contains("'"), "Aucune apostrophe droite ne doit apparaître.")
        XCTAssertFalse(detail.contains(" - "), "Le séparateur n'est pas un tiret.")
    }

    /// Un thème inconnu : le sous-titre perd le nom mais garde le reste, comme
    /// `undefined · couleur d’accent` dans l'original.
    func testTheCardDetailOfAnUnknownThemeOmitsTheName() {
        XCTAssertEqual(AppearanceOptions.cardDetail(for: "inconnu"), " · couleur d’accent")
        XCTAssertEqual(AppearanceOptions.cardDetail(for: nil), "Thème blanc · couleur d’accent")
    }

    // MARK: - Les palettes

    /// Un thème inconnu retombe sur la palette blanche — `palette(named:)`,
    /// qui reproduit le `if (!(theme in palettes)) theme = 'white'` d'`applyTheme`.
    func testAnUnknownThemeFallsBackToTheWhitePalette() {
        XCTAssertEqual(Theme.palette(named: "inconnu"), Theme.white)
        XCTAssertEqual(Theme.palette(named: nil), Theme.white)
        XCTAssertEqual(Theme.palette(named: ""), Theme.white)
        XCTAssertEqual(Theme.palette(named: "classic"), Theme.classic)
        XCTAssertEqual(Theme.palette(named: "night"), Theme.night)
    }

    /// Les cinq palettes sont distinctes : une copie laissée en place donnerait
    /// deux thèmes identiques, ce qui se verrait à l'usage et jamais au test.
    func testTheFivePalettesAreDistinct() {
        let palettes = [
            Theme.white, Theme.classic, Theme.feminine, Theme.lilac, Theme.night
        ]
        for i in palettes.indices {
            for j in palettes.indices where j > i {
                XCTAssertNotEqual(palettes[i], palettes[j], "Les palettes \(i) et \(j) sont identiques.")
            }
        }
    }
}

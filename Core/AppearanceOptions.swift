// AppearanceOptions.swift
// L'apparence — les thèmes et les couleurs d'accent.
//
// Correspondance : `src/ui/theme.tsx` (`themeOptions`, `applyTheme`) et
// `src/ui/DesignSystem.tsx` (`ThemeSelector`, `AccentSelector`), réunis par
// `src/ui/AppearanceScreen.tsx` et atteints par la carte « Apparence » de
// `src/App.tsx:329`.
//
// POURQUOI CE FICHIER
//   `Features/Settings/SettingsView.swift` énonce la règle du dossier : un
//   écran ne calcule rien. Or l'apparence porte quatre décisions qui, si elles
//   vivaient dans la vue, divergeraient en silence :
//
//     1. l'ordre d'affichage des thèmes n'est PAS l'ordre de la table. L'original
//        écrit `[themeOptions[0], themeOptions[2], themeOptions[1]]`
//        (`DesignSystem.tsx:17`) : blanc, rose, vert — le vert passe derrière le
//        rose alors qu'il le précède dans `themeOptions` ;
//     2. deux thèmes sont repliés derrière une bascule, et cette bascule est
//        ouverte d'emblée si le thème stocké est l'un des deux ;
//     3. les accents sont parcourus par `Object.keys`, donc dans l'ordre
//        d'insertion de l'objet : prune, rose, vert, doré. Un dictionnaire Swift
//        ne garantit aucun ordre ;
//     4. l'accent AFFICHÉ n'est pas l'accent stocké : à défaut, il se déduit du
//        thème (`classic` → vert, `feminine` → rose, sinon prune).
//
//   Ces quatre-là vivent ici, et la vue les lit. Un écran qui recopie une liste
//   ou un ordre diverge sans que rien ne le signale.

import SwiftUI

public enum AppearanceOptions {

    // MARK: - Ordre d'affichage des thèmes

    /// Les trois thèmes montrés d'emblée — `DesignSystem.tsx:17`.
    ///
    /// L'expression de l'original est `[themeOptions[0], themeOptions[2],
    /// themeOptions[1]]`. Le banc vérifie que cette liste littérale **est** cette
    /// dérivation : recopier le résultat sans le vérifier laisserait passer une
    /// inversion, et le vert et le rose se ressemblent assez peu pour qu'on s'en
    /// aperçoive tard.
    public static let primaryThemeKeys: [String] = ["white", "feminine", "classic"]

    /// Les deux thèmes repliés derrière la bascule — `themeOptions.slice(3)`.
    public static let extraThemeKeys: [String] = ["lilac", "night"]

    /// `useState(theme === 'lilac' || theme === 'night')` : la bascule est
    /// ouverte d'emblée si le thème stocké fait partie des thèmes
    /// supplémentaires. Sans quoi un utilisateur du thème « Lilas & Perle »
    /// verrait sa propre carte cachée.
    public static func extrasShownByDefault(for theme: String?) -> Bool {
        theme == "lilac" || theme == "night"
    }

    /// Les clés des thèmes à afficher, dans l'ordre.
    public static func themeKeys(showingExtras: Bool) -> [String] {
        showingExtras ? primaryThemeKeys + extraThemeKeys : primaryThemeKeys
    }

    /// Les thèmes à afficher, dans l'ordre, avec leur nom et leur description.
    ///
    /// Les noms et les descriptions viennent de `Theme.themeOptions` — la vue ne
    /// les écrit pas.
    public static func themes(showingExtras: Bool) -> [Theme.ThemeOption] {
        themeKeys(showingExtras: showingExtras).compactMap { key in
            Theme.themeOptions.first { $0.id == key }
        }
    }

    /// Le libellé de la bascule — `DesignSystem.tsx:17`.
    public static func extrasToggleLabel(showingExtras: Bool) -> String {
        showingExtras ? "Réduire" : "Autres thèmes existants"
    }

    // MARK: - Accents

    /// Un accent tel que le sélecteur l'affiche : une clé, un libellé, et la
    /// pastille.
    ///
    /// `swatch` est indispensable : c'est **la seule** chose qui distingue
    /// visuellement les quatre ronds (`DesignSystem.tsx:18`). Un accent réduit à
    /// son libellé donnerait quatre cercles de la même couleur.
    public struct AccentOption: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var swatch: Color
    }

    /// Les quatre accents dans l'ordre d'insertion de `accents`
    /// (`src/theme/tokens.ts:5-10`), que `AccentSelector` parcourt par
    /// `Object.keys` (`DesignSystem.tsx:18`).
    public static var accentOptions: [AccentOption] {
        Theme.accentOrder.compactMap { key in
            guard let accent = Theme.accents[key] else { return nil }
            return AccentOption(id: key, label: accent.label, swatch: accent.swatch)
        }
    }

    // MARK: - L'accent affiché

    /// `activeAccent` — `applyTheme`, `src/ui/theme.tsx:17`.
    ///
    /// C'est le repli par défaut : quand aucun accent n'est stocké, le thème
    /// décide lequel est coché.
    public static func activeAccent(for theme: String?) -> String {
        switch theme {
        case "classic": return "green"
        case "feminine": return "rose"
        default: return "prune"
        }
    }

    /// L'accent **affiché** : `state.accent ?? accent` (`AppearanceScreen.tsx:6`).
    ///
    /// À ne pas confondre avec l'accent **appliqué** à la palette, qui suit une
    /// autre règle : `applyTheme` n'écrase les couleurs que si l'accent est donné
    /// **ou** si le thème est blanc (`src/ui/theme.tsx:17`), et
    /// `AppViewModel.palette` reproduit cette asymétrie. Ici on ne décide que du
    /// rond coché — un thème « vert » peut donc être coché « Vert » sans que la
    /// palette soit pour autant réécrite par l'accent.
    public static func displayedAccent(stored: String?, theme: String?) -> String {
        stored ?? activeAccent(for: theme)
    }

    // MARK: - Le sous-titre de la carte

    /// Le nom affiché d'un thème — `themeOptions.find(t => t.key === (state.theme
    /// ?? 'white'))?.name`, `src/App.tsx:329`.
    ///
    /// Un thème inconnu rend la chaîne vide, exactement comme `?.name` rend
    /// `undefined` : l'original affiche alors « · couleur d'accent », sans nom.
    /// Ce n'est pas un cas d'école — une version plus ancienne de l'application
    /// peut avoir stocké une clé que celle-ci ne connaît plus, et il vaut mieux
    /// un sous-titre amputé qu'un nom inventé.
    public static func themeName(for theme: String?) -> String {
        let key = theme ?? "white"
        return Theme.themeOptions.first { $0.id == key }?.name ?? ""
    }

    /// Le sous-titre de la ligne « Apparence » — `src/App.tsx:329` :
    ///
    ///     {themeOptions.find(t => t.key === (state.theme ?? 'white'))?.name} ·
    ///     couleur d’accent
    ///
    /// Les deux caractères comptent : le séparateur est ` · ` (point médian
    /// U+00B7 entouré d'espaces) et l'apostrophe de `d’accent` est typographique
    /// (U+2019). Le banc compare la chaîne entière.
    public static func cardDetail(for theme: String?) -> String {
        "\(themeName(for: theme)) · couleur d’accent"
    }
}

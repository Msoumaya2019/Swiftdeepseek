// Theme.swift
// Jetons de design portés depuis `src/theme/tokens.ts` et `src/ui/theme.tsx`.
//
// Les cinq thèmes et les quatre accents sont ceux de l'application actuelle, avec
// les mêmes codes couleur : l'utilisateur doit retrouver son apparence. Une
// palette est choisie par `reader`/`theme` dans l'état synchronisé, donc le thème
// choisi dans React Native s'applique aussi ici.

import SwiftUI

public struct Palette: Equatable, Sendable {
    public var green: Color
    public var green2: Color
    public var cream: Color
    public var paper: Color
    public var beige: Color
    public var gold: Color
    public var text: Color
    public var muted: Color
    public var line: Color
    public var red: Color
    public var soft: Color
    public var softBorder: Color
    public var selected: Color
    public var track: Color
    public var progress: Color
    public var surahBadge: Color
}

private func hex(_ value: UInt32) -> Color {
    Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
    )
}

public enum Theme {

    // MARK: Couleurs écrites en hexadécimal

    /// Lit une couleur `#rrggbb` telle que l'original l'écrit dans ses tables.
    ///
    /// POURQUOI CETTE FONCTION
    ///   Les palettes de ce fichier portent leurs couleurs en `UInt32`
    ///   (`hex(0x7B285C)`), ce qui suffit pour des constantes écrites ici. Mais
    ///   deux tables de l'original donnent leurs couleurs sous forme de
    ///   **chaînes** — les quatre fonds du Coran
    ///   (`src/core/readerAppearance.ts:2-5`) et la couleur du libellé d'un fond
    ///   (`'#342a27'`, `src/App.tsx:330`). Les recopier en `UInt32` ferait perdre
    ///   la chaîne, et c'est justement la chaîne que le banc peut comparer au
    ///   fichier de référence : deux écritures différentes de la même couleur
    ///   (`#FAF7F2` et `#faf7f2`) ne se distinguent plus une fois converties.
    ///
    /// REND `nil` PLUTÔT QU'UNE COULEUR FAUSSE
    ///   Une chaîne qui n'est pas six chiffres hexadécimaux n'a pas de couleur.
    ///   Rendre du noir ou du transparent ferait passer une faute de frappe pour
    ///   un choix de design.
    public static func color(hexString: String) -> Color? {
        var text = hexString
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return hex(value)
    }

    // MARK: Palettes (src/ui/theme.tsx:9-13)

    public static let white = Palette(
        green: hex(0x7B285C), green2: hex(0x7B285C), cream: hex(0xFCFBF9),
        paper: hex(0xFFFFFF), beige: hex(0xECE8E5), gold: hex(0xC89A52),
        text: hex(0x241C2B), muted: hex(0x746D7B), line: hex(0xECE8E5),
        red: hex(0xA85353), soft: hex(0xF8F6F4), softBorder: hex(0xECE8E5),
        selected: hex(0xF5EDF2), track: hex(0xE8D9E3), progress: hex(0xF5EDF2),
        surahBadge: hex(0xF5EDF2)
    )

    public static let classic = Palette(
        green: hex(0x153F36), green2: hex(0x276454), cream: hex(0xF7F5EE),
        paper: hex(0xFFFDF7), beige: hex(0xE9E2D2), gold: hex(0xB39559),
        text: hex(0x20342E), muted: hex(0x6C7B72), line: hex(0xE4E7DF),
        red: hex(0x9D554D), soft: hex(0xECF1EA), softBorder: hex(0xCAD8CE),
        selected: hex(0xEAF2EC), track: hex(0x49756B), progress: hex(0xDBC591),
        surahBadge: hex(0xE8EFE8)
    )

    public static let feminine = Palette(
        green: hex(0x9D496B), green2: hex(0xC76D91), cream: hex(0xFFFAFC),
        paper: hex(0xFFF5F8), beige: hex(0xF3DCE5), gold: hex(0xB39559),
        text: hex(0x3C2833), muted: hex(0x765B69), line: hex(0xEBCAD8),
        red: hex(0x9D554D), soft: hex(0xF3DCE5), softBorder: hex(0xDCA6BD),
        selected: hex(0xF8E7EE), track: hex(0xB9708D), progress: hex(0xF3DCE5),
        surahBadge: hex(0xF3DCE5)
    )

    public static let lilac = Palette(
        green: hex(0x5F548E), green2: hex(0x897AB5), cream: hex(0xFBF9FF),
        paper: hex(0xFFFCFF), beige: hex(0xECE4F5), gold: hex(0xB89D65),
        text: hex(0x2D2943), muted: hex(0x716B86), line: hex(0xE3DCF0),
        red: hex(0xA45C67), soft: hex(0xF0EBF8), softBorder: hex(0xCFC5E3),
        selected: hex(0xECE6F6), track: hex(0x9689BB), progress: hex(0xD4C4EB),
        surahBadge: hex(0xEEE8F8)
    )

    public static let night = Palette(
        green: hex(0x132B47), green2: hex(0x315273), cream: hex(0xF7F7F4),
        paper: hex(0xFFFDF8), beige: hex(0xE9E6DF), gold: hex(0xB58942),
        text: hex(0x1C2A3B), muted: hex(0x68727D), line: hex(0xDFE3E5),
        red: hex(0xA85F57), soft: hex(0xE9EEF1), softBorder: hex(0xC4D2DB),
        selected: hex(0xE8EFF4), track: hex(0x5C7390), progress: hex(0xD8AF68),
        surahBadge: hex(0xE8EDF1)
    )

    public static func palette(named name: String?) -> Palette {
        switch name {
        case "classic": return classic
        case "feminine": return feminine
        case "lilac": return lilac
        case "night": return night
        default: return white
        }
    }

    // MARK: Accents (src/theme/tokens.ts:5-10)

    public struct Accent: Equatable, Sendable {
        public var label: String
        /// La pastille du sélecteur — `swatch`, `src/theme/tokens.ts:6-9`.
        ///
        /// Elle n'est PAS `primary` : trois des quatre accents portent une
        /// pastille plus claire que leur couleur appliquée (rose `#D9899A` pour
        /// un `primary` `#A95069`, vert `#6E8B68` pour `#54734E`, doré
        /// `#C89A52` pour `#916825`). Le rond affiché serait donc faux pour
        /// trois accents sur quatre si l'on confondait les deux.
        public var swatch: Color
        public var primary: Color
        public var soft: Color
    }

    public static let accents: [String: Accent] = [
        "prune": Accent(label: "Prune", swatch: hex(0x7B285C), primary: hex(0x7B285C), soft: hex(0xF5EDF2)),
        "rose": Accent(label: "Rose", swatch: hex(0xD9899A), primary: hex(0xA95069), soft: hex(0xFCF0F3)),
        "green": Accent(label: "Vert", swatch: hex(0x6E8B68), primary: hex(0x54734E), soft: hex(0xEDF5EA)),
        "gold": Accent(label: "Doré", swatch: hex(0xC89A52), primary: hex(0x916825), soft: hex(0xFBF4E8))
    ]

    /// L'ordre des accents — celui d'insertion de l'objet `accents`
    /// (`src/theme/tokens.ts:5-10`), que `AccentSelector` parcourt par
    /// `Object.keys` (`DesignSystem.tsx:18`).
    ///
    /// Un dictionnaire Swift n'a **aucun** ordre : sans cette liste, le
    /// sélecteur afficherait les quatre pastilles dans un ordre arbitraire, et
    /// donc pas celui de l'application actuelle.
    public static let accentOrder: [String] = ["prune", "rose", "green", "gold"]

    // MARK: Métriques (src/theme/tokens.ts:1-3)

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let section: CGFloat = 32
    }

    public enum Radius {
        public static let small: CGFloat = 14
        public static let card: CGFloat = 20
        public static let pill: CGFloat = 28
        public static let sheet: CGFloat = 30
    }

    public enum Typography {
        public static let header: CGFloat = 24
        public static let screen: CGFloat = 30
        public static let section: CGFloat = 21
        public static let card: CGFloat = 17
        public static let body: CGFloat = 14
        public static let secondary: CGFloat = 12
        public static let metadata: CGFloat = 11
        public static let arabic: CGFloat = 22
    }

    // MARK: Thèmes proposés (src/ui/theme.tsx:19-25)

    public struct ThemeOption: Identifiable, Sendable {
        public var id: String
        public var name: String
        public var description: String
    }

    public static let themeOptions: [ThemeOption] = [
        ThemeOption(id: "white", name: "Thème blanc", description: "Simple et épuré"),
        ThemeOption(id: "classic", name: "Thème vert", description: "Serein et naturel"),
        ThemeOption(id: "feminine", name: "Thème rose", description: "Doux et moderne"),
        ThemeOption(id: "lilac", name: "Lilas & Perle", description: "Délicat et raffiné"),
        ThemeOption(id: "night", name: "Bleu Nuit & Or", description: "Sobre et élégant")
    ]

    // MARK: Illustrations des thèmes (src/ui/Premium.tsx:9)

    /// `themeArt` — le nom de fichier de l'illustration d'un thème.
    ///
    /// **Deux clés ne portent pas le nom de leur fichier**, et c'est la seule
    /// raison d'être de cette table : `classic` lit `emerald.png`, et `feminine`
    /// lit `rose.png`. Écrire `classic.png` compilerait, ne trouverait rien, et
    /// laisserait la carte vide sans qu'aucun contrôle ne le signale.
    public static let artNames: [String: String] = [
        "white": "white.png",
        "classic": "emerald.png",
        "feminine": "rose.png",
        "lilac": "lilac.png",
        "night": "night.png"
    ]

    /// Le nom de fichier de l'illustration, ou `nil` pour un thème inconnu —
    /// comme `themeArt[clé]` rend `undefined` pour une clé absente.
    public static func artName(for theme: String) -> String? { artNames[theme] }

    /// Les mesures de l'illustration, lues dans la référence
    /// (`src/ui/DesignSystem.tsx:17` pour la carte, `src/ui/MainScreens.tsx:23`
    /// pour le bandeau d'accueil).
    ///
    /// La largeur de la carte est une **fraction de sa boîte de contenu**, pas
    /// une largeur fixe : la remplacer par des points donnerait une carte juste
    /// sur un seul format d'écran. Les quatre autres sont des valeurs absolues
    /// de la référence.
    public enum Art {
        /// `width: '42%'` de la boîte de contenu de la carte.
        public static let widthFraction: CGFloat = 0.42
        /// `height: 105`.
        public static let height: CGFloat = 105
        /// `borderRadius: 14`.
        public static let cornerRadius: CGFloat = 14
        /// `imageStyle={{opacity:0.55}}` du bandeau d'accueil.
        public static let bannerOpacity: Double = 0.55
        /// `minHeight: 100` du bandeau d'accueil.
        public static let bannerMinHeight: CGFloat = 100
    }
}

/// Environnement SwiftUI : la palette active suit `theme` et `accent` de l'état.
public struct ThemeKey: EnvironmentKey {
    public static let defaultValue = Theme.white
}

public extension EnvironmentValues {
    var palette: Palette {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

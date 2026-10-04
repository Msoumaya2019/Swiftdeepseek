// VerseBounds.swift
// Rectangles des versets sur les pages du Moushaf, et géométrie des pages.
//
// Correspondance : `MushafPage.tsx:29`, `:44`, `:48`, `:51-52` de l'application
// React Native, et `src/core/quranSources.ts:7-11`.
//
// À QUOI ÇA SERT
//   Mettre en évidence un verset dans le lecteur : verset difficile (rouge
//   clair), verset marqué d'un signet, verset en cours de lecture. Les pages
//   sont des IMAGES : sans ces rectangles, on ne saurait pas où se trouve un
//   verset sur la page.
//
//   Les données vivent déjà dans `Resources/Data/` — copiées du dépôt de
//   référence à l'octet près (MD5 vérifié), et jusqu'ici lues par aucun code.
//
// LES DEUX SOURCES NE SE RESSEMBLENT QU'EN APPARENCE
//
//   | | Coran de Médine | Coran 1441 |
//   | --- | --- | --- |
//   | Fichier de rectangles | `bounds.json` | `coran_1441-bounds.json` |
//   | Pages / lignes | 604 / **13 766** | 604 / **13 273** |
//   | Image | **une** page par image | **quinze** bandes par page |
//   | Taille | `1920 × 3106` | `1440 × 2320`, page par page |
//   | Coordonnées | entières | **décimales** (`352.08`, `745.714…`) |
//   | `line` | **1** … 15 | **0** … 14 |
//
//   Les deux fichiers partagent en revanche le même ordre de colonnes
//   (`surah, ayahStart, line, x1, x2, y1, y2`), ce qui permet de les lire par le
//   même code. Mesures faites sur les fichiers embarqués, pas déduites.
//
// CE QUE CE FICHIER NE FAIT PAS
//   Il ne dessine rien et ne connaît aucune couleur. Il rend des rectangles en
//   coordonnées d'IMAGE ; la vue qui dessine les projette à l'écran, parce
//   qu'elle seule connaît sa taille.

import CoreGraphics
import Foundation

public enum VerseBounds {

    // MARK: Sources

    /// Les deux sources dont les rectangles sont connus.
    public enum Source: String, Sendable, CaseIterable {
        case medine
        case coran1441

        /// Nom du fichier de rectangles, sans extension — cherché dans le paquet
        /// par `Bundle.main.url(forResource:withExtension:)`.
        var boundsFile: String {
            switch self {
            case .medine: return "bounds"
            case .coran1441: return "coran_1441-bounds"
            }
        }

        /// Taille utilisée quand la taille réelle de la page n'est pas connue.
        ///
        /// Ce n'est pas un ordre de grandeur : c'est la valeur **mesurée** sur
        /// les fichiers. Le Coran de Médine n'a pas de fichier de dimensions —
        /// sa taille est une constante de la source (`MushafPage.tsx:29`) ; le
        /// Coran 1441 en a un, et il donne `1440 × 2320` pour ses **604** pages.
        var fallbackImageSize: CGSize {
            switch self {
            case .medine: return CGSize(width: 1920, height: 3106)
            case .coran1441: return CGSize(width: 1440, height: 2320)
            }
        }
    }

    /// Nombre de bandes par page pour le Coran 1441.
    ///
    /// Vérifié sur place : l'archive publiée contient **9 060** fichiers
    /// (`604 × 15`), et `quranDownload.ts` borne les lignes à `1 … 15`.
    public static let linesPerPage = 15

    /// Hauteur d'une bande du Coran 1441, en pixels de sa page.
    ///
    /// Les images de bande font `1440 × 232`, et les rectangles du fichier
    /// `coran_1441-bounds.json` ont **tous** exactement cette hauteur.
    public static let coran1441BandHeight: CGFloat = 232

    /// Dimensions des pages du Coran de Médine, en pixels.
    ///
    /// Conservée telle quelle pour cette source ; `imageSize(for:page:)` est la
    /// forme qui vaut pour les deux.
    public static let imageSize = Source.medine.fallbackImageSize

    /// Dimensions à utiliser pour projeter un rectangle de cette page.
    ///
    /// Se fier à la mauvaise taille décale **toutes** les mises en évidence de
    /// la page, sans autre symptôme : la boîte calculée est simplement au mauvais
    /// endroit, et rien ne signale l'erreur. D'où une taille lue à la source
    /// plutôt que supposée.
    ///
    /// Le repli sur `fallbackImageSize` vaut pour une page absente du fichier de
    /// dimensions — cas qui ne se produit pas dans les fichiers livrés (604 pages
    /// sur 604), mais qui ne doit pas produire un rectangle infini si le fichier
    /// venait à manquer.
    ///
    /// Écart assumé avec l'original : `quranSources.ts:10` écrit
    /// `dimensions[page] ?? [1,1]`. Un repli sur `1 × 1` ne décale pas les
    /// rectangles, il les rend **absurdes** (toutes les coordonnées multipliées
    /// par la largeur de la vue). Le repli retenu est la taille réelle de la
    /// source.
    public static func imageSize(for source: Source, page: Int) -> CGSize {
        switch source {
        case .medine:
            return source.fallbackImageSize
        case .coran1441:
            guard let entry = coran1441Dimensions[String(page)],
                  entry.count == 2,
                  entry[0] > 0, entry[1] > 0 else {
                return source.fallbackImageSize
            }
            return CGSize(width: entry[0], height: entry[1])
        }
    }

    // MARK: Une ligne du fichier

    /// Une ligne de `bounds.json` : le verset, et le rectangle qu'il occupe.
    ///
    /// ATTENTION À L'ORDRE DES COLONNES. Le format est
    /// `[sourate, versetDébut, ligne, x1, x2, y1, y2]` — et **non**
    /// `x1, y1, x2, y2`. C'est l'usage qu'en fait l'original qui le fixe :
    ///   `left: row[3]`, `width: row[4] - row[3]`,
    ///   `top: row[5]`,  `height: row[6] - row[5]`.
    /// À l'œil, `bounds.json` donne l'impression d'un `x1, y1, x2, y2` : les
    /// valeurs décroissent dans cet ordre. Se fier à cette impression produit
    /// des rectangles faux — 6 425 lignes sur 13 766 auraient une taille
    /// négative — et un décalage qui ressemble à un problème de projection.
    ///
    /// La troisième colonne s'appelle `line`, et **non** « verset de fin ».
    /// Mesuré : elle plafonne à **15** dans `bounds.json`, alors qu'un numéro de
    /// verset atteindrait 286 (al-Baqarah). Trier les lignes d'une page par `y1`
    /// ne produit **aucune** inversion sur 13 162 paires : la valeur suit
    /// exactement la position verticale. L'original l'appelle `line` aux deux
    /// endroits où il l'utilise (`MushafPage.tsx:53`,
    /// `quranSources.ts:22`).
    ///
    /// Elle est **1-basée** pour le Coran de Médine (`1 … 15`) et **0-basée**
    /// pour le Coran 1441 (`0 … 14`) : deux sources, deux conventions, et rien
    /// ne le signale à la lecture. `line` porte donc la valeur brute du fichier,
    /// sans normalisation — la convertir serait une occasion de se tromper pour
    /// un gain nul, le Coran de Médine n'étant rendu qu'en une seule image.
    public struct Row: Equatable, Sendable {
        public let surah: Int
        public let ayahStart: Int
        public let line: Int
        public let rect: CGRect

        public init(surah: Int, ayahStart: Int, line: Int, rect: CGRect) {
            self.surah = surah
            self.ayahStart = ayahStart
            self.line = line
            self.rect = rect
        }
    }

    // MARK: Mise en évidence

    /// Pourquoi une zone est mise en évidence. La couleur est décidée par la vue.
    ///
    /// L'ordre des cas est l'ordre de priorité : quand un verset cumule
    /// plusieurs états, c'est le premier qui s'applique. Il n'existe pas de cas
    /// « aucune mise en évidence » : une ligne qui n'entre dans aucun de ces
    /// trois états n'est simplement pas rendue.
    public enum Kind: String, Sendable, CaseIterable {
        case difficult, bookmark, playing
    }

    /// Opacité de la mise en évidence — `MushafPage.tsx:51`.
    ///
    /// L'original écrit :
    ///   `opacity: bookmarkIds.includes(id) ? 0.18 : difficultIds.includes(id) ? 0.18 : active ? 0.42 : 0.11`
    /// soit, dans l'ordre de priorité de `Kind` : signet 0,18 ; difficile 0,18 ;
    /// lecture 0,42. Les deux premiers donnent la même valeur, donc `Kind` suffit
    /// à la déterminer — la couleur, elle, les distingue.
    ///
    /// La dernière branche de l'original (0,11, couleur `gold`) est
    /// **inatteignable** : une ligne n'est retenue que si elle est difficile,
    /// marquée, ou en lecture, et ces trois cas sont couverts ci-dessus. Elle
    /// n'est donc pas reprise — la reproduire laisserait croire à un état qui
    /// n'existe pas.
    public static func opacity(for kind: Kind) -> CGFloat {
        switch kind {
        case .difficult: return 0.18
        case .bookmark: return 0.18
        case .playing: return 0.42
        }
    }

    /// Rayon des coins, en points — `borderRadius: 4` dans l'original.
    public static let cornerRadius: CGFloat = 4

    /// Une zone à dessiner, en coordonnées d'image.
    public struct Highlight: Equatable, Sendable {
        public let verseID: Int
        public let rect: CGRect
        public let kind: Kind

        public init(verseID: Int, rect: CGRect, kind: Kind) {
            self.verseID = verseID
            self.rect = rect
            self.kind = kind
        }
    }

    // MARK: Lecture

    /// Les deux sources sont chargées **séparément et paresseusement** : un
    /// `static let` n'est initialisé qu'au premier accès, donc lire une page du
    /// Coran de Médine ne lit jamais le fichier du Coran 1441 — 789 Ko et
    /// 13 273 lignes qui n'ont pas à être analysés pour afficher un rectangle.
    ///
    /// C'est la raison pour laquelle il n'y a pas ici de boucle sur
    /// `Source.allCases` : elle chargerait **les deux** fichiers au premier
    /// usage, quel qu'il soit.
    private static let medineRows: [String: [Row]] = load(.medine)
    private static let coran1441Rows: [String: [Row]] = load(.coran1441)

    /// Dimensions du Coran 1441, page par page. Le Coran de Médine n'en a pas.
    private static let coran1441Dimensions: [String: [Double]] =
        loadDimensions("coran_1441-dimensions")

    public static func rows(page: Int, source: Source = .medine) -> [Row] {
        let table = source == .medine ? medineRows : coran1441Rows
        return table[String(page)] ?? []
    }

    /// Les zones à dessiner pour une page, dans l'ordre du document.
    ///
    /// Reproduit le filtre de `MushafPage.tsx:51` : une ligne est retenue si le
    /// verset qu'elle **ouvre** est difficile, marqué d'un signet, ou en cours
    /// de lecture. La difficulté prime, puis le signet, puis la lecture — c'est
    /// l'ordre des tests dans l'original, et c'est lui qui décide de la couleur
    /// quand un verset cumule plusieurs états.
    public static func highlights(
        page: Int,
        source: Source = .medine,
        difficulty: Set<Int> = [],
        bookmarks: Set<Int> = [],
        playing: Int? = nil
    ) -> [Highlight] {
        rows(page: page, source: source).compactMap { row in
            guard let id = Quran.verseID(surah: row.surah, ayah: row.ayahStart) else { return nil }
            if difficulty.contains(id) {
                return Highlight(verseID: id, rect: row.rect, kind: .difficult)
            }
            if bookmarks.contains(id) {
                return Highlight(verseID: id, rect: row.rect, kind: .bookmark)
            }
            if playing == id {
                return Highlight(verseID: id, rect: row.rect, kind: .playing)
            }
            return nil
        }
    }

    // MARK: Géométrie de la page

    /// La boîte où l'image est **réellement dessinée** dans `bounds`.
    ///
    /// `scaleAspectFit` laisse des bandes vides : sur une vue 1200 × 3000, la
    /// page du Coran de Médine occupe 1200 × 1941,25 et laisse 529,375 pt de
    /// vide en haut et en bas. Partir du coin de la vue au lieu du coin de
    /// l'image place le verset 415 pt trop haut.
    ///
    /// C'est la seule fonction qui calcule ce centrage : `project` s'appuie
    /// dessus, et la vue de dessin s'en sert pour ancrer le signet. Deux calculs
    /// séparés finiraient par diverger.
    public static func pageBox(in bounds: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.minX + (bounds.width - drawn.width) / 2,
            y: bounds.minY + (bounds.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
    }

    /// Projette un rectangle exprimé en coordonnées d'image vers la boîte où
    /// l'image est dessinée dans `bounds`.
    ///
    /// C'est la même arithmétique que l'original, où la boîte de la vue est
    /// construite au ratio de l'image (`MushafPage.tsx:51`) :
    ///   `padding + row[3] / sourceWidth * (width - padding * 2)`.
    ///
    /// L'original n'est exact que lorsque la boîte a **exactement** le ratio de
    /// l'image : sa formule suppose que l'image remplit la boîte, alors que
    /// `contain` la letterboxe. Ici le centrage est fait explicitement, donc la
    /// projection reste juste à n'importe quel ratio — et donne la même valeur
    /// quand le ratio correspond.
    public static func project(
        _ rect: CGRect,
        into bounds: CGRect,
        imageSize: CGSize = VerseBounds.imageSize
    ) -> CGRect {
        let box = pageBox(in: bounds, imageSize: imageSize)
        guard box.width > 0, box.height > 0 else { return .zero }

        return CGRect(
            x: box.minX + rect.minX / imageSize.width * box.width,
            y: box.minY + rect.minY / imageSize.height * box.height,
            width: rect.width / imageSize.width * box.width,
            height: rect.height / imageSize.height * box.height
        )
    }

    /// Position du haut d'une bande du Coran 1441, en coordonnées de sa page.
    ///
    /// `MushafPage.tsx:48` empile les quinze bandes à
    /// `top = (height - width * 232 / 1440) / 14 * line`. Ramené en coordonnées
    /// de page, cela fait un **pas constant** de
    /// `(2320 - 232) / 14 = 149,142857…` pixels, la dernière bande finissant
    /// exactement au bas de la page.
    ///
    /// Mesure de contrôle : les **13 273** lignes de `coran_1441-bounds.json`
    /// ont `y1 == pas × line` et `y2 - y1 == 232`, **sans une exception**. Les
    /// rectangles du fichier sont donc déjà des rectangles de bande — bandes et
    /// mises en évidence se projettent par la même fonction, et ne peuvent pas
    /// diverger.
    private static func bandTop(line: Int, imageSize: CGSize) -> CGFloat {
        let step = (imageSize.height - coran1441BandHeight) / CGFloat(linesPerPage - 1)
        return step * CGFloat(line)
    }

    /// Rectangle d'une bande, projeté dans `bounds`.
    ///
    /// Vaut pour le Coran 1441 seulement : le Coran de Médine est rendu en une
    /// seule image, sans bandes.
    ///
    /// `line` est l'indice **0-basé** de la bande, comme la troisième colonne de
    /// `coran_1441-bounds.json`.
    public static func bandRect(line: Int, in bounds: CGRect, imageSize: CGSize) -> CGRect {
        guard line >= 0, line < linesPerPage else { return .zero }
        let rect = CGRect(
            x: 0,
            y: bandTop(line: line, imageSize: imageSize),
            width: imageSize.width,
            height: coran1441BandHeight
        )
        return project(rect, into: bounds, imageSize: imageSize)
    }

    // MARK: Chargement

    /// Lit les rectangles d'une source.
    ///
    /// Décodage en `Double` pour les **deux** sources, et non en `Int` : le
    /// fichier du Coran de Médine ne contient que des entiers, mais celui du
    /// Coran 1441 porte des décimales (`352.08`, `745.714…`). `JSONDecoder`
    /// accepte un entier là où un `Double` est attendu, donc un seul code suffit
    /// — alors que décoder en `Int` ferait **échouer tout le fichier 1441**, et
    /// donc disparaître toutes ses mises en évidence, sans autre symptôme.
    private static func load(_ source: Source) -> [String: [Row]] {
        guard let url = Bundle.main.url(forResource: source.boundsFile, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [[Double]]].self, from: data) else {
            // Pas de `fatalError` ici, contrairement à `Quran.load()` : ces
            // rectangles ne servent qu'à la mise en évidence. Leur absence doit
            // laisser lire le Moushaf, pas fermer l'application.
            return [:]
        }

        var result: [String: [Row]] = [:]
        for (page, lines) in raw {
            result[page] = lines.compactMap { values in
                guard values.count == 7 else { return nil }
                // Un rectangle dégénéré ou inversé est écarté plutôt que
                // construit : `CGRect` accepte une largeur négative, et le
                // résultat serait invisible sans qu'on sache pourquoi.
                guard values[4] > values[3], values[6] > values[5] else { return nil }
                return Row(
                    surah: Int(values[0]),
                    ayahStart: Int(values[1]),
                    line: Int(values[2]),
                    rect: CGRect(
                        x: CGFloat(values[3]),
                        y: CGFloat(values[5]),
                        width: CGFloat(values[4] - values[3]),
                        height: CGFloat(values[6] - values[5])
                    )
                )
            }
        }
        return result
    }

    private static func loadDimensions(_ name: String) -> [String: [Double]] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data) else {
            return [:]
        }
        return raw
    }
}

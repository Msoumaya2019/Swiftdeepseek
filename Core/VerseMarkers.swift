// VerseMarkers.swift
// Pastilles de numéro de verset du Coran 1441.
//
// Correspondance : `MushafPage.tsx:4` (l'import) et `:49` (le rendu) de
// l'application React Native.
//
// À QUOI ÇA SERT
//   Le Coran 1441 est rendu en **quinze bandes** empilées. Les bandes sont des
//   images : le numéro de verset n'y est pas imprimé. L'original pose donc, au
//   début de chaque verset, une **pastille** portant son numéro en chiffres
//   arabes orientaux. Sans ces pastilles, le lecteur Swift affiche les quinze
//   bandes nues — lisible, mais sans repère de verset.
//
// LA DONNÉE ÉTAIT DÉJÀ LÀ
//   `Resources/Data/coran_1441-markers.json` est embarqué depuis l'origine et
//   n'était lu par aucun code. Vérifié à l'octet près contre
//   `src/data/quran-tests/coran_1441-markers.json` du dépôt de référence :
//   **200 110** octets, md5 `552b038299ae128131ffbe8d94cd7704`.
//
// FORMAT, MESURÉ
//   `{ "<page>": [[sourate, verset, ligne, x, y], …] }` — **604** pages,
//   **6 236** marqueurs, un par verset.
//
//   La `ligne` est **0-basée** (`0` à `14`) : c'est l'indice de bande, la même
//   convention que `coran_1441-bounds.json` — et non celle de `bounds.json`, qui
//   est 1-basée. Se tromper de convention ne produit aucune erreur, seulement des
//   pastilles sur la mauvaise bande.
//
//   `x` est une fraction de la **largeur de page** (`0,042` à `0,892`) ;
//   `y` une fraction de la **hauteur de bande** (`0,435` à `0,669`). Les deux
//   dénominateurs ne sont pas les mêmes — c'est la source d'erreur la plus facile
//   de ce fichier, et l'original les distingue explicitement :
//   `left: x * width`, `top: bandTop + y * (width * 232 / 1440)`.
//
// CE QUE CE FICHIER NE FAIT PAS
//   Il ne dessine rien et ne connaît aucune couleur. Il rend des boîtes en
//   coordonnées d'ÉCRAN, via la même projection que les mises en évidence ; la
//   vue qui dessine n'a donc aucune arithmétique à elle.

import CoreGraphics
import Foundation

public enum VerseMarkers {

    // MARK: Une pastille

    /// Un marqueur de `coran_1441-markers.json`.
    public struct Marker: Equatable, Sendable {
        public let surah: Int
        public let ayah: Int
        /// Indice de bande, **0-basé** (`0 … 14`).
        public let line: Int
        /// Position horizontale, en **fraction de la largeur de page**.
        public let x: CGFloat
        /// Position verticale, en **fraction de la hauteur de bande**.
        public let y: CGFloat

        public init(surah: Int, ayah: Int, line: Int, x: CGFloat, y: CGFloat) {
            self.surah = surah
            self.ayah = ayah
            self.line = line
            self.x = x
            self.y = y
        }
    }

    // MARK: Mesures reprises de l'original

    /// Diamètre de la pastille, en fraction de la largeur de page —
    /// `MushafPage.tsx:49` : `const diameter = width * .05`.
    public static let diameterRatio: CGFloat = 0.05

    /// Épaisseur de la bordure, en fraction de la largeur de page —
    /// `borderWidth: width * .003`.
    public static let borderRatio: CGFloat = 0.003

    /// Taille de la police, en fraction de la largeur de page —
    /// `fontSize: width * .025`.
    public static let fontRatio: CGFloat = 0.025

    // L'original resserre en outre la ligne du texte (`lineHeight: diameter * .8`,
    // `includeFontPadding: false`). Ce sont deux réglages de mise en page de React
    // Native, sans équivalent ici : la vue centre le glyphe sur sa propre boîte,
    // ce qui donne le même résultat sans dépendre d'un détail de la plateforme.

    // MARK: Chiffres arabes orientaux

    /// Les dix chiffres arabes orientaux, indexés par le chiffre ASCII.
    private static let easternDigits = Array("٠١٢٣٤٥٦٧٨٩")

    /// Rend un nombre en chiffres arabes orientaux — `٠١٢٣٤٥٦٧٨٩`.
    ///
    /// Reproduit exactement le remplacement de l'original
    /// (`String(ayah).replace(/\d/g, n => '٠١٢٣٤٥٦٧٨٩'[Number(n)])`), qui porte
    /// sur les chiffres **ASCII** `0` … `9` seulement.
    ///
    /// La distinction n'est pas théorique : `Character.wholeNumberValue` de
    /// Swift reconnaît aussi les chiffres arabes orientaux eux-mêmes, et un
    /// chiffre déjà converti serait alors reconverti — une faute invisible, le
    /// résultat restant un chiffre. D'où le test sur `asciiValue`.
    public static func easternArabicNumerals(_ value: Int) -> String {
        var result = ""
        for character in String(value) {
            guard let ascii = character.asciiValue, ascii >= 48, ascii <= 57 else {
                result.append(character)
                continue
            }
            result.append(easternDigits[Int(ascii - 48)])
        }
        return result
    }

    // MARK: Géométrie

    /// Largeur de la page **telle qu'elle est dessinée** dans `bounds`.
    ///
    /// C'est le dénominateur de `diameterRatio`, `borderRatio` et `fontRatio`.
    /// La prendre dans `bounds` plutôt que dans `imageSize` est ce qui fait
    /// suivre la taille de la pastille à l'écran (rotation, mini-lecteur).
    public static func pageWidth(in bounds: CGRect, imageSize: CGSize) -> CGFloat {
        VerseBounds.pageBox(in: bounds, imageSize: imageSize).width
    }

    /// Diamètre d'une pastille, en points.
    public static func diameter(in bounds: CGRect, imageSize: CGSize) -> CGFloat {
        pageWidth(in: bounds, imageSize: imageSize) * diameterRatio
    }

    /// La boîte d'une pastille, projetée dans `bounds`.
    ///
    /// Passe par `VerseBounds.bandRect` plutôt que de refaire le calcul de la
    /// bande : la pastille est alors **solidaire de la bande qu'elle annote**, et
    /// les deux ne peuvent pas diverger. C'est aussi ce qui rend la fonction
    /// juste quand la vue n'a pas le ratio de la page — cas où la formule de
    /// l'original (`(height - width * 232 / 1440) / 14 * line`) dérive, puisqu'elle
    /// suppose que la vue a exactement ce ratio.
    ///
    /// Rend `.zero` si la ligne sort des bornes ou si la bande est vide : la vue
    /// écarte alors la pastille au lieu de la dessiner à une position arbitraire.
    public static func medallionRect(
        for marker: Marker,
        in bounds: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        let band = VerseBounds.bandRect(line: marker.line, in: bounds, imageSize: imageSize)
        guard band.width > 0, band.height > 0 else { return .zero }

        let diameter = band.width * diameterRatio
        return CGRect(
            x: band.minX + marker.x * band.width - diameter / 2,
            y: band.minY + marker.y * band.height - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    // MARK: Lecture

    /// Les pastilles d'une page.
    ///
    /// **La source compte.** Ces marqueurs annotent les bandes du Coran 1441 :
    /// leurs fractions se rapportent à la page du 1441, et leur `line` est
    /// l'indice d'une de ses quinze bandes. Les projeter sur une page du Coran de
    /// Médine donnerait des pastilles à des endroits **plausibles** sur une image
    /// qui n'est pas la même — ce qui est pire que rien. La source est donc un
    /// paramètre, et toute source autre que le 1441 rend une liste vide.
    public static func markers(page: Int, source: VerseBounds.Source = .coran1441) -> [Marker] {
        guard source == .coran1441 else { return [] }
        return rows[String(page)] ?? []
    }

    /// Nombre de pages annotées. Sert de mesure de contrôle : le fichier livré en
    /// porte **604**, une par page.
    public static var annotatedPageCount: Int { rows.count }

    /// Total des pastilles. Le fichier livré en porte **6 236**, un par verset.
    public static var markerCount: Int { rows.values.reduce(0) { $0 + $1.count } }

    /// Chargé **paresseusement**, comme les rectangles : un `static let` n'est
    /// initialisé qu'au premier accès, donc une page du Coran de Médine ne fait
    /// jamais analyser ce fichier de 200 Ko.
    private static let rows: [String: [Marker]] = load()

    /// Lit le fichier des pastilles.
    ///
    /// Décodage en `Double` : le fichier porte des décimales (`0.29513928`).
    /// Aucun `fatalError` — contrairement à `Quran.load()` —, pour la même raison
    /// que `VerseBounds.load` : ces pastilles ne sont qu'un repère de lecture, et
    /// leur absence doit laisser lire le Moushaf, pas fermer l'application.
    private static func load() -> [String: [Marker]] {
        guard let url = Bundle.main.url(forResource: "coran_1441-markers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [[Double]]].self, from: data) else {
            return [:]
        }

        var result: [String: [Marker]] = [:]
        for (page, lines) in raw {
            result[page] = lines.compactMap { values in
                guard values.count == 5 else { return nil }

                // Une ligne hors des quinze bandes, ou une fraction hors de la
                // page, ne peut pas être dessinée : la pastille sortirait de sa
                // bande ou de l'image. L'écarter vaut mieux que la dessiner
                // ailleurs sans le dire.
                let line = Int(values[2])
                guard line >= 0, line < VerseBounds.linesPerPage else { return nil }
                guard values[3] >= 0, values[3] <= 1, values[4] >= 0, values[4] <= 1 else { return nil }

                return Marker(
                    surah: Int(values[0]),
                    ayah: Int(values[1]),
                    line: line,
                    x: CGFloat(values[3]),
                    y: CGFloat(values[4])
                )
            }
        }
        return result
    }
}

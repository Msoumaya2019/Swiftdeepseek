// VerseBounds.swift
// Rectangles des versets sur les pages du Moushaf.
//
// Correspondance : `MushafPage.tsx:51` de l'application React Native.
//
// À QUOI ÇA SERT
//   Mettre en évidence un verset dans le lecteur : verset difficile (rouge
//   clair), verset marqué d'un signet, verset en cours de lecture. Les pages
//   sont des IMAGES : sans ces rectangles, on ne saurait pas où se trouve un
//   verset sur la page.
//
//   Les données vivent déjà dans `Resources/Data/bounds.json` — copiées depuis
//   le dépôt de référence, et jusqu'ici chargées par aucun code Swift.
//
// CE QUE CE FICHIER NE FAIT PAS
//   Il ne dessine rien et ne connaît aucune couleur. Il rend des rectangles en
//   coordonnées d'IMAGE ; la vue qui dessine les projette à l'écran, parce
//   qu'elle seule connaît sa taille.

import CoreGraphics
import Foundation

public enum VerseBounds {

    /// Dimensions des images de page, en pixels.
    /// Constante de la source — `MushafPage.tsx:29` : `[1920, 3106]` pour le
    /// Coran de Médine. Elle n'est pas lue dans `dimensions.json` parce que
    /// `bounds.json` ne s'applique qu'à cette source-là.
    public static let imageSize = CGSize(width: 1920, height: 3106)

    /// Une ligne de `bounds.json` : le verset, et le rectangle qu'il occupe.
    ///
    /// ATTENTION À L'ORDRE DES COLONNES. Le format est
    /// `[sourate, versetDébut, versetFin, x1, x2, y1, y2]` — et **non**
    /// `x1, y1, x2, y2`. C'est l'usage qu'en fait l'original qui le fixe :
    ///   `left: row[3]`, `width: row[4] - row[3]`,
    ///   `top: row[5]`,  `height: row[6] - row[5]`.
    /// À l'œil, `bounds.json` donne l'impression d'un `x1, y1, x2, y2` : les
    /// valeurs décroissent dans cet ordre. Se fier à cette impression produit
    /// des rectangles faux, et un décalage qui ressemble à un problème de
    /// projection.
    public struct Row: Equatable, Sendable {
        public let surah: Int
        public let ayahStart: Int
        public let ayahEnd: Int
        public let rect: CGRect

        public init(surah: Int, ayahStart: Int, ayahEnd: Int, rect: CGRect) {
            self.surah = surah
            self.ayahStart = ayahStart
            self.ayahEnd = ayahEnd
            self.rect = rect
        }
    }

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

    /// Chargées une seule fois : 604 pages, quelques centaines de kilo-octets.
    private static let rowsByPage: [String: [Row]] = load()

    public static func rows(page: Int) -> [Row] {
        rowsByPage[String(page)] ?? []
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
        difficulty: Set<Int> = [],
        bookmarks: Set<Int> = [],
        playing: Int? = nil
    ) -> [Highlight] {
        rows(page: page).compactMap { row in
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

    // MARK: Projection

    /// Projette un rectangle exprimé en coordonnées d'image vers la zone où
    /// l'image est **réellement dessinée** dans `bounds`.
    ///
    /// `UIImageView` en `scaleAspectFit` laisse des bandes vides : le rectangle
    /// projeté doit donc partir du coin de l'image affichée, pas du coin de la
    /// vue. Utiliser `bounds` directement décale la mise en évidence vers le
    /// haut dès que la vue est plus large que l'image — et l'erreur grandit avec
    /// la taille de l'écran.
    ///
    /// C'est la même arithmétique que l'original, où la boîte de la vue est
    /// construite au ratio de l'image (`MushafPage.tsx:51`) :
    ///   `padding + row[3] / sourceWidth * (width - padding * 2)`.
    public static func project(
        _ rect: CGRect,
        into bounds: CGRect,
        imageSize: CGSize = VerseBounds.imageSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawnWidth = imageSize.width * scale
        let drawnHeight = imageSize.height * scale
        let originX = bounds.minX + (bounds.width - drawnWidth) / 2
        let originY = bounds.minY + (bounds.height - drawnHeight) / 2

        return CGRect(
            x: originX + rect.minX / imageSize.width * drawnWidth,
            y: originY + rect.minY / imageSize.height * drawnHeight,
            width: rect.width / imageSize.width * drawnWidth,
            height: rect.height / imageSize.height * drawnHeight
        )
    }

    // MARK: Chargement

    private static func load() -> [String: [Row]] {
        guard let url = Bundle.main.url(forResource: "bounds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [[Int]]].self, from: data) else {
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
                    surah: values[0],
                    ayahStart: values[1],
                    ayahEnd: values[2],
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
}

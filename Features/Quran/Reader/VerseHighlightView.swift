// VerseHighlightView.swift
// Mise en évidence des versets sur une page du Moushaf.
//
// Correspondance : `MushafPage.tsx:51-52` de l'application React Native.
//
// POURQUOI UNE VUE SÉPARÉE
//   Les pages sont des images : la position d'un verset n'est pas déductible du
//   texte affiché. `VerseBounds` rend les rectangles en coordonnées d'image ;
//   cette vue les projette à l'écran et les dessine. Les deux responsabilités
//   sont séparées pour que la géométrie soit éprouvable sans dessiner, et que le
//   dessin n'ait aucune arithmétique à lui.
//
// CE QUI EST REPRIS DE L'ORIGINAL, ET CE QUI NE L'EST PAS
//   Repris : les rectangles (rouge clair pour un verset difficile, vert pour un
//   signet, surbrillance pour le verset en lecture), leurs opacités, leurs coins
//   arrondis, et l'icône de signet sur le bord droit.
//   Non repris ICI : les repères de progression de séance dans la marge
//   (`MushafPage.tsx:53`). Ils le sont désormais, mais par une autre vue —
//   `VerseMarginView` — parce qu'ils ne se dessinent pas dans la même boîte :
//   le diamètre d'une pastille dépend de la place libre à gauche de la page,
//   donc de la vue entière. Voir `MarginAnnotations`.

import SwiftUI
import UIKit

// MARK: - Couleurs

/// Les trois couleurs d'une mise en évidence, résolues depuis la palette active.
///
/// La couleur du verset **difficile** est fixe dans l'original (`#E85B5B`), elle
/// ne suit pas le thème : c'est un signal, pas une décoration. Les deux autres
/// suivent le thème, comme dans l'original (`colors.green2`, `colors.selected`).
struct VerseHighlightStyle {

    var difficult: UIColor
    var bookmark: UIColor
    var playing: UIColor

    /// `#E85B5B` — `MushafPage.tsx:51`, branche `difficult`.
    static let difficultRed = UIColor(
        red: 0xE8 / 255,
        green: 0x5B / 255,
        blue: 0x5B / 255,
        alpha: 1
    )

    /// La palette porte déjà l'accent résolu (`AppViewModel.palette`) : `green2`
    /// et `selected` sont donc les mêmes valeurs qu'en React Native, sans
    /// rejouer ici la résolution de l'accent.
    static func from(_ palette: Palette) -> VerseHighlightStyle {
        VerseHighlightStyle(
            difficult: difficultRed,
            bookmark: UIColor(palette.green2),
            playing: UIColor(palette.selected)
        )
    }

    func color(for kind: VerseBounds.Kind) -> UIColor {
        switch kind {
        case .difficult: return difficult
        case .bookmark: return bookmark
        case .playing: return playing
        }
    }
}

// MARK: - La vue

/// Dessine les rectangles de mise en évidence d'**une** page.
///
/// Elle ne reçoit que les rectangles de la page affichée : elle n'a pas à savoir
/// quelle page, ni pourquoi un verset est mis en évidence.
final class VerseHighlightView: UIView {

    var highlights: [VerseBounds.Highlight] = [] {
        didSet {
            guard highlights != oldValue else { return }
            setNeedsDisplay()
        }
    }

    /// Pas de comparaison avant `setNeedsDisplay()` : le style est posé une fois
    /// par mise à jour, et `setNeedsDisplay` ne provoque qu'un seul redessin par
    /// image, même appelé plusieurs fois.
    var style: VerseHighlightStyle = .from(Theme.white) {
        didSet { setNeedsDisplay() }
    }

    /// Taille de l'image de page, en pixels.
    ///
    /// Elle **ne peut pas** être déduite de `bounds` : une vue plus large que
    /// l'image et une vue plus haute donnent la même boîte, et le rapport de
    /// l'image est justement ce qui manque pour la calculer. La vue la reçoit
    /// donc, et s'en sert pour **tout** : la boîte de page comme chaque
    /// rectangle.
    ///
    /// S'y tromper ne produit aucune erreur, seulement des mises en évidence au
    /// mauvais endroit : c'est le défaut le plus silencieux de ce fichier. Le
    /// Coran de Médine (1920 × 3106) et le Coran 1441 (1440 × 2320) ne se
    /// projettent pas de la même façon.
    var imageSize: CGSize = VerseBounds.imageSize {
        didSet {
            guard imageSize != oldValue else { return }
            setNeedsDisplay()
        }
    }

    /// Taille de l'icône de signet — `Icon name="bookmark" size={14}`.
    private static let bookmarkGlyphSize = CGSize(width: 14, height: 14)

    private static let bookmarkGlyph: UIImage? = UIImage(
        systemName: "bookmark",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        // `pointerEvents="none"` dans l'original : la mise en évidence ne doit
        // jamais intercepter le toucher, sinon on ne pourrait plus marquer un
        // verset ni poser un signet en appuyant dessus.
        isUserInteractionEnabled = false
        // Sans `redraw`, UIKit mettrait le dessin en cache et l'étirerait quand la
        // vue change de taille (rotation, mini-lecteur) : les rectangles
        // glisseraient alors au lieu de se recalculer.
        contentMode = .redraw
        isAccessibilityElement = false
    }

    override func draw(_ rect: CGRect) {
        guard !highlights.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }

        // La boîte où l'image est RÉELLEMENT dessinée, bandes vides exclues.
        // C'est elle qui sert d'ancrage au signet sur le bord droit.
        let imageBox = VerseBounds.pageBox(in: bounds, imageSize: imageSize)
        guard !imageBox.isEmpty else { return }

        for highlight in highlights {
            let projected = VerseBounds.project(highlight.rect, into: bounds, imageSize: imageSize)
            guard projected.width > 0, projected.height > 0 else { continue }

            context.setFillColor(
                style.color(for: highlight.kind)
                    .withAlphaComponent(VerseBounds.opacity(for: highlight.kind))
                    .cgColor
            )
            context.addPath(
                UIBezierPath(
                    roundedRect: projected,
                    cornerRadius: VerseBounds.cornerRadius
                ).cgPath
            )
            context.fillPath()
        }

        drawBookmarkGlyphs(anchoredTo: imageBox)
    }

    /// L'icône de signet est posée sur le bord droit de la page, alignée sur le
    /// haut du verset — `MushafPage.tsx:52` :
    /// `right: padding, top: padding + row[5] / sourceHeight * (height - padding * 2)`.
    private func drawBookmarkGlyphs(anchoredTo imageBox: CGRect) {
        guard let glyph = Self.bookmarkGlyph else { return }
        let tinted = glyph.withTintColor(style.bookmark, renderingMode: .alwaysOriginal)
        let size = Self.bookmarkGlyphSize

        for highlight in highlights where highlight.kind == .bookmark {
            let projected = VerseBounds.project(highlight.rect, into: bounds, imageSize: imageSize)
            guard projected.width > 0 else { continue }
            tinted.draw(
                in: CGRect(
                    x: imageBox.maxX - size.width,
                    y: projected.minY,
                    width: size.width,
                    height: size.height
                )
            )
        }
    }
}

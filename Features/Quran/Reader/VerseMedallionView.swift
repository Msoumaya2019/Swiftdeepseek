// VerseMedallionView.swift
// Pastilles de numéro de verset du Coran 1441.
//
// Correspondance : `MushafPage.tsx:49` de l'application React Native.
//
// POURQUOI UNE VUE SÉPARÉE
//   Les bandes du Coran 1441 sont des images : le numéro de verset n'y est pas
//   imprimé, et sa position n'est pas déductible du dessin. `VerseMarkers` rend
//   les boîtes ; cette vue les dessine. La géométrie reste donc éprouvable sans
//   dessiner, et le dessin n'a aucune arithmétique à lui.
//
// CE QUI EST REPRIS, ET CE QUI NE L'EST PAS
//   Repris : le diamètre, l'épaisseur de bordure, la taille de police, les deux
//   couleurs, et les chiffres arabes orientaux.
//   Non repris : le resserrement de ligne (`lineHeight: diameter * .8`,
//   `includeFontPadding: false`). Ce sont des réglages de mise en page de React
//   Native ; ici le glyphe est centré sur sa boîte, ce qui donne le même
//   résultat sans dépendre d'un détail de la plateforme.
//
// LES COULEURS NE SUIVENT PAS LE THÈME
//   Comme le rouge du verset difficile (`VerseHighlightStyle.difficultRed`), la
//   pastille est un **signal** et non une décoration : elle garde les deux
//   valeurs fixes de l'original, y compris en thème sombre.

import UIKit

// MARK: - Couleurs

/// Les deux couleurs d'une pastille — `MushafPage.tsx:49`.
struct VerseMedallionStyle {

    /// Fond de la pastille — `backgroundColor: '#ECFDF5'`.
    var background: UIColor

    /// Bordure **et** texte — `borderColor: '#047857'`, `color: '#047857'`.
    var ink: UIColor

    static let backgroundGreen = UIColor(
        red: 0xEC / 255,
        green: 0xFD / 255,
        blue: 0xF5 / 255,
        alpha: 1
    )

    static let inkGreen = UIColor(
        red: 0x04 / 255,
        green: 0x78 / 255,
        blue: 0x57 / 255,
        alpha: 1
    )

    /// Les deux valeurs sont fixes. Il n'y a donc **pas** de fabrique prenant une
    /// `Palette` : elle ignorerait son argument, ce qui laisserait croire que le
    /// thème agit sur la pastille. C'est le seul point où ce style diffère de
    /// `VerseHighlightStyle`, dont deux des trois couleurs suivent le thème.
    static let standard = VerseMedallionStyle(
        background: backgroundGreen,
        ink: inkGreen
    )
}

// MARK: - La vue

/// Dessine les pastilles de numéro de verset d'**une** page.
///
/// Elle ne reçoit que les marqueurs de la page affichée : elle n'a pas à savoir
/// quelle page, ni quelle édition.
final class VerseMedallionView: UIView {

    var markers: [VerseMarkers.Marker] = [] {
        didSet {
            guard markers != oldValue else { return }
            setNeedsDisplay()
        }
    }

    var style: VerseMedallionStyle = .standard {
        didSet { setNeedsDisplay() }
    }

    /// Taille de l'image de page, en pixels.
    ///
    /// Indispensable pour la même raison que dans `VerseHighlightView` : la boîte
    /// de page ne se déduit pas de `bounds`, et s'y tromper ne produit aucune
    /// erreur — seulement des pastilles au mauvais endroit. Le Coran 1441 vaut
    /// `1440 × 2320`.
    var imageSize: CGSize = VerseBounds.Source.coran1441.fallbackImageSize {
        didSet {
            guard imageSize != oldValue else { return }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        // `pointerEvents="none"` dans l'original : une pastille ne doit jamais
        // intercepter le toucher, sinon on ne pourrait plus marquer le verset
        // qu'elle annonce.
        isUserInteractionEnabled = false
        // Sans `redraw`, UIKit mettrait le dessin en cache et l'étirerait quand la
        // vue change de taille : les pastilles glisseraient au lieu de se
        // recalculer.
        contentMode = .redraw
        // L'original ne pose aucun libellé sur ces pastilles : quinze bandes de
        // numéros annoncés un par un noieraient la page. Elles restent donc
        // purement visuelles.
        isAccessibilityElement = false
    }

    override func draw(_ rect: CGRect) {
        guard !markers.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }

        let pageWidth = VerseMarkers.pageWidth(in: bounds, imageSize: imageSize)
        guard pageWidth > 0 else { return }

        let borderWidth = pageWidth * VerseMarkers.borderRatio
        let font = UIFont.systemFont(ofSize: pageWidth * VerseMarkers.fontRatio)

        for marker in markers {
            let box = VerseMarkers.medallionRect(for: marker, in: bounds, imageSize: imageSize)
            guard box.width > 0 else { continue }

            let path = UIBezierPath(ovalIn: box).cgPath

            context.setFillColor(style.background.cgColor)
            context.addPath(path)
            context.fillPath()

            if borderWidth > 0 {
                context.setStrokeColor(style.ink.cgColor)
                context.setLineWidth(borderWidth)
                context.addPath(path)
                context.strokePath()
            }

            drawNumber(marker.ayah, in: box, font: font)
        }
    }

    /// Le numéro du verset, centré sur sa pastille.
    ///
    /// Centré sur la boîte du glyphe, et non sur la ligne : `size(withAttributes:)`
    /// rend la hauteur de ligne de la police, qui inclut les ascendantes et les
    /// descendantes. La boîte du glyphe est ce qui se voit.
    private func drawNumber(_ ayah: Int, in box: CGRect, font: UIFont) {
        let text = VerseMarkers.easternArabicNumerals(ayah) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.ink,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

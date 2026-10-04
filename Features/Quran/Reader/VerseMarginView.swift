// VerseMarginView.swift
// Repères de progression de séance dans la marge d'une page du Moushaf.
//
// Correspondance : `MushafPage.tsx:53` de l'application React Native.
//
// POURQUOI UNE VUE SÉPARÉE
//   Le rail et les pastilles se posent sur la page, mais leur position se
//   calcule en fractions de page — un calcul que `MarginAnnotations` fait et
//   éprouve sans rien dessiner. Cette vue ne fait que tracer ce qu'il rend :
//   elle n'a aucune arithmétique de position à elle.
//
// ELLE SE DESSINE DANS LA VUE ENTIÈRE, PAS DANS LA BOÎTE DE PAGE
//   C'est la différence avec `VerseHighlightView`, et elle est voulue : le
//   diamètre d'une pastille dépend de la place libre À GAUCHE de la page
//   (`diameter = min(24, max(8, edge - 4))`). Une vue posée sur la boîte de
//   page aurait perdu cette place, et le diamètre serait faux. Le `padding`
//   intérieur de l'original (`zipped ? 0 : 2`) lui est donc passé à part.
//
// LES DEUX COULEURS NE SUIVENT PAS LE THÈME
//   Comme le rouge du verset difficile et le vert de la pastille de numéro, la
//   séance est un **signal** : `#246B48` dans les quatre thèmes de l'original
//   (`src/ui/theme.tsx:15`), et la pastille non validée est blanche.

import UIKit

// MARK: - Couleurs

/// Les deux couleurs d'un repère de séance — `MushafPage.tsx:53`.
struct VerseMarginStyle {

    /// Le rail et la bordure des pastilles — `sessionColor={colors.review}`.
    var rail: UIColor

    /// Le fond d'une pastille **non** validée — `backgroundColor: 'white'`.
    var pending: UIColor

    /// `colors.review` — `#246B48`, `src/ui/theme.tsx:15`.
    ///
    /// La valeur est fixe : `review` est ajouté APRÈS les palettes
    /// (`export const colors={...palettes.white, …, review:'#246B48'}`), donc
    /// elle ne dépend pas du thème. Comme le rouge d'un verset difficile, c'est
    /// un signal et non une décoration. Il n'y a donc **pas** de fabrique
    /// prenant une `Palette` : elle ignorerait son argument.
    static let sessionGreen = UIColor(
        red: 0x24 / 255,
        green: 0x6B / 255,
        blue: 0x48 / 255,
        alpha: 1
    )

    static let standard = VerseMarginStyle(rail: sessionGreen, pending: .white)
}

// MARK: - La vue

/// Dessine le rail et les pastilles de séance d'**une** page.
///
/// Elle ne reçoit que les régions de la page affichée et la séance à
/// représenter : elle n'a pas à savoir quelle page, ni quelle édition, ni
/// pourquoi une séance est ouverte.
final class VerseMarginView: UIView {

    /// Les régions de la page, en fractions de page.
    var regions: [MarginAnnotations.Region] = [] {
        didSet {
            guard regions != oldValue else { return }
            setNeedsDisplay()
            setNeedsLayout()
        }
    }

    /// La séance à représenter. `nil` — ou une plage qui ne touche pas cette
    /// page — et rien n'est dessiné : c'est le cas d'une lecture libre.
    var session: MarginAnnotations.Session? {
        didSet {
            guard session != oldValue else { return }
            setNeedsDisplay()
            setNeedsLayout()
        }
    }

    /// Marge intérieure de l'original — `MushafPage.tsx:44` :
    /// `padding = zipped ? 0 : 2`. Zéro pour le Coran 1441, deux pour le Coran
    /// de Médine.
    var padding: CGFloat = 0 {
        didSet {
            guard padding != oldValue else { return }
            setNeedsDisplay()
        }
    }

    /// Les deux couleurs. Le style est posé une fois par mise à jour ;
    /// `setNeedsDisplay` ne provoque qu'un seul redessin par image, même
    /// appelé plusieurs fois.
    var style: VerseMarginStyle = .standard {
        didSet { setNeedsDisplay() }
    }

    /// Taille de l'image de page, en pixels.
    ///
    /// Indispensable pour la même raison que dans `VerseHighlightView` : la
    /// boîte de page ne se déduit pas de `bounds`, et s'y tromper ne produit
    /// aucune erreur — seulement un rail et des pastilles au mauvais endroit.
    var imageSize: CGSize = VerseBounds.Source.medine.fallbackImageSize {
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
        // `pointerEvents="none"` dans l'original : un repère de marge ne doit
        // jamais intercepter le toucher, sinon on ne pourrait plus ni marquer un
        // verset ni poser un signet sur la zone qu'il recouvre.
        isUserInteractionEnabled = false
        // Sans `redraw`, UIKit mettrait le dessin en cache et l'étirerait quand
        // la vue change de taille : les repères glisseraient au lieu de se
        // recalculer.
        contentMode = .redraw
        // La vue elle-même n'est pas un élément : ce sont les pastilles qui le
        // sont, une par ligne — voir `rebuildAccessibilityElements`.
        isAccessibilityElement = false
    }

    // MARK: Dessin

    override func draw(_ rect: CGRect) {
        guard let layout = currentLayout(), let context = UIGraphicsGetCurrentContext() else { return }

        // Le rail : un trait d'un point, à 35 % d'opacité — `opacity: .35`.
        context.setFillColor(style.rail.withAlphaComponent(0.35).cgColor)
        context.fill(layout.rail)

        for marker in layout.markers {
            draw(marker, in: context)
        }
    }

    /// Une pastille : le fond, la bordure d'un point, puis le texte centré.
    private func draw(_ marker: MarginAnnotations.Marker, in context: CGContext) {
        let path = UIBezierPath(
            roundedRect: marker.rect,
            cornerRadius: marker.cornerRadius
        ).cgPath

        // Fond : plein quand TOUS les versets de la ligne sont validés, blanc
        // sinon — `backgroundColor: done ? sessionColor : 'white'`.
        context.setFillColor(marker.done ? style.rail.cgColor : style.pending.cgColor)
        context.addPath(path)
        context.fillPath()

        context.setStrokeColor(style.rail.cgColor)
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()

        drawLabel(marker)
    }

    /// Le ou les numéros de verset, centrés dans la pastille.
    ///
    /// La police est la police système, comme le `Text` de React Native, et le
    /// texte se replie sur plusieurs lignes quand la pastille en porte
    /// plusieurs — `« 3·4 »`. Le centrage vertical se fait sur la hauteur
    /// MESURÉE, pas sur celle de la boîte : sans quoi une pastille passée à la
    /// ligne collerait son texte en haut.
    private func drawLabel(_ marker: MarginAnnotations.Marker) {
        let attributes = Self.textAttributes(
            fontSize: marker.fontSize,
            color: marker.done ? .white : style.rail
        )
        let text = marker.label as NSString
        // La bordure est d'un point, et elle est DANS la boîte : le texte se
        // dispose sur `diameter - 2` — c'est aussi la largeur avec laquelle la
        // hauteur de la boîte a été calculée.
        let box = marker.rect.insetBy(dx: 1, dy: 1)
        guard box.width > 0, box.height > 0 else { return }

        let measured = text.boundingRect(
            with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        text.draw(
            with: CGRect(
                x: box.minX,
                y: box.minY + max(0, (box.height - measured.height) / 2),
                width: box.width,
                height: measured.height
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
    }

    // MARK: Accessibilité

    /// Une pastille = un élément, avec le libellé de l'original :
    /// `Verset 3, Verset 4 validé`.
    ///
    /// LIMITE CONNUE, ET ELLE N'EST PAS ICI : sur une page du Coran 1441, le
    /// contrôleur fait de la vue de page ENTIÈRE un élément d'accessibilité
    /// (`isAccessibilityElement`), donc les enfants ne sont pas parcourus et ces
    /// pastilles ne sont pas atteignables au lecteur d'écran. Le défaut vaut
    /// aussi pour les mises en évidence et les pastilles de numéro. Sur le Coran
    /// de Médine, l'élément est l'image et non le conteneur, donc ces pastilles
    /// *devraient* être parcourues — cela n'a pas été vérifié sur un appareil, et
    /// reste à faire.
    private func rebuildAccessibilityElements() {
        guard let layout = currentLayout(), !layout.isEmpty else {
            accessibilityElements = nil
            return
        }
        accessibilityElements = layout.markers.map { marker in
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityFrameInContainerSpace = marker.rect
            element.accessibilityLabel = marker.items
                .map { "Verset \($0.ayah)" + ($0.done ? " validé" : "") }
                .joined(separator: ", ")
            element.accessibilityTraits = .staticText
            return element
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Les cadres des éléments se recalculent avec la taille de la vue.
        rebuildAccessibilityElements()
    }

    // MARK: Aides

    /// Le calcul courant, ou `nil` s'il n'y a rien à dessiner.
    private func currentLayout() -> MarginAnnotations.Layout? {
        guard let session, !regions.isEmpty else { return nil }
        let layout = MarginAnnotations.layout(
            regions: regions,
            start: session.range.start,
            end: session.range.end,
            through: session.through,
            in: bounds,
            imageSize: imageSize,
            padding: padding,
            textHeight: Self.measuredTextHeight
        )
        return layout.isEmpty ? nil : layout
    }

    private static func textAttributes(
        fontSize: CGFloat,
        color: UIColor
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    }

    /// La hauteur du texte d'une pastille — injectée dans `MarginAnnotations`,
    /// qui ne connaît pas UIKit.
    ///
    /// Arrondie au point SUPÉRIEUR : une boîte plus courte que son texte
    /// tronquerait la dernière ligne, ce qui est exactement le défaut que ce
    /// calcul doit éviter.
    private static func measuredTextHeight(_ label: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard maxWidth > 0, !label.isEmpty else { return 0 }
        let measured = (label as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes(fontSize: fontSize, color: .black),
            context: nil
        )
        return ceil(measured.height)
    }
}

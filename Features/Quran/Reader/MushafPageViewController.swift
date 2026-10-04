// MushafPageViewController.swift
// Lecteur du Moushaf, en UIKit.
//
// POURQUOI UIKIT ICI ET PAS SWIFTUI PUR
//   `UIPageViewController` fournit le geste de balayage natif, la transition
//   entre pages et le maintien en mémoire des seules pages voisines. En SwiftUI
//   pur, il faudrait reconstruire ce comportement à la main, et le résultat est
//   moins fluide dès que les images sont grandes (1920 × 3106 pour le Coran de
//   Médine). C'est exactement le cas d'usage prévu par la demande.
//
// DEUX FORMES DE PAGE, ET C'EST LA DIFFÉRENCE QUI COMPTE
//   - Coran de Médine : **une** image par page (1920 × 3106).
//   - Coran 1441      : **quinze** bandes par page (1440 × 232 chacune),
//     empilées à pas constant (`MushafPage.tsx:48`).
//   Afficher une seule bande d'une page du 1441 montrerait le quinzième de la
//   page, et toutes les mises en évidence des autres lignes tomberaient hors de
//   l'image. Les deux formes partagent en revanche la même projection : elle est
//   calculée par `VerseBounds`, jamais ici.
//
// CE QUE CE FICHIER GARANTIT
//   - Préchargement de la page précédente, de la page courante et de la page
//     suivante, et de rien d'autre. Jamais les 604 pages en mémoire.
//   - Centrage vertical réel : la page est centrée dans l'espace disponible par
//     le calcul de la boîte, sans aucune marge haute fixe.
//   - Ratio des pages préservé : jamais d'étirement.
//   - Aucune page blanche : si une page n'est pas disponible — ou n'est
//     disponible qu'en partie — on affiche un texte qui le dit.
//   - Mise en évidence des versets (difficile, signet, lecture) posée par-dessus
//     la page, dans la même boîte qu'elle — voir `VerseHighlightView`.
//   - Repères de progression de séance dans la marge, quand une séance est
//     ouverte — voir `VerseMarginView` et `MarginAnnotations`.

import SwiftUI
import UIKit

// MARK: - Cache de pages

/// Cache d'images borné. `NSCache` libère tout seul sous pression mémoire.
///
/// ATTENTION : la limite de **nombre** compte des images, pas des pages. Une
/// page du Coran de Médine coûte 1 image, une page du Coran 1441 en coûte 15.
/// Une limite de 6 « pages » gardait donc moins d'une page du 1441 — d'où la
/// limite exprimée en pages multipliées par le nombre de bandes.
final class PageImageCache {
    static let shared = PageImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Trois pages (précédente, courante, suivante) dans le pire cas — celui
        // des pages en bandes — plus une petite marge.
        cache.countLimit = 3 * VerseBounds.linesPerPage + 3
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.path as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.path as NSString, cost: image.cost)
    }
}

private extension UIImage {
    var cost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

// MARK: - Une page

final class MushafPageViewController: UIViewController {

    let page: Int
    private let imageURLs: [URL]
    private let banded: Bool
    private let imageSize: CGSize

    private let pageImageView = UIImageView()
    private var bandImageViews: [UIImageView] = []
    private let medallionView = VerseMedallionView()
    private let highlightView = VerseHighlightView()
    private let marginView = VerseMarginView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let placeholderLabel = UILabel()
    private var loadTask: Task<Void, Never>?

    init(
        page: Int,
        imageURLs: [URL],
        banded: Bool,
        imageSize: CGSize,
        medallions: [VerseMarkers.Marker] = [],
        highlights: [VerseBounds.Highlight] = [],
        marginRegions: [MarginAnnotations.Region] = [],
        session: MarginAnnotations.Session? = nil,
        style: VerseHighlightStyle = .from(Theme.white)
    ) {
        self.page = page
        self.imageURLs = imageURLs
        self.banded = banded
        self.imageSize = imageSize
        super.init(nibName: nil, bundle: nil)
        medallionView.imageSize = imageSize
        medallionView.markers = medallions
        highlightView.imageSize = imageSize
        highlightView.highlights = highlights
        highlightView.style = style
        marginView.imageSize = imageSize
        marginView.padding = banded ? 0 : 2
        marginView.regions = marginRegions
        marginView.session = session
    }

    /// Met à jour la mise en évidence **sans reconstruire la page**. C'est ce qui
    /// permet de marquer un verset comme difficile et de voir le rouge apparaître
    /// immédiatement, sans que l'image soit rechargée ni la page reconstruite.
    ///
    /// La séance suit le même chemin : `through` peut avancer pendant que la
    /// page reste affichée, et le rail doit suivre sans recharger l'image.
    ///
    /// `session` n'a **pas** de valeur par défaut, et c'est voulu : un appel qui
    /// l'omettrait effacerait silencieusement les repères d'une séance ouverte.
    func apply(
        highlights: [VerseBounds.Highlight],
        style: VerseHighlightStyle,
        session: MarginAnnotations.Session?
    ) {
        highlightView.style = style
        highlightView.highlights = highlights
        marginView.session = session
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    deinit { loadTask?.cancel() }

    // MARK: Mise en page

    /// Marge autour de la page — `MushafPage.tsx:44` : `padding = zipped ? 0 : 2`.
    /// Le Coran 1441 occupe toute la largeur ; le Coran de Médine laisse 2 points.
    private var pagePadding: CGFloat { banded ? 0 : 2 }

    /// La zone où la page a le droit de se dessiner.
    private var layoutBox: CGRect { view.bounds.insetBy(dx: pagePadding, dy: pagePadding) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true

        if banded {
            // Quinze bandes empilées. Chacune est un `UIImageView` : leur
            // position est calculée par `VerseBounds.bandRect`, donc la même
            // fonction que celle qui projette les mises en évidence. Deux
            // calculs séparés finiraient par diverger.
            bandImageViews = (0..<VerseBounds.linesPerPage).map { _ in
                let imageView = UIImageView()
                imageView.contentMode = .scaleAspectFit
                imageView.clipsToBounds = true
                view.addSubview(imageView)
                return imageView
            }
            // Une page en bandes est un seul élément d'accessibilité : quinze
            // images annoncées séparément seraient quinze fois la même page.
            view.isAccessibilityElement = true
            view.accessibilityLabel = "Page \(page) du Moushaf"
        } else {
            pageImageView.contentMode = .scaleAspectFit
            pageImageView.clipsToBounds = true
            pageImageView.isAccessibilityElement = true
            pageImageView.accessibilityLabel = "Page \(page) du Moushaf"
            view.addSubview(pageImageView)
        }

        // Les pastilles de numéro de verset, puis les mises en évidence : l'ordre
        // d'ajout est l'ordre de dessin, et l'original place les pastilles dans
        // le conteneur des bandes, avant les rectangles. Une mise en évidence
        // passe donc **au-dessus** de la pastille qu'elle recouvre.
        //
        // Comme la mise en évidence, elle couvre exactement la zone de la page et
        // calcule elle-même la boîte où l'image est dessinée — donc aucune
        // contrainte de taille à lui donner.
        medallionView.frame = layoutBox
        view.addSubview(medallionView)

        // La mise en évidence couvre exactement la zone de la page : elle
        // calcule elle-même la boîte où l'image est dessinée, à partir de
        // `imageSize`, et suit donc tout changement de taille sans contrainte
        // supplémentaire. La placer sur `view` plutôt que sur l'image évite
        // d'avoir à choisir *laquelle* des quinze bandes la porte.
        highlightView.frame = layoutBox
        view.addSubview(highlightView)

        // Les repères de séance EN DERNIER : l'ordre d'ajout est l'ordre de
        // dessin, et l'original les place après les mises en évidence et les
        // icônes de signet (`MushafPage.tsx:53`, après `</Pressable>`). Une
        // pastille de séance passe donc au-dessus d'une mise en évidence.
        //
        // EUX SEULS SE DESSINENT DANS LA VUE ENTIÈRE, et non dans la zone de
        // page : le diamètre d'une pastille dépend de la place libre à gauche de
        // la page, que la zone de page aurait déjà retirée. Voir
        // `VerseMarginView`.
        marginView.frame = view.bounds
        view.addSubview(marginView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        placeholderLabel.font = .preferredFont(forTextStyle: .footnote)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.isHidden = true

        view.addSubview(spinner)
        view.addSubview(placeholderLabel)

        // LE POINT CENTRAL DU CENTRAGE VERTICAL :
        // la page est centrée dans l'espace que son conteneur lui laisse, quelle
        // que soit la hauteur de cet espace. Aucune marge haute fixe n'est
        // utilisée : c'est le conteneur (SwiftUI) qui retire la barre d'actions,
        // le mini-lecteur et les zones sûres. La page reste donc centrée entre
        // l'encoche et la barre d'accueil, sur tous les modèles d'iPhone.
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let box = layoutBox
        if banded {
            for line in 0..<bandImageViews.count {
                bandImageViews[line].frame = VerseBounds.bandRect(
                    line: line,
                    in: box,
                    imageSize: imageSize
                )
            }
        } else {
            pageImageView.frame = box
        }
        medallionView.frame = box
        highlightView.frame = box
        // La vue entière, et non `box` : voir `viewDidLoad`.
        marginView.frame = view.bounds
    }

    // MARK: Chargement

    private func load() {
        guard !imageURLs.isEmpty else {
            showPlaceholder(
                banded
                    ? "Le Coran 1441 n'est pas encore installé. Ouvre l'onglet Coran pour le télécharger — le Coran de Médine, lui, reste lisible hors ligne."
                    : "Cette page n'est pas encore disponible hors ligne."
            )
            return
        }
        // Une page du Coran 1441 est faite de quinze bandes : une page à moitié
        // téléchargée ne doit pas s'afficher à moitié, elle doit le dire.
        guard !banded || imageURLs.count == VerseBounds.linesPerPage else {
            showPlaceholder("Cette page du Coran 1441 n'est pas encore téléchargée en entier.")
            return
        }

        let urls = imageURLs
        // Cache d'abord : c'est ce qui rend le balayage instantané.
        let cached = urls.map { PageImageCache.shared.image(for: $0) }
        if cached.allSatisfy({ $0 != nil }) {
            apply(cached.compactMap { $0 })
            return
        }

        spinner.startAnimating()
        loadTask = Task { [weak self] in
            let images = await Self.loadImages(at: urls)
            guard !Task.isCancelled, let self else { return }
            self.spinner.stopAnimating()
            guard images.count == urls.count else {
                self.showPlaceholder("Page indisponible.")
                return
            }
            for (url, image) in zip(urls, images) {
                PageImageCache.shared.store(image, for: url)
            }
            self.apply(images)
        }
    }

    private func apply(_ images: [UIImage]) {
        if banded {
            for (line, image) in images.enumerated() where line < bandImageViews.count {
                bandImageViews[line].image = image
            }
        } else {
            pageImageView.image = images.first
        }
        placeholderLabel.isHidden = true
    }

    private func showPlaceholder(_ message: String) {
        spinner.stopAnimating()
        placeholderLabel.text = message
        placeholderLabel.isHidden = false
    }

    /// Décodage hors du fil principal : une image de 1920 × 3106 ne doit jamais
    /// figer le geste. L'ordre est préservé, et une image qui manque fait
    /// échouer la comparaison de nombre plutôt que de décaler les bandes.
    private static func loadImages(at urls: [URL]) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap { url -> UIImage? in
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                      let image = UIImage(data: data) else { return nil }
                // Force le décodage maintenant, pour que l'affichage soit immédiat.
                return image.preparingForDisplay() ?? image
            }
        }.value
    }
}

// MARK: - Conteneur de pages

/// `UIPageViewController` encapsulé. La transition est de type « page » (glissement
/// horizontal naturel) et le geste de bord gauche reste disponible pour fermer
/// le lecteur, comme dans l'application actuelle.
struct MushafPageController: UIViewControllerRepresentable {

    @Binding var page: Int
    let edition: QuranEdition
    let source: QuranSourceService

    /// Les versets à mettre en évidence, par identifiant. Ce sont les **états**,
    /// pas les rectangles : les rectangles dépendent de la page et de la source,
    /// et c'est le coordinateur qui les calcule pour la page qu'il construit.
    var difficulty: Set<Int> = []
    var bookmarks: Set<Int> = []
    var playing: Int?

    /// La séance à représenter dans la marge, ou `nil` pour une lecture libre.
    ///
    /// C'est la dérivation d'`App.tsx:477-481` qui décide — voir
    /// `MarginAnnotations.session(...)`. Le lecteur la calcule depuis
    /// `ReaderRequest` et l'état, et la passe ici : le contrôleur de pages n'a
    /// pas à savoir pourquoi une séance est ouverte.
    var session: MarginAnnotations.Session?

    var style: VerseHighlightStyle = .from(Theme.white)

    var onPageChange: (Int) -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        controller.setViewControllers(
            [context.coordinator.makePage(page)],
            direction: .forward,
            animated: false
        )
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard let current = controller.viewControllers?.first as? MushafPageViewController else { return }

        // Changement de page piloté par l'extérieur (reprise de lecture, marque-page).
        guard current.page == page else {
            let direction: UIPageViewController.NavigationDirection = page > current.page ? .forward : .reverse
            controller.setViewControllers([context.coordinator.makePage(page)], direction: direction, animated: false)
            return
        }

        // Même page, mais les ensembles ont pu changer : marquer un verset comme
        // difficile, poser ou retirer un signet, lancer une récitation. Sans ce
        // chemin, la mise en évidence ne suivrait qu'au changement de page.
        current.apply(
            highlights: context.coordinator.highlights(for: current.page),
            style: style,
            session: session
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

        var parent: MushafPageController

        init(parent: MushafPageController) {
            self.parent = parent
        }

        /// Les rectangles de la page, projetés nulle part : ils restent en
        /// coordonnées d'image, `VerseHighlightView` les projettera.
        ///
        /// La source compte ici : les deux fichiers n'ont ni les mêmes rectangles
        /// ni la même convention de ligne. Lire les rectangles du Coran de Médine
        /// pour une page du Coran 1441 ne donnerait aucun rectangle — donc aucune
        /// mise en évidence, et rien pour le signaler.
        ///
        /// Une édition dont les rectangles ne sont pas connus ne reçoit **aucune**
        /// mise en évidence, et surtout pas ceux du Coran de Médine : ils
        /// tomberaient à des endroits plausibles sur une image qui n'est pas la
        /// même, ce qui est pire que rien.
        func highlights(for page: Int) -> [VerseBounds.Highlight] {
            guard let source = parent.edition.boundsSource else { return [] }
            return VerseBounds.highlights(
                page: page,
                source: source,
                difficulty: parent.difficulty,
                bookmarks: parent.bookmarks,
                playing: parent.playing
            )
        }

        /// Les pastilles de numéro de verset de la page.
        ///
        /// Même règle, et même source, que les mises en évidence : les marqueurs
        /// annotent les **bandes** du Coran 1441, et leurs fractions se rapportent
        /// à sa page. Une édition dont la géométrie n'est pas connue n'en reçoit
        /// donc aucune — les projeter ailleurs donnerait des pastilles à des
        /// endroits plausibles sur une image qui n'est pas la même.
        ///
        /// Le repli `.medine` du `??` n'est pas un choix d'édition : c'est la
        /// source pour laquelle `VerseMarkers` rend une liste vide, ce qui garde
        /// la fonction totale plutôt que de la faire renvoyer un optionnel.
        func medallions(for page: Int) -> [VerseMarkers.Marker] {
            guard let source = parent.edition.boundsSource else { return [] }
            return VerseMarkers.markers(page: page, source: source)
        }

        /// Les régions de la page, pour les repères de séance.
        ///
        /// Elles ne dépendent PAS de la séance : ce sont les rectangles de la
        /// page, dont `MarginAnnotations` tire les groupes. Les recalculer à
        /// chaque changement de séance serait du travail perdu, mais elles
        /// doivent venir de la **même** source que les mises en évidence — lire
        /// les rectangles du Coran de Médine pour une page du 1441 ne donnerait
        /// aucun repère, et rien pour le signaler.
        func marginRegions(for page: Int) -> [MarginAnnotations.Region] {
            guard let source = parent.edition.boundsSource else { return [] }
            return MarginAnnotations.regions(page: page, source: source)
        }

        func makePage(_ number: Int) -> UIViewController {
            let clamped = min(max(number, 1), QuranSourceService.totalPages)
            let edition = parent.edition
            return MushafPageViewController(
                page: clamped,
                imageURLs: parent.source.imageURLs(for: edition, page: clamped),
                banded: edition == .coran1441,
                imageSize: parent.source.geometry(for: edition).size,
                medallions: medallions(for: clamped),
                highlights: highlights(for: clamped),
                marginRegions: marginRegions(for: clamped),
                session: parent.session,
                style: parent.style
            )
        }

        // MARK: Préchargement des voisines

        /// C'est ce qui supprime le délai perceptible : quand le doigt arrive sur
        /// la page suivante, ses images sont déjà décodées en cache.
        ///
        /// Pour le Coran 1441, cela fait quinze images par voisine. Le cache est
        /// borné en images, pas en pages — voir `PageImageCache`.
        private func preloadNeighbours(of page: Int) {
            let edition = parent.edition
            let expected = edition == .coran1441 ? VerseBounds.linesPerPage : 1
            for offset in [-1, 1] {
                let neighbour = page + offset
                guard neighbour >= 1, neighbour <= QuranSourceService.totalPages else { continue }
                let urls = parent.source.imageURLs(for: edition, page: neighbour)
                // Une page incomplète n'est pas préchargée : elle ne s'affichera
                // pas, et charger ses bandes ne ferait que chasser du cache les
                // pages qui, elles, s'affichent.
                guard urls.count == expected else { continue }
                for url in urls where PageImageCache.shared.image(for: url) == nil {
                    Task.detached(priority: .utility) {
                        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                              let image = UIImage(data: data) else { return }
                        PageImageCache.shared.store(image, for: url)
                    }
                }
            }
        }

        // MARK: DataSource

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? MushafPageViewController, current.page > 1 else { return nil }
            return makePage(current.page - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? MushafPageViewController,
                  current.page < QuranSourceService.totalPages else { return nil }
            return makePage(current.page + 1)
        }

        // MARK: Delegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pageViewController.viewControllers?.first as? MushafPageViewController else { return }
            let number = current.page
            preloadNeighbours(of: number)
            if parent.page != number {
                parent.page = number
                parent.onPageChange(number)
            }
        }
    }
}

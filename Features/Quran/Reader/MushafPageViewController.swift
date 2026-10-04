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
// CE QUE CE FICHIER GARANTIT
//   - Préchargement de la page précédente, de la page courante et de la page
//     suivante, et de rien d'autre. Jamais les 604 pages en mémoire.
//   - Centrage vertical réel : la page est centrée dans l'espace disponible par
//     contraintes, sans aucune marge haute fixe.
//   - Ratio des pages préservé : `scaleAspectFit`, jamais d'étirement.
//   - Aucune page blanche : si une page n'est pas disponible, on affiche un
//     indicateur de chargement.
//   - Mise en évidence des versets (difficile, signet, lecture) posée par-dessus
//     l'image, dans la même boîte qu'elle — voir `VerseHighlightView`.

import SwiftUI
import UIKit

// MARK: - Cache de pages

/// Cache d'images borné. `NSCache` libère tout seul sous pression mémoire.
final class PageImageCache {
    static let shared = PageImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 6 // page précédente, courante, suivante + marge
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
    private let imageURL: URL?
    private let imageView = UIImageView()
    private let highlightView = VerseHighlightView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let placeholderLabel = UILabel()
    private var loadTask: Task<Void, Never>?

    init(
        page: Int,
        imageURL: URL?,
        highlights: [VerseBounds.Highlight] = [],
        style: VerseHighlightStyle = .from(Theme.white)
    ) {
        self.page = page
        self.imageURL = imageURL
        super.init(nibName: nil, bundle: nil)
        highlightView.highlights = highlights
        highlightView.style = style
    }

    /// Met à jour la mise en évidence **sans reconstruire la page**. C'est ce qui
    /// permet de marquer un verset comme difficile et de voir le rouge apparaître
    /// immédiatement, sans que l'image soit rechargée ni la page reconstruite.
    func apply(highlights: [VerseBounds.Highlight], style: VerseHighlightStyle) {
        highlightView.style = style
        highlightView.highlights = highlights
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Page \(page) du Moushaf"

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        placeholderLabel.font = .preferredFont(forTextStyle: .footnote)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.isHidden = true

        view.addSubview(imageView)
        view.addSubview(spinner)
        view.addSubview(placeholderLabel)

        // La mise en évidence est posée PAR-DESSUS l'image, dans l'imageView :
        // elle partage donc exactement sa boîte, et suit ses changements de
        // taille sans qu'aucune contrainte supplémentaire soit nécessaire.
        // `imageView.clipsToBounds` garantit en prime qu'un rectangle ne peut pas
        // déborder de la page.
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(highlightView)

        // LE POINT CENTRAL DU CENTRAGE VERTICAL :
        // la page est centrée dans l'espace que son conteneur lui laisse, quelle
        // que soit la hauteur de cet espace. Aucune marge haute fixe n'est
        // utilisée : c'est le conteneur (SwiftUI) qui retire la barre d'actions,
        // le mini-lecteur et les zones sûres. La page reste donc centrée entre
        // l'encoche et la barre d'accueil, sur tous les modèles d'iPhone.
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            imageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            highlightView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            highlightView.topAnchor.constraint(equalTo: imageView.topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        load()
    }

    private func load() {
        guard let imageURL else {
            placeholderLabel.text = "Cette page n'est pas encore disponible hors ligne."
            placeholderLabel.isHidden = false
            return
        }
        // Cache d'abord : c'est ce qui rend le balayage instantané.
        if let cached = PageImageCache.shared.image(for: imageURL) {
            imageView.image = cached
            return
        }
        spinner.startAnimating()
        loadTask = Task { [weak self] in
            let image = await Self.loadImage(at: imageURL)
            guard !Task.isCancelled, let self else { return }
            self.spinner.stopAnimating()
            if let image {
                PageImageCache.shared.store(image, for: imageURL)
                self.imageView.image = image
            } else {
                self.placeholderLabel.text = "Page indisponible."
                self.placeholderLabel.isHidden = false
            }
        }
    }

    /// Décodage hors du fil principal : une image de 1920 × 3106 ne doit jamais
    /// figer le geste.
    private static func loadImage(at url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            guard let image = UIImage(data: data) else { return nil }
            // Force le décodage maintenant, pour que l'affichage soit immédiat.
            return image.preparingForDisplay() ?? image
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
    /// pas les rectangles : les rectangles dépendent de la page, et c'est le
    /// coordinateur qui les calcule pour la page qu'il construit.
    var difficulty: Set<Int> = []
    var bookmarks: Set<Int> = []
    var playing: Int?

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
            style: style
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
        func highlights(for page: Int) -> [VerseBounds.Highlight] {
            VerseBounds.highlights(
                page: page,
                difficulty: parent.difficulty,
                bookmarks: parent.bookmarks,
                playing: parent.playing
            )
        }

        func makePage(_ number: Int) -> UIViewController {
            let clamped = min(max(number, 1), QuranSourceService.totalPages)
            // `imageURL` est `nonisolated` sur l'acteur : l'appel est sûr ici.
            let url = Self.url(for: clamped, edition: parent.edition, source: parent.source)
            return MushafPageViewController(
                page: clamped,
                imageURL: url,
                highlights: highlights(for: clamped),
                style: parent.style
            )
        }

        private static func url(for page: Int, edition: QuranEdition, source: QuranSourceService) -> URL? {
            switch edition {
            case .medine:
                return Bundle.main.url(
                    forResource: String(format: "page%03d", page),
                    withExtension: "png",
                    subdirectory: "Mushaf"
                ) ?? Bundle.main.url(forResource: String(format: "page%03d", page), withExtension: "png")
            case .coran1441:
                let base = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask).first
                let directory = base?.appendingPathComponent("quran/coran_1441", isDirectory: true)
                let candidate = directory?.appendingPathComponent(String(format: "%03d-01.png", page))
                if let candidate, FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                return nil
            default:
                return nil
            }
        }

        // MARK: Préchargement des voisines

        /// C'est ce qui supprime le délai perceptible : quand le doigt arrive sur
        /// la page suivante, son image est déjà décodée en cache.
        private func preloadNeighbours(of page: Int) {
            for offset in [-1, 1] {
                let neighbour = page + offset
                guard neighbour >= 1, neighbour <= QuranSourceService.totalPages else { continue }
                guard let url = Self.url(for: neighbour, edition: parent.edition, source: parent.source),
                      PageImageCache.shared.image(for: url) == nil else { continue }
                Task.detached(priority: .utility) {
                    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                          let image = UIImage(data: data) else { return }
                    PageImageCache.shared.store(image, for: url)
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

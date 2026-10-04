// QuranSourceService.swift
// Accès aux éditions du Coran.
//
// Deux éditions sont câblées dans cette première étape, exactement celles
// demandées :
//   - « Coran de Médine »   (identifiant stocké : traditional) — 604 pages PNG
//     embarquées dans Resources/Mushaf, 1920 × 3106.
//   - « Coran 1441 »        (identifiant stocké : coran_1441) — 9060 images de
//     lignes (604 pages × 15), 1440 × 2320, téléchargées à la demande comme le
//     fait déjà l'application React Native.
//
// Les identifiants sont ceux du document `reader.mushaf` partagé : un
// utilisateur qui lisait le Coran 1441 dans React Native doit retrouver le
// Coran 1441 ici.
//
// Les éditions « Tawjeed test 2 » et « Medine Test » mentionnées dans la demande
// ne sont PAS encore présentes dans le dépôt de référence ; l'énumération est
// faite pour les accueillir sans rien casser (`case tawjeedTest2`, etc. à
// ajouter une fois les ressources fournies).

import Foundation
import CoreGraphics

public enum QuranEdition: String, CaseIterable, Sendable {
    case medine = "traditional"
    case coran1441 = "coran_1441"
    case tajweed = "tajweed"
    case tajweedPages = "tajweedPages"
    case coranTest = "coranTest"

    public var label: String {
        switch self {
        case .medine: return "Coran de Médine"
        case .coran1441: return "Coran 1441"
        case .tajweed: return "Lecture simplifiée"
        case .tajweedPages: return "Moushaf Tajwid"
        case .coranTest: return "Coran avec règles de Tajwid"
        }
    }

    /// Éditions réellement lisibles dans cette version.
    public var isAvailable: Bool {
        switch self {
        case .medine, .coran1441: return true
        case .tajweed, .tajweedPages, .coranTest: return false
        }
    }

    public static var available: [QuranEdition] {
        allCases.filter(\.isAvailable)
    }

    /// L'édition affichée quand celle qui est **enregistrée** ne peut pas être
    /// rendue par cette application.
    ///
    /// Le Coran de Médine est le seul repli possible : ses 604 pages sont dans
    /// le paquet, alors que le Coran 1441 exige une installation de 102 Mo. Se
    /// replier sur une édition non installée remplacerait un lecteur faux par un
    /// lecteur vide — deux défauts au lieu d'un.
    public static let fallback: QuranEdition = .medine

    /// L'édition que le lecteur doit **afficher**, pour une préférence
    /// enregistrée donnée.
    ///
    /// POURQUOI CETTE FONCTION EXISTE
    ///   L'application d'origine ouvre sur `reader.mushaf == "coranTest"`
    ///   (`src/core/program.ts:57`) : c'est sa valeur par défaut, donc celle de
    ///   **tout** utilisateur qui n'a jamais touché au choix d'affichage. Cette
    ///   édition est rendue par une page HTML dans un WebView
    ///   (`src/coranTest/html.ts`) avec 607 polices `.woff2` — une chaîne de
    ///   rendu que cette application n'a pas. Résoudre la préférence telle quelle
    ///   ouvrait donc le lecteur sur une édition sans images : chaque page
    ///   affichait « Cette page n'est pas encore disponible hors ligne », pour
    ///   tout le monde, dès la première ouverture.
    ///
    /// CE QUE CETTE FONCTION NE FAIT PAS
    ///   Elle ne réécrit **pas** la préférence enregistrée. `reader.mushaf` reste
    ///   `coranTest` dans le document synchronisé, donc l'application React
    ///   Native retrouve son édition de Tajwid. Le repli est une décision
    ///   d'**affichage**, pas une correction de données : réécrire la préférence
    ///   changerait ce que voit l'autre application.
    public static func displayed(stored: String?) -> QuranEdition {
        guard let stored, let edition = QuranEdition(rawValue: stored) else { return fallback }
        return edition.isAvailable ? edition : fallback
    }

    /// La source de rectangles de versets qui correspond à cette édition.
    ///
    /// `nil` veut dire « on ne sait pas où sont les versets sur ces pages » — et
    /// non « ce sont ceux du Coran de Médine ». Les éditions de Tajwid ont leurs
    /// propres fichiers (`mushaf-tajweed-bounds.json`), non repris à ce stade :
    /// leur appliquer les rectangles du Coran de Médine placerait les mises en
    /// évidence à des endroits plausibles sur une image différente.
    public var boundsSource: VerseBounds.Source? {
        switch self {
        case .medine: return .medine
        case .coran1441: return .coran1441
        case .tajweed, .tajweedPages, .coranTest: return nil
        }
    }
}

public struct PageGeometry: Sendable {
    public var width: CGFloat
    public var height: CGFloat

    /// Dimensions réelles des pages du Coran de Médine.
    public static let medine = PageGeometry(width: 1920, height: 3106)
    /// Dimensions réelles des pages du Coran 1441.
    public static let coran1441 = PageGeometry(width: 1440, height: 2320)

    public var size: CGSize { CGSize(width: width, height: height) }
}

public actor QuranSourceService {

    public static let totalPages = 604

    /// Nom du dossier où sont installées les 9 060 bandes du Coran 1441, sous le
    /// dossier de téléchargement.
    ///
    /// Une seule définition, parce que trois endroits s'accordent sur ce nom :
    /// le lecteur pour trouver une image (`imageURLs`), le compte des pages
    /// installées (`downloadedPageCount`), et l'installeur pour écrire. Deux
    /// littéraux qui doivent coïncider finissent par diverger — et la divergence
    /// serait **silencieuse** : l'installeur écrirait dans un dossier, le lecteur
    /// chercherait dans un autre, et l'écran resterait vide alors que le
    /// téléchargement aurait réussi.
    public static let coran1441FolderName = "coran_1441"

    /// L'archive publiée des pages du Coran 1441 — même adresse que celle
    /// qu'utilise l'application React Native (`src/services/quranDownload.ts:5`).
    ///
    /// Constante statique : elle ne dépend d'aucun état, et la lire ne doit pas
    /// exiger de construire le service.
    public static let coran1441ArchiveURL = URL(
        string: "https://files.quran.app/hafs/madani_1441/zips/images_1440.zip"
    )

    private let fileManager = FileManager.default
    private let downloadDirectory: URL
    /// Nombre de pages gardées en mémoire. Volontairement petit : le lecteur
    /// précharge la page précédente, la courante et la suivante, jamais les 604.
    private let memoryCache = NSCache<NSString, NSData>()

    public init() {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        downloadDirectory = base.appendingPathComponent("quran", isDirectory: true)
        memoryCache.countLimit = 12
    }

    public nonisolated func geometry(for edition: QuranEdition) -> PageGeometry {
        switch edition {
        case .coran1441: return .coran1441
        default: return .medine
        }
    }

    /// Les images d'une page, dans l'ordre.
    ///
    /// **Une** pour le Coran de Médine, **quinze** pour le Coran 1441 : une page
    /// du 1441 n'est pas une image mais quinze bandes empilées
    /// (`MushafPage.tsx:48`). Rendre une seule de ces bandes afficherait la
    /// quinzième partie de la page, et les mises en évidence des autres lignes
    /// tomberaient hors de l'image.
    ///
    /// Seules les images **présentes** sont rendues : une page à moitié
    /// téléchargée donne donc une liste incomplète, et c'est à l'appelant de
    /// décider quoi en faire — l'afficher en partie, ou dire qu'elle manque.
    ///
    /// `nonisolated` à dessein : le calcul ne touche que des valeurs immuables
    /// (`downloadDirectory`, `Bundle.main`) et doit pouvoir être appelé depuis
    /// la mise en page, qui est synchrone.
    public nonisolated func imageURLs(for edition: QuranEdition, page: Int) -> [URL] {
        guard page >= 1, page <= Self.totalPages else { return [] }
        switch edition {
        case .medine:
            let url = Bundle.main.url(
                forResource: String(format: "page%03d", page),
                withExtension: "png",
                subdirectory: "Mushaf"
            ) ?? Bundle.main.url(
                forResource: String(format: "page%03d", page),
                withExtension: "png"
            )
            return url.map { [$0] } ?? []
        case .coran1441:
            // Le Coran 1441 est découpé en 15 lignes par page : « 001-01.png ».
            let directory = downloadDirectory
                .appendingPathComponent(Self.coran1441FolderName, isDirectory: true)
            return (0..<VerseBounds.linesPerPage).compactMap { index in
                let candidate = directory.appendingPathComponent(
                    String(format: "%03d-%02d.png", page, index + 1)
                )
                return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
            }
        default:
            return []
        }
    }

    /// Chemin de l'image d'une page. `nil` si la ressource n'est pas disponible
    /// localement — l'appelant décide alors d'afficher un état de chargement,
    /// jamais une page blanche.
    ///
    /// Pour le Coran 1441, la première des quinze bandes : sert à savoir si la
    /// page est là, pas à l'afficher. `imageURLs` est la forme qui rend la page.
    public nonisolated func imageURL(for edition: QuranEdition, page: Int) -> URL? {
        imageURLs(for: edition, page: page).first
    }

    /// Vérifie qu'une page entière est présente hors ligne.
    public func isAvailableOffline(_ edition: QuranEdition, page: Int) -> Bool {
        imageURL(for: edition, page: page) != nil
    }

    /// Nombre de pages téléchargées pour le Coran 1441.
    public func downloadedPageCount() -> Int {
        let directory = downloadDirectory.appendingPathComponent(Self.coran1441FolderName, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let pages = Set(files.compactMap { name -> Int? in
            guard let prefix = name.split(separator: "-").first else { return nil }
            return Int(prefix)
        })
        return pages.count
    }

    /// Le dossier de téléchargement, où l'installeur écrit le Coran 1441.
    ///
    /// `cacheDirectory()` existait déjà ; c'est la forme asynchrone qui donne
    /// accès au dossier depuis l'extérieur de l'acteur, sans ajouter une seconde
    /// définition du chemin.
    public func cacheDirectory() -> URL { downloadDirectory }
}

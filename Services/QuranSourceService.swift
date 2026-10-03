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
}

public struct PageGeometry: Sendable {
    public var width: CGFloat
    public var height: CGFloat

    /// Dimensions réelles des pages du Coran de Médine.
    public static let medine = PageGeometry(width: 1920, height: 3106)
    /// Dimensions réelles des pages du Coran 1441.
    public static let coran1441 = PageGeometry(width: 1440, height: 2320)
}

public actor QuranSourceService {

    public static let totalPages = 604

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

    /// Chemin de l'image d'une page. `nil` si la ressource n'est pas disponible
    /// localement — l'appelant décide alors d'afficher un état de chargement,
    /// jamais une page blanche.
    public func imageURL(for edition: QuranEdition, page: Int) -> URL? {
        guard page >= 1, page <= Self.totalPages else { return nil }
        switch edition {
        case .medine:
            return Bundle.main.url(
                forResource: String(format: "page%03d", page),
                withExtension: "png",
                subdirectory: "Mushaf"
            ) ?? Bundle.main.url(
                forResource: String(format: "page%03d", page),
                withExtension: "png"
            )
        case .coran1441:
            // Le Coran 1441 est découpé en 15 lignes par page : « 001-01.png ».
            let directory = downloadDirectory
                .appendingPathComponent("coran_1441", isDirectory: true)
            let first = directory.appendingPathComponent(String(format: "%03d-01.png", page))
            return fileManager.fileExists(atPath: first.path) ? first : nil
        default:
            return nil
        }
    }

    /// Vérifie qu'une page entière est présente hors ligne.
    public func isAvailableOffline(_ edition: QuranEdition, page: Int) -> Bool {
        imageURL(for: edition, page: page) != nil
    }

    /// Nombre de pages téléchargées pour le Coran 1441.
    public func downloadedPageCount() -> Int {
        let directory = downloadDirectory.appendingPathComponent("coran_1441", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let pages = Set(files.compactMap { name -> Int? in
            guard let prefix = name.split(separator: "-").first else { return nil }
            return Int(prefix)
        })
        return pages.count
    }

    /// Pages du Coran 1441 : archive publiée par la même source que celle
    /// utilisée par l'application React Native (`src/services/quranDownload.ts:5`).
    public nonisolated var coran1441ArchiveURL: URL? {
        URL(string: "https://files.quran.app/hafs/madani_1441/zips/images_1440.zip")
    }

    public func cacheDirectory() -> URL { downloadDirectory }
}

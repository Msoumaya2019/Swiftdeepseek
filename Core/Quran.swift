// Quran.swift
// Port de `src/core/quran.ts`.
//
// Les tables sont chargées depuis les ressources embarquées (copiées du dépôt
// de référence, mêmes fichiers, mêmes octets) :
//   Resources/Data/meta.json    -> surahs, juzs, quarters
//   Resources/Data/verses.json  -> texte uthmani (Tanzil, CC BY 3.0)
//   Resources/Data/pages.json   -> page -> premier/dernier verset

import Foundation

public struct Verse: Codable, Sendable {
    public let surah: Int
    public let ayah: Int
    public let text: String
}

public struct Surah: Codable, Sendable {
    public let number: Int
    public let name: String
    public let meaning: String?
    public let arabic: String?
    public let start: Int
    public let end: Int
    public let count: Int
    public let isMeccan: Bool?
}

public struct Division: Codable, Sendable {
    public let number: Int
    public let start: Int
    public let end: Int
}

private struct Meta: Codable {
    let surahs: [Surah]
    let juzs: [Division]
    let quarters: [Division]
}

/// Entrée du fichier `pages.json` : une page, et les identifiants de versets
/// qu'elle contient.
///
/// `public` parce que `Quran.pages` l'est : une propriété publique ne peut pas
/// exposer un type privé. Seul `page` est lu hors de ce fichier
/// (`WeeklyProgress.memorizedPageCount`) ; `first` et `last` restent internes.
public struct PageEntry: Codable {
    public let page: Int
    let first: [Int]
    let last: [Int]
}

public enum Quran {
    // MARK: Données chargées une fois

    public static let verses: [Verse] = load("verses", as: [Verse].self)
    private static let meta: Meta = load("meta", as: Meta.self)
    private static let pageEntries: [PageEntry] = load("pages", as: [PageEntry].self)

    public static var surahs: [Surah] { meta.surahs }
    public static var juzs: [Division] { meta.juzs }
    public static var quarters: [Division] { meta.quarters }
    public static var pages: [PageEntry] { pageEntries }

    /// 60 hizbs dérivés des 240 rub‘ (`src/core/quran.ts:13`).
    public static let hizbs: [Division] = (0..<60).map { index in
        Division(
            number: index + 1,
            start: quarters[index * 4].start,
            end: quarters[index * 4 + 3].end
        )
    }

    /// 120 nisfs dérivés des 240 rub‘ (`src/core/quran.ts:14`).
    public static let halves: [Division] = (0..<120).map { index in
        Division(
            number: index + 1,
            start: quarters[index * 2].start,
            end: quarters[index * 2 + 1].end
        )
    }

    /// Poids d'un verset : nombre de lettres arabes, au moins 1
    /// (`src/core/quran.ts:51`). Sert au calcul du volume d'une portion.
    public static let weights: [Int] = verses.map { verse in
        let count = verse.text.unicodeScalars.filter { scalar in
            scalar.value >= 0x0621 && scalar.value <= 0x064A
        }.count
        return count > 0 ? count : 1
    }

    public static let totalVolume: Int = weights.reduce(0, +)

    // MARK: Conversions

    public static func verseID(surah: Int, ayah: Int) -> Int? {
        guard surah >= 1, surah <= surahs.count else { return nil }
        let entry = surahs[surah - 1]
        guard ayah >= 1, ayah <= entry.count else { return nil }
        return entry.start + ayah - 1
    }

    public static func verseAt(_ id: Int) -> Verse {
        precondition(id >= 1 && id <= verses.count, "Verset hors bornes : \(id)")
        return verses[id - 1]
    }

    public static func surahAt(_ id: Int) -> Surah {
        surahs[verseAt(id).surah - 1]
    }

    /// Recherche dichotomique page -> verset (`src/core/quran.ts:28`).
    public static func pageOf(_ id: Int) -> Int? {
        var left = 0
        var right = pageEntries.count - 1
        while left <= right {
            let mid = (left + right) / 2
            let entry = pageEntries[mid]
            guard let first = verseID(surah: entry.first[0], ayah: entry.first[1]),
                  let last = verseID(surah: entry.last[0], ayah: entry.last[1]) else { break }
            if id < first {
                right = mid - 1
            } else if id > last {
                left = mid + 1
            } else {
                return entry.page
            }
        }
        return nil
    }

    public static func pageRange(_ page: Int) -> VerseRange? {
        guard page >= 1, page <= pageEntries.count else { return nil }
        let entry = pageEntries[page - 1]
        guard let first = verseID(surah: entry.first[0], ayah: entry.first[1]),
              let last = verseID(surah: entry.last[0], ayah: entry.last[1]) else { return nil }
        return VerseRange(start: first, end: last)
    }

    public static func normalizeRanges(_ ranges: [VerseRange]) -> [VerseRange] {
        let sorted = ranges
            .filter { $0.start >= 1 && $0.end <= verses.count && $0.start <= $0.end }
            .sorted { $0.start < $1.start }
        var out: [VerseRange] = []
        for range in sorted {
            if let last = out.last, range.start <= last.end + 1 {
                out[out.count - 1].end = max(last.end, range.end)
            } else {
                out.append(range)
            }
        }
        return out
    }

    public static func expand(_ ranges: [VerseRange]) -> [Int] {
        var ids: [Int] = []
        for range in normalizeRanges(ranges) where range.start <= range.end {
            ids.append(contentsOf: range.start...range.end)
        }
        return ids
    }

    public static func volume(_ ids: [Int]) -> Int {
        ids.reduce(0) { total, id in
            guard id >= 1, id <= weights.count else { return total }
            return total + weights[id - 1]
        }
    }

    public static func reference(_ range: VerseRange) -> String {
        let first = verseAt(range.start)
        let last = verseAt(range.end)
        let firstName = surahAt(range.start).name
        if first.surah == last.surah {
            return "\(firstName) \(first.ayah)–\(last.ayah)"
        }
        return "\(firstName) \(first.ayah) → \(surahAt(range.end).name) \(last.ayah)"
    }

    // MARK: Chargement des ressources

    private static func load<T: Decodable>(_ name: String, as type: T.Type) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            fatalError("""
                Ressource « \(name).json » introuvable ou illisible.
                Elle doit être présente dans Resources/Data et incluse dans la cible.
                """)
        }
        return value
    }
}

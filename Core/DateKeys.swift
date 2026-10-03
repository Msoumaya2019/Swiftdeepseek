// DateKeys.swift
// Port de `dateKey` / `addDays` / `dayOf` / `todayLocal` de
// `src/core/program.ts`.
//
// Contrainte de compatibilité : les dates sont des chaînes « AAAA-MM-JJ »
// interprétées à midi local. Le midi évite les décalages d'heure d'été qui
// feraient changer de jour une date ajoutée de 24 h.

import Foundation

public enum DateKeys {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func key(_ date: Date) -> String {
        formatter.string(from: date)
    }

    public static func today() -> String {
        key(Date())
    }

    /// `new Date("\(key)T12:00:00")` côté JavaScript.
    public static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }

    public static func addDays(_ key: String, _ days: Int) -> String {
        guard let date = date(from: key),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            return key
        }
        return self.key(shifted)
    }

    /// Jour de la semaine, 0 = dimanche (comme `Date.getDay()`).
    public static func dayOf(_ key: String) -> Int {
        guard let date = date(from: key) else { return 0 }
        // Calendar renvoie 1 = dimanche en grégorien.
        return calendar.component(.weekday, from: date) - 1
    }

    /// Lundi 00:01 — début de la semaine d'objectif hebdomadaire.
    /// `addDays(at, -((getDay() + 6) % 7))` comme dans `stats()`.
    public static func weekStart(_ key: String) -> String {
        return addDays(key, -((dayOf(key) + 6) % 7))
    }

    public static func monthStart(_ key: String) -> String {
        String(key.prefix(7)) + "-01"
    }

    /// Horodatage ISO 8601 avec millisecondes, format produit par `toISOString()`.
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    public static func parseISO(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) { return date }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    /// Reproduit `new Date(Math.max(Date.now(), a + 1, b + 1)).toISOString()`.
    public static func maxISO(_ values: [Date?]) -> String {
        var latest = Date()
        for value in values.compactMap({ $0 }) where value >= latest {
            latest = value.addingTimeInterval(0.001)
        }
        return iso(latest)
    }
}

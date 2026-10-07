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

    /// L'heure d'un message, en `HH:mm` locale — ce que l'original obtient par
    /// `new Date(m.created_at).toLocaleTimeString('fr-FR', {hour:'2-digit', minute:'2-digit'})`
    /// (`SocialScreens.tsx:198`).
    ///
    /// Deux choses comptent et sont **mesurées** plutôt que supposées : le
    /// fuseau est celui de l'appareil (pas UTC — l'original n'impose rien), et
    /// le format est **24 heures** avec deux chiffres, ce que la locale `fr-FR`
    /// donne. Un horodatage illisible rend une chaîne vide, jamais l'entrée
    /// brute : un écran ne doit pas afficher une date ISO à la place d'une heure.
    public static func timeText(_ value: String) -> String {
        guard let date = parseISO(value) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// La date **longue** d'un rendez-vous — `toLocaleString('fr-FR')`
    /// (`SocialScreens.tsx:191`). Même règle : fuseau de l'appareil, entrée
    /// illisible rendue vide.
    public static func dateTimeText(_ value: String) -> String {
        guard let date = parseISO(value) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Reproduit `new Date(Math.max(Date.now(), a + 1, b + 1)).toISOString()`.
    ///
    /// Tout se calcule en **millisecondes entières**, comme le modèle JS :
    /// `Date.now()` en rend une, et `toISOString()` n'écrit que trois décimales.
    /// Comparer des `Date` de précision inférieure faisait rendre à `iso()` la
    /// milliseconde de `previous` — donc une valeur **égale**, là où le JS en
    /// rend une strictement supérieure. Mesuré : le run n° 54 a échoué sur
    /// `testResetAdvancesTheTimestamp`, les deux lectures d'horloge étant
    /// tombées dans la **même** milliseconde.
    ///
    /// `now` est injectable pour que ce cas — une fenêtre de moins d'une
    /// milliseconde — se teste sans dépendre de l'horloge.
    public static func maxISO(_ values: [Date?], now: Date = Date()) -> String {
        var latest = milliseconds(now)
        for value in values.compactMap({ $0 }) {
            let candidate = milliseconds(value)
            if candidate >= latest { latest = candidate + 1 }
        }
        return iso(Date(timeIntervalSince1970: Double(latest) / 1000))
    }

    /// La milliseconde entière d'un instant — la granularité du modèle JS.
    private static func milliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}

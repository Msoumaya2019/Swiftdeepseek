// WeeklyProgress.swift
// Port de `src/core/weeklyProgress.ts`.
//
// Deux règles produit à ne pas perdre :
//   - « Programme à venir » n'affiche que les 10 prochains jours, mais ne
//     supprime aucune donnée plus lointaine.
//   - La semaine d'objectif commence le lundi (arithmétique calendaire locale,
//     heure d'été comprise — pas une semaine de millisecondes fixes).

import Foundation

public enum WeeklyProgress {

    /// Un tableau de bord pour l'onglet Progrès et l'objectif hebdomadaire.
    public struct Summary: Equatable, Sendable {
        public var weekStart: String
        public var weekEnd: String
        public var total: Int
        public var done: Int
        public var ratio: Double
    }

    public struct SessionStats: Equatable, Sendable {
        public var today: Int
        public var week: Int
        public var month: Int
        public var days: Int
        public var revisions: Int
        public var hizbs: Int
        public var weeklySessions: Int
    }

    public enum SessionState: String, Sendable {
        case pending, completed, skipped, partiallyCompleted
    }

    public static func scheduledDate(_ session: Session) -> String {
        session.scheduledDate ?? session.date
    }

    /// Uniquement les 10 prochains jours, sans jamais purger le reste.
    public static func upcomingSessions(_ state: AppState, at: String = DateKeys.today()) -> [Session] {
        let limit = DateKeys.addDays(at, 10)
        return state.sessions
            .filter { session in
                session.status == .todo
                    && scheduledDate(session) >= at
                    && scheduledDate(session) <= limit
            }
            .sorted { scheduledDate($0) < scheduledDate($1) }
    }

    public static func weeklyProgress(_ state: AppState, now: Date = Date()) -> Summary {
        let key = DateKeys.key(now)
        let start = DateKeys.weekStart(key)
        let end = DateKeys.addDays(start, 6)
        let sessions = state.sessions.filter { session in
            let date = scheduledDate(session)
            return date >= start && date <= end
        }
        let done = sessions.filter { $0.status == .done }.count
        return Summary(
            weekStart: start,
            weekEnd: end,
            total: sessions.count,
            done: done,
            ratio: sessions.isEmpty ? 0 : Double(done) / Double(sessions.count)
        )
    }

    public static func sessionState(_ state: AppState, _ session: Session) -> SessionState {
        switch session.status {
        case .done: return .completed
        case .postponed: return .skipped
        case .todo:
            // La clé est `learning:<id>` — `studyKey('learning', id)`,
            // `src/core/studyProgress.ts:7`.
            let key = Program.studyKey(.learning, session.id)
            return state.studyProgress?[key]?.status == .partial ? .partiallyCompleted : .pending
        }
    }

    /// Statistiques affichées dans l'onglet Progrès — `stats()`, `src/core/program.ts:258`.
    public static func stats(_ state: AppState, at: String = DateKeys.today()) -> SessionStats {
        let tracked = (state.studyProgress ?? [:]).values.filter { $0.mode == .learning }
        let trackedIDs = Set(tracked.map(\.id))
        let done = state.sessions.filter { session in
            session.status == .done
                && session.completedAt != nil
                && !trackedIDs.contains(session.id)
        }
        let weekStart = DateKeys.weekStart(at)
        let monthStart = DateKeys.monthStart(at)

        func dateOf(_ session: Session) -> String {
            session.completedDate ?? String((session.completedAt ?? "").prefix(10))
        }
        let validations = tracked.flatMap(\.validations)

        func count(from start: String) -> Int {
            let fromSessions = done
                .filter { dateOf($0) >= start && dateOf($0) <= at }
                .reduce(0) { $0 + ($1.end - $1.start + 1) }
            let fromValidations = validations
                .filter { $0.date >= start && $0.date <= at }
                .reduce(0) { $0 + ($1.end - $1.start + 1) }
            return fromSessions + fromValidations
        }

        var distinctDays = Set(done.map(dateOf))
        for validation in validations { distinctDays.insert(validation.date) }

        let completedHizbs = Quran.hizbs.filter { hizb in
            let known = Set(state.memorizedIDs)
            for id in hizb.start...max(hizb.start, hizb.end) where !known.contains(id) {
                return false
            }
            return true
        }.count

        let weeklySessions = done.filter { dateOf($0) >= weekStart }.count
            + tracked.filter { record in
                guard record.status == .completed,
                      let last = record.validations.last else { return false }
                return last.date >= weekStart && last.date <= at
            }.count

        return SessionStats(
            today: count(from: at),
            week: count(from: weekStart),
            month: count(from: monthStart),
            days: distinctDays.count,
            revisions: state.revisions.reduce(0) { $0 + $1.completedCount },
            hizbs: completedHizbs,
            weeklySessions: weeklySessions
        )
    }

    // MARK: Régularité

    /// Les jours d'activité et la série en cours — `activity()`,
    /// `src/ui/MainScreens.tsx:17`.
    public struct Activity: Equatable, Sendable {
        /// Jours (clé `AAAA-MM-JJ`) où au moins un verset a été appris.
        public var dates: Set<String>
        /// Nombre de jours consécutifs jusqu'à aujourd'hui. La série reste
        /// valable si l'activité date d'hier : on ne casse pas la série avant la
        /// fin de la journée en cours.
        public var streak: Int
    }

    public static func activity(_ state: AppState) -> Activity {
        var dates = Set(
            state.sessions
                .filter { $0.status == .done }
                .map { $0.completedDate ?? String(($0.completedAt ?? "").prefix(10)).nilIfEmpty ?? $0.date }
        )
        for record in (state.studyProgress ?? [:]).values where record.mode == .learning {
            for validation in record.validations { dates.insert(validation.date) }
        }

        var streak = 0
        var cursor = DateKeys.today()
        if !dates.contains(cursor) { cursor = DateKeys.addDays(cursor, -1) }
        while dates.contains(cursor) {
            streak += 1
            cursor = DateKeys.addDays(cursor, -1)
        }
        return Activity(dates: dates, streak: streak)
    }

    /// Nombre de pages entièrement mémorisées.
    public static func memorizedPageCount(_ state: AppState) -> Int {
        let known = Set(state.memorizedIDs)
        return Quran.pages.filter { page in
            guard let range = Quran.pageRange(page.page) else { return false }
            return isComplete(range, known)
        }.count
    }

    /// Nombre de Juz’ entièrement mémorisés.
    public static func memorizedJuzCount(_ state: AppState) -> Int {
        let known = Set(state.memorizedIDs)
        return Quran.juzs.filter { isComplete(VerseRange(start: $0.start, end: $0.end), known) }.count
    }

    private static func isComplete(_ range: VerseRange, _ known: Set<Int>) -> Bool {
        for id in range.start...max(range.start, range.end) where !known.contains(id) {
            return false
        }
        return true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// Review.swift
// Port de `src/core/review.ts`.
//
// Cycles de révision : 7 / 14 / 21 / 30 jours (`reviewSettings.cycleDays`).
// Quantités quotidiennes : 1 nisf / 1 hizb / 1 juz / 2 juz
// (`reviewSettings.dailyQuantity`).
// Consolidations : J+1, J+3, J+7 après l'apprentissage d'un verset.
//
// Règle de compatibilité : ces valeurs sont déjà présentes dans les documents
// `user_state.data` des utilisateurs existants. Les libellés de statut et les
// clés (`recent`, `habitual`, `priority`) doivent rester identiques, sinon les
// deux clients ne se comprendront plus.

import Foundation

public enum Review {

    public static let consolidationOffsets = [1, 3, 7]

    public static let cycleOptions = [7, 14, 21, 30]
    public static let quantityOptions = ["nisf", "hizb", "juz", "juz2"]

    public static func reviewsEnabled(_ state: AppState) -> Bool {
        state.reviewSettings?.enabled != false
    }

    public static func reviewCycleDays(_ state: AppState) -> Int {
        state.reviewSettings?.cycleDays ?? 7
    }

    private static func known(_ state: AppState, _ id: Int) -> Bool {
        let mastery = state.knowledge[String(id)]
        return mastery == .perfect || mastery == .review
    }

    /// `age(from,to)` — `src/core/review.ts:12`.
    /// Midi UTC, comme la version JavaScript : c'est un écart de jours, pas de
    /// secondes.
    static func age(from: String, to: String) -> Int {
        func noonUTC(_ key: String) -> Date? {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            var components = DateComponents()
            components.year = parts[0]
            components.month = parts[1]
            components.day = parts[2]
            components.hour = 12
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar.date(from: components)
        }
        guard let start = noonUTC(from), let end = noonUTC(to) else { return 0 }
        return Int(((end.timeIntervalSince(start)) / 86400).rounded())
    }

    private static func idsOf(_ tasks: [VerseRange]) -> [Int] {
        tasks.flatMap { task in Array(task.start...max(task.start, task.end)) }
    }

    private static func isFull(_ set: Set<Int>, _ range: VerseRange) -> Bool {
        for id in range.start...max(range.start, range.end) where !set.contains(id) {
            return false
        }
        return true
    }

    /// Même contrôle, sur une division coranique entière (Hizb, Nisf, Rubu’,
    /// Juz’) — les unités de `Quran` portent `start`/`end` comme une plage.
    private static func isFull(_ set: Set<Int>, _ division: Division) -> Bool {
        isFull(set, VerseRange(start: division.start, end: division.end))
    }

    // MARK: Poids d'un verset dans sa page

    private static var pageVolumes: [Int: Int] = [:]

    /// Part de la page occupée par un verset — `reviewWeight`, `src/core/review.ts:18`.
    /// Un verset court et un verset long ne représentent pas la même charge, et
    /// aucun verset n'est jamais coupé.
    public static func reviewWeight(_ id: Int) -> Double {
        guard let page = Quran.pageOf(id), let range = Quran.pageRange(page) else { return 0 }
        let size: Int
        if let cached = pageVolumes[page] {
            size = cached
        } else {
            size = Quran.volume(Array(range.start...range.end))
            pageVolumes[page] = size
        }
        return Double(Quran.volume([id])) / Double(max(1, size))
    }

    // MARK: Répartition du corpus

    /// `partitionReviewCorpus` — `src/core/review.ts:23`.
    public static func partitionReviewCorpus(_ corpus: [Int], length: Int) -> [[Int]] {
        let ordered = Array(Set(corpus)).sorted()
        let set = Set(ordered)
        guard !ordered.isEmpty, length > 0 else { return [] }

        // La division exacte en unités coraniques entières a la priorité
        // (par exemple 7 hizb / 14 = 1 nisf).
        for units in [Quran.hizbs, Quran.halves, Quran.quarters] {
            let complete = units.filter { isFull(set, $0) }
            if complete.count >= length,
               complete.count % length == 0,
               idsOf(complete).count == ordered.count {
                let count = complete.count / length
                return (0..<length).map { day in
                    idsOf(Array(complete[(day * count)..<((day + 1) * count)]))
                }
            }
        }

        var prefix = [0]
        for id in ordered { prefix.append(prefix[prefix.count - 1] + Quran.volume([id])) }
        let total = prefix[ordered.count]
        var days: [[Int]] = []
        var cursor = 0

        let boundarySets = [Quran.hizbs, Quran.halves, Quran.quarters].map { units in
            Set(units.map(\.end))
        }
        let boundaryIndexes = boundarySets.map { ends in
            ordered.enumerated().compactMap { index, id in ends.contains(id) ? index + 1 : nil }
        }

        for day in 1...length {
            var end = cursor
            if day == length {
                end = ordered.count
            } else {
                let target = Double(total) * Double(day) / Double(length)
                while end < ordered.count, Double(prefix[end + 1]) <= target { end += 1 }
                if end < ordered.count,
                   abs(Double(prefix[end + 1]) - target) < abs(Double(prefix[end]) - target) {
                    end += 1
                }
            }
            // Préférer une vraie division coranique quand elle reste proche de
            // la cible équilibrée.
            if day < length {
                let target = Double(total) * Double(day) / Double(length)
                let tolerance = Double(total) / Double(length) * 0.15
                for indexes in boundaryIndexes {
                    let candidates = indexes.filter { index in
                        index > cursor && abs(Double(prefix[index]) - target) <= tolerance
                    }
                    if !candidates.isEmpty {
                        end = candidates.reduce(candidates[0]) { best, candidate in
                            abs(Double(prefix[candidate]) - target) < abs(Double(prefix[best]) - target)
                                ? candidate : best
                        }
                        break
                    }
                }
            }
            days.append(Array(ordered[cursor..<max(cursor, end)]))
            cursor = end
        }
        return days
    }

    /// `partitionDailyQuantity` — `src/core/review.ts:171`.
    public static func partitionDailyQuantity(_ corpus: [Int], quantity: String) -> [[Int]] {
        let units: [Division]
        switch quantity {
        case "nisf": units = Quran.halves
        case "hizb": units = Quran.hizbs
        default: units = Quran.juzs
        }
        let groups = units
            .map { unit in corpus.filter { $0 >= unit.start && $0 <= unit.end } }
            .filter { !$0.isEmpty }
        guard quantity == "juz2" else { return groups }
        var out: [[Int]] = []
        for (index, ids) in groups.enumerated() {
            if index % 2 == 1, !out.isEmpty {
                out[out.count - 1].append(contentsOf: ids)
            } else {
                out.append(ids)
            }
        }
        return out
    }

    // MARK: Cycle

    /// `createCycle` — `src/core/review.ts:48`.
    public static func createCycle(_ state: AppState, at: String, index: Int) -> ReviewCycle {
        let modelStart = state.reviewModelStartedAt ?? at
        let corpus = state.memorizedIDs.filter { id in
            guard let learned = state.memorizedAt?[String(id)] else { return true }
            let established = learned < modelStart && age(from: learned, to: modelStart) >= 7
            return established || state.reviewConsolidations?[String(id)]?.completed?["7"] != nil
        }.sorted()

        let days: [[Int]]
        var lengthDays = reviewCycleDays(state)
        if state.reviewSettings?.mode == "quantity" {
            days = partitionDailyQuantity(corpus, quantity: state.reviewSettings?.dailyQuantity ?? "hizb")
            lengthDays = max(1, days.count)
        } else {
            days = partitionReviewCorpus(corpus, length: lengthDays)
        }
        return ReviewCycle(
            index: index,
            startDate: at,
            lengthDays: lengthDays,
            corpus: corpus,
            days: days,
            completed: [],
            assignments: [:]
        )
    }

    // MARK: Versets difficiles

    /// `toggleDifficulty` — `src/core/review.ts:62`.
    /// Le marquage reste jusqu'à suppression volontaire ; il se transmet via
    /// `difficultyMarkers` et `difficultyHistory`, donc entre les deux clients.
    public static func toggleDifficulty(_ state: AppState, id: Int, at: String = DateKeys.today()) -> AppState {
        guard id >= 1, id <= 6236 else { return state }
        var markers = state.difficultyMarkers ?? [:]
        var current = markers[String(id)] ?? DifficultyMarker(user: nil, admin: nil)
        var due = state.reviewPriorityDue ?? [:]
        let action = current.user != nil ? "resolved" : "marked"

        if current.user != nil {
            current.user = nil
            due.removeValue(forKey: String(id))
        } else {
            current.user = DifficultyMarker.Entry(createdAt: at, comment: nil)
            due[String(id)] = at
        }
        if current.user != nil || current.admin != nil {
            markers[String(id)] = current
        } else {
            markers.removeValue(forKey: String(id))
        }
        var history = state.difficultyHistory ?? []
        history.append(DifficultyEvent(verseId: id, date: at, origin: "user", action: action, comment: nil))

        var next = state
        next.difficultyMarkers = markers
        next.reviewPriorityDue = due
        next.difficultyHistory = history
        return Program.touch(next)
    }

    /// Le verset est-il marqué « difficile » (par l'utilisateur ou par un
    /// encadrant) ? C'est ce qui déclenche l'affichage rouge léger dans
    /// l'apprentissage, la révision et la consolidation.
    public static func isDifficult(_ state: AppState, _ id: Int) -> Bool {
        guard let marker = state.difficultyMarkers?[String(id)] else { return false }
        return marker.user != nil || marker.admin != nil
    }

    // MARK: Consolidation

    /// `consolidationFor` — `src/core/review.ts:70`.
    static func consolidationFor(_ state: AppState, id: Int) -> Consolidation? {
        guard let learnedAt = state.memorizedAt?[String(id)] else { return nil }
        let key = String(id)

        if let stored = state.reviewConsolidations?[key], stored.learnedAt == learnedAt {
            if stored.scheduledDates != nil { return stored }
            var copy = stored
            copy.scheduledDates = [
                "1": DateKeys.addDays(learnedAt, 1),
                "3": DateKeys.addDays(learnedAt, 3),
                "7": DateKeys.addDays(learnedAt, 7)
            ]
            return copy
        }

        // Migration depuis les révisions réellement effectuées : aucun
        // rendez-vous manqué n'est inventé.
        var completed: [String: String] = [:]
        var previous = ""
        let events = (state.reviewHistory ?? [])
            .filter { $0.start <= id && $0.end >= id && $0.date >= learnedAt }
            .sorted { $0.date < $1.date }
        for offset in consolidationOffsets {
            let threshold = DateKeys.addDays(learnedAt, offset)
            guard let event = events.first(where: { $0.date >= threshold && $0.date > previous }) else {
                break
            }
            completed[String(offset)] = event.date
            previous = event.date
        }
        return Consolidation(
            learnedAt: learnedAt,
            scheduledDates: [
                "1": DateKeys.addDays(learnedAt, 1),
                "3": DateKeys.addDays(learnedAt, 3),
                "7": DateKeys.addDays(learnedAt, 7)
            ],
            completed: completed,
            completedAt: nil
        )
    }

    /// `prepareReviewSchedule` — `src/core/review.ts:79`.
    public static func prepareReviewSchedule(_ state: AppState, at: String = DateKeys.today()) -> AppState {
        guard reviewsEnabled(state) else { return state }
        var changed = state.reviewModelStartedAt == nil
        var cycle = state.reviewCycle
        if cycle == nil
            || (state.reviewSettings?.mode != "quantity" && cycle?.lengthDays != reviewCycleDays(state)) {
            cycle = createCycle(state, at: at, index: (cycle?.index ?? 0) + 1)
            changed = true
        }
        guard var working = cycle else { return state }

        let completed = Set(working.completed)
        let finished = working.corpus.allSatisfy { completed.contains($0) || !known(state, $0) }
        if finished, at >= DateKeys.addDays(working.startDate, working.lengthDays) {
            working = createCycle(state, at: at, index: working.index + 1)
            changed = true
        }

        if working.assignments[at] == nil {
            let done = Set(working.completed)
            // Une seule part quotidienne d'origine au maximum. Les jours manqués
            // allongent le cycle plutôt que d'accumuler les versets en retard.
            let index = working.days.enumerated().first { position, day in
                DateKeys.addDays(working.startDate, position) <= at
                    && day.contains { known(state, $0) && !done.contains($0) }
            }?.offset
            working.assignments[at] = index ?? -1
            changed = true
        }

        var consolidations = state.reviewConsolidations ?? [:]
        for id in state.memorizedIDs {
            if let value = consolidationFor(state, id: id), consolidations[String(id)] != value {
                consolidations[String(id)] = value
                changed = true
            }
        }
        guard changed else { return state }

        var history = state.reviewCycleHistory ?? []
        if working.index != state.reviewCycle?.index, let previous = state.reviewCycle {
            history.append(previous)
        }
        var next = state
        next.reviewModelStartedAt = state.reviewModelStartedAt ?? at
        next.reviewCycleHistory = history
        next.reviewCycle = working
        next.reviewConsolidations = consolidations
        return Program.touch(next)
    }

    /// `completeConsolidation` — `src/core/review.ts:181`.
    /// Une consolidation peut se faire en avance : les dates restent ancrées à
    /// l'apprentissage, jamais à la date d'exécution.
    public static func completeConsolidation(
        _ state: AppState,
        range: VerseRange,
        at: String = DateKeys.today(),
        completedAt: String = DateKeys.iso(Date()),
        targetOffset: Int? = nil
    ) -> AppState {
        let prepared = prepareReviewSchedule(state, at: at)
        var consolidations = prepared.reviewConsolidations ?? [:]
        var events = prepared.consolidationHistory ?? []

        for id in range.start...max(range.start, range.end) {
            guard known(prepared, id), let existing = consolidationFor(prepared, id: id) else { continue }
            guard let offset = consolidationOffsets.first(where: { existing.completed?[String($0)] == nil }) else {
                continue
            }
            if let targetOffset, targetOffset != offset { continue }
            var updated = existing
            updated.completed = (existing.completed ?? [:]).merging([String(offset): at]) { _, new in new }
            updated.completedAt = (existing.completedAt ?? [:]).merging([String(offset): completedAt]) { _, new in new }
            consolidations[String(id)] = updated
            events.append(ConsolidationEvent(
                id: "\(id)-\(existing.learnedAt)-\(offset)",
                verseId: id,
                offset: offset,
                learnedAt: existing.learnedAt,
                scheduledDate: existing.scheduledDates?[String(offset)] ?? DateKeys.addDays(existing.learnedAt, offset),
                completedAt: completedAt
            ))
        }
        var next = prepared
        next.reviewConsolidations = consolidations
        next.consolidationHistory = events
        return Program.touch(next)
    }

    /// La prochaine consolidation en attente pour un verset, et son échéance.
    public static func nextConsolidation(_ state: AppState, id: Int) -> (offset: Int, due: String)? {
        guard let consolidation = consolidationFor(state, id: id) else { return nil }
        for offset in consolidationOffsets where consolidation.completed?[String(offset)] == nil {
            let due = consolidation.scheduledDates?[String(offset)]
                ?? DateKeys.addDays(consolidation.learnedAt, offset)
            return (offset, due)
        }
        return nil
    }

    // MARK: Notation

    private static func grouped(_ ids: [Int], category: ReviewCategory) -> [ReviewTask] {
        var tasks: [ReviewTask] = []
        for id in Array(Set(ids)).sorted() {
            if let last = tasks.last,
               last.end + 1 == id,
               Quran.surahAt(last.start).number == Quran.surahAt(id).number {
                tasks[tasks.count - 1].end = id
                tasks[tasks.count - 1].id = "\(category.rawValue)-\(last.start)-\(id)"
            } else {
                tasks.append(ReviewTask(
                    id: "\(category.rawValue)-\(id)-\(id)",
                    start: id,
                    end: id,
                    category: category,
                    label: "Versets"
                ))
            }
        }
        return tasks
    }

    /// `gradeReviewTask` — `src/core/review.ts:138`.
    public static func gradeReviewTask(
        _ state: AppState,
        task: ReviewTask,
        grade: ReviewGrade,
        at: String = DateKeys.today()
    ) -> AppState {
        guard reviewsEnabled(state) else { return state }
        let prepared = prepareReviewSchedule(state, at: at)
        let reviewed = Set(idsOf((prepared.reviewHistory ?? []).filter { $0.date == at }.map {
            VerseRange(start: $0.start, end: $0.end)
        }))
        let ids = idsOf([VerseRange(start: task.start, end: task.end)])
            .filter { known(prepared, $0) && !reviewed.contains($0) }
        guard !ids.isEmpty else { return prepared }

        let event = ReviewEvent(
            id: "\(at)-\(task.category.rawValue)-\(task.start)-\(task.end)-\(Int(Date().timeIntervalSince1970 * 1000))",
            date: at,
            scheduledDate: task.scheduledDate ?? at,
            completedAt: DateKeys.iso(Date()),
            start: task.start,
            end: task.end,
            category: task.category,
            grade: grade.rawValue
        )

        var markers = prepared.difficultyMarkers ?? [:]
        var due = prepared.reviewPriorityDue ?? [:]
        var history = prepared.difficultyHistory ?? []
        var consolidations = prepared.reviewConsolidations ?? [:]
        var cycle = prepared.reviewCycle
        var completed = Set(cycle?.completed ?? [])
        let assignedIndex = cycle?.assignments[at] ?? -1
        let assigned = Set(
            assignedIndex >= 0 && assignedIndex < (cycle?.days.count ?? 0) ? cycle!.days[assignedIndex] : []
        )

        for id in ids {
            // Le chevauchement est effectué une seule fois, puis crédité à
            // chaque mécanisme concerné.
            if assigned.contains(id) || (task.category == .habitual && cycle?.corpus.contains(id) == true) {
                completed.insert(id)
            }
            let key = String(id)
            if let consolidation = consolidations[key],
               let offset = consolidationOffsets.first(where: { consolidation.completed?[String($0)] == nil }),
               DateKeys.addDays(consolidation.learnedAt, offset) <= at {
                var updated = consolidation
                updated.completed = (consolidation.completed ?? [:]).merging([String(offset): at]) { _, new in new }
                updated.completedAt = (consolidation.completedAt ?? [:])
                    .merging([String(offset): DateKeys.iso(Date())]) { _, new in new }
                consolidations[key] = updated
            }
            if grade != .perfect {
                if markers[key]?.user == nil {
                    markers[key] = DifficultyMarker(
                        user: DifficultyMarker.Entry(createdAt: at, comment: nil),
                        admin: markers[key]?.admin
                    )
                    history.append(DifficultyEvent(verseId: id, date: at, origin: "user", action: "marked", comment: nil))
                }
                due[key] = DateKeys.addDays(at, grade == .rework ? 1 : 2)
            } else {
                if markers[key]?.user != nil || markers[key]?.admin != nil {
                    due[key] = DateKeys.addDays(at, reviewCycleDays(prepared))
                } else {
                    due.removeValue(forKey: key)
                }
            }
        }

        if var working = cycle {
            working.completed = completed.sorted()
            cycle = working
        }
        var next = prepared
        next.reviewCycle = cycle
        next.reviewConsolidations = consolidations
        next.reviewPriorityDue = due
        next.difficultyMarkers = markers
        next.difficultyHistory = history
        next.reviewHistory = (prepared.reviewHistory ?? []) + [event]
        return Program.touch(next)
    }

    /// `reviewRhythm` — `src/core/review.ts:160`.
    public static func reviewRhythm(_ cycle: ReviewCycle) -> String {
        let set = Set(cycle.corpus)
        for (units, label) in [(Quran.hizbs, "Hizb"), (Quran.halves, "Nisf"), (Quran.quarters, "Rubu’")] {
            let complete = units.filter { isFull(set, $0) }
            let count = complete.count
            if count > 0,
               idsOf(complete).count == cycle.corpus.count,
               count % max(1, cycle.lengthDays) == 0 {
                return "\(count / max(1, cycle.lengthDays)) \(label) / jour"
            }
        }
        let pages = cycle.corpus.reduce(0.0) { $0 + reviewWeight($1) } / Double(max(1, cycle.lengthDays))
        if pages >= 1 {
            return "≈ \(String(format: "%.1f", pages)) pages / jour"
        }
        let verses = Double(cycle.corpus.count) / Double(max(1, cycle.lengthDays))
        return "≈ \(String(format: "%.1f", verses)) versets / jour"
    }

    // MARK: - Quantité lisible

    /// `reviewQuantity` — `src/core/review.ts:96`.
    /// Traduit une liste de versets en unité coranique lisible : Hizb, Nisf,
    /// Rubu’, pages, ou versets. Les libellés sont ceux affichés par
    /// l'application React Native.
    public static func reviewQuantity(_ input: [Int]) -> String {
        let ids = Array(Set(input)).sorted()
        let set = Set(ids)
        guard !ids.isEmpty else { return "0 verset" }

        for (units, label) in [(Quran.hizbs, "Hizb"), (Quran.halves, "Nisf"), (Quran.quarters, "Rubu’")] {
            let matched = units.filter { isFull(set, $0) }
            if matched.reduce(0, { $0 + ($1.end - $1.start + 1) }) == ids.count {
                return "\(matched.count) \(label)"
            }
        }

        let selectedPages = Array(Set(ids.compactMap { Quran.pageOf($0) })).sorted()
        if !selectedPages.isEmpty, selectedPages.allSatisfy({ page in
            guard let range = Quran.pageRange(page) else { return false }
            return isFull(set, range)
        }) {
            return "\(selectedPages.count) page\(selectedPages.count == 1 ? "" : "s")"
        }

        let equivalent = ids.reduce(0.0) { $0 + reviewWeight($1) }
        if equivalent >= 1.5 { return "≈ \(Int(equivalent.rounded())) pages" }
        return "\(ids.count) verset\(ids.count == 1 ? "" : "s")"
    }

    public static func reviewQuantity(_ ranges: [VerseRange]) -> String {
        reviewQuantity(idsOf(ranges))
    }

    public static func reviewQuantity(_ tasks: [ReviewTask]) -> String {
        reviewQuantity(tasks.map(\.range))
    }

    // MARK: - Plan du jour

    /// `reviewPlan` — `src/core/review.ts:116`.
    ///
    /// C'est la fonction que consultent l'accueil, le programme et le tableau de
    /// bord des révisions. Elle assemble, dans cet ordre : les séances de
    /// révision interrompues, les consolidations dues (J+1/J+3/J+7), les versets
    /// prioritaires (marqués difficiles), puis le cycle du jour. Un verset déjà
    /// revu aujourd'hui n'est jamais proposé deux fois.
    public static func reviewPlan(_ original: AppState, at: String = DateKeys.today()) -> ReviewPlan {
        let state = prepareReviewSchedule(original, at: at)
        let all = state.memorizedIDs.sorted()
        let set = Set(all)
        let cycle = state.reviewCycle

        var plan = ReviewPlan(
            recent: [],
            habitual: [],
            priority: [],
            session: [],
            completeJuz: Quran.juzs.filter { isFull(set, $0) }.count,
            completeRub: Quran.quarters.filter { isFull(set, $0) }.count,
            completeNisf: Quran.halves.filter { isFull(set, $0) }.count,
            cycle: cycle,
            cycleDay: cycle.map { min($0.lengthDays, max(1, age(from: $0.startDate, to: at) + 1)) } ?? 0,
            rework: [],
            consolidations: []
        )

        guard reviewsEnabled(state) else { return plan }

        let today = Set(idsOf((state.reviewHistory ?? [])
            .filter { $0.date == at }
            .map { VerseRange(start: $0.start, end: $0.end) }))

        var recentIDs: [Int] = []
        var rows: [ConsolidationRow] = []

        for id in all {
            let key = String(id)
            guard let consolidation = state.reviewConsolidations?[key],
                  consolidation.learnedAt == state.memorizedAt?[key],
                  consolidation.completed?["7"] == nil else { continue }

            let steps = consolidationOffsets.map { offset -> ConsolidationStep in
                ConsolidationStep(
                    offset: offset,
                    due: consolidation.scheduledDates?[String(offset)]
                        ?? DateKeys.addDays(consolidation.learnedAt, offset),
                    completed: consolidation.completed?[String(offset)]
                )
            }
            if let pending = steps.first(where: { $0.completed == nil }),
               pending.due <= at,
               !today.contains(id) {
                recentIDs.append(id)
            }

            if var last = rows.last,
               last.end + 1 == id,
               Quran.surahAt(last.start).number == Quran.surahAt(id).number,
               last.learnedAt == consolidation.learnedAt,
               last.steps == steps {
                last.end = id
                rows[rows.count - 1] = last
            } else {
                rows.append(ConsolidationRow(
                    start: id,
                    end: id,
                    learnedAt: consolidation.learnedAt,
                    steps: steps
                ))
            }
        }

        let priorityIDs = all.filter { id in
            let marker = state.difficultyMarkers?[String(id)]
            let flagged = marker?.user != nil || marker?.admin != nil
            return flagged && (state.reviewPriorityDue?[String(id)] ?? at) <= at && !today.contains(id)
        }

        let done = Set(cycle?.completed ?? [])
        let dayIndex = cycle?.assignments[at] ?? -1
        let assignedDay: [Int] = {
            guard let cycle, dayIndex >= 0, dayIndex < cycle.days.count else { return [] }
            return cycle.days[dayIndex]
        }()
        let habitualIDs = assignedDay.filter { known(state, $0) && !done.contains($0) && !today.contains($0) }

        plan.recent = rows.flatMap { row -> [ReviewTask] in
            let ids = idsOf([VerseRange(start: row.start, end: row.end)])
                .filter { recentIDs.contains($0) }
            let pendingDue = row.steps.first(where: { $0.completed == nil })?.due
            return grouped(ids, category: .recent).map { task in
                var copy = task
                copy.scheduledDate = pendingDue
                return copy
            }
        }
        plan.priority = grouped(priorityIDs, category: .priority).map { task in
            var copy = task
            copy.scheduledDate = state.reviewPriorityDue?[String(task.start)] ?? at
            return copy
        }
        plan.habitual = grouped(habitualIDs, category: .habitual).map { task in
            var copy = task
            copy.scheduledDate = (cycle != nil && dayIndex >= 0)
                ? DateKeys.addDays(cycle!.startDate, dayIndex)
                : at
            return copy
        }

        // Séances interrompues : on reprend exactement là où la personne s'est
        // arrêtée, en conservant l'identifiant du suivi.
        var partials: [ReviewTask] = []
        for record in (state.studyProgress ?? [:]).values
        where record.mode == .revision && record.status == .partial {
            let remaining = (0..<max(0, record.end - record.through)).map { record.through + $0 + 1 }
            let pending = grouped(remaining.filter { known(state, $0) }, category: record.category ?? .habitual)
            partials.append(contentsOf: pending.map { task in
                var copy = task
                copy.id = record.id
                return copy
            })
        }
        let partialIDs = Set(partials.map(\.id))

        var seen = Set<Int>()
        var session: [ReviewTask] = []
        for task in partials + plan.recent + plan.priority + plan.habitual {
            let ids = idsOf([VerseRange(start: task.start, end: task.end)]).filter { id in
                if seen.contains(id) { return false }
                seen.insert(id)
                return true
            }
            for piece in grouped(ids, category: task.category) {
                var copy = piece
                copy.scheduledDate = task.scheduledDate
                if partialIDs.contains(task.id) { copy.id = task.id }
                session.append(copy)
            }
        }
        plan.session = session

        plan.rework = grouped(all.filter { id in
            let marker = state.difficultyMarkers?[String(id)]
            return marker?.user != nil || marker?.admin != nil
        }, category: .priority)
        plan.consolidations = rows
        return plan
    }

    // MARK: - Réglages du cycle

    /// `setReviewCycle` — `src/core/review.ts:127`.
    /// L'historique des cycles est conservé : changer de durée n'efface rien.
    public static func setReviewCycle(_ state: AppState, cycleDays: Int, at: String = DateKeys.today()) -> AppState {
        if reviewCycleDays(state) == cycleDays && state.reviewSettings?.mode != "quantity" { return state }
        var next = state
        var settings = next.reviewSettings ?? ReviewSettings(enabled: reviewsEnabled(state), cycleDays: cycleDays)
        settings.enabled = reviewsEnabled(state)
        settings.cycleDays = cycleDays
        settings.mode = "cycle"
        next.reviewSettings = settings
        if let current = state.reviewCycle {
            next.reviewCycleHistory = (state.reviewCycleHistory ?? []) + [current]
        }
        next.reviewCycle = createCycle(next, at: at, index: (state.reviewCycle?.index ?? 0) + 1)
        return Program.touch(next)
    }

    /// `setReviewQuantity` — `src/core/review.ts:133`.
    public static func setReviewQuantity(_ state: AppState, quantity: String, at: String = DateKeys.today()) -> AppState {
        var next = state
        var settings = next.reviewSettings ?? ReviewSettings(enabled: reviewsEnabled(state), cycleDays: reviewCycleDays(state))
        settings.enabled = reviewsEnabled(state)
        settings.cycleDays = reviewCycleDays(state)
        settings.mode = "quantity"
        settings.dailyQuantity = quantity
        next.reviewSettings = settings
        if let current = state.reviewCycle {
            next.reviewCycleHistory = (state.reviewCycleHistory ?? []) + [current]
        }
        next.reviewCycle = createCycle(next, at: at, index: (state.reviewCycle?.index ?? 0) + 1)
        return Program.touch(next)
    }
}

// MARK: - Types de tâche

public struct ReviewTask: Equatable, Sendable {
    public var id: String
    public var start: Int
    public var end: Int
    public var scheduledDate: String?
    public var category: ReviewCategory
    public var label: String

    public init(
        id: String,
        start: Int,
        end: Int,
        scheduledDate: String? = nil,
        category: ReviewCategory,
        label: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.scheduledDate = scheduledDate
        self.category = category
        self.label = label
    }

    public var range: VerseRange { VerseRange(start: start, end: end) }
}

public struct ConsolidationRow: Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var learnedAt: String
    public var steps: [ConsolidationStep]
}

/// Une étape de consolidation (J+1, J+3, J+7) telle qu'affichée dans le tableau
/// de bord des révisions : son échéance et, le cas échéant, sa date de
/// réalisation.
public struct ConsolidationStep: Equatable, Sendable {
    public var offset: Int
    public var due: String
    public var completed: String?

    public init(offset: Int, due: String, completed: String?) {
        self.offset = offset
        self.due = due
        self.completed = completed
    }
}

/// `ReviewPlan` — `src/core/review.ts:114`.
///
/// Ce que la personne voit sur l'accueil, dans le programme et dans le tableau
/// de bord des révisions, calculé pour un jour donné.
public struct ReviewPlan: Sendable {
    public var recent: [ReviewTask]
    public var habitual: [ReviewTask]
    public var priority: [ReviewTask]
    public var session: [ReviewTask]
    public var completeJuz: Int
    public var completeRub: Int
    public var completeNisf: Int
    public var cycle: ReviewCycle?
    public var cycleDay: Int
    public var rework: [ReviewTask]
    public var consolidations: [ConsolidationRow]

    /// Rien à réviser aujourd'hui.
    public var isEmpty: Bool { session.isEmpty }
}

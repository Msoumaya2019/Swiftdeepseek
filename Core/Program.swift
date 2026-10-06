// Program.swift
// Port de `src/core/program.ts` : génération du programme d'apprentissage.
//
// Règles produit à préserver absolument :
//   - `scheduledDate` est la date PRÉVUE. Une séance faite en avance ne change
//     jamais sa date prévue : seule `completedAt` / `completedDate` bougent.
//   - Ignorer une séance (`postponeSession`) change son statut, jamais son
//     échéance ni celle des séances voisines.
//   - Le programme est prolongé en ajoutant des séances, sans reconstruire les
//     dates existantes (`extendLearningProgram`).

import Foundation

public enum Pace: String, Codable, CaseIterable, Sendable {
    case verse1, verse2, verse3, verse4, verse5
    case halfPage, page, page2
    case toumoun, quarter, halfHizb, hizb

    public var label: String {
        switch self {
        case .verse1: return "1 verset"
        case .verse2: return "2 versets"
        case .verse3: return "3 versets"
        case .verse4: return "4 versets"
        case .verse5: return "5 versets"
        case .halfPage: return "½ page"
        case .page: return "1 page"
        case .page2: return "2 pages"
        case .toumoun: return "1 toumoun"
        case .quarter: return "1 rub‘"
        case .halfHizb: return "1 nisf"
        case .hizb: return "1 hizb"
        }
    }

    /// `Number(pace.slice(5))` côté JavaScript.
    var verseCount: Int? {
        switch self {
        case .verse1: return 1
        case .verse2: return 2
        case .verse3: return 3
        case .verse4: return 4
        case .verse5: return 5
        default: return nil
        }
    }

    /// Le libellé du rythme **stocké**, ou la chaîne brute quand cette version ne
    /// connaît pas le rythme.
    ///
    /// `Pace(rawValue: state.pace)?.label ?? state.pace` — l'idiome était écrit
    /// **trois fois** (`Features/Program/ProgramView.swift:82`,
    /// `Features/Progress/ProgressScreenView.swift:362`,
    /// `Features/Settings/SettingsView.swift:144`), et l'écran du profil en
    /// demandait une quatrième. Il vit ici depuis, comme la recette du bouton
    /// secondaire vit dans `CardButton`.
    ///
    /// Le repli sur la valeur stockée n'est pas un luxe : une application plus
    /// ancienne peut avoir écrit un rythme que cette version ne connaît pas
    /// (`toumoun`, par exemple, reste indisponible tant que ses limites ne sont
    /// pas vérifiées). Afficher la chaîne brute est plus honnête que d'afficher
    /// un libellé faux.
    ///
    /// `state.pace` est une chaîne, pas un `Pace` : un document restauré peut
    /// porter une valeur inconnue, et c'est pourquoi le repli porte sur la
    /// chaîne et non sur un cas par défaut.
    public static func displayed(_ raw: String) -> String {
        Pace(rawValue: raw)?.label ?? raw
    }
}

public enum Program {

    /// Les limites Hafs des toumoun ne sont pas vérifiées dans le dépôt de
    /// référence (`toumoun.json` ne contient que des marqueurs « missing »).
    /// Tant qu'elles ne le sont pas, le rythme « toumoun » reste indisponible,
    /// exactement comme côté React Native (`availablePaces`).
    public static let verifiedToumouns: [Division]? = nil

    public static var availablePaces: [Pace] {
        Pace.allCases.filter { $0 != .toumoun || verifiedToumouns != nil }
    }

    public static let beginnerPaces: [Pace] = [.verse1, .verse2, .verse3, .verse4, .verse5]
    public static let intensivePaces: [Pace] = [.page, .page2, .quarter]

    public static let weekdays = [
        "Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"
    ]

    // MARK: État initial

    /// `defaultState()` — `src/core/program.ts:57`.
    public static func defaultState() -> AppState {
        AppState(
            schema: 1,
            onboardingDone: false,
            onboardingStep: nil,
            updatedAt: "1970-01-01T00:00:00.000Z",
            userId: nil,
            knowledge: [:],
            goal: Goal(
                deadline: nil,
                label: "Juz’ ‘Amma",
                ranges: [VerseRange(start: 5673, end: 6236)],
                direction: nil
            ),
            pace: Pace.verse3.rawValue,
            learningDays: [1, 2, 3, 4, 5],
            sessions: [],
            revisions: [],
            profile: nil,
            theme: "white",
            uiFont: nil,
            accent: nil,
            notifications: NotificationPreferences(messages: true, learning: false),
            reader: ReaderPreferences(mushaf: "coranTest", followAudio: true),
            audioPreferences: nil,
            bookmarks: nil,
            readPages: nil,
            lastRead: nil,
            memorizedAt: [:],
            reviewSettings: ReviewSettings(enabled: true, cycleDays: 7),
            reviewHistory: [],
            reviewDue: [:],
            difficultyMarkers: [:],
            difficultyHistory: [],
            reviewModelStartedAt: nil,
            reviewCycle: nil,
            reviewConsolidations: [:],
            reviewPriorityDue: [:],
            reviewCycleHistory: [],
            consolidationHistory: [],
            studyProgress: [:]
        )
    }

    /// `migrateReaderState` — `src/core/program.ts:59`.
    /// Les anciennes clés de source restent lisibles pour ne pas perdre les
    /// préférences ni les marques-pages déjà enregistrés.
    public static func migrateReaderState(_ state: AppState) -> AppState {
        var next = state
        if let mushaf = next.reader?.mushaf,
           ["tawjeed_test_2", "tajweed_test_2", "medine_test"].contains(mushaf) {
            next.reader?.mushaf = "coran_1441"
        }
        if next.sessions.contains(where: { $0.scheduledDate == nil }) {
            next.sessions = next.sessions.map { session in
                guard session.scheduledDate == nil else { return session }
                var copy = session
                copy.scheduledDate = session.date
                return copy
            }
        }
        if let mushaf = next.reader?.mushaf, mushaf != "tajweedPages" { return next }
        // `{...state.reader, mushaf:'coranTest', followAudio: …}` — un lecteur
        // ABSENT est donc CRÉÉ, jamais laissé absent.
        //
        // C'est un défaut latent qui vient d'être corrigé, et il valait la
        // peine d'être vu : l'ancienne écriture — `next.reader?.mushaf =
        // "coranTest"` — était une chaîne optionnelle, qui ne CRÉE pas
        // l'objet. Sur un `reader` à `nil` (clé absente, ou `"reader": null`),
        // elle ne faisait donc rien du tout, et le document produit divergeait
        // de celui de l'original. Aucun document des deux applications n'est
        // dans ce cas — `defaultState()` écrit toujours un lecteur — mais
        // `Reconcile.migrateRaw` porte la même règle sur le document brut et,
        // lui, le crée : les deux jumelles doivent décider la même chose, et
        // c'est un test qui les y tient (`ReconcileTests`).
        var reader = next.reader ?? ReaderPreferences(mushaf: "coranTest", followAudio: true)
        reader.mushaf = "coranTest"
        // `followAudio` est un `Bool` NON optionnel ici, donc `!== false` s'y
        // réduit à la valeur elle-même : l'expression est gardée telle quelle
        // pour rester lisible à côté de l'original.
        reader.followAudio = reader.followAudio != false
        next.reader = reader
        return next
    }

    public static func touch(_ state: AppState) -> AppState {
        var next = migrateReaderState(state)
        next.updatedAt = DateKeys.iso(Date())
        return next
    }

    /// Clé d'un suivi de séance dans `state.studyProgress` — `studyKey`,
    /// `src/core/studyProgress.ts:7` : `"<mode>:<id>"`, soit `learning:<id>` ou
    /// `revision:<id>`.
    ///
    /// À utiliser partout : la clé fait partie du document synchronisé, donc la
    /// construire à la main une seule fois de travers suffit à rendre un suivi
    /// invisible pour l'autre application.
    public static func studyKey(_ mode: StudyMode, _ id: String) -> String {
        "\(mode.rawValue):\(id)"
    }

    // MARK: Connaissance

    /// `markKnowledge` — `src/core/program.ts:101`.
    public static func markKnowledge(_ state: AppState, range: VerseRange, mastery: Mastery) -> AppState {
        var knowledge = state.knowledge
        var memorizedAt = state.memorizedAt ?? [:]
        var reviewDue = state.reviewDue ?? [:]
        let today = DateKeys.today()

        for id in range.start...max(range.start, range.end) {
            let key = String(id)
            let existing = knowledge[key]
            if mastery != .learning,
               state.onboardingDone,
               existing != .perfect,
               existing != .review,
               memorizedAt[key] == nil {
                memorizedAt[key] = today
            }
            knowledge[key] = mastery
            if mastery == .learning {
                memorizedAt.removeValue(forKey: key)
                reviewDue.removeValue(forKey: key)
            }
        }
        var next = state
        next.knowledge = knowledge
        next.memorizedAt = memorizedAt
        next.reviewDue = reviewDue
        return touch(next)
    }

    public static func toggleKnownRange(_ state: AppState, range: VerseRange) -> AppState {
        markKnowledge(state, range: range, mastery: state.isRangeKnown(range) ? .learning : .perfect)
    }

    /// `partialKnownRanges` — `src/core/program.ts:118`.
    public static func partialKnownRanges(_ state: AppState) -> [VerseRange] {
        let ids = state.memorizedIDs
        var ranges: [VerseRange] = []
        for id in ids {
            if let last = ranges.last,
               id == last.end + 1,
               Quran.surahAt(id).number == Quran.surahAt(last.start).number {
                ranges[ranges.count - 1].end = id
            } else {
                ranges.append(VerseRange(start: id, end: id))
            }
        }
        return ranges.filter { range in
            let surah = Quran.surahAt(range.start)
            return range.start != surah.start || range.end != surah.end
        }
    }

    // MARK: Découpage d'une séance

    private static func takePrefix(_ ids: [Int], where predicate: (Int) -> Bool) -> [Int] {
        var out: [Int] = []
        for id in ids {
            if !predicate(id) { break }
            out.append(id)
        }
        return out
    }

    private static func splitContiguous(_ ids: [Int]) -> [VerseRange] {
        var result: [VerseRange] = []
        for id in ids {
            if let last = result.last,
               id == last.end + 1,
               Quran.surahAt(id).number == Quran.surahAt(last.start).number {
                result[result.count - 1].end = id
            } else {
                result.append(VerseRange(start: id, end: id))
            }
        }
        return result
    }

    /// `nextChunk` — `src/core/program.ts:153`.
    static func nextChunk(_ remaining: [Int], pace: Pace) -> [Int] {
        guard !remaining.isEmpty else { return [] }
        if let count = pace.verseCount { return Array(remaining.prefix(count)) }
        let first = remaining[0]

        if pace == .page2 {
            var selectedPages = Set<Int>()
            var out: [Int] = []
            for id in remaining {
                guard let page = Quran.pageOf(id) else { continue }
                if !selectedPages.contains(page), selectedPages.count == 2 { break }
                selectedPages.insert(page)
                out.append(id)
            }
            return out
        }

        if pace == .halfPage || pace == .page {
            guard let range = Quran.pageRange(Quran.pageOf(first) ?? 1) else { return [] }
            let within = takePrefix(remaining) { $0 >= range.start && $0 <= range.end }
            if pace == .page { return within }
            let target = Double(Quran.volume(Array(range.start...range.end))) / 2
            var sum = 0
            var out: [Int] = []
            for id in within {
                out.append(id)
                sum += Quran.weights[id - 1]
                if Double(sum) >= target { break }
            }
            return out
        }

        if pace == .toumoun, verifiedToumouns == nil {
            return [] // Indisponible : les limites ne sont pas vérifiées.
        }
        let divisions: [Division]
        switch pace {
        case .toumoun: divisions = verifiedToumouns ?? []
        case .quarter: divisions = Quran.quarters
        case .halfHizb: divisions = Quran.halves
        default: divisions = Quran.hizbs
        }
        guard let boundary = divisions.first(where: { first >= $0.start && first <= $0.end }) else {
            return []
        }
        return takePrefix(remaining) { $0 >= boundary.start && $0 <= boundary.end }
    }

    // MARK: Génération

    /// `generateProgram` — `src/core/program.ts:190`.
    public static func generateProgram(
        _ state: AppState,
        from: String = DateKeys.today(),
        days: Int = 20000
    ) -> AppState {
        func isPartial(_ session: Session) -> Bool {
            state.studyProgress?[studyKey(.learning, session.id)]?.status == .partial
        }

        let old = state.sessions
            .filter { isPartial($0) || $0.status != .todo || $0.date < from }
            .map { session -> Session in
                guard session.status == .todo, !isPartial(session) else { return session }
                var copy = session
                copy.status = .postponed
                return copy
            }

        var scheduled = Set<Int>()
        for session in old where session.status == .done {
            scheduled.formUnion(session.start...max(session.start, session.end))
        }
        for session in old where isPartial(session) {
            scheduled.formUnion(session.start...max(session.start, session.end))
        }

        let known = Set(state.memorizedIDs)
        var remaining = state.learningOrderIDs.filter { !known.contains($0) && !scheduled.contains($0) }
        let pace = Pace(rawValue: state.pace) ?? .verse3

        var sessions: [Session] = []
        var serial = 0
        for offset in 0..<days where !remaining.isEmpty {
            let date = DateKeys.addDays(from, offset)
            guard state.learningDays.contains(DateKeys.dayOf(date)) else { continue }
            let chunk = nextChunk(remaining, pace: pace)
            guard !chunk.isEmpty else { break }
            remaining.removeFirst(chunk.count)
            for range in splitContiguous(chunk) {
                sessions.append(Session(
                    id: "\(date)-\(range.start)-\(serial)",
                    date: date,
                    scheduledDate: date,
                    start: range.start,
                    end: range.end,
                    unit: pace.rawValue,
                    status: .todo,
                    completedAt: nil,
                    completedDate: nil
                ))
                serial += 1
            }
        }

        var next = state
        next.sessions = (old + sessions).sorted { $0.date < $1.date }
        return touch(next)
    }

    /// `postponeSession` — `src/core/program.ts:215`.
    public static func postponeSession(_ state: AppState, id: String) -> AppState {
        let isPartial = state.studyProgress?[studyKey(.learning, id)]?.status == .partial
        var next = state
        next.sessions = state.sessions.map { session in
            guard session.id == id else { return session }
            var copy = session
            copy.status = isPartial ? .todo : .postponed
            return copy
        }
        return touch(next)
    }

    /// `completeSession` — `src/core/program.ts:220`.
    public static func completeSession(
        _ state: AppState,
        id: String,
        memorized: Bool,
        from: String = DateKeys.today()
    ) -> AppState {
        guard let session = state.sessions.first(where: { $0.id == id }) else { return state }
        guard memorized else { return postponeSession(state, id: id) }

        var memorizedAt = state.memorizedAt ?? [:]
        for verse in session.start...max(session.start, session.end) {
            let key = String(verse)
            if state.knowledge[key] != .perfect,
               state.knowledge[key] != .review,
               memorizedAt[key] == nil {
                memorizedAt[key] = from
            }
        }
        var withDates = state
        withDates.memorizedAt = memorizedAt
        let updated = markKnowledge(withDates, range: VerseRange(start: session.start, end: session.end), mastery: .perfect)

        var revisions = updated.revisions
        let revisionID = "r-\(session.start)-\(session.end)"
        if !revisions.contains(where: { $0.id == revisionID }) {
            revisions.append(Revision(
                id: revisionID,
                start: session.start,
                end: session.end,
                due: DateKeys.addDays(from, 1),
                interval: 1,
                streak: 0,
                lastGrade: nil,
                completedCount: 0
            ))
        }

        var next = updated
        next.revisions = revisions
        next.sessions = updated.sessions.map { item in
            guard item.id == id else { return item }
            var copy = item
            copy.status = .done
            copy.completedAt = DateKeys.iso(Date())
            copy.completedDate = from
            return copy
        }
        return extendLearningProgram(touch(next))
    }

    /// `extendLearningProgram` — `src/core/program.ts:234`.
    public static func extendLearningProgram(_ state: AppState) -> AppState {
        var covered = Set<Int>()
        for session in state.sessions where session.status == .todo || session.status == .done {
            covered.formUnion(session.start...max(session.start, session.end))
        }
        let stillMissing = state.learningOrderIDs.contains { id in
            !covered.contains(id) && state.knowledge[String(id)] != .perfect && state.knowledge[String(id)] != .review
        }
        guard stillMissing else { return state }

        var knowledge = state.knowledge
        for id in covered { knowledge[String(id)] = .perfect }
        let latest = state.sessions.map(\.effectiveScheduledDate).sorted().last
        let start = latest.map { DateKeys.addDays($0, 1) } ?? DateKeys.today()

        var seed = state
        seed.knowledge = knowledge
        seed.sessions = []
        let extensionProgram = generateProgram(seed, from: start)
        var next = state
        next.sessions = state.sessions + extensionProgram.sessions
        return touch(next)
    }

    /// `seedInitialRevisions` — `src/core/program.ts:208`.
    public static func seedInitialRevisions(_ state: AppState, from: String = DateKeys.today()) -> AppState {
        var covered = Set<Int>()
        for revision in state.revisions {
            covered.formUnion(revision.start...max(revision.start, revision.end))
        }
        let known = state.memorizedIDs.filter { !covered.contains($0) }.sorted()
        let groups = splitContiguous(known)
        var revisions = state.revisions
        for range in groups {
            revisions.append(Revision(
                id: "r-initial-\(range.start)-\(range.end)",
                start: range.start,
                end: range.end,
                due: DateKeys.addDays(from, 1),
                interval: 1,
                streak: 0,
                lastGrade: nil,
                completedCount: 0
            ))
        }
        var next = state
        next.revisions = revisions
        return touch(next)
    }
}

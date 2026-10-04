// AppState.swift
// Vue TYPÉE du document `user_state.data` (jsonb) de Supabase.
//
// Le document fait autorité sous forme de `JSONValue` (voir JSONValue.swift) :
// ces structs servent uniquement à LIRE l'état de façon sûre. Toute écriture
// repasse par le JSON brut afin de ne jamais perdre une clé inconnue.
//
// Correspondance : `src/core/program.ts:31` (type `AppState`).
// Les noms de propriétés Swift sont identiques aux clés JSON : aucune
// `CodingKeys` n'est nécessaire, ce qui évite une source d'erreur.

import Foundation

public typealias VerseID = Int

public enum Mastery: String, Codable, Sendable {
    case perfect, review, learning
}

public enum SessionStatus: String, Codable, Sendable {
    case todo, done, postponed
}

/// Note donnée à une TÂCHE de révision — `ReviewGrade`, `src/core/program.ts:23` :
/// `'perfect' | 'hesitant' | 'rework'`.
///
/// ATTENTION — L'APPLICATION D'ORIGINE A DEUX VOCABULAIRES DE NOTES
///   - les TÂCHES de révision notent `perfect | hesitant | rework`
///     (`program.ts:23`, consommé par `gradeReviewTask`, `review.ts:138`) ;
///   - les RÉVISIONS de versets notent `perfect | hesitant | errors | relearn`
///     (`program.ts:11`, `Revision.lastGrade`).
///
/// Ce sont deux jeux de valeurs différents, aux noms qui se ressemblent. Les
/// confondre écrirait dans le document synchronisé une valeur que l'application
/// React Native ne saurait pas relire.
///
/// Ce type-ci ne porte donc que les trois valeurs des tâches. Les deux autres
/// n'ont pas à figurer ici : `Revision.lastGrade` est un `String?`, ce qui
/// laisse passer n'importe laquelle des quatre valeurs sans avoir à les nommer.
public enum ReviewGrade: String, Codable, Sendable {
    case perfect, hesitant, rework
}

public enum ReviewCategory: String, Codable, Sendable {
    case recent, habitual, priority
}

public enum StudyStatus: String, Codable, Sendable {
    case partial, completed
}

public enum StudyMode: String, Codable, Sendable {
    case learning, revision
}

public struct VerseRange: Codable, Equatable, Hashable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct Session: Codable, Equatable, Sendable {
    public var id: String
    public var date: String
    public var scheduledDate: String?
    public var start: Int
    public var end: Int
    public var unit: String
    public var status: SessionStatus
    public var completedAt: String?
    public var completedDate: String?

    /// `scheduledDate ?? date` — `src/core/weeklyProgress.ts:2`.
    public var effectiveScheduledDate: String { scheduledDate ?? date }
}

public struct Revision: Codable, Equatable, Sendable {
    public var id: String
    public var start: Int
    public var end: Int
    public var due: String
    public var interval: Int
    public var streak: Int
    public var lastGrade: String?
    public var completedCount: Int
}

public struct Goal: Codable, Equatable, Sendable {
    public var deadline: String?
    public var label: String
    public var ranges: [VerseRange]
    public var direction: String?
}

public struct PersonalProfile: Codable, Equatable, Sendable {
    public var sex: String
    public var firstName: String
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var messages: Bool
    public var learning: Bool
    public var friendRequests: Bool?
    public var sharedProgress: Bool?
    public var revision: Bool?
    public var corrections: Bool?
    public var adminMessages: Bool?
    public var messagePreview: Bool?
    public var permissionExplained: Bool?
}

public struct ReaderPreferences: Codable, Equatable, Sendable {
    public var mushaf: String
    public var followAudio: Bool
    public var testPage: Int?
    public var paper: String?
}

public struct ReviewSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var cycleDays: Int
    public var mode: String?
    public var dailyQuantity: String?
    public var resumedAt: String?
}

public struct ReviewEvent: Codable, Equatable, Sendable {
    public var id: String
    public var date: String
    public var scheduledDate: String?
    public var completedAt: String?
    public var start: Int
    public var end: Int
    public var category: ReviewCategory
    public var grade: String
}

public struct DifficultyMarker: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var createdAt: String
        public var comment: String?
    }
    public var user: Entry?
    public var admin: Entry?
}

public struct DifficultyEvent: Codable, Equatable, Sendable {
    public var verseId: Int
    public var date: String
    public var origin: String
    public var action: String
    public var comment: String?
}

public struct ReviewCycle: Codable, Equatable, Sendable {
    public var index: Int
    public var startDate: String
    public var lengthDays: Int
    public var corpus: [Int]
    public var days: [[Int]]
    public var completed: [Int]
    public var assignments: [String: Int]
}

public struct Consolidation: Codable, Equatable, Sendable {
    public var learnedAt: String
    public var scheduledDates: [String: String]?
    public var completed: [String: String]?
    public var completedAt: [String: String]?
}

public struct ConsolidationEvent: Codable, Equatable, Sendable {
    public var id: String
    public var verseId: Int
    public var offset: Int
    public var learnedAt: String
    public var scheduledDate: String
    public var completedAt: String
}

public struct StudyValidation: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var date: String
    public var validatedAt: String?
}

public struct StudyProgress: Codable, Equatable, Sendable {
    public var id: String
    public var mode: StudyMode
    public var category: ReviewCategory?
    public var start: Int
    public var end: Int
    public var through: Int
    public var page: Int
    public var source: String
    public var updatedAt: String
    public var status: StudyStatus
    public var validations: [StudyValidation]
}

public struct VerseBookmark: Codable, Equatable, Sendable {
    public var verseId: Int
    public var surah: Int
    public var ayah: Int
    public var page: Int
    public var sourcePages: [String: Int]?
    public var createdAt: String
    public var updatedAt: String
    public var lastUsedAt: String?
    public var deletedAt: String?
}

public struct LastRead: Codable, Equatable, Sendable {
    public var page: Int
    public var verseId: Int
    public var readAt: String
}

public struct AudioPreferences: Codable, Equatable, Sendable {
    public var reciterId: String
}

/// Document complet. Toutes les clés optionnelles le sont parce que
/// `defaultState()` ne les écrit pas toutes (`src/core/program.ts:57`).
public struct AppState: Codable, Equatable, Sendable {
    public var schema: Int
    public var onboardingDone: Bool
    public var onboardingStep: Int?
    public var updatedAt: String
    public var userId: String?

    public var knowledge: [String: Mastery]
    public var goal: Goal
    public var pace: String
    public var learningDays: [Int]
    public var sessions: [Session]
    public var revisions: [Revision]

    public var profile: PersonalProfile?
    public var theme: String?
    public var uiFont: String?
    public var accent: String?
    public var notifications: NotificationPreferences?
    public var reader: ReaderPreferences?
    public var audioPreferences: AudioPreferences?

    public var bookmarks: [String: VerseBookmark]?
    public var readPages: [Int]?
    public var lastRead: LastRead?
    public var memorizedAt: [String: String]?

    public var reviewSettings: ReviewSettings?
    public var reviewHistory: [ReviewEvent]?
    public var reviewDue: [String: String]?
    public var difficultyMarkers: [String: DifficultyMarker]?
    public var difficultyHistory: [DifficultyEvent]?
    public var reviewModelStartedAt: String?
    public var reviewCycle: ReviewCycle?
    public var reviewConsolidations: [String: Consolidation]?
    public var reviewPriorityDue: [String: String]?
    public var reviewCycleHistory: [ReviewCycle]?
    public var consolidationHistory: [ConsolidationEvent]?
    public var studyProgress: [String: StudyProgress]?
}

// MARK: - Décodage

public extension AppState {
    /// Décode depuis le JSON brut. `nil` si le document n'a pas la forme attendue.
    static func decode(from value: JSONValue) -> AppState? {
        guard case .object = value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    /// Reproduit la validation de `loadState()` (`src/services/storage.ts:17`).
    var isUsable: Bool {
        schema == 1 && !sessions.isEmpty || schema == 1
    }

    /// Ranges mémorisés (`memorizedIds`, `src/core/program.ts:138`).
    var memorizedIDs: [Int] {
        knowledge.compactMap { key, value in
            (value == .perfect || value == .review) ? Int(key) : nil
        }.sorted()
    }

    var goalIDs: [Int] {
        Quran.expand(goal.ranges)
    }

    func isRangeKnown(_ range: VerseRange) -> Bool {
        for id in range.start...max(range.start, range.end) {
            guard let mastery = knowledge[String(id)],
                  mastery == .perfect || mastery == .review else { return false }
        }
        return true
    }

    /// Ordre d'apprentissage (`learningOrderIds`, `src/core/program.ts:132`).
    var learningOrderIDs: [Int] {
        let ids = goalIDs
        guard goal.direction == "fromNas" else { return ids }
        return ids.sorted { lhs, rhs in
            let ls = Quran.surahAt(lhs).number
            let rs = Quran.surahAt(rhs).number
            return ls == rs ? lhs < rhs : ls > rs
        }
    }

    /// `progress()` — `src/core/program.ts:139`.
    func progress() -> (quran: Double, goal: Double, goalKnown: Int, goalTotal: Int) {
        let known = Set(memorizedIDs)
        let target = goalIDs
        let goalTotal = Quran.volume(target)
        let goalKnown = Quran.volume(target.filter { known.contains($0) })
        let total = Quran.totalVolume
        return (
            quran: total > 0 ? Double(Quran.volume(Array(known))) / Double(total) : 0,
            goal: goalTotal > 0 ? Double(goalKnown) / Double(goalTotal) : 0,
            goalKnown: goalKnown,
            goalTotal: goalTotal
        )
    }
}

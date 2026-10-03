// ProgramTests.swift
// Le programme d'apprentissage.
//
// Ce que ces tests protègent :
//   - la forme du document initial, qui doit rester identique à celle de
//     l'application React Native (`defaultState()`) ;
//   - la clé de suivi `learning:<id>`, qui fait partie du document synchronisé ;
//   - la règle produit la plus facile à casser : une séance terminée en avance
//     ne doit PAS voir sa date prévue changer.

import XCTest
@testable import Swiftdeepseek

final class ProgramTests: XCTestCase {

    // MARK: Forme du document initial

    func testDefaultStateMatchesTheReactNativeShape() {
        let state = Program.defaultState()
        XCTAssertEqual(state.schema, 1)
        XCTAssertFalse(state.onboardingDone)
        XCTAssertEqual(state.goal.label, "Juz’ ‘Amma")
        XCTAssertEqual(state.goal.ranges, [VerseRange(start: 5673, end: 6236)])
        XCTAssertEqual(state.pace, "verse3")
        XCTAssertEqual(state.learningDays, [1, 2, 3, 4, 5])
        XCTAssertEqual(state.theme, "white")
        XCTAssertEqual(state.reader?.mushaf, "coranTest")
        XCTAssertEqual(state.reader?.followAudio, true)
        XCTAssertEqual(state.reviewSettings?.enabled, true)
        XCTAssertEqual(state.reviewSettings?.cycleDays, 7)
        XCTAssertEqual(state.notifications?.messages, true)
        XCTAssertEqual(state.notifications?.learning, false)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertTrue(state.knowledge.isEmpty)
        // Ces clés doivent exister (même vides) : l'application React Native les
        // écrit, et la fusion à trois voies s'appuie sur leur présence.
        XCTAssertEqual(state.studyProgress?.isEmpty, true)
        XCTAssertEqual(state.memorizedAt?.isEmpty, true)
        XCTAssertEqual(state.reviewHistory?.isEmpty, true)
        XCTAssertEqual(state.reviewConsolidations?.isEmpty, true)
        XCTAssertEqual(state.reviewPriorityDue?.isEmpty, true)
    }

    func testStudyKeyFormatIsShared() {
        // `studyKey('learning', id)` côté React Native — la clé fait partie du
        // document synchronisé, donc un écart la rendrait invisible à l'autre
        // application.
        XCTAssertEqual(Program.studyKey(.learning, "abc"), "learning:abc")
        XCTAssertEqual(Program.studyKey(.revision, "xyz"), "revision:xyz")
    }

    // MARK: Découpage des séances

    func testVersePacesTakeTheRequestedNumberOfVerses() {
        let remaining = Array(1...20)
        XCTAssertEqual(Program.nextChunk(remaining, pace: .verse1), [1])
        XCTAssertEqual(Program.nextChunk(remaining, pace: .verse3), [1, 2, 3])
        XCTAssertEqual(Program.nextChunk(remaining, pace: .verse5), [1, 2, 3, 4, 5])
    }

    func testNextChunkOfAnEmptyRemainderIsEmpty() {
        XCTAssertEqual(Program.nextChunk([], pace: .verse3), [])
    }

    func testToumounIsUnavailableRatherThanInvented() {
        // Les limites des toumouns ne sont pas vérifiées dans le dépôt de
        // référence : mieux vaut ne rien proposer que proposer un découpage
        // faux. C'est un choix explicite, pas un oubli.
        XCTAssertNil(Program.verifiedToumouns)
        XCTAssertEqual(Program.nextChunk(Array(1...10), pace: .toumoun), [])
    }

    // MARK: Génération

    func testGenerateProgramOnlySchedulesOnLearningDays() {
        let state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 30)
        XCTAssertFalse(state.sessions.isEmpty)
        for session in state.sessions {
            let weekday = DateKeys.dayOf(session.date)
            XCTAssertTrue(
                [1, 2, 3, 4, 5].contains(weekday),
                "Une séance est prévue un jour non retenu (jour \(weekday), \(session.date))."
            )
            XCTAssertEqual(session.status, .todo)
            // `scheduledDate` doit être renseignée dès la création : c'est elle
            // que lit la liste « À venir ».
            XCTAssertEqual(session.scheduledDate, session.date)
        }
    }

    func testGenerateProgramStartsOnTheGivenDate() {
        let state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 30)
        XCTAssertEqual(state.sessions.first?.date, "2026-10-05") // un lundi
    }

    func testGeneratedSessionsAreSortedByDate() {
        let state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 60)
        let dates = state.sessions.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testGeneratedSessionsDoNotOverlapTheGoal() {
        let state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 60)
        let goal = Set(5673...6236)
        for session in state.sessions {
            for verse in session.start...session.end {
                XCTAssertTrue(goal.contains(verse), "Le verset \(verse) sort de l'objectif.")
            }
        }
    }

    // MARK: Séance terminée

    func testCompleteSessionMarksKnowledgeAndSetsCompletedDate() throws {
        var state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 30)
        state.onboardingDone = true
        let session = try XCTUnwrap(state.sessions.first)

        let result = Program.completeSession(state, id: session.id, memorized: true, from: "2026-10-05")
        let updated = try XCTUnwrap(result.sessions.first { $0.id == session.id })

        XCTAssertEqual(updated.status, .done)
        XCTAssertEqual(updated.completedDate, "2026-10-05")
        XCTAssertNotNil(updated.completedAt)
        for verse in session.start...session.end {
            XCTAssertEqual(result.knowledge[String(verse)], .perfect)
            XCTAssertEqual(result.memorizedAt?[String(verse)], "2026-10-05")
        }
        // Une révision de départ est créée pour le lendemain.
        XCTAssertTrue(result.revisions.contains { $0.id == "r-\(session.start)-\(session.end)" })
    }

    /// LA règle à ne pas casser.
    ///
    /// Une personne peut faire sa séance en avance. Sa date *prévue* ne doit pas
    /// bouger pour autant : c'est elle qui structure le programme, et la déplacer
    /// décalerait tout ce qui suit. Seule `completedDate` enregistre l'avance.
    func testCompletingEarlyDoesNotMoveTheScheduledDate() throws {
        var state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 30)
        state.onboardingDone = true
        let session = try XCTUnwrap(state.sessions.first)
        let plannedDate = try XCTUnwrap(session.scheduledDate)

        // Terminée cinq jours avant la date prévue.
        let result = Program.completeSession(state, id: session.id, memorized: true, from: "2026-09-30")
        let updated = try XCTUnwrap(result.sessions.first { $0.id == session.id })

        XCTAssertEqual(updated.scheduledDate, plannedDate, "La date prévue a été déplacée.")
        XCTAssertEqual(updated.date, session.date, "Le jour d'origine a été déplacé.")
        XCTAssertEqual(updated.completedDate, "2026-09-30", "La date d'exécution n'a pas été enregistrée.")
    }

    func testNotMemorizedPostponesInsteadOfCompleting() throws {
        var state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 30)
        state.onboardingDone = true
        let session = try XCTUnwrap(state.sessions.first)

        let result = Program.completeSession(state, id: session.id, memorized: false, from: "2026-10-05")
        let updated = try XCTUnwrap(result.sessions.first { $0.id == session.id })

        XCTAssertEqual(updated.status, .postponed)
        XCTAssertEqual(updated.scheduledDate, session.scheduledDate)
        XCTAssertTrue(result.knowledge.isEmpty, "Rien ne doit être marqué comme su.")
    }

    /// Une séance interrompue doit rester reprenable : c'est le rôle de la clé
    /// `learning:<id>`. Si la clé était mal construite, cette séance serait
    /// reportée et la personne perdrait sa reprise.
    func testAPartialSessionStaysResumable() throws {
        var state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 30)
        let session = try XCTUnwrap(state.sessions.first)
        state.studyProgress = [
            Program.studyKey(.learning, session.id): StudyProgress(
                id: session.id,
                mode: .learning,
                category: nil,
                start: session.start,
                end: session.end,
                through: session.start,
                page: 1,
                source: "traditional",
                updatedAt: "2026-10-05T08:00:00.000Z",
                status: .partial,
                validations: []
            )
        ]

        let result = Program.postponeSession(state, id: session.id)
        let updated = try XCTUnwrap(result.sessions.first { $0.id == session.id })
        XCTAssertEqual(updated.status, .todo, "Une séance interrompue ne doit pas être reportée.")
    }

    func testCompletingAnUnknownSessionChangesNothing() {
        let state = Program.defaultState()
        let result = Program.completeSession(state, id: "inexistant", memorized: true)
        XCTAssertEqual(result.sessions.count, state.sessions.count)
        XCTAssertEqual(result.updatedAt, state.updatedAt)
    }
}

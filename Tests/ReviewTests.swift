// ReviewTests.swift
// Les règles de révision et de consolidation.
//
// Ces valeurs vivent dans le document synchronisé : les cycles de 7/14/21/30
// jours, les quantités 1 Nisf / 1 Hizb / 1 Juz / 2 Juz, et les consolidations
// J+1 / J+3 / J+7. Elles doivent rester exactement celles de l'application
// React Native, sinon les deux clients ne compteraient plus la même chose.

import XCTest
@testable import Swiftdeepseek

final class ReviewTests: XCTestCase {

    // MARK: Constantes partagées

    func testConstantsMatchTheReactNativeValues() {
        XCTAssertEqual(Review.consolidationOffsets, [1, 3, 7])
        XCTAssertEqual(Review.cycleOptions, [7, 14, 21, 30])
        XCTAssertEqual(Review.quantityOptions, ["nisf", "hizb", "juz", "juz2"])
    }

    func testReviewCycleDaysDefaultsToSeven() {
        XCTAssertEqual(Review.reviewCycleDays(Program.defaultState()), 7)
        var state = Program.defaultState()
        state.reviewSettings = ReviewSettings(enabled: true, cycleDays: 21)
        XCTAssertEqual(Review.reviewCycleDays(state), 21)
    }

    func testReviewsAreEnabledUnlessExplicitlyDisabled() {
        XCTAssertTrue(Review.reviewsEnabled(Program.defaultState()))
        var state = Program.defaultState()
        state.reviewSettings = ReviewSettings(enabled: false, cycleDays: 7)
        XCTAssertFalse(Review.reviewsEnabled(state))
    }

    // MARK: Quantités lisibles

    func testReviewQuantityNamesUnitsTheWayTheAppDoes() {
        XCTAssertEqual(Review.reviewQuantity([Int]()), "0 verset")

        let hizb = Quran.hizbs[0]
        XCTAssertEqual(Review.reviewQuantity(Array(hizb.start...hizb.end)), "1 Hizb")

        let nisf = Quran.halves[0]
        XCTAssertEqual(Review.reviewQuantity(Array(nisf.start...nisf.end)), "1 Nisf")

        let rub = Quran.quarters[0]
        XCTAssertEqual(Review.reviewQuantity(Array(rub.start...rub.end)), "1 Rubu’")
    }

    func testReviewQuantityFallsBackToVerses() {
        XCTAssertEqual(Review.reviewQuantity([1]), "1 verset")
        XCTAssertEqual(Review.reviewQuantity([1, 2]), "2 versets")
    }

    func testReviewQuantityIsStableRegardlessOfOrderOrRepetition() {
        let range = Array(Quran.halves[0].start...Quran.halves[0].end)
        let shuffled = Array(range.reversed()) + range
        XCTAssertEqual(Review.reviewQuantity(shuffled), Review.reviewQuantity(range))
    }

    // MARK: Répartition du corpus

    func testPartitioningAnEmptyCorpusYieldsNothing() {
        XCTAssertTrue(Review.partitionReviewCorpus([], length: 7).isEmpty)
    }

    func testPartitioningKeepsEveryVerseExactlyOnce() {
        let corpus = Array(1...700)
        let days = Review.partitionReviewCorpus(corpus, length: 7)
        XCTAssertEqual(days.count, 7, "Le cycle doit comporter exactement le nombre de jours demandé.")
        XCTAssertEqual(Set(days.flatMap { $0 }), Set(corpus), "Des versets ont été perdus ou dupliqués.")
    }

    func testPartitioningTheWholeQuranKeepsEveryVerse() {
        let corpus = Array(1...6236)
        let days = Review.partitionReviewCorpus(corpus, length: 30)
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(Set(days.flatMap { $0 }), Set(corpus))
    }

    // MARK: Cycle

    func testCreateCycleOnlyTakesEstablishedVerses() {
        // Un verset appris il y a moins de sept jours n'entre pas encore dans le
        // cycle : il passe d'abord par les consolidations J+1/J+3/J+7.
        var state = Program.defaultState()
        let today = "2026-10-05"
        state.knowledge = Dictionary(uniqueKeysWithValues: (1...20).map { (String($0), Mastery.perfect) })
        state.memorizedAt = Dictionary(uniqueKeysWithValues: (1...20).map { (String($0), DateKeys.addDays(today, -30)) })
        state.reviewModelStartedAt = today

        let cycle = Review.createCycle(state, at: today, index: 1)
        XCTAssertEqual(cycle.corpus, Array(1...20))
        XCTAssertEqual(cycle.days.count, 7)
        XCTAssertTrue(cycle.completed.isEmpty)
        XCTAssertTrue(cycle.assignments.isEmpty)
        XCTAssertEqual(cycle.startDate, today)
        XCTAssertEqual(cycle.index, 1)
    }

    func testRecentlyLearnedVersesStayOutOfTheCycle() {
        var state = Program.defaultState()
        let today = "2026-10-05"
        state.knowledge = Dictionary(uniqueKeysWithValues: (1...20).map { (String($0), Mastery.perfect) })
        state.memorizedAt = Dictionary(uniqueKeysWithValues: (1...20).map { (String($0), DateKeys.addDays(today, -2)) })
        state.reviewModelStartedAt = today

        let cycle = Review.createCycle(state, at: today, index: 1)
        XCTAssertTrue(cycle.corpus.isEmpty, "Un verset appris il y a deux jours n'est pas encore du cycle.")
    }

    // MARK: Réglages

    func testChangingTheCycleLengthKeepsThePreviousCycleInHistory() {
        var state = Program.defaultState()
        state.reviewCycle = ReviewCycle(
            index: 1,
            startDate: "2026-09-01",
            lengthDays: 7,
            corpus: [],
            days: [],
            completed: [],
            assignments: [:]
        )

        let result = Review.setReviewCycle(state, cycleDays: 14, at: "2026-10-05")
        XCTAssertEqual(result.reviewSettings?.cycleDays, 14)
        XCTAssertEqual(result.reviewSettings?.mode, "cycle")
        XCTAssertEqual(result.reviewCycleHistory?.count, 1)
        XCTAssertEqual(result.reviewCycleHistory?.first?.lengthDays, 7)
        XCTAssertEqual(result.reviewCycle?.index, 2)
        XCTAssertEqual(result.reviewCycle?.lengthDays, 14)
    }

    func testSettingAQuantitySwitchesModeWithoutLosingHistory() {
        var state = Program.defaultState()
        state.reviewCycle = ReviewCycle(
            index: 3,
            startDate: "2026-09-01",
            lengthDays: 7,
            corpus: [],
            days: [],
            completed: [],
            assignments: [:]
        )

        let result = Review.setReviewQuantity(state, quantity: "juz2", at: "2026-10-05")
        XCTAssertEqual(result.reviewSettings?.mode, "quantity")
        XCTAssertEqual(result.reviewSettings?.dailyQuantity, "juz2")
        XCTAssertEqual(result.reviewCycleHistory?.count, 1)
        XCTAssertEqual(result.reviewCycle?.index, 4)
    }

    // MARK: Consolidation

    /// LA règle des consolidations : les échéances restent ancrées à la date
    /// d'apprentissage. Faire une consolidation en avance ne la déplace pas —
    /// sinon J+3 et J+7 glisseraient à chaque fois.
    func testConsolidationDatesStayAnchoredToTheLearningDate() throws {
        let learned = "2026-10-01"
        var state = Program.defaultState()
        state.knowledge = ["1": .perfect, "2": .perfect]
        state.memorizedAt = ["1": learned, "2": learned]
        state.reviewModelStartedAt = learned

        let result = Review.completeConsolidation(
            state,
            range: VerseRange(start: 1, end: 2),
            at: learned
        )
        let consolidation = try XCTUnwrap(result.reviewConsolidations?["1"])

        XCTAssertEqual(consolidation.scheduledDates?["1"], DateKeys.addDays(learned, 1))
        XCTAssertEqual(consolidation.scheduledDates?["3"], DateKeys.addDays(learned, 3))
        XCTAssertEqual(consolidation.scheduledDates?["7"], DateKeys.addDays(learned, 7))
        // La consolidation a été faite le jour de l'apprentissage…
        XCTAssertEqual(consolidation.completed?["1"], learned)
        // …mais l'échéance enregistrée n'a pas bougé.
        XCTAssertNotEqual(consolidation.scheduledDates?["1"], learned)
    }

    func testConsolidationStepsAreConsumedInOrder() {
        let learned = "2026-10-01"
        var state = Program.defaultState()
        state.knowledge = ["1": .perfect]
        state.memorizedAt = ["1": learned]
        state.reviewModelStartedAt = learned

        let first = Review.completeConsolidation(state, range: VerseRange(start: 1, end: 1), at: learned)
        XCTAssertEqual(first.reviewConsolidations?["1"]?.completed?["1"], learned)
        XCTAssertNil(first.reviewConsolidations?["1"]?.completed?["3"])

        let second = Review.completeConsolidation(first, range: VerseRange(start: 1, end: 1), at: "2026-10-04")
        XCTAssertEqual(second.reviewConsolidations?["1"]?.completed?["3"], "2026-10-04")
        XCTAssertNil(second.reviewConsolidations?["1"]?.completed?["7"])

        let third = Review.completeConsolidation(second, range: VerseRange(start: 1, end: 1), at: "2026-10-08")
        XCTAssertEqual(third.reviewConsolidations?["1"]?.completed?["7"], "2026-10-08")
    }

    func testNextConsolidationReportsTheFollowingStep() {
        let learned = "2026-10-01"
        var state = Program.defaultState()
        state.knowledge = ["1": .perfect]
        state.memorizedAt = ["1": learned]
        state.reviewModelStartedAt = learned

        let prepared = Review.prepareReviewSchedule(state, at: learned)
        let next = Review.nextConsolidation(prepared, id: 1)
        XCTAssertEqual(next?.offset, 1)
        XCTAssertEqual(next?.due, DateKeys.addDays(learned, 1))
    }

    // MARK: Notation d'une tâche de révision

    /// `gradeReviewTask` n'était couvert par aucun test avant d'être branché
    /// dans la barre d'actions du lecteur (`ReaderView.gradeBar`). Ces règles
    /// décident de ce que voit la personne le lendemain : elles méritent d'être
    /// tenues par un test, pas seulement par une relecture.

    /// Le barème décide de l'échéance — `src/core/review.ts:153` :
    /// `due[id] = addDays(at, grade === 'rework' ? 1 : 2)`.
    func testReworkSchedulesTheVerseSoonerThanHesitant() {
        let at = "2026-10-05"

        let rework = Review.gradeReviewTask(
            gradedState(at: at),
            task: reviewTask(start: 1, end: 1),
            grade: .rework,
            at: at
        )
        XCTAssertEqual(rework.reviewPriorityDue?["1"], DateKeys.addDays(at, 1))

        let hesitant = Review.gradeReviewTask(
            gradedState(at: at),
            task: reviewTask(start: 1, end: 1),
            grade: .hesitant,
            at: at
        )
        XCTAssertEqual(hesitant.reviewPriorityDue?["1"], DateKeys.addDays(at, 2))
    }

    /// `perfect` efface la priorité d'un verset **non marqué**, mais repousse
    /// d'un cycle complet un verset **encore marqué** — il ne l'efface pas.
    ///
    /// L'état de départ porte volontairement une priorité déjà due : sans elle,
    /// l'assertion « effacée » serait vraie même si le code ne faisait rien.
    func testPerfectClearsAnUnmarkedVerseButPostponesAMarkedOne() {
        let at = "2026-10-05"
        let alreadyDue = ["1": DateKeys.addDays(at, -1)]

        var unmarked = gradedState(at: at)
        unmarked.reviewPriorityDue = alreadyDue
        let cleared = Review.gradeReviewTask(
            unmarked,
            task: reviewTask(start: 1, end: 1),
            grade: .perfect,
            at: at
        )
        XCTAssertNil(cleared.reviewPriorityDue?["1"])

        var marked = gradedState(at: at)
        marked.reviewPriorityDue = alreadyDue
        marked.difficultyMarkers = [
            "1": DifficultyMarker(
                user: DifficultyMarker.Entry(createdAt: "2026-09-01", comment: nil),
                admin: nil
            )
        ]
        let postponed = Review.gradeReviewTask(
            marked,
            task: reviewTask(start: 1, end: 1),
            grade: .perfect,
            at: at
        )
        XCTAssertEqual(
            postponed.reviewPriorityDue?["1"],
            DateKeys.addDays(at, Review.reviewCycleDays(marked))
        )
    }

    /// Toute note autre que `perfect` marque le verset comme **difficile** —
    /// c'est ce qui le fait apparaître en rouge clair dans le lecteur.
    func testAnyGradeButPerfectMarksTheVerseAsDifficult() {
        let at = "2026-10-05"

        for grade in [ReviewGrade.rework, .hesitant] {
            let next = Review.gradeReviewTask(
                gradedState(at: at),
                task: reviewTask(start: 1, end: 1),
                grade: grade,
                at: at
            )
            XCTAssertTrue(Review.isDifficult(next, 1), "\(grade) doit marquer le verset")
        }

        let perfect = Review.gradeReviewTask(
            gradedState(at: at),
            task: reviewTask(start: 1, end: 1),
            grade: .perfect,
            at: at
        )
        XCTAssertFalse(Review.isDifficult(perfect, 1))
    }

    /// LA règle de la date prévue : une révision faite **en avance** garde la
    /// date qui lui avait été assignée. `event.date` est le jour réel,
    /// `event.scheduledDate` celui du programme — et c'est le second qui décide
    /// de l'historique. Une séance faite en avance ne doit pas déplacer sa date.
    func testGradingKeepsTheScheduledDateEvenWhenDoneEarly() {
        let scheduled = "2026-10-20"
        let early = "2026-10-05"

        let next = Review.gradeReviewTask(
            gradedState(at: early),
            task: reviewTask(start: 1, end: 1, scheduledDate: scheduled),
            grade: .perfect,
            at: early
        )

        let event = next.reviewHistory?.last
        XCTAssertEqual(event?.date, early)
        XCTAssertEqual(event?.scheduledDate, scheduled)
        XCTAssertNotNil(event?.completedAt)
    }

    /// La première consolidation **due** est consommée par la notation : c'est
    /// le même verset qui avance dans J+1 / J+3 / J+7.
    func testGradingConsumesTheFirstDueConsolidation() {
        let learned = "2026-10-01"
        let at = "2026-10-02"

        var state = Program.defaultState()
        state.knowledge = ["1": .perfect]
        state.memorizedAt = ["1": learned]
        state.reviewModelStartedAt = learned

        let next = Review.gradeReviewTask(
            state,
            task: reviewTask(start: 1, end: 1),
            grade: .perfect,
            at: at
        )
        XCTAssertEqual(next.reviewConsolidations?["1"]?.completed?["1"], at)
        XCTAssertNil(next.reviewConsolidations?["1"]?.completed?["3"])
    }

    // MARK: Fabriques des tests de notation

    /// Un état où le verset 1 est connu, et où le programme de révision est déjà
    /// préparé pour `at` — donc prêt à être noté.
    private func gradedState(at: String) -> AppState {
        var state = Program.defaultState()
        state.knowledge = ["1": .perfect]
        state.memorizedAt = ["1": "2026-09-01"]
        state.reviewModelStartedAt = "2026-09-01"
        return Review.prepareReviewSchedule(state, at: at)
    }

    private func reviewTask(start: Int, end: Int, scheduledDate: String? = nil) -> ReviewTask {
        ReviewTask(
            id: "tache-\(start)-\(end)",
            start: start,
            end: end,
            scheduledDate: scheduledDate,
            category: .habitual,
            label: "Révision"
        )
    }

    // MARK: Versets difficiles

    func testDifficultyMarkingSurvivesUntilDeliberatelyRemoved() {
        var state = Program.defaultState()
        state.knowledge = ["1": .perfect]

        let marked = Review.toggleDifficulty(state, id: 1, at: "2026-10-05")
        XCTAssertTrue(Review.isDifficult(marked, 1))
        XCTAssertEqual(marked.reviewPriorityDue?["1"], "2026-10-05")
        XCTAssertEqual(marked.difficultyHistory?.count, 1)

        let cleared = Review.toggleDifficulty(marked, id: 1, at: "2026-10-06")
        XCTAssertFalse(Review.isDifficult(cleared, 1))
        XCTAssertNil(cleared.reviewPriorityDue?["1"])
        // L'historique conserve la trace des deux gestes.
        XCTAssertEqual(cleared.difficultyHistory?.count, 2)
    }

    func testDifficultyMarkingIgnoresOutOfRangeVerses() {
        let state = Program.defaultState()
        XCTAssertEqual(Review.toggleDifficulty(state, id: 0).difficultyMarkers?.count, 0)
        XCTAssertEqual(Review.toggleDifficulty(state, id: 9999).difficultyMarkers?.count, 0)
    }

    /// L'ensemble des versets à afficher en rouge — `App.tsx:499` :
    ///
    ///     Object.keys(state.difficultyMarkers ?? {})
    ///       .filter(id => state.difficultyMarkers?.[id]?.user || state.difficultyMarkers?.[id]?.admin)
    ///       .map(Number)
    ///
    /// Un marqueur posé par l'utilisateur compte, un marqueur posé par un
    /// encadrant compte, les deux ensemble comptent. Un marqueur dont les deux
    /// entrées sont absentes ne compte pas : c'est le cas défensif, les deux
    /// applications supprimant la clé au retrait.
    func testDifficultIDsCollectsMarkersFromBothOrigins() {
        let user = DifficultyMarker.Entry(createdAt: "2026-10-01", comment: nil)
        let admin = DifficultyMarker.Entry(createdAt: "2026-10-02", comment: "à revoir")

        var state = Program.defaultState()
        state.difficultyMarkers = [
            "12": DifficultyMarker(user: user, admin: nil),
            "13": DifficultyMarker(user: nil, admin: admin),
            "14": DifficultyMarker(user: user, admin: admin),
            "15": DifficultyMarker(user: nil, admin: nil),
            "abc": DifficultyMarker(user: user, admin: nil)
        ]

        XCTAssertEqual(Review.difficultIDs(state), [12, 13, 14])
    }

    func testDifficultIDsIsEmptyWithoutMarkers() {
        XCTAssertTrue(Review.difficultIDs(Program.defaultState()).isEmpty)
    }

    /// L'ensemble doit rester d'accord avec `isDifficult` : l'affichage en rouge
    /// et le bouton de marquage ne doivent jamais dire deux choses différentes.
    func testDifficultIDsAgreesWithIsDifficult() {
        let state = Review.toggleDifficulty(Program.defaultState(), id: 2, at: "2026-10-05")

        let ids = Review.difficultIDs(state)
        XCTAssertEqual(ids, [2])
        for id in 1...3 {
            XCTAssertEqual(ids.contains(id), Review.isDifficult(state, id), "verset \(id)")
        }
    }

    // MARK: Plan du jour

    func testReviewPlanOfAnEmptyAccountHasNothingToDo() {
        let plan = Review.reviewPlan(Program.defaultState(), at: "2026-10-05")
        XCTAssertTrue(plan.session.isEmpty)
        XCTAssertTrue(plan.recent.isEmpty)
        XCTAssertTrue(plan.priority.isEmpty)
        XCTAssertTrue(plan.habitual.isEmpty)
        XCTAssertTrue(plan.consolidations.isEmpty)
        XCTAssertEqual(plan.completeJuz, 0)
        XCTAssertEqual(plan.completeRub, 0)
        XCTAssertEqual(plan.completeNisf, 0)
    }

    func testReviewPlanSurfacesDueConsolidations() {
        let today = "2026-10-05"
        let learned = DateKeys.addDays(today, -3)
        var state = Program.defaultState()
        state.knowledge = Dictionary(uniqueKeysWithValues: (1...5).map { (String($0), Mastery.perfect) })
        state.memorizedAt = Dictionary(uniqueKeysWithValues: (1...5).map { (String($0), learned) })
        state.reviewModelStartedAt = learned

        let plan = Review.reviewPlan(state, at: today)

        XCTAssertFalse(plan.session.isEmpty, "Des consolidations sont dues : la séance ne peut pas être vide.")
        // Les cinq versets se suivent dans la même sourate : ils forment une
        // seule tâche, pas cinq.
        XCTAssertEqual(plan.recent.count, 1)
        XCTAssertEqual(plan.recent.first?.start, 1)
        XCTAssertEqual(plan.recent.first?.end, 5)
        XCTAssertEqual(plan.recent.first?.scheduledDate, DateKeys.addDays(learned, 1))
        XCTAssertEqual(plan.consolidations.count, 1)
    }

    func testReviewPlanDoesNotRepeatAVerseAlreadyReviewedToday() {
        let today = "2026-10-05"
        let learned = DateKeys.addDays(today, -3)
        var state = Program.defaultState()
        state.knowledge = Dictionary(uniqueKeysWithValues: (1...5).map { (String($0), Mastery.perfect) })
        state.memorizedAt = Dictionary(uniqueKeysWithValues: (1...5).map { (String($0), learned) })
        state.reviewModelStartedAt = learned
        // Les cinq versets ont déjà été revus aujourd'hui.
        state.reviewHistory = [
            ReviewEvent(
                id: "e1",
                date: today,
                scheduledDate: DateKeys.addDays(learned, 1),
                completedAt: "2026-10-05T08:00:00.000Z",
                start: 1,
                end: 5,
                category: .recent,
                grade: ReviewGrade.perfect.rawValue
            )
        ]

        let plan = Review.reviewPlan(state, at: today)
        XCTAssertTrue(plan.session.isEmpty, "Un verset déjà revu aujourd'hui ne doit pas être reproposé.")
    }

    func testReviewPlanRespectsDisabledReviews() {
        var state = Program.defaultState()
        state.reviewSettings = ReviewSettings(enabled: false, cycleDays: 7)
        state.knowledge = ["1": .perfect]
        state.memorizedAt = ["1": "2026-09-01"]

        let plan = Review.reviewPlan(state, at: "2026-10-05")
        XCTAssertTrue(plan.session.isEmpty)
        XCTAssertTrue(plan.recent.isEmpty)
        XCTAssertTrue(plan.priority.isEmpty)
    }

    // MARK: L'activation de l'espace Révisions

    /// `setReviewsEnabled` — `src/core/review.ts:53`.
    ///
    /// La durée choisie survit à l'extinction : l'original **ré-épingle**
    /// `cycleDays` à `reviewCycleDays(state)`, il ne le remet pas à 7.
    func testEnablingReviewsKeepsTheChosenCycleAndStampsTheResume() {
        var state = Program.defaultState()
        state.reviewSettings = ReviewSettings(enabled: false, cycleDays: 21)

        let result = Review.setReviewsEnabled(state, enabled: true, at: "2026-10-05")

        XCTAssertTrue(Review.reviewsEnabled(result))
        XCTAssertEqual(result.reviewSettings?.cycleDays, 21, "Une durée de 21 jours ne redevient pas 7.")
        XCTAssertEqual(result.reviewSettings?.resumedAt, "2026-10-05", "Le retour est horodaté.")
    }

    /// `resumedAt` n'est écrit qu'à l'**activation** : l'original écrit
    /// `...(enabled ? {resumedAt: at} : {})`, donc désactiver ne l'efface pas.
    ///
    /// Aucune lecture n'en est faite — ni ici, ni dans l'application React
    /// Native, où il n'apparaît que dans le type et dans cette ligne. C'est
    /// pourquoi il faut le porter tel quel : un champ que personne ne lit ne se
    /// voit pas manquer, et le jour où un client le lira, les deux documents
    /// différeront en silence.
    func testDisablingReviewsKeepsThePreviousResumeDate() {
        var state = Program.defaultState()
        state.reviewSettings = ReviewSettings(enabled: true, cycleDays: 7, resumedAt: "2026-09-01")

        let result = Review.setReviewsEnabled(state, enabled: false, at: "2026-10-05")

        XCTAssertFalse(Review.reviewsEnabled(result))
        XCTAssertEqual(result.reviewSettings?.resumedAt, "2026-09-01", "Désactiver n'efface pas la date.")
    }

    /// Le retour anticipé de l'original : viser la valeur déjà en place ne
    /// touche pas le document, donc n'avance pas `updatedAt` — et n'invente pas
    /// d'horodatage de reprise.
    func testSettingTheSameValueLeavesTheDocumentUntouched() {
        let state = Program.defaultState()
        XCTAssertTrue(Review.reviewsEnabled(state), "Le document initial a les révisions actives.")

        let result = Review.setReviewsEnabled(state, enabled: true, at: "2026-10-05")

        XCTAssertEqual(result.updatedAt, state.updatedAt, "Aucune écriture quand rien ne change.")
        XCTAssertNil(result.reviewSettings?.resumedAt, "Et surtout : aucun horodatage inventé.")
    }

    /// Un état **sans** `reviewSettings` ressort avec `cycleDays` à 7 : c'est le
    /// repli de `reviewCycleDays`, et non un champ absent.
    func testDisablingReviewsOnAnEmptySettingsPinsTheCycleToSeven() {
        var state = Program.defaultState()
        state.reviewSettings = nil

        let result = Review.setReviewsEnabled(state, enabled: false, at: "2026-10-05")

        XCTAssertFalse(Review.reviewsEnabled(result))
        XCTAssertEqual(result.reviewSettings?.cycleDays, 7)
    }
}

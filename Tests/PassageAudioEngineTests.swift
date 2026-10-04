// PassageAudioEngineTests.swift
// La boucle de répétition : chaque transition, et ses effets.
//
// LES VALEURS SONT MESURÉES, PAS DÉDUITES DU CODE
//   Les positions attendues viennent de `PassageAudio.next` et les attentes de
//   `PassageAudio.waitMilliseconds`, tous deux figés par
//   `_banc/oracle-audio.mjs` sur le **vrai** `src/core/audio.ts`. Les séquences
//   d'effets, elles, sont ancrées sur les lignes décisives de
//   `src/PassageAudioPlayer.tsx` : la section 16 du banc extrait ces lignes du
//   TSX et vérifie qu'elles se trouvent dans `Core/PassageAudioEngine.swift`
//   **et dans l'ordre**. Une transition qui s'inverserait ferait donc tomber le
//   banc, et pas seulement ce fichier.
//
// CE QUE CES TESTS NE PROUVENT PAS
//   Qu'AVFoundation joue, ni que la minuterie de borne se déclenche à la bonne
//   milliseconde sur un appareil. Ce sont les deux parties qui ne se prouvent
//   pas sans appareil ; elles sont isolées dans l'exécuteur d'effets, qui ne
//   contient aucune décision.

import XCTest
@testable import Swiftdeepseek

final class PassageAudioEngineTests: XCTestCase {

    private func preferences(
        count: AudioRepeatPreferences.CountChoice = .times(3),
        custom: String = "20",
        mode: RepeatMode = .passage,
        gap: Int = 0,
        speed: Double = 1,
        autoStop: Bool = true
    ) -> AudioRepeatPreferences {
        AudioRepeatPreferences(countChoice: count, customCount: custom, repeatMode: mode,
                               gap: gap, speed: speed, autoStop: autoStop)
    }

    /// Amène la machine jusqu'à un état `playing` sur `position`.
    private func playing(
        range: VerseRange = VerseRange(start: 1, end: 7),
        _ prefs: AudioRepeatPreferences? = nil
    ) -> PassageAudioEngine {
        var engine = PassageAudioEngine()
        _ = engine.begin(range: range, preferences: prefs ?? preferences())
        _ = engine.loadSucceeded()
        return engine
    }

    // MARK: - `begin`

    func testTheRangeIsResolvedBeforeTheCustomCountIsRefused() {
        // `:175-179` — `selectionRange()` est évaluée AVANT le refus du compte.
        // Une plage invalide l'emporte donc sur un champ libre invalide : c'est
        // l'ordre de l'original, et il est observable par le message affiché.
        var engine = PassageAudioEngine()
        let effects = engine.begin(
            range: VerseRange(start: 0, end: 5),
            preferences: preferences(count: .custom, custom: "5000")
        )
        XCTAssertEqual(effects, [.fail("Choisis une plage de versets valide.")])
        XCTAssertEqual(engine.phase, .idle)
    }

    func testTheCustomCountIsRefusedAtLaunchWithTheOriginalMessage() {
        // `:176` — `'5000'` est un entier, mais hors de 1…999 : il est refusé au
        // lancement, alors que `:79` l'aurait normalisé en 5000. Les deux
        // fonctions ne disent pas la même chose.
        var engine = PassageAudioEngine()
        let effects = engine.begin(
            range: VerseRange(start: 1, end: 7),
            preferences: preferences(count: .custom, custom: "5000")
        )
        XCTAssertEqual(effects, [.fail("Choisis entre 1 et 999 écoutes.")])
        XCTAssertEqual(engine.phase, .idle)
    }

    func testAValidRangeStartsOnItsFirstVerse() {
        var engine = PassageAudioEngine()
        let effects = engine.begin(range: VerseRange(start: 3, end: 9), preferences: preferences())
        XCTAssertEqual(effects, [.load(AudioPosition(verseID: 3, repetition: 1))])
        XCTAssertEqual(engine.phase, .loading(AudioPosition(verseID: 3, repetition: 1)))
    }

    func testAFinishedLoadAnnouncesTheVerseAndPlays() {
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 1, end: 7), preferences: preferences())
        XCTAssertEqual(engine.loadSucceeded(), [.announceVerse(1)])
        XCTAssertEqual(engine.phase, .playing(AudioPosition(verseID: 1, repetition: 1)))
    }

    func testAFailedLoadFailsAndClearsTheVerse() {
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 1, end: 7), preferences: preferences())
        XCTAssertEqual(engine.loadFailed("Lecture indisponible."),
                       [.fail("Lecture indisponible."), .announceVerse(nil)])
        XCTAssertEqual(engine.phase, .completed(AudioPosition(verseID: 1, repetition: 1)))
    }

    // MARK: - `finish` : ce qui s'enchaîne, ce qui s'arrête

    func testWithinTheRangeTheNextVerseKeepsTheFloorOfTwoHundredMilliseconds() {
        // `:196` — ni redémarrage, ni verset répété : la marge technique de
        // 200 ms est SEULE, même avec un silence choisi de 10 s.
        var engine = playing(preferences(gap: 10))
        let effects = engine.finish(timelineCoversNextVerse: false)
        XCTAssertEqual(effects, [
            .pause,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 2, repetition: 1))
        ])
    }

    func testAtTheEndOfTheRangeTheChosenGapApplies() {
        // `:194-196` — `restart` est vrai : le silence choisi s'applique, et la
        // marge de 200 ms devient un plancher, pas un plafond.
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 5, end: 7), preferences: preferences(gap: 5))
        _ = engine.loadSucceeded()
        _ = engine.finish(timelineCoversNextVerse: false)   // 5 → 6
        _ = engine.waitElapsed()
        _ = engine.finish(timelineCoversNextVerse: false)   // 6 → 7
        _ = engine.waitElapsed()
        // 7 est le dernier : on redémarre au début, répétition 2.
        let effects = engine.finish(timelineCoversNextVerse: false)
        XCTAssertEqual(effects, [
            .pause,
            .scheduleWait(milliseconds: 5000, next: AudioPosition(verseID: 5, repetition: 2))
        ])
    }

    func testTheLastPassageOfAFinishedCountStopsInsteadOfRestarting() {
        // Règle 1 : `nil` est le seul cas où l'on conclut. Avec `count = 2` sur
        // une plage de deux versets, le passage compte **quatre** écoutes —
        // (1,1) (2,1) (1,2) (2,2) — et ne s'arrête qu'après la dernière.
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 1, end: 2), preferences: preferences(count: .times(2)))
        _ = engine.loadSucceeded()
        // Trois enchaînements, et aucun ne conclut. La garde porte sur l'ÉTAT et
        // non sur la séquence d'effets : écrire ici la séquence attendue ferait
        // apparaître dans ce fichier, en négatif, la chaîne que le banc cherche
        // en positif — et une séquence mutée ailleurs resterait « trouvée ».
        for step in 1...3 {
            _ = engine.finish(timelineCoversNextVerse: false)
            guard case .waiting = engine.phase else {
                XCTFail("la machine a conclu au tour \(step) alors que le compte n'était pas épuisé")
                return
            }
            _ = engine.waitElapsed()
        }
        let effects = engine.finish(timelineCoversNextVerse: false)
        XCTAssertEqual(effects, [.pause, .cancelWait, .announceVerse(nil)])
        XCTAssertEqual(engine.phase, .completed(AudioPosition(verseID: 2, repetition: 2)))
    }

    func testInEachVerseModeARepeatedVerseTakesTheChosenGap() {
        // `:195-196` — `repeatedVerse` est vrai : même verset, répétition qui
        // augmente. Le silence choisi s'applique donc ici aussi.
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 1, end: 3),
                         preferences: preferences(count: .times(3), mode: .eachVerse, gap: 2))
        _ = engine.loadSucceeded()
        let effects = engine.finish(timelineCoversNextVerse: false)
        XCTAssertEqual(effects, [
            .pause,
            .scheduleWait(milliseconds: 2000, next: AudioPosition(verseID: 1, repetition: 2))
        ])
    }

    func testInEachVerseModeContinuousNeverLeavesTheVerse() {
        // Règle 3 de `Core/PassageAudio.swift` : `continuous` en mode « verset
        // par verset » ne fait jamais avancer le verset.
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 4, end: 9),
                         preferences: preferences(count: .continuous, mode: .eachVerse))
        _ = engine.loadSucceeded()
        // Les quatre répétitions, accumulées puis comparées D'UN SEUL TENANT :
        // le banc relit cette séquence entière dans ce fichier, et quatre
        // assertions séparées ne s'y lisent pas comme une séquence.
        var sequence: [PassageAudioEffect] = []
        for _ in 1...4 {
            sequence += engine.finish(timelineCoversNextVerse: false)
            _ = engine.waitElapsed()
        }
        XCTAssertEqual(sequence, [
            .pause,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 4, repetition: 2)),
            .pause,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 4, repetition: 3)),
            .pause,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 4, repetition: 4)),
            .pause,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 4, repetition: 5))
        ])
    }

    func testWithAutoStopOffThePassageNeverEnds() {
        // `:158` — `unlimited` couvre DEUX causes : « en continu », et l'arrêt
        // automatique décoché. Ici le compte vaut 1, et pourtant on redémarre.
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 1, end: 1),
                         preferences: preferences(count: .times(1), autoStop: false))
        _ = engine.loadSucceeded()
        let effects = engine.finish(timelineCoversNextVerse: false)
        XCTAssertEqual(effects, [
            .pause,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 1, repetition: 2))
        ])
    }

    // MARK: - L'attente : reprise ou rechargement

    func testAVerseThatFollowsInTheSameTimelineResumesWithoutReloading() {
        // Règle 3 : `continuation` — le verset suivant est dans la même piste.
        // La lecture ne s'interrompt pas, donc aucun `load`.
        var engine = playing()
        _ = engine.finish(timelineCoversNextVerse: true)
        let effects = engine.waitElapsed()
        XCTAssertEqual(effects, [.resume, .announceVerse(2)])
        XCTAssertEqual(engine.phase, .playing(AudioPosition(verseID: 2, repetition: 1)))
    }

    func testAVerseWithoutTimelineIsLoadedAfresh() {
        var engine = playing()
        _ = engine.finish(timelineCoversNextVerse: false)
        let effects = engine.waitElapsed()
        XCTAssertEqual(effects, [.load(AudioPosition(verseID: 2, repetition: 1))])
    }

    func testATimelineThatDoesNotCoverTheNextVerseDoesNotResume() {
        // La piste existe, mais elle s'arrête au verset courant : la
        // « continuation » est fausse, et le verset suivant se recharge.
        var engine = playing()
        let effects = engine.finish(timelineCoversNextVerse: false)
        XCTAssertEqual(effects, [
            .pause,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 2, repetition: 1))
        ])
    }

    // MARK: - `playPause`

    func testPausingWhilePlayingStopsAndKeepsThePosition() {
        var engine = playing()
        let effects = engine.playPause()
        XCTAssertEqual(effects, [.pause, .cancelWait])
        XCTAssertEqual(engine.phase, .paused(AudioPosition(verseID: 1, repetition: 1)))
    }

    func testPausingDuringTheWaitKeepsTheRemainingTimeAndNotTheFullOne() {
        // Règle 4. La première pause mémorise 200 ms ; la seconde doit planifier
        // 200 ms, et NON une attente recalculée ou une attente nulle.
        var engine = playing()
        _ = engine.finish(timelineCoversNextVerse: false)
        XCTAssertEqual(engine.phase,
                       .waiting(next: AudioPosition(verseID: 2, repetition: 1), milliseconds: 200))

        let paused = engine.playPause()
        XCTAssertEqual(engine.phase, .paused(AudioPosition(verseID: 2, repetition: 1)))

        let resumed = engine.playPause()
        // Les deux appels sont comparés D'UN SEUL TENANT : le banc relit cette
        // séquence entière dans le fichier, et deux assertions séparées ne s'y
        // lisent pas comme une séquence.
        XCTAssertEqual(paused + resumed, [
            .pause,
            .cancelWait,
            .scheduleWait(milliseconds: 200, next: AudioPosition(verseID: 2, repetition: 1))
        ])
        XCTAssertEqual(engine.phase,
                       .waiting(next: AudioPosition(verseID: 2, repetition: 1), milliseconds: 200))
    }

    func testPausingWhileLoadingIsNotAnError() {
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 1, end: 7), preferences: preferences())
        XCTAssertEqual(engine.phase, .loading(AudioPosition(verseID: 1, repetition: 1)))
        let effects = engine.playPause()
        XCTAssertEqual(effects, [.pause, .cancelWait])
        XCTAssertEqual(engine.phase, .paused(AudioPosition(verseID: 1, repetition: 1)))
    }

    func testResumingAPausedVerseDoesNotReloadIt() {
        var engine = playing()
        _ = engine.playPause()
        XCTAssertEqual(engine.playPause(), [.resume])
    }

    func testACompletedPassageRestartsFromTheBeginning() {
        // `:231` — `completedRef` vrai : `begin()`, donc on repart du premier
        // verset de la plage, à la répétition 1.
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 6, end: 8), preferences: preferences(count: .times(1)))
        _ = engine.loadSucceeded()
        _ = engine.finish(timelineCoversNextVerse: false)   // 6 → 7
        _ = engine.waitElapsed()
        _ = engine.finish(timelineCoversNextVerse: false)   // 7 → 8
        _ = engine.waitElapsed()
        let ended = engine.finish(timelineCoversNextVerse: false)
        let restarted = engine.playPause()
        // La conclusion et la relance, d'un seul tenant : le banc relit la
        // séquence entière, et « on conclut puis on repart du premier verset »
        // n'est vrai que dans cet ordre.
        XCTAssertEqual(ended + restarted, [
            .pause,
            .cancelWait,
            .announceVerse(nil),
            .load(AudioPosition(verseID: 6, repetition: 1))
        ])
    }

    // MARK: - `stop`, `jump`, vitesse

    func testStoppingReleasesAndClearsTheVerse() {
        var engine = playing()
        XCTAssertEqual(engine.stop(), [.stop, .cancelWait, .announceVerse(nil)])
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.range)
        // Un second arrêt ne redemande rien : il n'y avait plus de source.
        XCTAssertEqual(engine.stop(), [])
    }

    func testJumpingIsClampedInsideTheRange() {
        var engine = PassageAudioEngine()
        _ = engine.begin(range: VerseRange(start: 3, end: 5), preferences: preferences())
        _ = engine.loadSucceeded()
        // « précédent » au premier verset relance le premier, et « suivant » au
        // dernier le relance aussi : la borne est clampée des deux côtés. Les
        // quatre sauts sont comparés d'un seul tenant, pour que le banc les lise
        // comme une séquence.
        let back = engine.jump(-1)
        _ = engine.loadSucceeded()
        let forward = engine.jump(1)
        _ = engine.loadSucceeded()
        let last = engine.jump(1)
        _ = engine.loadSucceeded()
        let beyond = engine.jump(1)
        XCTAssertEqual(back + forward + last + beyond, [
            .load(AudioPosition(verseID: 3, repetition: 1)),
            .load(AudioPosition(verseID: 4, repetition: 1)),
            .load(AudioPosition(verseID: 5, repetition: 1)),
            .load(AudioPosition(verseID: 5, repetition: 1))
        ])
    }

    func testJumpingResetsTheRepetitionCounter() {
        // `:229` — `startAt({verseId: id, repetition: 1})` : sauter remet le
        // compteur à 1, quel que soit le nombre de répétitions déjà faites.
        var engine = playing()
        _ = engine.finish(timelineCoversNextVerse: false)
        _ = engine.waitElapsed()                            // sur le verset 2, répétition 1
        XCTAssertEqual(engine.jump(-1), [.load(AudioPosition(verseID: 1, repetition: 1))])
    }

    func testChangingTheSpeedOnlySignalsWhileSomethingIsLoaded() {
        var engine = playing()
        XCTAssertEqual(engine.setPreferences(preferences(speed: 1.25)), [.setRate(1.25)])
        // Une vitesse identique ne réémet rien.
        XCTAssertEqual(engine.setPreferences(preferences(speed: 1.25)), [])
        // À l'arrêt, rien à réarmer.
        _ = engine.stop()
        XCTAssertEqual(engine.setPreferences(preferences(speed: 0.75)), [])
    }

    func testFollowingTheTimelineAdvancesTheDisplayWithoutChangingTheRepetition() {
        var engine = playing()
        let effects = engine.followContinuously(AudioPosition(verseID: 2, repetition: 1))
        XCTAssertEqual(effects, [.announceVerse(2)])
        XCTAssertEqual(engine.phase, .playing(AudioPosition(verseID: 2, repetition: 1)))
        // Une position identique ne réémet rien.
        XCTAssertEqual(engine.followContinuously(AudioPosition(verseID: 2, repetition: 1)), [])
    }

    func testPlayPauseOnAnIdleEngineFails() {
        var engine = PassageAudioEngine()
        XCTAssertEqual(engine.playPause(), [.fail("Aucun passage sélectionné.")])
    }
}

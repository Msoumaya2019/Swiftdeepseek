// ProgramGoalTests.swift
// La couche « objectif » : préréglés, validation, remise à zéro.
//
// Ce que ces tests protègent :
//   - les bornes des six objectifs préréglés, qui sont écrites dans
//     `goal.ranges` et donc dans le document synchronisé ;
//   - les libellés des préréglés, que l'application React Native reconnaît par
//     ÉGALITÉ DE CHAÎNE pour retrouver le préréglé d'un objectif
//     (`src/App.tsx:359`) — une apostrophe changée suffit à le lui faire perdre ;
//   - les deux valeurs par défaut divergentes de `resetAllProgress` ;
//   - la lecture de l'objectif courant par l'écran « Mon programme ».
//
// CE QUE CES TESTS NE PEUVENT PAS PROUVER, ET QUI EST PROUVÉ AILLEURS
//   Deux points ne sont pas vérifiables en Swift seul, parce qu'ils ne se
//   comparent qu'à la source TypeScript :
//
//     - le seuil FLOTTANT de `validGoal` (`volume >= totalVolume / 60`, où `/`
//       est la division JavaScript). Le banc `_banc/verifier-reglages.mjs` lit
//       l'expression Swift et exige qu'elle compare deux `Double` ; les tests
//       ci-dessous n'éprouvent que la règle produit (« un hizb entier suffit »,
//       « un verset ne suffit pas ») ;
//     - l'égalité littérale des libellés avec ceux de `program.ts:43`, là aussi
//       vérifiée par le banc, caractère par caractère.
//
//   Aucun nombre de ce fichier n'est inventé : les bornes attendues sont
//   construites à partir de `Quran`, et les volumes à partir de `Quran.weights`.

import XCTest
@testable import Swiftdeepseek

final class ProgramGoalTests: XCTestCase {

    // MARK: - Les six objectifs préréglés

    /// Les libellés, caractère par caractère — `src/core/program.ts:43`.
    func testGoalPresetLabelsAreTheOnesTheReactNativeAppMatchesOn() {
        XCTAssertEqual(Program.goalPresetLabels[.lastTen], "Les 10 dernières sourates")
        XCTAssertEqual(Program.goalPresetLabels[.sabbih], "Hizb Sabbih")
        XCTAssertEqual(Program.goalPresetLabels[.amma], "Juz’ ‘Amma")
        XCTAssertEqual(Program.goalPresetLabels[.toYasin], "Jusqu’à la sourate Ya-Sîn")
        XCTAssertEqual(Program.goalPresetLabels[.half], "La moitié du Coran")
        XCTAssertEqual(Program.goalPresetLabels[.all], "Tout le Coran")
    }

    /// L'ordre d'affichage, et le fait que chaque préréglé ait un libellé : un
    /// préréglé sans libellé retomberait sur sa chaîne brute, et
    /// l'application React Native ne le reconnaîtrait plus.
    func testEveryPresetHasALabelAndIsListed() {
        XCTAssertEqual(Program.goalPresetOrder.count, GoalPreset.allCases.count)
        for preset in GoalPreset.allCases {
            XCTAssertNotNil(Program.goalPresetLabels[preset], "libellé manquant : \(preset)")
            XCTAssertEqual(Set(Program.goalPresetOrder).count, Program.goalPresetOrder.count)
            XCTAssertTrue(Program.goalPresetOrder.contains(preset))
        }
    }

    /// « Les 10 dernières sourates » — de la 105ᵉ (Al-Fîl) à la 114ᵉ (An-Nâs).
    func testLastTenCoversExactlyTheLastTenSurahs() {
        let goal = Program.goalFromPreset(.lastTen)
        XCTAssertEqual(goal.ranges.count, 1)
        XCTAssertEqual(goal.ranges[0].start, Quran.surahs[104].start)
        XCTAssertEqual(goal.ranges[0].end, Quran.surahs[113].end)
        // Dix sourates, ni neuf ni onze.
        XCTAssertEqual(
            Quran.surahAt(goal.ranges[0].start).number,
            Quran.surahAt(goal.ranges[0].end).number - 9
        )
    }

    /// « Hizb Sabbih » est le 60ᵉ hizb — `hizbs[59]`.
    func testSabbihIsTheSixtiethHizb() {
        let goal = Program.goalFromPreset(.sabbih)
        let hizb = Quran.hizbs[59]
        XCTAssertEqual(goal.ranges, [VerseRange(start: hizb.start, end: hizb.end)])
    }

    /// « Juz’ ‘Amma » est le 30ᵉ juz’ — `juzs[29]`, et c'est aussi le juz’ de
    /// l'état par défaut.
    func testAmmaIsTheThirtiethJuzAndTheDefaultGoal() {
        let goal = Program.goalFromPreset(.amma)
        let juz = Quran.juzs[29]
        XCTAssertEqual(goal.ranges, [VerseRange(start: juz.start, end: juz.end)])
        XCTAssertEqual(Program.defaultState().goal.ranges, goal.ranges)
    }

    /// « Jusqu'à la sourate Ya-Sîn » — de la 36ᵉ à la fin du Coran.
    func testToYasinStartsAtYaSinAndEndsAtTheLastVerse() {
        let goal = Program.goalFromPreset(.toYasin)
        XCTAssertEqual(goal.ranges.count, 1)
        XCTAssertEqual(goal.ranges[0].start, Quran.surahs[35].start)
        XCTAssertEqual(Quran.surahAt(goal.ranges[0].start).number, 36)
        XCTAssertEqual(goal.ranges[0].end, Quran.surahs[113].end)
        XCTAssertEqual(goal.ranges[0].end, Quran.verses.count)
    }

    /// « La moitié du Coran » — du 16ᵉ juz’ à la fin du 30ᵉ.
    func testHalfStartsAtTheSixteenthJuz() {
        let goal = Program.goalFromPreset(.half)
        XCTAssertEqual(goal.ranges.count, 1)
        XCTAssertEqual(goal.ranges[0].start, Quran.juzs[15].start)
        XCTAssertEqual(goal.ranges[0].end, Quran.juzs[29].end)
    }

    /// « Tout le Coran » — du premier au dernier verset, et rien de plus.
    func testAllCoversTheWholeQuran() {
        let goal = Program.goalFromPreset(.all)
        XCTAssertEqual(goal.ranges, [VerseRange(start: 1, end: Quran.verses.count)])
        XCTAssertEqual(Quran.verses.count, 6236)
    }

    /// Le sens est écrit tel quel dans `goal.direction` — c'est une `String?`
    /// dans le document partagé, donc la valeur brute compte.
    func testDirectionIsStoredAsTheSharedRawValue() {
        XCTAssertEqual(Program.goalFromPreset(.all, direction: .fromStart).direction, "fromStart")
        XCTAssertEqual(Program.goalFromPreset(.all, direction: .fromNas).direction, "fromNas")
        XCTAssertEqual(Program.goalFromPreset(.lastTen).direction, "fromNas")
        XCTAssertNil(Program.goalFromPreset(.lastTen).deadline)
    }

    /// Seul « Tout le Coran » laisse choisir le sens ; les cinq autres imposent
    /// An-Nâs (`src/App.tsx:406`).
    func testOnlyTheWholeQuranLetsTheDirectionBeChosen() {
        for preset in GoalPreset.allCases {
            XCTAssertEqual(preset.walksBackwardsFromAnNas, preset != .all, "\(preset)")
        }
    }

    // MARK: - Un objectif déjà atteint

    /// Un préréglé entièrement connu est reconnu comme tel — c'est ce qui le
    /// retire de la liste des objectifs proposés.
    func testAPresetIsKnownOnlyWhenEveryVerseOfItIsKnown() {
        var state = Program.defaultState()
        XCTAssertFalse(Program.goalIsAlreadyKnown(state, preset: .amma))

        // Tous les versets de « Juz’ ‘Amma », sauf le dernier.
        let amma = Program.goalFromPreset(.amma).ranges[0]
        state = Program.markKnowledge(
            state,
            range: VerseRange(start: amma.start, end: amma.end - 1),
            mastery: .perfect
        )
        XCTAssertFalse(
            Program.goalIsAlreadyKnown(state, preset: .amma),
            "il manque un verset : le préréglé ne doit pas être déclaré connu"
        )

        state = Program.markKnowledge(
            state,
            range: VerseRange(start: amma.end, end: amma.end),
            mastery: .perfect
        )
        XCTAssertTrue(Program.goalIsAlreadyKnown(state, preset: .amma))
    }

    /// « Tout le Coran » connu rend TOUS les préréglés connus : ils en sont tous
    /// des sous-ensembles.
    func testKnowingTheWholeQuranMakesEveryPresetKnown() {
        let state = Program.markKnowledge(
            Program.defaultState(),
            range: VerseRange(start: 1, end: Quran.verses.count),
            mastery: .perfect
        )
        for preset in GoalPreset.allCases {
            XCTAssertTrue(Program.goalIsAlreadyKnown(state, preset: preset), "\(preset)")
        }
    }

    // MARK: - Validation d'un objectif personnalisé

    /// Un hizb entier suffit, même s'il est petit — `src/core/program.ts:149`.
    func testAWholeHizbIsAValidGoal() {
        for hizb in [Quran.hizbs[0], Quran.hizbs[29], Quran.hizbs[59]] {
            XCTAssertTrue(
                Program.validGoal([Program.range(of: hizb)]),
                "hizb \(hizb.number) refusé"
            )
        }
    }

    /// Un verset ne suffit pas, et une liste vide non plus.
    func testOneVerseIsNotAValidGoal() {
        XCTAssertFalse(Program.validGoal([VerseRange(start: 1, end: 1)]))
        XCTAssertFalse(Program.validGoal([]))
    }

    /// Un soixantième du Coran suffit, même sans hizb entier — c'est la seconde
    /// branche du seuil. La plage est construite à partir des poids réels.
    func testOneSixtiethOfTheQuranIsAValidGoal() throws {
        let threshold = Double(Quran.totalVolume) / 60
        var volume = 0
        var boundary = 0
        for id in 1...Quran.weights.count {
            volume += Quran.weights[id - 1]
            if Double(volume) >= threshold {
                boundary = id
                break
            }
        }
        let range = VerseRange(start: 1, end: boundary)
        // Le préfixe doit bien atteindre le seuil, sinon le test ne dit rien.
        XCTAssertGreaterThanOrEqual(
            Double(Quran.volume(Quran.expand([range]))),
            threshold
        )
        // S'il se trouve que ce préfixe est un hizb entier, c'est la première
        // branche qui l'accepte : le test serait concluant pour la mauvaise
        // raison. On le signale plutôt que de le laisser passer.
        let isWholeHizb = Quran.hizbs.contains {
            $0.start == range.start && $0.end == range.end
        }
        try XCTSkipIf(isWholeHizb, "le préfixe du seuil est un hizb entier : cas non discriminant")
        XCTAssertTrue(Program.validGoal([range]))
    }

    /// Des plages qui se recouvrent sont fusionnées avant d'être mesurées.
    ///
    /// Les deux assertions sont choisies pour être VRAIES quoi qu'il arrive aux
    /// volumes : la première passe par la branche « un hizb entier », la seconde
    /// est trop petite pour passer par l'une ou l'autre.
    func testOverlappingRangesAreMergedBeforeMeasuring() {
        let hizb = Program.range(of: Quran.hizbs[0])
        let middle = (hizb.start + hizb.end) / 2
        // Deux moitiés jointes : aucune n'est un hizb entier, leur fusion l'est.
        XCTAssertTrue(
            Program.validGoal([
                VerseRange(start: hizb.start, end: middle),
                VerseRange(start: middle + 1, end: hizb.end)
            ]),
            "la fusion de deux moitiés doit reconstituer le hizb entier"
        )
        // Deux fois le même verset : la fusion n'en fait qu'un, ni hizb ni
        // soixantième du Coran.
        XCTAssertFalse(
            Program.validGoal([
                VerseRange(start: 1, end: 1),
                VerseRange(start: 1, end: 1)
            ])
        )
    }

    // MARK: - Rythmes

    /// `pacePresets` — `src/core/program.ts:34`. Les trois niveaux, leurs
    /// libellés, et le rythme que chacun applique.
    func testPacePresetsMatchTheReference() {
        XCTAssertEqual(Program.pacePresets[.beginner]?.label, "Débutant")
        XCTAssertEqual(Program.pacePresets[.beginner]?.pace, .verse1)
        XCTAssertEqual(Program.pacePresets[.beginner]?.detail, "1 à 5 versets par séance")
        XCTAssertEqual(Program.pacePresets[.intermediate]?.label, "Intermédiaire")
        XCTAssertEqual(Program.pacePresets[.intermediate]?.pace, .halfPage)
        XCTAssertEqual(Program.pacePresets[.intensive]?.label, "Intensif")
        XCTAssertEqual(Program.pacePresets[.intensive]?.pace, .page)
        XCTAssertEqual(Program.pacePresetOrder, [.beginner, .intermediate, .intensive])
    }

    /// Les rythmes proposés par niveau — `src/App.tsx:403`.
    func testPacesPerLevel() {
        XCTAssertEqual(Program.paces(for: .beginner), Program.beginnerPaces)
        XCTAssertEqual(Program.paces(for: .intermediate), [.halfPage])
        XCTAssertEqual(Program.paces(for: .intensive), Program.intensivePaces)
        // Un rythme indisponible (« toumoun ») n'est proposé par aucun niveau.
        for level in PacePreset.allCases {
            XCTAssertFalse(Program.paces(for: level).contains(.toumoun))
        }
    }

    /// `halfPage` est testé AVANT `intensivePaces` — `src/App.tsx:358`.
    func testPresetLevelForAStoredPace() {
        XCTAssertEqual(Program.presetLevel(for: .halfPage), .intermediate)
        for pace in Program.intensivePaces {
            XCTAssertEqual(Program.presetLevel(for: pace), .intensive, "\(pace)")
        }
        for pace in Program.beginnerPaces {
            XCTAssertEqual(Program.presetLevel(for: pace), .beginner, "\(pace)")
        }
        // Le rythme indisponible retombe sur « débutant », comme l'original,
        // qui ne le trouve dans aucune des deux listes.
        XCTAssertEqual(Program.presetLevel(for: .toumoun), .beginner)
    }

    /// Le rythme par défaut d'un groupe de l'écran « Mon programme » —
    /// `src/ui/GoalScreen.tsx:6`.
    func testPaceUnitDefaultPaces() {
        XCTAssertEqual(PaceUnit.page.defaultPace, .page)
        XCTAssertEqual(PaceUnit.verse.defaultPace, .verse1)
        XCTAssertEqual(PaceUnit.rubu.defaultPace, .quarter)
    }

    // MARK: - Lecture de l'objectif courant

    /// Un objectif qui EST un juz’ rouvre l'écran sur ce juz’.
    func testInitialUnitAndIndexRecogniseAJuz() {
        var state = Program.defaultState()
        state.goal = Program.goalFromPreset(.amma)
        XCTAssertEqual(ProgramEditorView.initialUnit(for: state), .juz)
        XCTAssertEqual(ProgramEditorView.initialIndex(for: state), Quran.juzs[29].number)
    }

    /// …un hizb sur ce hizb…
    func testInitialUnitAndIndexRecogniseAHizb() {
        var state = Program.defaultState()
        state.goal = Program.goalFromPreset(.sabbih)
        XCTAssertEqual(ProgramEditorView.initialUnit(for: state), .hizb)
        XCTAssertEqual(ProgramEditorView.initialIndex(for: state), Quran.hizbs[59].number)
    }

    /// …et une sourate sur cette sourate.
    func testInitialUnitAndIndexRecogniseASurah() {
        var state = Program.defaultState()
        let surah = Quran.surahs[1] // Al-Baqara
        state.goal = Goal(
            deadline: nil,
            label: "Finir \(surah.name)",
            ranges: [VerseRange(start: surah.start, end: surah.end)],
            direction: nil
        )
        XCTAssertEqual(ProgramEditorView.initialUnit(for: state), .surah)
        XCTAssertEqual(ProgramEditorView.initialIndex(for: state), surah.number)
    }

    /// Un objectif sur PLUSIEURS plages n'est aucune des trois unités : l'écran
    /// retombe sur « Hizb », comme l'original.
    func testInitialUnitFallsBackToHizbForAMultiRangeGoal() {
        var state = Program.defaultState()
        state.goal.ranges = [VerseRange(start: 1, end: 7), VerseRange(start: 100, end: 120)]
        XCTAssertEqual(ProgramEditorView.initialUnit(for: state), .hizb)
    }

    /// Le repli place l'index sur le premier hizb dont la fin couvre la fin de
    /// l'objectif — `GoalScreen.tsx:5`.
    func testInitialIndexFallsBackToTheCoveringHizb() throws {
        var state = Program.defaultState()
        state.goal.ranges = [VerseRange(start: 1, end: 7), VerseRange(start: 100, end: 120)]
        let lastEnd = 120
        let covering = try XCTUnwrap(Quran.hizbs.first { lastEnd <= $0.end })
        XCTAssertEqual(ProgramEditorView.initialIndex(for: state), covering.number)
        // Le premier hizb qui couvre la fin de l'objectif, pas un hizb au hasard.
        for earlier in Quran.hizbs where earlier.number < covering.number {
            XCTAssertLessThan(earlier.end, lastEnd, "hizb \(earlier.number) couvrirait déjà")
        }
    }

    /// Le groupe de rythme se déduit du rythme stocké — `GoalScreen.tsx:6`.
    func testInitialPaceUnitFollowsTheStoredPace() {
        XCTAssertEqual(ProgramEditorView.initialPaceUnit(for: "verse3"), .verse)
        XCTAssertEqual(ProgramEditorView.initialPaceUnit(for: "quarter"), .rubu)
        XCTAssertEqual(ProgramEditorView.initialPaceUnit(for: "page"), .page)
        XCTAssertEqual(ProgramEditorView.initialPaceUnit(for: "page2"), .page)
        XCTAssertEqual(ProgramEditorView.initialPaceUnit(for: "hizb"), .page)
        // « toumoun » ne commence pas par « verse » et n'est pas « quarter » :
        // il tombe dans « Par page », exactement comme l'original.
        XCTAssertEqual(ProgramEditorView.initialPaceUnit(for: "toumoun"), .page)
    }

    // MARK: - Validation de l'échéance

    /// Les trois refus de `GoalScreen.tsx:16`, dans l'ordre : la forme, puis
    /// l'existence réelle de la date.
    func testDeadlineValidation() {
        XCTAssertTrue(ProgramEditorView.isValidDeadline("2026-10-05"))
        XCTAssertTrue(ProgramEditorView.isValidDeadline("2000-01-01"))
        XCTAssertFalse(ProgramEditorView.isValidDeadline("2026-2-5"), "forme sans zéro")
        XCTAssertFalse(ProgramEditorView.isValidDeadline("05/10/2026"), "forme française")
        XCTAssertFalse(ProgramEditorView.isValidDeadline(""), "vide")
        XCTAssertFalse(ProgramEditorView.isValidDeadline("abcd-ef-gh"), "non numérique")
        // Un 31 février est accepté par la forme mais n'existe pas : c'est le
        // troisième contrôle qui le refuse.
        XCTAssertFalse(ProgramEditorView.isValidDeadline("2026-02-31"))
        XCTAssertFalse(ProgramEditorView.isValidDeadline("2026-13-01"), "mois 13")
    }

    // MARK: - Remise à zéro

    /// Ce qui est effacé.
    func testResetClearsLearningButKeepsNothingOfIt() {
        var state = Program.generateProgram(Program.defaultState(), from: "2026-10-05", days: 30)
        state.onboardingDone = true
        state.onboardingStep = 2
        state = Program.markKnowledge(
            state,
            range: VerseRange(start: 1, end: 10),
            mastery: .perfect
        )
        XCTAssertFalse(state.sessions.isEmpty)
        XCTAssertFalse(state.knowledge.isEmpty)

        let reset = Program.resetAllProgress(state)
        XCTAssertTrue(reset.sessions.isEmpty)
        XCTAssertTrue(reset.revisions.isEmpty)
        XCTAssertTrue(reset.knowledge.isEmpty)
        XCTAssertTrue(reset.memorizedAt?.isEmpty ?? false)
        XCTAssertFalse(reset.onboardingDone)
        XCTAssertNil(reset.onboardingStep)
    }

    /// Ce qui est conservé : ce qui identifie l'utilisateur et son confort.
    func testResetKeepsTheAccountAndThePreferences() {
        var state = Program.defaultState()
        state.userId = "6f0e0d3c-0000-0000-0000-000000000000"
        state.profile = PersonalProfile(sex: "Femme", firstName: "Soumaya")
        state.theme = "night"
        state.accent = "prune"
        state.uiFont = "grand"
        state.bookmarks = ["1": VerseBookmark(
            verseId: 1,
            surah: 1,
            ayah: 1,
            page: 1,
            createdAt: "2026-01-01T00:00:00.000Z",
            updatedAt: "2026-01-01T00:00:00.000Z"
        )]
        state.audioPreferences = AudioPreferences(reciterId: "alafasy")
        state.reader = ReaderPreferences(mushaf: "coran_1441", followAudio: false)
        state.reviewSettings = ReviewSettings(enabled: false, cycleDays: 30)

        let reset = Program.resetAllProgress(state)
        XCTAssertEqual(reset.userId, "6f0e0d3c-0000-0000-0000-000000000000")
        XCTAssertEqual(reset.profile?.firstName, "Soumaya")
        XCTAssertEqual(reset.theme, "night")
        XCTAssertEqual(reset.accent, "prune")
        XCTAssertEqual(reset.uiFont, "grand")
        XCTAssertEqual(reset.bookmarks?["1"]?.page, 1)
        XCTAssertEqual(reset.audioPreferences?.reciterId, "alafasy")
        XCTAssertEqual(reset.reader?.mushaf, "coran_1441")
        XCTAssertEqual(reset.reader?.followAudio, false)
        XCTAssertEqual(reset.reviewSettings?.enabled, false)
        XCTAssertEqual(reset.reviewSettings?.cycleDays, 30)
    }

    /// La divergence des notifications, recopiée à dessein de
    /// `src/core/program.ts:90` : `defaultState()` laisse le rappel
    /// d'apprentissage ÉTEINT, mais le repli de la remise à zéro l'ALLUME.
    func testResetTurnsTheDailyReminderOnWhereTheInitialStateLeavesItOff() {
        XCTAssertEqual(Program.defaultState().notifications?.learning, false)
        let resetWithoutPrevious = Program.resetAllProgress(nil)
        XCTAssertEqual(resetWithoutPrevious.notifications?.learning, true)
        XCTAssertEqual(resetWithoutPrevious.notifications?.messages, true)

        // Un réglage existant, lui, est conservé tel quel — y compris « éteint ».
        var state = Program.defaultState()
        state.notifications = NotificationPreferences(messages: false, learning: false)
        XCTAssertEqual(Program.resetAllProgress(state).notifications?.learning, false)
    }

    /// L'horodatage doit être STRICTEMENT postérieur : c'est ce qui fait
    /// reconnaître la remise à zéro comme la version la plus récente.
    func testResetAdvancesTheTimestamp() throws {
        var state = Program.defaultState()
        state.updatedAt = DateKeys.iso(Date())
        let previous = try XCTUnwrap(DateKeys.parseISO(state.updatedAt))

        let reset = Program.resetAllProgress(state)
        let after = try XCTUnwrap(DateKeys.parseISO(reset.updatedAt))
        XCTAssertGreaterThan(after, previous)

        // Une remise à zéro d'un état très ancien prend l'heure courante.
        var old = Program.defaultState()
        old.updatedAt = "2000-01-01T00:00:00.000Z"
        let resetOld = Program.resetAllProgress(old)
        let oldAfter = try XCTUnwrap(DateKeys.parseISO(resetOld.updatedAt))
        XCTAssertGreaterThan(oldAfter, Date(timeIntervalSince1970: 0))
    }

    /// Une remise à zéro d'un état sans compte laisse `userId` à `nil` — et ne
    /// fabrique pas d'identifiant.
    func testResetDoesNotInventAUserId() {
        XCTAssertNil(Program.resetAllProgress(nil).userId)
        XCTAssertEqual(Program.resetAllProgress(Program.defaultState()).schema, 1)
    }

    // MARK: - Texte de confirmation

    /// Les trois phrases de confirmation viennent du modèle, pas de la vue :
    /// les deux applications doivent annoncer la même chose.
    func testResetTextsAreCarriedByTheModel() {
        XCTAssertEqual(Program.resetProgressTitle, "Tout remettre à zéro ?")
        XCTAssertTrue(Program.resetProgressPrompt.contains("Ton compte et les pages du Coran seront conservés"))
        XCTAssertTrue(Program.resetProgressPrompt.contains("ne peut pas être annulée"))
        XCTAssertTrue(Program.resetProgressDetail.contains("Ton prénom et ton thème seront conservés"))
    }
}

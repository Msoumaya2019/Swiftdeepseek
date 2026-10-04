// ProgramGoal.swift
// Port de la couche « objectif » de `src/core/program.ts` : les objectifs
// préréglés, leur validation, la remise à zéro, et les niveaux de rythme.
//
// POURQUOI CE FICHIER EXISTE
//   `Program.swift` portait déjà la génération du programme, la connaissance
//   verset par verset et la prolongation. Il manquait la couche qui permet à
//   l'utilisateur de CHOISIR son objectif et son rythme — c'est-à-dire tout ce
//   que `GoalScreen` et l'assistant d'accueil consomment :
//
//       goalFromPreset        program.ts:46
//       goalIsAlreadyKnown    program.ts:114
//       validGoal             program.ts:147
//       resetAllProgress      program.ts:90
//       pacePresets           program.ts:34
//       goalPresetLabels      program.ts:43
//
//   Sans elle, `Réglages ▸ Modifier mon programme` n'aurait rien à afficher.
//
// RÈGLE DE CE FICHIER : il ne décide rien, il traduit.
//   Chaque fonction reprend une fonction de l'original, avec les mêmes bornes
//   et les mêmes retours. Les deux seuls endroits où le portage ne peut pas
//   être une recopie littérale sont signalés en commentaire — `validGoal`
//   (division flottante) et `resetAllProgress` (une valeur par défaut
//   DIFFÉRENTE de celle de `defaultState`). Ce sont les deux pièges que le banc
//   `_banc/verifier-reglages.mjs` surveille.

import Foundation

// MARK: - Types de l'original

/// `LearningDirection` — `src/core/program.ts:12`.
///
/// Le sens de parcours de l'objectif. Stocké dans `goal.direction`, qui est une
/// `String?` côté Swift : la valeur est écrite telle quelle dans le document
/// synchronisé, donc les deux applications lisent la même chaîne.
public enum GoalDirection: String, Codable, CaseIterable, Sendable {
    case fromStart
    case fromNas

    /// Les deux libellés de `src/App.tsx:408`.
    public var label: String {
        switch self {
        case .fromStart: return "Depuis Al-Fatiha"
        case .fromNas: return "Depuis An-Nâs"
        }
    }

    public var detail: String {
        switch self {
        case .fromStart: return "Sourates 1 à 114"
        case .fromNas: return "Sourates 114 à 1 ; versets de chaque sourate dans l’ordre"
        }
    }
}

/// `GoalPreset` — `src/core/program.ts:14`.
public enum GoalPreset: String, Codable, CaseIterable, Sendable {
    case lastTen, sabbih, amma, toYasin, half, all

    public var label: String { Program.goalPresetLabels[self] ?? rawValue }

    /// La phrase affichée sous la liste des objectifs quand le sens est imposé
    /// (`src/App.tsx:406`) : « depuis An-Nâs, en remontant sourate après
    /// sourate ». Elle ne s'applique PAS à `all`, qui laisse choisir.
    public var walksBackwardsFromAnNas: Bool { self != .all }
}

/// `PacePreset` — `src/core/program.ts:8`.
public enum PacePreset: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, intensive

    public var label: String { Program.pacePresets[self]?.label ?? rawValue }
    public var detail: String { Program.pacePresets[self]?.detail ?? "" }

    /// Le rythme appliqué quand on choisit ce niveau
    /// (`pacePresets[key].pace`). Attention : ce n'est PAS le rythme courant,
    /// c'est celui du niveau — `beginner` vaut `verse1`, pas `verse3`.
    public var defaultPace: Pace { Program.pacePresets[self]?.pace ?? .verse3 }
}

/// Une ligne de `pacePresets` : le libellé du niveau, le rythme qu'il applique,
/// et sa description.
public struct PacePresetEntry: Sendable {
    public let label: String
    public let pace: Pace
    public let detail: String
}

// MARK: - Objectifs préréglés

public extension Program {

    /// `goalPresetLabels` — `src/core/program.ts:43`.
    ///
    /// Les libellés sont EXACTEMENT ceux de l'original : ils sont écrits dans
    /// `goal.label`, donc dans le document synchronisé, et l'assistant de
    /// l'application React Native reconnaît un objectif préréglé en comparant
    /// ce libellé (`Object.keys(goalPresetLabels).find(key => … ===
    /// state.goal.label)`, `src/App.tsx:359`). Une apostrophe typographique
    /// changée en apostrophe droite suffirait à lui faire perdre la trace du
    /// préréglé.
    static let goalPresetLabels: [GoalPreset: String] = [
        .lastTen: "Les 10 dernières sourates",
        .sabbih: "Hizb Sabbih",
        .amma: "Juz’ ‘Amma",
        .toYasin: "Jusqu’à la sourate Ya-Sîn",
        .half: "La moitié du Coran",
        .all: "Tout le Coran"
    ]

    /// L'ordre d'affichage de `src/App.tsx:405`.
    static let goalPresetOrder: [GoalPreset] = [
        .lastTen, .sabbih, .amma, .toYasin, .half, .all
    ]

    /// `goalFromPreset` — `src/core/program.ts:46`.
    ///
    /// Les index sont ceux de l'original, qui sont 0-basés des deux côtés :
    /// `surahs[104]` est donc la 105ᵉ sourate (Al-Fîl) et `surahs[113]` la 114ᵉ
    /// (An-Nâs) ; `juzs[29]` est le 30ᵉ juz’ ; `hizbs[59]` le 60ᵉ hizb.
    ///
    /// `deadline` reste `nil` : l'original ne le pose pas ici, et l'échéance est
    /// un repère facultatif posé à part (`GoalScreen`).
    static func goalFromPreset(
        _ preset: GoalPreset,
        direction: GoalDirection = .fromNas
    ) -> Goal {
        let ranges: [VerseRange]
        switch preset {
        case .lastTen:
            ranges = [VerseRange(start: Quran.surahs[104].start, end: Quran.surahs[113].end)]
        case .sabbih:
            ranges = [Self.range(of: Quran.hizbs[59])]
        case .amma:
            ranges = [Self.range(of: Quran.juzs[29])]
        case .toYasin:
            ranges = [VerseRange(start: Quran.surahs[35].start, end: Quran.surahs[113].end)]
        case .half:
            ranges = [VerseRange(start: Quran.juzs[15].start, end: Quran.juzs[29].end)]
        case .all:
            ranges = [VerseRange(start: 1, end: 6236)]
        }
        return Goal(
            deadline: nil,
            label: goalPresetLabels[preset] ?? preset.rawValue,
            ranges: ranges,
            direction: direction.rawValue
        )
    }

    /// `Division` vers `VerseRange` — même paire de bornes, sans décision.
    static func range(of division: Division) -> VerseRange {
        VerseRange(start: division.start, end: division.end)
    }

    /// `goalIsAlreadyKnown` — `src/core/program.ts:114`.
    ///
    /// Sert à retirer de la liste des objectifs ceux qui sont déjà atteints :
    /// proposer « Tout le Coran » à quelqu'un qui le connaît par cœur n'a pas de
    /// sens. `allSatisfy` sur une liste vide vaut `true` — mais aucun préréglé
    /// ne produit de liste vide, donc le cas ne se présente pas.
    static func goalIsAlreadyKnown(_ state: AppState, preset: GoalPreset) -> Bool {
        goalFromPreset(preset).ranges.allSatisfy { state.isRangeKnown($0) }
    }

    /// `validGoal` — `src/core/program.ts:147`.
    ///
    /// Un objectif personnalisé est acceptable s'il contient **un hizb entier**,
    /// ou à défaut s'il atteint un soixantième du Coran en volume.
    ///
    /// ATTENTION — DIVISION FLOTTANTE. L'original écrit
    /// `volume(ids) >= totalVolume/60`, où `/` est la division JavaScript, donc
    /// flottante. Écrire `Quran.volume(ids) >= Quran.totalVolume / 60` en Swift
    /// ferait une division ENTIÈRE : le seuil serait abaissé jusqu'à un volume
    /// entier en dessous, et un objectif refusé par l'application React Native
    /// serait accepté ici. Les deux `Double` ci-dessous reproduisent la
    /// comparaison de l'original.
    static func validGoal(_ ranges: [VerseRange]) -> Bool {
        let ids = Quran.expand(ranges)
        let selected = Set(ids)
        let holdsWholeHizb = Quran.hizbs.contains { hizb in
            (hizb.start...max(hizb.start, hizb.end)).allSatisfy { selected.contains($0) }
        }
        if holdsWholeHizb { return true }
        return Double(Quran.volume(ids)) >= Double(Quran.totalVolume) / 60
    }

    /// Les rythmes proposés pour un niveau (`src/App.tsx:403`).
    static func paces(for preset: PacePreset) -> [Pace] {
        switch preset {
        case .beginner: return beginnerPaces
        case .intermediate: return [.halfPage]
        case .intensive: return intensivePaces
        }
    }

    /// `pacePresets` — `src/core/program.ts:34`, dans l'ordre d'affichage de
    /// `src/App.tsx:403` (`Object.keys(pacePresets)`).
    static let pacePresetOrder: [PacePreset] = [.beginner, .intermediate, .intensive]

    static let pacePresets: [PacePreset: PacePresetEntry] = [
        .beginner: PacePresetEntry(
            label: "Débutant",
            pace: .verse1,
            detail: "1 à 5 versets par séance"
        ),
        .intermediate: PacePresetEntry(
            label: "Intermédiaire",
            pace: .halfPage,
            detail: "Une demi-page par séance"
        ),
        .intensive: PacePresetEntry(
            label: "Intensif",
            pace: .page,
            detail: "1 page, 2 pages ou 1 rub‘ par séance"
        )
    ]

    /// Le niveau qui correspond au rythme STOCKÉ — `src/App.tsx:358` :
    /// `state.pace === 'halfPage' ? 'intermediate' : intensivePaces.includes(
    /// state.pace) ? 'intensive' : 'beginner'`.
    ///
    /// Noter que `halfPage` est testé AVANT `intensivePaces`, bien que les deux
    /// listes soient disjointes : l'ordre n'a pas d'importance ici, mais il est
    /// recopié tel quel pour que la lecture reste comparable.
    static func presetLevel(for pace: Pace) -> PacePreset {
        if pace == .halfPage { return .intermediate }
        if intensivePaces.contains(pace) { return .intensive }
        return .beginner
    }

    /// `resetAllProgress` — `src/core/program.ts:90`.
    ///
    /// Efface l'apprentissage, les séances et les révisions, et CONSERVE ce qui
    /// identifie l'utilisateur et son confort de lecture : compte, marque-pages,
    /// réglages audio, profil, thème, police, accent, notifications, source du
    /// Coran, réglages de révision.
    ///
    /// ATTENTION — DEUX VALEURS PAR DÉFAUT DIFFÉRENTES. `defaultState()` écrit
    /// `notifications.learning = false`, mais le repli de `resetAllProgress`
    /// est `{messages: true, learning: true}`. Autrement dit, une remise à zéro
    /// ACTIVE le rappel quotidien d'apprentissage alors que l'état initial le
    /// laisse éteint. C'est une incohérence de l'original, et elle est recopiée
    /// ici à dessein : la corriger changerait le comportement après une remise à
    /// zéro, donc ferait diverger les deux applications.
    ///
    /// `updatedAt` doit rester STRICTEMENT supérieur à l'horodatage précédent :
    /// c'est ce qui permet à la synchronisation de reconnaître la remise à zéro
    /// comme la version la plus récente (`DateKeys.maxISO`, qui reproduit
    /// `new Date(Math.max(now, previousTime + 1)).toISOString()`).
    static func resetAllProgress(_ previous: AppState? = nil) -> AppState {
        var next = defaultState()
        next.userId = previous?.userId
        next.bookmarks = previous?.bookmarks
        next.audioPreferences = previous?.audioPreferences
        next.profile = previous?.profile
        next.theme = previous?.theme ?? "white"
        next.accent = previous?.accent
        next.uiFont = previous?.uiFont
        next.notifications = previous?.notifications
            ?? NotificationPreferences(messages: true, learning: true)
        next.reader = previous?.reader
            ?? ReaderPreferences(mushaf: "coranTest", followAudio: true)
        next.reviewSettings = previous?.reviewSettings
            ?? ReviewSettings(enabled: true, cycleDays: 7)
        next.updatedAt = DateKeys.maxISO([previous.flatMap { DateKeys.parseISO($0.updatedAt) }])
        return next
    }

    /// Ce que la remise à zéro déclenche, et ce qu'elle ne touche pas — les deux
    /// phrases de confirmation de `src/App.tsx:321`, reprises telles quelles
    /// pour que les deux applications annoncent la même chose.
    static let resetProgressTitle = "Tout remettre à zéro ?"

    static let resetProgressPrompt =
        "Tes connaissances, séances, révisions, statistiques et choix de "
        + "programme seront effacés. Ton compte et les pages du Coran seront "
        + "conservés. Cette action ne peut pas être annulée."

    static let resetProgressDetail =
        "Recommencer le questionnaire et effacer tout l’apprentissage et toutes "
        + "les révisions. Ton prénom et ton thème seront conservés."
}

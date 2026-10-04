// ProgramEditorView.swift
// « Modifier mon programme » — l'écran qui définit objectif, rythme et jours.
//
// Deux écrans dans ce fichier, parce que l'application actuelle en a deux :
//
//   `ProgramEditorView`    `GoalScreen` de `src/ui/GoalScreen.tsx`. C'est ce
//                          qu'ouvre le bouton « Modifier mon programme » des
//                          réglages (`src/App.tsx:326`). Objectif choisi par
//                          UNITÉ et INDEX (« Finir le Juz’ 12 »), rythme,
//                          échéance, aperçu du programme, enregistrement.
//
//   `AdvancedProgramView`  Les étapes 1 à 3 de l'assistant (`src/App.tsx:390`),
//                          atteintes par « Options avancées · passages et
//                          jours ». Objectifs PRÉRÉGLÉS ou objectif
//                          personnalisé par passages, rythme par niveau, et —
//                          ce que `GoalScreen` n'a pas — les JOURS
//                          d'apprentissage.
//
// RÈGLE DE CES ÉCRANS : ils ne calculent rien.
//   Les objectifs préréglés viennent de `Program.goalPresetLabels` et
//   `Program.goalFromPreset`, leur filtrage de `Program.goalIsAlreadyKnown`, la
//   validation d'un objectif personnalisé de `Program.validGoal`, les rythmes de
//   `Program.pacePresets` / `Program.paces(for:)`, les libellés de `Pace.label`,
//   les jours de `Program.weekdays`, les divisions de `Quran`, les références de
//   `Quran.reference`, et l'aperçu de `AppViewModel.previewProgram`. Aucun
//   libellé, aucune borne, aucune liste n'est écrit ici.
//
// CE QUI DIVERGE DE L'ORIGINAL, ET POURQUOI
//   `GoalScreen` porte aussi une carte « Je connais déjà » qui marque un
//   PRÉFIXE du Coran (« jusqu'à la sourate X, verset Y »). Cette carte n'est pas
//   reprise ici : « Modifier mes connaissances » couvre le même besoin en plus
//   large — plages quelconques, sourates, juz’, hizb — et deux écrans qui
//   écrivent `state.knowledge` seraient deux endroits à faire diverger. La
//   sauvegarde, elle, est inchangée : `generateProgram(seedInitialRevisions(
//   touch(draft)))`, exactement la même chaîne que l'original.

import SwiftUI

// MARK: - Unités de l'objectif

/// `type GoalUnit = 'Sourate' | 'Hizb' | 'Juz’'` — `src/ui/GoalScreen.tsx:3`.
/// La chaîne brute sert de libellé ET entre dans `goal.label`, donc elle est
/// écrite telle quelle, apostrophe typographique comprise.
enum GoalUnit: String, CaseIterable {
    case surah = "Sourate"
    case hizb = "Hizb"
    case juz = "Juz’"
}

/// `type PaceUnit = 'Par page' | 'Par verset' | 'Par rubu‘'` —
/// `src/ui/GoalScreen.tsx:3`.
enum PaceUnit: String, CaseIterable {
    case page = "Par page"
    case verse = "Par verset"
    case rubu = "Par rubu‘"

    /// Le rythme appliqué quand on choisit ce groupe — `GoalScreen.tsx:6` :
    /// `unit === 'Par page' ? 'page' : unit === 'Par verset' ? 'verse1' :
    /// 'quarter'`.
    ///
    /// C'est le rythme par DÉFAUT du groupe, pas le rythme courant : changer de
    /// groupe remplace donc le rythme, même si le rythme précédent appartenait
    /// au nouveau groupe.
    var defaultPace: Pace {
        switch self {
        case .page: return .page
        case .verse: return .verse1
        case .rubu: return .quarter
        }
    }
}

// MARK: - Écran principal

struct ProgramEditorView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var unit: GoalUnit
    @State private var index: Int
    @State private var goalEdited: Bool
    @State private var pace: Pace
    @State private var paceUnit: PaceUnit
    @State private var deadlineMode: Bool
    @State private var deadline: String
    @State private var error: String?
    @State private var showAdvanced = false

    /// L'état n'est lu qu'une fois, à l'ouverture : c'est un BROUILLON.
    /// `GoalScreen` fait de même avec ses `useState` — l'écran ne réécrit rien
    /// tant que « Enregistrer mon programme » n'a pas été touché.
    init(state: AppState) {
        _unit = State(initialValue: Self.initialUnit(for: state))
        _index = State(initialValue: Self.initialIndex(for: state))
        _goalEdited = State(initialValue: false)
        _pace = State(initialValue: Pace(rawValue: state.pace) ?? .verse3)
        _paceUnit = State(initialValue: Self.initialPaceUnit(for: state.pace))
        _deadlineMode = State(initialValue: state.goal.deadline != nil)
        _deadline = State(initialValue: state.goal.deadline ?? "")
    }

    var body: some View {
        NavigationStack {
            List {
                goalSection
                paceSection
                deadlineSection
                previewSection
                if let error {
                    Section { Text(error).foregroundStyle(palette.red) }
                }
            }
            .navigationTitle("Mon programme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdvanced) {
                AdvancedProgramView(state: model.state)
            }
        }
    }

    // MARK: Mon objectif

    /// `src/ui/GoalScreen.tsx:5` — l'unité, puis l'index dans cette unité.
    @ViewBuilder private var goalSection: some View {
        Section {
            SegmentedControl(
                options: GoalUnit.allCases.map(\.rawValue),
                selection: Binding(
                    get: { GoalUnit.allCases.firstIndex(of: unit) ?? 0 },
                    set: { newValue in
                        unit = GoalUnit.allCases[newValue]
                        index = 1
                        goalEdited = true
                    }
                )
            )
            Picker("Objectif", selection: $index) {
                ForEach(divisions.indices, id: \.self) { offset in
                    Text(optionLabel(for: offset)).tag(offset + 1)
                }
            }
            .onChange(of: index) { _ in goalEdited = true }
            if !goalEdited {
                Text("Objectif actuel : \(model.state.goal.label)")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(palette.muted)
            }
        } header: {
            Text("Mon objectif")
        } footer: {
            Text("L’objectif se compte depuis le début du Coran jusqu’à la fin de l’unité choisie.")
        }
    }

    /// « Finir Al-Baqara » pour une sourate, « Finir le Juz’ 12 » sinon —
    /// `src/ui/GoalScreen.tsx:5`. Le numéro vient de la division elle-même, pas
    /// de son rang : pour les sourates les deux coïncident, et l'original s'y
    /// fie, mais lire `number` reste juste même si l'ordre des tables changeait.
    private func optionLabel(for offset: Int) -> String {
        if unit == .surah { return "Finir \(Quran.surahs[offset].name)" }
        return "Finir le \(unit.rawValue) \(divisions[offset].number)"
    }

    // MARK: Mon rythme

    /// `src/ui/GoalScreen.tsx:6` — trois groupes de rythmes, et un pas à pas
    /// borné aux rythmes du groupe.
    @ViewBuilder private var paceSection: some View {
        Section {
            SegmentedControl(
                options: PaceUnit.allCases.map(\.rawValue),
                selection: Binding(
                    get: { PaceUnit.allCases.firstIndex(of: paceUnit) ?? 0 },
                    set: { newValue in
                        paceUnit = PaceUnit.allCases[newValue]
                        pace = paceUnit.defaultPace
                    }
                )
            )
            HStack(spacing: Theme.Spacing.md) {
                Button { changePace(-1) } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.green)
                .accessibilityLabel("Réduire le rythme")

                Text("\(pace.label) / jour")
                    .font(.system(size: Theme.Typography.header, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity)

                Button { changePace(1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.green)
                .accessibilityLabel("Augmenter le rythme")
            }
        } header: {
            Text("Mon rythme")
        } footer: {
            Text("Le rythme fixe la quantité apprise à chaque séance.")
        }
    }

    /// Les rythmes du groupe affiché (`paceOptions`, `GoalScreen.tsx:7`).
    private var paceOptions: [Pace] {
        switch paceUnit {
        case .page: return [.halfPage, .page, .page2]
        case .verse: return Program.beginnerPaces
        case .rubu: return [.quarter, .halfHizb, .hizb]
        }
    }

    /// `changePace` — `GoalScreen.tsx:8`. L'index courant vaut `-1` quand le
    /// rythme stocké n'appartient pas au groupe affiché : le pas ramène alors au
    /// premier rythme du groupe, exactement comme `indexOf` en JavaScript.
    private func changePace(_ delta: Int) {
        let current = paceOptions.firstIndex(of: pace) ?? -1
        let target = max(0, min(paceOptions.count - 1, current + delta))
        pace = paceOptions[target]
    }

    // MARK: Échéance

    /// `GoalScreen.tsx:6` — l'échéance est un repère, jamais une contrainte de
    /// calcul : les séances suivent le rythme et les jours.
    @ViewBuilder private var deadlineSection: some View {
        Section {
            SegmentedControl(
                options: ["Sans date", "Choisir une date"],
                selection: Binding(
                    get: { deadlineMode ? 1 : 0 },
                    set: { deadlineMode = $0 == 1 }
                )
            )
            if deadlineMode {
                TextField("AAAA-MM-JJ", text: $deadline)
                    .keyboardType(.numbersAndPunctuation)
            }
        } header: {
            Text("Échéance")
        } footer: {
            Text("La date est un repère ; les séances sont calculées selon ton rythme.")
        }
    }

    // MARK: Programme généré

    /// `GoalScreen.tsx:13` — l'aperçu, puis l'enregistrement.
    ///
    /// L'aperçu est demandé au modèle, qui appelle `generateProgram` sur un
    /// BROUILLON : rien n'est écrit tant qu'on n'a pas enregistré.
    @ViewBuilder private var previewSection: some View {
        Section {
            if let session = preview {
                Text(Quran.reference(VerseRange(start: session.start, end: session.end)))
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                    .foregroundStyle(palette.text)
            } else {
                Text("Objectif atteint")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
            Button("Enregistrer mon programme") { save() }
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                .foregroundStyle(palette.green)
            Button("Options avancées · passages et jours") { showAdvanced = true }
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.green)
        } header: {
            Text("Programme généré")
        } footer: {
            Text("Selon ton objectif, ton rythme et tes jours d’apprentissage.")
        }
    }

    private var preview: Session? {
        model.previewProgram(
            goal: draftGoal,
            pace: pace,
            learningDays: model.state.learningDays
        )
    }

    // MARK: Le brouillon

    /// `draft` — `GoalScreen.tsx:5`.
    ///
    /// `direction` et les autres champs de l'objectif sont **conservés** : le
    /// brouillon ne remplace que l'échéance, et le libellé et les plages quand
    /// l'utilisateur a effectivement touché à l'objectif.
    private var draftGoal: Goal {
        var goal = model.state.goal
        goal.deadline = deadlineMode ? deadline : nil
        if goalEdited {
            let selected = divisions[index - 1]
            goal.label = unit == .surah
                ? "Finir \(Quran.surahs[index - 1].name)"
                : "Finir le \(unit.rawValue) \(index)"
            goal.ranges = [VerseRange(start: 1, end: selected.end)]
        }
        return goal
    }

    /// `divisions` — `GoalScreen.tsx:7`.
    private var divisions: [Division] {
        switch unit {
        case .surah:
            return Quran.surahs.map {
                Division(number: $0.number, start: $0.start, end: $0.end)
            }
        case .hizb:
            return Quran.hizbs
        case .juz:
            return Quran.juzs
        }
    }

    /// La validation de l'échéance puis l'enregistrement — `GoalScreen.tsx:16`.
    ///
    /// L'original refuse une date qui n'a pas la forme `AAAA-MM-JJ`, qui n'est
    /// pas analysable, **ou** qui ne se relit pas à l'identique — ce dernier
    /// contrôle rejette les dates qui n'existent pas, comme le 31 février, que
    /// le calendrier normaliserait en silence.
    private func save() {
        if deadlineMode, !Self.isValidDeadline(deadline) {
            error = "Indique une date valide au format AAAA-MM-JJ."
            return
        }
        model.saveProgram(
            goal: draftGoal,
            pace: pace,
            learningDays: model.state.learningDays
        )
        dismiss()
    }

    /// `!/^\d{4}-\d{2}-\d{2}$/.test(deadline) || Number.isNaN(Date.parse(deadline))
    /// || new Date(deadline + 'T12:00:00').toISOString().slice(0, 10) !== deadline`
    /// — les trois refus de `GoalScreen.tsx:16`, dans le même ordre.
    ///
    /// `DateKeys.date(from:)` interprète la date à **midi local**, comme
    /// l'original (`DateKeys.swift:5`), donc l'aller-retour `key(date(from:))`
    /// rend la même chaîne pour toute date réelle.
    static func isValidDeadline(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = DateKeys.date(from: value) else { return false }
        return DateKeys.key(date) == value
    }

    // MARK: Valeurs initiales

    /// `initialGoal` puis `initialJuz / initialHizb / initialSurah` —
    /// `GoalScreen.tsx:5`. Un objectif n'est reconnu comme une unité que s'il
    /// porte sur UNE SEULE plage dont les bornes sont exactement les siennes.
    static func initialUnit(for state: AppState) -> GoalUnit {
        guard state.goal.ranges.count == 1 else { return .hizb }
        let single = state.goal.ranges[0]
        let matches: (Division) -> Bool = { $0.start == single.start && $0.end == single.end }
        if Quran.juzs.contains(where: matches) { return .juz }
        if Quran.hizbs.contains(where: matches) { return .hizb }
        if Quran.surahs.contains(where: matches) { return .surah }
        return .hizb
    }

    /// `initialJuz?.number ?? initialHizb?.number ?? initialSurah?.number ??
    /// Math.max(1, hizbs.find(d => (state.goal.ranges.at(-1)?.end ?? 6236)
    /// <= d.end)?.number ?? 60)` — `GoalScreen.tsx:5`.
    ///
    /// Le repli place l'index sur le premier hizb dont la fin couvre la fin de
    /// l'objectif courant : l'écran s'ouvre donc là où l'utilisateur en est,
    /// même quand son objectif n'est pas un hizb entier.
    static func initialIndex(for state: AppState) -> Int {
        let ranges = state.goal.ranges
        if ranges.count == 1 {
            let single = ranges[0]
            let matches: (Division) -> Bool = { $0.start == single.start && $0.end == single.end }
            if let juz = Quran.juzs.first(where: matches) { return juz.number }
            if let hizb = Quran.hizbs.first(where: matches) { return hizb.number }
            if let surah = Quran.surahs.first(where: matches) { return surah.number }
        }
        let lastEnd = ranges.last?.end ?? 6236
        guard let covering = Quran.hizbs.first(where: { lastEnd <= $0.end }) else { return 60 }
        return max(1, covering.number)
    }

    /// `state.pace.startsWith('verse') ? 'Par verset' : state.pace === 'quarter'
    /// ? 'Par rubu‘' : 'Par page'` — `GoalScreen.tsx:6`.
    static func initialPaceUnit(for raw: String) -> PaceUnit {
        if raw.hasPrefix("verse") { return .verse }
        if raw == Pace.quarter.rawValue { return .rubu }
        return .page
    }
}

// MARK: - Options avancées

/// Les étapes 1 à 3 de l'assistant — `src/App.tsx:390-411`.
///
/// C'est le seul endroit où l'on choisit les JOURS d'apprentissage, et le seul
/// où l'on compose un objectif PERSONNALISÉ par passages (juz’, hizb, sourates,
/// plage précise), validé par `Program.validGoal`.
struct AdvancedProgramView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var preset: GoalPreset?
    @State private var direction: GoalDirection
    @State private var selectedJuz: [Int] = []
    @State private var selectedHizb: [Int] = []
    @State private var selectedSurahs: [Int] = []
    @State private var customRanges: [VerseRange] = []
    @State private var customSurah = ""
    @State private var customStart = ""
    @State private var customEnd = ""
    @State private var paceLevel: PacePreset
    @State private var pace: Pace
    @State private var learningDays: [Int]
    @State private var error: String?

    init(state: AppState) {
        // `kind` — `src/App.tsx:359` : le préréglé dont le libellé est celui de
        // l'objectif courant, sinon « personnalisé ».
        let match = Program.goalPresetOrder.first { Program.goalPresetLabels[$0] == state.goal.label }
        _preset = State(initialValue: match)
        _direction = State(initialValue: GoalDirection(rawValue: state.goal.direction ?? "") ?? .fromNas)
        // `customRanges` — `src/App.tsx:363` : les plages courantes sont
        // reprises si l'objectif est déjà personnalisé.
        let label = state.goal.label
        let isCustom = label == "Objectif personnalisé"
            || label.hasPrefix("Juz’ ")
            || label.hasPrefix("Hizb ")
        _customRanges = State(initialValue: isCustom ? state.goal.ranges : [])
        _paceLevel = State(initialValue: Program.presetLevel(for: Pace(rawValue: state.pace) ?? .verse3))
        _pace = State(initialValue: Pace(rawValue: state.pace) ?? .verse3)
        _learningDays = State(initialValue: state.learningDays)
    }

    var body: some View {
        NavigationStack {
            List {
                presetSection
                if preset == nil { customSection }
                paceSection
                daysSection
                if let error {
                    Section { Text(error).foregroundStyle(palette.red) }
                }
                saveSection
            }
            .navigationTitle("Options avancées")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: Mon objectif

    /// `src/App.tsx:405` — les préréglés, moins ceux déjà atteints, plus
    /// « Créer un objectif personnalisé ».
    ///
    /// Le filtrage par `goalIsAlreadyKnown` est ce qui évite de proposer « Tout
    /// le Coran » à quelqu'un qui le connaît par cœur.
    @ViewBuilder private var presetSection: some View {
        Section {
            ForEach(Program.goalPresetOrder.filter { !Program.goalIsAlreadyKnown(model.state, preset: $0) }, id: \.self) { candidate in
                SelectableRow(
                    label: prompt(for: candidate),
                    selected: preset == candidate,
                    style: .single
                ) {
                    preset = candidate
                    if candidate == .all { direction = .fromNas }
                }
            }
            SelectableRow(label: "Créer un objectif personnalisé", selected: preset == nil, style: .single) {
                preset = nil
            }
            if let preset, preset.walksBackwardsFromAnNas {
                Text("Apprentissage depuis An-Nâs, en remontant sourate après sourate.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(palette.muted)
            }
            // `src/App.tsx:408` — « Par où commencer ? », deux choix, et
            // seulement pour « Tout le Coran » : les cinq autres préréglés
            // imposent le sens (`walksBackwardsFromAnNas`).
            if preset == .all {
                ForEach(GoalDirection.allCases, id: \.self) { candidate in
                    SelectableRow(
                        label: candidate.label,
                        subtitle: candidate.detail,
                        selected: direction == candidate,
                        style: .single
                    ) { direction = candidate }
                }
            }
        } header: {
            Text("Mon objectif")
        }
    }

    /// Les sept phrases de `src/App.tsx:405`, dans l'ordre.
    private func prompt(for preset: GoalPreset) -> String {
        switch preset {
        case .lastTen: return "Je souhaite apprendre les petites sourates (les 10 dernières)"
        case .sabbih: return "Je souhaite apprendre le Hizb Sabbih"
        case .amma: return "Je souhaite apprendre le Juz’ ‘Amma"
        case .toYasin: return "Je souhaite apprendre jusqu’à la sourate Ya-Sîn"
        case .half: return "Je souhaite mémoriser la moitié du Coran"
        case .all: return "Je souhaite mémoriser tout le Coran"
        }
    }

    /// `src/App.tsx:409` — juz’, hizb, sourates, et plage précise. Le tout est
    /// normalisé par `Quran.normalizeRanges` avant d'être soumis à
    /// `Program.validGoal`.
    @ViewBuilder private var customSection: some View {
        Section("Juz’") {
            ForEach(Quran.juzs, id: \.number) { division in
                SelectableRow(
                    label: "Juz’ \(division.number)",
                    selected: selectedJuz.contains(division.number),
                    style: .multiple
                ) { toggle(division.number, in: &selectedJuz) }
            }
        }
        Section("Hizb") {
            ForEach(Quran.hizbs, id: \.number) { division in
                SelectableRow(
                    label: "Hizb \(division.number)",
                    selected: selectedHizb.contains(division.number),
                    style: .multiple
                ) { toggle(division.number, in: &selectedHizb) }
            }
        }
        Section("Sourates") {
            ForEach(Quran.surahs, id: \.number) { surah in
                SelectableRow(
                    label: "\(surah.number). \(surah.name)",
                    selected: selectedSurahs.contains(surah.number),
                    style: .multiple
                ) { toggle(surah.number, in: &selectedSurahs) }
            }
        }
        Section {
            TextField("Numéro de sourate", text: $customSurah)
                .keyboardType(.numberPad)
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Verset début", text: $customStart)
                    .keyboardType(.numberPad)
                TextField("Verset fin", text: $customEnd)
                    .keyboardType(.numberPad)
            }
            Button("Ajouter le passage") { addCustomRange() }
            ForEach(customRanges, id: \.self) { range in
                Text(Quran.reference(range))
                    .font(.system(size: Theme.Typography.body))
            }
        } header: {
            Text("Passage précis")
        }
    }

    /// `addPartial(true)` — `src/App.tsx:369`.
    private func addCustomRange() {
        guard let surah = Int(customSurah),
              let start = Int(customStart),
              let end = Int(customEnd),
              let first = Quran.verseID(surah: surah, ayah: start),
              let last = Quran.verseID(surah: surah, ayah: end),
              first <= last else {
            error = "Indique une sourate et des versets valides."
            return
        }
        customRanges = Quran.normalizeRanges(customRanges + [VerseRange(start: first, end: last)])
        customSurah = ""
        customStart = ""
        customEnd = ""
        error = nil
    }

    // MARK: Mon rythme

    /// `src/App.tsx:403` — le niveau d'abord, puis la quantité.
    @ViewBuilder private var paceSection: some View {
        Section {
            ForEach(Program.pacePresetOrder, id: \.self) { level in
                SelectableRow(
                    label: level.label,
                    subtitle: level.detail,
                    selected: paceLevel == level,
                    style: .single
                ) {
                    paceLevel = level
                    pace = level.defaultPace
                }
            }
            ForEach(Program.paces(for: paceLevel), id: \.self) { candidate in
                SelectableRow(
                    label: candidate.label,
                    selected: pace == candidate,
                    style: .single
                ) { pace = candidate }
            }
        } header: {
            Text("Mon rythme")
        } footer: {
            Text("Les quantités proposées correspondent au niveau sélectionné.")
        }
    }

    // MARK: Mes jours

    /// `src/App.tsx:411` — l'ordre de l'original : lundi à samedi, puis
    /// dimanche (index 0, comme `Date.getDay()`).
    @ViewBuilder private var daysSection: some View {
        Section {
            ForEach(Array(1...6) + [0], id: \.self) { day in
                SelectableRow(
                    label: Program.weekdays[day],
                    selected: learningDays.contains(day),
                    style: .multiple
                ) { toggle(day, in: &learningDays) }
            }
        } header: {
            Text("Mes jours d’apprentissage")
        } footer: {
            Text("Les jours non sélectionnés restent libres pour les révisions.")
        }
    }

    // MARK: Enregistrer

    @ViewBuilder private var saveSection: some View {
        Section {
            Button("Enregistrer mon programme") { save() }
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                .foregroundStyle(palette.green)
        }
    }

    /// `next()` à l'étape 3 puis à l'étape 1 — `src/App.tsx:385-390`.
    ///
    /// L'objectif personnalisé est refusé tant que `Program.validGoal` le juge
    /// insuffisant, avec le message de l'original. Le préréglé, lui, n'est jamais
    /// refusé : il vient de `Program.goalFromPreset`.
    private func save() {
        if learningDays.isEmpty {
            error = "Sélectionne au moins un jour d’apprentissage."
            return
        }
        let goal: Goal
        if let preset {
            goal = Program.goalFromPreset(preset, direction: preset == .all ? direction : .fromNas)
        } else {
            // `src/App.tsx:386` — l'ordre de l'original est juz’, sourates,
            // hizb, puis les plages saisies. Comme `normalizeRanges` fusionne et
            // trie, l'ordre n'a pas d'effet sur le résultat ; il est conservé
            // pour que la lecture reste comparable.
            let chosenJuz = Quran.juzs.filter { selectedJuz.contains($0.number) }
            let chosenSurahs = Quran.surahs
                .filter { selectedSurahs.contains($0.number) }
                .map { VerseRange(start: $0.start, end: $0.end) }
            let chosenHizb = Quran.hizbs.filter { selectedHizb.contains($0.number) }
            let ranges = Quran.normalizeRanges(
                chosenJuz.map(Program.range(of:))
                    + chosenSurahs
                    + chosenHizb.map(Program.range(of:))
                    + customRanges
            )
            guard Program.validGoal(ranges) else {
                error = "Choisis au moins l’équivalent d’un hizb complet. "
                    + "Les passages déjà mémorisés comptent dans cet objectif."
                return
            }
            goal = Goal(
                deadline: nil,
                label: "Objectif personnalisé",
                ranges: ranges,
                direction: GoalDirection.fromStart.rawValue
            )
        }
        model.saveProgram(
            goal: goal,
            pace: pace,
            learningDays: learningDays,
            finishingOnboarding: true
        )
        dismiss()
    }

    /// `toggle` — `src/App.tsx:366`.
    private func toggle(_ value: Int, in list: inout [Int]) {
        if let index = list.firstIndex(of: value) {
            list.remove(at: index)
        } else {
            list.append(value)
        }
    }
}

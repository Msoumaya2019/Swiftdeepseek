// ProgressScreenView.swift
// Onglet Progrès.
//
// Correspondance : le composant `ProgressScreen` de `src/ui/MainScreens.tsx`.
//
// Le nom du type évite `ProgressView`, qui est déjà un type de SwiftUI utilisé
// ailleurs dans l'application.
//
// Ce que l'écran doit préserver :
//   - le pourcentage du Coran mémorisé, calculé en volume de texte arabe et non
//     en nombre de versets (un verset court ne pèse pas comme un verset long) ;
//   - les mêmes fenêtres temporelles que l'application actuelle : aujourd'hui,
//     semaine (à partir du lundi), mois ;
//   - la régularité, en jours consécutifs ;
//   - les révisions réellement effectuées.

import SwiftUI

public struct ProgressScreenView: View {

    @EnvironmentObject private var model: AppViewModel
    @State private var period = 1
    @State private var showGraph = false
    @State private var showGoal = false

    private let periods = ["Jour", "Semaine", "Mois"]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HeroHeader(title: "Ma progression", subtitle: "Suis ton évolution pas à pas.")
                    overviewCard
                    SegmentedControl(options: periods, selection: $period)
                    periodStats
                    memorizationStats
                    graphToggle
                    if showGraph { graphCard }
                    goalsSection
                    statsSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(model.palette.cream)
            .navigationTitle("Progrès")
            .sheet(isPresented: $showGoal) {
                GoalSummaryView()
                    .environmentObject(model)
            }
        }
    }

    // MARK: Vue d'ensemble

    private var overviewCard: some View {
        Card {
            HStack(spacing: Theme.Spacing.lg) {
                ProgressRing(value: model.progress.quran, size: 112) {
                    Text(percent(model.progress.quran))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(model.palette.text)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(knownCount)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(model.palette.text)
                        Text("/ 6236")
                            .font(.system(size: 17))
                            .foregroundStyle(model.palette.muted)
                    }
                    Text("versets mémorisés")
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                }
                Spacer()
            }
        }
    }

    // MARK: Statistiques de la période

    private var periodStats: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            StatCard(title: periodLabel, value: "\(periodValue)", symbol: "chart.bar")
            StatCard(title: "Régularité", value: streakText, symbol: "calendar.badge.checkmark")
        }
    }

    private var memorizationStats: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            StatCard(
                title: "Pages mémorisées",
                value: "\(WeeklyProgress.memorizedPageCount(model.state))",
                symbol: "book"
            )
            StatCard(
                title: "Révisions faites",
                value: "\(model.state.reviewHistory?.count ?? 0)",
                symbol: "arrow.triangle.2.circlepath"
            )
        }
    }

    // MARK: Graphique

    private var graphToggle: some View {
        Button {
            showGraph.toggle()
        } label: {
            Text(showGraph ? "Masquer le graphique" : "Voir le graphique de la période")
                .font(.system(size: Theme.Typography.secondary, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.bordered)
        .tint(model.palette.green)
    }

    private var graphCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(graphTitle)
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                    ForEach(graphBars) { bar in
                        VStack(spacing: Theme.Spacing.xs) {
                            Text("\(bar.value)")
                                .font(.system(size: 10))
                                .foregroundStyle(model.palette.muted)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(model.palette.green2)
                                .frame(height: bar.height)
                            Text(bar.label)
                                .font(.system(size: 10))
                                .foregroundStyle(model.palette.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110, alignment: .bottom)
            }
        }
    }

    /// Une barre du graphique. Une structure plutôt qu'un tuple : Swift
    /// n'autorise pas les keypaths vers les éléments d'un tuple, donc
    /// `ForEach` et `map` ne peuvent pas s'appuyer dessus.
    private struct Point {
        let label: String
        let value: Int
    }

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let value: Int
        let height: CGFloat
    }

    /// Les barres, déjà mises à l'échelle : la barre la plus haute fait 64 points.
    private var graphBars: [Bar] {
        let values = graphValues
        let maxValue = max(1, values.map(\.value).max() ?? 1)
        return values.map { entry in
            Bar(
                id: entry.label,
                label: entry.label,
                value: entry.value,
                height: max(3, CGFloat(entry.value) / CGFloat(maxValue) * 64)
            )
        }
    }

    private var graphTitle: String {
        switch period {
        case 0: return "Les 7 derniers jours"
        case 2: return "Ce mois"
        default: return "Cette semaine"
        }
    }

    // MARK: Objectifs

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Mes objectifs", action: "Voir tout", onPress: { showGoal = true })
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(model.state.goal.label)
                        .font(.system(size: Theme.Typography.card, weight: .semibold))
                    Text("Objectif en cours")
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                    ProgressTrack(value: model.progress.goal)
                    Text(percent(model.progress.goal))
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                }
            }
        }
    }

    // MARK: Statistiques détaillées

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Statistiques")
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                StatCard(
                    title: "Juz’ complétés",
                    value: "\(WeeklyProgress.memorizedJuzCount(model.state))",
                    symbol: "book"
                )
                StatCard(
                    title: "Jours actifs",
                    value: "\(activity.dates.count)",
                    symbol: "calendar"
                )
            }
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                StatCard(
                    title: "Pages lues",
                    value: "\(model.state.readPages?.count ?? (model.state.lastRead != nil ? 1 : 0))",
                    symbol: "doc"
                )
                StatCard(title: "Versets mémorisés", value: "\(knownCount)", symbol: "chart.bar")
            }
        }
    }

    // MARK: Calculs

    private var knownCount: Int { model.state.memorizedIDs.count }
    private var activity: WeeklyProgress.Activity { WeeklyProgress.activity(model.state) }

    private var periodValue: Int {
        switch period {
        case 0: return model.stats.today
        case 2: return model.stats.month
        default: return model.stats.week
        }
    }

    private var periodLabel: String {
        switch period {
        case 0: return "Versets appris aujourd'hui"
        case 2: return "Versets appris ce mois"
        default: return "Versets appris cette semaine"
        }
    }

    private var streakText: String {
        "\(activity.streak) jour\(activity.streak > 1 ? "s" : "") d'affilée"
    }

    /// Chaque barre compte les versets appris sur la fenêtre correspondante,
    /// exactement comme `ProgressScreen` : jour par jour, puis semaine par
    /// semaine pour le mois.
    private var graphValues: [Point] {
        let today = DateKeys.today()
        let events = learningEvents

        func count(from start: String, to end: String) -> Int {
            events.filter { $0.date >= start && $0.date <= end }
                .reduce(0) { $0 + ($1.end - $1.start + 1) }
        }

        switch period {
        case 0:
            let start = DateKeys.addDays(today, -6)
            return (0..<7).map { offset in
                let date = DateKeys.addDays(start, offset)
                return Point(label: shortWeekday(date), value: count(from: date, to: date))
            }
        case 2:
            let monthStart = DateKeys.monthStart(today)
            return (0..<5).map { index in
                let start = DateKeys.addDays(monthStart, index * 7)
                let end = DateKeys.addDays(start, 6)
                return Point(label: "S\(index + 1)", value: count(from: start, to: end))
            }
        default:
            let start = DateKeys.weekStart(today)
            return (0..<7).map { offset in
                let date = DateKeys.addDays(start, offset)
                return Point(label: shortWeekday(date), value: count(from: date, to: date))
            }
        }
    }

    /// Les versets réellement appris, avec leur date : séances terminées hors
    /// suivi détaillé, plus chaque validation d'un apprentissage suivi.
    private var learningEvents: [LearningEvent] {
        let tracked = Set((model.state.studyProgress ?? [:]).values
            .filter { $0.mode == .learning }
            .map(\.id))
        var events: [LearningEvent] = model.state.sessions
            .filter { $0.status == .done && !tracked.contains($0.id) }
            .map { session in
                LearningEvent(start: session.start, end: session.end, date: completionDate(session))
            }
        for record in (model.state.studyProgress ?? [:]).values where record.mode == .learning {
            for validation in record.validations {
                events.append(LearningEvent(start: validation.start, end: validation.end, date: validation.date))
            }
        }
        return events
    }

    private struct LearningEvent {
        let start: Int
        let end: Int
        let date: String
    }

    /// `completedDate` si présent, sinon les dix premiers caractères de
    /// `completedAt`, sinon la date prévue — comme `src/ui/MainScreens.tsx:48`.
    private func completionDate(_ session: Session) -> String {
        if let completedDate = session.completedDate, !completedDate.isEmpty { return completedDate }
        if let completedAt = session.completedAt, completedAt.count >= 10 {
            return String(completedAt.prefix(10))
        }
        return session.date
    }

    private func percent(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded())) %" }

    private func shortWeekday(_ key: String) -> String {
        guard let date = DateKeys.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(3))
    }
}

// MARK: - Résumé de l'objectif

/// Vue volontairement en lecture seule pour cette première étape : modifier
/// l'objectif (l'assistant `GoalScreen` de l'application actuelle) touche à
/// `goal.ranges` et à la régénération du programme — cela viendra après, avec
/// ses propres tests de parité.
struct GoalSummaryView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Objectif en cours")
                                .font(.system(size: Theme.Typography.metadata))
                                .foregroundStyle(model.palette.muted)
                            Text(model.state.goal.label)
                                .font(.system(size: Theme.Typography.header, weight: .semibold))
                            Text("Rythme : \(Pace(rawValue: model.state.pace)?.label ?? model.state.pace) / jour")
                                .font(.system(size: Theme.Typography.secondary))
                                .foregroundStyle(model.palette.muted)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Passages visés")
                                .font(.system(size: Theme.Typography.card, weight: .semibold))
                            ForEach(model.state.goal.ranges, id: \.self) { range in
                                Text(Quran.reference(range))
                                    .font(.system(size: Theme.Typography.secondary))
                            }
                        }
                    }
                    Text("La modification de l'objectif arrivera dans une étape ultérieure : elle régénère le programme et doit donc être accompagnée de ses propres tests.")
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(model.palette.cream)
            .navigationTitle("Mon objectif")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

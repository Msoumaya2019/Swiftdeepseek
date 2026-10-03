// ReviewDashboardView.swift
// Tableau de bord des révisions.
//
// Correspondance : `src/ReviewDashboard.tsx`.
//
// Ce que l'écran doit préserver, parce que c'est là que vivent les règles de
// révision de l'application actuelle :
//   - les cycles de 7 / 14 / 21 / 30 jours (`reviewSettings.cycleDays`) ;
//   - les quantités quotidiennes 1 Nisf / 1 Hizb / 1 Juz / 2 Juz
//     (`reviewSettings.dailyQuantity`) ;
//   - les consolidations J+1, J+3, J+7 après l'apprentissage ;
//   - les versets « à retravailler », marqués lors d'une révision précédente.
//
// Une consolidation peut être faite en avance : les dates restent ancrées à la
// date d'apprentissage, jamais à la date d'exécution.

import SwiftUI

struct ReviewDashboardView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var readerRequest: ReaderRequest?
    @State private var showCyclePicker = false
    @State private var showAllConsolidations = false
    @State private var showAllPriorities = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Un programme fondé sur les versets réellement mémorisés.")
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)

                    resumeSection
                    todayCard
                    cycleCard
                    consolidationCard
                    reworkCard
                    trackingCard
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(model.palette.cream)
            .navigationTitle("Mes révisions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .fullScreenCover(item: $readerRequest) { request in
                ReaderView(request: request, edition: model.edition, startPage: model.resumePage)
                    .environmentObject(model)
            }
        }
    }

    private var plan: ReviewPlan { Review.reviewPlan(model.state) }

    // MARK: Reprises en cours

    @ViewBuilder
    private var resumeSection: some View {
        let partials = (model.state.studyProgress ?? [:]).values
            .filter { $0.mode == .revision && $0.status == .partial }
            .sorted { $0.updatedAt > $1.updatedAt }

        ForEach(partials, id: \.id) { record in
            Card {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Révision en cours")
                            .font(.system(size: Theme.Typography.card, weight: .semibold))
                        Text("Reprendre au verset \(record.through + 1)")
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                    }
                    Spacer()
                    Button("Reprendre") {
                        let task = ReviewTask(
                            id: record.id,
                            start: min(record.through + 1, record.end),
                            end: record.end,
                            category: record.category ?? .habitual,
                            label: "Versets"
                        )
                        open(task, consolidation: false)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.palette.green)
                }
            }
        }
    }

    // MARK: Révision du jour

    private var todayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heading("calendar.badge.checkmark", "Ma révision du jour")

                HStack(alignment: .top, spacing: 0) {
                    summaryColumn(
                        symbol: "book",
                        label: "Cycle du jour",
                        tasks: plan.habitual,
                        showDivider: true
                    )
                    summaryColumn(
                        symbol: "leaf",
                        label: "Consolidation",
                        tasks: plan.recent,
                        showDivider: true
                    )
                    summaryColumn(
                        symbol: "arrow.clockwise",
                        label: "À retravailler",
                        tasks: plan.priority,
                        showDivider: false
                    )
                }

                Button {
                    guard let first = plan.session.first else { return }
                    open(first, consolidation: first.category == .recent)
                } label: {
                    Text("Commencer ma révision")
                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.palette.green)
                .disabled(plan.session.isEmpty)

                Text(plan.session.isEmpty
                     ? "Ta révision du jour est terminée, ou aucune échéance n'est prévue aujourd'hui."
                     : "La séance du jour regroupe automatiquement ton cycle, tes consolidations et tes versets prioritaires.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
            }
        }
    }

    private func summaryColumn(symbol: String, label: String, tasks: [ReviewTask], showDivider: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(model.palette.green)
            Text(label)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
            Text(Review.reviewQuantity(tasks))
                .font(.system(size: 14, weight: .bold))
                .multilineTextAlignment(.center)
            Text(tasks.first.map { Quran.reference($0.range) + (tasks.count > 1 ? "…" : "") } ?? "Rien à revoir")
                .font(.system(size: 10))
                .foregroundStyle(model.palette.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 3)
        .overlay(alignment: .trailing) {
            if showDivider {
                Rectangle().fill(model.palette.line).frame(width: 1)
            }
        }
    }

    // MARK: Cycle

    private var cycleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    heading("chart.bar", "Mon cycle de révision")
                    Spacer()
                    Button("Modifier") { showCyclePicker.toggle() }
                        .font(.system(size: Theme.Typography.secondary, weight: .medium))
                        .foregroundStyle(model.palette.green)
                        .frame(minWidth: 64, minHeight: 44)
                }

                if showCyclePicker {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(Review.cycleOptions, id: \.self) { days in
                            Button("\(days) jours") {
                                model.update { Review.setReviewCycle($0, cycleDays: days) }
                                showCyclePicker = false
                            }
                            .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                model.state.reviewSettings?.cycleDays == days ? model.palette.green : model.palette.soft,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                            )
                            .foregroundStyle(model.state.reviewSettings?.cycleDays == days ? model.palette.paper : model.palette.text)
                        }
                    }

                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(Array(Review.quantityOptions.enumerated()), id: \.offset) { _, quantity in
                            Button(quantityLabel(quantity)) {
                                model.update { Review.setReviewQuantity($0, quantity: quantity) }
                                showCyclePicker = false
                            }
                            .font(.system(size: Theme.Typography.secondary, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                            .foregroundStyle(model.palette.text)
                        }
                    }
                }

                HStack {
                    Text(currentModeLabel)
                        .font(.system(size: Theme.Typography.secondary))
                    Spacer()
                    Text("Jour \(plan.cycleDay) / \(plan.cycle?.lengthDays ?? Review.reviewCycleDays(model.state))")
                        .font(.system(size: Theme.Typography.secondary))
                }

                ProgressTrack(value: completedRatio)
                Text("\(percent(completedRatio)) réellement révisés")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.green)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text("\(model.state.memorizedIDs.count) versets mémorisés · \(plan.completeJuz) Juz’ · \(plan.completeRub) Rubu’ · \(plan.completeNisf) Nisf")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)

                HStack(spacing: Theme.Spacing.sm) {
                    quantityBox(Review.reviewQuantity(plan.cycle?.corpus ?? []), "à revoir")
                    quantityBox(Review.reviewQuantity(plan.cycle?.completed ?? []), "révisés")
                    quantityBox(Review.reviewQuantity(remainingCorpus), "restants")
                }
            }
        }
    }

    private func quantityBox(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                .foregroundStyle(model.palette.text)
            Text(label)
                .font(.system(size: Theme.Typography.metadata))
                .foregroundStyle(model.palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completedRatio: Double {
        guard let cycle = plan.cycle, !cycle.corpus.isEmpty else { return 0 }
        let total = cycle.corpus.reduce(0.0) { $0 + Review.reviewWeight($1) }
        guard total > 0 else { return 0 }
        let done = cycle.completed.reduce(0.0) { $0 + Review.reviewWeight($1) }
        return done / total
    }

    /// Les versets du cycle qui restent à réviser.
    private var remainingCorpus: [Int] {
        let done = Set(plan.cycle?.completed ?? [])
        return (plan.cycle?.corpus ?? []).filter { !done.contains($0) }
    }

    private var currentModeLabel: String {
        if model.state.reviewSettings?.mode == "quantity" {
            return quantityLabel(model.state.reviewSettings?.dailyQuantity ?? "hizb")
        }
        return "Cycle de \(plan.cycle?.lengthDays ?? Review.reviewCycleDays(model.state)) jours"
    }

    private func quantityLabel(_ quantity: String) -> String {
        switch quantity {
        case "nisf": return "1 Nisf / jour"
        case "juz": return "1 Juz / jour"
        case "juz2": return "2 Juz / jour"
        default: return "1 Hizb / jour"
        }
    }

    // MARK: Consolidations

    private var consolidationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heading("leaf", "Nouveaux versets à consolider")
                Text("Les nouveaux versets appris sont revus à J+1, J+3 puis J+7, avant d'intégrer le prochain cycle.")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)

                if plan.consolidations.isEmpty {
                    EmptyLabel(text: "Aucun nouveau verset à consolider.")
                } else {
                    let rows = showAllConsolidations ? plan.consolidations : Array(plan.consolidations.prefix(5))
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        consolidationRow(row)
                    }
                    if plan.consolidations.count > 5 {
                        Button(showAllConsolidations ? "Réduire" : "Voir toutes les consolidations") {
                            showAllConsolidations.toggle()
                        }
                        .font(.system(size: Theme.Typography.secondary, weight: .semibold))
                        .foregroundStyle(model.palette.green)
                    }
                }
            }
        }
    }

    private func consolidationRow(_ row: ConsolidationRow) -> some View {
        let range = VerseRange(start: row.start, end: row.end)
        let today = DateKeys.today()
        return Button {
            open(
                ReviewTask(
                    id: "consolidation-\(row.start)-\(row.end)",
                    start: row.start,
                    end: row.end,
                    category: .recent,
                    label: "Consolidation"
                ),
                consolidation: true
            )
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(Quran.reference(range))
                    .font(.system(size: Theme.Typography.body, weight: .bold))
                    .foregroundStyle(model.palette.text)
                Text("\(Review.reviewQuantity([range])) · appris le \(shortDate(row.learnedAt))")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.steps.enumerated()), id: \.offset) { _, step in
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: stepSymbol(step, today: today))
                                .font(.system(size: 16))
                                .foregroundStyle(step.completed != nil || step.due <= today
                                                 ? model.palette.green : model.palette.muted)
                            Text("J+\(step.offset)")
                                .font(.system(size: 12, weight: .bold))
                            Text(stepLabel(step, today: today))
                                .font(.system(size: 10))
                                .foregroundStyle(model.palette.muted)
                                .multilineTextAlignment(.center)
                            Text(shortDate(step.completed ?? step.due))
                                .font(.system(size: 10))
                                .foregroundStyle(model.palette.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.sm)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(step.completed != nil ? model.palette.green : model.palette.line)
                                .frame(height: 2)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(model.palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .stroke(model.palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func stepSymbol(_ step: ConsolidationStep, today: String) -> String {
        if step.completed != nil { return "checkmark.circle" }
        if step.due <= today { return "clock" }
        return "circle"
    }

    private func stepLabel(_ step: ConsolidationStep, today: String) -> String {
        if step.completed != nil { return "Consolidé" }
        if step.due == today { return "Aujourd'hui" }
        if step.due < today { return "À rattraper" }
        return "À venir"
    }

    // MARK: À retravailler

    private var reworkCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heading("arrow.clockwise", "À retravailler")
                Text("\(Review.reviewQuantity(plan.priority)) à retravailler aujourd'hui")
                    .font(.system(size: Theme.Typography.secondary, weight: .bold))
                    .foregroundStyle(model.palette.green)

                if plan.rework.isEmpty {
                    EmptyLabel(text: "Aucun verset prioritaire prévu aujourd'hui.")
                } else {
                    let tasks = showAllPriorities ? plan.rework : Array(plan.rework.prefix(5))
                    ForEach(tasks, id: \.id) { task in
                        Button {
                            open(task, consolidation: false)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Quran.reference(task.range)) ›")
                                    .font(.system(size: Theme.Typography.body, weight: .bold))
                                    .foregroundStyle(model.palette.text)
                                Text("\(Review.reviewQuantity([task])) · marqué lors d'une révision précédente")
                                    .font(.system(size: Theme.Typography.metadata))
                                    .foregroundStyle(model.palette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Theme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if plan.rework.count > 5 {
                        Button(showAllPriorities ? "Réduire" : "Voir tous les versets prioritaires") {
                            showAllPriorities.toggle()
                        }
                        .font(.system(size: Theme.Typography.secondary, weight: .semibold))
                        .foregroundStyle(model.palette.green)
                    }
                }
            }
        }
    }

    // MARK: Suivi

    private var trackingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                heading("clock.arrow.circlepath", "Mon suivi")
                Text("\(model.state.memorizedIDs.count) versets mémorisés · \(plan.completeJuz) Juz’ · \(plan.completeRub) Rubu’ · \(plan.completeNisf) Nisf")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
                Text("\(model.state.reviewHistory?.count ?? 0) révisions effectuées")
                    .font(.system(size: Theme.Typography.body))
            }
        }
    }

    // MARK: Outils

    private func heading(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(model.palette.green)
            Text(title)
                .font(.system(size: Theme.Typography.card, weight: .bold))
                .foregroundStyle(model.palette.text)
        }
    }

    private func open(_ task: ReviewTask, consolidation: Bool) {
        readerRequest = ReaderRequest(
            range: task.range,
            sessionID: nil,
            page: Quran.pageOf(task.start) ?? 1,
            reviewTask: task,
            consolidation: consolidation
        )
    }

    private func percent(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded())) %" }

    private func shortDate(_ key: String) -> String {
        guard let date = DateKeys.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

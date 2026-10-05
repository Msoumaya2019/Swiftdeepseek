// ProgramView.swift
// Onglet Programme.
//
// Correspondance : le composant `ProgramScreen` de `src/ui/MainScreens.tsx`.
//
// Ce que l'écran doit préserver, parce que l'utilisateur le retrouve dans
// l'application React Native :
//   - la séance d'apprentissage du jour et la séance de révision du jour ;
//   - l'objectif en cours et son avancement ;
//   - les séances en retard (« À rattraper ») — on ne supprime jamais rien ;
//   - « À venir » sur trois périodes, plafonné aux dix prochains jours ;
//   - l'historique des séances terminées ou reportées.
//
// Règle de compatibilité : `scheduledDate` est la date prévue, `completedAt`
// celle de l'exécution. Terminer une séance en avance ne doit pas déplacer sa
// date prévue — c'est `Program.completeSession` qui s'en charge.

import SwiftUI

public struct ProgramView: View {

    @EnvironmentObject private var model: AppViewModel
    @State private var readerRequest: ReaderRequest?
    @State private var period = 0
    @State private var showHistory = false
    @State private var showReviewDashboard = false

    private let periods = ["Jour", "Semaine", "Mois"]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HeroHeader(
                        title: "Mon programme",
                        subtitle: "Ton parcours du jour, calculé selon ton objectif"
                    )
                    todayCard
                    goalCard
                    resumeCards
                    weeklyCard
                    catchUpCard
                    upcomingSection
                    historySection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(model.palette.cream)
            .navigationTitle("Programme")
            .fullScreenCover(item: $readerRequest) { request in
                ReaderView(request: request, edition: model.edition, startPage: model.resumePage)
                    .environmentObject(model)
            }
            .sheet(isPresented: $showReviewDashboard) {
                ReviewDashboardView()
                    .environmentObject(model)
            }
        }
    }

    // MARK: Données du jour

    private var plan: ReviewPlan { Review.reviewPlan(model.state) }

    private var learningSession: Session? {
        let today = DateKeys.today()
        return model.state.sessions.first { $0.status == .todo && WeeklyProgress.scheduledDate($0) == today }
            ?? model.upcoming.first
    }

    private var reviewTask: ReviewTask? { plan.session.first }

    private var overdueSessions: [Session] {
        let today = DateKeys.today()
        return model.state.sessions.filter { $0.status == .todo && WeeklyProgress.scheduledDate($0) < today }
    }

    private var paceLabel: String {
        Pace.displayed(model.state.pace)
    }

    // MARK: Aujourd'hui

    private var todayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundStyle(model.palette.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aujourd'hui")
                            .font(.system(size: Theme.Typography.card, weight: .semibold))
                        Text(longDate(DateKeys.today()))
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                    }
                }

                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    DailyTaskCard(
                        title: "Apprentissage",
                        passage: learningSession.map { Quran.reference(VerseRange(start: $0.start, end: $0.end)) }
                            ?? "Programme terminé",
                        details: learningSession.map { "\(verseCount($0)) • Page \(page(of: $0.start))" }
                            ?? "Aucune séance"
                    ) {
                        openLearning()
                    }

                    if Review.reviewsEnabled(model.state) {
                        DailyTaskCard(
                            title: "Révision",
                            passage: reviewTask.map { Quran.reference($0.range) } ?? "Révisions à jour",
                            details: reviewTask.map { "\(Review.reviewQuantity([$0])) • Page \(page(of: $0.start))" }
                                ?? "Aucun passage dû",
                            isRevision: true
                        ) {
                            openReview()
                        }
                    }
                }

                if let learningSession, WeeklyProgress.scheduledDate(learningSession) != DateKeys.today() {
                    Text("Prochaine séance prévue : \(longDate(WeeklyProgress.scheduledDate(learningSession)))")
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                }

                Button {
                    openLearning()
                } label: {
                    Text("Ouvrir la lecture du jour ›")
                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.palette.green)
            }
        }
    }

    // MARK: Objectif

    private var goalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "target")
                        .foregroundStyle(model.palette.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mon objectif")
                            .font(.system(size: Theme.Typography.card, weight: .semibold))
                        Text(model.state.goal.label)
                            .font(.system(size: Theme.Typography.body))
                        Text("Rythme : \(paceLabel) / jour")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                    }
                    Spacer()
                }
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressTrack(value: model.progress.goal)
                    Text(percent(model.progress.goal))
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                }
            }
        }
    }

    // MARK: Reprises en cours

    @ViewBuilder
    private var resumeCards: some View {
        let pending = (model.state.studyProgress ?? [:]).values
            .filter { $0.mode == .learning && $0.status == .partial }
            .filter { record in
                model.state.sessions.contains { $0.id == record.id && $0.status == .todo }
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        ForEach(pending, id: \.id) { record in
            Card {
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apprentissage en cours")
                            .font(.system(size: Theme.Typography.card, weight: .semibold))
                        Text("Reprendre au verset \(record.through + 1)")
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                    }
                    Spacer()
                    Button("Reprendre") {
                        readerRequest = ReaderRequest(
                            range: VerseRange(start: min(record.through + 1, record.end), end: record.end),
                            sessionID: record.id,
                            page: record.page
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(model.palette.green)
                }
            }
        }
    }

    // MARK: Semaine

    private var weeklyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Objectif de la semaine · \(percent(model.weekly.ratio))")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
                ProgressTrack(value: model.weekly.ratio)
                Text("Nouvelle période chaque lundi à 00:01. L'historique précédent est conservé.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
            }
        }
    }

    // MARK: À rattraper

    @ViewBuilder
    private var catchUpCard: some View {
        if !overdueSessions.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("À rattraper")
                        .font(.system(size: Theme.Typography.card, weight: .semibold))
                    ForEach(overdueSessions.prefix(10), id: \.id) { session in
                        Button {
                            readerRequest = ReaderRequest(
                                range: VerseRange(start: session.start, end: session.end),
                                sessionID: session.id,
                                page: page(of: session.start)
                            )
                        } label: {
                            HStack {
                                Text(WeeklyProgress.scheduledDate(session))
                                    .font(.system(size: Theme.Typography.metadata))
                                    .foregroundStyle(model.palette.muted)
                                Text(Quran.reference(VerseRange(start: session.start, end: session.end)))
                                    .font(.system(size: Theme.Typography.secondary, weight: .medium))
                                    .foregroundStyle(model.palette.text)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(model.palette.muted)
                            }
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: À venir

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("À venir")
                    .font(.system(size: Theme.Typography.section, weight: .semibold))
                Spacer()
                SegmentedControl(options: periods, selection: $period)
                    .frame(width: 210)
            }
            Card {
                if filteredUpcoming.isEmpty {
                    EmptyLabel(text: "Aucune séance sur les 10 prochains jours.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(filteredUpcoming, id: \.id) { session in
                            upcomingRow(session)
                            if session.id != filteredUpcoming.last?.id {
                                Divider().overlay(model.palette.line)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Le programme à venir reste plafonné aux dix prochains jours : au-delà, la
    /// liste n'est pas affichée — mais les données restent en base.
    private var filteredUpcoming: [Session] {
        let all = model.upcoming
        guard let first = all.first else { return [] }
        let today = DateKeys.today()
        switch period {
        case 0:
            return all.filter { WeeklyProgress.scheduledDate($0) == WeeklyProgress.scheduledDate(first) }
        case 1:
            return all.filter { WeeklyProgress.scheduledDate($0) <= DateKeys.addDays(today, 7) }
        default:
            return all
        }
    }

    private func upcomingRow(_ session: Session) -> some View {
        let date = WeeklyProgress.scheduledDate(session)
        let surah = Quran.surahAt(session.start)
        return Button {
            readerRequest = ReaderRequest(
                range: VerseRange(start: session.start, end: session.end),
                sessionID: session.id,
                page: page(of: session.start)
            )
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(spacing: 1) {
                    Text(shortWeekday(date).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(model.palette.green)
                    Text(dayNumber(date))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(model.palette.text)
                }
                .frame(width: 44, height: 52)
                .background(model.palette.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

                VStack(alignment: .leading, spacing: 3) {
                    Text(Quran.reference(VerseRange(start: session.start, end: session.end)))
                        .font(.system(size: Theme.Typography.card, weight: .semibold))
                        .foregroundStyle(model.palette.text)
                        .lineLimit(1)
                    Text("\(verseCount(session)) • Page \(page(of: session.start))")
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                    Text(relativeDay(date))
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                }
                Spacer()
                if let arabic = surah.arabic {
                    ArabicLabel(text: arabic, size: 19)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(model.palette.muted)
            }
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Historique

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(
                title: "Historique",
                action: showHistory ? "Masquer" : "Voir tout",
                onPress: { showHistory.toggle() }
            )
            if showHistory {
                let finished = model.state.sessions
                    .filter { $0.status != .todo }
                    .suffix(20)
                    .reversed()
                ForEach(Array(finished), id: \.id) { session in
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(WeeklyProgress.scheduledDate(session)) · \(session.status == .done ? "Terminé" : "Reporté")")
                                .font(.system(size: Theme.Typography.metadata))
                                .foregroundStyle(model.palette.muted)
                            Text(Quran.reference(VerseRange(start: session.start, end: session.end)))
                                .font(.system(size: Theme.Typography.card, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func openLearning() {
        guard let session = learningSession else {
            model.notice = "Ton programme est à jour."
            return
        }
        readerRequest = ReaderRequest(
            range: VerseRange(start: session.start, end: session.end),
            sessionID: session.id,
            page: page(of: session.start)
        )
    }

    private func openReview() {
        guard let task = reviewTask else {
            showReviewDashboard = true
            return
        }
        readerRequest = ReaderRequest(
            range: task.range,
            sessionID: nil,
            page: page(of: task.start),
            reviewTask: task,
            consolidation: task.category == .recent
        )
    }

    // MARK: Formatage

    private func page(of verseID: Int) -> Int { Quran.pageOf(verseID) ?? 1 }

    private func verseCount(_ session: Session) -> String {
        let count = session.end - session.start + 1
        return "\(count) verset\(count == 1 ? "" : "s")"
    }

    private func percent(_ ratio: Double) -> String { "\(Int((ratio * 100).rounded())) %" }

    private func date(_ key: String) -> Date? { DateKeys.date(from: key) }

    private func longDate(_ key: String) -> String {
        guard let date = date(key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: date)
    }

    private func shortWeekday(_ key: String) -> String {
        guard let date = date(key) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dayNumber(_ key: String) -> String {
        guard let date = date(key) else { return "" }
        return String(Calendar.current.component(.day, from: date))
    }

    private func relativeDay(_ key: String) -> String {
        if key == DateKeys.today() { return "Aujourd'hui" }
        if key == DateKeys.addDays(DateKeys.today(), 1) { return "Demain" }
        guard let date = date(key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
}

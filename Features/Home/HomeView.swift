// HomeView.swift
// Onglet Accueil.
//
// Correspondance : le composant `Home` de `src/ui/MainScreens.tsx`.
// On y retrouve, comme dans l'application actuelle :
//   - l'avancement vers l'objectif, en pourcentage ;
//   - les séances du jour, avec reprise possible ;
//   - la reprise de lecture à la dernière page lue ;
//   - l'accès aux révisions en attente ;
//   - l'accès à la question du jour et aux quiz entre amis.

import SwiftUI

public struct HomeView: View {

    @EnvironmentObject private var model: AppViewModel
    @State private var readerRequest: ReaderRequest?
    @State private var showProfile = false
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    progressCard
                    resumeCard
                    if !model.todaySessions.isEmpty { todayCard }
                    upcomingCard
                    quickActions
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(model.palette.cream)
            .navigationTitle("Apprendre le Coran")
            .toolbar {
                // Le bouton de profil vient en PREMIER, comme dans la barre de
                // titre de l'original (`onProfile` puis `onSettings`,
                // `App.tsx:236`). Il porte l'initiale du prénom, ou un bonhomme.
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileHeaderButton(firstName: model.state.profile?.firstName) {
                        showProfile = true
                    }
                    .accessibilityLabel("Ouvrir le profil")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(item: $readerRequest) { request in
                ReaderView(
                    request: request,
                    edition: model.edition,
                    startPage: model.resumePage
                )
                .environmentObject(model)
            }
        }
    }

    // MARK: Sections

    /// Le bandeau d'accueil — `src/ui/MainScreens.tsx:23`.
    ///
    /// L'illustration du thème courant est posée **derrière** le texte, à 55 %
    /// d'opacité : c'est ce qui la rend lisible sans effacer le texte, et ce
    /// n'est pas un détail — à pleine opacité, le prénom devient illisible sur
    /// le thème « Bleu Nuit & Or ». Le bandeau **déborde** de la gouttière de
    /// l'écran (`marginHorizontal:-18` dans la référence), d'où le rembourrage
    /// négatif appliqué en dernier.
    ///
    /// L'ordre des deux `background` compte : l'illustration est au plus près du
    /// texte, et le fond crème derrière elle. Inversé, le crème masquerait
    /// l'image, et le bandeau paraîtrait simplement uni.
    ///
    /// DIVERGENCE ASSUMÉE : les **textes** ne sont pas ceux de la référence, qui
    /// affiche « As-Salâm ‘Alaykoum, », puis le **prénom** en grand, puis
    /// « Prêt à continuer ton apprentissage ? ». Ici la grande ligne porte
    /// l'**objectif**. Le bandeau illustré est porté tel quel ; aligner les
    /// textes est un travail à part, et le faire en silence changerait un écran
    /// que rien n'a demandé de changer.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let firstName = model.state.profile?.firstName, !firstName.isEmpty {
                Text("As-salāmu ‘alaykum, \(firstName)")
                    .font(.system(size: Theme.Typography.body))
                    .foregroundStyle(model.palette.muted)
            }
            Text(model.state.goal.label)
                .font(.system(size: Theme.Typography.screen, weight: .semibold))
                .foregroundStyle(model.palette.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.md)
        .frame(minHeight: Theme.Art.bannerMinHeight, alignment: .leading)
        .background(
            ThemeArtImage(theme: model.state.theme ?? "white")
                .opacity(Theme.Art.bannerOpacity)
        )
        .background(model.palette.cream)
        .padding(.horizontal, -Theme.Spacing.lg)
    }

    private var progressCard: some View {
        let progress = model.progress
        return Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("Mon objectif")
                        .font(.system(size: Theme.Typography.card, weight: .semibold))
                    Spacer()
                    Text(percent(progress.goal))
                        .font(.system(size: Theme.Typography.header, weight: .bold))
                        .foregroundStyle(model.palette.green)
                }
                ProgressView(value: progress.goal)
                    .tint(model.palette.green)
                Text("\(progress.goalKnown) / \(progress.goalTotal) lettres apprises")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
            }
        }
    }

    private var resumeCard: some View {
        Card {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Reprendre la lecture")
                        .font(.system(size: Theme.Typography.card, weight: .semibold))
                    if let lastRead = model.state.lastRead {
                        Text("Page \(lastRead.page)")
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                    } else {
                        Text(model.edition.label)
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                    }
                }
                Spacer()
                Button {
                    readerRequest = ReaderRequest(range: nil, sessionID: nil, page: model.resumePage)
                } label: {
                    Label("Ouvrir", systemImage: "book")
                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(model.palette.green)
            }
        }
    }

    private var todayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Aujourd'hui")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                ForEach(model.todaySessions, id: \.id) { session in
                    Button {
                        readerRequest = ReaderRequest(
                            range: VerseRange(start: session.start, end: session.end),
                            sessionID: session.id,
                            page: Quran.pageOf(session.start) ?? 1
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Quran.reference(VerseRange(start: session.start, end: session.end)))
                                    .font(.system(size: Theme.Typography.body, weight: .medium))
                                    .foregroundStyle(model.palette.text)
                                Text(session.unit)
                                    .font(.system(size: Theme.Typography.metadata))
                                    .foregroundStyle(model.palette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(model.palette.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Seulement les 10 prochains jours, sans jamais purger le reste.
    private var upcomingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Programme à venir")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                if model.upcoming.isEmpty {
                    Text("Aucune séance prévue dans les dix prochains jours.")
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                } else {
                    ForEach(model.upcoming.prefix(10), id: \.id) { session in
                        HStack {
                            Text(WeeklyProgress.scheduledDate(session))
                                .font(.system(size: Theme.Typography.secondary))
                                .foregroundStyle(model.palette.muted)
                                .frame(width: 92, alignment: .leading)
                            Text(Quran.reference(VerseRange(start: session.start, end: session.end)))
                                .font(.system(size: Theme.Typography.body))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: Theme.Spacing.md) {
            quickAction("Question du jour", "questionmark.circle") {
                model.notice = "La question du jour arrive avec l'étape Quiz."
            }
            quickAction("Révisions", "arrow.triangle.2.circlepath") {
                model.notice = "L'écran de révision arrive à l'étape suivante."
            }
        }
    }

    private func quickAction(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: Theme.Typography.secondary, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(model.palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(model.palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.palette.green)
    }

    private func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded())) %"
    }
}

// MARK: - Demande d'ouverture du lecteur

/// Décrit *pourquoi* le lecteur s'ouvre. Les quatre cas existent déjà dans
/// l'application React Native (`App.tsx` : `openReader({range, sessionId,
/// reviewTask, consolidation})`) et changent le comportement de la barre
/// d'actions du lecteur :
///   - `sessionID` : séance d'apprentissage à valider ;
///   - `reviewTask` : tâche de révision à noter ;
///   - `consolidation` : consolidation J+1/J+3/J+7 d'un verset nouvellement appris.
public struct ReaderRequest: Identifiable {
    public let id = UUID()
    public var range: VerseRange?
    public var sessionID: String?
    public var page: Int
    public var reviewTask: ReviewTask?
    public var consolidation: Bool

    public init(
        range: VerseRange?,
        sessionID: String?,
        page: Int,
        reviewTask: ReviewTask? = nil,
        consolidation: Bool = false
    ) {
        self.range = range
        self.sessionID = sessionID
        self.page = page
        self.reviewTask = reviewTask
        self.consolidation = consolidation
    }
}

/// Carte réutilisable — même rôle que `Card` de `src/ui/theme.tsx`.
///
/// `tint` existe pour un seul appelant, et il vient de l'original : la carte
/// d'EXPLICATION de « Mes marques-pages » passe `backgroundColor: colors.soft`
/// là où `Card` pose `paper` (`BookmarksScreen.tsx:11`). C'est le même procédé
/// que le titre plus discret de `QuranSourcesCard` : l'original distingue une
/// NOTE d'une ENTRÉE. Écrire cette variante en clair dans la vue aurait
/// dupliqué la recette de la carte — bordure, rayon, remplissage —, et les deux
/// copies auraient divergé au premier ajustement.
struct Card<Content: View>: View {
    @EnvironmentObject private var model: AppViewModel
    @ViewBuilder var content: Content
    var tint: Color? = nil

    var body: some View {
        content
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint ?? model.palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(model.palette.line, lineWidth: 1)
            )
    }
}

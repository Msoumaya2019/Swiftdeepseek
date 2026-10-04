// ReaderView.swift
// Lecteur plein écran du Moushaf.
//
// Correspondance : `ReaderScreen` de `src/App.tsx` + `ImmersiveReaderChrome.tsx`.
//
// ORGANISATION DE L'ESPACE — c'est ici que se joue le centrage vertical demandé.
// La pile est la suivante, de haut en bas :
//   1. la barre de titre (hauteur mesurée, jamais fixée en dur) ;
//   2. LA ZONE DE PAGE, qui prend TOUT l'espace restant ;
//   3. le mini-lecteur audio, s'il est ouvert ;
//   4. la barre d'actions.
// La page est centrée DANS la zone 2. Comme cette zone est définie par ce qui
// reste, elle s'adapte toute seule à l'encoche, à l'île dynamique, à la barre
// d'accueil et au mini-lecteur. Aucune marge haute fixe n'est utilisée nulle
// part, et le ratio des pages n'est jamais modifié (`scaleAspectFit`).

import SwiftUI

public struct ReaderView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    // Pas d'insertion de zone sûre lue depuis l'environnement : SwiftUI n'expose
    // pas `safeAreaInsets` par ce canal, et la mise en page n'en a pas besoin.
    // La zone de page prend l'espace RESTANT (voir l'en-tête) : elle s'adapte
    // donc déjà à l'encoche, à l'île dynamique et à la barre d'accueil, sans
    // qu'aucune marge haute soit fixée.

    let request: ReaderRequest
    let edition: QuranEdition

    @State private var page: Int
    @State private var showAudio = false
    @State private var showEditionPicker = false
    @State private var chromeHeight: CGFloat = 0

    public init(request: ReaderRequest, edition: QuranEdition, startPage: Int) {
        self.request = request
        self.edition = edition
        self._page = State(initialValue: request.range.flatMap { Quran.pageOf($0.start) } ?? startPage)
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { chromeHeight = proxy.size.height }
                    }
                )

            // Le lecteur peut afficher une autre édition que celle qui est
            // enregistrée (voir `QuranEdition.displayed(stored:)`). Le dire est
            // le seul moyen de ne pas faire passer une limite de cette version
            // pour un choix ignoré.
            if let substituted = model.substitutedEdition {
                substitutionNotice(substituted)
            }

            // ZONE DE PAGE : tout l'espace qui reste. C'est elle qui centre.
            ZStack {
                model.palette.cream
                MushafPageController(
                    page: $page,
                    edition: edition,
                    source: model.sources,
                    difficulty: difficultIDs,
                    bookmarks: bookmarkIDs,
                    playing: model.audio.currentVerseID,
                    session: readerSession,
                    style: VerseHighlightStyle.from(model.palette),
                    onPageChange: { _ in }
                )
                .accessibilityLabel("Moushaf, page \(page)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showAudio { audioBar }
            actionBar
        }
        .background(model.palette.cream)
        .ignoresSafeArea(edges: .bottom)
        .onDisappear { model.recordReading(page: page) }
        .sheet(isPresented: $showEditionPicker) { editionPicker }
    }

    // MARK: Barre de titre

    private var titleBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                model.recordReading(page: page)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel("Fermer le lecteur")

            VStack(alignment: .leading, spacing: 0) {
                Text(edition.label)
                    .font(.system(size: Theme.Typography.body, weight: .semibold))
                    .foregroundStyle(model.palette.text)
                Text("Page \(page) sur \(QuranSourceService.totalPages)")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
            }

            Spacer()

            Button {
                showEditionPicker = true
            } label: {
                Image(systemName: "books.vertical")
                    .font(.system(size: 17))
            }
            .accessibilityLabel("Changer d'édition")

            Button {
                toggleBookmark()
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 17))
            }
            .accessibilityLabel(isBookmarked ? "Retirer la marque-page" : "Marquer cette page")
        }
        .foregroundStyle(model.palette.green)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(model.palette.paper)
        .overlay(alignment: .bottom) {
            Rectangle().fill(model.palette.line).frame(height: 1)
        }
    }

    // MARK: Édition substituée

    /// Dit quelle édition est affichée **à la place** de celle qui est
    /// enregistrée, et pourquoi.
    ///
    /// Le cas n'est pas rare : l'application d'origine ouvre par défaut sur
    /// « Coran avec règles de Tajwid » (`src/core/program.ts:57`), une édition
    /// rendue dans un WebView et non reprise ici. Sans ce bandeau, un utilisateur
    /// venu de l'application React Native verrait le Coran de Médine sans
    /// explication.
    ///
    /// La préférence enregistrée n'est pas modifiée : elle reste `coranTest`
    /// dans le document synchronisé, et l'autre application continue de
    /// l'afficher telle quelle.
    private func substitutionNotice(_ stored: QuranEdition) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle")
            Text("« \(stored.label) » n'est pas encore lisible dans cette version. Affichage du \(edition.label).")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: Theme.Typography.metadata))
        .foregroundStyle(model.palette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(model.palette.soft)
    }

    // MARK: Barre d'actions

    /// Vrai quand le lecteur a été ouvert pour une **révision** — et non pour une
    /// simple lecture, ni pour une consolidation.
    ///
    /// Reproduit `App.tsx:476` : `reviewing = !!(reviewTask || revisionId || consolidation)`,
    /// combiné au fait que la barre de notation est masquée pendant une
    /// consolidation (`App.tsx:511` : `reviewing && !reader.consolidation`).
    private var isReviewing: Bool {
        request.reviewTask != nil && !request.consolidation
    }

    /// La séance à représenter dans la marge de la page, ou `nil` pour une
    /// lecture libre.
    ///
    /// Toute la dérivation d'`App.tsx:477-481` — quel suivi lire, quelle plage
    /// afficher, jusqu'où la séance est validée — vit dans
    /// `MarginAnnotations.session(...)`, où elle est éprouvable sans interface.
    /// Ici il n'y a que le passage des quatre entrées de la demande.
    ///
    /// `revisionId` n'existe pas dans `ReaderRequest` : une révision est
    /// toujours ouverte avec une `reviewTask` (`ReviewDashboardView.open`), donc
    /// la condition de l'original se réduit à ces trois-là.
    private var readerSession: MarginAnnotations.Session? {
        MarginAnnotations.session(
            learningSessionID: request.sessionID,
            reviewTaskID: request.reviewTask?.id,
            isConsolidation: request.consolidation,
            requestRange: request.range,
            state: model.state
        )
    }

    /// Le premier décalage de consolidation encore en attente pour le verset de
    /// début — 1, 3 ou 7. C'est celui que le bouton valide.
    ///
    /// Reproduit `App.tsx:474` :
    /// `([1,3,7] as const).find(o => !state.reviewConsolidations?.[range.start]?.completed[o])`.
    /// `nextConsolidation` lit les consolidations **stockées** et applique le même
    /// critère, sans avoir à rejouer la recherche à la main.
    private var pendingConsolidationOffset: Int? {
        guard let start = request.range?.start else { return nil }
        return Review.nextConsolidation(model.state, id: start)?.offset
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            if isReviewing { gradeBar }
            iconBar
        }
        .background(model.palette.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(model.palette.line).frame(height: 1)
        }
    }

    private var iconBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            actionButton("speaker.wave.2", showAudio ? "Masquer l'audio" : "Écouter") {
                showAudio.toggle()
                if showAudio { model.audio.play(verseID: currentVerseID) }
            }
            actionButton("chevron.left", "Page précédente") {
                page = max(1, page - 1)
            }
            actionButton("chevron.right", "Page suivante") {
                page = min(QuranSourceService.totalPages, page + 1)
            }
            actionButton(
                Review.isDifficult(model.state, currentVerseID) ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                "Marquer comme difficile"
            ) {
                model.update { Review.toggleDifficulty($0, id: currentVerseID) }
            }
            Spacer()
            trailingAction
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// L'action de droite dépend de **pourquoi** le lecteur a été ouvert. C'est
    /// le seul endroit où les trois cas se distinguent.
    @ViewBuilder
    private var trailingAction: some View {
        if request.consolidation {
            // Reproduit `App.tsx:511` :
            //   <Button onPress={validateConsolidation}>Valider la consolidation · J+{offset}</Button>
            // Le repli à 7 suit l'original (`consolidationOffset ?? 7`) : il ne
            // devrait pas servir, `pendingConsolidationOffset` étant non nul dès
            // lors qu'une consolidation reste due.
            Button("Valider la consolidation · J+\(pendingConsolidationOffset ?? 7)") {
                completeConsolidation()
            }
            .buttonStyle(.borderedProminent)
            .tint(model.palette.green)
            .font(.system(size: Theme.Typography.body, weight: .semibold))
            .accessibilityHint("Marque cette consolidation comme faite")

        } else if request.range != nil, let sessionID = request.sessionID {
            // La présence d'un `range` est la condition ; sa valeur n'est pas lue.
            // (La version précédente portait `.opacity(range.start > 0 ? 1 : 1)`,
            // qui ne changeait rien — les deux branches valaient 1.)
            Button("Valider") {
                model.update { Program.completeSession($0, id: sessionID, memorized: true) }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(model.palette.green)
            .font(.system(size: Theme.Typography.body, weight: .semibold))
            .accessibilityHint("Marque la séance comme apprise")
        }
    }

    /// Barre de notation d'une révision.
    ///
    /// Reproduit `RevisionBottomActionBar.tsx:7` — **mêmes icônes, mêmes
    /// libellés, même ordre**, et la même barre verticale de séparation avant la
    /// partie audio :
    ///
    ///     ['check','Parfait','perfect']
    ///     ['signal','Quelques hésitations','hesitant']
    ///     ['refresh','À retravailler','rework']
    ///     — séparation —
    ///     ['play','Écouter','audio']
    ///
    /// Les trois notes sont celles du vocabulaire des **tâches de révision**
    /// (`perfect | hesitant | rework`). L'application d'origine en a un SECOND,
    /// pour les révisions de versets (`errors | relearn`) — ne pas confondre :
    /// voir `Core/AppState.swift` et `SWIFT_MIGRATION.md` §9.6.
    ///
    /// L'original comporte un cinquième bouton, « Ma voix » (`onRecord`). Il n'est
    /// pas repris : l'enregistrement des récitations n'est pas implémenté côté
    /// Swift, et un bouton sans effet serait pire que son absence.
    private var gradeBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            gradeButton("check", "Parfait") { grade(.perfect) }
            gradeButton("signal", "Quelques hésitations") { grade(.hesitant) }
            gradeButton("refresh", "À retravailler") { grade(.rework) }

            Rectangle()
                .fill(model.palette.line)
                .frame(width: 1)
                .padding(.vertical, Theme.Spacing.sm)

            gradeButton("play", "Écouter") {
                showAudio.toggle()
                if showAudio { model.audio.play(verseID: currentVerseID) }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.sm)
    }

    private func gradeButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .foregroundStyle(model.palette.green)
        .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityLabel(label)
    }

    private func grade(_ grade: ReviewGrade) {
        guard let task = request.reviewTask else { return }
        model.update { Review.gradeReviewTask($0, task: task, grade: grade) }
        dismiss()
    }

    private func completeConsolidation() {
        guard let range = request.range else { return }
        model.update {
            Review.completeConsolidation($0, range: range, targetOffset: pendingConsolidationOffset)
        }
        dismiss()
    }

    private func actionButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(model.palette.green)
        .accessibilityLabel(label)
    }

    // MARK: Mini-lecteur audio

    private var audioBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                model.audio.togglePlayPause()
            } label: {
                Image(systemName: model.audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(model.palette.selected, in: Circle())
            }
            .accessibilityLabel(model.audio.isPlaying ? "Mettre en pause" : "Lire")

            VStack(alignment: .leading, spacing: 0) {
                Text(model.audio.reciter.name)
                    .font(.system(size: Theme.Typography.secondary, weight: .medium))
                    .lineLimit(1)
                if let verse = model.audio.currentVerseID {
                    Text("Verset \(verse)")
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                }
            }

            Spacer()

            Menu {
                ForEach(Reciter.all) { reciter in
                    Button(reciter.name) { model.selectReciter(reciter) }
                }
            } label: {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 16))
            }
            .accessibilityLabel("Changer de récitateur")
        }
        .foregroundStyle(model.palette.green)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(model.palette.soft)
    }

    // MARK: Choix de l'édition

    private var editionPicker: some View {
        NavigationStack {
            List {
                Section("Éditions disponibles") {
                    ForEach(QuranEdition.available, id: \.rawValue) { item in
                        Button {
                            model.setEdition(item)
                            showEditionPicker = false
                        } label: {
                            HStack {
                                Text(item.label)
                                Spacer()
                                if item == edition {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(model.palette.green)
                                }
                            }
                        }
                        .foregroundStyle(model.palette.text)
                    }
                }
                Section {
                    Text("""
                        Les éditions « Tawjeed test 2 » et « Medine Test » seront ajoutées \
                        dès que leurs ressources seront fournies.
                        """)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                }
            }
            .navigationTitle("Édition")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { showEditionPicker = false }
                }
            }
        }
    }

    // MARK: Aides

    private var currentVerseID: Int {
        request.range?.start ?? Quran.pageRange(page)?.start ?? 1
    }

    /// Les versets marqués **difficiles** — mis en évidence en rouge léger sur la
    /// page, jusqu'à retrait délibéré du marquage.
    ///
    /// La dérivation (clé entière, `user` ou `admin` présent) vit dans
    /// `Review.difficultIDs`, où elle est éprouvable sans interface.
    private var difficultIDs: Set<Int> {
        Review.difficultIDs(model.state)
    }

    /// Les versets marqués d'un **signet**, retirés exclus — `visibleBookmarks`,
    /// `src/core/bookmarks.ts:18`. Les marques de suppression sont conservées dans
    /// l'état, d'où le filtre sur `deletedAt`.
    private var bookmarkIDs: Set<Int> {
        Set(Bookmark.visible(model.state).map(\.verseId))
    }

    private var isBookmarked: Bool {
        model.state.bookmarks?[String(currentVerseID)]?.deletedAt == nil
            && model.state.bookmarks?[String(currentVerseID)] != nil
    }

    private func toggleBookmark() {
        let id = currentVerseID
        let existing = model.state.bookmarks?[String(id)]
        model.update { state in
            if existing != nil, existing?.deletedAt == nil {
                return Bookmark.delete(state, verseID: id)
            }
            return Bookmark.save(state, verseID: id, source: edition.rawValue, page: page)
        }
    }
}

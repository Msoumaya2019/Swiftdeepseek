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
    @Environment(\.safeAreaInsets) private var safeArea

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

            // ZONE DE PAGE : tout l'espace qui reste. C'est elle qui centre.
            ZStack {
                model.palette.cream
                MushafPageController(
                    page: $page,
                    edition: edition,
                    source: model.sources,
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

    // MARK: Barre d'actions

    private var actionBar: some View {
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
            if let range = request.range, let sessionID = request.sessionID {
                Button("Valider") {
                    model.update { Program.completeSession($0, id: sessionID, memorized: true) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.palette.green)
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                .accessibilityHint("Marque la séance comme apprise")
                .opacity(range.start > 0 ? 1 : 1)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(model.palette.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(model.palette.line).frame(height: 1)
        }
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

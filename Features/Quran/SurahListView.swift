// SurahListView.swift
// L'onglet Coran : la liste des sourates, des Juz' et des Hizb.
// Port de `QuranScreen` (`src/ui/MainScreens.tsx:28-34`).
//
// CE QUE CET ÉCRAN REMPLACE
//   `QuranScreenView` occupait l'onglet Coran avec autre chose : le choix
//   d'édition, l'installation du Coran 1441, la reprise et la porte des
//   marque-pages. Rien de tout cela n'est dans `QuranScreen`. L'original place
//   le choix d'édition dans le **lecteur** (`App.tsx:515`) et dans la carte de
//   réglages (`App.tsx:330`), et l'installation du 1441 dans le même sélecteur
//   du lecteur. Les deux y sont désormais — voir `ReaderView.editionPicker`.
//
//   Ce qui reste ici est ce que la référence affiche : le héros, la carte
//   « J'ai appris jusqu'à », la recherche, le filtre, les trois vues, la liste,
//   la carte de pied, et le bouton flottant « Dernière lecture ».
//
// AUCUNE RÈGLE ICI
//   Les trois vues, le filtre, la recherche, les textes et les pages d'une
//   division vivent dans `Core/SurahListOptions.swift`. Cet écran ne décide que
//   des **effets** : ouvrir le lecteur, écrire une préférence, ouvrir un écran.
//
// LE BOUTON FLOTTANT EST POSÉ SUR LA LISTE, PAS DANS
//   `position:'absolute'` dans l'original, donc par-dessus le défilement. Un
//   `overlay` sur la `ScrollView` reproduit cela ; le `padding(.bottom, 90)` du
//   contenu est la place qu'on lui laisse, exactement comme le
//   `contentContainerStyle={{paddingBottom:90}}` de la référence.

import SwiftUI

struct SurahListView: View {

    @EnvironmentObject private var model: AppViewModel

    @State private var mode: SurahListOptions.Mode = .liste
    @State private var query = ""
    @State private var filter: SurahListOptions.Filter = .all
    @State private var readerRequest: ReaderRequest?
    @State private var showGoal = false
    @State private var showFilter = false

    /// L'édition avec laquelle ouvrir le lecteur, **figée au moment de l'appui**.
    ///
    /// POURQUOI CE N'EST PAS `model.edition` DANS LA FERMETURE
    ///   `model.setEdition` passe par `AppViewModel.update`, qui ouvre une
    ///   `Task` : le dépôt n'a pas encore rafraîchi son état quand le
    ///   `fullScreenCover` se présente. Lire `model.edition` à cet instant
    ///   rendrait l'édition **précédente** — et depuis la carte de pied, un
    ///   utilisateur qui lisait le Coran 1441 ouvrirait le lecteur en 1441 au
    ///   lieu du repli. C'est l'appelant qui sait ce qu'il vient d'écrire : il
    ///   le calcule donc lui-même.
    @State private var readerEdition: QuranEdition = .medine

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                ForEach(rows) { row in
                    rowButton(row)
                }

                if rows.isEmpty { emptyState }

                tajweedCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 90)
        }
        .background(model.palette.cream)
        .overlay(alignment: .bottomTrailing) { lastReadButton }
        .fullScreenCover(item: $readerRequest) { request in
            ReaderView(request: request, edition: readerEdition, startPage: request.page)
                .environmentObject(model)
        }
        .sheet(isPresented: $showGoal) {
            ProgramEditorView(state: model.state)
        }
        .confirmationDialog(
            SurahListOptions.filterButton,
            isPresented: $showFilter,
            titleVisibility: .visible
        ) {
            ForEach(SurahListOptions.Filter.allCases, id: \.rawValue) { option in
                Button(SurahListOptions.filterLabel(option)) { filter = option }
            }
            Button(SurahListOptions.filterCancel, role: .cancel) {}
        } message: {
            Text(SurahListOptions.filterAlertMessage)
        }
    }

    // MARK: - Les lignes

    /// Recalculées à chaque rendu, comme l'original — qui les dérive aussi dans
    /// le corps du composant, sans mémoïsation (`MainScreens.tsx:31`).
    private var rows: [SurahListOptions.Row] {
        SurahListOptions.rows(
            mode: mode,
            query: query,
            filter: filter,
            edition: model.edition
        )
    }

    // MARK: - L'en-tête

    @ViewBuilder
    private var header: some View {
        HeroHeader(
            title: SurahListOptions.heroTitle,
            subtitle: SurahListOptions.heroSubtitle(mode)
        )

        learnedCard

        searchRow

        SegmentedControl(
            options: SurahListOptions.Mode.allCases.map(\.label),
            selection: modeSelection
        )
        .padding(.top, Theme.Spacing.sm)
    }

    /// Le sélecteur des trois vues.
    ///
    /// Changer de vue **vide la recherche** — `onChange={value=>{setView(value);
    /// setQuery('')}}` (`MainScreens.tsx:32`). Ce n'est pas un détail : une
    /// recherche de sourate ne trouve rien dans la vue « Juz' », et la garder
    /// donnerait une liste vide sans que l'utilisateur ait rien fait.
    private var modeSelection: Binding<Int> {
        Binding(
            get: { SurahListOptions.Mode.allCases.firstIndex(of: mode) ?? 0 },
            set: { index in
                guard SurahListOptions.Mode.allCases.indices.contains(index) else { return }
                mode = SurahListOptions.Mode.allCases[index]
                query = ""
            }
        )
    }

    /// « J'ai appris jusqu'à » — `MainScreens.tsx:32`.
    ///
    /// Le crayon ouvre `ProgramEditorView`, la traduction du `GoalScreen` que
    /// `onEditKnowledge` monte dans l'original (`App.tsx:248` →
    /// `setUtilityView('goal')`). L'alerte de repli de l'original n'est donc
    /// **jamais** atteinte ici : elle ne sert que si aucun gestionnaire n'est
    /// fourni, et l'original en fournit toujours un.
    private var learnedCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "book")
                    .font(.system(size: 20))
                    .foregroundStyle(model.palette.green)

                VStack(alignment: .leading, spacing: 0) {
                    Text(SurahListOptions.learnedPrefix)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                    Text(SurahListOptions.lastLearned(model.state))
                        .font(.system(size: Theme.Typography.card, weight: .semibold))
                        .foregroundStyle(model.palette.green)
                }

                Spacer(minLength: 0)

                Button { showGoal = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 24))
                        .foregroundStyle(model.palette.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SurahListOptions.editKnowledge)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    /// La recherche, et le bouton de filtre — qui n'existe que dans la vue
    /// « Liste » (`view==='Liste'&&<IconButton …/>`, `MainScreens.tsx:32`).
    private var searchRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField(SurahListOptions.searchPlaceholder(mode), text: $query)
                .font(.system(size: Theme.Typography.body))
                .foregroundStyle(model.palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    model.palette.paper,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .stroke(model.palette.line, lineWidth: 1)
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if mode == .liste {
                Button { showFilter = true } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 24))
                        .foregroundStyle(model.palette.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SurahListOptions.filterButton)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Une ligne

    private func rowButton(_ row: SurahListOptions.Row) -> some View {
        Button { open(row) } label: { rowContent(row) }
            .buttonStyle(.plain)
            .accessibilityLabel(SurahListOptions.openLabel(row.name))
            .padding(.bottom, 5)
    }

    private func rowContent(_ row: SurahListOptions.Row) -> some View {
        Card(padding: 10) {
            HStack(spacing: 10) {
                QuranNumberMedallion(number: row.number)

                VStack(alignment: .leading, spacing: 2) {
                    // `Heading size={18}` : l'original ne passe PAS de couleur, et
                    // le défaut de `Heading` est `colors.green`
                    // (`src/ui/DesignSystem.tsx:9`) — pas la couleur du texte.
                    Text(row.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.palette.green)
                        .multilineTextAlignment(.leading)
                    Text(row.meaning)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                        .lineLimit(1)
                }
                // Le nom garde son espace ; c'est l'arabe qui se resserre.
                .layoutPriority(1)

                Spacer(minLength: 0)

                if row.kind == .surah { originBadge(row) }

                if !row.arabic.isEmpty {
                    // `maxWidth:'24%'` dans l'original : le garde-fou qui empêche
                    // l'arabe de manger le nom. Exprimé ici par la priorité
                    // ci-dessus plutôt que par un pourcentage — un pourcentage
                    // aurait demandé de mesurer la ligne, pour un résultat
                    // visiblement identique.
                    ArabicLabel(text: row.arabic, size: 20, color: model.palette.green)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 19))
                    .foregroundStyle(model.palette.muted)
            }
        }
    }

    /// Le badge de lieu de révélation et le nombre de versets.
    ///
    /// Rendus pour les **sourates** seulement (`item.kind==='surah'`). Les deux
    /// couleurs du badge « Médinoise » ne suivent pas le thème : `review` et
    /// `reviewSoft` sont ajoutés APRÈS les palettes
    /// (`src/ui/theme.tsx:15`) — voir `Theme.review`.
    private func originBadge(_ row: SurahListOptions.Row) -> some View {
        VStack(spacing: 4) {
            Text(SurahListOptions.originBadge(isMeccan: row.isMeccan))
                .font(.system(size: 10))
                .foregroundStyle(row.isMeccan ? model.palette.green : Theme.review)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    row.isMeccan ? model.palette.selected : Theme.reviewSoft,
                    in: RoundedRectangle(cornerRadius: 10)
                )
            Text(SurahListOptions.verseCount(row.count))
                .font(.system(size: 10))
                .foregroundStyle(model.palette.muted)
        }
    }

    /// `ListEmptyComponent` — `MainScreens.tsx:33`.
    private var emptyState: some View {
        Text(SurahListOptions.emptyState)
            .font(.system(size: Theme.Typography.secondary))
            .foregroundStyle(model.palette.muted)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - La carte de pied

    /// « Coran avec règles de Tajwid » — `ListFooterComponent`.
    ///
    /// Elle ÉCRIT la préférence avant d'ouvrir le lecteur
    /// (`mushaf:'coranTest'`, `followAudio` remis à son défaut), exactement
    /// comme `QuranDisplayOptions.settingEdition(_:_:)` : l'écran ne refait pas
    /// cette écriture, il l'appelle. C'est ce qui garantit que la préférence
    /// reste celle que l'application React Native relira.
    ///
    /// L'édition n'étant pas rendue par cette version, le lecteur affichera le
    /// Coran de Médine **en le disant** (`ReaderView.substitutionNotice`).
    private var tajweedCard: some View {
        Button { openTajweed() } label: {
            Card(padding: 8) {
                HStack(spacing: 12) {
                    ReadingArt()
                        .frame(width: 105, height: 75)
                        .clipShape(RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(SurahListOptions.tajweedTitle)
                            .font(.system(size: Theme.Typography.card, weight: .semibold))
                            .foregroundStyle(model.palette.green)
                            .multilineTextAlignment(.leading)
                        Text(SurahListOptions.tajweedSubtitle)
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(model.palette.green)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Le bouton flottant

    /// `position:'absolute', right:18, bottom:12, 70 × 70, borderRadius:35`.
    private var lastReadButton: some View {
        Button { openLastRead() } label: {
            VStack(spacing: 0) {
                Image(systemName: "book")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                Text(SurahListOptions.lastReadButton)
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 70, height: 70)
            .background(model.palette.green, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SurahListOptions.lastReadButton)
        .padding(.trailing, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Les effets

    /// Un appui sur une ligne — `openReader({range:{start,end}})`.
    private func open(_ row: SurahListOptions.Row) {
        let range = VerseRange(start: row.start, end: row.end)
        readerEdition = model.edition
        readerRequest = ReaderRequest(
            range: range,
            sessionID: nil,
            page: SurahListOptions.page(range.start, edition: readerEdition)
        )
    }

    /// « Dernière lecture » — `openReader({range:{start:id,end:id}})` avec
    /// `id = state.lastRead?.verseId ?? 1`.
    private func openLastRead() {
        let verseID = SurahListOptions.lastReadVerse(model.state)
        readerEdition = model.edition
        readerRequest = ReaderRequest(
            range: VerseRange(start: verseID, end: verseID),
            sessionID: nil,
            page: SurahListOptions.page(verseID, edition: readerEdition)
        )
    }

    /// La carte de pied : écrire la préférence, puis ouvrir la page de
    /// `reader.testPage` dans la pagination du **moushaf**.
    private func openTajweed() {
        let range = SurahListOptions.tajweedRange(model.state)
        let edition = SurahListOptions.tajweedEdition

        model.setEdition(edition)

        // L'édition AFFICHÉE, calculée ici et non lue plus tard : `setEdition`
        // est asynchrone, et `.coranTest` n'est pas rendue — le repli est le
        // Coran de Médine (`QuranEdition.displayed(stored:)`).
        readerEdition = QuranEdition.displayed(stored: edition.rawValue)
        readerRequest = ReaderRequest(
            range: range,
            sessionID: nil,
            page: SurahListOptions.page(range.start, edition: readerEdition)
        )
    }
}

// MARK: - L'illustration de la carte de pied

/// `readingArt` — `src/ui/DesignSystem.tsx:8`, `assets/illustrations/reading.png`.
///
/// Le fichier est copié à l'octet depuis la référence (2 371 675 octets,
/// 1374 × 1145) et posé à la RACINE du paquet : il se charge donc par son nom.
///
/// Le recadrage est un **remplissage**, pas un ajustement : l'original pose
/// `width:105, height:75` — un rapport de 1,4 — sur une image de rapport 1,2, et
/// le `resizeMode` par défaut de React Native est `cover`. Un ajustement qui
/// préserve l'image entière laisserait des bandes vides, comme pour
/// `white.png` dans `ThemeArtImage`.
private struct ReadingArt: View {
    var body: some View {
        if let image = UIImage(named: "reading") {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            Color.clear
        }
    }
}

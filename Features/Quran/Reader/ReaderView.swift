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
    @State private var showAudioSettings = false
    @State private var showEditionPicker = false
    @State private var showBookmarks = false
    @State private var chromeHeight: CGFloat = 0

    public init(request: ReaderRequest, edition: QuranEdition, startPage: Int) {
        self.request = request
        self.edition = edition
        // LA PAGE D'UN VERSET DÉPEND DE L'ÉDITION AFFICHÉE
        //   C'est `sourceVersePage` de l'original (`src/App.tsx:211`) : la page
        //   connue si elle porte le verset dans cette édition, sinon la première
        //   page du verset. `Quran.pageOf` rendait toujours une page du **Coran de
        //   Médine** : ouvrir « Al Mâ'idah » depuis la liste en affichant le Coran
        //   1441 rendait donc un numéro de page de l'AUTRE pagination. Le défaut
        //   est réel et mesuré — **56 versets sur 6 236** changent de première page
        //   entre les deux éditions, le premier étant le verset 746 (Al Mâ'idah
        //   77 : page 121 au Médine, 120 en 1441).
        //
        //   La page connue de l'original — `lastRead.page`, quand
        //   `lastRead.verseId == range.start` — n'est pas transmise, et c'est
        //   mesuré aussi : **aucun verset n'est à cheval sur deux pages** dans
        //   l'un ni l'autre des deux jeux de rectangles, donc `pages.first` est
        //   toujours la seule page du verset et la valeur connue ne peut pas en
        //   désigner une autre. La transmettre ne changerait rien ; l'ignorer est
        //   une simplification prouvée, pas un raccourci.
        self._page = State(initialValue: request.range.flatMap {
            QuranSourceNavigation.versePage(edition, verseID: $0.start)
        } ?? startPage)
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
                // TROISIÈME FORME DU CORPS — l'édition « Lecture simplifiée »
                // n'est pas une page.
                //
                // Les deux autres éditions rendues ici sont des images : une page,
                // un rectangle, et un `UIPageViewController` qui les fait glisser.
                // « Lecture simplifiée » rend le **texte** des versets, en cartes
                // qui défilent (`MushafPage.tsx:34-43`, `App.tsx:499`). Elle ne
                // peut donc pas passer par le contrôleur de pages : c'est la seule
                // raison de cette branche, et la seule édition qui l'emprunte.
                if edition == .tajweed {
                    TajweedVerseListView(
                        page: page,
                        language: .arabic,
                        playing: model.audio.currentVerseID,
                        difficulty: difficultIDs,
                        bookmarks: bookmarkIDs,
                        session: readerSession,
                        palette: model.palette
                    )
                } else {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showAudio { audioBar }
            actionBar
        }
        .background(model.palette.cream)
        .ignoresSafeArea(edges: .bottom)
        .onDisappear { model.recordReading(page: page) }
        .sheet(isPresented: $showEditionPicker) { editionPicker }
        .sheet(isPresented: $showAudioSettings) {
            AudioRepeatSettingsView(
                sessionRange: audioSessionRange,
                pageRangeOverride: sourcePageRange
            )
        }
        // L'original REMPLACE le lecteur par la liste (`App.tsx:492`) ; ici, un
        // plein écran par-dessus — même effet visible, et le lecteur garde sa
        // page courante, que `page` porte déjà.
        .fullScreenCover(isPresented: $showBookmarks) {
            BookmarksView(edition: edition, onResume: resumeFromBookmark)
                .environmentObject(model)
        }
    }

    /// La plage de la page lue **dans la pagination de l'édition affichée**, ou
    /// `nil` si la page n'en a pas.
    ///
    /// C'est `sourcePageRange(mushaf, page)` de l'original (`App.tsx:437`), que
    /// `App.tsx:505` passe au panneau audio sous le nom `pageRangeOverride`, et
    /// qui y sert la pastille « Toute la page » (`PassageAudioPlayer.tsx:36`).
    ///
    /// POURQUOI LA PLAGE DÉPEND DE L'ÉDITION, ET PAS SEULEMENT DE LA PAGE
    ///   Les deux paginations ne coïncident pas : **36 pages sur 604** portent
    ///   une plage différente, et sur 33 d'entre elles la LONGUEUR diffère aussi
    ///   (page 597 : 6 099…6 125 au Médine contre 6 093…6 118 en 1441). Lire la
    ///   page 121 du Coran 1441 et se voir proposer 746…751 — la plage du Coran
    ///   de Médine — annonce un passage qui n'est pas celui qu'on lit. C'est le
    ///   défaut que ce calcul remplace, et il était servi à toutes les pages de
    ///   toutes les éditions.
    private var displayedPageRange: VerseRange? {
        QuranSourceNavigation.pageRange(edition, page: page)
    }

    /// La plage que l'écran de réglages appelle « Ma séance ».
    ///
    /// C'est celle de la demande quand elle existe — une séance du programme ou
    /// une tâche de révision —, sinon la page affichée. Jamais une plage vide :
    /// l'écran doit toujours avoir quelque chose à lancer.
    ///
    /// Le repli sur la page n'existe pas dans l'original, dont `reader.range`
    /// est toujours posé : il vient du programme. Ici la demande peut n'en
    /// porter aucun — « Dernière lecture » ou un marque-page ouvrent sur un
    /// verset —, et il en faut un. Il prend donc la page affichée, **dans la
    /// pagination de l'édition affichée**, et non celle du Coran de Médine.
    private var audioSessionRange: VerseRange {
        request.range ?? displayedPageRange ?? VerseRange(start: 1, end: 1)
    }

    /// La plage de la page affichée, jamais vide — ce que l'écran audio reçoit.
    ///
    /// Le repli sur la séance n'existe pas dans l'original : `pageRange` lève
    /// sur une page hors bornes, et `zipPageRange` rend alors une plage infinie.
    /// Les deux sont inatteignables — `pages.json` et `coran_1441-bounds.json`
    /// portent chacun 604 pages —, mais l'écran doit avoir quelque chose à
    /// lancer dans tous les cas, et retomber sur la séance vaut mieux que
    /// retirer la pastille.
    private var sourcePageRange: VerseRange {
        displayedPageRange ?? audioSessionRange
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

            // Deux gestes distincts, deux boutons. Celui du dessus POSE ou RETIRE
            // une marque-page sur le verset courant ; celui-ci ouvre la LISTE,
            // d'où l'on reprend une marque-page existante. Les confondre rendait
            // la liste inatteignable depuis le lecteur — qui est pourtant
            // l'endroit où l'on en a besoin.
            Button {
                showBookmarks = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17))
            }
            .accessibilityLabel(BookmarkOptions.screenTitle)
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

            Button {
                showAudioSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
            }
            .accessibilityLabel("Réglages de répétition")
        }
        .foregroundStyle(model.palette.green)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(model.palette.soft)
    }

    // MARK: Choix de l'édition

    /// « Affichage du Coran » — le sélecteur modal de l'original (`App.tsx:515`).
    ///
    /// POURQUOI IL PASSE PAR `QuranEditionChooser`
    ///   Ce sélecteur avait sa propre liste : `QuranEdition.available`, soit les
    ///   **deux** éditions rendues ici, plus une note annonçant que « Tawjeed
    ///   test 2 » et « Medine Test » viendraient plus tard. Or ces deux noms ne
    ///   sont pas des éditions : ce sont d'anciennes clés, que
    ///   `migrateReaderState` réécrit vers `coran_1441` (`program.ts:60`). Et
    ///   l'original propose **quatre** entrées ici comme dans la carte de
    ///   réglages — les deux listes s'accordent.
    ///
    ///   Passer par le composant partagé, c'est garantir que les trois portes
    ///   (celle-ci, la carte de réglages, et l'onglet Coran tant qu'il l'a
    ///   portée) proposent la même liste dans le même ordre. C'est aussi lui qui
    ///   route l'appui : choisir le Coran 1441 quand il n'est pas installé
    ///   déclenche l'installation au lieu d'ouvrir un lecteur vide.
    ///
    /// CE QU'IL NE FAIT PAS ENCORE
    ///   Changer d'édition ici **n'échange pas** celle du lecteur ouvert :
    ///   `ReaderView.edition` est figée à la construction, et la page courante
    ///   est un numéro de la pagination précédente. La recalculer dans la
    ///   nouvelle pagination est un bloc à part — la faire à moitié montrerait
    ///   une page **fausse** dans le Coran 1441, ce qui est pire que de laisser
    ///   l'ancienne édition à l'écran. La préférence est bien écrite, et
    ///   l'application React Native la relit.
    private var editionPicker: some View {
        NavigationStack {
            List {
                Section {
                    QuranEditionChooser(
                        stored: model.state.reader?.mushaf,
                        coran1441Installed: model.coran1441.isInstalled,
                        // Le sélecteur modal de l'original rend les entrées en
                        // `Button` nus (`App.tsx:515`) ; la carte de réglages,
                        // elle, montre les sous-titres.
                        showsSubtitles: false,
                        onSelect: { item in
                            model.setEdition(item)
                            showEditionPicker = false
                        },
                        onInstall: { _ in model.coran1441.start() },
                        onUnavailable: { item in
                            model.notice = QuranDisplayOptions.unavailableNotice(for: item)
                        }
                    )
                }

                // La progression de l'installation, quand il y en a une. Une fois
                // le Coran 1441 installé, la section disparaît et le sélecteur
                // redevient une simple liste d'éditions.
                if !model.coran1441.isInstalled {
                    Section("Coran 1441") {
                        Coran1441InstallView()
                    }
                }
            }
            .navigationTitle(QuranDisplayOptions.cardTitle)
            .onAppear { model.coran1441.refresh() }
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

    /// « Reprendre » depuis la liste — `App.tsx:492`.
    ///
    /// Toute la règle vit dans `AppViewModel.resumeBookmark` : la page à ouvrir,
    /// et la date de dernier usage (`Bookmark.use`, qui fait vivre le badge
    /// « Dernière reprise »). Ici, il ne reste que l'effet propre au lecteur —
    /// se déplacer, puis fermer la liste.
    ///
    /// La sélection du verset et la remise à zéro du panneau de séance, que
    /// l'original fait aussi, n'ont pas d'équivalent dans ce portage.
    private func resumeFromBookmark(_ verseID: Int) {
        if let target = model.resumeBookmark(verseID) { page = target }
        showBookmarks = false
    }
}

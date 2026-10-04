// AudioRepeatSettingsView.swift
// Les réglages de répétition audio — l'écran SANS décision.
//
// Correspondance : `src/PassageAudioPlayer.tsx:236-271`.
//
// RÈGLE DE CE FICHIER : il ne calcule rien.
//   Tous les libellés viennent de `AudioRepeatPreferences` — `countLabel`,
//   `countText`, `showsAutoStopSelected`, `displaysUnlimitedRepetition`,
//   `launchError` —, la marge technique de `PassageAudio`, et les plages de
//   `Quran` / `PassageAudio.range`. Aucun nombre de la liste des répétitions
//   n'est écrit ici, aucun libellé de vitesse, aucun état de case à cocher.
//
//   C'est ce qui rend cet écran vérifiable **par lecture** : il n'y a rien à
//   éprouver, parce qu'il n'y a aucune décision à se tromper. C'est aussi ce qui
//   garantit que les deux applications affichent la même chose à réglage égal —
//   les trois pièges d'affichage de l'original sont portés par le modèle, et non
//   recopiés ici :
//
//     - `autoStop` reste **vrai** en mode « en continu » ; c'est la **case** qui
//       se décoche (`showsAutoStopSelected`), pas le réglage qui change. Un
//       `Toggle` lié à `autoStop` afficherait donc l'état STOCKÉ, et divergerait
//       de l'original : la case est ici un bouton qui montre une coche.
//     - le `∞` a **deux** causes distinctes — « en continu », ou l'arrêt
//       automatique décoché — d'où `displaysUnlimitedRepetition`.
//     - la pause de `0` seconde s'affiche « Aucune », et la vitesse `0,75` s'écrit
//       avec une **virgule**. L'original porte deux libellés pour la même pause —
//       « 0s » dans la barre repliée (`:241`), « Aucune » dans le panneau
//       détaillé (`:248`) — et deux écritures pour la même vitesse (« 0.75x » et
//       « 0,75× »). Cet écran est le panneau détaillé : il retient la forme
//       complète, la seule qui dise quelque chose à l'utilisateur.
//
// LES RÉGLAGES SONT LOCAUX, ET ILS SONT ENFIN ÉCRITS
//   `Storage/LocalStore.swift` savait lire et écrire le fichier
//   `audio-repeat-preferences.json` depuis le début, mais **personne ne
//   l'appelait** : les réglages n'étaient persistés nulle part. Cet écran est le
//   premier appelant, et c'est `AppViewModel` qui écrit, à chaque changement.
//
// CE QUI RESTE
//   La couche AVFoundation — l'exécuteur des `PassageAudioEffect`. Cet écran
//   lance la lecture du **premier** verset de la plage ; la boucle de répétition
//   est décidée par `Core/PassageAudioEngine.swift`, mais rien ne la pilote
//   encore. Voir `SWIFT_MIGRATION.md` §9.16.

import SwiftUI

struct AudioRepeatSettingsView: View {

    /// Les deux valeurs que l'original reçoit de son parent
    /// (`PassageAudioPlayer.tsx:19`) : la plage de la séance, et la page lue.
    let sessionRange: VerseRange
    let page: Int

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// `:13` — `type Selection='session'|'verse'|'custom'|'page'|'surah'`.
    private enum Selection {
        case session, verse, custom, page, surah
    }

    @State private var selection: Selection = .session
    @State private var selectedRange: VerseRange
    @State private var chosenID: Int
    @State private var surahText: String
    @State private var firstText: String
    @State private var lastText: String
    /// Le message du dernier lancement refusé. Il vient de `launchError`, ou de
    /// la résolution de la plage — jamais d'un calcul fait ici.
    @State private var error: String?

    init(sessionRange: VerseRange, page: Int) {
        self.sessionRange = sessionRange
        self.page = page
        let first = Quran.verseAt(sessionRange.start)
        let last = Quran.verseAt(sessionRange.end)
        _selectedRange = State(initialValue: sessionRange)
        _chosenID = State(initialValue: sessionRange.start)
        _surahText = State(initialValue: String(first.surah))
        _firstText = State(initialValue: String(first.ayah))
        _lastText = State(initialValue: last.surah == first.surah ? String(last.ayah) : String(first.ayah))
    }

    // MARK: - Le réglage courant

    /// Une seule porte d'écriture : on part du réglage courant, on le modifie,
    /// et `AppViewModel` l'écrit sur disque. Aucun état local ne double le
    /// réglage — sinon les deux pourraient diverger, en silence.
    private var preferences: AudioRepeatPreferences { model.repeatPreferences }

    private func update(_ transform: (inout AudioRepeatPreferences) -> Void) {
        var updated = model.repeatPreferences
        transform(&updated)
        model.setRepeatPreferences(updated)
    }

    // MARK: - Corps

    var body: some View {
        NavigationStack {
            List {
                reciterSection
                passageSection
                repetitionsSection
                modeSection
                speedSection
                gapSection
                autoStopSection
                if let error {
                    Section { Text(error).foregroundStyle(palette.red) }
                }
                launchSection
            }
            .navigationTitle("Écouter un récitateur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    // MARK: - Récitateur

    /// `:244` et `:259` — la liste, avec l'écriture arabe en sous-titre quand le
    /// récitateur en a une.
    @ViewBuilder private var reciterSection: some View {
        Section("Récitateur") {
            ForEach(Reciter.all) { reciter in
                Button {
                    model.selectReciter(reciter)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reciter.name)
                                .font(.system(size: Theme.Typography.body))
                            if let arabic = reciter.arabic {
                                Text(arabic)
                                    .font(.system(size: Theme.Typography.secondary))
                                    .foregroundStyle(palette.muted)
                            }
                        }
                        Spacer()
                        if reciter.id == model.audio.reciter.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(palette.green)
                        }
                    }
                }
                .foregroundStyle(palette.text)
            }
        }
    }

    // MARK: - Choix du passage

    @ViewBuilder private var passageSection: some View {
        Section("Choisir le passage") {
            grid {
                pill("Ce verset", selected: selection == .verse) {
                    let identifier = model.audio.currentVerseID ?? chosenID
                    choose(VerseRange(start: identifier, end: identifier))
                    selection = .verse
                }
                pill("Toute la page", selected: selection == .page) {
                    choose(currentPageRange)
                    selection = .page
                }
                pill("Toute la sourate", selected: selection == .surah) {
                    let surah = Quran.surahAt(model.audio.currentVerseID ?? chosenID)
                    choose(VerseRange(start: surah.start, end: surah.end))
                    selection = .surah
                }
                pill("Ma séance", selected: selection == .session) {
                    choose(sessionRange)
                    selection = .session
                }
            }
            Text(Quran.reference(displayedRange))
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.muted)
            HStack {
                Text("Sourate (1–114)").font(.system(size: Theme.Typography.body))
                Spacer()
                TextField("1", text: $surahText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 72)
                    .onChange(of: surahText) { _ in
                        // `:246` et `:260` : changer la sourate remet les deux
                        // bornes à 1 et bascule en saisie libre.
                        firstText = "1"
                        lastText = "1"
                        selection = .custom
                    }
            }
            stepper("Du verset", text: $firstText)
            stepper("Au verset", text: $lastText)
        }
    }

    /// `:236` — le pas à pas, porté tel quel : la borne basse est **1**, la borne
    /// haute est le nombre de versets de la sourate choisie.
    private func stepper(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title).font(.system(size: Theme.Typography.body))
            Spacer()
            Button {
                text.wrappedValue = stepped(text.wrappedValue, by: -1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 34)
                    .background(palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) : reculer d'un verset")

            TextField("1", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 64)

            Button {
                text.wrappedValue = stepped(text.wrappedValue, by: 1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 34)
                    .background(palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) : avancer d'un verset")
        }
        .foregroundStyle(palette.green)
    }

    // MARK: - Répétitions

    @ViewBuilder private var repetitionsSection: some View {
        Section("Répétitions") {
            grid {
                // `:14` — l'ORDRE des pastilles est celui du modèle, jamais
                // celui d'une liste recopiée.
                ForEach(Array(AudioRepeatPreferences.countChoices.enumerated()), id: \.offset) { _, choice in
                    pill(AudioRepeatPreferences.countLabel(choice),
                         selected: preferences.countChoice == choice) {
                        update { $0.countChoice = choice }
                    }
                }
            }
            if preferences.countChoice == .custom {
                // `:265` — le champ libre, gardé en **chaîne** : un `'1,5'`
                // refusé doit rester affiché tel quel.
                TextField("Nombre personnalisé (1 à 999)", text: Binding(
                    get: { preferences.customCount },
                    set: { value in update { $0.customCount = value } }
                ))
                .keyboardType(.numberPad)
            }
        }
    }

    // MARK: - Mode

    @ViewBuilder private var modeSection: some View {
        Section("Mode") {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(RepeatMode.allCases, id: \.rawValue) { mode in
                    pill(mode == .passage ? "Passage complet" : "Chaque verset",
                         selected: preferences.repeatMode == mode) {
                        update { $0.repeatMode = mode }
                    }
                }
            }
        }
    }

    // MARK: - Vitesse

    @ViewBuilder private var speedSection: some View {
        Section("Vitesse") {
            grid {
                // `:268` — `String(value).replace('.',',')+'×'`.
                ForEach(AudioRepeatPreferences.speedChoices, id: \.self) { value in
                    pill(Self.speedLabel(value), selected: preferences.speed == value) {
                        update { $0.speed = value }
                    }
                }
            }
        }
    }

    // MARK: - Pause

    @ViewBuilder private var gapSection: some View {
        Section {
            grid {
                // `:268` — `value?`${value} s`:'Aucune'`.
                ForEach(AudioRepeatPreferences.gapChoices, id: \.self) { value in
                    pill(value == 0 ? "Aucune" : "\(value) s", selected: preferences.gap == value) {
                        update { $0.gap = value }
                    }
                }
            }
        } header: {
            Text("Pause entre deux écoutes")
        } footer: {
            // Le nombre vient du modèle, jamais d'un littéral recopié.
            Text("Une marge technique de \(PassageAudio.defaultAyahGapMilliseconds) ms reste active entre les versets.")
        }
    }

    // MARK: - Arrêt automatique

    @ViewBuilder private var autoStopSection: some View {
        Section {
            Button {
                update { $0.autoStop.toggle() }
            } label: {
                HStack {
                    Text("Arrêter à la fin des écoutes")
                        .font(.system(size: Theme.Typography.body))
                    Spacer()
                    if preferences.showsAutoStopSelected {
                        Image(systemName: "checkmark").foregroundStyle(palette.green)
                    }
                }
            }
            .foregroundStyle(palette.text)
            .accessibilityAddTraits(preferences.showsAutoStopSelected ? [.isSelected] : [])
        } footer: {
            // `:256` / `:258` — la durée restante affichée : `∞` quand le compte
            // est « en continu » **ou** quand l'arrêt automatique est décoché.
            Text("Écoutes prévues : \(AudioRepeatPreferences.countText(preferences.count))"
                + (preferences.displaysUnlimitedRepetition ? " (sans fin)" : ""))
        }
    }

    // MARK: - Lancement

    @ViewBuilder private var launchSection: some View {
        Section {
            Button("▶ Lancer ce passage") { launch() }
                .foregroundStyle(palette.green)
            Button("Recommencer le passage") {
                choose(sessionRange)
                selection = .session
                launch()
            }
            .foregroundStyle(palette.green)
        }
    }

    // MARK: - Une pastille

    private func pill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: Theme.Typography.secondary, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? palette.paper : palette.green)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    selected ? palette.green : palette.soft,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// `:237` et `:245` — les pastilles s'enroulent : leur nombre varie avec le
    /// réglage (sept répétitions, deux modes, trois vitesses, quatre pauses).
    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Theme.Spacing.xs)],
                  spacing: Theme.Spacing.xs) {
            content()
        }
    }

    // MARK: - La plage désignée

    /// `:234` — la plage **affichée** : celle de la sélection, ou la dernière
    /// valide pendant qu'un champ est en cours d'édition. L'original enveloppe
    /// `selectionRange()` d'un `try` et garde `selectedRange` en cas d'échec.
    private var displayedRange: VerseRange {
        (try? selectionRange()) ?? selectedRange
    }

    /// `:103-110` — `selectionRange`, porté tel quel.
    private func selectionRange() throws -> VerseRange {
        switch selection {
        case .session, .page, .surah:
            return selectedRange
        case .verse:
            return VerseRange(start: chosenID, end: chosenID)
        case .custom:
            // `verseId(Number(surahText), Number(firstText))`. Le pavé numérique
            // ne produit que des entiers : une valeur non entière est traitée
            // comme absente, là où l'original la laisserait passer.
            let surah = AudioRepeatPreferences.customInteger(surahText)
            let from = AudioRepeatPreferences.customInteger(firstText)
            let to = AudioRepeatPreferences.customInteger(lastText)
            guard let surah, let from, let to,
                  let start = Quran.verseID(surah: surah, ayah: from),
                  let end = Quran.verseID(surah: surah, ayah: to) else {
                throw PassageAudioError(message: "Indique une sourate et des versets existants.")
            }
            // `audioRange(start,end)` — qui refuse une plage inversée.
            return try PassageAudio.range(start: start, end: end)
        }
    }

    /// `:232` — `chooseRange` : la plage choisie devient la plage affichée, et
    /// les champs reprennent ses bornes.
    private func choose(_ range: VerseRange) {
        let first = Quran.verseAt(range.start)
        let last = Quran.verseAt(range.end)
        selectedRange = range
        chosenID = range.start
        surahText = String(first.surah)
        firstText = String(first.ayah)
        lastText = last.surah == first.surah ? String(last.ayah) : String(first.ayah)
    }

    /// La page lue, ou la séance quand la page n'est pas résolue.
    private var currentPageRange: VerseRange {
        Quran.pageRange(page) ?? sessionRange
    }

    // MARK: - Le lancement

    /// `:175-179` — `begin()` : la plage est résolue **avant** le refus du
    /// compte, et le message est celui de l'échec rencontré. `AppViewModel`
    /// porte cet ordre ; l'écran ne fait que l'afficher.
    private func launch() {
        do {
            error = try model.launchAudioPassage(selectionRange())
        } catch let failure as PassageAudioError {
            error = failure.message
        } catch {
            // Un `catch` sans motif lie l'erreur à un `error` **implicite**, qui
            // masquerait le réglage : d'où `self.error`. C'est le seul endroit du
            // fichier où la distinction compte.
            self.error = "Passage invalide."
        }
    }

    // MARK: - Les libellés du pas à pas

    /// `String(Math.max(1,Number(value)-1))` et
    /// `String(Math.min(selectedSurah?.count??1,Number(value)+1))` de `:236`.
    ///
    /// `jsNumber` rend `nil` là où JavaScript rend `NaN` — et `String(NaN)` vaut
    /// « NaN ». Le pavé numérique ne produit pas ce cas, mais un collage le peut :
    /// on reproduit « NaN » plutôt que d'inventer autre chose.
    private func stepped(_ text: String, by delta: Double) -> String {
        guard let value = AudioRepeatPreferences.jsNumber(text), value.isFinite else { return "NaN" }
        // `selectedSurah?.count ?? 1` : une sourate hors bornes ne donne pas de
        // borne haute, donc **1** — et non un plantage.
        let upper: Double
        if let surah = AudioRepeatPreferences.customInteger(surahText),
           (1...Quran.surahs.count).contains(surah) {
            upper = Double(Quran.surahs[surah - 1].count)
        } else {
            upper = 1
        }
        return Self.plain(delta < 0 ? max(1, value - 1) : min(upper, value + 1))
    }

    /// `String(number)` de JavaScript : un entier s'écrit sans `.0`.
    private static func plain(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }

    /// `String(value).replace('.',',')+'×'` — `:268`.
    private static func speedLabel(_ value: Double) -> String {
        plain(value).replacingOccurrences(of: ".", with: ",") + "×"
    }
}

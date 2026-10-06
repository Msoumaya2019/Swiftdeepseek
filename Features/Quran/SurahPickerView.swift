// SurahPickerView.swift
// Le sélecteur de sourate — une feuille modale posée sur le lecteur.
// Port de `src/SurahPicker.tsx` (18 lignes) et de son montage (`src/App.tsx:517`).
//
// CE QUE CET ÉCRAN EST, ET CE QU'IL N'EST PAS
//   Ce n'est **pas** l'onglet Coran. `SurahListView` occupe l'onglet ; celui-ci
//   est une **feuille** qui s'ouvre depuis le lecteur, par le panneau d'options
//   de séance (`onSurah` → `setSurahPicker(true)`, `App.tsx:514`). L'original le
//   dit par sa forme : `Modal presentationStyle="pageSheet"`, pas un écran de
//   pile.
//
// LES QUATRE GESTES DE LA FERMETURE, ET LE CINQUIÈME QUI N'Y EST PAS
//   `onClose` (`App.tsx:517`) fait **deux** choses : fermer le sélecteur, puis
//   `setSessionPanel('options')`. Le panneau s'était fermé en l'ouvrant
//   (`onSurah` commence par `setSessionPanel(null)`), donc le retour le
//   rouvre — on revient **d'où l'on vient**, pas à la page.
//
//   `onSelect`, lui, en fait **cinq** : arrêter l'audio (`stopActiveAudio`),
//   oublier le verset joué (`setPlayingVerseId(null)`), oublier la commande
//   (`setAudioCommand(null)`), oublier le verset sélectionné
//   (`setSelectedVerse(null)`), puis fermer le panneau **et** le sélecteur.
//   Les quatre premiers sont la raison d'être de la fonction : changer de
//   sourate pendant qu'un verset joue laisserait l'audio du verset PRÉCÉDENT
//   continuer sur la nouvelle page. L'ordre importe peu en JavaScript ; ce qui
//   compte est qu'aucun des cinq ne soit omis.
//
// L'ÉCRAN NE CALCULE RIEN
//   La validité de la page, l'indice de départ, l'existence de la ligne de
//   saut et l'état initial du champ vivent dans `Core/SurahPickerOptions.swift`.

import SwiftUI

struct SurahPickerView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    /// La sourate courante, **1-basée** — `currentSurah={currentSurah.number}`.
    let currentSurah: Int
    /// La page courante, **optionnelle** — `currentPage={page}`.
    let currentPage: Int?
    /// Fourni ⇒ la ligne de saut existe. `nil` ⇒ elle n'existe pas.
    let onPage: ((Int) -> Void)?
    let onClose: () -> Void
    let onSelect: (Surah) -> Void

    /// `useState(String(currentPage ?? 1))` (`:9`).
    @State private var pageText: String
    /// L'alerte de `goPage` — `Alert.alert('Page invalide', …)`.
    @State private var showInvalidPage = false

    private let surahs = Quran.surahs

    init(
        currentSurah: Int,
        currentPage: Int?,
        onPage: ((Int) -> Void)?,
        onClose: @escaping () -> Void,
        onSelect: @escaping (Surah) -> Void
    ) {
        self.currentSurah = currentSurah
        self.currentPage = currentPage
        self.onPage = onPage
        self.onClose = onClose
        self.onSelect = onSelect
        self._pageText = State(
            initialValue: SurahPickerOptions.initialPageText(currentPage: currentPage)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete

            // `{visible && <FlatList …/>}` — la liste n'existe que lorsque la
            // feuille est visible. En SwiftUI une feuille **n'est pas montée**
            // tant qu'elle n'est pas présentée : la condition est donc portée
            // par l'appelant, et non ici. Voir `ReaderView`, où le `sheet` ne
            // se présente que si le drapeau est vrai.
            liste
        }
        .background(model.palette.cream)
        // `Alert.alert('Page invalide', 'Choisis une page entre 1 et 604.')`.
        .alert(
            SurahPickerOptions.invalidPageTitle,
            isPresented: $showInvalidPage
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(SurahPickerOptions.invalidPageMessage)
        }
    }

    // MARK: L'en-tête — `padding:18`

    private var entete: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                onClose()
            } label: {
                Text(SurahPickerOptions.closeTitle)
                    .font(.system(size: Theme.Typography.body, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        model.palette.soft,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                    )
            }
            .buttonStyle(.plain)

            Text(SurahPickerOptions.title)
                .font(.system(size: Theme.Typography.header, weight: .bold))
                .foregroundStyle(model.palette.text)

            Text(SurahPickerOptions.subtitle)
                .font(.system(size: Theme.Typography.metadata))
                .foregroundStyle(model.palette.muted)

            // `{onPage && <View …>}` — la ligne n'existe que si l'appelant sait
            // naviguer. Recopiée telle quelle : un appelant sans `onPage` ne
            // voit ni le champ ni le bouton.
            if SurahPickerOptions.showsPageJump(hasOnPage: onPage != nil) {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField(
                        SurahPickerOptions.pageFieldPlaceholder,
                        text: $pageText
                    )
                    .keyboardType(.numberPad)
                    .font(.system(size: Theme.Typography.body))
                    .padding(Theme.Spacing.sm)
                    .background(
                        model.palette.soft,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                    )

                    Button {
                        goPage()
                    } label: {
                        Text(SurahPickerOptions.pageSubmitTitle)
                            .font(.system(size: Theme.Typography.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                model.palette.green,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
            }
        }
        .padding(18)
    }

    /// `const goPage=()=>{…}` (`:11`) — la règle est dans `SurahPickerOptions`.
    private func goPage() {
        switch SurahPickerOptions.page(from: pageText) {
        case .go(let page):
            onPage?(page)
        case .refused:
            showInvalidPage = true
        }
    }

    // MARK: La liste — `FlatList` sur les 114 sourates

    private var liste: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(surahs, id: \.number) { surah in
                        ligne(surah)
                    }
                }
            }
            .onAppear {
                // `initialScrollIndex={Math.max(0, currentSurah-1)}` (`:15`).
                // Sur `FlatList` l'index de départ fait partie de la mise en
                // page (`getItemLayout`, `length:64`) : la liste s'ouvre
                // **déjà** sur la ligne. `ScrollViewReader` l'obtient par un
                // défilement initial, sans animation — c'est le même résultat
                // observable, la ligne courante sous les yeux à l'ouverture.
                let index = SurahPickerOptions.initialScrollIndex(
                    currentSurah: currentSurah
                )
                guard index < surahs.count else { return }
                proxy.scrollTo(surahs[index].number, anchor: .top)
            }
        }
    }

    /// Une ligne de 64 points — `style={{height:64,…}}` (`:15`).
    private func ligne(_ surah: Surah) -> some View {
        let selectionnee = surah.number == currentSurah
        return Button {
            onSelect(surah)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Text(String(surah.number))
                    .font(.system(size: Theme.Typography.body, weight: .bold))
                    .foregroundStyle(model.palette.green)
                    .frame(width: 30, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    Text(surah.name)
                        .font(.system(size: Theme.Typography.body, weight: .bold))
                        .foregroundStyle(model.palette.text)
                        .lineLimit(1)

                    Text(SurahPickerOptions.verseCountLabel(surah.count))
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                }

                Spacer(minLength: 0)

                if let arabic = surah.arabic, !arabic.isEmpty {
                    Text(arabic)
                        .font(.system(size: 23))
                        .foregroundStyle(model.palette.green)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .frame(height: 64)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectionnee ? model.palette.selected : model.palette.paper
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(model.palette.line)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // `accessibilityRole="button"`, `accessibilityLabel=« n. Nom »`,
        // `accessibilityState={{selected:…}}`.
        .accessibilityLabel(
            SurahPickerOptions.accessibilityLabel(number: surah.number, name: surah.name)
        )
        .accessibilityAddTraits(selectionnee ? [.isButton, .isSelected] : .isButton)
        .id(surah.number)
    }
}

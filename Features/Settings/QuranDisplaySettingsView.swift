// QuranDisplaySettingsView.swift
// Réglages — « Affichage du Coran » : les éditions, le fond, le suivi audio.
//
// Correspondance : la carte « Affichage du Coran » de `src/App.tsx:330`, dans la
// branche `mode==='settings'` de `ProfileScreen`.
//
// RÈGLE DE CE FICHIER : il ne calcule rien.
//   Les quatre éditions et leur ordre, les sous-titres, la décision d'un appui,
//   le texte du refus, les quatre fonds, leurs couleurs, la couleur du libellé,
//   les mesures du sélecteur et le libellé du suivi audio viennent tous de
//   `Core/QuranDisplayOptions.swift`. Il n'y a ici que de la mise en page.
//
// CE QUI EST APPLIQUÉ, ET CE QUI NE L'EST PAS ENCORE
//   L'ÉDITION est appliquée : choisir « Coran de Médine » change ce que le
//   lecteur ouvre, et le choix est écrit dans le document synchronisé.
//
//   Le FOND et le SUIVI AUDIO sont écrits et affichés, mais pas encore
//   appliqués — leurs seuls consommateurs dans l'original sont
//   `readerState.background` de l'édition rendue en WebView et
//   `followAudio(id)` (`App.tsx:445`), deux chaînes que ce portage n'a pas
//   encore. Les écrire est nécessaire : c'est ce qui fait que l'utilisateur
//   retrouve ses choix d'une application à l'autre. Le dire est nécessaire
//   aussi — un interrupteur qui ne change rien à l'écran ferait croire
//   l'application cassée.
//
// L'INSTALLATION DU CORAN 1441 N'EST PAS ICI
//   `DownloadSourceChoice` (`QuranDownload.tsx:8`) déplie son installateur
//   **dans** le sélecteur. Cet écran-ci est une feuille de réglages : elle
//   lance l'installation et le dit, et l'avancement reste visible dans l'onglet
//   Coran, où l'installateur vit depuis le début. Divergence assumée.

import SwiftUI

struct QuranDisplaySettingsView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle(QuranDisplayOptions.cardTitle)

                    Text(QuranDisplayOptions.cardDetail)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(palette.muted)
                        .padding(.bottom, Theme.Spacing.md)

                    card {
                        QuranEditionChooser(
                            stored: model.state.reader?.mushaf,
                            coran1441Installed: model.coran1441.isInstalled,
                            onSelect: { model.setEdition($0) },
                            onInstall: { _ in
                                model.coran1441.start()
                                model.notice = """
                                    Installation du Coran 1441 lancée. Son avancement \
                                    s'affiche dans l'onglet Coran.
                                    """
                            },
                            onUnavailable: { model.notice = QuranDisplayOptions.unavailableNotice(for: $0) }
                        )
                    }

                    sectionTitle(QuranDisplayOptions.paperSectionTitle)
                        .padding(.top, Theme.Spacing.xl)

                    paperGrid

                    followAudioRow
                        .padding(.top, Theme.Spacing.lg)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(palette.cream)
            .navigationTitle(QuranDisplayOptions.cardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    // MARK: - Le fond du Coran

    /// Deux fonds par ligne — le résultat que `width: '47%'` et `flexWrap`
    /// produisent dans l'original.
    private var paperGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.sm),
                GridItem(.flexible(), spacing: Theme.Spacing.sm)
            ],
            spacing: Theme.Spacing.sm
        ) {
            ForEach(QuranDisplayOptions.paperOptions) { option in
                paperSwatch(option)
            }
        }
    }

    private func paperSwatch(_ option: QuranDisplayOptions.PaperOption) -> some View {
        let selected = QuranDisplayOptions.selectedPaper(stored: model.state.reader?.paper) == option.id

        return Button {
            model.setPaper(option.id)
        } label: {
            // `{option.label} {selected ? '✓' : ''}` — le séparateur est une
            // espace, y compris quand la coche est absente.
            Text("\(option.label) \(selected ? QuranDisplayOptions.Paper.checkmark : "")")
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                // La couleur du libellé est écrite en clair dans l'original et
                // n'est PAS celle de la palette : les quatre fonds sont clairs,
                // donc le libellé doit rester sombre quel que soit le thème.
                .foregroundStyle(QuranDisplayOptions.paperLabelColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(QuranDisplayOptions.Paper.padding)
                .frame(minHeight: QuranDisplayOptions.Paper.minHeight)
                .background(
                    option.color,
                    in: RoundedRectangle(cornerRadius: QuranDisplayOptions.Paper.cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: QuranDisplayOptions.Paper.cornerRadius)
                        .strokeBorder(
                            selected ? palette.green : palette.line,
                            lineWidth: selected
                                ? QuranDisplayOptions.Paper.selectedBorderWidth
                                : QuranDisplayOptions.Paper.borderWidth
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fond \(option.label)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Le suivi audio

    /// `state.reader?.followAudio !== false` — le défaut est **vrai**, et un
    /// `false` stocké reste `false`. Le calcul est fait par le modèle.
    private var followAudioRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(QuranDisplayOptions.followAudioLabel)
                .font(.system(size: Theme.Typography.body))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.sm)
            Toggle(
                "",
                isOn: Binding(
                    get: { model.state.reader?.followAudio ?? true },
                    set: { model.setFollowAudio($0) }
                )
            )
            .labelsHidden()
            .tint(palette.green)
            .accessibilityLabel(QuranDisplayOptions.followAudioLabel)
        }
    }

    // MARK: - Mise en page

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.Typography.section, weight: .semibold))
            .foregroundStyle(palette.green)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Spacing.md)
            .background(
                palette.paper,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(palette.line, lineWidth: 1)
            )
    }
}

// AppearanceView.swift
// Apparence — le thème de l'application et la couleur d'accent.
//
// Correspondance : `src/ui/AppearanceScreen.tsx`, atteint par la carte
// « Apparence » de `src/App.tsx:329`.
//
// RÈGLE DE CE FICHIER : il ne calcule rien.
//   L'ordre des thèmes, la règle qui ouvre la bascule des thèmes
//   supplémentaires, l'ordre des accents, la pastille de chaque accent et
//   l'accent coché viennent tous de `Core/AppearanceOptions.swift`. Ici il n'y a
//   que de la mise en page — pas une liste, pas un ordre, pas un code couleur.
//   C'est la même règle que `SettingsView.swift`, pour la même raison : un écran
//   qui ne décide rien n'a rien à se tromper.
//
// CE QUI N'EST PAS ENCORE LÀ
//   L'original porte une troisième section, « Police de l'interface », avec
//   trois choix — élégante, moderne, classique (`AppearanceScreen.tsx:6`). Elle
//   n'est pas portée, et c'est délibéré : le choix ÉCRIT bien `state.uiFont`,
//   mais rien ici ne le lit. `src/theme/fonts.ts` branche `titleFont()` sur
//   « Cormorant-Semibold » et `interfaceFont()` sur « Cormorant-Regular », deux
//   polices livrées par `@expo-google-fonts` et absentes de ce dépôt. Afficher
//   trois choix dont aucun ne change quoi que ce soit à l'écran serait un
//   mensonge : l'utilisateur croirait l'application cassée. Cette section
//   viendra avec les polices — 197 appels `.font(.system(` répartis sur treize
//   fichiers, plus les fichiers de police à embarquer.
//
//   L'illustration des cartes de thème manque également. L'original affiche,
//   pour chaque thème, une image (`themeArt`, cinq PNG de `assets/themes/`,
//   10 199 065 octets au total). Ces cinq images servent AUSSI l'en-tête de
//   l'accueil (`IslamicHero`, `src/ui/Premium.tsx:13`) : elles seront portées
//   une seule fois, avec le bloc des ressources. En attendant, la carte affiche
//   le nom et la description — et rien d'inventé à la place de l'image.

import SwiftUI

struct AppearanceView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// `nil` tant que l'utilisateur n'a pas touché à la bascule.
    ///
    /// L'original fait `useState(theme === 'lilac' || theme === 'night')` : la
    /// valeur est calculée **au montage**, à partir du thème stocké. Un simple
    /// `false` initial cacherait sa propre carte à un utilisateur du thème
    /// « Lilas & Perle ». On garde donc l'absence de choix distincte du choix,
    /// et c'est le modèle qui dit ce que vaut l'absence.
    @State private var extrasChoice: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("Thème de l’application")
                    themeList

                    sectionTitle("Couleur d’accent")
                        .padding(.top, Theme.Spacing.xl)
                    accentList
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(palette.cream)
            .navigationTitle("Apparence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    // MARK: - Textes dérivés

    /// Le thème stocké, ou « white » — `state.theme ?? 'white'`.
    ///
    /// `Core/AppearanceOptions.swift` replie déjà sur « white » pour le nom et
    /// pour l'accent ; ici c'est la carte à cocher qu'il faut désigner, et la
    /// valeur de repli doit être la même des deux côtés.
    private var storedTheme: String { model.state.theme ?? "white" }

    /// L'état de la bascule : le choix de l'utilisateur s'il en a fait un,
    /// sinon ce que dit le modèle pour ce thème.
    private var showingExtras: Bool {
        extrasChoice ?? AppearanceOptions.extrasShownByDefault(for: storedTheme)
    }

    // MARK: - Les thèmes

    private var themeList: some View {
        VStack(spacing: 0) {
            ForEach(AppearanceOptions.themes(showingExtras: showingExtras)) { option in
                themeCard(option, selected: option.id == storedTheme)
                    .padding(.bottom, Theme.Spacing.md)
            }

            Button {
                extrasChoice = !showingExtras
            } label: {
                Text(AppearanceOptions.extrasToggleLabel(showingExtras: showingExtras))
                    .font(.system(size: Theme.Typography.secondary, weight: .semibold))
                    .foregroundStyle(palette.green)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        palette.soft,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    /// Une carte de thème : le nom, la description, et la marque de sélection.
    private func themeCard(_ option: Theme.ThemeOption, selected: Bool) -> some View {
        Button {
            model.setTheme(option.id)
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(option.name)
                        .font(.system(size: Theme.Typography.section, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.leading)
                    Text(option.description)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? palette.green : palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.sm)
            .background(palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(
                        selected ? palette.green : palette.line,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Les accents

    /// Les quatre pastilles. La couleur vient du modèle (`option.swatch`) : trois
    /// des quatre accents portent une pastille différente de leur couleur
    /// appliquée, et confondre les deux donnerait trois ronds faux.
    private var accentList: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(AppearanceOptions.accentOptions) { option in
                accentSwatch(
                    option,
                    selected: option.id == AppearanceOptions.displayedAccent(
                        stored: model.state.accent,
                        theme: model.state.theme
                    )
                )
            }
        }
    }

    private func accentSwatch(
        _ option: AppearanceOptions.AccentOption,
        selected: Bool
    ) -> some View {
        Button {
            model.setAccent(option.id)
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(option.swatch)
                    .frame(width: 48, height: 48)
                    .padding(3)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                selected ? palette.green : palette.line,
                                lineWidth: selected ? 2 : 1
                            )
                    )
                Text(option.label)
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(selected ? palette.green : palette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accent \(option.label)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Gabarit

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.Typography.header, weight: .semibold))
            .foregroundStyle(palette.green)
            .padding(.bottom, Theme.Spacing.lg)
    }
}

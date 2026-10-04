// SettingsView.swift
// Réglages — l'écran qui permet de modifier son programme et ses connaissances.
//
// Correspondance : `ProfileScreen` de `src/App.tsx:294`. L'application actuelle
// n'a qu'un seul écran pour le profil et les réglages ; les deux cartes qui nous
// intéressent ici sont dans la branche `mode==='profile'`, atteinte par le même
// bouton « Réglages » de la barre de titre :
//
//     « Connaissances »       → openKnowledge → assistant, étape 0   (App.tsx:325)
//     « Objectif et rythme »  → openGoal      → GoalScreen            (App.tsx:326)
//
// RÈGLE DE CE FICHIER : il ne calcule rien.
//   Le libellé de l'objectif vient de `state.goal.label`, celui du rythme de
//   `Pace.label`, les sous-titres et les textes de confirmation de `Program`.
//   Aucune liste, aucun libellé, aucun nombre n'est écrit ici — exactement
//   comme `Features/Quran/AudioRepeatSettingsView.swift`, pour la même raison :
//   un écran qui ne décide rien n'a rien à se tromper, et les deux applications
//   affichent la même chose à état égal.
//
// CE QUI N'EST PAS ENCORE LÀ
//   L'application actuelle répartit ses réglages sur deux pages — « Profil »
//   (prénom, compte, récitations, connaissances, objectif) et « Réglages »
//   (apparence, affichage du Coran, notifications, remise à zéro, sources).
//   Cet écran porte les connaissances, l'objectif et le rythme, l'apparence, et
//   la remise à zéro de l'apprentissage. Restent l'affichage du Coran, les
//   notifications, les sources et le compte : ils viendront avec leurs écrans
//   respectifs. Il n'y a pas de bouton mort ici — chaque ligne ouvre quelque
//   chose qui existe.

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showKnowledge = false
    @State private var showProgram = false
    @State private var showAppearance = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    settingsRow(
                        title: "Connaissances",
                        detail: "Modifier les sourates, juz’, hizb et passages déjà appris.",
                        action: "Modifier mes connaissances",
                        symbol: "checkmark.seal"
                    ) { showKnowledge = true }
                }

                Section {
                    settingsRow(
                        title: "Objectif et rythme",
                        detail: "\(model.state.goal.label) · \(paceLabel)",
                        action: "Modifier mon programme",
                        symbol: "target"
                    ) { showProgram = true }
                }

                Section {
                    settingsRow(
                        title: "Apparence",
                        detail: AppearanceOptions.cardDetail(for: model.state.theme),
                        action: "Choisir mon apparence",
                        symbol: "paintpalette"
                    ) { showAppearance = true }
                }

                Section("Tout remettre à 0") {
                    Text(Program.resetProgressDetail)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Réinitialiser apprentissage et révisions") {
                        confirmReset = true
                    }
                    .font(.system(size: Theme.Typography.body))
                    .foregroundStyle(palette.red)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
            .sheet(isPresented: $showKnowledge) { KnowledgeEditorView() }
            .sheet(isPresented: $showProgram) { ProgramEditorView(state: model.state) }
            .sheet(isPresented: $showAppearance) { AppearanceView() }
            .confirmationDialog(
                Program.resetProgressTitle,
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Tout remettre à zéro", role: .destructive) { model.resetProgress() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text(Program.resetProgressPrompt)
            }
        }
    }

    // MARK: - Textes dérivés

    /// `Pace(rawValue:)?.label ?? state.pace` — l'idiome déjà employé par
    /// `ProgramView.swift:82` et `ProgressScreenView.swift:362`.
    ///
    /// Le repli sur la valeur stockée n'est pas un luxe : une application plus
    /// ancienne peut avoir écrit un rythme que cette version ne connaît pas
    /// (`toumoun`, par exemple, reste indisponible tant que ses limites ne sont
    /// pas vérifiées). Afficher la chaîne brute est plus honnête que d'afficher
    /// un libellé faux.
    private var paceLabel: String {
        Pace(rawValue: model.state.pace)?.label ?? model.state.pace
    }

    // MARK: - Gabarit d'une carte

    /// Un titre, une explication, et le bouton qui ouvre l'écran correspondant.
    /// Les trois textes viennent de l'appelant, qui les tient lui-même du modèle.
    private func settingsRow(
        title: String,
        detail: String,
        action: String,
        symbol: String,
        onPress: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.green)
                Text(title)
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            Text(detail)
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onPress) {
                Text(action)
                    .font(.system(size: Theme.Typography.body, weight: .semibold))
                    .foregroundStyle(palette.green)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        palette.soft,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

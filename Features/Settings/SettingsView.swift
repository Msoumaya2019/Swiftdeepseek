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
// LA RÉPARTITION EST DÉSORMAIS CELLE DE L'ORIGINAL
//   L'application actuelle a deux pages — « Profil » (prénom, compte,
//   récitations, connaissances, objectif, apprentissage, amis) et « Réglages »
//   (apparence, affichage du Coran, notifications, remise à zéro, sources).
//   Cet écran portait les connaissances et l'objectif à titre provisoire ;
//   `Features/Profile/ProfileView.swift` existe maintenant et les a repris,
//   parce que l'original ne les met **que** là : le relevé des occurrences de
//   « Connaissances », « Modifier mes connaissances » et « Modifier mon
//   programme » dans `src/` ne rend que `src/App.tsx:325-326`. Il ne reste ici
//   que ce que la page « Réglages » de l'original porte, et il n'y a pas de
//   bouton mort : chaque ligne ouvre quelque chose qui existe.

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showAppearance = false
    @State private var showQuranDisplay = false
    @State private var showNotifications = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    settingsRow(
                        title: "Apparence",
                        detail: AppearanceOptions.cardDetail(for: model.state.theme),
                        action: "Choisir mon apparence",
                        symbol: "paintpalette"
                    ) { showAppearance = true }
                }

                Section {
                    settingsRow(
                        title: QuranDisplayOptions.cardTitle,
                        detail: QuranDisplayOptions.cardDetail,
                        action: "Choisir l'affichage du Coran",
                        symbol: "book"
                    ) { showQuranDisplay = true }
                }

                Section {
                    settingsRow(
                        title: NotificationOptions.cardTitle,
                        detail: NotificationOptions.cardDetail(model.state),
                        action: "Choisir mes notifications",
                        symbol: "bell"
                    ) { showNotifications = true }
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

                Section {
                    sourcesCard
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
            .sheet(isPresented: $showAppearance) { AppearanceView() }
            .sheet(isPresented: $showQuranDisplay) { QuranDisplaySettingsView() }
            .sheet(isPresented: $showNotifications) { NotificationSettingsView() }
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

    // MARK: - La carte des sources

    /// La dernière carte de la page « Réglages » de l'original (`App.tsx:350`).
    ///
    /// Elle n'ouvre **aucun** écran : c'est un texte d'attribution, avec un seul
    /// lien sortant. C'est pourquoi elle n'emprunte pas le gabarit
    /// `settingsRow` ci-dessous — ce gabarit porte un bouton, et il n'y en a pas
    /// ici. Elle est rendue en clair, dans l'ordre exact de l'original : le
    /// titre, le premier paragraphe, le lien, le second paragraphe.
    ///
    /// Le titre est volontairement plus discret que celui des autres cartes
    /// (`Theme.Typography.body` en `semibold`, couleur `muted`) : l'original
    /// l'écrit `fontSize:14, fontWeight:'600'` et `muted`, là où les réglages
    /// portent `fontWeight:'700'` et la couleur de texte. La carte est une note
    /// de bas de page, et l'afficher comme un réglage serait une décision que
    /// l'original n'a pas prise.
    ///
    /// Le lien prend `palette.green2` et non `palette.green` : c'est la couleur
    /// `colors.green2` de l'original, qui diffère de `green` sur deux thèmes
    /// (rose, violet) — voir `Theme.swift`. Les autres liens de ce dossier
    /// emploient `green`, et ce n'est pas une incohérence : ils portent des
    /// boutons, alors que celui-ci porte un lien.
    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(QuranSourcesCard.title)
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                .foregroundStyle(palette.muted)
            Text(QuranSourcesCard.textAttribution)
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: QuranSourcesCard.linkURL) {
                Text(QuranSourcesCard.linkTitle)
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(palette.green2)
                    .underline()
            }
            Text(QuranSourcesCard.editionAttribution)
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Spacing.xs)
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
            // La recette du bouton vit désormais dans `CardButton`
            // (`Features/Shared/Components.swift`) : elle était écrite ici, et
            // l'écran du profil en avait besoin à l'identique. Deux copies
            // auraient divergé au premier ajustement.
            CardButton(title: action, action: onPress)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

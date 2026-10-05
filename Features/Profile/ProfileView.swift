// ProfileView.swift
// Profil — le prénom et le compte.
//
// Correspondance : la branche `mode==='profile'` de `ProfileScreen`
// (`src/App.tsx:294`), pour les deux seuls blocs dont le modèle est porté :
// « Mon prénom » et « Compte et synchronisation », tous deux dans la **même**
// carte de l'original (`App.tsx:322`).
//
// OÙ VIT CETTE PAGE
//   L'original l'ouvre depuis le bouton de profil de sa barre de titre
//   (`onProfile`, `App.tsx:236`), à côté de l'engrenage des réglages. Ce portage
//   fait de même : `Features/Home/HomeView.swift` porte les deux boutons, et les
//   deux pages sont des feuilles — `ProfileView` comme `SettingsView`.
//
// LA LIGNE, ICI
//   Les textes des blocs viennent tous de `ProfileOptions`, jamais d'ici : ce
//   sont eux que l'application React Native affiche, et deux copies
//   divergeraient. Ce fichier n'écrit que sa propre « chrome » — le titre de la
//   feuille, sa ligne de sous-titre, et le libellé d'accessibilité de son
//   bouton — exactement comme `SettingsView` écrit les siens. Aucun nombre,
//   aucune borne, aucune comparaison ne vit ici.
//
// CE QUI N'EST PAS ENCORE LÀ
//   1. LA PHOTO. La rangée d'avatar et ses deux boutons (« Choisir ou modifier
//      ma photo », « Ajouter une photo (facultatif) », « Supprimer ma photo »)
//      ne sont **pas** montés : l'envoi et le retrait demandent le bucket
//      `friend-avatars` et une écriture sur `friend_profiles.avatar_path`, donc
//      une vérification serveur que cette version ne fait pas. Les textes, les
//      bornes et l'emplacement de l'objet sont portés par `ProfileOptions`.
//      Même discipline que le bouton « Vérifier le jeton push » de §9.23 : on
//      ne monte pas un bouton qui ne peut rien faire.
//   2. LA BRANCHE DÉCONNECTÉE. L'original affiche, quand `account` est nul, un
//      formulaire d'adresse et de mot de passe et quatre boutons. Il n'est pas
//      monté ici : `App/ContentView.swift` montre `SignInView` **avant** toute
//      page — c'est la porte de ce portage, et elle applique déjà les règles du
//      modèle (`ProfileOptions.canSignIn`). Monter un second formulaire
//      donnerait deux portes pour un même contrat, et la seconde serait
//      inatteignable.
//   3. « Mes récitations », « Connaissances », « Objectif et rythme »,
//      « Apprentissage », « Amis et entraide ». Les trois du milieu vivent déjà
//      dans `SettingsView` ; les deux autres attendent leur fonctionnalité.

import SwiftUI

struct ProfileView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// La saisie du prénom — un état **local**.
    ///
    /// L'original garde la même variable et la resynchronise quand le prénom
    /// enregistré change (`App.tsx:308`, `useEffect(...,[state.profile?.firstName])`).
    /// Rien n'est écrit avant le bouton : c'est ce qui permet d'abandonner une
    /// saisie en fermant la feuille.
    @State private var firstName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Tes préférences et tes données")
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(palette.muted)
                        .padding(.top, Theme.Spacing.sm)
                    profileCard
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(palette.cream)
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
            .onAppear { firstName = model.state.profile?.firstName ?? "" }
            .onChange(of: model.state.profile?.firstName) { value in
                firstName = value ?? ""
            }
        }
    }

    // MARK: - La carte

    /// La carte de l'original — une seule, deux blocs (`App.tsx:322`).
    ///
    /// Le second bloc n'est pas un second `Card` : l'original les met dans la
    /// même boîte, séparés par un `marginTop:16` sur le titre du second. Deux
    /// cartes changeraient le découpage de la page.
    private var profileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                firstNameBlock
                accountBlock
            }
        }
    }

    /// « Mon prénom » — `App.tsx:322`.
    ///
    /// Le champ ne porte **pas** `autocorrectionDisabled()` : le `Field` de
    /// l'original ne règle que `autoCapitalize` (`src/ui/theme.tsx:32`), et
    /// `words` est exactement ce qu'il demande pour un prénom. Éteindre la
    /// correction ici serait une décision que l'original n'a pas prise.
    private var firstNameBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(ProfileOptions.firstNameTitle)
                .font(.system(size: Theme.Typography.card, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(ProfileOptions.firstNameHint)
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField(ProfileOptions.firstNamePlaceholder, text: $firstName)
                .textInputAutocapitalization(.words)
                .font(.system(size: Theme.Typography.body))
                .foregroundStyle(palette.text)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .stroke(palette.line, lineWidth: 1)
                )
            CardButton(title: ProfileOptions.firstNameSaveAction) {
                model.saveFirstName(firstName)
            }
        }
    }

    /// « Compte et synchronisation » — `App.tsx:322`.
    ///
    /// C'est la branche **connectée** de l'original. Les deux autres — service
    /// non configuré, et formulaire de connexion — ne sont pas montées ; voir
    /// l'en-tête.
    private var accountBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(ProfileOptions.accountTitle)
                .font(.system(size: Theme.Typography.card, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(accountLabel)
                .font(.system(size: Theme.Typography.body))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            CardButton(title: ProfileOptions.syncNowAction) {
                Task { await model.syncNow() }
            }
            CardButton(title: ProfileOptions.signOutAction) {
                Task { await model.signOut() }
            }
        }
    }

    // MARK: - Textes dérivés

    /// L'identifiant affiché du compte — `account`, `App.tsx:322`.
    ///
    /// `user.email ?? user.id` : une session restaurée depuis le trousseau peut
    /// ne pas porter d'adresse, et l'original montre alors l'identifiant plutôt
    /// que rien.
    private var accountLabel: String {
        model.auth.session?.email ?? model.auth.userId ?? ""
    }
}

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
//   3. « MES RÉCITATIONS » ET « AMIS ET ENTRAIDE ». La première attend son écran :
//      `openRecitations` ouvre un enregistreur et des corrections de professeur,
//      qui ne sont pas portés. La seconde attend une écriture serveur — ses trois
//      préférences de partage passent par `updateSocialProfile`
//      (`src/services/social.ts:24`), un `PATCH` sur `friend_profiles` que
//      `SupabaseRESTClient` ne sait pas encore faire.
//
// LES TROIS CARTES QUI SONT LÀ
//   « Connaissances » (`App.tsx:325`), « Objectif et rythme » (`App.tsx:326`) et
//   « Apprentissage » (`App.tsx:327`) ont, elles, leur destination et leur
//   modèle. Les deux premières n'existent **qu'ici** dans l'original : le relevé
//   des occurrences de « Connaissances », « Modifier mes connaissances » et
//   « Modifier mon programme » dans `src/` ne rend que ces deux lignes. Le
//   portage les avait placées dans `SettingsView` à titre provisoire — son
//   propre en-tête l'annonçait — et elles lui ont été retirées : deux chemins
//   pour une même carte seraient une divergence que l'original ne connaît pas.

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

    /// Les deux écrans qu'ouvrent les cartes — un état **local**, comme le
    /// `showKnowledge` / `showProgram` que `SettingsView` portait pour elles.
    @State private var showKnowledge = false
    @State private var showProgram = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Tes préférences et tes données")
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(palette.muted)
                        .padding(.top, Theme.Spacing.sm)
                    profileCard
                    knowledgeCard
                    goalCard
                    learningCard
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
            .sheet(isPresented: $showKnowledge) { KnowledgeEditorView() }
            .sheet(isPresented: $showProgram) { ProgramEditorView(state: model.state) }
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

    /// « Connaissances » — `App.tsx:325`.
    ///
    /// La destination est `KnowledgeEditorView`, qui porte l'étape 0 de
    /// l'assistant d'accueil (`src/App.tsx:399-402`) — exactement ce qu'ouvre
    /// `openKnowledge`, qui vaut `setWizard(0)`.
    private var knowledgeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(ProfileOptions.knowledgeTitle)
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(ProfileOptions.knowledgeDetail)
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                CardButton(title: ProfileOptions.knowledgeAction) { showKnowledge = true }
            }
        }
    }

    /// « Objectif et rythme » — `App.tsx:326`.
    ///
    /// La ligne du milieu n'est pas un texte fixe : elle porte l'objectif
    /// **courant** et le rythme **courant**, composés par le modèle
    /// (`ProfileOptions.goalAndPace`). La vue ne compose pas la chaîne, et ne
    /// choisit pas le libellé du rythme — c'est le quatrième appelant de
    /// `Pace.displayed`, celui qui a décidé de l'extraire.
    private var goalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(ProfileOptions.goalTitle)
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(ProfileOptions.goalAndPace(
                    goalLabel: model.state.goal.label,
                    pace: model.state.pace
                ))
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                CardButton(title: ProfileOptions.goalAction) { showProgram = true }
            }
        }
    }

    /// « Apprentissage » — `App.tsx:327`.
    ///
    /// Deux blocs dans **une** carte, et le second est conditionnel : l'original
    /// n'affiche la rangée des durées que si `reviewsEnabled(state)`. Éteindre
    /// l'espace Révisions fait donc disparaître la rangée, et la rallumer la
    /// ramène sur la durée déjà choisie — `setReviewsEnabled` ré-épingle
    /// `cycleDays`, il ne le remet pas à 7.
    private var learningCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(ProfileOptions.learningTitle)
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                    .foregroundStyle(palette.text)
                Toggle(isOn: reviewsBinding) {
                    Text(ProfileOptions.reviewsToggleLabel)
                        .font(.system(size: Theme.Typography.body))
                        .foregroundStyle(palette.text)
                }
                .tint(palette.green)
                if Review.reviewsEnabled(model.state) {
                    Text(ProfileOptions.reviewCycleHeading)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(palette.muted)
                        .padding(.top, Theme.Spacing.sm)
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(Review.cycleOptions, id: \.self) { days in
                            CycleChoice(
                                title: ProfileOptions.cycleLabel(days),
                                selected: Review.reviewCycleDays(model.state) == days
                            ) {
                                model.update { Review.setReviewCycle($0, cycleDays: days) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// L'interrupteur, écrit par le modèle — `App.tsx:327` :
    /// `onValueChange={value => update(setReviewsEnabled(state, value))}`.
    ///
    /// Le `set` passe par `model.update`, donc par `AppStateRepository.mutate`,
    /// qui applique le `touch` — voir `ProfileOptions.settingFirstName`.
    private var reviewsBinding: Binding<Bool> {
        Binding(
            get: { Review.reviewsEnabled(model.state) },
            set: { value in model.update { Review.setReviewsEnabled($0, enabled: value) } }
        )
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

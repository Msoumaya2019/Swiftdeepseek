// AuthGateView.swift
// La porte d'accueil — le tout premier écran, avant la navigation.
//
// Correspondance : `AccountWelcome` de `src/App.tsx:260-288`. C'est le seul
// écran de `Features/Auth/`, et il est monté par `App/ContentView.swift`.
//
// CE QUE CET ÉCRAN A DE PARTICULIER
//   Il **s'ouvre sur un choix**, pas sur un formulaire. `App.tsx:260` initialise
//   `mode` à `null`, et le JSX rend trois boutons tant que le mode est nul :
//
//     - « Se connecter »        → mode « login »
//     - « Créer mon compte »    → mode « signup »
//     - « Réessayer la restauration de ma session » → relance `restore()`
//
//   Le troisième est celui qu'un portage « propre » perdrait : il rend
//   atteignable la restauration d'une session que le lancement aurait manquée
//   (serveur momentanément injoignable). Sans lui, une personne dont la session
//   existe mais n'a pas été restaurée n'a plus aucun recours que de se
//   reconnecter à la main.
//
// LES RÈGLES N'ONT PAS ÉTÉ RELUES ICI
//   Le bouton principal, les deux boutons conditionnels et le retour au choix
//   interrogent `AuthGateOptions` — qui porte les règles **de cette porte**,
//   distinctes de celles de la carte du profil. Cet écran ne décide rien :
//   même discipline que le reste de `Features/` (voir `SettingsView.swift`).

import SwiftUI

public struct AuthGateView: View {

    @EnvironmentObject private var model: AppViewModel

    /// `mode` est *nullable* : c'est le choix. L'écran s'ouvre dessus.
    @State private var mode: AuthGateOptions.Mode?
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                enTete
                if let mode {
                    formulaire(mode)
                } else {
                    choix
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.section)
            .frame(maxWidth: .infinity)
        }
        .background(model.palette.cream)
    }

    // MARK: En-tête

    /// `App.tsx:279` : le ۞, « Bienvenue », et la phrase d'accroche.
    /// L'en-tête ne change **pas** avec le mode : il appartient à la porte.
    private var enTete: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("۞")
                .font(.system(size: 36))
                .foregroundStyle(model.palette.green)
            Text("Bienvenue")
                .font(.system(size: Theme.Typography.screen, weight: .bold))
                .foregroundStyle(model.palette.green)
            Text("Crée ton compte pour retrouver ton apprentissage sur tous tes appareils.")
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(model.palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: Le choix

    private var choix: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { mode = .login } } label: {
                    Text("Se connecter")
                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.palette.green)

                Button { withAnimation(.easeInOut(duration: 0.2)) { mode = .signup } } label: {
                    Text("Créer mon compte")
                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)

                // Le troisième bouton : rendre atteignable une restauration que
                // le lancement a manquée. `App.tsx:280` — `onRetry`.
                Button {
                    Task { await model.auth.restore() }
                } label: {
                    Text("Réessayer la restauration de ma session")
                        .font(.system(size: Theme.Typography.secondary))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(model.palette.muted)
            }
        }
    }

    // MARK: Le formulaire

    private func formulaire(_ mode: AuthGateOptions.Mode) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(AuthGateOptions.title(for: mode))
                    .font(.system(size: Theme.Typography.header, weight: .bold))
                    .foregroundStyle(model.palette.text)

                Text("Adresse e-mail")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
                TextField("Adresse e-mail", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: Theme.Typography.body))
                    .padding(Theme.Spacing.sm)
                    .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

                // Le texte d'invite dit « au moins 6 caractères » dans les DEUX
                // modes, dans l'original (`App.tsx:283`). La borne, elle, n'est
                // appliquée qu'à l'inscription — l'invite et la règle ne disent
                // pas la même chose, et c'est l'original.
                Text("Mot de passe (au moins 6 caractères)")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
                SecureField("••••••••", text: $password)
                    .textContentType(mode == .signup ? .newPassword : .password)
                    .font(.system(size: Theme.Typography.body))
                    .padding(Theme.Spacing.sm)
                    .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

                Button {
                    Task { await soumettre(mode) }
                } label: {
                    HStack {
                        if isWorking { ProgressView().tint(model.palette.paper) }
                        Text(AuthGateOptions.submitTitle(for: mode, busy: isWorking))
                            .font(.system(size: Theme.Typography.body, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.palette.green)
                // La règle vient d'`AuthGateOptions.canSubmit` — celle de CETTE
                // porte : arobase exigée même en connexion, et six caractères
                // seulement en inscription.
                .disabled(
                    !AuthGateOptions.canSubmit(
                        busy: isWorking,
                        email: email,
                        password: password,
                        mode: mode
                    )
                )

                if let message {
                    Text(message)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(isError ? model.palette.red : model.palette.text)
                }

                // Les deux boutons secondaires sont **exclusifs l'un de l'autre**,
                // et leurs règles vivent dans `AuthGateOptions`.
                if AuthGateOptions.canRequestPasswordLink(busy: isWorking, email: email, mode: mode) {
                    Button("Mot de passe oublié") {
                        Task { await demanderLien() }
                    }
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.green)
                } else if mode == .signup, !email.isEmpty || message != nil {
                    // Le bouton peut être présent sans être armé : l'original le
                    // rend dès qu'un message existe, et le désarme sans arobase.
                    Button("Renvoyer la confirmation") {
                        Task { await renvoyerConfirmation() }
                    }
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.green)
                    .disabled(
                        !AuthGateOptions.canResendConfirmation(
                            busy: isWorking,
                            email: email,
                            mode: mode,
                            message: message
                        )
                    )
                }

                Button("Retour") {
                    // Rend au choix ET efface le message — les deux gestes de
                    // `App.tsx:288`. `AuthGateOptions.afterBack` les porte.
                    let retour = AuthGateOptions.afterBack(message: message)
                    withAnimation(.easeInOut(duration: 0.2)) { self.mode = retour.mode }
                    message = retour.message
                    isError = false
                }
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(model.palette.muted)
            }
        }
    }

    // MARK: Actions

    private func soumettre(_ mode: AuthGateOptions.Mode) async {
        isWorking = true
        message = nil
        isError = false
        let result = await model.authenticate(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            register: mode == .signup
        )
        isWorking = false
        if result.outcome == .failed {
            message = result.notice
            isError = true
        } else if mode == .signup, result.outcome == .confirmEmail {
            // L'inscription sans session n'est pas une erreur : le projet exige
            // la confirmation par courriel. Le message reste donc neutre, et le
            // bouton « Renvoyer la confirmation » devient atteignable.
            message = result.notice
            isError = false
        }
    }

    private func demanderLien() async {
        isError = false
        do {
            try await model.auth.requestPasswordReset(email: email)
            message = "Un lien de réinitialisation a été envoyé."
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func renvoyerConfirmation() async {
        isError = false
        do {
            try await model.auth.resendConfirmation(email: email)
            message = "Courriel de confirmation renvoyé."
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}

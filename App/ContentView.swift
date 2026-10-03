// ContentView.swift
// Racine de l'interface : porte d'authentification puis navigation principale.
//
// Correspondance : le rendu conditionnel d'`App.tsx` côté React Native, qui
// affiche l'écran de connexion tant que la session n'est pas restaurée.
//
// Comportement hors ligne : si une session est conservée dans le trousseau,
// l'application s'ouvre sans réseau. C'est `AuthService.restore()` qui le
// garantit — il ne consulte pas le serveur pour laisser entrer.

import SwiftUI

public struct ContentView: View {

    @EnvironmentObject private var model: AppViewModel

    public init() {}

    public var body: some View {
        AuthGate(auth: model.auth)
            .environmentObject(model)
            .environment(\.palette, model.palette)
    }
}

/// Observe directement `AuthService` : `AppViewModel` n'a pas à republier l'état
/// d'authentification, et la vue se rafraîchit dès que la session change.
private struct AuthGate: View {

    @ObservedObject var auth: AuthService
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Group {
            if let problem = AppConfig.configurationProblem {
                // Configuration incomplète : on l'explique plutôt que de
                // laisser l'application se fermer sans rien dire.
                ConfigurationView(problem: problem)
            } else {
                switch auth.state {
                case .checking:
                    SplashView()
                case .signedOut:
                    SignInView()
                case .signedIn:
                    MainTabView()
                }
            }
        }
        .background(model.palette.cream)
    }
}

// MARK: - Configuration incomplète

private struct ConfigurationView: View {

    @EnvironmentObject private var model: AppViewModel

    let problem: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Configuration à compléter")
                    .font(.system(size: Theme.Typography.header, weight: .bold))
                    .foregroundStyle(model.palette.green)
                    .padding(.top, Theme.Spacing.section)

                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(problem)
                            .font(.system(size: Theme.Typography.body))
                            .foregroundStyle(model.palette.text)
                        Text("Copie `Config/Secrets.xcconfig.example` en `Config/Secrets.xcconfig`, renseigne l'URL du projet Supabase et la clé publiable (jamais la clé service_role), puis relance la compilation.")
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .background(model.palette.cream)
    }
}

// MARK: - Écran de démarrage

private struct SplashView: View {

    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundStyle(model.palette.green)
            ProgressView()
                .tint(model.palette.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.palette.cream)
    }
}

// MARK: - Connexion

private struct SignInView: View {

    @EnvironmentObject private var model: AppViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Coran Mémoire")
                        .font(.system(size: Theme.Typography.screen, weight: .bold))
                        .foregroundStyle(model.palette.green)
                    Text("Connecte-toi avec ton compte habituel : tu retrouveras ta progression, tes révisions et tes amis.")
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.muted)
                }
                .padding(.top, Theme.Spacing.section)

                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Adresse e-mail")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        TextField("nom@exemple.fr", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: Theme.Typography.body))
                            .padding(Theme.Spacing.sm)
                            .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

                        Text("Mot de passe")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        SecureField("••••••••", text: $password)
                            .textContentType(.password)
                            .font(.system(size: Theme.Typography.body))
                            .padding(Theme.Spacing.sm)
                            .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

                        Button {
                            Task { await signIn() }
                        } label: {
                            HStack {
                                if isWorking { ProgressView().tint(model.palette.paper) }
                                Text(isWorking ? "Connexion…" : "Se connecter")
                                    .font(.system(size: Theme.Typography.body, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(model.palette.green)
                        .disabled(isWorking || email.isEmpty || password.isEmpty)

                        if let message {
                            Text(message)
                                .font(.system(size: Theme.Typography.secondary))
                                .foregroundStyle(isError ? model.palette.red : model.palette.muted)
                        }

                        Button("Mot de passe oublié ?") {
                            Task { await resetPassword() }
                        }
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.green)
                        .disabled(email.isEmpty)
                    }
                }

                Text("Cette application utilise le même compte que l'application existante. Si tu n'as pas encore de compte, crée-le depuis l'application d'origine : tu éviteras un doublon.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.section)
        }
        .background(model.palette.cream)
    }

    private func signIn() async {
        isWorking = true
        message = nil
        isError = false
        await model.signIn(email: email, password: password)
        isWorking = false
        if let notice = model.notice {
            message = notice
            isError = true
            model.notice = nil
        }
    }

    private func resetPassword() async {
        isError = false
        do {
            try await model.auth.requestPasswordReset(email: email)
            message = "Un lien de réinitialisation vient d'être envoyé à \(email)."
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}

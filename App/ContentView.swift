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
            // L'avis est monté **au-dessus de la porte**, et non dans
            // `MainTabView` : l'original le pose à la racine de son interface, et
            // c'est ce qui lui permet de survivre au changement de compte. Ici,
            // « Déconnecté. » s'affiche alors que `AuthGate` est déjà revenu à
            // `AuthGateView` ; monté dans les onglets, il disparaîtrait avec eux.
            .overlay(alignment: .bottom) {
                if let notice = model.notice, !notice.isEmpty {
                    NoticeToast(text: notice) { model.notice = nil }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.lg)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.notice)
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
                    // La porte vit dans `Features/Auth/AuthGateView.swift` : cet
                    // écran est un écran comme les autres, et sa place est dans
                    // son dossier. Il a été écrit ici à l'origine, ce qui laissait
                    // `Features/Auth/` vide tout en faisant croire que l'écran
                    // manquait.
                    AuthGateView()
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

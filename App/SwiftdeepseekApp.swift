// SwiftdeepseekApp.swift
// Point d'entrée de l'application.
//
// Correspondance : `App.tsx` côté React Native, qui tient le même rôle —
// restaurer la session, puis afficher soit l'écran de connexion, soit la
// navigation principale.

import SwiftUI

@main
public struct SwiftdeepseekApp: App {

    @StateObject private var model = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environment(\.palette, model.palette)
                // `swiftdeepseek://auth` — le schéma propre à cette application.
                // Celui de l'application React Native reste `coranmemoire://`.
                .onOpenURL { url in
                    // `handleAuthLink` est `throws` : une URL de retour
                    // malformée ne doit pas faire tomber l'application. On
                    // l'ignore, et la session reste simplement non connectée.
                    Task { try? await model.auth.handleAuthLink(url) }
                }
                .task { await model.start() }
        }
        // Forme à UN SEUL paramètre. La variante `{ _, phase in }` exige
        // iOS 17, alors que la cible de déploiement est iOS 16 (`project.yml`).
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await model.sync.refreshPendingCount()
                await model.sync.flush()
            }
        }
    }
}

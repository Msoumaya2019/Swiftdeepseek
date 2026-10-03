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
                    Task { await model.auth.handleAuthLink(url) }
                }
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.sync.refreshPendingCount()
                await model.sync.flush()
            }
        }
    }
}

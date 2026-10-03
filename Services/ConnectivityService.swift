// ConnectivityService.swift
// Suivi de l'état du réseau.
//
// Correspondance : `src/services/connectivity.ts` côté React Native. Même
// comportement : dès que la connexion revient après une coupure, on vide la file
// de synchronisation. Le bandeau « Mode hors connexion » et le message
// « Connexion rétablie » reprennent ceux de l'application existante.

import Foundation
import Network

@MainActor
public final class ConnectivityService: ObservableObject {

    @Published public private(set) var isOffline = false
    @Published public private(set) var justRestored = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "fr.swiftdeepseek.connectivity")
    private var wasOffline = false
    private var restoreTask: Task<Void, Never>?
    private var onRestore: (() async -> Void)?

    public init() {}

    public func start(onRestore: @escaping () async -> Void) {
        self.onRestore = onRestore
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                self?.update(offline: offline)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
        restoreTask?.cancel()
    }

    private func update(offline: Bool) {
        isOffline = offline
        if !offline, wasOffline {
            justRestored = true
            restoreTask?.cancel()
            restoreTask = Task { [weak self] in
                await self?.onRestore?()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                self?.justRestored = false
            }
        }
        wasOffline = offline
    }
}

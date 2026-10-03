// StateSyncService.swift
// Synchronisation du document d'état avec Supabase.
//
// Port de `src/services/sync.ts` (pullState / pushState) et de
// `src/services/offlineSync.ts` (flushPendingSync), y compris la fusion à trois
// voies. C'est ce mécanisme qui rend vraie la promesse :
//   séance faite dans React Native → visible ici ;
//   révision validée ici → visible dans React Native.

import Foundation

@MainActor
public final class StateSyncService: ObservableObject {

    @Published public private(set) var lastError: String?
    @Published public private(set) var isSyncing = false
    @Published public private(set) var pendingCount = 0

    private let client: SupabaseRESTClient
    private let auth: AuthService
    private let store: LocalStore
    private let repository: AppStateRepository

    public init(
        client: SupabaseRESTClient,
        auth: AuthService,
        store: LocalStore,
        repository: AppStateRepository
    ) {
        self.client = client
        self.auth = auth
        self.store = store
        self.repository = repository
    }

    // MARK: Lecture

    public func pull() async throws -> JSONValue? {
        guard let userId = auth.userId else { return nil }
        let token = try await auth.validAccessToken()
        return try await client.fetchUserState(userId: userId, accessToken: token)
    }

    /// Récupère l'état distant et le fait adopter par le dépôt.
    /// C'est l'appel qui fait « retrouver sa progression » après connexion.
    public func syncOnSignIn() async {
        guard let userId = auth.userId else { return }
        await repository.load(userId: userId)
        do {
            if let remote = try await pull() {
                await repository.applyRemote(remote)
                // Une fusion reste nécessaire si des modifications locales
                // attendaient : c'est le rôle de `flush`.
            }
            await flush()
        } catch {
            // Hors ligne : on continue avec l'état local. Aucune donnée n'est
            // perdue, la file sera vidée à la reconnexion.
            lastError = error.localizedDescription
        }
    }

    // MARK: Écriture

    /// Vide la file d'attente en fusionnant chaque instantané avec le serveur.
    /// Port de `flushPendingSync` — `src/services/offlineSync.ts:8`.
    public func flush() async {
        guard let userId = auth.userId, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let operations = await store.pendingOperations(for: userId)
        pendingCount = operations.count
        guard !operations.isEmpty else {
            lastError = nil
            return
        }

        do {
            let token = try await auth.validAccessToken()
            for operation in operations {
                // L'état local a pu changer de compte entre-temps.
                guard auth.userId == operation.userId else { throw CancellationError() }

                let remote = try await client.fetchUserState(userId: userId, accessToken: token)
                let merged = OfflineMerge.mergeOfflineState(
                    base: operation.base,
                    local: operation.payload,
                    remote: remote
                )
                guard let typed = AppState.decode(from: merged) else {
                    throw AppStateRepository.RepositoryError.unreadableDocument
                }
                try await client.upsertUserState(
                    userId: userId,
                    data: merged,
                    updatedAt: typed.updatedAt,
                    accessToken: token
                )
                try await store.acknowledge(operation.id)
                await repository.markSynced(merged)
            }
            lastError = nil
        } catch is CancellationError {
            // Compte changé : on ne pousse rien.
        } catch {
            // Échec réseau : la file est conservée telle quelle, elle sera
            // retentée. Rien n'est perdu.
            lastError = error.localizedDescription
        }
        pendingCount = await store.pendingCount()
    }

    /// Pousse l'état courant sans fusion (premier envoi d'un compte neuf).
    public func pushCurrent() async throws {
        guard let userId = auth.userId else { return }
        let token = try await auth.validAccessToken()
        try await client.upsertUserState(
            userId: userId,
            data: repository.rawState,
            updatedAt: repository.state.updatedAt,
            accessToken: token
        )
        await repository.markSynced(repository.rawState)
    }

    public func refreshPendingCount() async {
        pendingCount = await store.pendingCount()
    }
}

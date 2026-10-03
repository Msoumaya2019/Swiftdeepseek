// LocalStore.swift
// Stockage local de l'état et de la file de synchronisation.
//
// Correspondance : `src/services/storage.ts` côté React Native, qui utilise
// SQLite (`coran-memoire.db`). Le format local n'a PAS besoin d'être identique :
// il ne quitte jamais l'appareil. Ce qui doit être identique, c'est le document
// envoyé à Supabase — et c'est `user_state.data` qui fait foi.
//
// Choix : des fichiers JSON dans Application Support plutôt que SQLite.
// Raison : l'état est un document unique (pas des milliers de lignes), et cela
// supprime une dépendance. Le dossier est exclu des sauvegardes iCloud : c'est
// un cache reconstructible, pas une donnée à préserver.

import Foundation

public struct SyncOperation: Codable, Equatable, Sendable {
    public var id: String
    public var userId: String
    public var payload: JSONValue
    public var base: JSONValue?
    public var createdAt: String
}

public actor LocalStore {

    private let directory: URL
    private let fileManager = FileManager.default

    public init(directoryName: String = "SwiftdeepseekState") {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = directory
        try? mutable.setResourceValues(values)
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private func read(_ name: String) -> Data? {
        try? Data(contentsOf: url(name))
    }

    /// Écriture atomique : un fichier partiel ne doit jamais être relu comme un
    /// état valide (même précaution que le `.part` de `verseAudioCache.ts`).
    private func write(_ data: Data, to name: String) throws {
        let temporary = url(name + ".part")
        try data.write(to: temporary, options: .atomic)
        _ = try? fileManager.removeItem(at: url(name))
        try fileManager.moveItem(at: temporary, to: url(name))
    }

    // MARK: État courant

    public func loadState() -> JSONValue? {
        guard let data = read("state.json") else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func saveState(_ state: JSONValue) throws {
        try write(try JSONEncoder().encode(state), to: "state.json")
    }

    /// État conservé par compte, pour que changer de compte ne mélange pas les
    /// progressions (`account_state` côté React Native).
    public func loadAccountState(_ userId: String) -> JSONValue? {
        guard let data = read("account-\(userId).json") else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func saveAccountState(_ userId: String, state: JSONValue) throws {
        try write(try JSONEncoder().encode(state), to: "account-\(userId).json")
    }

    // MARK: File de synchronisation

    private func loadQueue() -> [SyncOperation] {
        guard let data = read("pending.json") else { return [] }
        return (try? JSONDecoder().decode([SyncOperation].self, from: data)) ?? []
    }

    private func saveQueue(_ queue: [SyncOperation]) throws {
        try write(try JSONEncoder().encode(queue), to: "pending.json")
    }

    public func enqueue(_ operation: SyncOperation) throws {
        var queue = loadQueue()
        guard !queue.contains(where: { $0.id == operation.id }) else { return }
        queue.append(operation)
        try saveQueue(queue)
    }

    public func pendingOperations(for userId: String) -> [SyncOperation] {
        loadQueue().filter { $0.userId == userId }
    }

    public func pendingCount() -> Int {
        loadQueue().count
    }

    public func acknowledge(_ id: String) throws {
        try saveQueue(loadQueue().filter { $0.id != id })
    }

    public func clearQueue() throws {
        try saveQueue([])
    }
}

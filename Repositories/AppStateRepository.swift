// AppStateRepository.swift
// Source de vérité locale de l'état applicatif.
//
// PRINCIPE — le document JSON brut est conservé tel quel ; les structs typés n'en
// sont qu'une vue. Toute écriture part du JSON existant et n'écrase que les clés
// que cette application connaît.
//
// Pourquoi : l'application React Native peut ajouter demain une clé que cette
// version ignore. Un client Swift qui reconstruirait le document de zéro la
// supprimerait silencieusement, et l'utilisateur perdrait des données dans
// l'autre application. Ce fichier est la garantie que cela n'arrive pas.

import Foundation

@MainActor
public final class AppStateRepository: ObservableObject {

    public enum RepositoryError: LocalizedError {
        case unreadableDocument

        public var errorDescription: String? {
            switch self {
            case .unreadableDocument:
                return """
                    Le document d'état reçu n'a pas la forme attendue.
                    Aucune écriture n'a été faite, pour ne pas risquer d'écraser \
                    les données existantes.
                    """
            }
        }
    }

    /// Clés que cette application sait produire. Une clé absente d'ici n'est
    /// jamais touchée.
    private static let knownKeys: Set<String> = [
        "schema", "onboardingDone", "onboardingStep", "updatedAt", "userId",
        "knowledge", "goal", "pace", "learningDays", "sessions", "revisions",
        "profile", "theme", "uiFont", "accent", "notifications", "reader",
        "audioPreferences", "bookmarks", "readPages", "lastRead", "memorizedAt",
        "reviewSettings", "reviewHistory", "reviewDue", "difficultyMarkers",
        "difficultyHistory", "reviewModelStartedAt", "reviewCycle",
        "reviewConsolidations", "reviewPriorityDue", "reviewCycleHistory",
        "consolidationHistory", "studyProgress"
    ]

    @Published public private(set) var state: AppState
    @Published public private(set) var rawState: JSONValue
    @Published public private(set) var hasLocalChanges = false

    private let store: LocalStore
    /// Dernier document dont on sait qu'il était synchronisé : c'est la « base »
    /// de la fusion à trois voies.
    private var base: JSONValue?
    private var userId: String?
    /// Le document du compte TEL QU'IL EST SUR CET APPAREIL — et non le repli
    /// global.
    ///
    /// La distinction compte : `Reconcile.accountState` demande « le cache
    /// appartient-il à ce compte ? » (`cached?.userId === userId`), et l'état
    /// global n'est pas un cache de compte. Le confondre ferait adopter comme
    /// état local un document qui n'appartient à personne.
    private var accountCache: JSONValue?

    public init(store: LocalStore = LocalStore()) {
        self.store = store
        let initial = Program.defaultState()
        self.state = initial
        self.rawState = (try? JSONEncoder().encode(initial)).flatMap {
            try? JSONDecoder().decode(JSONValue.self, from: $0)
        } ?? .object([:])
    }

    // MARK: Chargement

    public func load(userId: String?) async {
        self.userId = userId
        guard let userId else { return }

        let account = await store.loadAccountState(userId)
        accountCache = account

        // L'état du compte est prioritaire, l'état global sert de repli.
        //
        // En deux temps, et non `await a ?? (await b)` : l'opérateur `??` prend
        // son opérande droit dans une autoclosure, qui ne supporte pas
        // `await` — « 'await' in an autoclosure that does not support
        // concurrency ».
        var cached = account
        if cached == nil { cached = await store.loadState() }
        guard let cached, let typed = AppState.decode(from: cached) else { return }

        state = Program.migrateReaderState(typed)
        rawState = cached
        base = cached
        hasLocalChanges = !(await store.pendingOperations(for: userId)).isEmpty
    }

    /// Adopte le document venu du serveur, en le RÉCONCILIANT avec le cache de
    /// ce compte — `accountState`, `src/core/program.ts:82`.
    ///
    /// Rend `true` quand le document adopté doit repartir vers le serveur : une
    /// métadonnée a été récupérée du local, ou le local était plus récent.
    /// L'appelant met alors la synchronisation en file.
    ///
    /// Ce que cette méthode remplace, et pourquoi c'est un correctif : elle
    /// adoptait auparavant le document distant TEL QUEL. Un document distant
    /// plus ancien, ou écrit par une version qui ne connaissait pas encore
    /// `bookmarks`, `readPages` ou `studyProgress`, écrasait alors ces clés
    /// côté local — sans que rien ne le signale. `reconcileState` est la
    /// fonction que l'application React Native emploie au même instant.
    @discardableResult
    public func applyRemote(_ remote: JSONValue) async -> Bool {
        guard let userId else { return false }
        let pending = await store.pendingOperations(for: userId)
        guard pending.isEmpty else {
            // Une modification locale attend : la fusion à trois voies de
            // `StateSyncService` décidera, au moment de la poussée. On ne
            // remplace rien ici, et on ne pousse rien non plus.
            base = remote
            return false
        }

        let outcome = Reconcile.accountState(userId: userId, cache: accountCache, remote: remote)
        guard let typed = AppState.decode(from: outcome.document) else { return false }
        state = Program.migrateReaderState(typed)
        rawState = outcome.document
        // La base reste ce que le SERVEUR porte : c'est la dernière version dont
        // on sait qu'elle était synchronisée, et c'est sur elle que portera la
        // fusion à trois voies si une modification locale survient ensuite.
        base = remote
        try? await store.saveState(outcome.document)
        try? await store.saveAccountState(userId, state: outcome.document)
        return outcome.shouldPush
    }

    // MARK: Mutation

    /// Applique une transformation, enregistre localement et met en file la
    /// synchronisation. C'est le point d'entrée unique de toute modification.
    @discardableResult
    public func mutate(_ transform: (AppState) -> AppState) async -> AppState {
        let previousRaw = rawState
        let next = Program.touch(transform(state))
        let merged = Self.patch(raw: previousRaw, with: next)
        guard let typed = AppState.decode(from: merged) else {
            // Le document produit serait illisible : on n'écrit rien.
            return state
        }
        state = typed
        rawState = merged

        guard let userId else { return typed }
        try? await store.saveState(merged)
        try? await store.saveAccountState(userId, state: merged)
        try? await store.enqueue(SyncOperation(
            id: "\(userId):\(Int(Date().timeIntervalSince1970 * 1000)):\(UUID().uuidString.prefix(6))",
            userId: userId,
            payload: merged,
            base: base ?? previousRaw,
            createdAt: DateKeys.iso(Date())
        ))
        hasLocalChanges = true
        return typed
    }

    /// Met en file la synchronisation du document COURANT, sans le transformer.
    ///
    /// Le pendant de `mutate` pour un document qui vient d'être adopté : la
    /// réconciliation a déjà décidé de son contenu, il n'y a rien à transformer
    /// de plus. C'est le `enqueueState(result.state)` de `App.tsx:132`.
    public func enqueueCurrent() async {
        guard let userId else { return }
        try? await store.enqueue(SyncOperation(
            id: "\(userId):\(Int(Date().timeIntervalSince1970 * 1000)):\(UUID().uuidString.prefix(6))",
            userId: userId,
            payload: rawState,
            base: base ?? rawState,
            createdAt: DateKeys.iso(Date())
        ))
        hasLocalChanges = true
    }

    /// Marque la base de fusion après une synchronisation réussie.
    public func markSynced(_ document: JSONValue) async {
        base = document
        guard let userId else { return }
        let remaining = await store.pendingOperations(for: userId)
        hasLocalChanges = !remaining.isEmpty
    }

    public func currentBase() -> JSONValue? { base }

    // MARK: Réécriture ciblée

    /// Fusionne l'état typé dans le document brut.
    ///
    /// - Les clés connues sont écrites (une clé connue devenue `nil` devient
    ///   `null`, ce qui correspond à ce que produit `defaultState()` côté
    ///   React Native).
    /// - Les clés inconnues du document brut sont laissées intactes.
    static func patch(raw: JSONValue, with typed: AppState) -> JSONValue {
        guard let encodedData = try? JSONEncoder().encode(typed),
              let encoded = try? JSONDecoder().decode(JSONValue.self, from: encodedData),
              var result = raw.objectValue else {
            return raw
        }
        let produced = encoded.objectValue ?? [:]
        for (key, value) in produced {
            result[key] = value
        }
        // Clé connue absente de l'état typé : elle a été effacée volontairement.
        for key in knownKeys where produced[key] == nil && result[key] != nil {
            result[key] = .null
        }
        return .object(result)
    }
}

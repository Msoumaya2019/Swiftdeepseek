// SupabaseRESTClient.swift
// Client Supabase minimal, bâti sur Foundation uniquement.
//
// DÉCISION D'ARCHITECTURE — pourquoi pas le SDK `supabase-swift` ?
//   Le SDK officiel est le choix habituel. Il a été écarté ici pour une raison
//   précise : ce dépôt a été écrit sans Mac, donc sans possibilité de compiler
//   pour vérifier l'API du SDK. Une dépendance non vérifiable est un risque, et
//   le SDK n'apporte ici que ce que ces 250 lignes font déjà — d'autant que
//   `@supabase/supabase-js` (utilisé par l'application React Native) est
//   lui-même un simple client REST.
//   Bénéfice secondaire : le protocole sur le fil est reproduit à l'identique
//   de celui de l'application React Native, ce qui garantit la compatibilité.
//   Le SDK pourra être substitué plus tard : l'interface publique de
//   `AuthService` et de `StateSyncService` ne bougerait pas.

import Foundation

public struct SupabaseSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userId: String
    public var email: String?

    public var isExpired: Bool { expiresAt <= Date().addingTimeInterval(30) }
}

public struct SupabaseAuthError: LocalizedError, Equatable {
    public var message: String
    public var status: Int?

    public var errorDescription: String? { message }
}

public actor SupabaseRESTClient {

    private let baseURL: URL
    private let publishableKey: String
    private let session: URLSession

    public init(baseURL: URL, publishableKey: String, timeout: TimeInterval = AppConfig.requestTimeout) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Requête générique

    private func request(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        accessToken: String? = nil,
        extraHeaders: [String: String] = [:],
        isAuthEndpoint: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else {
            throw SupabaseAuthError(message: "URL invalide : \(path)", status: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // GoTrue attend le jeton d'accès ; PostgREST accepte la clé publique en
        // repli quand l'appel est anonyme.
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError(message: "Réponse illisible", status: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseAuthError(
                message: Self.errorMessage(from: data) ?? "Erreur HTTP \(http.statusCode)",
                status: http.statusCode
            )
        }
        return (data, http)
    }

    /// Extrait le message d'erreur GoTrue/PostgREST, en français quand c'est
    /// possible — le même genre de message que l'application React Native.
    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let raw = (object["error_description"] as? String)
            ?? (object["msg"] as? String)
            ?? (object["message"] as? String)
            ?? (object["error"] as? String)
        guard let raw else { return nil }
        return Self.localizedAuthMessage(raw)
    }

    static func localizedAuthMessage(_ raw: String) -> String {
        switch raw {
        case "Invalid login credentials":
            return "Identifiants incorrects. Vérifie ton adresse e-mail et ton mot de passe."
        case "Email not confirmed":
            return "Adresse e-mail non confirmée. Ouvre le lien reçu par e-mail."
        case "User already registered":
            return "Un compte existe déjà avec cette adresse e-mail."
        case "Password should be at least 6 characters":
            return "Le mot de passe doit contenir au moins 6 caractères."
        default:
            return raw
        }
    }

    // MARK: - Authentification (GoTrue)

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: String
            let email: String?
        }
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let user: User?
    }

    /// `supabase.auth.signInWithPassword` — mêmes comptes que l'application
    /// React Native, donc mêmes UUID.
    public func signIn(email: String, password: String) async throws -> SupabaseSession {
        let payload = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password
        ])
        let (data, _) = try await request(
            "auth/v1/token",
            method: "POST",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            body: payload,
            isAuthEndpoint: true
        )
        return try Self.session(from: data)
    }

    /// `supabase.auth.signUp` — inscription d'un NOUVEAU compte. À n'utiliser
    /// que si la personne n'en a pas déjà un : créer un second compte pour la
    /// même personne produirait exactement le doublon d'utilisateurs à éviter.
    public func signUp(email: String, password: String) async throws -> SupabaseSession? {
        let payload = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password
        ])
        let (data, _) = try await request(
            "auth/v1/signup",
            method: "POST",
            body: payload,
            isAuthEndpoint: true
        )
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let access = response.access_token,
              let refresh = response.refresh_token else {
            return nil // Confirmation par e-mail requise.
        }
        return try Self.session(from: data)
    }

    public func refresh(_ refreshToken: String) async throws -> SupabaseSession {
        let payload = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let (data, _) = try await request(
            "auth/v1/token",
            method: "POST",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: payload,
            isAuthEndpoint: true
        )
        return try Self.session(from: data)
    }

    public func user(accessToken: String) async throws -> (id: String, email: String?) {
        let (data, _) = try await request("auth/v1/user", accessToken: accessToken)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = object?["id"] as? String else {
            throw SupabaseAuthError(message: "Utilisateur illisible", status: nil)
        }
        return (id, object?["email"] as? String)
    }

    public func signOut(accessToken: String) async {
        _ = try? await request("auth/v1/logout", method: "POST", accessToken: accessToken)
    }

    public func requestPasswordReset(email: String, redirectTo: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "redirect_to": redirectTo
        ])
        _ = try await request("auth/v1/recover", method: "POST", body: payload, isAuthEndpoint: true)
    }

    public func resendSignupConfirmation(email: String, redirectTo: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "type": "signup",
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "options": ["emailRedirectTo": redirectTo]
        ])
        _ = try await request("auth/v1/resend", method: "POST", body: payload, isAuthEndpoint: true)
    }

    public func updatePassword(_ password: String, accessToken: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["password": password])
        _ = try await request("auth/v1/user", method: "PUT", body: payload, accessToken: accessToken)
    }

    /// Échange les jetons d'un lien reçu par e-mail (`coranmemoire://auth` côté
    /// React Native, `swiftdeepseek://auth` ici).
    public func sessionFromAuthLink(_ url: URL) async throws -> SupabaseSession {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
                ?? url.query else {
            throw SupabaseAuthError(message: "Lien de connexion incomplet.", status: nil)
        }
        var parameters: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            parameters[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
        if let error = parameters["error"] {
            throw SupabaseAuthError(
                message: parameters["error_description"] ?? "Lien expiré ou invalide.",
                status: nil
            )
        }
        guard let access = parameters["access_token"], let refresh = parameters["refresh_token"] else {
            throw SupabaseAuthError(message: "Lien de connexion incomplet.", status: nil)
        }
        let identity = try await user(accessToken: access)
        return SupabaseSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(3600),
            userId: identity.id,
            email: identity.email
        )
    }

    private static func session(from data: Data) throws -> SupabaseSession {
        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw SupabaseAuthError(message: "Réponse d'authentification illisible", status: nil)
        }
        guard let access = response.access_token,
              let refresh = response.refresh_token,
              let user = response.user else {
            throw SupabaseAuthError(message: "Session incomplète", status: nil)
        }
        return SupabaseSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(response.expires_in ?? 3600),
            userId: user.id,
            email: user.email
        )
    }

    // MARK: - Données (PostgREST)

    /// Lit `public.user_state.data` — la seule table de données que cette
    /// première étape utilise.
    public func fetchUserState(userId: String, accessToken: String) async throws -> JSONValue? {
        let (data, _) = try await request(
            "rest/v1/user_state",
            query: [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "select", value: "data")
            ],
            accessToken: accessToken
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first,
              let value = first["data"] else {
            return nil
        }
        return JSONValue.from(value)
    }

    /// Écrit `public.user_state` — `upsert` complet, comme `pushState()` de
    /// l'application React Native (`sync.ts:62`).
    public func upsertUserState(userId: String, data: JSONValue, updatedAt: String, accessToken: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "user_id": userId,
            "data": data.anyValue,
            "updated_at": updatedAt
        ])
        _ = try await request(
            "rest/v1/user_state",
            method: "POST",
            body: payload,
            accessToken: accessToken,
            extraHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        )
    }

    /// Appel d'une fonction RPC (utilisé par les étapes suivantes : Quiz, amis,
    /// notifications). Les tables `quiz_*` ne sont pas lisibles directement —
    /// tout passe par ces fonctions, côté React Native comme ici.
    public func rpc(_ name: String, parameters: [String: Any], accessToken: String) async throws -> JSONValue {
        let payload = try JSONSerialization.data(withJSONObject: parameters)
        let (data, _) = try await request(
            "rest/v1/rpc/\(name)",
            method: "POST",
            body: payload,
            accessToken: accessToken
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return JSONValue.from(object)
    }

    /// Lecture d'une table PostgREST — l'équivalent de
    /// `client().from(table).select(...)` côté React Native.
    ///
    /// Les filtres passent par `query`, sous la forme exacte de PostgREST
    /// (`id=eq.<uuid>`, `select=id,display_name`, `order=created_at.desc`), afin
    /// que les requêtes des deux applications restent comparables ligne à ligne.
    ///
    /// Les politiques RLS s'appliquent : c'est le jeton d'accès de la personne
    /// connectée qui décide de ce qui est lisible, jamais une clé privilégiée.
    public func select(
        table: String,
        query: [URLQueryItem],
        accessToken: String
    ) async throws -> JSONValue {
        let (data, _) = try await request(
            "rest/v1/\(table)",
            query: query,
            accessToken: accessToken
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return .null
        }
        return JSONValue.from(object)
    }

    /// Écrit une ligne dans une table PostgREST — l'équivalent de
    /// `client().from(table).insert(...)`.
    ///
    /// `Prefer: return=minimal` comme l'application React Native : l'insertion
    /// ne renvoie rien, donc aucune ligne n'est exposée au-delà de ce que la RLS
    /// autorise déjà. `resolution` n'est **pas** posé : c'est un `insert` pur,
    /// pas un `upsert`.
    public func insert(
        table: String,
        row: [String: Any],
        accessToken: String
    ) async throws {
        let payload = try JSONSerialization.data(withJSONObject: row)
        _ = try await request(
            "rest/v1/\(table)",
            method: "POST",
            body: payload,
            accessToken: accessToken,
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    /// `upsert` d'une ligne, la clé étant déclarée par `onConflict` (une colonne
    /// ou une liste `a,b`) — l'équivalent de `client().from(table).upsert(...)`.
    ///
    /// `resolution=merge-duplicates` est ce que fait Supabase par défaut pour un
    /// `upsert` : la ligne existante est **fusionnée**, pas dupliquée.
    public func upsert(
        table: String,
        row: [String: Any],
        onConflict: String,
        accessToken: String
    ) async throws {
        let payload = try JSONSerialization.data(withJSONObject: row)
        _ = try await request(
            "rest/v1/\(table)",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: onConflict)],
            body: payload,
            accessToken: accessToken,
            extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    /// Compte les lignes qui répondent à `query` — l'équivalent de
    /// `client().from(table).select('id',{count:'exact',head:true})`.
    ///
    /// `head:true` n'est pas une option de PostgREST : PostgREST répond au
    /// `HEAD` avec le décompte dans `Content-Range`, sans corps. C'est donc une
    /// méthode **dédiée**, pas un `select` détourné.
    ///
    /// La valeur vient de `Content-Range`, « `start-end/total` » ou `*/total`
    /// quand la plage est vide — les deux formes portent le total après la barre.
    public func count(
        table: String,
        query: [URLQueryItem],
        accessToken: String
    ) async throws -> Int {
        var items = query
        items.append(URLQueryItem(name: "select", value: "id"))
        let (_, response) = try await request(
            "rest/v1/\(table)",
            method: "HEAD",
            query: items,
            accessToken: accessToken,
            extraHeaders: ["Prefer": "count=exact"]
        )
        guard let range = response.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last,
              let value = Int(total) else {
            return 0
        }
        return value
    }

    /// Lit **au plus une** ligne et la rend en objet, ou `nil` s'il n'y en a
    /// aucune — l'équivalent de `.maybeSingle()`, que PostgREST n'a pas.
    ///
    /// On passe par `Accept: application/vnd.pgrst.object+json`, que PostgREST
    /// rend en **objet** au lieu d'un tableau d'une ligne. `limit=1` borne la
    /// lecture : sans lui, PostgREST refuserait deux lignes là où `.maybeSingle()`
    /// aurait échoué. Le cas « aucune ligne » rend `nil` et **non** une erreur.
    public func maybeSingle(
        table: String,
        query: [URLQueryItem],
        accessToken: String
    ) async throws -> JSONValue? {
        var items = query
        items.append(URLQueryItem(name: "limit", value: "1"))
        let (data, response) = try await request(
            "rest/v1/\(table)",
            query: items,
            accessToken: accessToken,
            extraHeaders: ["Accept": "application/vnd.pgrst.object+json"]
        )
        // PostgREST renvoie 406 (Not Acceptable) quand zéro ligne correspond à
        // la demande d'objet unique : c'est le « pas de ligne », pas une panne.
        if response.statusCode == 406 { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if object is NSNull { return nil }
        return JSONValue.from(object)
    }
}

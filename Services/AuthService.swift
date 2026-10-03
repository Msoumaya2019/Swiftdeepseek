// AuthService.swift
// Authentification auprès du Supabase EXISTANT.
//
// Objectif explicite : une personne qui possède déjà un compte dans
// l'application React Native entre les mêmes identifiants ici et retrouve le
// MÊME compte — donc le même UUID, les mêmes données, les mêmes amis.
//
// Conséquence : ce service n'ouvre JAMAIS de nouvelle base d'authentification et
// ne crée pas d'utilisateur à la place de quelqu'un d'existant. `signUp` est
// réservé aux personnes qui n'ont réellement pas encore de compte.

import Foundation

@MainActor
public final class AuthService: ObservableObject {

    public enum State: Equatable {
        case checking
        case signedOut
        case signedIn(SupabaseSession)
    }

    @Published public private(set) var state: State = .checking
    @Published public private(set) var lastError: String?

    private let client: SupabaseRESTClient

    public init(client: SupabaseRESTClient) {
        self.client = client
    }

    public var session: SupabaseSession? {
        if case .signedIn(let session) = state { return session }
        return nil
    }

    public var userId: String? { session?.userId }

    // MARK: Restauration

    /// Restaure la session conservée dans le trousseau, en rafraîchissant le
    /// jeton s'il a expiré. C'est ce qui permet d'ouvrir l'application sans
    /// réseau : on ne vérifie pas la session auprès du serveur pour laisser
    /// entrer, on se fie au trousseau.
    public func restore() async {
        guard let stored = SessionStore.load() else {
            state = .signedOut
            return
        }
        if stored.isExpired {
            do {
                let refreshed = try await client.refresh(stored.refreshToken)
                SessionStore.save(refreshed)
                state = .signedIn(refreshed)
            } catch {
                // Réseau indisponible : on garde la session locale. Un jeton
                // expiré ne doit pas empêcher d'accéder aux fonctions locales.
                // Le rafraîchissement sera retenté à la reconnexion.
                state = .signedIn(stored)
            }
        } else {
            state = .signedIn(stored)
        }
    }

    // MARK: Connexion

    public func signIn(email: String, password: String) async throws -> SupabaseSession {
        lastError = nil
        do {
            let session = try await client.signIn(email: email, password: password)
            SessionStore.save(session)
            state = .signedIn(session)
            return session
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Création d'un compte réellement nouveau.
    public func signUp(email: String, password: String) async throws -> SupabaseSession? {
        lastError = nil
        do {
            let session = try await client.signUp(email: email, password: password)
            if let session {
                SessionStore.save(session)
                state = .signedIn(session)
            }
            return session
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    public func signOut() async {
        if let session = session {
            await client.signOut(accessToken: session.accessToken)
        }
        SessionStore.clear()
        state = .signedOut
    }

    // MARK: Mot de passe

    public func requestPasswordReset(email: String) async throws {
        try await client.requestPasswordReset(email: email, redirectTo: AppConfig.authRedirect)
    }

    public func resendConfirmation(email: String) async throws {
        try await client.resendSignupConfirmation(email: email, redirectTo: AppConfig.authRedirect)
    }

    public func changePassword(_ password: String) async throws {
        guard let session = session else { return }
        try await client.updatePassword(password, accessToken: session.accessToken)
    }

    /// Traite un lien reçu par e-mail (`swiftdeepseek://auth#access_token=...`).
    public func handleAuthLink(_ url: URL) async throws {
        let session = try await client.sessionFromAuthLink(url)
        SessionStore.save(session)
        state = .signedIn(session)
    }

    // MARK: Jeton valide

    /// Renvoie un jeton d'accès valide, en le rafraîchissant si besoin.
    /// Le rafraîchissement est sérialisé par l'acteur `SupabaseRESTClient`.
    public func validAccessToken() async throws -> String {
        guard let session = session else {
            throw SupabaseAuthError(message: "Connecte-toi pour synchroniser tes données.", status: nil)
        }
        guard session.isExpired else { return session.accessToken }
        let refreshed = try await client.refresh(session.refreshToken)
        SessionStore.save(refreshed)
        state = .signedIn(refreshed)
        return refreshed.accessToken
    }
}

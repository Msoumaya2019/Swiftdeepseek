// SocialService.swift
// Couche d'accès aux données sociales (amis, invitations, messagerie).
//
// Correspondance : `src/services/social.ts`.
//
// IMPORTANT — périmètre de cette première étape.
// L'application React Native utilise 24 tables et une quarantaine de fonctions
// RPC pour le social. Cette étape n'en couvre qu'une partie, celle qui suffit à
// retrouver ses amis et son code d'invitation :
//   - `friend_profiles`     (profil social, code d'invitation)
//   - `friend_links`        (relations entre deux comptes)
//   - `friend_inbox`        (RPC : dernier message + non-lus + présence)
//   - `ensure_social_profile`, `request_friend`, `accept_friend`,
//     `decline_friend`, `remove_friend`, `block_friend`, `unblock_friend`,
//     `my_unread_messages`, `set_social_online`
// Restent à porter (voir `SWIFT_MIGRATION.md`) : la messagerie en temps réel,
// les groupes, les objectifs partagés, les rendez-vous de révision, les
// récitations partagées, la modération.
//
// Aucune table n'est modifiée par ce fichier : uniquement des lectures et des
// appels de fonctions déjà existantes. Les politiques RLS décident seules de ce
// qui est lisible.

import Foundation

// MARK: - Modèles

/// `FriendProfile` — `src/services/social.ts:4`.
public struct FriendProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var inviteCode: String
    public var shareOnline: Bool
    public var shareLocation: Bool
    public var shareProgress: Bool
    public var avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case inviteCode = "invite_code"
        case shareOnline = "share_online"
        case shareLocation = "share_location"
        case shareProgress = "share_progress"
        case avatarPath = "avatar_path"
    }
}

/// `FriendLink` — `src/services/social.ts:5`.
public struct FriendLink: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var requesterId: String
    public var recipientId: String
    public var status: String
    public var blockedBy: String?
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case requesterId = "requester_id"
        case recipientId = "recipient_id"
        case status
        case blockedBy = "blocked_by"
        case createdAt = "created_at"
    }
}

/// Une relation telle qu'affichée : la relation, plus le profil de l'autre
/// personne quand il est lisible.
public struct FriendRow: Identifiable, Sendable {
    public var id: String { link.id }
    public var link: FriendLink
    public var other: FriendProfile?

    /// Vrai quand c'est l'autre personne qui a envoyé la demande et qu'elle
    /// attend une réponse.
    public func isIncomingRequest(myID: String) -> Bool {
        link.status == "pending" && link.requesterId != myID
    }

    public func isOutgoingRequest(myID: String) -> Bool {
        link.status == "pending" && link.requesterId == myID
    }

    public var isAccepted: Bool { link.status == "accepted" }
}

/// Une ligne de `friend_inbox` — `src/services/social.ts:84`.
public struct FriendInboxRow: Sendable {
    public var linkId: String
    public var body: String?
    public var createdAt: String?
    public var unreadCount: Int
    public var otherId: String
    public var isOnline: Bool
}

public struct SocialError: LocalizedError {
    public var message: String
    public var errorDescription: String? { message }
}

// MARK: - Service

public final class SocialService: Sendable {

    private let client: SupabaseRESTClient

    public init(client: SupabaseRESTClient) {
        self.client = client
    }

    // MARK: Profil

    /// `ensure_social_profile` — crée le profil social s'il n'existe pas encore.
    /// C'est la fonction appelée par l'application React Native à l'ouverture de
    /// l'onglet Amis, donc un compte déjà utilisé possède déjà son profil.
    public func ensureProfile(accessToken: String) async throws -> FriendProfile {
        let value = try await client.rpc("ensure_social_profile", parameters: [:], accessToken: accessToken)
        return try decode(value)
    }

    public func profile(id: String, accessToken: String) async throws -> FriendProfile? {
        let value = try await client.select(
            table: "friend_profiles",
            query: [
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "select", value: "*")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value).first
    }

    // MARK: Relations

    /// `listFriendLinks` — `src/services/social.ts:28`.
    /// Les politiques RLS ne renvoient que les relations où la personne est
    /// partie prenante.
    public func links(accessToken: String) async throws -> [FriendLink] {
        let value = try await client.select(
            table: "friend_links",
            query: [
                URLQueryItem(
                    name: "select",
                    value: "id,requester_id,recipient_id,status,blocked_by,created_at"
                ),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    /// Les relations accompagnées du profil de l'autre personne.
    public func rows(myID: String, accessToken: String) async throws -> [FriendRow] {
        let links = try await links(accessToken: accessToken)
        let others = links.map { $0.requesterId == myID ? $0.recipientId : $0.requesterId }
        guard !others.isEmpty else {
            return links.map { FriendRow(link: $0, other: nil) }
        }
        let value = try await client.select(
            table: "friend_profiles",
            query: [
                URLQueryItem(name: "select", value: "id,display_name,invite_code,share_online,share_location,share_progress,avatar_path"),
                URLQueryItem(name: "id", value: "in.(\(others.joined(separator: ",")))")
            ],
            accessToken: accessToken
        )
        let profiles = try decodeArray(value) as [FriendProfile]
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return links.map { link in
            let otherID = link.requesterId == myID ? link.recipientId : link.requesterId
            return FriendRow(link: link, other: byID[otherID])
        }
    }

    /// `friend_inbox` — dernier message, nombre de non-lus et présence, pour
    /// toutes les conversations acceptées, en un seul aller-retour.
    public func inbox(accessToken: String) async throws -> [FriendInboxRow] {
        let value = try await client.rpc("friend_inbox", parameters: [:], accessToken: accessToken)
        guard let rows = value.arrayValue else { return [] }
        return rows.map { row in
            FriendInboxRow(
                linkId: row["link_id"]?.stringValue ?? "",
                body: row["body"]?.stringValue,
                createdAt: row["created_at"]?.stringValue,
                unreadCount: row["unread_count"]?.intValue ?? 0,
                otherId: row["other_id"]?.stringValue ?? "",
                isOnline: row["is_online"]?.boolValue ?? false
            )
        }
    }

    // MARK: Actions

    public func requestFriend(code: String, accessToken: String) async throws {
        _ = try await client.rpc("request_friend", parameters: ["p_code": code], accessToken: accessToken)
    }

    public func acceptFriend(linkID: String, accessToken: String) async throws {
        _ = try await client.rpc("accept_friend", parameters: ["p_link": linkID], accessToken: accessToken)
    }

    public func declineFriend(linkID: String, accessToken: String) async throws {
        _ = try await client.rpc("decline_friend", parameters: ["p_link": linkID], accessToken: accessToken)
    }

    public func removeFriend(linkID: String, accessToken: String) async throws {
        _ = try await client.rpc("remove_friend", parameters: ["p_link": linkID], accessToken: accessToken)
    }

    public func blockFriend(otherID: String, accessToken: String) async throws {
        _ = try await client.rpc("block_friend", parameters: ["p_other": otherID], accessToken: accessToken)
    }

    public func unblockFriend(otherID: String, accessToken: String) async throws {
        _ = try await client.rpc("unblock_friend", parameters: ["p_other": otherID], accessToken: accessToken)
    }

    public func unreadMessageCount(accessToken: String) async throws -> Int {
        let value = try await client.rpc("my_unread_messages", parameters: [:], accessToken: accessToken)
        return value.intValue ?? 0
    }

    public func setOnline(_ active: Bool, accessToken: String) async throws {
        _ = try await client.rpc("set_social_online", parameters: ["p_active": active], accessToken: accessToken)
    }

    // MARK: Décodage

    private func decode<T: Decodable>(_ value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SocialError(message: "Réponse illisible du serveur social.")
        }
    }

    private func decodeArray<T: Decodable>(_ value: JSONValue) throws -> [T] {
        guard value.arrayValue != nil else { return [] }
        return try decode(value)
    }
}

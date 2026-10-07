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

/// `ChatMessage` — `src/services/social.ts:11`.
///
/// `recitation` n'est **pas** décodée de la table `friend_messages` : elle est
/// attachée après coup par `listMessages`, depuis la table `recitations`. Le
/// champ est donc optionnel et absent du décodage.
public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var linkId: String?
    public var groupId: String?
    public var senderId: String
    public var kind: String
    public var body: String
    public var recitationId: String?
    public var createdAt: String
    public var deletedAt: String?
    public var recitation: MessagingOptions.Recitation?

    enum CodingKeys: String, CodingKey {
        case id
        case linkId = "link_id"
        case groupId = "group_id"
        case senderId = "sender_id"
        case kind
        case body
        case recitationId = "recitation_id"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    /// La sorte, quand elle est reconnue. Une valeur inconnue rend `nil` : le
    /// message s'affiche alors comme un message ordinaire plutôt que d'échouer.
    public var kindValue: MessagingOptions.Kind? { MessagingOptions.Kind(rawValue: kind) }

    /// Un message supprimé garde sa ligne (suppression douce) : c'est
    /// `deleted_at` qui décide, pas l'absence du corps.
    public var isDeleted: Bool { deletedAt != nil }
}

/// `MessageReport` — `src/services/social.ts:12`.
public struct MessageReport: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var messageId: String
    public var reason: String
    public var reporterId: String
    public var excerpt: String
    public var status: String
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case reason
        case reporterId = "reporter_id"
        case excerpt
        case status
        case createdAt = "created_at"
    }
}

/// `FriendGroup` — `src/services/social.ts:8`.
public struct FriendGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var ownerId: String
    public var createdAt: String
    /// Le contact administrateur du groupe, s'il en est un.
    ///
    /// `supabase/admin-contact.sql:2` ajoute la colonne **hors** du schéma
    /// initial, et le type de l'original la porte **optionnelle** en plus d'être
    /// nulle (`contact_user_id?:string|null`, `social.ts:7`). Une clé ABSENTE et
    /// une clé NULLE doivent donc toutes deux décoder en `nil` — c'est le
    /// défaut de `Codable` pour un `Optional`, et il ne faut **pas** le
    /// remplacer par un `decodeIfPresent` assorti d'une valeur par défaut, qui
    /// écraserait la distinction.
    ///
    /// C'est lui qui décide d'un ÉCRAN : un groupe d'administration
    /// (`contactUserId != nil`) n'a ni objectif partagé, ni rendez-vous, ni
    /// membres à nommer — l'original le dit par `!!g.contact_user_id`
    /// (`SocialScreens.tsx:162`).
    public var contactUserId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case contactUserId = "contact_user_id"
    }
}

/// `GroupMember` — `src/services/social.ts:9`.
public struct GroupMember: Codable, Equatable, Sendable {
    public var groupId: String
    public var userId: String
    public var role: String
    public var acceptedAt: String?
    public var invitedBy: String?
    public var profile: FriendProfile?

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case userId = "user_id"
        case role
        case acceptedAt = "accepted_at"
        case invitedBy = "invited_by"
    }
}

/// `SharedGoal` — `src/services/social.ts:15`.
public struct SharedGoal: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var linkId: String
    public var weekStart: String
    public var targetSessions: Int
    public var proposedBy: String
    public var acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case linkId = "link_id"
        case weekStart = "week_start"
        case targetSessions = "target_sessions"
        case proposedBy = "proposed_by"
        case acceptedAt = "accepted_at"
    }
}

/// `ReviewAppointment` — `src/services/social.ts:16`.
public struct ReviewAppointment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var linkId: String
    public var startsAt: String
    public var proposedBy: String
    public var acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case linkId = "link_id"
        case startsAt = "starts_at"
        case proposedBy = "proposed_by"
        case acceptedAt = "accepted_at"
    }
}

/// `SocialSuspension` — `src/services/social.ts:13`.
public struct SocialSuspension: Codable, Equatable, Sendable {
    public var userId: String
    public var reason: String
    public var suspendedUntil: String?
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case reason
        case suspendedUntil = "suspended_until"
        case createdAt = "created_at"
    }
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

    // MARK: Messagerie

    /// `listMessages` — `src/services/social.ts:130`.
    ///
    /// Trois étapes, dans cet ordre : les 50 derniers messages de la pièce (du
    /// plus récent au plus ancien, puis **remis à l'endroit**), le retrait de
    /// ceux que **moi** j'ai masqués, puis l'attache des récitations partagées.
    ///
    /// `before` est un curseur de pagination : on demande les messages
    /// **strictement antérieurs** à cet horodatage.
    public func messages(room: MessagingOptions.Room, before: String? = nil, accessToken: String) async throws -> [ChatMessage] {
        var query = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(MessagingOptions.pageSize)),
            URLQueryItem(name: "\(room.column)", value: "eq.\(room.value)")
        ]
        if let before {
            query.append(URLQueryItem(name: "created_at", value: "lt.\(before)"))
        }
        let value = try await client.select(table: "friend_messages", query: query, accessToken: accessToken)
        // `.reverse()` de l'original : la lecture descendante, l'affichage montant.
        var messages: [ChatMessage] = try decodeArray(value)
        messages.reverse()
        guard !messages.isEmpty else { return [] }

        let allIDs = messages.map(\.id)
        let hiddenValue = try await client.select(
            table: "friend_message_hidden",
            query: [
                URLQueryItem(name: "select", value: "message_id"),
                URLQueryItem(name: "message_id", value: "in.(\(allIDs.joined(separator: ",")))")
            ],
            accessToken: accessToken
        )
        let hidden = Set(hiddenValue.arrayValue?.compactMap { $0["message_id"]?.stringValue } ?? [])
        let visible = MessagingOptions.visible(messages, id: { $0.id }, hidden: hidden)

        let recitationIDs = MessagingOptions.recitationIDs(
            visible.map { (kind: $0.kindValue ?? .text, recitationID: $0.recitationId) }
        )
        guard !recitationIDs.isEmpty else { return visible }

        let rowsValue = try await client.select(
            table: "recitations",
            query: [
                URLQueryItem(name: "select", value: "id,start_verse_id,end_verse_id,duration_ms,storage_path"),
                URLQueryItem(name: "id", value: "in.(\(recitationIDs.joined(separator: ",")))")
            ],
            accessToken: accessToken
        )
        let attachments = try decodeArray(rowsValue) as [RecitationRow]
        let byID = Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0.recitation) })
        return visible.map { message in
            guard let id = message.recitationId, let recitation = byID[id] else { return message }
            var copy = message
            copy.recitation = recitation
            return copy
        }
    }

    /// La ligne brute de `recitations`, réduite au strict nécessaire —
    /// `social.ts:141`, `select('id,start_verse_id,end_verse_id,duration_ms,storage_path')`.
    private struct RecitationRow: Codable {
        var id: String
        var startVerseID: Int
        var endVerseID: Int
        var durationMS: Int
        var storagePath: String

        enum CodingKeys: String, CodingKey {
            case id
            case startVerseID = "start_verse_id"
            case endVerseID = "end_verse_id"
            case durationMS = "duration_ms"
            case storagePath = "storage_path"
        }

        var recitation: MessagingOptions.Recitation {
            MessagingOptions.Recitation(
                id: id,
                startVerseID: startVerseID,
                endVerseID: endVerseID,
                durationMS: durationMS,
                storagePath: storagePath
            )
        }
    }

    /// `hideMessageForMe` — `src/services/social.ts:144`. Masque un message pour
    /// **moi seul** : la ligne reste, mais `listMessages` la retire.
    public func hideMessage(messageID: String, myID: String, accessToken: String) async throws {
        try await client.upsert(
            table: "friend_message_hidden",
            row: ["message_id": messageID, "user_id": myID],
            onConflict: "message_id,user_id",
            accessToken: accessToken
        )
    }

    /// `markConversationRead` — `src/services/social.ts:148`. Écrit la marque de
    /// lecture à **maintenant**, en millisecondes entières (`MessagingOptions.readStamp`).
    public func markConversationRead(linkID: String, myID: String, now: Date, accessToken: String) async throws {
        try await client.upsert(
            table: "friend_message_reads",
            row: [
                "link_id": linkID,
                "user_id": myID,
                "last_read_at": MessagingOptions.readStamp(now: now)
            ],
            onConflict: "link_id,user_id",
            accessToken: accessToken
        )
    }

    /// `otherReadAt` — `src/services/social.ts:152`. La marque de lecture de
    /// **l'autre**, qui décide de l'affichage « vu ».
    public func otherReadAt(linkID: String, otherID: String, accessToken: String) async throws -> String? {
        let value = try await client.maybeSingle(
            table: "friend_message_reads",
            query: [
                URLQueryItem(name: "select", value: "last_read_at"),
                URLQueryItem(name: "link_id", value: "eq.\(linkID)"),
                URLQueryItem(name: "user_id", value: "eq.\(otherID)")
            ],
            accessToken: accessToken
        )
        return value?["last_read_at"]?.stringValue
    }

    /// `sendMessage` — `src/services/social.ts:157`. Le corps est **détouré**
    /// avant l'envoi (`MessagingOptions.outgoing`), et la pièce est posée en
    /// `null` pour l'autre colonne : un message appartient à **une** pièce.
    public func sendMessage(room: MessagingOptions.Room, body: String, kind: MessagingOptions.Kind = .text, myID: String, accessToken: String) async throws {
        if kind == .recitation {
            throw SocialError(message: "Un partage de récitation passe par shareRecitation.")
        }
        try await client.insert(
            table: "friend_messages",
            row: [
                "link_id": room.column == "link_id" ? room.value : NSNull(),
                "group_id": room.column == "group_id" ? room.value : NSNull(),
                "sender_id": myID,
                "body": MessagingOptions.outgoing(body),
                "kind": kind.rawValue
            ],
            accessToken: accessToken
        )
    }

    /// `shareRecitation` — `src/services/social.ts:162`. Un partage va
    /// **toujours** dans une conversation à deux (`group_id: null`) et sa
    /// description est bornée à 2 000 unités UTF-16.
    public func shareRecitation(linkID: String, recitationID: String, description: String, myID: String, accessToken: String) async throws {
        try await client.insert(
            table: "friend_messages",
            row: [
                "link_id": linkID,
                "group_id": NSNull(),
                "sender_id": myID,
                "kind": MessagingOptions.Kind.recitation.rawValue,
                "recitation_id": recitationID,
                "body": MessagingOptions.sharedDescription(description)
            ],
            accessToken: accessToken
        )
    }

    /// `conversationSummaries` — `src/services/social.ts:166`.
    ///
    /// Une seule requête pour tous les **derniers** messages, une autre pour les
    /// marques de lecture, puis un décompte de non-lus **par conversation**.
    /// Les trois décisions (premier message gagnant, message supprimé, décompte
    /// qui crée le résumé) vivent dans `MessagingOptions.summaries`, où elles
    /// sont mesurables sans réseau.
    public func conversationSummaries(linkIDs: [String], myID: String, now: Date, accessToken: String) async throws -> [String: MessagingOptions.Summary] {
        guard !linkIDs.isEmpty else { return [:] }
        let list = linkIDs.joined(separator: ",")
        let mine = try await client.select(
            table: "friend_message_reads",
            query: [
                URLQueryItem(name: "select", value: "link_id,user_id,last_read_at"),
                URLQueryItem(name: "link_id", value: "in.(\(list))")
            ],
            accessToken: accessToken
        )
        let readRows: [ReadRow] = try decodeArray(mine)
        let readAt = Dictionary(
            uniqueKeysWithValues: readRows.filter { $0.userId == myID }.map { ($0.linkId, $0.lastReadAt) }
        )

        // Le décompte des non-lus, conversation par conversation. Une requête
        // par conversation, comme l'original : c'est un `count:exact` en en-tête.
        var unread: [String: Int] = [:]
        for linkID in linkIDs {
            var query = [
                URLQueryItem(name: "select", value: "id"),
                URLQueryItem(name: "link_id", value: "eq.\(linkID)"),
                URLQueryItem(name: "sender_id", value: "neq.\(myID)"),
                URLQueryItem(name: "deleted_at", value: "is.null")
            ]
            if let stamp = readAt[linkID] {
                query.append(URLQueryItem(name: "created_at", value: "gt.\(stamp)"))
            }
            let count = try await client.count(table: "friend_messages", query: query, accessToken: accessToken)
            if count > 0 { unread[linkID] = count }
        }

        let recent = try await client.select(
            table: "friend_messages",
            query: [
                URLQueryItem(name: "select", value: "link_id,body,created_at,sender_id,deleted_at"),
                URLQueryItem(name: "link_id", value: "in.(\(list))"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: String(MessagingOptions.summaryLimit))
            ],
            accessToken: accessToken
        )
        let recentRows: [SummaryRow] = try decodeArray(recent)
        return MessagingOptions.summaries(
            messages: recentRows.map {
                (linkID: $0.linkId, body: $0.body, createdAt: $0.createdAt, isDeleted: $0.deletedAt != nil)
            },
            unreadCounts: unread,
            now: now
        )
    }

    /// La ligne de `friend_message_reads` utilisée par les résumés.
    private struct ReadRow: Codable {
        var linkId: String
        var userId: String
        var lastReadAt: String

        enum CodingKeys: String, CodingKey {
            case linkId = "link_id"
            case userId = "user_id"
            case lastReadAt = "last_read_at"
        }
    }

    /// La ligne de `friend_messages` utilisée par les résumés.
    private struct SummaryRow: Codable {
        var linkId: String
        var body: String
        var createdAt: String
        var senderId: String
        var deletedAt: String?

        enum CodingKeys: String, CodingKey {
            case linkId = "link_id"
            case body
            case createdAt = "created_at"
            case senderId = "sender_id"
            case deletedAt = "deleted_at"
        }
    }

    /// `deleteMessage` / `reportMessage` — `src/services/social.ts:186-187`.
    /// Les deux passent par une fonction, jamais par une écriture directe : la
    /// suppression est **douce**, et seul le serveur sait qui a le droit.
    public func deleteMessage(messageID: String, accessToken: String) async throws {
        _ = try await client.rpc("delete_friend_message", parameters: ["p_message": messageID], accessToken: accessToken)
    }

    public func reportMessage(messageID: String, reason: String, accessToken: String) async throws {
        _ = try await client.rpc(
            "report_friend_message",
            parameters: ["p_message": messageID, "p_reason": reason],
            accessToken: accessToken
        )
    }

    /// `listGroupReports` — `src/services/social.ts:188`.
    public func groupReports(groupID: String, accessToken: String) async throws -> [MessageReport] {
        let messages = try await messages(room: .group(groupID), accessToken: accessToken)
        guard !messages.isEmpty else { return [] }
        let value = try await client.select(
            table: "friend_message_reports",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "message_id", value: "in.(\(messages.map(\.id).joined(separator: ",")))"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    // MARK: Groupes

    /// `listGroups` — `src/services/social.ts:120`.
    public func groups(accessToken: String) async throws -> [FriendGroup] {
        let value = try await client.select(
            table: "friend_groups",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    /// `listGroupMembers` — `src/services/social.ts:121`. Les membres, puis leurs
    /// profils en **un** aller-retour, réunis par identifiant.
    public func groupMembers(groupID: String, accessToken: String) async throws -> [GroupMember] {
        let value = try await client.select(
            table: "friend_group_members",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "group_id", value: "eq.\(groupID)")
            ],
            accessToken: accessToken
        )
        var members: [GroupMember] = try decodeArray(value)
        guard !members.isEmpty else { return [] }
        let profileValue = try await client.select(
            table: "friend_profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(members.map(\.userId).joined(separator: ",")))")
            ],
            accessToken: accessToken
        )
        let profiles: [FriendProfile] = try decodeArray(profileValue)
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        for index in members.indices {
            members[index].profile = byID[members[index].userId]
        }
        return members
    }

    public func createGroup(name: String, accessToken: String) async throws -> String {
        let value = try await client.rpc("create_friend_group", parameters: ["p_name": name], accessToken: accessToken)
        return value.stringValue ?? ""
    }

    public func inviteGroupMember(groupID: String, friendID: String, accessToken: String) async throws {
        _ = try await client.rpc("invite_group_member", parameters: ["p_group": groupID, "p_friend": friendID], accessToken: accessToken)
    }

    public func acceptGroupInvite(groupID: String, accessToken: String) async throws {
        _ = try await client.rpc("accept_group_invite", parameters: ["p_group": groupID], accessToken: accessToken)
    }

    public func declineGroupInvite(groupID: String, accessToken: String) async throws {
        _ = try await client.rpc("decline_group_invite", parameters: ["p_group": groupID], accessToken: accessToken)
    }

    public func setGroupModerator(groupID: String, memberID: String, enabled: Bool, accessToken: String) async throws {
        _ = try await client.rpc(
            "set_group_moderator",
            parameters: ["p_group": groupID, "p_member": memberID, "p_enabled": enabled],
            accessToken: accessToken
        )
    }

    public func removeGroupMember(groupID: String, memberID: String, accessToken: String) async throws {
        _ = try await client.rpc("remove_group_member", parameters: ["p_group": groupID, "p_member": memberID], accessToken: accessToken)
    }

    public func deleteGroup(groupID: String, accessToken: String) async throws {
        _ = try await client.rpc("delete_friend_group", parameters: ["p_group": groupID], accessToken: accessToken)
    }

    // MARK: Objectifs partagés et rendez-vous

    /// `listSharedGoals` — `src/services/social.ts:191`. Les huit dernières
    /// semaines proposées, de la plus récente à la plus ancienne.
    public func sharedGoals(linkID: String, accessToken: String) async throws -> [SharedGoal] {
        let value = try await client.select(
            table: "friend_shared_goals",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "link_id", value: "eq.\(linkID)"),
                URLQueryItem(name: "order", value: "week_start.desc"),
                URLQueryItem(name: "limit", value: "8")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    public func proposeSharedGoal(linkID: String, weekStart: String, target: Int, myID: String, accessToken: String) async throws {
        try await client.insert(
            table: "friend_shared_goals",
            row: [
                "link_id": linkID,
                "week_start": weekStart,
                "target_sessions": target,
                "proposed_by": myID
            ],
            accessToken: accessToken
        )
    }

    public func acceptSharedGoal(goalID: String, accessToken: String) async throws {
        _ = try await client.rpc("accept_shared_goal", parameters: ["p_goal": goalID], accessToken: accessToken)
    }

    /// `listAppointments` — `src/services/social.ts:196`. Seulement les
    /// rendez-vous **à venir** : la borne est l'instant présent, injecté.
    public func appointments(linkID: String, now: Date, accessToken: String) async throws -> [ReviewAppointment] {
        let value = try await client.select(
            table: "friend_review_appointments",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "link_id", value: "eq.\(linkID)"),
                URLQueryItem(name: "starts_at", value: "gte.\(DateKeys.iso(now))"),
                URLQueryItem(name: "order", value: "starts_at"),
                URLQueryItem(name: "limit", value: "20")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    public func proposeAppointment(linkID: String, startsAt: String, myID: String, accessToken: String) async throws {
        try await client.insert(
            table: "friend_review_appointments",
            row: ["link_id": linkID, "starts_at": startsAt, "proposed_by": myID],
            accessToken: accessToken
        )
    }

    public func acceptAppointment(appointmentID: String, accessToken: String) async throws {
        _ = try await client.rpc("accept_review_appointment", parameters: ["p_appointment": appointmentID], accessToken: accessToken)
    }

    public func cancelAppointment(appointmentID: String, accessToken: String) async throws {
        _ = try await client.rpc("cancel_review_appointment", parameters: ["p_appointment": appointmentID], accessToken: accessToken)
    }

    // MARK: Modération

    /// `isSocialAdmin` — `src/services/social.ts:203`.
    public func isSocialAdmin(myID: String, accessToken: String) async throws -> Bool {
        let value = try await client.maybeSingle(
            table: "app_admins",
            query: [
                URLQueryItem(name: "select", value: "user_id"),
                URLQueryItem(name: "user_id", value: "eq.\(myID)")
            ],
            accessToken: accessToken
        )
        return value != nil
    }

    /// `mySocialSuspension` — `src/services/social.ts:207`.
    public func mySuspension(userID: String, accessToken: String) async throws -> SocialSuspension? {
        let value = try await client.maybeSingle(
            table: "social_suspensions",
            query: [
                URLQueryItem(name: "select", value: "user_id,reason,suspended_until,created_at"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)")
            ],
            accessToken: accessToken
        )
        guard let value else { return nil }
        return try decode(value)
    }

    /// `listAdminReports` — `src/services/social.ts:211`. Les signalements
    /// **ouverts** seulement.
    public func adminReports(accessToken: String) async throws -> [MessageReport] {
        let value = try await client.select(
            table: "friend_message_reports",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "status", value: "eq.open"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "100")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    public func adminMessages(accessToken: String) async throws -> [ChatMessage] {
        let value = try await client.select(
            table: "friend_messages",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "100")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    /// `adminProfiles` — `src/services/social.ts:217`. Les identifiants sont
    /// **dédoublonnés** avant la requête : `[...new Set(ids)]` de l'original.
    public func adminProfiles(ids: [String], accessToken: String) async throws -> [FriendProfile] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }
        let value = try await client.select(
            table: "friend_profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(unique.joined(separator: ",")))")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    public func socialSuspensions(accessToken: String) async throws -> [SocialSuspension] {
        let value = try await client.select(
            table: "social_suspensions",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ],
            accessToken: accessToken
        )
        return try decodeArray(value)
    }

    public func resolveReport(reportID: String, accessToken: String) async throws {
        _ = try await client.rpc("resolve_friend_report", parameters: ["p_report": reportID], accessToken: accessToken)
    }

    /// `suspendMember` — `src/services/social.ts:231`. `until` est une chaîne ISO
    /// ou `nil` : la suspension est alors **sans terme**, et c'est `NSNull` que
    /// PostgREST reçoit, pas l'absence de clé.
    public func suspendMember(userID: String, reason: String, until: String?, accessToken: String) async throws {
        _ = try await client.rpc(
            "suspend_social_member",
            parameters: ["p_user": userID, "p_reason": reason, "p_until": until ?? NSNull()],
            accessToken: accessToken
        )
    }

    public func unsuspendMember(userID: String, accessToken: String) async throws {
        _ = try await client.rpc("unsuspend_social_member", parameters: ["p_user": userID], accessToken: accessToken)
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

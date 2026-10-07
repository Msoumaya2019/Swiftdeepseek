// FriendsView.swift
// Onglet Amis.
//
// Correspondance : le composant `FriendsScreen` de `src/SocialScreens.tsx`.
//
// Cette première étape couvre ce qui permet de retrouver ses amis et son code
// d'invitation. La messagerie, les groupes, les objectifs partagés et les
// rendez-vous de révision viendront ensuite — ils utilisent les mêmes tables et
// les mêmes fonctions que l'application React Native, donc les deux clients
// resteront compatibles au fur et à mesure (voir `SWIFT_MIGRATION.md`).
//
// Rien n'est créé côté Supabase : le profil social est obtenu par la fonction
// `ensure_social_profile`, exactement celle qu'appelle l'application actuelle.

import SwiftUI

public struct FriendsView: View {

    @EnvironmentObject private var model: AppViewModel
    @State private var rows: [FriendRow] = []
    @State private var inbox: [String: FriendInboxRow] = [:]
    @State private var profile: FriendProfile?
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var infoText: String?
    @State private var openRoom: OpenRoom?

    /// La pièce ouverte, ou rien. L'original décide par `selected` — `null`
    /// veut dire « la liste ». Ici c'est une valeur **présentée**, ce qui laisse
    /// SwiftUI empiler l'écran et le désempiler d'un geste, sans `useEffect` de
    /// navigation.
    private struct OpenRoom: Identifiable, Hashable {
        let id: String
        let room: MessagingOptions.Room
        let name: String
        let accessToken: String

        static func == (lhs: OpenRoom, rhs: OpenRoom) -> Bool { lhs.id == rhs.id }

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HeroHeader(title: "Mes amis", subtitle: "Révisez et encouragez-vous ensemble.")
                    profileCard
                    addFriendCard
                    requestsSection
                    friendsSection
                    comingSoonCard
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(model.palette.cream)
            .navigationTitle("Amis")
            .refreshable { await load() }
            .task { await load() }
            .navigationDestination(item: $openRoom) { open in
                MessagingView(
                    room: open.room,
                    title: open.name,
                    isAdminContact: false,
                    myID: myID ?? "",
                    accessToken: open.accessToken,
                    onUnreadChange: { Task { await load() } },
                    shareText: shareText
                )
            }
        }
    }

    /// Le texte que l'ami reçoit quand on partage volontairement son étape.
    /// L'original le fabrique dans `App.tsx` et le passe à `FriendsScreen`.
    private var shareText: String { "" }

    private var myID: String? { model.auth.userId }

    // MARK: Mon code d'invitation

    private var profileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Mon code d'invitation")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
                HStack(spacing: Theme.Spacing.md) {
                    Text(profile?.inviteCode ?? (inviteCode.isEmpty ? "—" : inviteCode))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(model.palette.green)
                    Spacer()
                    if let code = profile?.inviteCode, !code.isEmpty {
                        ShareLink(item: "Rejoins-moi sur l'application de mémorisation du Coran. Mon code : \(code)") {
                            Label("Partager", systemImage: "square.and.arrow.up")
                                .font(.system(size: Theme.Typography.secondary, weight: .semibold))
                        }
                        .foregroundStyle(model.palette.green)
                    }
                }
                if let name = profile?.displayName, !name.isEmpty {
                    Text("Visible sous le nom « \(name) »")
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                }
            }
        }
    }

    // MARK: Ajouter un ami

    private var addFriendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Ajouter un ami")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Code d'invitation", text: $inviteCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: Theme.Typography.body, design: .monospaced))
                        .padding(Theme.Spacing.sm)
                        .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    Button("Envoyer") {
                        Task { await sendRequest() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.palette.green)
                    .disabled(inviteCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Text(errorText)
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.red)
                }
                if let infoText {
                    Text(infoText)
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.green)
                }
            }
        }
    }

    // MARK: Demandes reçues

    @ViewBuilder
    private var requestsSection: some View {
        let incoming = rows.filter { $0.isIncomingRequest(myID: myID ?? "") }
        if !incoming.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Demandes reçues")
                        .font(.system(size: Theme.Typography.card, weight: .semibold))
                    ForEach(incoming) { row in
                        HStack(spacing: Theme.Spacing.sm) {
                            avatar(row)
                            Text(row.other?.displayName ?? "Compte inconnu")
                                .font(.system(size: Theme.Typography.body, weight: .medium))
                            Spacer()
                            Button("Accepter") {
                                Task { await act { try await accept(row) } }
                            }
                            .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                            .foregroundStyle(model.palette.green)
                            Button("Refuser") {
                                Task { await act { try await decline(row) } }
                            }
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        }
                        .frame(minHeight: 48)
                    }
                }
            }
        }
    }

    // MARK: Mes amis

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Mes amis")
            let accepted = rows.filter(\.isAccepted)
            if isLoading && accepted.isEmpty {
                Card { EmptyLabel(text: "Chargement…") }
            } else if accepted.isEmpty {
                Card { EmptyLabel(text: "Aucun ami pour le moment. Partage ton code d'invitation.") }
            } else {
                ForEach(accepted) { row in
                    Card {
                        Button {
                            open(link: row)
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                avatar(row)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.other?.displayName ?? "Compte inconnu")
                                        .font(.system(size: Theme.Typography.body, weight: .semibold))
                                    Text(lastMessage(for: row))
                                        .font(.system(size: Theme.Typography.metadata))
                                        .foregroundStyle(model.palette.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let badge = MessagingOptions.unreadBadge(inbox[row.id]?.unreadCount ?? 0) {
                                    Text(badge)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(model.palette.paper)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(model.palette.green, in: Capsule())
                                }
                            }
                            .frame(minHeight: 56)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let outgoing = rows.filter { $0.isOutgoingRequest(myID: myID ?? "") }
            if !outgoing.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Demandes envoyées")
                            .font(.system(size: Theme.Typography.card, weight: .semibold))
                        ForEach(outgoing) { row in
                            HStack {
                                Text(row.other?.displayName ?? "En attente de réponse")
                                    .font(.system(size: Theme.Typography.body))
                                Spacer()
                                Text("En attente")
                                    .font(.system(size: Theme.Typography.metadata))
                                    .foregroundStyle(model.palette.muted)
                            }
                            .frame(minHeight: 40)
                        }
                    }
                }
            }
        }
    }

    private var comingSoonCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("À venir")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                Text("La messagerie, les groupes, les objectifs partagés, les rendez-vous de révision et les quiz entre amis arrivent aux étapes suivantes. Ils s'appuieront sur les mêmes tables et les mêmes fonctions que l'application actuelle, donc tes conversations et tes amis seront bien les mêmes des deux côtés.")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
            }
        }
    }

    // MARK: Sous-vues

    private func avatar(_ row: FriendRow) -> some View {
        let name = row.other?.displayName ?? "?"
        let letter = String(name.first ?? "?").uppercased()
        let online = inbox[row.id]?.isOnline ?? false
        return ZStack(alignment: .bottomTrailing) {
            Text(letter)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(model.palette.green)
                .frame(width: 42, height: 42)
                .background(model.palette.selected, in: Circle())
            if online {
                Circle()
                    .fill(model.palette.green)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(model.palette.paper, lineWidth: 2))
            }
        }
    }

    private func lastMessage(for row: FriendRow) -> String {
        guard let entry = inbox[row.id] else { return "Aucun message" }
        if entry.unreadCount > 0 { return "\(entry.unreadCount) message(s) non lu(s)" }
        return entry.body ?? "Aucun message"
    }

    // MARK: Actions

    private func open(link row: FriendRow) async {
        guard let token = await model.socialAccessToken() else { return }
        openRoom = OpenRoom(
            id: row.id,
            room: .link(row.id),
            name: row.other?.displayName ?? "Ami",
            accessToken: token
        )
    }

    private func open(link row: FriendRow) {
        Task { await open(link: row) }
    }

    private func load() async {
        guard let myID, let token = await model.socialAccessToken() else {
            errorText = "Connecte-toi pour utiliser les amis."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await model.social.ensureProfile(accessToken: token)
            rows = try await model.social.rows(myID: myID, accessToken: token)
            let accepted = rows.filter(\.isAccepted)
            if !accepted.isEmpty {
                let entries = try await model.social.inbox(accessToken: token)
                // Construction manuelle : `Dictionary(uniqueKeysWithValues:)`
                // s'interrompt sur une clé dupliquée, et une réponse serveur ne
                // doit jamais faire planter l'écran.
                var map: [String: FriendInboxRow] = [:]
                for entry in entries { map[entry.linkId] = entry }
                inbox = map
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func sendRequest() async {
        guard let token = await model.socialAccessToken() else { return }
        let code = inviteCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        await act {
            try await model.social.requestFriend(code: code, accessToken: token)
            inviteCode = ""
            infoText = "Demande envoyée."
        }
    }

    private func accept(_ row: FriendRow) async throws {
        guard let token = await model.socialAccessToken() else { return }
        try await model.social.acceptFriend(linkID: row.id, accessToken: token)
    }

    private func decline(_ row: FriendRow) async throws {
        guard let token = await model.socialAccessToken() else { return }
        try await model.social.declineFriend(linkID: row.id, accessToken: token)
    }

    private func open(link row: FriendRow) {
        Task { await open(link: row) }
    }

    private func act(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

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
    /// La pile de navigation de l'onglet. Vide = la liste d'amis.
    ///
    /// L'original décide par `selected` — `null` veut dire « la liste ». Ici
    /// c'est le **chemin** qui le dit, et SwiftUI empile/désempile l'écran d'un
    /// geste, sans `useEffect` de navigation.
    @State private var path: [Route] = []

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HeroHeader(title: "Mes amis", subtitle: "Révisez et encouragez-vous ensemble.")
                    profileCard
                    addFriendCard
                    requestsSection
                    friendsSection
                    circlesCard
                    comingSoonCard
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(model.palette.cream)
            .navigationTitle("Amis")
            .refreshable { await load() }
            .task { await load() }
            // `navigationDestination(item:)` n'existe qu'à partir d'iOS 17, et
            // la cible du projet est iOS 16 (`project.yml:23`). On passe donc
            // par la forme iOS 16 : un `NavigationLink(value:)` invisible
            // déclenché par un chemin, plus `navigationDestination(for:)`.
            //
            // Le chemin porte les DEUX destinations possibles, parce qu'un
            // `NavigationStack` n'accepte qu'un `navigationDestination(for:)`
            // par type — d'où l'énumération plutôt que deux `Bool`.
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .room(id, name, token):
                    MessagingView(
                        room: id,
                        title: name,
                        isAdminContact: false,
                        myID: myID ?? "",
                        accessToken: token,
                        onUnreadChange: { Task { await load() } },
                        shareText: shareText
                    )
                case let .circles(token):
                    CirclesView(
                        myID: myID ?? "",
                        accessToken: token,
                        onUnreadChange: { Task { await load() } }
                    )
                }
            }
        }
    }

    /// Les destinations de la pile d'amis.
    ///
    /// Le jeton est obtenu **à l'ouverture** (`circlesToken`), pas au rendu :
    /// c'est pour cela que la route le porte, plutôt que de le relire dans la
    /// destination — une destination ne peut pas `await` à la construction.
    enum Route: Hashable {
        case room(MessagingOptions.Room, String, String)
        case circles(String)
    }

    /// Le texte que l'ami reçoit quand on partage volontairement son étape.
    /// L'original le fabrique dans `App.tsx` et le passe à `FriendsScreen`.
    private var shareText: String { "" }

    // MARK: Cercles privés

    /// La porte d'entrée des cercles.
    ///
    /// Elle vit **dans** la liste d'amis, à la place exacte où l'original
    /// l'ouvre (`SocialScreens.tsx:196` : « Cercles privés · 3 à 5 personnes »).
    /// L'écran des cercles a besoin du jeton : on ne l'obtient qu'à l'ouverture,
    /// d'où une navigation par **état** — et non un `NavigationLink` qui
    /// n'aurait pas le jeton au moment de construire la destination.
    private var circlesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Cercles privés · 3 à 5 personnes")
                    .font(.system(size: Theme.Typography.subhead, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                Text("Apprenez ensemble dans un petit groupe : un fil partagé, et chacun garde son programme.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
                CardButton(title: circlesToken == nil ? "Ouverture…" : "Ouvrir mes cercles",
                           disabled: circlesToken == nil) {
                    if let token = circlesToken { path.append(.circles(token)) }
                }
            }
        }
    }

    /// Le jeton, obtenu une fois au chargement de l'écran. `nil` tant qu'il
    /// n'est pas là : le bouton reste éteint plutôt que d'ouvrir un écran sans
    /// réseau.
    @State private var circlesToken: String?

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
                // La messagerie et les cercles ne sont PLUS « à venir » : ils
                // sont portés. Laisser la phrase d'origine aurait annoncé comme
                // futur ce que l'écran ouvre déjà — le genre de mensonge qu'un
                // simple `grep` ne voit pas, mais que l'utilisateur lit.
                Text("Les objectifs partagés, les rendez-vous de révision, les récitations entre amis et les quiz arrivent aux étapes suivantes. Ils s'appuieront sur les mêmes tables et les mêmes fonctions que l'application actuelle, donc tes conversations et tes amis seront bien les mêmes des deux côtés.")
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

    // Une seule déclaration pour ce nom. Le bouton est SYNCHRONE et ne peut pas
    // `await` : il ouvre la tâche. La partie asynchrone porte donc un autre nom
    // — `ouvrirLaConversation` — sinon les deux surcharges porteraient le même
    // libellé et Swift refuserait le fichier (« invalid redeclaration »). C'est
    // exactement ce que la CI a signalé, et le banc le mesure désormais.
    private func ouvrirLaConversation(_ row: FriendRow) async {
        guard let token = await model.socialAccessToken() else { return }
        // Le jeton est obtenu ICI — c'est tout l'intérêt de la fonction
        // asynchrone : sans lui, la route ne peut pas être construite.
        path.append(.room(.link(row.id), row.other?.displayName ?? "Ami", token))
    }

    private func open(link row: FriendRow) {
        Task { await ouvrirLaConversation(row) }
    }

    private func load() async {
        guard let myID, let token = await model.socialAccessToken() else {
            errorText = "Connecte-toi pour utiliser les amis."
            return
        }
        circlesToken = token
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

    private func act(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

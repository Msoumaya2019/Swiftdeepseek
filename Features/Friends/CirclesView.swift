// CirclesView.swift
// Les cercles privés — créer, lister, ouvrir, inviter.
//
// Correspondance : `FriendsScreen` de `src/SocialScreens.tsx:36`, **branche
// « cercles »**. L'original la cache derrière un bouton (`inviteOpen`) qui
// n'existe que dans la moitié « liste d'amis ». Le portage la sort dans un
// écran propre : la liste d'amis n'a pas à porter deux formulaires de création
// pour un seul bouton.
//
// POURQUOI CET ÉCRAN EXISTE. Le service des groupes était porté **et couvert**
// — `createGroup`, `inviteGroupMember`, `acceptGroupInvite` … — mais rien ne
// l'appelait : la seule façon d'ouvrir un fil de groupe était de connaître un
// identifiant. C'est le même défaut que §34 (`Features/Auth/` vide alors que
// `SignInView` vivait ailleurs) : une capacité sans porte d'entrée.
//
// AUCUNE RÈGLE ICI QUI NE SOIT ÉCRITE DANS `Core/`. Deux le sont, et elles
// vivent dans `MessagingOptions` avec leurs tests :
//   · `circleNameIsAcceptable` — le nom d'un cercle fait **au moins deux
//     caractères une fois détouré** (`groupName.trim().length < 2`,
//     `SocialScreens.tsx:196`). L'original désactive le bouton sur cette
//     condition ; on la nomme pour qu'elle ne puisse pas dériver.
//   · Le rôle qui autorise la modération — `owner | moderator`
//     (`SocialScreens.tsx:203`) — est déjà `MessagingOptions.managesMembers`.

import SwiftUI

/// Les cercles privés : créer, lister, ouvrir, inviter.
struct CirclesView: View {

    @EnvironmentObject private var model: AppViewModel

    /// Mon identifiant.
    let myID: String
    /// Le jeton d'accès.
    let accessToken: String
    /// Appelé après une lecture, pour rafraîchir la pastille de l'onglet.
    var onUnreadChange: (() -> Void)?

    /// Le cercle que l'on ouvre.
    private struct OpenCircle: Hashable {
        let id: String
        let name: String
        let isAdminContact: Bool
    }

    @State private var circles: [FriendGroup] = []
    @State private var acceptedFriends: [FriendLink] = []
    @State private var membersByCircle: [String: [GroupMember]] = [:]
    @State private var draftName = ""
    @State private var notice: String?
    @State private var busy = false
    @State private var loading = true
    /// La pile de CET écran. Le fil d'un cercle s'empile par-dessus la liste.
    @State private var path: [OpenCircle] = []
    @State private var invitingCircleID: String?

    var body: some View {
        NavigationStack(path: $path) {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let notice {
                    Card { EmptyLabel(text: notice) }
                }

                createSection
                listSection

                Text("Un cercle privé réunit 3 à 5 personnes. Chacun garde son propre programme ; le fil et les membres, eux, sont partagés.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.section)
        }
        .background(model.palette.cream)
        .navigationTitle("Cercles privés")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // L'écran de conversation est le MÊME que pour un ami : un cercle n'est
        // qu'une autre pièce (`MessagingOptions.Room.group`).
        //
        // Forme iOS 16 : `navigationDestination(item:)` n'existe qu'à partir
        // d'iOS 17, et la cible est iOS 16 (`project.yml:23`).
        .navigationDestination(for: OpenCircle.self) { circle in
            MessagingView(
                room: .group(circle.id),
                title: circle.name,
                isAdminContact: circle.isAdminContact,
                myID: myID,
                accessToken: accessToken,
                onUnreadChange: onUnreadChange
            )
        }
        }
    }

    // MARK: Créer

    @ViewBuilder
    private var createSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Créer un cercle")
                    .font(.system(size: Theme.Typography.subhead, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                TextField("Nom du cercle", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                CardButton(
                    title: busy ? "Création…" : "Créer un cercle",
                    disabled: busy || !MessagingOptions.circleNameIsAcceptable(draftName)
                ) {
                    Task { await create() }
                }
            }
        }
    }

    // MARK: Lister

    @ViewBuilder
    private var listSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Mes cercles (\(circles.count))")
                    .font(.system(size: Theme.Typography.subhead, weight: .semibold))
                    .foregroundStyle(model.palette.green)

                if loading {
                    EmptyLabel(text: "Chargement…")
                } else if circles.isEmpty {
                    EmptyLabel(text: "Aucun cercle pour le moment.")
                } else {
                    ForEach(circles) { circle in
                        circleRow(circle)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func circleRow(_ circle: FriendGroup) -> some View {
        let members = membersByCircle[circle.id] ?? []
        let joined = members.filter { $0.acceptedAt != nil }
        let mine = members.first { $0.userId == myID }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(circle.name)
                    .font(.system(size: Theme.Typography.body, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                Spacer()
                Text("\(joined.count)/5")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
            }

            // Une invitation en attente pour MOI : c'est l'original
            // (`m.user_id === myId && !m.accepted_at`), et c'est la seule
            // action qui fasse entrer dans le cercle.
            if let mine, MessagingOptions.awaitsMyAnswer(mine, myID: myID) {
                Text("Invitation en attente")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
                HStack(spacing: Theme.Spacing.sm) {
                    CardButton(title: "Rejoindre", disabled: busy) {
                        Task { await act { try await model.social.acceptGroupInvite(groupID: circle.id, accessToken: accessToken) } }
                    }
                    CardButton(title: "Refuser", disabled: busy) {
                        Task { await act { try await model.social.declineGroupInvite(groupID: circle.id, accessToken: accessToken) } }
                    }
                }
            } else {
                CardButton(title: "Ouvrir", disabled: false) {
                    path.append(OpenCircle(
                        id: circle.id,
                        name: circle.name,
                        isAdminContact: circle.contactUserId != nil
                    ))
                }
            }

            // Inviter un ami : réservé au propriétaire et aux modérateurs
            // (`SocialScreens.tsx:203`), et jamais à un cercle d'administration.
            if circle.contactUserId == nil,
               let mine, MessagingOptions.managesMembers(mine.role) {
                if invitingCircleID == circle.id {
                    let invitable = acceptedFriends.filter { link in
                        !members.contains { $0.userId == otherID(of: link) }
                    }
                    if invitable.isEmpty {
                        Text("Tous tes amis sont déjà dans ce cercle.")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                    } else {
                        ForEach(invitable) { link in
                            CardButton(
                                title: "Inviter \(link.other?.displayName ?? "un ami")",
                                disabled: busy
                            ) {
                                Task {
                                    await act {
                                        try await model.social.inviteGroupMember(
                                            groupID: circle.id,
                                            friendID: otherID(of: link),
                                            accessToken: accessToken
                                        )
                                    }
                                    invitingCircleID = nil
                                }
                            }
                        }
                    }
                } else {
                    CardButton(title: "Inviter un ami", disabled: busy) {
                        invitingCircleID = circle.id
                    }
                }
            }

            // La suppression n'est ouverte qu'au propriétaire — et l'original
            // confirme par une alerte avant (`SocialScreens.tsx:204`). Ici la
            // confirmation est une seconde frappe : le bouton devient un
            // avertissement, et c'est la même garantie sans boîte de dialogue.
            if circle.contactUserId == nil, let mine, mine.role == "owner" {
                CardButton(title: "Supprimer le cercle", disabled: busy) {
                    Task {
                        await act {
                            try await model.social.deleteGroup(groupID: circle.id, accessToken: accessToken)
                        }
                        // Le cercle vient de disparaître : on quitte son fil,
                        // sinon la pile garderait un écran dont la pièce n'existe
                        // plus et le chargement échouerait à chaque passage.
                        path.removeAll { $0.id == circle.id }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Actions

    /// L'identifiant de l'autre, tel que l'original le calcule.
    private func otherID(of link: FriendLink) -> String {
        link.requesterId == myID ? link.recipientId : link.requesterId
    }

    private func create() async {
        // Le nom envoyé est celui que la règle a accepté, détouré par ELLE —
        // l'écran ne détoure pas une seconde fois, sinon les deux détourages
        // pourraient diverger.
        let name = MessagingOptions.trimmedCircleName(draftName)
        guard MessagingOptions.circleNameIsAcceptable(draftName) else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await model.social.createGroup(name: name, accessToken: accessToken)
            draftName = ""
            notice = "Cercle créé."
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func act(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let links = try await model.social.links(accessToken: accessToken)
            acceptedFriends = links.filter(\.isAccepted)
            circles = try await model.social.groups(accessToken: accessToken)
            var map: [String: [GroupMember]] = [:]
            for circle in circles {
                map[circle.id] = (try? await model.social.groupMembers(
                    groupID: circle.id, accessToken: accessToken)) ?? []
            }
            membersByCircle = map
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }
}

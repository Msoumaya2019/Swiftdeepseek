// MessagingView.swift
// Le fil d'une conversation — avec un ami, ou dans un cercle privé.
//
// Correspondance : `FriendsScreen` de `src/SocialScreens.tsx:36`, **partie
// « conversation »** (à partir de `{selected ? …}`). La liste d'amis, elle, vit
// dans `FriendsView.swift` : l'original porte les deux dans un seul composant,
// mais la décision y est **un seul état** — `selected` vaut `null` (la liste)
// ou une pièce (le fil). Deux vues pilotées par un booléen donnent exactement
// le même écran, sans le `useEffect` de 40 lignes que l'original traîne.
//
// AUCUNE RÈGLE ICI. Tout ce qui décide est dans `Core/MessagingOptions.swift`
// et est couvert par `Tests/MessagingTests.swift` : la taille d'une page, la
// coupe de la description partagée en unités UTF-16, le corps d'un message
// supprimé, le filtre des messages masqués, le calcul d'une non-lecture, le
// libellé de chaque sorte, et le format d'une durée. La vue ne fait que
// **poser** ces décisions — c'est la condition pour que l'écran ne puisse pas
// diverger de l'application React Native sans qu'un test tombe.
//
// TROIS CHOSES QUE LA VUE NE DÉCIDE PAS, ET QUI SONT ÉCRITES ICI POUR MÉMOIRE :
//   · La page vaut `MessagingOptions.pageSize` (50). « Charger les précédents »
//     n'existe que si la dernière page était **pleine** — une page plus courte
//     est la fin du fil, et le redemander boucle.
//   · L'accusé de lecture compare des **horodatages ISO** en texte
//     (`MessagingOptions.isUnread`), jamais des `Date` : les deux applications
//     écrivent ces chaînes, et une comparaison de `Date` les réinterpréterait.
//   · Un message masqué n'est pas un message supprimé : le masquage est
//     **local à l'utilisateur** (`MessagingOptions.visible`).

import SwiftUI

/// Le fil d'une conversation.
struct MessagingView: View {

    @EnvironmentObject private var model: AppViewModel

    /// La pièce ouverte.
    let room: MessagingOptions.Room
    /// Le nom affiché dans la barre de titre.
    let title: String
    /// Vrai pour le contact administrateur : ni objectif, ni rendez-vous, ni
    /// outils — l'original les écarte par `!selected.adminContact`.
    let isAdminContact: Bool
    /// Mon identifiant.
    let myID: String
    /// Le jeton d'accès.
    let accessToken: String
    /// Appelé après une lecture, pour rafraîchir la pastille de l'onglet.
    var onUnreadChange: (() -> Void)?
    /// Le texte partagé volontairement — l'étape de progression de l'original.
    var shareText: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var members: [GroupMember] = []
    @State private var goals: [SharedGoal] = []
    @State private var appointments: [ReviewAppointment] = []
    @State private var suspension: SocialSuspension?
    @State private var draft = ""
    @State private var notice: String?
    @State private var busy = false
    @State private var hasOlder = false
    @State private var loadingOlder = false
    @State private var otherReadAt: String?
    @State private var reportTarget: String?
    @State private var reason = ""
    @State private var showTools = false
    @State private var targetSessions = "3"
    @State private var appointmentText = ""
    @State private var link: FriendLink?

    private var groupID: String? {
        if case let .group(id) = room { return id }
        return nil
    }

    private var linkID: String? {
        if case let .link(id) = room { return id }
        return nil
    }

    /// Ma suspension bloque-t-elle l'envoi ?
    /// L'original : `!!suspension && (!suspension.suspended_until || new Date(...) > new Date())`.
    /// Une suspension **sans date de fin** bloque indéfiniment — d'où le `nil`
    /// qui vaut « bloqué », et non « libre ».
    private var isSuspended: Bool {
        guard let suspension else { return false }
        guard let until = suspension.suspendedUntil, let when = DateKeys.parseISO(until) else { return true }
        return when > Date()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if let notice {
                        Card { EmptyLabel(text: notice) }
                    }
                    toolsSection
                    historySection
                    composerHooked(proxy)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.section)
            }
            .background(model.palette.cream)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadRoom(proxy: proxy) }
        }
    }

    // MARK: Outils — profil, objectifs, rendez-vous, membres

    @ViewBuilder
    private var toolsSection: some View {
        if !isAdminContact {
            CardButton(title: showTools ? "Masquer les options" : "Profil et entraide", secondary: true) {
                showTools.toggle()
            }
        }
        if !isAdminContact, showTools {
            if let link, linkID != nil {
                linkedTools(link: link)
            }
            if let groupID {
                groupTools(groupID: groupID)
            }
        }
    }

    @ViewBuilder
    private func linkedTools(link: FriendLink) -> some View {
        let other = link.requesterId == myID ? link.recipientId : link.requesterId

        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Objectif partagé")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                Text("Fixez ensemble un nombre de séances pour cette semaine. Chacun garde son propre programme.")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Séances cette semaine (1 à 14)", text: $targetSessions)
                        .keyboardType(.numberPad)
                        .padding(Theme.Spacing.sm)
                        .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    Button("Proposer") {
                        Task { await proposeGoal(linkID: link.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.palette.green)
                    // L'original n'active le bouton que si `Number.isInteger`.
                    // `Int("3.5")` rend `nil`, donc la même décision.
                    .disabled(busy || !MessagingOptions.isValidSessionCount(targetSessions))
                }
                ForEach(goals) { goal in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Semaine du \(goal.weekStart) · \(goal.targetSessions) séances")
                            .font(.system(size: Theme.Typography.secondary, weight: .medium))
                        Text(goal.acceptedAt != nil ? "Accepté par vous deux" : "En attente d'acceptation")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        if goal.acceptedAt == nil, goal.proposedBy != myID {
                            Button("Accepter") {
                                Task { await act { try await model.social.acceptSharedGoal(goalID: goal.id, accessToken: accessToken) } }
                            }
                            .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                            .foregroundStyle(model.palette.green)
                        }
                    }
                }
            }
        }

        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Rendez-vous de révision")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("AAAA-MM-JJ HH:mm", text: $appointmentText)
                        .autocorrectionDisabled()
                        .font(.system(size: Theme.Typography.body, design: .monospaced))
                        .padding(Theme.Spacing.sm)
                        .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    Button("Proposer") {
                        Task { await proposeAppointment(linkID: link.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.palette.green)
                    .disabled(busy)
                }
                ForEach(appointments) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DateKeys.dateTimeText(item.startsAt))
                            .font(.system(size: Theme.Typography.secondary, weight: .medium))
                        Text(item.acceptedAt != nil ? "Confirmé" : "En attente")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        HStack(spacing: Theme.Spacing.md) {
                            if item.acceptedAt == nil, item.proposedBy != myID {
                                Button("Accepter") {
                                    Task { await act { try await model.social.acceptAppointment(appointmentID: item.id, accessToken: accessToken) } }
                                }
                                .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                                .foregroundStyle(model.palette.green)
                            }
                            Button("Annuler") {
                                Task { await act { try await model.social.cancelAppointment(appointmentID: item.id, accessToken: accessToken) } }
                            }
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        }
                    }
                }
            }
        }

        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Mon correspondant")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                Text(other.isEmpty ? "Compte inconnu" : other)
                    .font(.system(size: Theme.Typography.metadata, design: .monospaced))
                    .foregroundStyle(model.palette.muted)
            }
        }
    }

    @ViewBuilder
    private func groupTools(groupID: String) -> some View {
        let accepted = members.filter { $0.acceptedAt != nil }
        let mine = members.first { $0.userId == myID }
        let canModerate = mine.map { ["owner", "moderator"].contains($0.role) } ?? false
        let isOwner = mine?.role == "owner"

        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Membres (\(accepted.count)/5)")
                    .font(.system(size: Theme.Typography.card, weight: .semibold))
                ForEach(members, id: \.userId) { member in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(member.profile?.displayName ?? "Membre") · \(member.role)\(member.acceptedAt == nil ? " · invitation en attente" : "")")
                            .font(.system(size: Theme.Typography.secondary))
                        HStack(spacing: Theme.Spacing.md) {
                            if member.acceptedAt == nil, member.userId == myID {
                                Button("Rejoindre") {
                                    Task { await act { try await model.social.acceptGroupInvite(groupID: groupID, accessToken: accessToken) } }
                                }
                                .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                                .foregroundStyle(model.palette.green)
                                Button("Refuser") {
                                    Task { await act { try await model.social.declineGroupInvite(groupID: groupID, accessToken: accessToken) } }
                                }
                                .font(.system(size: Theme.Typography.metadata))
                                .foregroundStyle(model.palette.muted)
                            }
                            if member.userId != myID, member.acceptedAt != nil, isOwner {
                                Button(member.role == "moderator" ? "Retirer la modération" : "Nommer modérateur") {
                                    Task {
                                        await act {
                                            try await model.social.setGroupModerator(
                                                groupID: groupID, memberID: member.userId,
                                                enabled: member.role != "moderator", accessToken: accessToken)
                                        }
                                    }
                                }
                                .font(.system(size: Theme.Typography.metadata))
                                .foregroundStyle(model.palette.muted)
                            }
                            if member.userId != myID, member.role != "owner", canModerate {
                                Button("Retirer du cercle") {
                                    Task { await act { try await model.social.removeGroupMember(groupID: groupID, memberID: member.userId, accessToken: accessToken) } }
                                }
                                .font(.system(size: Theme.Typography.metadata))
                                .foregroundStyle(model.palette.muted)
                            }
                        }
                    }
                    .frame(minHeight: 40)
                }
            }
        }
    }

    // MARK: Le fil

    @ViewBuilder
    private var historySection: some View {
        Text("Discussion")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(model.palette.green)
            .padding(.top, Theme.Spacing.sm)

        if hasOlder {
            CardButton(title: loadingOlder ? "Chargement…" : "Charger les messages précédents", secondary: true) {
                Task { await loadOlder() }
            }
        }

        if isSuspended, let suspension {
            Card { EmptyLabel(text: "Messagerie suspendue : \(suspension.reason)") }
        }

        ForEach(messages) { message in
            messageBubble(message)
        }

        if reportTarget != nil {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Signaler cette conversation à la modération")
                        .font(.system(size: Theme.Typography.secondary, weight: .medium))
                    TextField("Motif du signalement", text: $reason)
                        .padding(Theme.Spacing.sm)
                        .background(model.palette.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    Button("Envoyer") {
                        Task { await sendReport() }
                    }
                    .font(.system(size: Theme.Typography.metadata, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    Button("Annuler") { reportTarget = nil }
                        .font(.system(size: Theme.Typography.metadata))
                        .foregroundStyle(model.palette.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let mine = message.senderId == myID
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            Text("\(senderName(message.senderId)) · \(DateKeys.timeText(message.createdAt))")
                .font(.system(size: 11))
                .foregroundStyle(model.palette.muted)
            Text(message.body)
                .font(.system(size: Theme.Typography.body))
                .padding(Theme.Spacing.sm)
                .background(mine ? model.palette.soft : model.palette.paper,
                            in: RoundedRectangle(cornerRadius: 18))
            // La pièce jointe se reconnaît par la RÈGLE, jamais par un test de
            // chaîne écrit ici : `carriesRecitation` dit quelle sorte en porte
            // une, et c'est le même prédicat que `recitationIDs` emploie.
            if message.kindValue?.carriesRecitation == true {
                recitationCard(message)
            }
            if mine, linkID != nil {
                // L'accusé de lecture se compare en **texte**, sur des
                // horodatages ISO : c'est la règle de `MessagingOptions`.
                Text(otherReadAt.map { MessagingOptions.isRead(message.createdAt, at: $0) } == true ? "Lu" : "Envoyé")
                    .font(.system(size: 10))
                    .foregroundStyle(model.palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    /// La carte d'une récitation partagée — `SocialScreens.tsx:198`. Le titre
    /// est la **référence** du passage (sourate et versets), la durée vient de
    /// `MessagingOptions.durationText`, et une pièce absente est **dite** :
    /// « Enregistrement indisponible ». Un message de récitation sans pièce
    /// n'est pas un message ordinaire — c'est une pièce manquante.
    @ViewBuilder
    private func recitationCard(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.recitation.map { Quran.reference(start: $0.startVerseID, end: $0.endVerseID) }
                 ?? "Enregistrement indisponible")
                .font(.system(size: Theme.Typography.secondary, weight: .semibold))
            if let recitation = message.recitation {
                Text("Durée : \(MessagingOptions.durationText(recitation.durationMS))")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(model.palette.paper, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: La zone d'écriture

    @ViewBuilder
    private func composerHooked(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                TextField("Écris un message à tes amis…", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.system(size: Theme.Typography.body))
                    .padding(Theme.Spacing.sm)
                    .background(model.palette.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    // La borne de l'original est `maxLength={2000}` — mais elle
                    // compte en **unités UTF-16**, comme la description
                    // partagée. `String.count` compte des graphèmes : la vue
                    // n'impose donc **pas** de limite ici, et `send` refuse un
                    // corps hors bornes par `MessagingOptions.outgoing`, qui
                    // coupe au même endroit que le JavaScript.
                Button("Envoyer") {
                    Task { await send(proxy: proxy) }
                }
                .buttonStyle(.borderedProminent)
                .tint(model.palette.green)
                .disabled(busy || MessagingOptions.outgoing(draft).isEmpty || isSuspended)
            }
            if linkID != nil, !isAdminContact, !shareText.isEmpty {
                CardButton(title: "Partager volontairement mon étape", secondary: true) {
                    Task { await shareStep() }
                }
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: Actions

    private func senderName(_ id: String) -> String {
        if id == myID { return "Moi" }
        if let name = members.first(where: { $0.userId == id })?.profile?.displayName { return name }
        return "Membre"
    }

    private func loadRoom(proxy: ScrollViewProxy) async {
        do {
            let latest = try await model.social.messages(room: room, accessToken: accessToken)
            messages = merge(latest, into: messages)
            // Une page pleine veut dire « il y a peut-être plus vieux ».
            hasOlder = latest.count == MessagingOptions.pageSize
            if let last = messages.last {
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            if let linkID {
                try await model.social.markConversationRead(
                    linkID: linkID, myID: myID, now: Date(), accessToken: accessToken)
                onUnreadChange?()
                otherReadAt = try await model.social.otherReadAt(
                    linkID: linkID, otherID: otherID(), accessToken: accessToken)
            }
            if let groupID {
                members = try await model.social.groupMembers(groupID: groupID, accessToken: accessToken)
            } else if !isAdminContact {
                // L'original écarte ces deux lectures pour le contact
                // administrateur (`SocialScreens.tsx:104`) : ce n'est pas une
                // optimisation, c'est une règle — la conversation d'administration
                // n'a ni objectif partagé ni rendez-vous.
                goals = try await model.social.sharedGoals(linkID: linkID ?? "", accessToken: accessToken)
                appointments = try await model.social.appointments(
                    linkID: linkID ?? "", now: Date(), accessToken: accessToken)
            }
            // La pièce « lien » est relue pour connaître l'AUTRE : c'est
            // `link.requester_id === myId ? recipient : requester`
            // (`SocialScreens.tsx:105`), et non une donnée de la pièce.
            if let linkID {
                link = try await model.social.links(accessToken: accessToken).first { $0.id == linkID }
            }
            suspension = try await model.social.mySuspension(userID: myID, accessToken: accessToken)
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    /// L'identifiant de l'autre, tel que l'original le calcule :
    /// `link.requester_id === myId ? link.recipient_id : link.requester_id`.
    private func otherID() -> String {
        guard let link else { return "" }
        return link.requesterId == myID ? link.recipientId : link.requesterId
    }

    /// Fusionne deux pages par identifiant, triées par horodatage **texte**.
    /// L'original écrit `[...byId.values()].sort((a,b) => a.created_at.localeCompare(b.created_at))` :
    /// l'ordre est celui des chaînes ISO, qui est aussi l'ordre chronologique —
    /// et c'est ce qui garantit que les deux applications affichent le même fil.
    private func merge(_ incoming: [ChatMessage], into existing: [ChatMessage]) -> [ChatMessage] {
        var byID: [String: ChatMessage] = [:]
        for message in existing { byID[message.id] = message }
        for message in incoming { byID[message.id] = message }
        return byID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func loadOlder() async {
        guard !messages.isEmpty, !loadingOlder, let oldest = messages.first?.createdAt else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let older = try await model.social.messages(
                room: room, before: oldest, accessToken: accessToken)
            messages = merge(older, into: messages)
            hasOlder = older.count == MessagingOptions.pageSize
        } catch {
            notice = error.localizedDescription
        }
    }

    private func send(proxy: ScrollViewProxy) async {
        let body = MessagingOptions.outgoing(draft)
        guard !body.isEmpty else { return }
        await act {
            try await model.social.sendMessage(
                room: room, body: body, myID: myID, accessToken: accessToken)
            draft = ""
        }
        if let last = messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    /// Le partage **volontaire** de mon étape — `SocialScreens.tsx:207`. C'est
    /// une `sendMessage` de sorte `.progress` et non un partage de récitation,
    /// et l'original ne l'offre qu'en conversation **avec un ami** (jamais dans
    /// un cercle, jamais avec l'administration).
    private func shareStep() async {
        await act {
            try await model.social.sendMessage(
                room: room, body: shareText, kind: .progress, myID: myID, accessToken: accessToken)
        }
    }

    private func proposeGoal(linkID: String) async {
        guard let target = MessagingOptions.sessionCount(targetSessions) else { return }
        let week = DateKeys.weekStart(DateKeys.today())
        await act {
            try await model.social.proposeSharedGoal(
                linkID: linkID, weekStart: week, target: target, myID: myID, accessToken: accessToken)
        }
    }

    private func proposeAppointment(linkID: String) async {
        guard let iso = MessagingOptions.appointmentISO(appointmentText, now: Date()) else {
            notice = "Entre une date et une heure futures au format AAAA-MM-JJ HH:mm."
            return
        }
        await act {
            try await model.social.proposeAppointment(
                linkID: linkID, startsAt: iso, myID: myID, accessToken: accessToken)
            appointmentText = ""
        }
    }

    private func sendReport() async {
        guard let reportTarget else { return }
        await act {
            try await model.social.reportMessage(
                messageID: reportTarget, reason: reason, accessToken: accessToken)
            self.reportTarget = nil
            reason = ""
        }
    }

    private func act(_ operation: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await operation()
            let reopened = try await model.social.messages(room: room, accessToken: accessToken)
            messages = merge(reopened, into: messages)
        } catch {
            notice = error.localizedDescription
        }
    }
}

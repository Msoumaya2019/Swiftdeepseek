// AdminView.swift
// La modération — signalements, suspensions, messages récents.
//
// Correspondance : `AdminScreen` de `src/SocialScreens.tsx:212`, **partie
// modération**. L'original en écarte six sous-écrans (`problemMode`, `quizMode`,
// `dailyMode`, `accountsMode`, `recitationMode`, `notificationMode`) ; ils ne
// sont **pas** portés ici, et leur absence est visible : les boutons qui les
// ouvrent ne sont pas rendus, plutôt que d'être rendus inertes.
//
// La porte : `social.isSocialAdmin()`. Ce n'est PAS un contrôle de sécurité —
// ce sont les politiques RLS de Supabase qui décident, et l'original le rappelle
// (« Les actions sont vérifiées par Supabase »). La vérification ici sert à
// **expliquer** un refus, pas à l'empêcher.
//
// AUCUNE RÈGLE ICI. Quatre vivent dans `Core/MessagingOptions` avec leurs tests :
// les quatre durées d'une suspension et leurs libellés, la conversion en date de
// fin (**86 400 000 ms par jour**, et non un `Calendar`), la borne du motif,
// l'état ouvert d'un signalement, et l'activité d'une suspension. La vue les
// appelle ; elle ne les réécrit pas.

import SwiftUI

/// La modération : signalements, suspensions, messages récents.
struct AdminView: View {

    @EnvironmentObject private var model: AppViewModel

    /// Mon identifiant.
    let myID: String
    /// Le jeton d'accès.
    let accessToken: String

    @State private var reports: [MessageReport] = []
    @State private var messages: [ChatMessage] = []
    @State private var suspensions: [SocialSuspension] = []
    /// Les noms affichés, par identifiant. Une seule requête les rassemble.
    @State private var names: [String: String] = [:]
    @State private var reason = ""
    @State private var target = ""
    @State private var duration = MessagingOptions.SuspensionLength.sevenDays
    @State private var notice: String?
    @State private var busy = false
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let notice {
                    Card { EmptyLabel(text: notice) }
                }

                Text("Signalements et discussions entre membres. Les actions sont vérifiées par Supabase.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)

                CardButton(title: loading ? "Chargement…" : "Actualiser", disabled: loading) {
                    Task { await load() }
                }

                reportsSection
                suspensionForm
                suspensionsSection
                messagesSection
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.section)
        }
        .background(model.palette.cream)
        .navigationTitle("Modération")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: Signalements

    @ViewBuilder
    private var reportsSection: some View {
        // L'écran ne montre que les signalements OUVERTS : « Signalements
        // ouverts · N » (`SocialScreens.tsx:239`). Un signalement classé reste
        // en base mais ne s'affiche plus — c'est la règle, et elle est nommée.
        let open = reports.filter { MessagingOptions.reportIsOpen($0) }
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Signalements ouverts · \(open.count)")
                    .font(.system(size: Theme.Typography.subhead, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                if !loading && open.isEmpty {
                    EmptyLabel(text: "Aucun signalement ouvert.")
                }
                ForEach(open) { report in
                    reportRow(report)
                }
            }
        }
    }

    @ViewBuilder
    private func reportRow(_ report: MessageReport) -> some View {
        // L'auteur peut être introuvable : le message signalé peut être plus
        // ancien que la fenêtre des « messages récents ». L'original l'écrit
        // explicitement (« message plus ancien ») — l'écran ne doit pas
        // afficher un identifiant brut à la place.
        let author = messages.first { $0.id == report.messageId }

        VStack(alignment: .leading, spacing: 6) {
            Text("\(names[report.reporterId] ?? "Membre") a signalé un message")
                .font(.system(size: Theme.Typography.body, weight: .semibold))
            Text("Motif : \(report.reason)")
            Text("Message : \(report.excerpt)")
            Text("Auteur : \(author.map { names[$0.senderId] ?? $0.senderId } ?? "message plus ancien") · \(DateKeys.dateTimeText(report.createdAt))")
                .font(.system(size: Theme.Typography.metadata))
                .foregroundStyle(model.palette.muted)

            CardButton(title: "Supprimer le message et clôturer", disabled: busy) {
                Task {
                    await act {
                        try await model.social.deleteMessage(messageID: report.messageId, accessToken: accessToken)
                        try await model.social.resolveReport(reportID: report.id, accessToken: accessToken)
                    }
                }
            }
            CardButton(title: "Classer sans suppression", disabled: busy) {
                Task {
                    await act {
                        try await model.social.resolveReport(reportID: report.id, accessToken: accessToken)
                    }
                }
            }
            if let author {
                CardButton(title: "Suspendre l’auteur", disabled: busy) {
                    target = author.senderId
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Suspendre

    @ViewBuilder
    private var suspensionForm: some View {
        if !target.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Suspendre \(names[target] ?? "ce membre") de la messagerie")
                        .font(.system(size: Theme.Typography.subhead, weight: .semibold))
                        .foregroundStyle(model.palette.green)
                    TextField("Motif (obligatoire)", text: $reason)
                        .textFieldStyle(.roundedBorder)

                    // Les quatre durées, dans l'ordre de `CaseIterable` — qui est
                    // celui de l'original. Le choix est un état, la conversion en
                    // date une règle de `Core/`.
                    ForEach(MessagingOptions.SuspensionLength.allCases, id: \.self) { length in
                        Button {
                            duration = length
                        } label: {
                            HStack {
                                Image(systemName: duration == length ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(model.palette.green)
                                Text(length.label)
                                    .font(.system(size: Theme.Typography.secondary))
                                    .foregroundStyle(model.palette.green)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    CardButton(
                        title: "Confirmer la suspension",
                        disabled: busy || !MessagingOptions.suspensionReasonIsAcceptable(reason)
                    ) {
                        Task { await suspend() }
                    }
                    CardButton(title: "Annuler", disabled: busy) {
                        target = ""
                        reason = ""
                    }
                }
            }
        }
    }

    // MARK: Suspensions actives

    @ViewBuilder
    private var suspensionsSection: some View {
        let now = Date()
        let active = suspensions.filter { MessagingOptions.suspensionIsActive($0, now: now) }
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Suspensions actives")
                    .font(.system(size: Theme.Typography.subhead, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                if !loading && active.isEmpty {
                    EmptyLabel(text: "Aucune suspension active.")
                }
                ForEach(active, id: \.userId) { suspension in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(names[suspension.userId] ?? suspension.userId)
                            .font(.system(size: Theme.Typography.body, weight: .semibold))
                        Text(suspension.reason)
                        Text(suspension.suspendedUntil == nil
                             ? "Sans date de fin"
                             : "Jusqu’au \(DateKeys.dateTimeText(suspension.suspendedUntil ?? ""))")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        CardButton(title: "Lever la suspension", disabled: busy) {
                            Task {
                                await act {
                                    try await model.social.unsuspendMember(
                                        userID: suspension.userId, accessToken: accessToken)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Messages récents

    @ViewBuilder
    private var messagesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Messages récents")
                    .font(.system(size: Theme.Typography.subhead, weight: .semibold))
                    .foregroundStyle(model.palette.green)
                if !loading && messages.isEmpty {
                    EmptyLabel(text: "Aucun message récent.")
                }
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(names[message.senderId] ?? message.senderId) · \(DateKeys.dateTimeText(message.createdAt))")
                            .font(.system(size: Theme.Typography.metadata))
                            .foregroundStyle(model.palette.muted)
                        // Le corps d'un message supprimé passe par la règle de
                        // `Core/` — l'écran n'invente pas le libellé.
                        Text(MessagingOptions.summaryBody(
                            body: message.body, isDeleted: message.deletedAt != nil))
                        // Un message déjà supprimé n'offre plus ni suppression ni
                        // suspension : c'est `!m.deleted_at` de l'original.
                        if message.deletedAt == nil {
                            CardButton(title: "Supprimer", disabled: busy) {
                                Task {
                                    await act {
                                        try await model.social.deleteMessage(
                                            messageID: message.id, accessToken: accessToken)
                                    }
                                }
                            }
                            CardButton(title: "Suspendre l’auteur", disabled: busy) {
                                target = message.senderId
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Actions

    private func suspend() async {
        guard MessagingOptions.suspensionReasonIsAcceptable(reason) else { return }
        let until = MessagingOptions.suspensionUntil(duration, now: Date())
        busy = true
        defer { busy = false }
        do {
            try await model.social.suspendMember(
                userID: target,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                until: until,
                accessToken: accessToken)
            target = ""
            reason = ""
            await load()
            notice = "Action enregistrée."
        } catch {
            notice = error.localizedDescription
        }
    }

    private func act(_ operation: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await operation()
            await load()
            notice = "Action enregistrée."
        } catch {
            notice = error.localizedDescription
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            // La porte d'abord : sans droits, on n'interroge RIEN. L'original
            // lève avant ses trois requêtes (`SocialScreens.tsx:226`), et pas
            // après — une erreur de permission doit se lire comme telle, non
            // comme trois listes vides.
            guard try await model.social.isSocialAdmin(myID: myID, accessToken: accessToken) else {
                notice = "Accès administrateur refusé."
                return
            }
            async let reportsTask = model.social.adminReports(accessToken: accessToken)
            async let messagesTask = model.social.adminMessages(accessToken: accessToken)
            async let suspensionsTask = model.social.socialSuspensions(accessToken: accessToken)
            let (loadedReports, loadedMessages, loadedSuspensions) =
                try await (reportsTask, messagesTask, suspensionsTask)
            reports = loadedReports
            messages = loadedMessages
            suspensions = loadedSuspensions

            // Les noms en UN aller-retour, pour les trois sources réunies. Les
            // doublons sont retirés avant la requête : `in.(...)` les tolère,
            // mais la réponse serait plus longue que nécessaire — et c'est la
            // règle que `adminProfiles` porte déjà.
            var ids: [String] = []
            ids.append(contentsOf: loadedMessages.map(\.senderId))
            ids.append(contentsOf: loadedReports.map(\.reporterId))
            ids.append(contentsOf: loadedSuspensions.map(\.userId))
            let people = try await model.social.adminProfiles(ids: ids, accessToken: accessToken)
            names = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.displayName) })
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }
}

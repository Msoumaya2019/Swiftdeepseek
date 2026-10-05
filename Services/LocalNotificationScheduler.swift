// LocalNotificationScheduler.swift
// Le programmateur des rappels locaux — la seule partie des notifications qui
// touche l'appareil.
//
// Correspondance : `cancelAutomaticReminders`, `syncLearningReminder`,
// `testLocalNotification`, `scheduledReminderCounts` et
// `ensureNotificationPermission` de `src/services/notifications.ts`.
//
// POURQUOI UN PROTOCOLE
//   Les décisions — quels rappels annuler, que compter, quand programmer — vivent
//   dans `Core/NotificationOptions.swift` et s'éprouvent sans appareil. Ce fichier
//   ne fait que les traduire en appels à `UNUserNotificationCenter`. Un faux
//   l'implémente pour les tests : c'est la même séparation que
//   `Services/PassageAudioExecutor.swift`, et pour la même raison — un service qui
//   décide ne se teste qu'avec un appareil.
//
// `scheduleQueue` DEVIENT UN ACTEUR
//   L'original sérialise ses programmations par une chaîne de promesses
//   (`notifications.ts:23,71,142`) : sans elle, une annulation et une
//   programmation lancées ensemble pourraient s'entrelacer. Un acteur donne la
//   même garantie — l'isolation sérialise les appels —, et se passe de la chaîne.
//
// CE QUI N'EST PAS ICI, ET POURQUOI
//   Le jeton APNs, la table `push_devices`, `registerPushDevice`,
//   `updatePushPresence`, `unregisterPushDevice`, `pushDiagnostic` et
//   `saveNotificationPreferences` ne sont pas portés : ils demandent un compte
//   Apple Developer, un appareil physique, le déploiement des déclencheurs SQL et
//   une table `notification_preferences` dont l'existence côté serveur n'est pas
//   vérifiée ici. Les porter à moitié donnerait un bouton qui ment.

import Foundation
import UserNotifications

/// Ce que le système doit savoir programmer — et rien de plus.
public struct LocalNotificationRequest: Equatable, Sendable {
    public var kind: NotificationOptions.Kind
    public var title: String
    public var body: String
    /// Répétition quotidienne à cette heure — `syncLearningReminder`.
    public var dailyHour: Int?
    public var dailyMinute: Int?
    /// Délai unique, en secondes — `testLocalNotification`.
    public var afterSeconds: Int?

    public init(
        kind: NotificationOptions.Kind,
        title: String,
        body: String,
        dailyHour: Int? = nil,
        dailyMinute: Int? = nil,
        afterSeconds: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.dailyHour = dailyHour
        self.dailyMinute = dailyMinute
        self.afterSeconds = afterSeconds
    }
}

/// Les six opérations dont le service a besoin. Un faux les implémente pour les
/// tests ; l'implémentation réelle est plus bas.
public protocol LocalNotificationScheduling: Sendable {
    func permission() async -> NotificationOptions.PermissionResult
    func requestPermission() async -> NotificationOptions.PermissionResult
    func scheduled() async -> [NotificationOptions.ScheduledReminder]
    func cancel(ids: [String]) async
    func schedule(_ request: LocalNotificationRequest) async
}

/// Le port des fonctions exportées de `src/services/notifications.ts`.
///
/// Un acteur, donc : deux appels concurrents ne s'entrelacent pas comme ils le
/// feraient sur un `final class`.
public actor LocalNotificationService {

    private let scheduler: LocalNotificationScheduling

    public init(scheduler: LocalNotificationScheduling) {
        self.scheduler = scheduler
    }

    /// `ensureNotificationPermission(prompt)` — `notifications.ts:56-62`.
    ///
    /// La demande n'est envoyée que si `needsRequest` la juge utile : un statut
    /// `PROVISIONAL` ou `EPHEMERAL` est déjà une autorisation, et redemander
    /// ferait apparaître une boîte système pour rien.
    public func ensurePermission(prompt: Bool) async -> NotificationOptions.PermissionResult {
        var result = await scheduler.permission()
        if NotificationOptions.needsRequest(result, prompt: prompt) {
            result = await scheduler.requestPermission()
        }
        return result
    }

    /// `cancelAutomaticReminders` — `notifications.ts:64-72`.
    public func cancelAutomaticReminders() async {
        let scheduled = await scheduler.scheduled()
        await scheduler.cancel(ids: NotificationOptions.automaticReminderIds(scheduled))
    }

    /// `syncLearningReminder(enabled)` — `notifications.ts:135-143`.
    ///
    /// L'ordre compte, et c'est celui de l'original : on **annule** d'abord les
    /// rappels d'apprentissage, puis on en programme un seul si le rappel est
    /// allumé et la permission acquise. Éteindre le rappel suffit donc à le
    /// retirer, sans condition de permission.
    public func syncLearningReminder(enabled: Bool) async {
        let scheduled = await scheduler.scheduled()
        let ids = scheduled
            .filter { $0.kind == .learningReminder }
            .map(\.id)
        await scheduler.cancel(ids: ids)

        let permission = await ensurePermission(prompt: false)
        guard NotificationOptions.shouldScheduleLearningReminder(
            enabled: enabled,
            permission: permission
        ) else { return }

        await scheduler.schedule(
            LocalNotificationRequest(
                kind: .learningReminder,
                title: NotificationOptions.reminderTitle,
                body: NotificationOptions.reminderBody,
                dailyHour: NotificationOptions.reminderHour,
                dailyMinute: NotificationOptions.reminderMinute
            )
        )
    }

    /// `testLocalNotification` — `notifications.ts:145-148`.
    ///
    /// Rend `true` si la notification a été programmée, `false` si la permission
    /// manque — l'appelant en fait un avis, pas une erreur.
    @discardableResult
    public func testLocalNotification() async -> Bool {
        let permission = await ensurePermission(prompt: true)
        guard NotificationOptions.shouldScheduleTestNotification(permission: permission) else {
            return false
        }
        await scheduler.schedule(
            LocalNotificationRequest(
                kind: .notificationTest,
                title: NotificationOptions.testTitle,
                body: NotificationOptions.testBody,
                afterSeconds: NotificationOptions.testDelaySeconds
            )
        )
        return true
    }

    /// `scheduledReminderCounts` — `notifications.ts:150-157`.
    public func scheduledReminderCounts() async -> (learning: Int, revision: Int) {
        NotificationOptions.reminderCounts(await scheduler.scheduled())
    }

    /// Le texte de l'avis des comptes — `App.tsx:346`. Le calcul vit dans le
    /// modèle ; ce fichier ne fait que l'appeler, pour que la vue n'ait rien à
    /// composer.
    public func countsNotice() async -> String {
        let counts = await scheduledReminderCounts()
        return NotificationOptions.countsNotice(learning: counts.learning, revision: counts.revision)
    }
}

// MARK: - L'implémentation réelle

/// `UNUserNotificationCenter`, réduit aux six opérations du protocole.
public final class UserNotificationsScheduler: LocalNotificationScheduling, @unchecked Sendable {

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// `getPermissionsAsync()`.
    ///
    /// `granted` est dérivé du **seul** statut `authorized`. C'est ce qui donne
    /// leur sens aux deux prédicats de l'original : `App.tsx:112` et
    /// `notifications.ts:61` ajoutent `|| PROVISIONAL || EPHEMERAL` à `granted`,
    /// ce qu'ils n'écriraient pas si `granted` couvrait déjà ces deux statuts. Le
    /// paquet `expo-notifications` n'est pas installé dans le dépôt de référence,
    /// donc cette correspondance est une **lecture**, pas une mesure — et le banc
    /// la vérifie pour qu'elle ne change pas en silence.
    public func permission() async -> NotificationOptions.PermissionResult {
        Self.result(await center.notificationSettings())
    }

    /// `requestPermissionsAsync()` — la demande système.
    public func requestPermission() async -> NotificationOptions.PermissionResult {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await permission()
    }

    public func scheduled() async -> [NotificationOptions.ScheduledReminder] {
        let requests = await center.pendingNotificationRequests()
        return requests.map { request in
            let raw = request.content.userInfo["kind"] as? String
            return NotificationOptions.ScheduledReminder(
                id: request.identifier,
                kind: raw.flatMap(NotificationOptions.Kind.init(rawValue:))
            )
        }
    }

    public func cancel(ids: [String]) async {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func schedule(_ request: LocalNotificationRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["kind": request.kind.rawValue]

        let trigger: UNNotificationTrigger?
        if let hour = request.dailyHour, let minute = request.dailyMinute {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else if let seconds = request.afterSeconds {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(seconds),
                repeats: false
            )
        } else {
            trigger = nil
        }

        let notification = UNNotificationRequest(
            identifier: request.kind.rawValue,
            content: content,
            trigger: trigger
        )
        try? await center.add(notification)
    }

    /// `UNAuthorizationStatus` vers le modèle.
    ///
    /// Les valeurs numériques d'`expo-notifications` sont celles du système :
    /// `notDetermined` 0, `denied` 1, `authorized` 2, `provisional` 3,
    /// `ephemeral` 4. La lecture est directe, et un statut inconnu — ajouté par
    /// une version future d'iOS — retombe sur `notDetermined`, donc sur un refus.
    static func result(_ settings: UNNotificationSettings) -> NotificationOptions.PermissionResult {
        let status = NotificationOptions.AuthorizationStatus(
            rawValue: settings.authorizationStatus.rawValue
        ) ?? .notDetermined
        return NotificationOptions.PermissionResult(
            granted: status == .authorized,
            status: status
        )
    }
}

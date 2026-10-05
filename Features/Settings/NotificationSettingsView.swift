// NotificationSettingsView.swift
// Réglages — « Notifications » : la porte de permission, les sept
// interrupteurs, le pied de carte, et les deux vérifications locales.
//
// Correspondance : la carte « Notifications » de `src/App.tsx:331-348`, dans la
// branche `mode==='settings'` de `ProfileScreen`.
//
// RÈGLE DE CE FICHIER : il ne calcule rien.
//   Les sept interrupteurs et leur ordre, leurs libellés, leur valeur de repli,
//   le texte de la porte, le texte du pied de carte, les libellés des deux
//   boutons et les avis qu'ils produisent viennent tous de
//   `Core/NotificationOptions.swift`. La permission est lue par
//   `AppViewModel`, jamais ici.
//
// CE QUI EST ÉCRIT, ET CE QUI AGIT VRAIMENT
//   Les sept préférences sont ÉCRITES dans le document synchronisé : c'est ce
//   qui fait que l'application actuelle les relit, et c'est la raison d'être de
//   cet écran. Une seule agit **ici** : le rappel quotidien, réellement
//   programmé sur ce téléphone par `LocalNotificationService`.
//
//   Les six autres sont des contrôles d'affichage : dans l'original, elles
//   décident si une notification **déjà reçue** s'affiche (`notifications.ts:36`
//   — les sept portes de `shouldPresent`). Tant que la réception n'est pas
//   portée, elles ne changent rien à l'écran. Les écrire est nécessaire, et le
//   dire l'est aussi : un interrupteur qui ne change rien ferait croire
//   l'application cassée.
//
// UN APPUI ÉCRIT LE DÉFAUT MATÉRIALISÉ
//   `App.tsx:304,306` : la valeur écrite est `{...notificationPrefs, [key]:value}`,
//   où `notificationPrefs` vaut `state.notifications ?? {messages:true,learning:false}`.
//   Toucher un interrupteur sur une installation neuve écrit donc **aussi**
//   `messages:true` et `learning:false`. Ce n'est pas un défaut : c'est le
//   contrat que l'application actuelle relit. Le modèle le reproduit
//   (`NotificationOptions.setting`).
//
// DEUX PRÉDICATS DE PERMISSION, ET ILS DIVERGENT
//   La carte autorise sur `granted || PROVISIONAL` (`App.tsx:305`) ; le service,
//   sur `granted || PROVISIONAL || EPHEMERAL` (`notifications.ts:61`). Un statut
//   EPHEMERAL — le provisoire d'un jour d'iOS — laisse donc le service envoyer
//   pendant que la carte montre encore la porte. La divergence est celle de
//   l'original et elle est conservée : `cardAllows` ici, `serviceAllows` là-bas.
//
// LE TROISIÈME BOUTON DE L'ORIGINAL N'EST PAS ICI
//   `App.tsx:347` ajoute « Vérifier le jeton push » dès qu'un compte est ouvert.
//   Ce bouton interroge l'enregistrement du jeton APNs, qui n'est **pas porté**
//   — il demande une vérification côté serveur et une migration, ce que la
//   charte interdit sans accord préalable. Un bouton qui ne peut rien vérifier
//   serait un bouton mort : il est absent, et
//   `NotificationOptions.shouldRegisterPushDevice` porte la dérivation pour
//   qu'un futur écran ne puisse pas l'inventer.
//
// CE QUI RESTE À FAIRE ICI N'EST PAS DU CODE
//   Éprouver sur un appareil : que la notification de test arrive bien cinq
//   secondes après l'appui, et que le rappel quotidien se déclenche à 19 h avec
//   la bonne heure locale.

import SwiftUI

struct NotificationSettingsView: View {

    @EnvironmentObject private var model: AppViewModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// `deviceNotificationsAllowed` (`App.tsx:303`) — l'état de la porte, lu au
    /// chargement **sans jamais demander**. Le prédicat est celui de la carte,
    /// donc sans EPHEMERAL.
    @State private var deviceAllowed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle(NotificationOptions.cardTitle)

                    card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            // `!deviceNotificationsAllowed?` (`App.tsx:333`) : la
                            // porte disparaît dès que la permission est accordée,
                            // et ne revient pas — comme dans l'original.
                            if !deviceAllowed {
                                permissionGate
                            }

                            ForEach(NotificationOptions.switches) { item in
                                switchRow(item)
                            }

                            Text(NotificationOptions.cardFooter)
                                .font(.system(size: Theme.Typography.secondary))
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            actionButton(NotificationOptions.testAction, perform: runTest)
                            actionButton(NotificationOptions.countsAction, perform: runCounts)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(palette.cream)
            .navigationTitle(NotificationOptions.cardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
            // `App.tsx:305` : la lecture au montage, sans invite. Le repli de la
            // promesse est silencieux dans l'original (`.catch(()=>{})`) — la
            // porte reste donc fermée plutôt que de faire échouer l'écran.
            .task {
                deviceAllowed = await model.syncDeviceNotificationPermission()
            }
        }
    }

    // MARK: - La porte de permission

    private var permissionGate: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(NotificationOptions.permissionDetail)
                .font(.system(size: Theme.Typography.secondary))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            actionButton(NotificationOptions.permissionAction, perform: askPermission)
        }
    }

    // MARK: - Un interrupteur

    /// `notificationSwitch(...)` (`App.tsx:307`) : le libellé, puis
    /// `notificationPrefs[key] ?? fallback`. La valeur vient du modèle.
    private func switchRow(_ item: NotificationOptions.Switch) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Text(item.label)
                .font(.system(size: Theme.Typography.body))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Theme.Spacing.sm)

            Toggle(
                "",
                isOn: Binding(
                    get: { NotificationOptions.value(model.state, item.id) },
                    set: { model.setNotification(item.id, to: $0) }
                )
            )
            .labelsHidden()
            .tint(palette.green)
            .accessibilityLabel(item.label)
        }
    }

    // MARK: - Les actions

    /// `App.tsx:335` — trois issues dans l'original : accordée, refusée, ou
    /// indisponible (le `catch`). L'API Swift ne rend pas d'erreur mais un
    /// résultat non accordé ; les deux issues qu'un utilisateur peut suivre sont
    /// donc conservées, et `unavailableNotice` reste porté sans être montré.
    private func askPermission() {
        Task {
            let allowed = await model.requestDeviceNotificationPermission()
            if allowed {
                deviceAllowed = true
                model.notice = NotificationOptions.grantedNotice
            } else {
                model.notice = NotificationOptions.deniedNotice
            }
        }
    }

    /// `App.tsx:345` — `testLocalNotification()` **lève** quand la permission
    /// manque (`notifications.ts:146`), d'où le message dédié.
    private func runTest() {
        Task {
            let scheduled = await model.testLocalNotification()
            model.notice = scheduled
                ? NotificationOptions.testScheduledNotice
                : NotificationOptions.testFailureNotice(NotificationOptions.testPermissionNotice)
        }
    }

    /// `App.tsx:346` — le texte est composé par le service, pas ici.
    private func runCounts() {
        Task {
            model.notice = await model.scheduledReminderNotice()
        }
    }

    // MARK: - Mise en page

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.Typography.section, weight: .semibold))
            .foregroundStyle(palette.green)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `Button secondary` / `Button secondary small` de l'original, dans le
    /// gabarit déjà employé par `SettingsView.settingsRow` : fond `soft`,
    /// texte vert, hauteur minimale 42.
    private func actionButton(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: Theme.Typography.body, weight: .semibold))
                .foregroundStyle(palette.green)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    palette.soft,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small)
                )
        }
        .buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Spacing.md)
            .background(
                palette.paper,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(palette.line, lineWidth: 1)
            )
    }
}

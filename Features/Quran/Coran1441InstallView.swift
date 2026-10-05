// Coran1441InstallView.swift
// L'installation du Coran 1441 : son état, sa progression, ses commandes.
//
// POURQUOI CE FICHIER EXISTE
//   Ce bloc vivait dans `QuranScreenView`, c'est-à-dire dans l'onglet Coran. Or
//   l'onglet Coran de l'original est la liste des sourates (`QuranScreen`), qui
//   ne parle ni d'édition ni d'installation. L'original installe le Coran 1441
//   depuis le sélecteur « Affichage du Coran » du **lecteur**
//   (`App.tsx:515` → `DownloadSourceChoice`), au moment où l'utilisateur choisit
//   cette édition — et c'est le seul endroit où la question se pose.
//
//   Le bloc est donc sorti de l'écran qui l'hébergeait, pour que le lecteur
//   puisse le monter sans dépendre d'un onglet qui n'existe plus.
//
// AUCUNE RÈGLE ICI
//   Les phases, la progression, la pause et la reprise viennent de
//   `Services/Coran1441Download.swift`, que l'écran ne fait qu'observer. Le seul
//   calcul local est la taille annoncée, et elle est dérivée de la constante de
//   l'archive — jamais écrite à la main : une taille en dur deviendrait fausse
//   le jour où l'archive change, et l'utilisateur découvrirait l'écart au milieu
//   du téléchargement.

import SwiftUI

/// L'état de l'installation, et ses commandes.
///
/// Rendue seulement quand il y a quelque chose à dire : une fois le Coran 1441
/// installé, l'appelant ne la monte plus et le sélecteur redevient une simple
/// liste d'éditions.
struct Coran1441InstallView: View {

    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        let download = model.coran1441

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            switch download.state.phase {
            case .idle:
                Text("""
                    Les pages du Coran 1441 ne sont pas dans l'application : elles \
                    s'installent une fois, puis restent disponibles hors connexion.
                    """)
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                installButton("Installer (\(Self.approximateMegabytes) Mo)")

            case .downloading:
                progressRow(title: "Téléchargement", value: download.state.progress)
                installButton("Mettre en pause") { download.pause() }

            case .extracting:
                progressRow(title: "Installation des pages", value: download.state.progress)
                Text("Garde l'application ouverte pendant l'installation.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)

            case .paused:
                Text("Installation en pause. Le téléchargement reprend où il s'est arrêté.")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                installButton("Reprendre")

            case .failed:
                if let message = download.state.message {
                    Text(message)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                installButton("Réessayer")

            case .ready:
                EmptyView()
            }
        }
    }

    // MARK: - Morceaux

    private func installButton(
        _ title: String,
        action: (() -> Void)? = nil
    ) -> some View {
        Button(title) {
            if let action { action() } else { model.coran1441.start() }
        }
        .font(.system(size: Theme.Typography.body, weight: .semibold))
        .foregroundStyle(model.palette.green)
        .buttonStyle(.plain)
    }

    private func progressRow(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value * 100).rounded())) %")
                    .foregroundStyle(model.palette.muted)
                    .monospacedDigit()
            }
            ProgressView(value: min(max(value, 0), 1))
                .tint(model.palette.green)
        }
        .font(.system(size: Theme.Typography.secondary))
    }

    /// Taille de l'archive, en mégaoctets, arrondie au mégaoctet.
    static var approximateMegabytes: Int {
        Int((Double(Coran1441Install.archiveBytes) / 1_048_576).rounded())
    }
}

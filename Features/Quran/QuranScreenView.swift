// QuranScreenView.swift
// Onglet Coran : choix de l'édition, installation du Coran 1441, reprise,
// marques-pages, accès au lecteur.

import SwiftUI

public struct QuranScreenView: View {

    @EnvironmentObject private var model: AppViewModel
    @State private var readerRequest: ReaderRequest?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Éditions") {
                    ForEach(QuranEdition.allCases, id: \.rawValue) { edition in
                        Button {
                            choose(edition)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(edition.label)
                                        .foregroundStyle(edition.isAvailable ? model.palette.text : model.palette.muted)
                                    Text(subtitle(for: edition))
                                        .font(.system(size: Theme.Typography.metadata))
                                        .foregroundStyle(model.palette.muted)
                                }
                                Spacer()
                                if QuranEdition(rawValue: model.state.reader?.mushaf ?? "") == edition {
                                    Image(systemName: "checkmark").foregroundStyle(model.palette.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // L'installation n'apparaît que lorsqu'elle a quelque chose à
                // dire : une fois le Coran 1441 installé, la section disparaît et
                // l'écran redevient celui d'avant.
                if showsCoran1441Install {
                    coran1441Section
                }

                Section("Reprendre") {
                    if let lastRead = model.state.lastRead {
                        Button {
                            readerRequest = ReaderRequest(range: nil, sessionID: nil, page: lastRead.page)
                        } label: {
                            HStack {
                                Text("Page \(lastRead.page)")
                                Spacer()
                                Image(systemName: "book")
                            }
                        }
                        .foregroundStyle(model.palette.green)
                    } else {
                        Text("Aucune lecture enregistrée.")
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                    }
                }

                Section("Marques-pages") {
                    let items = Bookmark.visible(model.state)
                    if items.isEmpty {
                        Text("Aucune marque-page.")
                            .font(.system(size: Theme.Typography.secondary))
                            .foregroundStyle(model.palette.muted)
                    } else {
                        ForEach(items, id: \.verseId) { item in
                            Button {
                                readerRequest = ReaderRequest(
                                    range: nil,
                                    sessionID: nil,
                                    page: item.sourcePages?[model.edition.rawValue] ?? item.page
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Quran.surahAt(item.verseId).name) · verset \(item.ayah)")
                                        .foregroundStyle(model.palette.text)
                                    Text("Page \(item.page)")
                                        .font(.system(size: Theme.Typography.metadata))
                                        .foregroundStyle(model.palette.muted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Coran")
            .onAppear { model.coran1441.refresh() }
            .fullScreenCover(item: $readerRequest) { request in
                ReaderView(request: request, edition: model.edition, startPage: request.page)
                    .environmentObject(model)
            }
        }
    }

    // MARK: Choix d'une édition

    /// Sélectionne une édition — ou, pour le Coran 1441, propose de l'installer.
    ///
    /// Le Coran 1441 n'est pas dans le paquet : ouvrir le lecteur sur une édition
    /// dont les 9 060 images ne sont pas là donnerait des pages vides. Mieux vaut
    /// lancer l'installation et le dire, que d'ouvrir un lecteur muet.
    private func choose(_ edition: QuranEdition) {
        guard edition.isAvailable else {
            model.notice = "\(edition.label) n'est pas encore disponible dans cette version."
            return
        }

        if edition == .coran1441, !model.coran1441.isInstalled {
            model.coran1441.start()
            return
        }

        model.setEdition(edition)
        readerRequest = ReaderRequest(range: nil, sessionID: nil, page: model.resumePage)
    }

    private func subtitle(for edition: QuranEdition) -> String {
        guard edition.isAvailable else { return "À venir" }
        guard edition == .coran1441 else { return "Disponible" }
        return model.coran1441.isInstalled ? "Installé" : "À installer"
    }

    // MARK: Installation du Coran 1441

    private var showsCoran1441Install: Bool {
        !model.coran1441.isInstalled
    }

    @ViewBuilder
    private var coran1441Section: some View {
        let download = model.coran1441

        Section("Coran 1441") {
            switch download.state.phase {
            case .idle:
                Text("""
                    Les pages du Coran 1441 ne sont pas dans l'application : elles \
                    s'installent une fois, puis restent disponibles hors connexion.
                    """)
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
                Button("Installer (\(Self.approximateMegabytes) Mo)") { download.start() }
                    .foregroundStyle(model.palette.green)

            case .downloading:
                progressRow(title: "Téléchargement", value: download.state.progress)
                Button("Mettre en pause") { download.pause() }
                    .foregroundStyle(model.palette.green)

            case .extracting:
                progressRow(title: "Installation des pages", value: download.state.progress)
                Text("Garde l'application ouverte pendant l'installation.")
                    .font(.system(size: Theme.Typography.metadata))
                    .foregroundStyle(model.palette.muted)

            case .paused:
                Text("Installation en pause. Le téléchargement reprend où il s'est arrêté.")
                    .font(.system(size: Theme.Typography.secondary))
                    .foregroundStyle(model.palette.muted)
                Button("Reprendre") { download.start() }
                    .foregroundStyle(model.palette.green)

            case .failed:
                if let message = download.state.message {
                    Text(message)
                        .font(.system(size: Theme.Typography.secondary))
                        .foregroundStyle(model.palette.text)
                }
                Button("Réessayer") { download.start() }
                    .foregroundStyle(model.palette.green)

            case .ready:
                EmptyView()
            }
        }
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
    ///
    /// Calculée depuis la constante, jamais écrite à la main : une taille
    /// annoncée en dur deviendrait fausse le jour où l'archive change, et
    /// l'utilisateur découvrirait l'écart au milieu du téléchargement.
    private static var approximateMegabytes: Int {
        Int((Double(Coran1441Install.archiveBytes) / 1_048_576).rounded())
    }
}

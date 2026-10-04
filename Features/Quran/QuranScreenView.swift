// QuranScreenView.swift
// Onglet Coran : choix de l'édition, installation du Coran 1441, reprise,
// marques-pages, accès au lecteur.
//
// LE CHOIX D'ÉDITION N'EST PAS DÉCIDÉ ICI
//   La liste des quatre éditions, l'ordre, la décision d'un appui et le texte du
//   refus vivent dans `Core/QuranDisplayOptions.swift`, et le rendu dans
//   `Features/Quran/QuranEditionChooser.swift`. Cet écran ne fournit que les
//   effets. C'est ce qui le tient d'accord avec la carte « Affichage du Coran »
//   des réglages : deux copies d'une même règle finissent par diverger, et la
//   divergence serait ici silencieuse — l'écran s'afficherait, avec une liste
//   différente.

import SwiftUI

public struct QuranScreenView: View {

    @EnvironmentObject private var model: AppViewModel
    @State private var readerRequest: ReaderRequest?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Éditions") {
                    // Les quatre éditions viennent de `QuranDisplayOptions` — la
                    // même liste, dans le même ordre, que la carte de réglages.
                    // Parcourir `QuranEdition.allCases` affichait cinq éditions
                    // dans un autre ordre, dont « Moushaf Tajwid » que l'original
                    // ne propose nulle part.
                    QuranEditionChooser(
                        stored: model.state.reader?.mushaf,
                        coran1441Installed: model.coran1441.isInstalled,
                        onSelect: { edition in
                            model.setEdition(edition)
                            readerRequest = ReaderRequest(
                                range: nil, sessionID: nil, page: model.resumePage
                            )
                        },
                        onInstall: { _ in
                            model.coran1441.start()
                        },
                        onUnavailable: { edition in
                            model.notice = QuranDisplayOptions.unavailableNotice(for: edition)
                        }
                    )
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: Theme.Spacing.lg,
                            bottom: 0,
                            trailing: Theme.Spacing.lg
                        )
                    )
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

    // La décision vit dans `QuranDisplayOptions.choice(for:coran1441Installed:)`,
    // et le rendu des quatre éditions dans `QuranEditionChooser`. Cet écran ne
    // fournit que les **effets** : changer la préférence et ouvrir le lecteur,
    // lancer l'installation, ou dire le refus. C'est ce qui garantit que
    // l'onglet Coran et l'écran de réglages proposent la même liste et prennent
    // la même décision — deux copies d'une même règle divergent en silence.

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

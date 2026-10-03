// QuranScreenView.swift
// Onglet Coran : choix de l'édition, reprise, marques-pages, accès au lecteur.

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
                            guard edition.isAvailable else {
                                model.notice = "\(edition.label) n'est pas encore disponible dans cette version."
                                return
                            }
                            model.setEdition(edition)
                            readerRequest = ReaderRequest(range: nil, sessionID: nil, page: model.resumePage)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(edition.label)
                                        .foregroundStyle(edition.isAvailable ? model.palette.text : model.palette.muted)
                                    Text(edition.isAvailable ? "Disponible" : "À venir")
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
            .fullScreenCover(item: $readerRequest) { request in
                ReaderView(request: request, edition: model.edition, startPage: request.page)
                    .environmentObject(model)
            }
        }
    }
}

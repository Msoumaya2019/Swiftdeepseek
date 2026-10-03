// MainTabView.swift
// Navigation principale.
//
// Les cinq onglets sont ceux de l'application actuelle, dans le même ordre :
//   Accueil · Coran · Programme · Progrès · Amis
// (`type Tab = 'Accueil'|'Coran'|'Programme'|'Progrès'|'Amis'` — src/App.tsx:65)

import SwiftUI

public enum MainTab: String, CaseIterable, Identifiable {
    case home = "Accueil"
    case quran = "Coran"
    case program = "Programme"
    case progress = "Progrès"
    case friends = "Amis"

    public var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .quran: return "book.fill"
        case .program: return "calendar"
        case .progress: return "chart.bar.fill"
        case .friends: return "person.2.fill"
        }
    }
}

public struct MainTabView: View {

    @EnvironmentObject private var model: AppViewModel

    public init() {}

    public var body: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(MainTab.allCases) { tab in
                content(for: tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.symbol)
                    }
                    .tag(tab)
            }
        }
        .tint(model.palette.green)
    }

    @ViewBuilder
    private func content(for tab: MainTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .quran: QuranScreenView()
        case .program: ProgramView()
        // `ProgressScreenView` et non `ProgressView` : ce dernier nom est déjà
        // celui du type de SwiftUI, utilisé dans HomeView.
        case .progress: ProgressScreenView()
        case .friends: FriendsView()
        }
    }
}

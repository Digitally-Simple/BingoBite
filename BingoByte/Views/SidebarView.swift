import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case songs
    case playlists
    case bingoSets
    case bingoGames

    var id: String { rawValue }

    var label: String {
        switch self {
        case .songs: return "Songs"
        case .playlists: return "Playlists"
        case .bingoSets: return "Bingo Sets"
        case .bingoGames: return "Bingo Games"
        }
    }

    var icon: String {
        switch self {
        case .songs: return "music.note.list"
        case .playlists: return "list.bullet.rectangle"
        case .bingoSets: return "square.grid.3x3.fill"
        case .bingoGames: return "gamecontroller.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.label, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("BingoByte")
    }
}

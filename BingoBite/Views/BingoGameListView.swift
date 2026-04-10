import SwiftUI
import SwiftData

struct BingoGameListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]
    var onSelect: (PersistentIdentifier) -> Void

    @State private var tableSelection: PersistentIdentifier?
    @State private var sortOrder = [KeyPathComparator(\BingoGame.creationDate, order: .reverse)]
    @State private var searchText = ""
    @State private var showCreateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by name or playlist", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            Group {
                if bingoGames.isEmpty {
                    ContentUnavailableView(
                        "No Bingo Games",
                        systemImage: "gamecontroller.fill",
                        description: Text("Create a bingo game to get started.")
                    )
                } else {
                    Table(sortedBingoGames, selection: $tableSelection, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Playlist") { game in
                            Text(game.playlistName)
                        }
                        .width(ideal: 120)
                        TableColumn("Status") { game in
                            if game.isCompleted {
                                Text("Completed")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("In Progress")
                                    .foregroundStyle(.green)
                            }
                        }
                        .width(ideal: 90)
                        TableColumn("Progress") { game in
                            Text(game.progress)
                                .monospacedDigit()
                        }
                        .width(ideal: 70)
                        TableColumn("Cards") { game in
                            Text("\(game.numberOfCards)")
                                .monospacedDigit()
                        }
                        .width(ideal: 50)
                        TableColumn("Created") { game in
                            Text(game.creationDate, style: .date)
                                .foregroundStyle(.secondary)
                        }
                        .width(ideal: 100)
                    }
                    .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                        if let id = ids.first,
                           let game = bingoGames.first(where: { $0.persistentModelID == id }) {
                            Button("Delete", role: .destructive) {
                                tableSelection = nil
                                BingoGameService.delete(game, in: modelContext)
                            }
                        }
                    } primaryAction: { ids in
                        guard let id = ids.first else { return }
                        onSelect(id)
                    }
                }
            }
        }
        .navigationTitle("Bingo Games")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Bingo Game")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            BingoGameCreateSheet { game in
                onSelect(game.persistentModelID)
            }
        }
    }

    // MARK: - Filtered & Sorted

    private var filteredBingoGames: [BingoGame] {
        guard !searchText.isEmpty else { return bingoGames }
        let query = searchText.lowercased()
        return bingoGames.filter {
            $0.name.lowercased().contains(query) ||
            $0.playlistName.lowercased().contains(query)
        }
    }

    private var sortedBingoGames: [BingoGame] {
        filteredBingoGames.sorted(using: sortOrder)
    }
}

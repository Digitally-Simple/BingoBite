import SwiftUI
import SwiftData

struct BingoSetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BingoSet.creationDate) private var bingoSets: [BingoSet]
    var onSelect: (PersistentIdentifier) -> Void
    var songs: [Song]

    @State private var tableSelection: PersistentIdentifier?
    @State private var sortOrder = [KeyPathComparator(\BingoSet.name)]
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
                if bingoSets.isEmpty {
                    ContentUnavailableView(
                        "No Bingo Sets",
                        systemImage: "square.grid.3x3.fill",
                        description: Text("Create a bingo set from a playlist to get started.")
                    )
                } else {
                    Table(sortedBingoSets, selection: $tableSelection, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Playlist") { bingoSet in
                            Text(bingoSet.playlistName)
                        }
                        .width(ideal: 120)
                        TableColumn("Cards") { bingoSet in
                            Text("\(bingoSet.numberOfCards)")
                                .monospacedDigit()
                        }
                        .width(ideal: 60)
                        TableColumn("Songs") { bingoSet in
                            Text("\(bingoSet.songCount)")
                                .monospacedDigit()
                        }
                        .width(ideal: 60)
                        TableColumn("Free Space") { bingoSet in
                            Text(bingoSet.hasFreeSpace ? "Yes" : "No")
                        }
                        .width(ideal: 80)
                        TableColumn("Created") { bingoSet in
                            Text(bingoSet.creationDate, style: .date)
                                .foregroundStyle(.secondary)
                        }
                        .width(ideal: 100)
                    }
                    .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                        if let id = ids.first,
                           let bingoSet = bingoSets.first(where: { $0.persistentModelID == id }) {
                            Button("Delete", role: .destructive) {
                                tableSelection = nil
                                BingoSetService.delete(bingoSet, in: modelContext)
                            }
                        }
                    } primaryAction: { ids in
                        guard let id = ids.first else { return }
                        onSelect(id)
                    }
                }
            }
        }
        .navigationTitle("Bingo Sets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Bingo Set")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            BingoSetCreateSheet(songs: songs)
        }
    }

    // MARK: - Filtered & Sorted

    private var filteredBingoSets: [BingoSet] {
        guard !searchText.isEmpty else { return bingoSets }
        let query = searchText.lowercased()
        return bingoSets.filter {
            $0.name.lowercased().contains(query) ||
            $0.playlistName.lowercased().contains(query)
        }
    }

    private var sortedBingoSets: [BingoSet] {
        filteredBingoSets.sorted(using: sortOrder)
    }
}

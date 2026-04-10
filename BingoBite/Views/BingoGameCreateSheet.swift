import SwiftUI
import SwiftData

struct BingoGameCreateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.creationDate) private var playlists: [Playlist]
    var onCreate: (BingoGame) -> Void

    @State private var selectedPlaylistID: PersistentIdentifier?
    @State private var name = ""

    private var selectedPlaylist: Playlist? {
        guard let id = selectedPlaylistID else { return nil }
        return playlists.first { $0.persistentModelID == id }
    }

    private var isValid: Bool {
        selectedPlaylistID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Bingo Game")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Picker("Playlist", selection: $selectedPlaylistID) {
                    Text("Select a playlist…")
                        .tag(nil as PersistentIdentifier?)
                    ForEach(playlists) { playlist in
                        Text("\(playlist.name) (\(playlist.songCount) songs, \(playlist.numberOfCards) cards)")
                            .tag(playlist.persistentModelID as PersistentIdentifier?)
                    }
                }

                TextField("Game Name (optional)", text: $name)
                    .help("Leave blank to auto-generate from the playlist name and date")
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Start Game") {
                    guard let playlist = selectedPlaylist else { return }
                    let game = BingoGameService.create(
                        name: name,
                        playlist: playlist,
                        in: modelContext
                    )
                    dismiss()
                    onCreate(game)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480, height: 280)
    }
}

import SwiftUI
import SwiftData

struct BingoSetCreateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    var songs: [Song]

    @State private var name = ""
    @State private var selectedPlaylistUUID: String?
    @State private var numberOfCards = 10
    @State private var hasFreeSpace = true

    private var selectedPlaylist: Playlist? {
        guard let uuid = selectedPlaylistUUID else { return nil }
        return playlists.first { $0.uuid == uuid }
    }

    private var requiredSongs: Int {
        hasFreeSpace ? 24 : 25
    }

    private var isValid: Bool {
        guard !name.isEmpty else { return false }
        guard let playlist = selectedPlaylist else { return false }
        return playlist.songCount >= requiredSongs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Bingo Set")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                TextField("Name", text: $name)

                Picker("Playlist", selection: $selectedPlaylistUUID) {
                    Text("Select a playlist...")
                        .tag(nil as String?)
                    ForEach(playlists) { playlist in
                        Text("\(playlist.name) (\(playlist.songCount) songs)")
                            .tag(playlist.uuid as String?)
                    }
                }

                Stepper("Number of Cards: \(numberOfCards)", value: $numberOfCards, in: 1...100)

                Toggle("Free Space (center)", isOn: $hasFreeSpace)

                if let playlist = selectedPlaylist, playlist.songCount < requiredSongs {
                    Text("Playlist needs at least \(requiredSongs) songs (has \(playlist.songCount)).")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Create") {
                    guard let playlist = selectedPlaylist else { return }
                    _ = BingoSetService.create(
                        name: name,
                        playlist: playlist,
                        songs: songs,
                        numberOfCards: numberOfCards,
                        hasFreeSpace: hasFreeSpace,
                        in: modelContext
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 450, height: 350)
    }
}

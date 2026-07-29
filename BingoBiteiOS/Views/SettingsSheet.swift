import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var playlists: [Playlist]
    @Query private var games: [BingoGame]

    @State private var suggestedFolders: [URL] = []

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Playlists", value: "\(playlists.count)")
                    LabeledContent("Bingo games", value: "\(games.count)")
                    LabeledContent("Version", value: version)
                } header: {
                    Text("Library")
                }

                Section {
                    if suggestedFolders.isEmpty {
                        Text("No music folders yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestedFolders, id: \.self) { folder in
                            Label(folder.lastPathComponent, systemImage: "folder.fill")
                        }
                    }
                } header: {
                    Text("Music in the BingoBite Folder")
                } footer: {
                    Text("Open the **Files** app and go to **On My iPad › BingoBite** to add or remove music folders. Playlists can also point at folders anywhere else in Files.")
                }

                Section {
                    LabeledContent("Audio formats", value: FolderScannerService.supportedExtensions.sorted().joined(separator: ", "))
                } footer: {
                    Text("Song tags — including Genius annotations, credits, and links written by Music Downloader — are read directly from each file.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                suggestedFolders = SongsFolderService.suggestedFolders()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

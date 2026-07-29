import SwiftUI

/// Swaps a missing track for another file from the same source folder, so the
/// already-printed cards stay valid.
struct TrackReplacementSheet: View {
    let missingTrack: PlaylistService.MissingTrack
    let availableSongs: [Song]
    let onReplace: (Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedID: Song.ID?

    private var filtered: [Song] {
        guard !searchText.isEmpty else { return availableSongs }
        return availableSongs.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.displayArtist.localizedCaseInsensitiveContains(searchText) ||
            $0.fileName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableSongs.isEmpty {
                    ContentUnavailableView {
                        Label("No Spare Tracks", systemImage: "music.note.list")
                    } description: {
                        Text("Every audio file in the source folder is already used by this playlist. Add more songs to the folder in Files, then try again.")
                    }
                } else {
                    List(filtered, selection: $selectedID) { song in
                        HStack(spacing: 12) {
                            ArtworkView(data: song.artworkData, corner: 8)
                                .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.displayTitle).lineLimit(1)
                                Text(song.displayArtist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(song.formattedDuration)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)

                            if selectedID == song.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = song.id }
                    }
                    .searchable(text: $searchText, prompt: "Search songs")
                }
            }
            .navigationTitle("Replace Missing Track")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Label("Replacing “\(missingTrack.originalFileName)”", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") {
                        if let song = availableSongs.first(where: { $0.id == selectedID }) {
                            onReplace(song)
                        }
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(selectedID == nil)
                }
            }
        }
    }
}

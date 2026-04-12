import SwiftUI

struct TrackReplacementSheet: View {
    let missingTrack: PlaylistService.MissingTrack
    let availableSongs: [Song]
    let onReplace: (Song) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedSongID: Song.ID?

    private var filteredSongs: [Song] {
        if searchText.isEmpty { return availableSongs }
        return availableSongs.filter { song in
            song.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            song.displayArtist.localizedCaseInsensitiveContains(searchText) ||
            song.fileName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            songList
            Divider()
            footer
        }
        .frame(width: 500, height: 450)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Replace Missing Track")
                .font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(missingTrack.originalFileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Select a replacement from the source folder. Only tracks not already in the playlist are shown.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("Search songs\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 4)
        }
        .padding()
    }

    // MARK: - Song List

    private var songList: some View {
        List(filteredSongs, selection: $selectedSongID) { song in
            HStack(spacing: 10) {
                Group {
                    if let image = song.artworkImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                            Image(systemName: "music.note")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.body)
                        .lineLimit(1)
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
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if availableSongs.isEmpty {
                Text("No unassigned tracks in the source folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(filteredSongs.count) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Replace") {
                if let id = selectedSongID,
                   let song = availableSongs.first(where: { $0.id == id }) {
                    onReplace(song)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedSongID == nil)
        }
        .padding()
    }
}

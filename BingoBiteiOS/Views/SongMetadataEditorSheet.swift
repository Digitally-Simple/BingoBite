import SwiftUI
import SwiftData
import PhotosUI

/// Per-song tag overrides. The audio file itself is never modified — edits are
/// stored as a `SongMetadataOverride` and layered on at load time.
struct SongMetadataEditorSheet: View {
    let song: Song
    var onSave: (Song) -> Void
    var onRevert: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var year = ""
    @State private var genre = ""
    @State private var comments = ""
    @State private var artworkData: Data?
    @State private var artworkChanged = false
    @State private var photoItem: PhotosPickerItem?
    @State private var hasOverride = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 20) {
                        ArtworkView(data: artworkData, corner: Glassware.tileCorner, placeholderScale: 0.28)
                            .frame(width: 132, height: 132)

                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Choose Artwork", systemImage: "photo")
                            }
                            .buttonStyle(.glass)

                            if artworkData != nil {
                                Button("Remove Artwork", systemImage: "trash", role: .destructive) {
                                    artworkData = nil
                                    artworkChanged = true
                                }
                                .buttonStyle(.glass)
                            }

                            Text(song.fileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Text("\(song.formattedDuration) · \(song.formattedFileSize)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                Section("Tags") {
                    LabeledContent("Title") {
                        TextField("Title", text: $title).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Artist") {
                        TextField("Artist", text: $artist).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Album") {
                        TextField("Album", text: $album).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Year") {
                        TextField("Year", text: $year)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    LabeledContent("Genre") {
                        TextField("Genre", text: $genre).multilineTextAlignment(.trailing)
                    }
                }

                Section("Comments") {
                    TextField("Notes", text: $comments, axis: .vertical)
                        .lineLimit(3...8)
                }

                if hasOverride {
                    Section {
                        Button("Revert to File Tags", systemImage: "arrow.uturn.backward", role: .destructive) {
                            SongMetadataService.remove(for: song, in: modelContext)
                            onRevert()
                            dismiss()
                        }
                    } footer: {
                        Text("Discards your edits and re-reads the tags stored in the audio file.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await MainActor.run {
                        artworkData = ImageOverlay.downsampledData(from: data, maxDimension: 800) ?? data
                        artworkChanged = true
                        photoItem = nil
                    }
                }
            }
        }
    }

    private func load() {
        title = song.title ?? ""
        artist = song.artist ?? ""
        album = song.album ?? ""
        year = song.year ?? ""
        genre = song.genre ?? ""
        comments = song.comments ?? ""
        artworkData = song.artworkData
        artworkChanged = false
        hasOverride = SongMetadataService.fetch(for: song, in: modelContext) != nil
    }

    private func save() {
        let artwork = artworkChanged ? artworkData : song.artworkData

        SongMetadataService.save(
            for: song,
            title: trimmed(title),
            artist: trimmed(artist),
            album: trimmed(album),
            artworkData: artwork,
            genre: trimmed(genre),
            year: trimmed(year),
            comments: trimmed(comments),
            in: modelContext
        )

        var updated = song
        updated.title = trimmed(title)
        updated.artist = trimmed(artist)
        updated.album = trimmed(album)
        updated.genre = trimmed(genre)
        updated.year = trimmed(year)
        updated.comments = trimmed(comments)
        Song.clearCachedImage(for: song.id)
        updated.artworkData = artwork

        onSave(updated)
        dismiss()
    }

    private func trimmed(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

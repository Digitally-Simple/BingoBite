import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Per-song inspector with metadata view/edit, artwork management,
/// and read-only Song Facts (parsed from the comment tag written by Music Downloader).
struct SongMetadataEditorSheet: View {
    let song: Song
    var onSave: (Song) -> Void
    var onRevert: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Edit mode state
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editArtist = ""
    @State private var editAlbum = ""
    @State private var editYear = ""
    @State private var editGenre = ""
    @State private var editComments = ""
    @State private var editArtworkData: Data?
    @State private var artworkChanged = false

    // Existing override check
    @State private var hasExistingOverride = false

    var body: some View {
        VStack(spacing: 0) {
            // File info row
            fileInfoRow
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    // Left: tags
                    VStack(alignment: .leading, spacing: 16) {
                        tagsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right: artwork
                    ArtworkDropZone(
                        artworkData: isEditing ? editArtworkData : song.artworkData,
                        artworkURL: nil,
                        isEditable: isEditing,
                        onArtworkChanged: { data in
                            editArtworkData = data
                            artworkChanged = true
                        }
                    )
                }
                .padding(20)

                if !isEditing {
                    VStack(alignment: .leading, spacing: 16) {
                        songFactsSection
                    }
                    .disclosureGroupStyle(TappableDisclosureGroupStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }

            Divider()

            actionsSection
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 660, height: 620)
        .onAppear { loadValues() }
    }

    // MARK: - File info row

    private var fileInfoRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("File:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(song.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 4) {
                Text("Size:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(song.formattedFileSize)
                    .font(.caption)
            }

            HStack(spacing: 4) {
                Text("Duration:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(song.formattedDuration)
                    .font(.caption)
            }

            Spacer()
        }
    }

    // MARK: - Tags section

    @ViewBuilder
    private var tagsSection: some View {
        HStack {
            sectionLabel("Tags")
            Spacer()
            Button {
                if isEditing {
                    isEditing = false
                    artworkChanged = false
                } else {
                    enterEditMode()
                }
            } label: {
                Text(isEditing ? "Cancel" : "Edit")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        if isEditing {
            editableFields
        } else {
            readOnlyFields
        }
    }

    // MARK: - Read-only fields (view mode)

    @ViewBuilder
    private var readOnlyFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(label: "Title", value: song.displayTitle)
            infoRow(label: "Artist", value: song.artist ?? "—")
            infoRow(label: "Album", value: song.album ?? "—")
            infoRow(label: "Year", value: song.year ?? "—")
            infoRow(label: "Genre", value: song.genre ?? "—")
            if let comments = song.comments, !comments.isEmpty {
                infoRow(label: "Comments", value: comments)
            }
        }
    }

    // MARK: - Editable fields (edit mode)

    @ViewBuilder
    private var editableFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            editRow(label: "Title", text: $editTitle)
            editRow(label: "Artist", text: $editArtist)
            editRow(label: "Album", text: $editAlbum)
            editRow(label: "Year", text: $editYear)
            editRow(label: "Genre", text: $editGenre)

            HStack(alignment: .top, spacing: 10) {
                Text("Comments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                    .padding(.top, 4)
                TextEditor(text: $editComments)
                    .font(.caption)
                    .frame(height: 60)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func editRow(label: String, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    private func enterEditMode() {
        editTitle = song.title ?? ""
        editArtist = song.artist ?? ""
        editAlbum = song.album ?? ""
        editYear = song.year ?? ""
        editGenre = song.genre ?? ""
        editComments = song.comments ?? ""
        editArtworkData = song.artworkData
        artworkChanged = false
        isEditing = true
    }

    // MARK: - Song Facts (view mode only)

    @ViewBuilder
    private var songFactsSection: some View {
        let desc = song.songDescription
        let annotations = song.annotations ?? []
        let hasFacts = (desc != nil && !desc!.isEmpty) || !annotations.isEmpty

        if hasFacts {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Song Facts")

                if let desc, !desc.isEmpty {
                    DisclosureGroup("About This Song") {
                        Text(desc)
                            .font(.caption)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                }

                let verified = annotations.filter(\.verified)
                let accepted = annotations.filter { !$0.verified }

                if !verified.isEmpty {
                    DisclosureGroup("Artist Annotations (\(verified.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(verified.enumerated()), id: \.offset) { _, fact in
                                annotationFactView(fact)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                }

                if !accepted.isEmpty {
                    DisclosureGroup("Top Annotations (\(accepted.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(accepted.enumerated()), id: \.offset) { _, fact in
                                annotationFactView(fact)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                }
            }
        }
    }

    private func annotationFactView(_ fact: AnnotationFact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\"\(fact.fragment.prefix(120))\"")
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(fact.body)
                .font(.caption)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Text(fact.authors)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if fact.verified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else {
                    Text("\(fact.votes) votes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
        }
    }

    // MARK: - Actions bar

    @ViewBuilder
    private var actionsSection: some View {
        HStack(spacing: 8) {
            if hasExistingOverride {
                Button("Revert to Original") {
                    SongMetadataService.remove(for: song, in: modelContext)
                    onRevert()
                    dismiss()
                }
            }

            Spacer()

            Button("Close") { dismiss() }

            if isEditing {
                Button {
                    saveEdits()
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Loading

    private func loadValues() {
        if SongMetadataService.fetch(for: song, in: modelContext) != nil {
            hasExistingOverride = true
        }
    }

    // MARK: - Save edits

    private func saveEdits() {
        let title = trimOrNil(editTitle)
        let artist = trimOrNil(editArtist)
        let album = trimOrNil(editAlbum)
        let year = trimOrNil(editYear)
        let genre = trimOrNil(editGenre)
        let comments = trimOrNil(editComments)
        let artwork = artworkChanged ? editArtworkData : song.artworkData

        SongMetadataService.save(
            for: song,
            title: title,
            artist: artist,
            album: album,
            artworkData: artwork,
            genre: genre,
            year: year,
            comments: comments,
            in: modelContext
        )

        var updated = song
        updated.title = title
        updated.artist = artist
        updated.album = album
        updated.genre = genre
        updated.year = year
        updated.comments = comments
        Song.clearCachedImage(for: song.id)
        updated.artworkData = artwork

        onSave(updated)
        isEditing = false
        artworkChanged = false
        hasExistingOverride = true
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trimOrNil(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

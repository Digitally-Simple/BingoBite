import SwiftUI
import SwiftData

/// Builds a playlist from a song list pasted out of Music Downloader.
///
/// The manifest in an export folder does this automatically; this is the manual
/// route, for when you want one playlist rather than a whole export, or the
/// list arrived over a message.
struct PastePlaylistSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let libraryURL: URL
    var onCreated: (Playlist) -> Void

    @State private var pastedText = ""
    @State private var matches: [SongListParser.Match] = []
    @State private var playlistName = ""
    @State private var numberOfCards = 30
    @State private var hasFreeSpace = true
    @State private var hasParsed = false
    @State private var resolvingMatch: SongListParser.Match?
    @State private var errorMessage: String?

    private var resolved: [SongListParser.Match] { matches.filter(\.isResolved) }
    private var unresolved: [SongListParser.Match] { matches.filter { !$0.isResolved } }
    private var requiredCount: Int { hasFreeSpace ? 24 : 25 }
    private var canCreate: Bool { resolved.count >= requiredCount }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if hasParsed { resultsSection } else { inputSection }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .glassCard(tint: .orange)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Paste Song List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if hasParsed {
                        Button("Create") { create() }.disabled(!canCreate)
                    } else {
                        Button("Match") { runMatch() }
                            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .sheet(item: $resolvingMatch) { match in
                SongPickerSheet(
                    query: "\(match.line.artist) \(match.line.title)",
                    suggestions: match.suggestions,
                    libraryURL: libraryURL
                ) { chosen in
                    apply(chosen, to: match)
                }
            }
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Song list")
            Text("Paste the list from Music Downloader. Lines look like *Artist — Title*; a leading `#BingoBite Playlist:` line sets the name.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $pastedText)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button {
                if let clip = UIPasteboard.general.string { pastedText = clip }
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.glass)
        }
        .glassCard()
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading("Playlist")
                TextField("Name", text: $playlistName)
                    .textFieldStyle(.roundedBorder)
                Stepper("Cards: \(numberOfCards)", value: $numberOfCards, in: 1...500)
                Toggle("Free space in the middle", isOn: $hasFreeSpace)
                    .font(.callout)

                HStack(spacing: 6) {
                    Image(systemName: canCreate ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(canCreate ? .green : .orange)
                    Text("\(resolved.count) of \(matches.count) matched · \(requiredCount) needed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .glassCard()

            if !unresolved.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("Couldn't match")
                    Text("Tap a line to pick the right song, or leave it out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(unresolved) { match in
                        Button {
                            resolvingMatch = match
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.line.artist.isEmpty
                                         ? match.line.title
                                         : "\(match.line.artist) — \(match.line.title)")
                                        .lineLimit(1)
                                    Text(match.rung.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .interactiveGlassCard()
                    }
                }
            }

            if !resolved.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("Matched \(resolved.count)")
                    ForEach(resolved) { match in
                        HStack(spacing: 10) {
                            ArtworkView(data: match.song?.artworkData, corner: 6)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(match.song?.displayTitle ?? "")
                                    .lineLimit(1)
                                Text(match.song?.displayArtist ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .glassCard()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func runMatch() {
        let parsed = SongListParser.parse(pastedText)
        guard !parsed.lines.isEmpty else {
            errorMessage = "No song lines found. Each line should look like “Artist — Title”."
            return
        }
        let songs = LibraryIndexService.songs(in: context, libraryRoot: libraryURL)
        guard !songs.isEmpty else {
            errorMessage = "Your library is empty, so there's nothing to match against."
            return
        }
        matches = SongListParser.match(parsed, against: songs)
        if playlistName.isEmpty { playlistName = parsed.playlistName ?? "Pasted Playlist" }
        hasParsed = true
        errorMessage = nil
    }

    private func apply(_ song: Song, to match: SongListParser.Match) {
        guard let index = matches.firstIndex(where: { $0.id == match.id }) else { return }
        matches[index].song = song
        matches[index].rung = .exact
        resolvingMatch = nil
    }

    private func create() {
        do {
            let songs = resolved.compactMap(\.song)
            let playlist = try PlaylistService.create(
                folderURL: libraryURL,
                includedSongs: songs,
                name: playlistName,
                description: "",
                numberOfCards: numberOfCards,
                hasFreeSpace: hasFreeSpace,
                in: context
            )
            onCreated(playlist)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Picks a library song for a line the parser couldn't resolve.
private struct SongPickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let query: String
    let suggestions: [Song]
    let libraryURL: URL
    var onPick: (Song) -> Void

    @State private var searchText = ""

    private var allSongs: [Song] {
        LibraryIndexService.songs(in: context, libraryRoot: libraryURL)
    }

    private var results: [Song] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return suggestions }
        return allSongs.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(trimmed)
                || $0.displayArtist.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if results.isEmpty {
                            ContentUnavailableView(
                                "No matches",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different search.")
                            )
                            .padding(.top, 40)
                        }
                        ForEach(results) { song in
                            Button {
                                onPick(song)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    ArtworkView(data: song.artworkData, corner: 6)
                                        .frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(song.displayTitle).lineLimit(1)
                                        Text(song.displayArtist)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .interactiveGlassCard()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Choose a Song")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search your library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
            .onAppear { if searchText.isEmpty && suggestions.isEmpty { searchText = query } }
        }
    }
}

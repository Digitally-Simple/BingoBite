import SwiftUI
import SwiftData

/// The master library: every song on the device, once.
///
/// Playlists point at these rather than each owning a copy, so a song used in
/// five playlists is stored one time. Reads from the cached index, so opening
/// this is instant no matter how big the library gets.
struct SongsLibraryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    @Query(sort: [SortDescriptor(\LibraryIndexEntry.artist), SortDescriptor(\LibraryIndexEntry.title)])
    private var entries: [LibraryIndexEntry]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]

    @State private var searchText = ""
    @State private var isSweeping = false
    @State private var sweepProgress: LibraryIndexService.Progress?
    @State private var importCandidates: [ExportFolderImporter.Candidate] = []
    @State private var importingCandidate: ExportFolderImporter.Candidate?
    @State private var errorMessage: String?
    @State private var showingMissingOnly = false
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var showingBatchTrim = false
    @State private var batchNotice: String?
    @State private var selectedPlaylistUUID: String?
    @State private var sortField: SongLibrarySortField = .artist
    @State private var sortDirection: SongLibrarySortDirection = .ascending

    fileprivate enum SongLibrarySortField: String, CaseIterable, Identifiable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case duration = "Duration"
        case added = "Recently Added"
        case missing = "Missing"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .title: "textformat"
            case .artist: "music.mic"
            case .album: "rectangle.stack.fill"
            case .duration: "clock"
            case .added: "calendar.badge.plus"
            case .missing: "exclamationmark.triangle"
            }
        }
    }

    fileprivate enum SongLibrarySortDirection: String, CaseIterable, Identifiable {
        case ascending = "Ascending"
        case descending = "Descending"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .ascending: "arrow.up"
            case .descending: "arrow.down"
            }
        }
    }

    /// Selected entries, in the order they appear in the list.
    private var selectedEntries: [LibraryIndexEntry] {
        filtered.filter { selection.contains($0.relativePath) }
    }

    private var selectedSongs: [Song] {
        selectedEntries
            .filter { !$0.isMissing }
            .map { $0.makeSong(libraryRoot: libraryURL) }
    }

    private var libraryURL: URL { SongsFolderService.libraryURL }

    private var missingCount: Int {
        entries.filter(\.isMissing).count
    }

    private var selectedPlaylist: Playlist? {
        guard let selectedPlaylistUUID else { return nil }
        return playlists.first { $0.uuid == selectedPlaylistUUID }
    }

    private var activePlaylistSongKeys: Set<String>? {
        selectedPlaylist.map { Set($0.songKeys) }
    }

    private var filtered: [LibraryIndexEntry] {
        var base = showingMissingOnly ? entries.filter(\.isMissing) : entries
        if let activePlaylistSongKeys {
            base = base.filter { entry in
                activePlaylistSongKeys.contains { playlistKey in
                    playlistKey.matches(entry)
                }
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            base = base.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || $0.displayArtist.localizedCaseInsensitiveContains(query)
                    || $0.displayAlbum.localizedCaseInsensitiveContains(query)
            }
        }
        return base.sortedForLibrary(using: sortField, direction: sortDirection)
    }

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search songs")
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selection.count == filtered.count ? "Deselect All" : "Select All") {
                        if selection.count == filtered.count {
                            selection.removeAll()
                        } else {
                            selection = Set(filtered.map(\.relativePath))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Trim…") { showingBatchTrim = true }
                        .disabled(selectedSongs.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isSelecting = false
                        selection.removeAll()
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Playlist", selection: $selectedPlaylistUUID) {
                            Text("All Songs").tag(String?.none)
                            ForEach(playlists) { playlist in
                                Text(playlist.name).tag(Optional(playlist.uuid))
                            }
                        }
                    } label: {
                        Label(selectedPlaylist?.name ?? "All Songs", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $sortField) {
                            ForEach(SongLibrarySortField.allCases) { field in
                                Label(field.rawValue, systemImage: field.systemImage).tag(field)
                            }
                        }
                        Divider()
                        Picker("Direction", selection: $sortDirection) {
                            ForEach(SongLibrarySortDirection.allCases) { direction in
                                Label(direction.rawValue, systemImage: direction.systemImage).tag(direction)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: sortDirection.systemImage)
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") { isSelecting = true }
                        .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await sweep() }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(isSweeping)
                }
            }
        }
        .sheet(isPresented: $showingBatchTrim) {
            BatchTrimSheet(songs: selectedSongs) { result in
                batchNotice = result.isEmpty
                    ? "Trims cleared."
                    : "Trimmed \(result.applied.count) song\(result.applied.count == 1 ? "" : "s")."
                isSelecting = false
                selection.removeAll()
            }
        }
        .alert("Done", isPresented: Binding(
            get: { batchNotice != nil },
            set: { if !$0 { batchNotice = nil } }
        )) {
            Button("OK") { batchNotice = nil }
        } message: {
            if let batchNotice { Text(batchNotice) }
        }
        .task { await initialLoad() }
        .refreshable { await sweep() }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
        .sheet(item: $importingCandidate) { candidate in
            ExportImportSheet(candidate: candidate, libraryURL: libraryURL) {
                importCandidates = SongsFolderService.pendingExportFolders().map(ExportFolderImporter.inspect)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSweeping && entries.isEmpty {
            sweepingPlaceholder
        } else if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    if !importCandidates.isEmpty { importBanner }
                    if missingCount > 0 { missingBanner }
                    if let sweepProgress, isSweeping { progressBanner(sweepProgress) }
                    libraryControls

                    if !filtered.isEmpty { SongsLibraryHeader() }

                    ForEach(filtered) { entry in
                        SongsLibraryRow(
                            entry: entry,
                            libraryURL: libraryURL,
                            selectionState: isSelecting
                                ? (selection.contains(entry.relativePath) ? .selected : .unselected)
                                : .notSelecting
                        ) {
                            // In select mode a tap toggles rather than plays —
                            // starting audio while picking twenty songs would
                            // be chaos.
                            if isSelecting {
                                toggle(entry)
                            } else {
                                play(entry)
                            }
                        }
                    }

                    if filtered.isEmpty && !entries.isEmpty {
                        if !searchText.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .padding(.top, 40)
                        } else {
                            ContentUnavailableView {
                                Label("No Songs Match", systemImage: "music.note.list")
                            } description: {
                                Text(selectedPlaylist.map { "No indexed songs were found in \($0.name)." } ?? "No songs match the current filters.")
                            }
                            .padding(.top, 40)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - States

    private var sweepingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
            if let sweepProgress, sweepProgress.total > 0 {
                Text("Reading \(sweepProgress.processed) of \(sweepProgress.total) songs…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ProgressView(value: sweepProgress.fraction)
                    .frame(maxWidth: 280)
            } else {
                Text("Looking for songs…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !importCandidates.isEmpty { importBanner }

                ContentUnavailableView {
                    Label("No songs yet", systemImage: "music.note.list")
                } description: {
                    Text("Connect your iPad and drop songs into **On My iPad › BingoBite › Library**, then pull down to rescan.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var importBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Ready to import")
            ForEach(importCandidates) { candidate in
                Button {
                    importingCandidate = candidate
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .fontWeight(.medium)
                            Text(candidate.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .interactiveGlassCard()
            }
        }
    }

    private var missingBanner: some View {
        Button {
            showingMissingOnly.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(missingCount) song\(missingCount == 1 ? "" : "s") missing")
                        .fontWeight(.medium)
                    Text(showingMissingOnly ? "Showing only missing songs" : "The files were removed from the Library folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(showingMissingOnly ? "Show all" : "Review")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassCard(tint: .orange)
    }

    private var libraryControls: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Playlist", selection: $selectedPlaylistUUID) {
                    Text("All Songs").tag(String?.none)
                    ForEach(playlists) { playlist in
                        Text(playlist.name).tag(Optional(playlist.uuid))
                    }
                }
            } label: {
                Label(selectedPlaylist?.name ?? "All Songs", systemImage: "music.note.list")
                    .lineLimit(1)
            }

            Menu {
                Picker("Sort by", selection: $sortField) {
                    ForEach(SongLibrarySortField.allCases) { field in
                        Label(field.rawValue, systemImage: field.systemImage).tag(field)
                    }
                }
                Divider()
                Picker("Direction", selection: $sortDirection) {
                    ForEach(SongLibrarySortDirection.allCases) { direction in
                        Label(direction.rawValue, systemImage: direction.systemImage).tag(direction)
                    }
                }
            } label: {
                Label("\(sortField.rawValue), \(sortDirection.rawValue.lowercased())", systemImage: sortDirection.systemImage)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("\(filtered.count) / \(entries.count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private func progressBanner(_ progress: LibraryIndexService.Progress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reading song details… \(progress.processed) of \(progress.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: progress.fraction)
        }
        .glassCard()
    }

    // MARK: - Actions

    private func initialLoad() async {
        importCandidates = SongsFolderService.pendingExportFolders().map(ExportFolderImporter.inspect)
        // Only sweep automatically the first time; after that it's on pull-to-
        // refresh, so opening this tab never blocks on disk work.
        let root = LibraryIndexService.root(in: context)
        if root == nil || root?.hasBeenSwept == false {
            await sweep()
        }
    }

    private func sweep() async {
        guard !isSweeping else { return }
        isSweeping = true
        defer { isSweeping = false; sweepProgress = nil }

        do {
            try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            let root = LibraryIndexService.setRoot(url: libraryURL, name: "Library", in: context)
            try await LibraryIndexService.sweep(root: root, in: context) { progress in
                sweepProgress = progress
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ entry: LibraryIndexEntry) {
        if selection.contains(entry.relativePath) {
            selection.remove(entry.relativePath)
        } else {
            selection.insert(entry.relativePath)
        }
    }

    private func play(_ entry: LibraryIndexEntry) {
        guard !entry.isMissing else {
            errorMessage = "“\(entry.displayTitle)” is missing from the Library folder."
            return
        }
        // The cached row only carries a thumbnail; load the real file so
        // playback and full artwork work.
        let song = entry.makeSong(libraryRoot: libraryURL)
        if !audioPlayer.play(song) {
            errorMessage = "Couldn't play “\(entry.displayTitle)”. The file may be damaged or in an unsupported format."
        }
    }
}

private extension String {
    func matches(_ entry: LibraryIndexEntry) -> Bool {
        if self == entry.stableKey { return true }
        if let uid = SongKey.uid(from: self), uid == entry.uid { return true }
        if let path = SongKey.path(from: self), path == entry.relativePath { return true }
        if let fileName = SongKey.fileName(from: self), fileName == entry.fileName { return true }
        return false
    }
}

private extension Array where Element == LibraryIndexEntry {
    func sortedForLibrary(
        using field: SongsLibraryView.SongLibrarySortField,
        direction: SongsLibraryView.SongLibrarySortDirection
    ) -> [LibraryIndexEntry] {
        sorted { lhs, rhs in
            let orderedAscending: Bool
            switch field {
            case .title:
                orderedAscending = compare(lhs.displayTitle, rhs.displayTitle, fallback: lhs.displayArtist, rhsFallback: rhs.displayArtist)
            case .artist:
                orderedAscending = compare(lhs.displayArtist, rhs.displayArtist, fallback: lhs.displayTitle, rhsFallback: rhs.displayTitle)
            case .album:
                orderedAscending = compare(lhs.displayAlbum, rhs.displayAlbum, fallback: lhs.displayTitle, rhsFallback: rhs.displayTitle)
            case .duration:
                orderedAscending = lhs.duration == rhs.duration
                    ? compare(lhs.displayTitle, rhs.displayTitle)
                    : lhs.duration < rhs.duration
            case .added:
                orderedAscending = lhs.addedAt == rhs.addedAt
                    ? compare(lhs.displayTitle, rhs.displayTitle)
                    : lhs.addedAt < rhs.addedAt
            case .missing:
                orderedAscending = lhs.isMissing == rhs.isMissing
                    ? compare(lhs.displayTitle, rhs.displayTitle)
                    : !lhs.isMissing && rhs.isMissing
            }
            return direction == .ascending ? orderedAscending : !orderedAscending
        }
    }

    private func compare(
        _ lhs: String,
        _ rhs: String,
        fallback: String = "",
        rhsFallback: String = ""
    ) -> Bool {
        let result = lhs.localizedStandardCompare(rhs)
        if result == .orderedSame {
            return fallback.localizedStandardCompare(rhsFallback) == .orderedAscending
        }
        return result == .orderedAscending
    }
}

extension ExportFolderImporter.Candidate {
    var summary: String {
        var parts = ["\(audioFileCount) song\(audioFileCount == 1 ? "" : "s")"]
        if playlistCount > 0 {
            parts.append("\(playlistCount) playlist\(playlistCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

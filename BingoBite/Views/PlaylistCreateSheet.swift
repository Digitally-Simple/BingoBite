import SwiftUI
import SwiftData
import AppKit

struct PlaylistCreateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Folder state
    @State private var pickedFolder: URL?
    @State private var accessedURL: URL?
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var scannedSongs: [Song] = []

    // Identity
    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var nameEditedByUser = false

    // Inclusion toggles keyed by absolute URL string
    @State private var excluded: Set<String> = []

    // Card settings
    @State private var numberOfCards: Int = 10
    @State private var hasFreeSpace: Bool = true

    // Create feedback
    @State private var createError: String?
    @State private var songSearch = ""
    @State private var cardCountText = "10"

    // Completion callback — parent can use this to select the new playlist
    var onCreated: (Playlist) -> Void = { _ in }

    private var requiredSongs: Int { hasFreeSpace ? 24 : 25 }

    static let cardRange = 1...500

    private func clampCardCount() {
        numberOfCards = min(max(numberOfCards, Self.cardRange.lowerBound), Self.cardRange.upperBound)
        cardCountText = String(numberOfCards)
    }

    private var isSearching: Bool {
        !songSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The songs the list is currently showing. Include/exclude act on this,
    /// not on everything scanned.
    private var visibleSongs: [Song] {
        let query = songSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scannedSongs }
        return scannedSongs.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.displayArtist.localizedCaseInsensitiveContains(query)
                || ($0.album?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func include(_ songs: [Song]) {
        for song in songs { excluded.remove(song.id.absoluteString) }
    }

    private func exclude(_ songs: [Song]) {
        for song in songs { excluded.insert(song.id.absoluteString) }
    }

    private var includedSongs: [Song] {
        scannedSongs.filter { !excluded.contains($0.id.absoluteString) }
    }

    private var canCreate: Bool {
        pickedFolder != nil
            && !isScanning
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && includedSongs.count >= requiredSongs
            && numberOfCards >= 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Playlist")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    releaseAccess()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    folderSection
                    if pickedFolder != nil {
                        identitySection
                        // Cards before the song list: the list runs to hundreds
                        // of rows, and burying the card settings under it means
                        // scrolling the whole library to change a number.
                        cardsSection
                        songsSection
                    }
                    if let createError {
                        Text(createError)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Create") {
                    performCreate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
            .padding()
        }
        .frame(width: 580, height: 680)
    }

    // MARK: - Sections

    @ViewBuilder
    private var folderSection: some View {
        GroupBox("Folder") {
            VStack(alignment: .leading, spacing: 8) {
                if let pickedFolder {
                    Text(pickedFolder.path)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .font(.callout)
                        .help(pickedFolder.path)
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Button(pickedFolder == nil ? "Choose Folder…" : "Change Folder…") {
                    chooseFolder()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        GroupBox("Name") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Playlist name", text: Binding(
                    get: { name },
                    set: { newValue in
                        name = newValue
                        nameEditedByUser = true
                    }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Description (optional)", text: $descriptionText)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private var songsSection: some View {
        GroupBox("Songs") {
            VStack(alignment: .leading, spacing: 8) {
                if isScanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Scanning folder…")
                            .foregroundStyle(.secondary)
                    }
                } else if let scanError {
                    Text(scanError)
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if scannedSongs.isEmpty {
                    Text("No supported audio files found.\nSupported: mp3, m4a, flac, wav, opus")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    HStack {
                        Text("Included: \(includedSongs.count) of \(scannedSongs.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        // While filtering, these act on what's shown — clearing
                        // hidden songs after a search would be a nasty surprise.
                        Button(isSearching ? "Include Shown" : "Include All") {
                            include(visibleSongs)
                        }
                        .controlSize(.small)
                        Button(isSearching ? "Exclude Shown" : "Exclude All") {
                            exclude(visibleSongs)
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search these songs", text: $songSearch)
                            .textFieldStyle(.plain)
                        if !songSearch.isEmpty {
                            Button {
                                songSearch = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if visibleSongs.isEmpty {
                                Text("No songs match “\(songSearch)”.")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                                    .padding(8)
                            }
                            ForEach(visibleSongs) { song in
                                songRow(song)
                            }
                        }
                    }
                    .frame(height: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                    if includedSongs.count < requiredSongs {
                        Text("Need at least \(requiredSongs) songs included (currently \(includedSongs.count)).")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private func songRow(_ song: Song) -> some View {
        let key = song.id.absoluteString
        let isIncluded = !excluded.contains(key)
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isIncluded },
                set: { newValue in
                    if newValue {
                        excluded.remove(key)
                    } else {
                        excluded.insert(key)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            if let nsImage = song.artworkImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(song.artist ?? "Unknown Artist") · \(song.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var cardsSection: some View {
        GroupBox("Cards") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Number of Cards")
                    // Typing beats holding a stepper when a venue wants 100.
                    // String-backed so non-digits are filtered rather than
                    // silently reverted on commit.
                    TextField("10", text: $cardCountText)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .onSubmit { clampCardCount() }
                    Stepper("Number of Cards", value: $numberOfCards, in: Self.cardRange)
                        .labelsHidden()
                    Spacer()
                }
                Toggle("Free Space (center)", isOn: $hasFreeSpace)
            }
            .onAppear { cardCountText = String(numberOfCards) }
            .onChange(of: cardCountText) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(3))
                if digits != newValue { cardCountText = digits }
                if let value = Int(digits) { numberOfCards = value }
            }
            .onChange(of: numberOfCards) { _, newValue in
                if Int(cardCountText) != newValue { cardCountText = String(newValue) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing audio files"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Release any previously accessed URL
        releaseAccess()

        guard BookmarkService.startAccessing(url) else {
            scanError = "Unable to access the selected folder."
            return
        }
        accessedURL = url
        pickedFolder = url
        scanError = nil
        scannedSongs = []
        excluded = []
        if !nameEditedByUser {
            name = url.lastPathComponent
        }
        Task {
            await scanPickedFolder()
        }
    }

    @MainActor
    private func scanPickedFolder() async {
        guard let folder = pickedFolder else { return }
        isScanning = true
        scanError = nil
        do {
            let songs = try await FolderScannerService.scanForAudio(in: folder)
            scannedSongs = songs
        } catch {
            scanError = "Failed to scan folder: \(error.localizedDescription)"
            scannedSongs = []
        }
        isScanning = false
    }

    private func performCreate() {
        guard let folder = pickedFolder else { return }
        createError = nil
        do {
            let playlist = try PlaylistService.create(
                folderURL: folder,
                includedSongs: includedSongs,
                name: name,
                description: descriptionText,
                numberOfCards: numberOfCards,
                hasFreeSpace: hasFreeSpace,
                in: modelContext
            )
            releaseAccess()
            onCreated(playlist)
            dismiss()
        } catch {
            createError = error.localizedDescription
        }
    }

    private func releaseAccess() {
        if let accessedURL {
            BookmarkService.stopAccessing(accessedURL)
        }
        accessedURL = nil
    }
}

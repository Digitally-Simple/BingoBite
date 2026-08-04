import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Creates a playlist from a folder of audio files.
///
/// Folders can come from two places: the app's own **BingoBite** folder in
/// Files (offered as one-tap suggestions) or anywhere else in Files via the
/// document picker, which hands back a security-scoped URL.
struct PlaylistCreateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onCreated: (Playlist) -> Void

    // Folder
    @State private var pickedFolder: URL?
    @State private var accessedURL: URL?
    @State private var suggestions: [URL] = []
    @State private var showFolderPicker = false

    // Scan
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var scannedSongs: [Song] = []
    @State private var excluded: Set<String> = []

    // Identity
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var nameEditedByUser = false

    // Cards
    @State private var numberOfCards = 10
    @State private var hasFreeSpace = true

    @State private var createError: String?
    @State private var songSearch = ""
    @State private var cardCountText = "10"
    @FocusState private var cardCountFocused: Bool

    /// True when songs came from the master library rather than a folder scan.
    /// Library songs are read from the cached index, so no disk scan happens.
    @State private var usingLibrary = false
    @State private var librarySongCount = 0

    private var requiredSongs: Int { hasFreeSpace ? 24 : 25 }
    private var includedSongs: [Song] { scannedSongs.filter { !excluded.contains($0.id.absoluteString) } }

    private var isSearching: Bool {
        !songSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The songs the list is currently showing. Include/exclude actions operate
    /// on this rather than on everything scanned.
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

    private var canCreate: Bool {
        pickedFolder != nil
            && !isScanning
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && includedSongs.count >= requiredSongs
            && numberOfCards >= 1
    }

    var body: some View {
        NavigationStack {
            Form {
                folderSection
                if pickedFolder != nil {
                    detailsSection
                    // Cards before the song list: the list runs to hundreds of
                    // rows, and burying the card settings under it means
                    // scrolling the whole library to change a number.
                    cardsSection
                    songsSection
                }
                if let createError {
                    Section {
                        Label(createError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        releaseAccess()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: performCreate)
                        .buttonStyle(.glassProminent)
                        .disabled(!canCreate)
                }
                // The number pad has no return key, so the card count needs an
                // explicit way out.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { cardCountFocused = false }
                }
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderPick(result)
            }
            .onAppear {
                suggestions = SongsFolderService.suggestedFolders()
                librarySongCount = LibraryIndexService.allEntries(in: modelContext)
                    .count { !$0.isMissing }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Folder

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if let pickedFolder {
                LabeledContent(usingLibrary ? "Source" : "Folder") {
                    Text(usingLibrary
                         ? "Your library — \(scannedSongs.count) songs"
                         : SongsFolderService.displayPath(for: pickedFolder))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Button("Choose a Different Folder", systemImage: "folder") {
                    usingLibrary = false
                    showFolderPicker = true
                }
            } else {
                // The library first: it's the space-saving option, and for
                // anyone using Music Downloader it's where everything already is.
                if librarySongCount > 0 {
                    Button {
                        selectLibrary()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "books.vertical.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use My Library")
                                    .foregroundStyle(.primary)
                                Text("\(librarySongCount) songs · no extra copies on disk")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if !suggestions.isEmpty || SongsFolderService.documentsRootHasAudio() {
                    if SongsFolderService.documentsRootHasAudio() {
                        folderButton(SongsFolderService.documentsURL, subtitle: "Loose files in the BingoBite folder")
                    }
                    ForEach(suggestions, id: \.self) { folder in
                        folderButton(folder, subtitle: "In the BingoBite folder")
                    }
                }

                Button("Browse Files…", systemImage: "folder.badge.plus") {
                    showFolderPicker = true
                }
            }
        } header: {
            Text("Music Folder")
        } footer: {
            if pickedFolder == nil {
                Text("Drop a folder of songs into **On My iPad › BingoBite** in the Files app and it will appear here. You can also browse to any other folder, including iCloud Drive.")
            } else {
                Text("Supported formats: \(FolderScannerService.supportedExtensions.sorted().joined(separator: ", ")).")
            }
        }
    }

    private func folderButton(_ folder: URL, subtitle: String) -> some View {
        Button {
            select(folder: folder, isSecurityScoped: false)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.lastPathComponent)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section("Details") {
            TextField("Playlist name", text: Binding(
                get: { name },
                set: { name = $0; nameEditedByUser = true }
            ))
            TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                .lineLimit(1...3)
        }
    }

    // MARK: - Songs

    @ViewBuilder
    private var songsSection: some View {
        Section {
            if isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading tags…").foregroundStyle(.secondary)
                }
            } else if let scanError {
                Label(scanError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if scannedSongs.isEmpty {
                Text("No supported audio files in this folder.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search these songs", text: $songSearch)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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

                if visibleSongs.isEmpty {
                    Text("No songs match “\(songSearch)”.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleSongs) { song in
                        songRow(song)
                    }
                }
            }
        } header: {
            HStack {
                Text("Songs")
                Spacer()
                if !scannedSongs.isEmpty && !isScanning {
                    Text("\(includedSongs.count) of \(scannedSongs.count) included")
                        .font(.caption)
                        .textCase(nil)
                    // While a search is active these act on what's visible —
                    // "None" silently clearing hidden songs would be a nasty
                    // surprise after filtering to three of two hundred.
                    Button(isSearching ? "All Shown" : "All") { include(visibleSongs) }
                        .font(.caption)
                        .textCase(nil)
                    Button(isSearching ? "None Shown" : "None") { exclude(visibleSongs) }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        } footer: {
            if !scannedSongs.isEmpty, includedSongs.count < requiredSongs {
                Text("Bingo cards need at least \(requiredSongs) songs — \(includedSongs.count) are included.")
                    .foregroundStyle(.red)
            }
        }
    }

    private func songRow(_ song: Song) -> some View {
        let key = song.id.absoluteString
        let isIncluded = !excluded.contains(key)

        return Button {
            if isIncluded { excluded.insert(key) } else { excluded.remove(key) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isIncluded ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

                ArtworkView(data: song.artworkData, corner: 6)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text("\(song.displayArtist) · \(song.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .opacity(isIncluded ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    private var cardsSection: some View {
        Section("Bingo Cards") {
            LabeledContent("Number of cards") {
                HStack(spacing: 10) {
                    // Typing beats 90 taps on a stepper when a venue wants 100
                    // cards, but the stepper stays for small adjustments.
                    //
                    // Backed by a String rather than `value:format:` because
                    // `.keyboardType` is only a hint to the software keyboard —
                    // an iPad in a keyboard case can type letters straight in.
                    // The digits are filtered here instead.
                    TextField("10", text: $cardCountText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                        .focused($cardCountFocused)

                    Stepper("Number of cards", value: $numberOfCards, in: Self.cardRange)
                        .labelsHidden()
                }
            }
            Toggle("Free space in the center", isOn: $hasFreeSpace)
        }
        .onAppear { cardCountText = String(numberOfCards) }
        .onChange(of: cardCountText) { _, newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(3))
            if digits != newValue { cardCountText = digits }
            if let value = Int(digits) { numberOfCards = value }
        }
        .onChange(of: numberOfCards) { _, newValue in
            // Keep the field in step when the stepper drives the change.
            if Int(cardCountText) != newValue { cardCountText = String(newValue) }
        }
        .onChange(of: cardCountFocused) { _, isFocused in
            // The number pad has no return key, so clamp when focus leaves
            // rather than fighting the user mid-edit.
            if !isFocused { clampCardCount() }
        }
    }

    private static let cardRange = 1...500

    private func clampCardCount() {
        numberOfCards = min(max(numberOfCards, Self.cardRange.lowerBound), Self.cardRange.upperBound)
        cardCountText = String(numberOfCards)
    }

    // MARK: - Actions

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        select(folder: url, isSecurityScoped: true)
    }

    /// Loads songs straight from the library index — no folder scan, no tag
    /// reads, so it's instant no matter how large the library is.
    private func selectLibrary() {
        releaseAccess()
        usingLibrary = true
        pickedFolder = SongsFolderService.libraryURL
        scanError = nil
        excluded = []
        // Missing files can't be played, so they'd only produce dead cards.
        scannedSongs = LibraryIndexService.allEntries(in: modelContext)
            .filter { !$0.isMissing }
            .map { $0.makeSong(libraryRoot: SongsFolderService.libraryURL) }
        if !nameEditedByUser { name = "" }
    }

    private func select(folder: URL, isSecurityScoped: Bool) {
        releaseAccess()
        usingLibrary = false

        // Folders inside the app's own container are readable without a
        // security scope; picker results are not.
        if isSecurityScoped && !SongsFolderService.isAppOwned(folder) {
            guard BookmarkService.startAccessing(folder) else {
                scanError = "BingoBite couldn't open that folder."
                return
            }
            accessedURL = folder
        }

        pickedFolder = folder
        scanError = nil
        scannedSongs = []
        excluded = []
        if !nameEditedByUser {
            name = folder.lastPathComponent
        }
        Task { await scan() }
    }

    @MainActor
    private func scan() async {
        guard let folder = pickedFolder else { return }
        isScanning = true
        scanError = nil
        do {
            scannedSongs = try await FolderScannerService.scanForAudio(in: folder)
        } catch {
            scanError = "Couldn't read that folder: \(error.localizedDescription)"
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

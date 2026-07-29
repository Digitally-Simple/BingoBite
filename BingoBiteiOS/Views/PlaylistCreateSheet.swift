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

    private var requiredSongs: Int { hasFreeSpace ? 24 : 25 }
    private var includedSongs: [Song] { scannedSongs.filter { !excluded.contains($0.id.absoluteString) } }

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
                    songsSection
                    cardsSection
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
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Folder

    @ViewBuilder
    private var folderSection: some View {
        Section {
            if let pickedFolder {
                LabeledContent("Folder") {
                    Text(SongsFolderService.displayPath(for: pickedFolder))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Button("Choose a Different Folder", systemImage: "folder") {
                    showFolderPicker = true
                }
            } else {
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
                ForEach(scannedSongs) { song in
                    songRow(song)
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
                    Button("All") { excluded.removeAll() }
                        .font(.caption)
                        .textCase(nil)
                    Button("None") { excluded = Set(scannedSongs.map(\.id.absoluteString)) }
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
            Stepper("Number of cards: \(numberOfCards)", value: $numberOfCards, in: 1...200)
            Toggle("Free space in the center", isOn: $hasFreeSpace)
        }
    }

    // MARK: - Actions

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        select(folder: url, isSecurityScoped: true)
    }

    private func select(folder: URL, isSecurityScoped: Bool) {
        releaseAccess()

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

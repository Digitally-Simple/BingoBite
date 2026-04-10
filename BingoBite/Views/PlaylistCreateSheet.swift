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

    // Completion callback — parent can use this to select the new playlist
    var onCreated: (Playlist) -> Void = { _ in }

    private var requiredSongs: Int { hasFreeSpace ? 24 : 25 }

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
                        songsSection
                        cardsSection
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
                        Button("Include All") {
                            excluded.removeAll()
                        }
                        .controlSize(.small)
                        Button("Exclude All") {
                            excluded = Set(scannedSongs.map { $0.id.absoluteString })
                        }
                        .controlSize(.small)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(scannedSongs) { song in
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
                Stepper("Number of Cards: \(numberOfCards)", value: $numberOfCards, in: 1...200)
                Toggle("Free Space (center)", isOn: $hasFreeSpace)
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

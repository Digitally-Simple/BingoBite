import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    var onFolderChanged: () -> Void

    private var settings: AppSettings {
        if let existing = settingsItems.first {
            return existing
        }
        let newSettings = AppSettings()
        modelContext.insert(newSettings)
        return newSettings
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Music Folder") {
                VStack(alignment: .leading, spacing: 12) {
                    if settings.folderPath.isEmpty {
                        Text("No folder selected")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(settings.folderPath)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(settings.folderPath)
                    }

                    HStack {
                        Button("Choose Folder...") {
                            chooseFolder()
                        }

                        if !settings.folderPath.isEmpty {
                            Button("Clear") {
                                clearFolder()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox("Genius API") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter your Genius API access token to display song tidbits in the inspector. Get one free at genius.com/api-clients.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("Genius API Key", text: Binding(
                        get: { settings.geniusAPIKey },
                        set: { newValue in
                            settings.geniusAPIKey = newValue
                            try? modelContext.save()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450, height: 380)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing MP3 files"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmarkData = try BookmarkService.createBookmark(for: url)
            settings.folderPath = url.path
            settings.bookmarkData = bookmarkData
            settings.lastScannedDate = nil
            try modelContext.save()
            onFolderChanged()
        } catch {
            print("Failed to create bookmark: \(error)")
        }
    }

    private func clearFolder() {
        settings.folderPath = ""
        settings.bookmarkData = nil
        settings.lastScannedDate = nil
        try? modelContext.save()
        onFolderChanged()
    }
}

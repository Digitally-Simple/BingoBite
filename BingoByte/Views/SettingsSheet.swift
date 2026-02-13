import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    var onFolderChanged: () -> Void
    var onLicenseDeactivated: (() -> Void)? = nil

    @State private var isDeactivating = false
    @State private var deactivationError: String?

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

            GroupBox("License") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Key:")
                            .foregroundStyle(.secondary)
                        Text(maskedLicenseKey)
                            .monospaced()
                    }

                    if let lastValidation = settings.lastLicenseValidationDate {
                        HStack {
                            Text("Last validated:")
                                .foregroundStyle(.secondary)
                            Text(lastValidation, style: .date)
                        }
                    }

                    if let deactivationError {
                        Text(deactivationError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Button(role: .destructive) {
                        deactivateLicense()
                    } label: {
                        if isDeactivating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Deactivate License")
                        }
                    }
                    .disabled(isDeactivating)
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
        .frame(width: 450, height: 520)
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

    private var maskedLicenseKey: String {
        let key = settings.licenseKey
        guard key.count > 8 else { return key }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)****\(suffix)"
    }

    private func deactivateLicense() {
        isDeactivating = true
        deactivationError = nil

        Task {
            do {
                try await LicenseService.deactivate(
                    licenseKey: settings.licenseKey,
                    instanceId: settings.licenseKeyInstanceId
                )
                LicenseService.clearLicense(settings: settings, in: modelContext)
                dismiss()
                onLicenseDeactivated?()
            } catch let error as LicenseError {
                deactivationError = error.errorDescription
            } catch {
                deactivationError = "Failed to deactivate. Please try again."
            }
            isDeactivating = false
        }
    }
}

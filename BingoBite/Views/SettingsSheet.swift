import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    var trialDaysRemaining: Int?
    var onFolderChanged: () -> Void = { }
    var onLicenseDeactivated: (() -> Void)? = nil

    @State private var isDeactivating = false
    @State private var deactivationError: String?
    @State private var licenseKeyInput = ""
    @State private var isActivatingFromSettings = false
    @State private var activationError: String?

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

            GroupBox("License") {
                VStack(alignment: .leading, spacing: 8) {
                    if let days = trialDaysRemaining {
                        HStack {
                            Text("Status:")
                                .foregroundStyle(.secondary)
                            Text("Trial - \(days) \(days == 1 ? "day" : "days") remaining")
                        }

                        Text("Enter a license key to activate the full version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("License Key", text: $licenseKeyInput)
                            .textFieldStyle(.roundedBorder)

                        if let activationError {
                            Text(activationError)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }

                        Button(action: activateLicenseFromSettings) {
                            if isActivatingFromSettings {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Activate License")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivatingFromSettings)
                    } else {
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
        .frame(width: 420, height: 320)
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

    private func activateLicenseFromSettings() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isActivatingFromSettings = true
        activationError = nil

        Task {
            do {
                let response = try await LicenseService.activate(licenseKey: key)
                LicenseService.persistActivation(
                    settings: settings,
                    licenseKey: key,
                    instanceId: response.id,
                    in: modelContext
                )
                dismiss()
                NotificationCenter.default.post(name: .licenseDeactivated, object: nil)
            } catch let error as LicenseError {
                activationError = error.errorDescription
            } catch {
                activationError = "An unexpected error occurred. Please try again."
            }
            isActivatingFromSettings = false
        }
    }
}

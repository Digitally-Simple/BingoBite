import SwiftUI
import SwiftData

struct LicenseGateView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]

    @State private var licenseKeyInput = ""
    @State private var isActivating = false
    @State private var errorMessage: String?

    var onActivated: () -> Void

    private var settings: AppSettings {
        if let existing = settingsItems.first {
            return existing
        }
        let newSettings = AppSettings()
        modelContext.insert(newSettings)
        return newSettings
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Welcome to BingoBite")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Enter your license key to get started.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("License Key", text: $licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)
                    .onSubmit { activateLicense() }

                Button(action: activateLicense) {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 100)
                    } else {
                        Text("Activate")
                            .frame(width: 100)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                .keyboardShortcut(.defaultAction)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .frame(maxWidth: 360)
                }
            }

            Link("Don't have a license key? Purchase BingoBite",
                 destination: URL(string: "https://test.store.dodopayments.com/bingobyte")!)
                .font(.caption)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Pre-fill if returning after grace period expiry
            let stored = settings.licenseKey
            if !stored.isEmpty {
                licenseKeyInput = stored
            }
        }
    }

    private func activateLicense() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isActivating = true
        errorMessage = nil

        Task {
            do {
                // If we already have a stored instance for this key, try validating it first
                let existingInstanceId = settings.licenseKeyInstanceId
                if key == settings.licenseKey, !existingInstanceId.isEmpty {
                    let valid = try await LicenseService.validate(licenseKey: key, instanceId: existingInstanceId)
                    if valid {
                        settings.lastLicenseValidationDate = Date()
                        try? modelContext.save()
                        onActivated()
                        isActivating = false
                        return
                    }
                }

                // No stored instance or it's invalid — create a new activation
                let response = try await LicenseService.activate(licenseKey: key)
                LicenseService.persistActivation(
                    settings: settings,
                    licenseKey: key,
                    instanceId: response.id,
                    in: modelContext
                )
                onActivated()
            } catch let error as LicenseError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "An unexpected error occurred. Please try again."
            }
            isActivating = false
        }
    }
}

//
//  BingoBiteApp.swift
//  BingoBite
//
//  Created by Austin Lackey on 2/7/26.
//

import SwiftUI
import SwiftData
import Sparkle

@main
struct BingoBiteApp: App {
    let container: ModelContainer
    @State private var isLicensed = false
    @State private var hasCheckedLicense = false

    private let updaterController: SPUStandardUpdaterController

    private static let schemaVersionKey = "BingoBite.SchemaVersion"
    private static let currentSchemaVersion = 2

    init() {
        Self.resetStoreIfNeeded()
        let container = try! ModelContainer(for: AppSettings.self, SoundByte.self, Playlist.self, BingoGame.self)
        self.container = container
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private static func resetStoreIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: schemaVersionKey) >= currentSchemaVersion { return }

        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundleID = Bundle.main.bundleIdentifier ?? "BingoBite"
            let storeDir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
            for suffix in ["default.store", "default.store-shm", "default.store-wal"] {
                try? fm.removeItem(at: storeDir.appendingPathComponent(suffix))
            }
        }
        defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCheckedLicense {
                    ProgressView("Checking license...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLicensed {
                    ContentView()
                } else {
                    LicenseGateView {
                        isLicensed = true
                    }
                }
            }
            .task {
                await checkLicense()
            }
            .onReceive(NotificationCenter.default.publisher(for: .licenseDeactivated)) { _ in
                isLicensed = false
            }
        }
        .modelContainer(container)
        .commands {
            InspectorCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }

    @MainActor
    private func checkLicense() async {
        let context = container.mainContext
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? context.fetch(descriptor).first else {
            hasCheckedLicense = true
            return
        }

        let key = settings.licenseKey
        let instanceId = settings.licenseKeyInstanceId

        guard !key.isEmpty, !instanceId.isEmpty else {
            hasCheckedLicense = true
            return
        }

        do {
            let valid = try await LicenseService.validate(licenseKey: key, instanceId: instanceId)
            if valid {
                settings.lastLicenseValidationDate = Date()
                try? context.save()
                isLicensed = true
            } else {
                LicenseService.clearLicense(settings: settings, in: context)
            }
        } catch {
            // Network error — check offline grace period
            if LicenseService.isWithinOfflineGracePeriod(lastValidation: settings.lastLicenseValidationDate) {
                isLicensed = true
            } else {
                // Grace period expired, force re-validation
            }
        }

        hasCheckedLicense = true
    }
}

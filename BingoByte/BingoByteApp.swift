//
//  BingoByteApp.swift
//  BingoByte
//
//  Created by Austin Lackey on 2/7/26.
//

import SwiftUI
import SwiftData

@main
struct BingoByteApp: App {
    let container: ModelContainer
    @State private var isLicensed = false
    @State private var hasCheckedLicense = false

    init() {
        let container = try! ModelContainer(for: AppSettings.self, SoundByte.self, Playlist.self, BingoSet.self, BingoGame.self)
        self.container = container

        // Backfill UUIDs for existing playlists migrated with empty default
        let context = container.mainContext
        let descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.uuid == "" })
        if let playlists = try? context.fetch(descriptor) {
            for playlist in playlists {
                playlist.uuid = UUID().uuidString
            }
            try? context.save()
        }
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

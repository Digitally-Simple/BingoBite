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

    private let updaterController: SPUStandardUpdaterController

    private static let schemaVersionKey = "BingoBite.SchemaVersion"
    private static let currentSchemaVersion = 3

    init() {
        Self.resetStoreIfNeeded()
        let container = try! ModelContainer(for: AppSettings.self, SoundByte.self, Playlist.self, BingoGame.self, SongMetadataOverride.self)
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
            ContentView()
        }
        .modelContainer(container)
        .commands {
            InspectorCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

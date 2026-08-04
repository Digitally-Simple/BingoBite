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

    init() {
        Self.resetStoreIfNeeded()
        let container = Self.makeContainer()
        self.container = container
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Opens the store, archiving and retrying once if it can't be read.
    ///
    /// A schema change that isn't matched by a version bump makes SwiftData
    /// refuse the store outright. On `try!` that was a crash on launch with no
    /// route back short of deleting the app.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            AppSettings.self,
            SoundByte.self,
            Playlist.self,
            BingoGame.self,
            SongMetadataOverride.self,
            LibraryRoot.self,
            LibraryIndexEntry.self,
        ] as [any PersistentModel.Type])

        do {
            return try ModelContainer(for: schema)
        } catch {
            let fm = FileManager.default
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let bundleID = Bundle.main.bundleIdentifier ?? "BingoBite"
                StoreResetService.forceArchive(
                    storeDirectory: appSupport.appendingPathComponent(bundleID, isDirectory: true)
                )
            }
            return try! ModelContainer(for: schema)
        }
    }

    private static func resetStoreIfNeeded() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? "BingoBite"
        StoreResetService.resetIfNeeded(
            storeDirectory: appSupport.appendingPathComponent(bundleID, isDirectory: true)
        )
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

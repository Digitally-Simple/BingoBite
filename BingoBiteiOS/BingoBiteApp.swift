import SwiftUI
import SwiftData

@main
struct BingoBiteApp: App {
    let container: ModelContainer

    private static let schemaVersionKey = "BingoBite.SchemaVersion"
    private static let currentSchemaVersion = 3

    init() {
        Self.resetStoreIfNeeded()
        SongsFolderService.prepareDocumentsFolder()
        container = try! ModelContainer(
            for: AppSettings.self, SoundByte.self, Playlist.self, BingoGame.self, SongMetadataOverride.self
        )
    }

    /// Wipes the store when the schema shape changes, matching the Mac app.
    private static func resetStoreIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: schemaVersionKey) >= currentSchemaVersion { return }

        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            for suffix in ["default.store", "default.store-shm", "default.store-wal"] {
                try? fm.removeItem(at: appSupport.appendingPathComponent(suffix))
            }
        }
        defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // The app is designed as flat black or flat white with a single
                // accent; dark is the one it's tuned for and the one a host is
                // holding in a dim room.
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

import SwiftUI
import SwiftData

@main
struct BingoBiteApp: App {
    let container: ModelContainer

    init() {
        Self.resetStoreIfNeeded()
        SongsFolderService.prepareDocumentsFolder()
        container = Self.makeContainer()
    }

    /// Opens the store, archiving and retrying once if it can't be read.
    ///
    /// A schema change that isn't matched by a version bump makes SwiftData
    /// refuse the store outright. On `try!` that was a crash on launch with no
    /// route back short of deleting the app — so the second attempt moves the
    /// unreadable store aside rather than taking the whole app down with it.
    private static func makeContainer() -> ModelContainer {
        let models: [any PersistentModel.Type] = [
            AppSettings.self,
            SoundByte.self,
            Playlist.self,
            BingoGame.self,
            SongMetadataOverride.self,
            LibraryRoot.self,
            LibraryIndexEntry.self,
        ]
        let schema = Schema(models)

        do {
            return try ModelContainer(for: schema)
        } catch {
            let fm = FileManager.default
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                StoreResetService.forceArchive(storeDirectory: appSupport)
            }
            // Second failure means something is wrong beyond the store file,
            // and there's no sensible way to run without one.
            return try! ModelContainer(for: schema)
        }
    }

    /// Archives and clears the store when the schema shape changes, matching
    /// the Mac app.
    private static func resetStoreIfNeeded() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        StoreResetService.resetIfNeeded(storeDirectory: appSupport)
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

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

    init() {
        let container = try! ModelContainer(for: AppSettings.self, SoundByte.self, Playlist.self, BingoSet.self)
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
            ContentView()
        }
        .modelContainer(container)
        .commands {
            InspectorCommands()
        }
    }
}

import SwiftUI
import SwiftData

struct CardDesignerSheet: View {
    var playlist: Playlist
    var songs: [Song]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var settings: CardDesignSettings
    @State private var isExporting = false
    @State private var selectedOverlayID: String? = nil

    private var cards: [BingoCard] {
        let grids = CardGenerator.decode(from: playlist.cardsData)
        return grids.enumerated().map { index, grid in
            BingoCard(id: index + 1, grid: grid)
        }
    }

    init(playlist: Playlist, songs: [Song]) {
        self.playlist = playlist
        self.songs = songs
        self._settings = State(initialValue: CardDesignSettings.decode(from: playlist.cardDesignData))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainContent
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 700)
        .onDisappear {
            saveSettings()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Design & Print Cards")
                    .font(.headline)
                Text("\(cards.count) cards from \"\(playlist.name)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Main Content

    private var mainContent: some View {
        HSplitView {
            CardDesignControlsView(settings: $settings, selectedOverlayID: $selectedOverlayID)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            CardDesignPreviewView(
                cards: cards,
                songs: songs,
                songURLStrings: playlist.songURLStrings,
                settings: $settings,
                selectedOverlayID: $selectedOverlayID
            )
            .frame(minWidth: 400)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Reset to Defaults") {
                settings = CardDesignSettings()
            }

            Spacer()

            Button("Print\u{2026}") {
                saveSettings()
                CardExportService.printCards(
                    cards: cards,
                    songs: songs,
                    songURLStrings: playlist.songURLStrings,
                    settings: settings
                )
            }
            .disabled(cards.isEmpty)

            Button("Export PDF\u{2026}") {
                saveSettings()
                CardExportService.exportPDF(
                    cards: cards,
                    songs: songs,
                    songURLStrings: playlist.songURLStrings,
                    settings: settings,
                    defaultName: playlist.name
                )
            }
            .keyboardShortcut(.defaultAction)
            .disabled(cards.isEmpty)
        }
        .padding()
    }

    // MARK: - Persistence

    private func saveSettings() {
        playlist.cardDesignData = settings.encode()
        try? modelContext.save()
    }
}

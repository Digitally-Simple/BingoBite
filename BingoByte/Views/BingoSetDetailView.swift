import SwiftUI

struct BingoSetDetailView: View {
    var bingoSet: BingoSet
    @Binding var selectedCard: BingoCard?

    @State private var tableSelection: Int?
    @State private var sortOrder = [KeyPathComparator(\BingoCard.id)]

    private var cards: [BingoCard] {
        BingoSetService.bingoCards(from: bingoSet)
    }

    private let bingoColumns = ["B", "I", "N", "G", "O"]

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            statsBar
            Divider()
            cardsTable
        }
        .navigationTitle(bingoSet.name)
        .onChange(of: tableSelection) {
            if let id = tableSelection {
                selectedCard = cards.first { $0.id == id }
            } else {
                selectedCard = nil
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bingoSet.name)
                .font(.title2.bold())
            Text("Source: \(bingoSet.playlistName)")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem(label: "Cards", value: "\(bingoSet.numberOfCards)")
            statItem(label: "Songs", value: "\(bingoSet.songCount)")
            statItem(label: "Free Space", value: bingoSet.hasFreeSpace ? "Yes" : "No")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cards Table

    private func columnText(card: BingoCard, col: Int) -> String {
        card.grid.map { $0[col] }.map { $0 == 0 ? "FREE" : "\($0)" }.joined(separator: ", ")
    }

    private var cardsTable: some View {
        Table(cards, selection: $tableSelection, sortOrder: $sortOrder) {
            TableColumn("Card #", value: \.id) { card in
                Text("#\(card.id)")
                    .monospacedDigit()
            }
            .width(ideal: 60)
            TableColumn("B") { card in
                Text(columnText(card: card, col: 0))
                    .font(.caption).monospacedDigit()
            }
            TableColumn("I") { card in
                Text(columnText(card: card, col: 1))
                    .font(.caption).monospacedDigit()
            }
            TableColumn("N") { card in
                Text(columnText(card: card, col: 2))
                    .font(.caption).monospacedDigit()
            }
            TableColumn("G") { card in
                Text(columnText(card: card, col: 3))
                    .font(.caption).monospacedDigit()
            }
            TableColumn("O") { card in
                Text(columnText(card: card, col: 4))
                    .font(.caption).monospacedDigit()
            }
        }
    }
}

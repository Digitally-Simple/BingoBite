import SwiftUI
import SwiftData

struct BingoGameCreateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BingoSet.creationDate) private var bingoSets: [BingoSet]
    var onCreate: (BingoGame) -> Void

    @State private var selectedBingoSetID: PersistentIdentifier?
    @State private var name = ""

    private var selectedBingoSet: BingoSet? {
        guard let id = selectedBingoSetID else { return nil }
        return bingoSets.first { $0.persistentModelID == id }
    }

    private var isValid: Bool {
        selectedBingoSetID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Bingo Game")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Picker("Bingo Set", selection: $selectedBingoSetID) {
                    Text("Select a bingo set...")
                        .tag(nil as PersistentIdentifier?)
                    ForEach(bingoSets) { bingoSet in
                        Text("\(bingoSet.name) (\(bingoSet.songCount) songs, \(bingoSet.numberOfCards) cards)")
                            .tag(bingoSet.persistentModelID as PersistentIdentifier?)
                    }
                }

                TextField("Game Name (optional)", text: $name)
                    .help("Leave blank to auto-generate from the bingo set name and date")
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Start Game") {
                    guard let bingoSet = selectedBingoSet else { return }
                    let game = BingoGameService.create(
                        name: name,
                        bingoSet: bingoSet,
                        in: modelContext
                    )
                    dismiss()
                    onCreate(game)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 450, height: 280)
    }
}

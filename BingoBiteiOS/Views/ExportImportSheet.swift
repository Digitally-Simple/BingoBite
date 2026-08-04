import SwiftUI
import SwiftData

/// Merges a Music Downloader export folder into the library.
struct ExportImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let candidate: ExportFolderImporter.Candidate
    let libraryURL: URL
    let onFinish: () -> Void

    @State private var isImporting = false
    @State private var progress: (done: Int, total: Int)?
    @State private var result: ExportFolderImporter.Result?
    @State private var errorMessage: String?
    @State private var deleteAfterImport = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard
                        if let result {
                            resultCard(result)
                        } else {
                            optionsCard
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .glassCard(tint: .orange)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") {
                        if result != nil { onFinish() }
                        dismiss()
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result == nil {
                        Button("Import") { Task { await runImport() } }
                            .disabled(isImporting || candidate.audioFileCount == 0)
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("From")
            DetailRow(label: "Folder", value: candidate.name)
            DetailRow(label: "Songs", value: "\(candidate.audioFileCount)")
            if candidate.playlistCount > 0 {
                DetailRow(label: "Playlists", value: "\(candidate.playlistCount)")
            }
            if candidate.manifest == nil {
                Text("No manifest in this folder, so songs will be copied but no playlists created.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Options")
            Toggle("Delete the folder after importing", isOn: $deleteAfterImport)
                .font(.callout)
            Text("Songs already in your library are skipped, so importing the same folder twice is safe.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isImporting {
                if let progress, progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                    Text("Copying \(progress.done) of \(progress.total)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Working…").controlSize(.small)
                }
            }
        }
        .glassCard()
    }

    private func resultCard(_ result: ExportFolderImporter.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading("Imported")
            DetailRow(label: "Songs added", value: "\(result.copied)")
            if result.skippedDuplicates > 0 {
                DetailRow(label: "Already had", value: "\(result.skippedDuplicates)")
            }
            if result.playlistsCreated > 0 {
                DetailRow(label: "Playlists created", value: "\(result.playlistsCreated)")
            }
            if !result.playlistsSkipped.isEmpty {
                Text("Playlists not created")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                ForEach(result.playlistsSkipped, id: \.self) { note in
                    Text("• \(note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !result.failures.isEmpty {
                Text("\(result.failures.count) file\(result.failures.count == 1 ? "" : "s") couldn't be copied")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .glassCard()
    }

    private func runImport() async {
        isImporting = true
        defer { isImporting = false; progress = nil }
        do {
            let outcome = try await ExportFolderImporter.import(
                candidate: candidate,
                libraryURL: libraryURL,
                in: context
            ) { done, total in
                progress = (done, total)
            }
            result = outcome
            // Only remove the source once everything landed — a partial import
            // with the folder deleted would be unrecoverable.
            if deleteAfterImport, outcome.failures.isEmpty {
                try? FileManager.default.removeItem(at: candidate.folderURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

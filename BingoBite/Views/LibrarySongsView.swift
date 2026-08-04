import AppKit
import SwiftUI
import SwiftData

/// The master library on macOS.
///
/// Unlike iPad — where the library is a fixed folder inside the app's own
/// Documents so it shows up in Files — the Mac has no such convention, so the
/// user points at any folder and it's remembered by bookmark.
struct LibrarySongsView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\LibraryIndexEntry.artist), SortDescriptor(\LibraryIndexEntry.title)])
    private var entries: [LibraryIndexEntry]

    @State private var searchText = ""
    @State private var isSweeping = false
    @State private var progress: LibraryIndexService.Progress?
    @State private var errorMessage: String?
    @State private var showingMissingOnly = false

    private var root: LibraryRoot? { LibraryIndexService.root(in: context) }

    private var missingCount: Int { entries.count(where: \.isMissing) }

    private var filtered: [LibraryIndexEntry] {
        var base = showingMissingOnly ? entries.filter(\.isMissing) : entries
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            base = base.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || $0.displayArtist.localizedCaseInsensitiveContains(query)
                    || $0.displayAlbum.localizedCaseInsensitiveContains(query)
            }
        }
        return base
    }

    var body: some View {
        Group {
            if root == nil {
                setupState
            } else if entries.isEmpty && !isSweeping {
                emptyState
            } else {
                table
            }
        }
        .navigationTitle("Songs")
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, prompt: "Search songs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await sweep() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(isSweeping || root == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Library Folder…", systemImage: "folder")
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    private var subtitle: String {
        guard root != nil else { return "No library folder chosen" }
        var text = "\(entries.count) song\(entries.count == 1 ? "" : "s")"
        if missingCount > 0 { text += " · \(missingCount) missing" }
        return text
    }

    private var setupState: some View {
        ContentUnavailableView {
            Label("No library yet", systemImage: "books.vertical")
        } description: {
            Text("Pick the folder holding your music. Playlists reference it, so a song used in five playlists is stored once.")
        } actions: {
            Button("Choose Library Folder…") { chooseFolder() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No songs found", systemImage: "music.note")
        } description: {
            Text("Nothing playable in \(root?.url.path ?? "that folder").")
        } actions: {
            Button("Rescan") { Task { await sweep() } }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            if missingCount > 0 {
                Button {
                    showingMissingOnly.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(missingCount) song\(missingCount == 1 ? "" : "s") missing from the library folder")
                            .font(.callout)
                        Spacer()
                        Text(showingMissingOnly ? "Show all" : "Review")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.orange.opacity(0.12))
            }

            if isSweeping, let progress, progress.total > 0 {
                ProgressView(value: progress.fraction) {
                    Text("Reading \(progress.processed) of \(progress.total)…")
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            List(filtered) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.isMissing ? "exclamationmark.triangle.fill" : "music.note")
                        .foregroundStyle(entry.isMissing ? Color.orange : Color.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayTitle).lineLimit(1)
                        if entry.isMissing {
                            Text("Missing from the library folder")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(entry.displayArtist)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)

                    Text(entry.displayAlbum)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)

                    Text(formatDuration(entry.duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Show in Finder") {
                        guard let root else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([
                            root.url.appendingPathComponent(entry.relativePath)
                        ])
                    }
                }
            }
            .alternatingRowBackgrounds()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Library"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try BookmarkService.createBookmark(for: url)
            LibraryIndexService.setRoot(
                url: url,
                name: url.lastPathComponent,
                bookmarkData: bookmark,
                in: context
            )
            Task { await sweep() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sweep() async {
        guard let root, !isSweeping else { return }
        isSweeping = true
        defer { isSweeping = false; progress = nil }

        // Only the Mac needs scoped access — the iPad's library is app-owned.
        let scoped = root.needsScopedAccess && BookmarkService.startAccessing(root.url)
        defer { if scoped { BookmarkService.stopAccessing(root.url) } }

        do {
            try await LibraryIndexService.sweep(root: root, in: context) { update in
                progress = update
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

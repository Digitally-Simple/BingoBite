import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var playlists: [Playlist]
    @Query private var games: [BingoGame]

    @State private var suggestedFolders: [URL] = []
    @State private var settings: AppSettings?

    /// Clip length the preview curve is drawn against. Most sound bytes land
    /// near this, and it makes the fade proportions legible.
    private let previewClipDuration: TimeInterval = 30

    @ViewBuilder
    private var fadeSection: some View {
        if let settings {
            @Bindable var settings = settings

            Section {
                Toggle("Fade songs in and out", isOn: $settings.fadesEnabled)

                if settings.fadesEnabled {
                    FadeEnvelopeView(
                        envelope: settings.fadeEnvelope,
                        clipDuration: previewClipDuration
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                    Picker("Fade in", selection: $settings.fadeInCurve) {
                        ForEach(FadeCurve.allCases) { curve in
                            Text(curve.displayName).tag(curve)
                        }
                    }
                    durationRow(
                        "Fade in length",
                        value: $settings.fadeInDuration
                    )

                    Picker("Fade out", selection: $settings.fadeOutCurve) {
                        ForEach(FadeCurve.allCases) { curve in
                            Text(curve.displayName).tag(curve)
                        }
                    }
                    durationRow(
                        "Fade out length",
                        value: $settings.fadeOutDuration
                    )
                }
            } header: {
                Text("Fades")
            } footer: {
                if settings.fadesEnabled {
                    Text("\(settings.fadeInCurve.displayName) in — \(settings.fadeInCurve.explanation)\n\n\(settings.fadeOutCurve.displayName) out — \(settings.fadeOutCurve.explanation)\n\nThe curve is drawn against a \(Int(previewClipDuration))-second clip. On a shorter clip both fades shrink to fit rather than overlapping.")
                } else {
                    Text("Songs start and stop at full volume.")
                }
            }
        }
    }

    @ViewBuilder
    private var autoplaySection: some View {
        if let settings {
            @Bindable var settings = settings

            Section {
                durationRow(
                    "Gap between songs",
                    value: $settings.autoplayGap,
                    range: 0...AppSettings.maximumAutoplayGap
                )
            } header: {
                Text("Autoplay")
            } footer: {
                Text("Turn autoplay on from the game screen. Each round plays its trimmed segment — fading in at the in point and out by the out point — then waits \(FadeEnvelopeView.format(settings.autoplayGap)) before the next song starts.\n\nThe host can still move rounds by hand at any time, and doing so turns nothing off.")
            }
        }
    }

    private func durationRow(
        _ title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval> = 0...AppSettings.maximumFadeDuration
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(FadeEnvelopeView.format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.5)
        }
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Playlists", value: "\(playlists.count)")
                    LabeledContent("Bingo games", value: "\(games.count)")
                    LabeledContent("Version", value: version)
                } header: {
                    Text("Library")
                }

                Section {
                    if suggestedFolders.isEmpty {
                        Text("No music folders yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestedFolders, id: \.self) { folder in
                            Label(folder.lastPathComponent, systemImage: "folder.fill")
                        }
                    }
                } header: {
                    Text("Music in the BingoBite Folder")
                } footer: {
                    Text("Open the **Files** app and go to **On My iPad › BingoBite** to add or remove music folders. Playlists can also point at folders anywhere else in Files.")
                }

                fadeSection

                autoplaySection

                Section {
                    LabeledContent("Audio formats", value: FolderScannerService.supportedExtensions.sorted().joined(separator: ", "))
                } footer: {
                    Text("Song tags — including Genius annotations, credits, and links written by Music Downloader — are read directly from each file.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                suggestedFolders = SongsFolderService.suggestedFolders()
                settings = AppSettingsService.current(in: modelContext)
            }
            .onDisappear { AppSettingsService.save(in: modelContext) }
        }
        .presentationDetents([.medium, .large])
    }
}

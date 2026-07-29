import SwiftUI
import SwiftData

/// Full song read-out: artwork, transport, sound-byte editor, tags, Genius
/// annotations, credits, relationships, and links. Used both as the game's
/// "Now Playing" tab and inside the song inspector sheet.
struct SongDetailPanel: View {
    var song: Song?
    @ObservedObject var audioPlayer: AudioPlayerService
    var emptyMessage: String = "Select a song to see its details."
    var bottomInset: CGFloat = 24

    @Environment(\.modelContext) private var modelContext

    @State private var clipStart: TimeInterval = 0
    @State private var clipEnd: TimeInterval = 0
    @State private var hasClip = false

    var body: some View {
        Group {
            if let song {
                content(song)
            } else {
                ContentUnavailableView {
                    Label("No Song Playing", systemImage: "music.note")
                } description: {
                    Text(emptyMessage)
                }
            }
        }
        .onAppear { loadClip() }
        .onChange(of: song) { loadClip() }
    }

    private func content(_ song: Song) -> some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 18) {
                    hero(song)
                    clipEditor(song)
                    details(song)
                    if hasFacts(song) { facts(song) }
                    if let credits = song.credits, !credits.isEmpty { creditsCard(credits) }
                    if let relationships = song.songRelationships, !relationships.isEmpty {
                        relationshipsCard(relationships)
                    }
                    if hasLinks(song) { linksCard(song) }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, bottomInset)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .disclosureGroupStyle(TappableDisclosureGroupStyle())
    }

    // MARK: - Hero

    private func hero(_ song: Song) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { heroArt(song); heroText(song) }
            VStack(spacing: 16) { heroArt(song); heroText(song) }
        }
        .padding(20)
        .glassCard(corner: Glassware.panelCorner)
    }

    private func heroArt(_ song: Song) -> some View {
        ArtworkView(data: song.artworkData, corner: Glassware.tileCorner, placeholderScale: 0.3)
            .frame(width: 168, height: 168)
    }

    private func heroText(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.displayTitle)
                .font(.title.bold())
                .lineLimit(3)
            Text(song.displayArtist)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(song.displayAlbum)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 12)

            if audioPlayer.currentSong == song {
                transport
            } else {
                Button("Play", systemImage: "play.fill") {
                    audioPlayer.play(song)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 6) {
            scrubber

            HStack {
                Text(audioPlayer.formattedCurrentTime)
                Spacer()
                Text(audioPlayer.formattedDuration)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Previous", systemImage: "backward.end.fill") { audioPlayer.skipBackward() }
                    .disabled(!audioPlayer.canSkipBackward)

                Button(
                    audioPlayer.isPlaying ? "Pause" : "Play",
                    systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill"
                ) { audioPlayer.togglePlayPause() }

                Button("Next", systemImage: "forward.end.fill") { audioPlayer.skipForward() }
                    .disabled(!audioPlayer.canSkipForward)

                Button("Stop", systemImage: "stop.fill") { audioPlayer.stop() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        }
    }

    /// Playback slider with the saved clip range drawn behind it.
    private var scrubber: some View {
        ZStack {
            if hasClip, audioPlayer.duration > 0 {
                GeometryReader { geo in
                    let start = clipStart / audioPlayer.duration
                    let end = clipEnd / audioPlayer.duration
                    Capsule()
                        .fill(.tint.opacity(0.30))
                        .frame(width: max(0, CGFloat(end - start) * geo.size.width), height: 6)
                        .offset(x: CGFloat(start) * geo.size.width)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .allowsHitTesting(false)
            }

            Slider(
                value: Binding(
                    get: { audioPlayer.progress },
                    set: { audioPlayer.seek(to: $0) }
                ),
                in: 0...1
            )
        }
        .frame(height: 28)
    }

    // MARK: - Clip editor

    private func clipEditor(_ song: Song) -> some View {
        let isLoaded = audioPlayer.currentSong == song
        let isValid = clipEnd > clipStart

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Sound Byte", systemImage: "scissors")

            VStack(spacing: 0) {
                clipRow(label: "Start", value: clipStart, enabled: isLoaded) {
                    clipStart = audioPlayer.currentTime
                    if clipEnd <= clipStart { clipEnd = min(clipStart + 15, audioPlayer.duration) }
                }
                Divider().padding(.leading, 18)
                clipRow(label: "End", value: clipEnd, enabled: isLoaded) {
                    clipEnd = audioPlayer.currentTime
                    if clipStart >= clipEnd { clipStart = max(clipEnd - 15, 0) }
                }
                Divider().padding(.leading, 18)

                HStack(spacing: 10) {
                    Button("Save", systemImage: "checkmark") {
                        SoundByteService.save(for: song, startTime: clipStart, endTime: clipEnd, in: modelContext)
                        hasClip = true
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!isValid)

                    Button("Preview", systemImage: "play.circle") {
                        audioPlayer.preview(song, startTime: clipStart, endTime: clipEnd)
                    }
                    .buttonStyle(.glass)
                    .disabled(!isValid)

                    if hasClip {
                        Button("Clear", systemImage: "trash", role: .destructive) {
                            SoundByteService.remove(for: song, in: modelContext)
                            clipStart = 0
                            clipEnd = 0
                            hasClip = false
                        }
                        .buttonStyle(.glass)
                    }

                    Spacer()

                    if isValid {
                        Text("\(Format.time(clipEnd - clipStart)) clip")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .controlSize(.small)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .glassCard(corner: Glassware.cardCorner)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clipRow(label: String, value: TimeInterval, enabled: Bool, set: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Format.time(value))
                .monospacedDigit()
            Button("Set to Now", action: set)
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!enabled)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - Details

    private func details(_ song: Song) -> some View {
        var rows: [(String, String)] = [
            ("Title", song.displayTitle),
            ("Artist", song.displayArtist),
            ("Album", song.displayAlbum),
            ("Duration", song.formattedDuration),
            ("Size", song.formattedFileSize),
            ("File", song.fileName),
        ]
        if let featured = song.featuredArtists, !featured.isEmpty { rows.append(("Featured", featured.joined(separator: ", "))) }
        if let producers = song.producerArtists, !producers.isEmpty { rows.append(("Producers", producers.joined(separator: ", "))) }
        if let writers = song.writerArtists, !writers.isEmpty { rows.append(("Writers", writers.joined(separator: ", "))) }
        if let genre = song.genre, !genre.isEmpty { rows.append(("Genre", genre)) }
        if let language = song.language, !language.isEmpty { rows.append(("Language", language)) }
        if let location = song.recordingLocation, !location.isEmpty { rows.append(("Recorded", location)) }
        if let released = song.releaseDate, !released.isEmpty { rows.append(("Released", released)) }
        if hasClip {
            rows.append(("Clip", "\(Format.time(clipStart)) – \(Format.time(clipEnd))"))
        }

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Details", systemImage: "info.circle")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    DetailRow(label: row.0, value: row.1, showsDivider: index < rows.count - 1)
                }
            }
            .glassCard(corner: Glassware.cardCorner)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Song facts

    private func hasFacts(_ song: Song) -> Bool {
        let description = song.songDescription ?? ""
        return !description.isEmpty || !(song.annotations ?? []).isEmpty
    }

    private func facts(_ song: Song) -> some View {
        let annotations = song.annotations ?? []
        let verified = annotations.filter(\.verified)
        let community = annotations.filter { !$0.verified }

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Song Facts", systemImage: "sparkles")

            VStack(alignment: .leading, spacing: 0) {
                if let description = song.songDescription, !description.isEmpty {
                    disclosure("About This Song") {
                        Text(description)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                if !verified.isEmpty {
                    disclosure("Artist Annotations (\(verified.count))") {
                        annotationList(verified)
                    }
                }
                if !community.isEmpty {
                    disclosure("Top Annotations (\(community.count))") {
                        annotationList(community)
                    }
                }
            }
            .glassCard(corner: Glassware.cardCorner)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func annotationList(_ facts: [AnnotationFact]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(fact.fragment.prefix(160))”")
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)

                    Text(fact.body)
                        .font(.callout)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        Text(fact.authors)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if fact.verified {
                            Label("Verified", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        } else {
                            Text("\(fact.votes) votes")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Credits & relationships

    private func creditsCard(_ credits: [CreditEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Credits", systemImage: "person.2")
            VStack(alignment: .leading, spacing: 0) {
                disclosure("Performance Credits (\(credits.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in
                            labelledLine(credit.role, credit.artists.joined(separator: ", "))
                        }
                    }
                }
            }
            .glassCard(corner: Glassware.cardCorner)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relationshipsCard(_ relationships: [SongRelationshipEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Connections", systemImage: "arrow.triangle.branch")
            VStack(alignment: .leading, spacing: 0) {
                disclosure("Song Relationships (\(relationships.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(relationships.enumerated()), id: \.offset) { _, relationship in
                            labelledLine(
                                Format.relationshipType(relationship.type),
                                "“\(relationship.title)” by \(relationship.artist)"
                            )
                        }
                    }
                }
            }
            .glassCard(corner: Glassware.cardCorner)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelledLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .trailing)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Links

    private func hasLinks(_ song: Song) -> Bool {
        !(song.mediaLinks ?? []).isEmpty || song.geniusURL != nil
    }

    private func linksCard(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Links", systemImage: "link")

            VStack(alignment: .leading, spacing: 12) {
                if let links = song.mediaLinks, !links.isEmpty {
                    WrappingHStack(spacing: 8) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            Link(destination: link.url) {
                                Label(Format.providerName(link.provider), systemImage: Format.providerIcon(link.provider))
                                    .font(.callout)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .glassCard(corner: 20)
                            }
                        }
                    }
                }

                if let geniusURL = song.geniusURL {
                    Link(destination: geniusURL) {
                        Label("View on Genius", systemImage: "arrow.up.right.square")
                            .font(.callout)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(corner: Glassware.cardCorner)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func disclosure<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        // Build eagerly: DisclosureGroup's content closure escapes.
        let body = content()
        return DisclosureGroup {
            body.padding(.top, 4)
        } label: {
            Text(title)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func loadClip() {
        guard let song else {
            clipStart = 0
            clipEnd = 0
            hasClip = false
            return
        }
        if let clip = SoundByteService.fetch(for: song, in: modelContext) {
            clipStart = clip.startTime
            clipEnd = clip.endTime
            hasClip = true
        } else {
            clipStart = 0
            clipEnd = 0
            hasClip = false
        }
    }
}

// MARK: - Sheet wrapper

struct SongInspectorSheet: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SongDetailPanel(song: song, audioPlayer: audioPlayer, bottomInset: 24)
                .appSurface()
                .navigationTitle("Song Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

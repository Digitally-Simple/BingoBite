import SwiftUI
import SwiftData

struct InspectorPaneView: View {
    var selectedSong: Song?
    @ObservedObject var audioPlayer: AudioPlayerService
    @Environment(\.modelContext) private var modelContext

    @State private var editingStartTime: TimeInterval?
    @State private var editingEndTime: TimeInterval?
    @State private var hasSoundByte: Bool = false

    var body: some View {
        Group {
            if let song = selectedSong {
                songDetail(song)
            } else {
                ContentUnavailableView("No Selection", systemImage: "music.note", description: Text("Select a song to view its details."))
            }
        }
        .onAppear { loadSoundByte() }
        .onChange(of: selectedSong) { loadSoundByte() }
    }

    @ViewBuilder
    private func songDetail(_ song: Song) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                nowPlayingSection(song)
                    .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal)

                soundByteSection(song)

                Divider()
                    .padding(.horizontal)

                metadataSection(song)

                if hasSongFacts(song) {
                    Divider()
                        .padding(.horizontal)

                    songFactsSection(song)
                }

                if hasCredits(song) {
                    Divider()
                        .padding(.horizontal)

                    creditsSection(song)
                }

                if hasRelationships(song) {
                    Divider()
                        .padding(.horizontal)

                    relationshipsSection(song)
                }

                if hasMediaLinks(song) {
                    Divider()
                        .padding(.horizontal)

                    mediaLinksSection(song)
                }
            }
            .padding(.vertical)
            .disclosureGroupStyle(TappableDisclosureGroupStyle())
        }
    }

    // MARK: - Now Playing / Artwork Section

    @ViewBuilder
    private func nowPlayingSection(_ song: Song) -> some View {
        VStack(spacing: 12) {
            // Album Artwork
            artworkView(song)
                .padding(.horizontal, 24)

            // Song Title & Artist
            VStack(spacing: 4) {
                Text(song.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(song.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(song.album ?? "Unknown Album")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal)

            // Playback controls
            if audioPlayer.currentSong == song {
                playbackControls
                    .padding(.horizontal, 24)
            } else {
                Button {
                    audioPlayer.play(song)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.borderless)
                .help("Play")
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func artworkView(_ song: Song) -> some View {
        Group {
            if let image = song.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 4) {
            // Progress bar with sound byte markers
            ZStack {
                Slider(
                    value: Binding(
                        get: { audioPlayer.progress },
                        set: { audioPlayer.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)

                // Sound byte overlay markers
                if audioPlayer.duration > 0, editingStartTime != nil || editingEndTime != nil {
                    GeometryReader { geo in
                        let startFraction = (editingStartTime ?? 0) / audioPlayer.duration
                        let endFraction = (editingEndTime ?? 0) / audioPlayer.duration

                        // Highlighted region between markers
                        if let _ = editingStartTime, let _ = editingEndTime {
                            Rectangle()
                                .fill(Color.green.opacity(0.15))
                                .frame(
                                    width: max(0, CGFloat(endFraction - startFraction) * geo.size.width),
                                    height: geo.size.height
                                )
                                .offset(x: CGFloat(startFraction) * geo.size.width)
                        }

                        // Start marker (green)
                        if let _ = editingStartTime {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 2, height: geo.size.height)
                                .offset(x: CGFloat(startFraction) * geo.size.width - 1)
                        }

                        // End marker (red)
                        if let _ = editingEndTime {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: geo.size.height)
                                .offset(x: CGFloat(endFraction) * geo.size.width - 1)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }

            // Time labels
            HStack {
                Text(audioPlayer.formattedCurrentTime)
                Spacer()
                Text(audioPlayer.formattedDuration)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            // Transport controls
            HStack(spacing: 24) {
                Button {
                    audioPlayer.skipBackward()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!audioPlayer.canSkipBackward)
                .help("Previous")

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                .buttonStyle(.borderless)
                .help(audioPlayer.isPlaying ? "Pause" : "Play")

                Button {
                    audioPlayer.skipForward()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!audioPlayer.canSkipForward)
                .help("Next")
            }
            .padding(.top, 4)

            Button {
                audioPlayer.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Stop")
            .padding(.top, 2)
        }
    }

    // MARK: - Sound Byte Section

    @ViewBuilder
    private func soundByteSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound Byte")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(spacing: 8) {
                // Start time row
                HStack {
                    Text("Start")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                    Text(editingStartTime.map { Self.formatTime($0) } ?? "--:--")
                        .monospacedDigit()
                    Spacer()
                    Button("Set to Now") {
                        let now = audioPlayer.currentTime
                        editingStartTime = now
                        if let end = editingEndTime, end <= now {
                            editingEndTime = nil
                        }
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }
                .font(.callout)

                // End time row
                HStack {
                    Text("End")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                    Text(editingEndTime.map { Self.formatTime($0) } ?? "--:--")
                        .monospacedDigit()
                    Spacer()
                    Button("Set to Now") {
                        let now = audioPlayer.currentTime
                        if let start = editingStartTime, now <= start {
                            editingStartTime = nil
                        }
                        editingEndTime = now
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }
                .font(.callout)

                // Action buttons
                HStack(spacing: 8) {
                    Button("Save") {
                        if let start = editingStartTime, let end = editingEndTime {
                            SoundByteService.save(
                                for: song,
                                startTime: start,
                                endTime: end,
                                in: modelContext
                            )
                            hasSoundByte = true
                        }
                    }
                    .disabled(!hasValidRange)

                    Button("Preview") {
                        if let start = editingStartTime, let end = editingEndTime {
                            audioPlayer.preview(song, startTime: start, endTime: end)
                        }
                    }
                    .disabled(!hasValidRange)

                    if hasSoundByte {
                        Button("Clear") {
                            SoundByteService.remove(for: song, in: modelContext)
                            editingStartTime = nil
                            editingEndTime = nil
                            hasSoundByte = false
                        }
                    }

                    Spacer()
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Metadata Section

    @ViewBuilder
    private func metadataSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(spacing: 0) {
                metadataRow(label: "Title", value: song.displayTitle)
                Divider().padding(.leading)
                metadataRow(label: "Artist", value: song.artist ?? "Unknown Artist")
                Divider().padding(.leading)
                metadataRow(label: "Album", value: song.album ?? "Unknown Album")
                Divider().padding(.leading)
                metadataRow(label: "Duration", value: song.formattedDuration)
                Divider().padding(.leading)
                metadataRow(label: "Size", value: song.formattedFileSize)
                Divider().padding(.leading)
                metadataRow(label: "File", value: song.fileName)

                if let featured = song.featuredArtists, !featured.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Featured", value: featured.joined(separator: ", "))
                }
                if let producers = song.producerArtists, !producers.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Producers", value: producers.joined(separator: ", "))
                }
                if let writers = song.writerArtists, !writers.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Writers", value: writers.joined(separator: ", "))
                }
                if let language = song.language, !language.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Language", value: language)
                }
                if let location = song.recordingLocation, !location.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Recorded", value: location)
                }
                if let releaseDate = song.releaseDate, !releaseDate.isEmpty {
                    Divider().padding(.leading)
                    metadataRow(label: "Released", value: releaseDate)
                }

                if hasSoundByte, let start = editingStartTime, let end = editingEndTime {
                    Divider().padding(.leading)
                    metadataRow(label: "Clip Start", value: Self.formatTime(start))
                    Divider().padding(.leading)
                    metadataRow(label: "Clip End", value: Self.formatTime(end))
                    Divider().padding(.leading)
                    metadataRow(label: "Clip Len", value: Self.formatTime(end - start))
                }
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Song Facts Section

    private func hasSongFacts(_ song: Song) -> Bool {
        let desc = song.songDescription
        let annotations = song.annotations ?? []
        return (desc != nil && !desc!.isEmpty) || !annotations.isEmpty
    }

    @ViewBuilder
    private func songFactsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song Facts")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 10) {
                if let desc = song.songDescription, !desc.isEmpty {
                    DisclosureGroup("About This Song") {
                        Text(desc)
                            .font(.caption)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal)
                }

                let annotations = song.annotations ?? []
                let verified = annotations.filter(\.verified)
                let accepted = annotations.filter { !$0.verified }

                if !verified.isEmpty {
                    DisclosureGroup("Artist Annotations (\(verified.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(verified.enumerated()), id: \.offset) { _, fact in
                                annotationFactView(fact)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal)
                }

                if !accepted.isEmpty {
                    DisclosureGroup("Top Annotations (\(accepted.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(accepted.enumerated()), id: \.offset) { _, fact in
                                annotationFactView(fact)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal)
                }

            }
            .padding(.bottom, 12)
        }
    }

    private func annotationFactView(_ fact: AnnotationFact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\"\(fact.fragment.prefix(120))\"")
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(fact.body)
                .font(.caption)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Text(fact.authors)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if fact.verified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else {
                    Text("\(fact.votes) votes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
        }
    }

    // MARK: - Credits Section

    private func hasCredits(_ song: Song) -> Bool {
        guard let credits = song.credits else { return false }
        return !credits.isEmpty
    }

    @ViewBuilder
    private func creditsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            DisclosureGroup("Performance Credits (\(song.credits?.count ?? 0))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((song.credits ?? []).enumerated()), id: \.offset) { _, credit in
                        HStack(alignment: .top, spacing: 6) {
                            Text(credit.role + ":")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Text(credit.artists.joined(separator: ", "))
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Song Relationships Section

    private func hasRelationships(_ song: Song) -> Bool {
        guard let relationships = song.songRelationships else { return false }
        return !relationships.isEmpty
    }

    @ViewBuilder
    private func relationshipsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song Relationships")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            DisclosureGroup("Connections (\(song.songRelationships?.count ?? 0))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array((song.songRelationships ?? []).enumerated()), id: \.offset) { _, rel in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.formatRelationshipType(rel.type) + ":")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Text("\"\(rel.title)\" by \(rel.artist)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private static func formatRelationshipType(_ type: String) -> String {
        switch type {
        case "samples":           "Samples"
        case "sampled_in":        "Sampled in"
        case "interpolates":      "Interpolates"
        case "interpolated_by":   "Interpolated by"
        case "cover_of":          "Cover of"
        case "covered_by":        "Covered by"
        case "remix_of":          "Remix of"
        case "remixed_by":        "Remixed by"
        case "live_version_of":   "Live version of"
        case "performed_live_as": "Performed live as"
        default:                  type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Media Links Section

    private func hasMediaLinks(_ song: Song) -> Bool {
        let hasLinks = song.mediaLinks != nil && !song.mediaLinks!.isEmpty
        let hasGenius = song.geniusURL != nil
        return hasLinks || hasGenius
    }

    @ViewBuilder
    private func mediaLinksSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Links")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                if let links = song.mediaLinks, !links.isEmpty {
                    WrappingHStack(spacing: 8) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            Link(destination: link.url) {
                                HStack(spacing: 4) {
                                    Image(systemName: Self.iconForProvider(link.provider))
                                    Text(Self.displayNameForProvider(link.provider))
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                if let geniusURL = song.geniusURL {
                    Link(destination: geniusURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("View on Genius")
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private static func iconForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "spotify":      "arrow.up.right.square"
        case "apple_music":  "arrow.up.right.square"
        case "youtube":      "play.rectangle"
        case "soundcloud":   "arrow.up.right.square"
        default:             "link"
        }
    }

    private static func displayNameForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "spotify":      "Spotify"
        case "apple_music":  "Apple Music"
        case "youtube":      "YouTube"
        case "soundcloud":   "SoundCloud"
        default:             provider.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Helpers

    private var hasValidRange: Bool {
        guard let start = editingStartTime, let end = editingEndTime else { return false }
        return end > start
    }

    private func loadSoundByte() {
        guard let song = selectedSong else {
            editingStartTime = nil
            editingEndTime = nil
            hasSoundByte = false
            return
        }
        if let soundByte = SoundByteService.fetch(for: song, in: modelContext) {
            editingStartTime = soundByte.startTime
            editingEndTime = soundByte.endTime
            hasSoundByte = true
        } else {
            editingStartTime = nil
            editingEndTime = nil
            hasSoundByte = false
        }
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Tappable disclosure group style

/// Makes the entire DisclosureGroup header row (chevron + label) tappable,
/// not just the chevron.
struct TappableDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: configuration.isExpanded)
                configuration.label
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    configuration.isExpanded.toggle()
                }
            }

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 13)
            }
        }
    }
}

// MARK: - Flow layout for media link pills

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}

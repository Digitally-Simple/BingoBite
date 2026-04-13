import SwiftUI
import SwiftData

struct BingoGameInfoView: View {
    var song: Song?
    @ObservedObject var audioPlayer: AudioPlayerService
    @Environment(\.modelContext) private var modelContext

    @State private var editingStartTime: TimeInterval = 0
    @State private var editingEndTime: TimeInterval = 0
    @State private var hasSoundByte: Bool = false

    var body: some View {
        Group {
            if let song {
                songDetail(song)
            } else {
                ContentUnavailableView("No Song Playing", systemImage: "music.note", description: Text("Start playing a song to view its details."))
            }
        }
        .onAppear { loadSoundByte() }
        .onChange(of: song) { loadSoundByte() }
    }

    // MARK: - Card Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(
        header: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func cardRow(label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
                .padding(.leading, 16)
        }
    }

    // MARK: - Song Detail

    @ViewBuilder
    private func songDetail(_ song: Song) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                heroCard(song)
                soundByteCard(song)
                detailsCard(song)

                if hasSongFacts(song) {
                    songFactsCard(song)
                }
                if hasCredits(song) {
                    creditsCard(song)
                }
                if hasRelationships(song) {
                    connectionsCard(song)
                }
                if hasMediaLinks(song) {
                    linksCard(song)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .disclosureGroupStyle(TappableDisclosureGroupStyle())
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Hero Card

    @ViewBuilder
    private func heroCard(_ song: Song) -> some View {
        sectionCard {
            HStack(alignment: .top, spacing: 16) {
                artworkView(song)
                    .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(3)

                    Text(song.artist ?? "Unknown Artist")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(song.album ?? "Unknown Album")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer()

                    if audioPlayer.currentSong == song {
                        playbackControls(song)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
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

    @ViewBuilder
    private func playbackControls(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Slider(
                    value: Binding(
                        get: { audioPlayer.progress },
                        set: { audioPlayer.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)

                if hasSoundByte && audioPlayer.duration > 0 {
                    GeometryReader { geo in
                        let startFraction = editingStartTime / audioPlayer.duration
                        let endFraction = editingEndTime / audioPlayer.duration

                        Rectangle()
                            .fill(Color.green.opacity(0.15))
                            .frame(
                                width: max(0, CGFloat(endFraction - startFraction) * geo.size.width),
                                height: geo.size.height
                            )
                            .offset(x: CGFloat(startFraction) * geo.size.width)

                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: CGFloat(startFraction) * geo.size.width - 1)

                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: geo.size.height)
                            .offset(x: CGFloat(endFraction) * geo.size.width - 1)
                    }
                    .allowsHitTesting(false)
                }
            }

            HStack {
                Text(audioPlayer.formattedCurrentTime)
                Spacer()
                Text(audioPlayer.formattedDuration)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            HStack(spacing: 20) {
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
                        .font(.system(size: 32))
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

                Button {
                    audioPlayer.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Stop")
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Sound Byte Card

    @ViewBuilder
    private func soundByteCard(_ song: Song) -> some View {
        sectionCard(header: "Sound Byte") {
            // Start row
            VStack(spacing: 0) {
                HStack {
                    Text("Start")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatTime(editingStartTime))
                        .monospacedDigit()
                    Button("Set to Now") {
                        editingStartTime = audioPlayer.currentTime
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
                    .padding(.leading, 16)
            }

            // End row
            VStack(spacing: 0) {
                HStack {
                    Text("End")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatTime(editingEndTime))
                        .monospacedDigit()
                    Button("Set to Now") {
                        editingEndTime = audioPlayer.currentTime
                    }
                    .controlSize(.small)
                    .disabled(audioPlayer.currentSong != song)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
                    .padding(.leading, 16)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Save") {
                    SoundByteService.save(
                        for: song,
                        startTime: editingStartTime,
                        endTime: editingEndTime,
                        in: modelContext
                    )
                    hasSoundByte = true
                }
                .disabled(editingEndTime <= editingStartTime)

                Button("Preview") {
                    audioPlayer.preview(song, startTime: editingStartTime, endTime: editingEndTime)
                }
                .disabled(editingEndTime <= editingStartTime)

                if hasSoundByte {
                    Button("Clear") {
                        SoundByteService.remove(for: song, in: modelContext)
                        editingStartTime = 0
                        editingEndTime = 0
                        hasSoundByte = false
                    }
                }

                Spacer()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Details Card

    @ViewBuilder
    private func detailsCard(_ song: Song) -> some View {
        sectionCard(header: "Details") {
            cardRow(label: "Title", value: song.displayTitle)
            cardRow(label: "Artist", value: song.artist ?? "Unknown Artist")
            cardRow(label: "Album", value: song.album ?? "Unknown Album")
            cardRow(label: "Duration", value: song.formattedDuration)
            cardRow(label: "Size", value: song.formattedFileSize)
            cardRow(label: "File", value: song.fileName)

            if let featured = song.featuredArtists, !featured.isEmpty {
                cardRow(label: "Featured", value: featured.joined(separator: ", "))
            }
            if let producers = song.producerArtists, !producers.isEmpty {
                cardRow(label: "Producers", value: producers.joined(separator: ", "))
            }
            if let writers = song.writerArtists, !writers.isEmpty {
                cardRow(label: "Writers", value: writers.joined(separator: ", "))
            }
            if let language = song.language, !language.isEmpty {
                cardRow(label: "Language", value: language)
            }
            if let location = song.recordingLocation, !location.isEmpty {
                cardRow(label: "Recorded", value: location)
            }
            if let releaseDate = song.releaseDate, !releaseDate.isEmpty {
                cardRow(label: "Released", value: releaseDate)
            }

            if hasSoundByte {
                cardRow(label: "Clip Start", value: Self.formatTime(editingStartTime))
                cardRow(label: "Clip End", value: Self.formatTime(editingEndTime))
                cardRow(label: "Clip Length", value: Self.formatTime(editingEndTime - editingStartTime))
            }
        }
    }

    // MARK: - Song Facts Card

    private func hasSongFacts(_ song: Song) -> Bool {
        let desc = song.songDescription
        let annotations = song.annotations ?? []
        return (desc != nil && !desc!.isEmpty) || !annotations.isEmpty
    }

    @ViewBuilder
    private func songFactsCard(_ song: Song) -> some View {
        sectionCard(header: "Song Facts") {
            VStack(alignment: .leading, spacing: 0) {
                if let desc = song.songDescription, !desc.isEmpty {
                    DisclosureGroup("About This Song") {
                        Text(desc)
                            .font(.caption)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                let annotations = song.annotations ?? []
                let verified = annotations.filter(\.verified)
                let accepted = annotations.filter { !$0.verified }

                if !verified.isEmpty {
                    Divider().padding(.leading, 16)
                    DisclosureGroup("Artist Annotations (\(verified.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(verified.enumerated()), id: \.offset) { _, fact in
                                annotationFactView(fact)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                if !accepted.isEmpty {
                    Divider().padding(.leading, 16)
                    DisclosureGroup("Top Annotations (\(accepted.count))") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(accepted.enumerated()), id: \.offset) { _, fact in
                                annotationFactView(fact)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
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

    // MARK: - Credits Card

    private func hasCredits(_ song: Song) -> Bool {
        guard let credits = song.credits else { return false }
        return !credits.isEmpty
    }

    @ViewBuilder
    private func creditsCard(_ song: Song) -> some View {
        sectionCard(header: "Credits") {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Connections Card

    private func hasRelationships(_ song: Song) -> Bool {
        guard let relationships = song.songRelationships else { return false }
        return !relationships.isEmpty
    }

    @ViewBuilder
    private func connectionsCard(_ song: Song) -> some View {
        sectionCard(header: "Connections") {
            DisclosureGroup("Song Relationships (\(song.songRelationships?.count ?? 0))") {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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

    // MARK: - Links Card

    private func hasMediaLinks(_ song: Song) -> Bool {
        let hasLinks = song.mediaLinks != nil && !song.mediaLinks!.isEmpty
        let hasGenius = song.geniusURL != nil
        return hasLinks || hasGenius
    }

    @ViewBuilder
    private func linksCard(_ song: Song) -> some View {
        sectionCard(header: "Links") {
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
            .padding(16)
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

    private func loadSoundByte() {
        guard let song else {
            editingStartTime = 0
            editingEndTime = 0
            hasSoundByte = false
            return
        }
        if let soundByte = SoundByteService.fetch(for: song, in: modelContext) {
            editingStartTime = soundByte.startTime
            editingEndTime = soundByte.endTime
            hasSoundByte = true
        } else {
            editingStartTime = 0
            editingEndTime = 0
            hasSoundByte = false
        }
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

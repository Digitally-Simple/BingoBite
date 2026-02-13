import SwiftUI

struct SongTidbitsView: View {
    var song: Song
    var apiKey: String
    @StateObject private var geniusService = GeniusService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song Tidbits")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)

            if apiKey.isEmpty {
                noAPIKeyView
            } else if geniusService.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = geniusService.errorMessage {
                errorView(error)
            } else if let info = geniusService.songInfo {
                tidbitsContent(info)
            } else {
                emptyView
            }
        }
        .onAppear { fetchInfo() }
        .onChange(of: song) { fetchInfo() }
    }

    // MARK: - States

    private var noAPIKeyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "key")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Add your Genius API key in Settings to see song tidbits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No tidbits found for this song.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Tidbits Content

    @ViewBuilder
    private func tidbitsContent(_ info: GeniusSongInfo) -> some View {
        VStack(spacing: 0) {
            // 1. About
            if let description = info.description {
                tidbitRow(icon: "text.quote", label: "About", value: description, multiline: true)
            }
            // 2. Album
            if let album = info.albumName {
                Divider().padding(.leading)
                tidbitRow(icon: "opticaldisc", label: "Album", value: album)
            }
            // 3. Released
            if let releaseDate = info.releaseDate {
                Divider().padding(.leading)
                tidbitRow(icon: "calendar", label: "Released", value: releaseDate)
            }
            // 4. Recorded At
            if let location = info.recordingLocation {
                Divider().padding(.leading)
                tidbitRow(icon: "location", label: "Recorded At", value: location)
            }
            // 5. Featuring
            if !info.featuredArtists.isEmpty {
                Divider().padding(.leading)
                tidbitRow(icon: "person.2", label: "Featuring", value: info.featuredArtists.joined(separator: ", "))
            }
            // 6. Written By
            if !info.writers.isEmpty {
                Divider().padding(.leading)
                tidbitRow(icon: "pencil", label: "Written By", value: info.writers.joined(separator: ", "))
            }
            // 7. Produced By
            if !info.producers.isEmpty {
                Divider().padding(.leading)
                tidbitRow(icon: "slider.horizontal.3", label: "Produced By", value: info.producers.joined(separator: ", "))
            }
            // 8. Additional Credits
            ForEach(Array(info.customPerformances.enumerated()), id: \.offset) { _, perf in
                Divider().padding(.leading)
                tidbitRow(icon: "person.text.rectangle", label: perf.label, value: perf.artists.joined(separator: ", "))
            }
            // 9. Relationships
            ForEach(Array(info.relationships.enumerated()), id: \.offset) { _, rel in
                Divider().padding(.leading)
                tidbitRow(
                    icon: iconForRelationship(rel.type),
                    label: displayNameForRelationship(rel.type),
                    value: rel.songs.joined(separator: ", ")
                )
            }
            // 10. Community Note
            if let annotation = info.topAnnotation {
                Divider().padding(.leading)
                tidbitRow(icon: "quote.bubble", label: "Community Note", value: annotation, multiline: true)
            }
            // 11. Q&A
            if !info.questionsAndAnswers.isEmpty {
                Divider().padding(.leading)
                qaSection(info.questionsAndAnswers)
            }
            // 12. Listen & Watch
            if !info.mediaLinks.isEmpty {
                Divider().padding(.leading)
                mediaLinksRow(info.mediaLinks)
            }
            // 13. Stats
            if info.pageviews != nil || info.pyongsCount != nil || info.annotationCount != nil {
                Divider().padding(.leading)
                statsRow(info)
            }
            // 14. View on Genius (always last)
            if let url = info.geniusURL {
                Divider().padding(.leading)
                linkRow(url: url)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Row Views

    private func tidbitRow(icon: String, label: String, value: String, multiline: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(multiline ? 6 : 2)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func linkRow(url: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            if let linkURL = URL(string: url) {
                Link("View on Genius", destination: linkURL)
                    .font(.callout)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - New Sections

    private func qaSection(_ pairs: [(question: String, answer: String)]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.bubble")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Q&A")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    DisclosureGroup {
                        Text(pair.answer)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(pair.question)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func mediaLinksRow(_ links: [(provider: String, url: String)]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "play.rectangle")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Listen & Watch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        if let linkURL = URL(string: link.url) {
                            Link(destination: linkURL) {
                                Text(displayNameForProvider(link.provider))
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.fill.tertiary, in: Capsule())
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func statsRow(_ info: GeniusSongInfo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chart.bar")
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Stats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let pageviews = info.pageviews {
                        Label(formatNumber(pageviews), systemImage: "eye")
                            .font(.callout)
                    }
                    if let pyongs = info.pyongsCount, pyongs > 0 {
                        Label("\(pyongs)", systemImage: "flame")
                            .font(.callout)
                    }
                    if let annotations = info.annotationCount, annotations > 0 {
                        Label("\(annotations)", systemImage: "text.bubble")
                            .font(.callout)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func fetchInfo() {
        geniusService.fetchSongInfo(
            title: song.displayTitle,
            artist: song.artist,
            apiKey: apiKey
        )
    }

    private func iconForRelationship(_ type: String) -> String {
        switch type {
        case "samples": return "waveform.badge.plus"
        case "sampled_in": return "waveform"
        case "interpolates": return "arrow.triangle.branch"
        case "interpolated_by": return "arrow.triangle.merge"
        case "cover_of": return "doc.on.doc"
        case "covered_by": return "doc.on.doc.fill"
        case "remix_of": return "repeat"
        case "remixed_by": return "repeat.1"
        case "live_version_of": return "music.mic"
        default: return "link"
        }
    }

    private func displayNameForRelationship(_ type: String) -> String {
        switch type {
        case "samples": return "Samples"
        case "sampled_in": return "Sampled In"
        case "interpolates": return "Interpolates"
        case "interpolated_by": return "Interpolated By"
        case "cover_of": return "Cover Of"
        case "covered_by": return "Covered By"
        case "remix_of": return "Remix Of"
        case "remixed_by": return "Remixed By"
        case "live_version_of": return "Live Version Of"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func displayNameForProvider(_ provider: String) -> String {
        switch provider {
        case "youtube": return "YouTube"
        case "spotify": return "Spotify"
        case "soundcloud": return "SoundCloud"
        case "apple_music": return "Apple Music"
        default: return provider.capitalized
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

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
            if let description = info.description {
                tidbitRow(icon: "text.quote", label: "About", value: description, multiline: true)
            }
            if let releaseDate = info.releaseDate {
                Divider().padding(.leading)
                tidbitRow(icon: "calendar", label: "Released", value: releaseDate)
            }
            if let location = info.recordingLocation {
                Divider().padding(.leading)
                tidbitRow(icon: "location", label: "Recorded At", value: location)
            }
            if !info.writers.isEmpty {
                Divider().padding(.leading)
                tidbitRow(icon: "pencil", label: "Written By", value: info.writers.joined(separator: ", "))
            }
            if !info.producers.isEmpty {
                Divider().padding(.leading)
                tidbitRow(icon: "slider.horizontal.3", label: "Produced By", value: info.producers.joined(separator: ", "))
            }
            ForEach(Array(info.relationships.enumerated()), id: \.offset) { _, rel in
                Divider().padding(.leading)
                tidbitRow(
                    icon: iconForRelationship(rel.type),
                    label: displayNameForRelationship(rel.type),
                    value: rel.songs.joined(separator: ", ")
                )
            }
            if let annotation = info.topAnnotation {
                Divider().padding(.leading)
                tidbitRow(icon: "quote.bubble", label: "Community Note", value: annotation, multiline: true)
            }
            if let pageviews = info.pageviews {
                Divider().padding(.leading)
                tidbitRow(icon: "eye", label: "Genius Views", value: formatNumber(pageviews))
            }
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

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

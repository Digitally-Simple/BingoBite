import Combine
import Foundation

struct GeniusSongInfo {
    var description: String?
    var releaseDate: String?
    var recordingLocation: String?
    var pageviews: Int?
    var writers: [String]
    var producers: [String]
    var relationships: [(type: String, songs: [String])]
    var topAnnotation: String?
    var geniusURL: String?

    // Q&A scraped from Genius web page
    var questionsAndAnswers: [(question: String, answer: String)] = []

    // Additional metadata from /songs response
    var mediaLinks: [(provider: String, url: String)] = []
    var albumName: String?
    var featuredArtists: [String] = []
    var customPerformances: [(label: String, artists: [String])] = []
    var pyongsCount: Int?
    var annotationCount: Int?
}

@MainActor
final class GeniusService: ObservableObject {
    @Published var songInfo: GeniusSongInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let baseURL = "https://api.genius.com"
    private var currentTask: Task<Void, Never>?
    private var lastQuery = ""

    func fetchSongInfo(title: String, artist: String?, apiKey: String) {
        let query = [title, artist].compactMap { $0 }.joined(separator: " ")

        guard !query.isEmpty else {
            clear()
            return
        }

        // Skip if same query is already loaded or loading
        if query == lastQuery && (songInfo != nil || isLoading) { return }

        currentTask?.cancel()
        lastQuery = query

        guard !apiKey.isEmpty else {
            songInfo = nil
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        songInfo = nil

        currentTask = Task {
            do {
                // Step 1: Search for the song
                let songId = try await searchSong(query: query, apiKey: apiKey)
                guard !Task.isCancelled else { return }

                guard let songId else {
                    isLoading = false
                    return
                }

                // Step 2: Get song details
                var info = try await fetchSongDetails(songId: songId, apiKey: apiKey)
                guard !Task.isCancelled else { return }

                // Step 3: Get top annotation + Q&A in parallel
                async let annotationResult = fetchTopAnnotation(songId: songId, apiKey: apiKey)
                async let questionsResult = fetchQuestions(geniusURL: info.geniusURL)
                let (annotation, questions) = try await (annotationResult, questionsResult)
                guard !Task.isCancelled else { return }
                info.topAnnotation = annotation
                info.questionsAndAnswers = questions

                songInfo = info
                isLoading = false
            } catch is CancellationError {
                // Cancelled, do nothing
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    func clear() {
        currentTask?.cancel()
        songInfo = nil
        isLoading = false
        errorMessage = nil
        lastQuery = ""
    }

    // MARK: - Private API Calls

    private func searchSong(query: String, apiKey: String) async throws -> Int? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search?q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            throw GeniusError.invalidAPIKey
        }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GeniusError.httpError(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseBody = json["response"] as? [String: Any],
              let hits = responseBody["hits"] as? [[String: Any]],
              let firstHit = hits.first,
              let result = firstHit["result"] as? [String: Any],
              let songId = result["id"] as? Int else {
            return nil
        }

        return songId
    }

    private func fetchSongDetails(songId: Int, apiKey: String) async throws -> GeniusSongInfo {
        guard let url = URL(string: "\(baseURL)/songs/\(songId)?text_format=plain") else {
            return GeniusSongInfo(writers: [], producers: [], relationships: [])
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseBody = json["response"] as? [String: Any],
              let song = responseBody["song"] as? [String: Any] else {
            return GeniusSongInfo(writers: [], producers: [], relationships: [])
        }

        var info = GeniusSongInfo(writers: [], producers: [], relationships: [])

        // Description
        if let desc = song["description"] as? [String: Any],
           let plain = desc["plain"] as? String,
           plain != "?" && !plain.isEmpty {
            info.description = plain
        }

        // Release date
        info.releaseDate = song["release_date_for_display"] as? String

        // Recording location
        if let location = song["recording_location"] as? String, !location.isEmpty {
            info.recordingLocation = location
        }

        // Stats
        if let stats = song["stats"] as? [String: Any] {
            info.pageviews = stats["pageviews"] as? Int
        }

        // Writers
        if let writers = song["writer_artists"] as? [[String: Any]] {
            info.writers = writers.compactMap { $0["name"] as? String }
        }

        // Producers
        if let producers = song["producer_artists"] as? [[String: Any]] {
            info.producers = producers.compactMap { $0["name"] as? String }
        }

        // Song relationships
        if let relationships = song["song_relationships"] as? [[String: Any]] {
            for rel in relationships {
                if let type = rel["relationship_type"] as? String,
                   let relSongs = rel["songs"] as? [[String: Any]],
                   !relSongs.isEmpty {
                    let songNames = relSongs.compactMap { $0["full_title"] as? String }
                    if !songNames.isEmpty {
                        info.relationships.append((type: type, songs: songNames))
                    }
                }
            }
        }

        // Album name
        if let album = song["album"] as? [String: Any],
           let albumName = album["name"] as? String, !albumName.isEmpty {
            info.albumName = albumName
        }

        // Featured artists
        if let featured = song["featured_artists"] as? [[String: Any]] {
            info.featuredArtists = featured.compactMap { $0["name"] as? String }
        }

        // Custom performances (additional credits like mixing, mastering, etc.)
        if let performances = song["custom_performances"] as? [[String: Any]] {
            info.customPerformances = performances.prefix(5).compactMap { perf in
                guard let label = perf["label"] as? String,
                      let artists = perf["artists"] as? [[String: Any]] else { return nil }
                let names = artists.compactMap { $0["name"] as? String }
                guard !names.isEmpty else { return nil }
                return (label: label, artists: names)
            }
        }

        // Media links (YouTube, Spotify, SoundCloud, Apple Music)
        let knownProviders: Set<String> = ["youtube", "spotify", "soundcloud", "apple_music"]
        if let media = song["media"] as? [[String: Any]] {
            info.mediaLinks = media.compactMap { item in
                guard let provider = item["provider"] as? String,
                      knownProviders.contains(provider),
                      let url = item["url"] as? String else { return nil }
                return (provider: provider, url: url)
            }
        }

        // Engagement stats
        if let stats = song["stats"] as? [String: Any] {
            info.pyongsCount = stats["pyongs_count"] as? Int
        }
        info.pyongsCount = info.pyongsCount ?? (song["pyongs_count"] as? Int)
        info.annotationCount = song["annotation_count"] as? Int

        // Genius URL
        info.geniusURL = song["url"] as? String

        return info
    }

    private func fetchTopAnnotation(songId: Int, apiKey: String) async throws -> String? {
        guard let url = URL(string: "\(baseURL)/referents?song_id=\(songId)&text_format=plain&per_page=5") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseBody = json["response"] as? [String: Any],
              let referents = responseBody["referents"] as? [[String: Any]] else {
            return nil
        }

        var bestAnnotation: (text: String, votes: Int)?
        for referent in referents {
            if let annotations = referent["annotations"] as? [[String: Any]] {
                for annotation in annotations {
                    if let body = annotation["body"] as? [String: Any],
                       let plain = body["plain"] as? String,
                       !plain.isEmpty {
                        let votes = annotation["votes_total"] as? Int ?? 0
                        if bestAnnotation == nil || votes > bestAnnotation!.votes {
                            bestAnnotation = (text: plain, votes: votes)
                        }
                    }
                }
            }
        }

        return bestAnnotation?.text
    }

    private func fetchQuestions(geniusURL: String?) async throws -> [(question: String, answer: String)] {
        guard let urlString = geniusURL, let url = URL(string: urlString) else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        // Extract __PRELOADED_STATE__ JSON from the page
        guard let stateJSON = extractPreloadedState(from: html) else { return [] }

        guard let entities = stateJSON["entities"] as? [String: Any],
              let questionsMap = entities["questions"] as? [String: Any],
              let answersMap = entities["answers"] as? [String: Any],
              let songPage = stateJSON["songPage"] as? [String: Any],
              let pinnedIds = songPage["pinnedQuestions"] as? [Any] else {
            return []
        }

        var results: [(question: String, answer: String)] = []
        for pinnedId in pinnedIds.prefix(5) {
            let qKey = "\(pinnedId)"
            guard let q = questionsMap[qKey] as? [String: Any] else { continue }

            // Question body can be a plain String or a dict with markdown/plain keys
            let qText: String
            if let bodyStr = q["body"] as? String {
                qText = bodyStr
            } else if let bodyDict = q["body"] as? [String: Any] {
                qText = bodyDict["markdown"] as? String ?? bodyDict["plain"] as? String ?? ""
            } else {
                continue
            }
            guard !qText.isEmpty else { continue }

            guard let ansId = q["answer"],
                  let aObj = answersMap["\(ansId)"] as? [String: Any],
                  let aBody = aObj["body"] as? [String: Any] else { continue }
            var aText = aBody["markdown"] as? String ?? aBody["plain"] as? String ?? ""
            guard !aText.isEmpty else { continue }

            // Strip markdown links: [text](url) → text
            aText = aText.replacingOccurrences(
                of: "\\[([^\\]]+)\\]\\([^)]+\\)",
                with: "$1",
                options: .regularExpression
            )

            results.append((question: qText, answer: aText))
        }
        return results
    }

    private func extractPreloadedState(from html: String) -> [String: Any]? {
        guard let startMarker = html.range(of: "window.__PRELOADED_STATE__ = JSON.parse('"),
              let endMarker = html.range(of: "');", range: startMarker.upperBound..<html.endIndex) else {
            return nil
        }

        var raw = String(html[startMarker.upperBound..<endMarker.lowerBound])

        // Unescape JS string: the content is a JSON string inside JS single quotes
        // Handle \\ first (to preserve literal backslashes), then \" and \'
        raw = raw.replacingOccurrences(of: "\\\\", with: "\u{0000}PH\u{0000}")
        raw = raw.replacingOccurrences(of: "\\\"", with: "\"")
        raw = raw.replacingOccurrences(of: "\\'", with: "'")
        raw = raw.replacingOccurrences(of: "\u{0000}PH\u{0000}", with: "\\")

        // Fix invalid JSON escapes (e.g. \$ in user-generated content)
        let pattern = try? NSRegularExpression(pattern: "\\\\(?![\"\\\\\\//bfnrtu])")
        if let pattern {
            raw = pattern.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        }

        guard let jsonData = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return json
    }
}

enum GeniusError: LocalizedError {
    case invalidAPIKey
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid Genius API key. Check your key in Settings."
        case .httpError(let code):
            return "Genius API error (HTTP \(code))."
        }
    }
}

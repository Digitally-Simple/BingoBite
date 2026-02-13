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

                // Step 3: Get top annotation
                let annotation = try await fetchTopAnnotation(songId: songId, apiKey: apiKey)
                guard !Task.isCancelled else { return }
                info.topAnnotation = annotation

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

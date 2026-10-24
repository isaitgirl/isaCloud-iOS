//
//  GiphySearch.swift
//  Monal
//
//  isaCloud: GIF search for the chat input (Giphy API). The key comes from the build (GiphyAPIKey in Info.plist),
//  kept out of the repository; the GIF is sent as its original animated file, so the animation is kept.
//

import Foundation

struct GiphyGif: Equatable {
    let id: String
    /// small animated version of the GIF, for the preview grid
    let previewURL: URL
    /// the animated GIF that is sent
    let originalURL: URL
}

enum GiphySearchError: Error, Equatable {
    case missingKey
    case badResponse
}

enum GiphySearch {
    static let endpoint = URL(string: "https://api.giphy.com/v1/gifs/search")!

    /// the key from the build; empty or unresolved values count as missing
    static func apiKey(from infoDictionary: [String: Any]?) -> String? {
        guard let key = infoDictionary?["GiphyAPIKey"] as? String else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") {
            return nil
        }
        return trimmed
    }

    static let trendingEndpoint = URL(string: "https://api.giphy.com/v1/gifs/trending")!

    static func searchURL(query: String, apiKey: String, limit: Int = 24) -> URL? {
        return url(endpoint, [URLQueryItem(name: "q", value: query)], apiKey: apiKey, limit: limit)
    }

    static func trendingURL(apiKey: String, limit: Int = 24) -> URL? {
        return url(trendingEndpoint, [], apiKey: apiKey, limit: limit)
    }

    private static func url(_ endpoint: URL, _ extra: [URLQueryItem], apiKey: String, limit: Int) -> URL? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "rating", value: "g"),
        ] + extra
        return components?.url
    }

    /// reads the "data" list of a Giphy search response; GIFs without the needed URLs are skipped
    static func parse(_ data: Data) throws -> [GiphyGif] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else {
            throw GiphySearchError.badResponse
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let images = item["images"] as? [String: Any],
                  let previewURL = previewURL(in: images),
                  let original = images["original"] as? [String: Any],
                  let originalURL = (original["url"] as? String).flatMap(URL.init(string:)) else {
                return nil
            }
            return GiphyGif(id: id, previewURL: previewURL, originalURL: originalURL)
        }
    }

    /// the small animated version, or the still one when Giphy does not send the animated one
    private static func previewURL(in images: [String: Any]) -> URL? {
        for name in ["fixed_width_small", "fixed_width_small_still"] {
            if let image = images[name] as? [String: Any], let url = (image["url"] as? String).flatMap(URL.init(string:)) {
                return url
            }
        }
        return nil
    }

    static func search(query: String, apiKey: String) async throws -> [GiphyGif] {
        guard let url = searchURL(query: query, apiKey: apiKey) else {
            throw GiphySearchError.badResponse
        }
        return try await fetch(url)
    }

    static func trending(apiKey: String) async throws -> [GiphyGif] {
        guard let url = trendingURL(apiKey: apiKey) else {
            throw GiphySearchError.badResponse
        }
        return try await fetch(url)
    }

    private static func fetch(_ url: URL) async throws -> [GiphyGif] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GiphySearchError.badResponse
        }
        return try parse(data)
    }

    /// the bytes of a GIF, from the network or from a local file
    static func loadData(_ url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        return try? await URLSession.shared.data(from: url).0
    }

    /// downloads the animated GIF to a temporary file, to be sent as an attachment
    static func download(_ gif: GiphyGif) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: gif.originalURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GiphySearchError.badResponse
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-\(gif.id).gif")
        try data.write(to: url, options: .atomic)
        return url
    }
}

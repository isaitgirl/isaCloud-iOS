//
//  GiphySearch.swift
//  Monal
//
//  isaCloud: GIF search for the chat input (GIPHY and KLIPY APIs). The keys come from the build (GiphyAPIKey and KlipyAPIKey in
//  Info.plist), kept out of the repository; the GIF is sent as its original animated file, so the animation is kept.
//

import Foundation

struct GiphyGif: Equatable, Codable {
    let id: String
    /// small animated version of the GIF, for the preview grid
    let previewURL: URL
    /// the animated GIF that is sent
    let originalURL: URL
}

/// isaCloud: the GIF providers the picker can search. GIPHY is the default; KLIPY is the second option.
enum GifProvider: String, CaseIterable, Identifiable {
    case giphy, klipy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .giphy: return "GIPHY"
        case .klipy: return "KLIPY"
        }
    }

    /// the key in HelperTools.defaultsDB() holding the chosen provider ("giphy" or "klipy")
    static let defaultsKey = "gifProvider"
    static let defaultProvider: GifProvider = .giphy
}

/// isaCloud: the keys of each provider, from the build. A provider without a key is not offered.
struct GifKeys: Equatable {
    var giphy: String?
    var klipy: String?

    static func fromBundle(_ infoDictionary: [String: Any]?) -> GifKeys {
        return GifKeys(giphy: GiphySearch.apiKey(named: "GiphyAPIKey", from: infoDictionary),
                       klipy: GiphySearch.apiKey(named: "KlipyAPIKey", from: infoDictionary))
    }

    func key(for provider: GifProvider) -> String? {
        switch provider {
        case .giphy: return giphy
        case .klipy: return klipy
        }
    }

    /// the providers that have a key, in the order of GifProvider.allCases
    var available: [GifProvider] {
        return GifProvider.allCases.filter { key(for: $0) != nil }
    }

    /// the stored choice when it has a key; otherwise the default when it has a key; otherwise the first available; nil when none
    func resolved(stored: String?) -> GifProvider? {
        if let stored, let provider = GifProvider(rawValue: stored), key(for: provider) != nil {
            return provider
        }
        if key(for: GifProvider.defaultProvider) != nil {
            return GifProvider.defaultProvider
        }
        return available.first
    }
}

/// one page of results; hasMore tells whether another page may exist. fromCache and rateLimitRemaining only feed the log.
struct GifPage: Equatable {
    let gifs: [GiphyGif]
    let hasMore: Bool
    /// isaCloud: true when the HTTP cache answered, so no request reached the server
    var fromCache: Bool = false
    /// isaCloud: the x-ratelimit-remaining header of the response, when the server sends it
    var rateLimitRemaining: Int? = nil
}

/// isaCloud: the one session for every GIF request. Both API keys are limited for all users together, so the responses the server
/// marks as cacheable (KLIPY: 6 h; the GIF files: 1 to 7 days) are kept in an HTTP cache on disk.
enum GifNetwork {
    static let cachesDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory

    static let cache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024,
                                directory: GifNetwork.cachesDirectory.appendingPathComponent("gif-http-cache"))

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    /// the data of a GET request, and whether the HTTP cache answered it (no request reached the server)
    static func fetch(_ url: URL) async throws -> (data: Data, response: URLResponse, fromCache: Bool) {
        let delegate = CacheMetricsDelegate()
        let (data, response) = try await session.data(for: URLRequest(url: url), delegate: delegate)
        return (data, response, delegate.servedFromCache)
    }

    /// the x-ratelimit-remaining header of a response; nil when the server does not send it
    static func rateLimitRemaining(_ response: HTTPURLResponse) -> Int? {
        return response.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap { Int($0) }
    }
}

/// isaCloud: reads from the transaction metrics whether the cache answered the request (see GifNetwork.fetch)
private final class CacheMetricsDelegate: NSObject, URLSessionTaskDelegate {
    // written on the session's delegate queue and read after the await, so it goes through a lock
    private let lock = NSLock()
    private var fromCache = false

    var servedFromCache: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fromCache
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let value = metrics.transactionMetrics.last?.resourceFetchType == .localCache
        lock.lock()
        fromCache = value
        lock.unlock()
    }
}

/// isaCloud: how many GIF requests the HTTP cache answered during one opening of the picker (logged when it closes)
final class GifNetworkStats {
    static let shared = GifNetworkStats()

    private let lock = NSLock()
    private var apiFromCache = 0
    private var apiFromNetwork = 0
    private var previewsFromCache = 0
    private var previewsFromNetwork = 0

    func recordAPI(fromCache: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if fromCache {
            apiFromCache += 1
        } else {
            apiFromNetwork += 1
        }
    }

    func recordPreview(fromCache: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if fromCache {
            previewsFromCache += 1
        } else {
            previewsFromNetwork += 1
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        apiFromCache = 0
        apiFromNetwork = 0
        previewsFromCache = 0
        previewsFromNetwork = 0
    }

    func snapshot() -> (apiFromCache: Int, apiFromNetwork: Int, previewsFromCache: Int, previewsFromNetwork: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (apiFromCache, apiFromNetwork, previewsFromCache, previewsFromNetwork)
    }
}

/// the reactions of a GIF message, grouped by emoji in the order they first appear, with how many of each
enum GifReactionCounts {
    static func counts(of emojis: [String]) -> [(emoji: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for emoji in emojis {
            if counts[emoji] == nil {
                order.append(emoji)
            }
            counts[emoji, default: 0] += 1
        }
        return order.map { (emoji: $0, count: counts[$0] ?? 0) }
    }
}

enum GiphySearchError: Error, Equatable {
    case missingKey
    case badResponse
}

enum GiphySearch {
    static let endpoint = URL(string: "https://api.giphy.com/v1/gifs/search")!

    /// the GIPHY key from the build; empty or unresolved values count as missing
    static func apiKey(from infoDictionary: [String: Any]?) -> String? {
        return apiKey(named: "GiphyAPIKey", from: infoDictionary)
    }

    /// a key from the build, by its Info.plist name; empty or unresolved values count as missing
    static func apiKey(named name: String, from infoDictionary: [String: Any]?) -> String? {
        guard let key = infoDictionary?[name] as? String else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") {
            return nil
        }
        return trimmed
    }

    static let trendingEndpoint = URL(string: "https://api.giphy.com/v1/gifs/trending")!

    static func searchURL(query: String, apiKey: String, limit: Int = 24, offset: Int = 0) -> URL? {
        return url(endpoint, [URLQueryItem(name: "q", value: query)], apiKey: apiKey, limit: limit, offset: offset)
    }

    static func trendingURL(apiKey: String, limit: Int = 24, offset: Int = 0) -> URL? {
        return url(trendingEndpoint, [], apiKey: apiKey, limit: limit, offset: offset)
    }

    private static func url(_ endpoint: URL, _ extra: [URLQueryItem], apiKey: String, limit: Int, offset: Int) -> URL? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
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

    static func search(query: String, apiKey: String, offset: Int = 0, limit: Int = 24) async throws -> GifPage {
        guard let url = searchURL(query: query, apiKey: apiKey, limit: limit, offset: offset) else {
            throw GiphySearchError.badResponse
        }
        return try await fetch(url, limit: limit)
    }

    static func trending(apiKey: String, offset: Int = 0, limit: Int = 24) async throws -> GifPage {
        guard let url = trendingURL(apiKey: apiKey, limit: limit, offset: offset) else {
            throw GiphySearchError.badResponse
        }
        return try await fetch(url, limit: limit)
    }

    /// a full page (as many GIFs as the limit) may be followed by another one; a shorter one is the last
    private static func fetch(_ url: URL, limit: Int) async throws -> GifPage {
        let (data, response, fromCache) = try await GifNetwork.fetch(url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GiphySearchError.badResponse
        }
        let gifs = try parse(data)
        GifNetworkStats.shared.recordAPI(fromCache: fromCache)
        return GifPage(gifs: gifs, hasMore: gifs.count == limit, fromCache: fromCache,
                       rateLimitRemaining: GifNetwork.rateLimitRemaining(http))
    }

    /// the bytes of a GIF, from the network or from a local file
    static func loadData(_ url: URL) async -> Data? {
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        guard let result = try? await GifNetwork.fetch(url) else {
            return nil
        }
        GifNetworkStats.shared.recordPreview(fromCache: result.fromCache)
        return result.data
    }

    /// downloads the animated GIF to a temporary file, to be sent as an attachment
    static func download(_ gif: GiphyGif) async throws -> URL {
        let (data, response, _) = try await GifNetwork.fetch(gif.originalURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GiphySearchError.badResponse
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-\(gif.id).gif")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// isaCloud: the KLIPY API (api.klipy.com). The key is a path segment of the URL. Pages start at 1. No customer id is sent.
enum KlipySearch {
    static let endpoint = URL(string: "https://api.klipy.com/api/v1")!

    static func trendingURL(apiKey: String, page: Int = 1, perPage: Int = GifSearch.pageSize) -> URL? {
        return url(["gifs", "trending"], [], apiKey: apiKey, page: page, perPage: perPage)
    }

    static func searchURL(query: String, apiKey: String, page: Int = 1, perPage: Int = GifSearch.pageSize) -> URL? {
        return url(["gifs", "search"], [URLQueryItem(name: "q", value: query)], apiKey: apiKey, page: page, perPage: perPage)
    }

    private static func url(_ segments: [String], _ extra: [URLQueryItem], apiKey: String, page: Int, perPage: Int) -> URL? {
        // the key is one path component: it is percent-encoded, so a "/" or "?" in it cannot change the path
        var url = endpoint.appendingPathComponent(apiKey)
        for segment in segments {
            url = url.appendingPathComponent(segment)
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = extra + [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "rating", value: "g"),
        ]
        return components?.url
    }

    /// reads the page of a KLIPY response; items that are not GIFs (ads) and items without the needed URLs are skipped
    static func parse(_ data: Data) throws -> GifPage {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let body = root["data"] as? [String: Any],
              let items = body["data"] as? [[String: Any]] else {
            throw GiphySearchError.badResponse
        }
        let gifs = items.compactMap(gif(from:))
        return GifPage(gifs: gifs, hasMore: (body["has_next"] as? Bool) ?? false)
    }

    private static func gif(from item: [String: Any]) -> GiphyGif? {
        // an item with another type (an ad) is not a GIF
        if let type = item["type"], (type as? String) != "gif" {
            return nil
        }
        let id: String?
        if let number = item["id"] as? NSNumber {
            id = number.stringValue
        } else {
            id = item["id"] as? String
        }
        guard let id, let file = item["file"] as? [String: Any],
              let previewURL = gifURL(file, size: "xs") ?? gifURL(file, size: "sm"),
              let originalURL = gifURL(file, size: "hd") ?? gifURL(file, size: "md") else {
            return nil
        }
        return GiphyGif(id: "klipy-\(id)", previewURL: previewURL, originalURL: originalURL)
    }

    /// the GIF file of one size (xs, sm, md or hd), or nil when KLIPY does not send it
    private static func gifURL(_ file: [String: Any], size: String) -> URL? {
        guard let sizes = file[size] as? [String: Any],
              let formats = sizes["gif"] as? [String: Any],
              let text = formats["url"] as? String else {
            return nil
        }
        return URL(string: text)
    }

    static func search(query: String, apiKey: String, page: Int, perPage: Int = GifSearch.pageSize) async throws -> GifPage {
        guard let url = searchURL(query: query, apiKey: apiKey, page: page, perPage: perPage) else {
            throw GiphySearchError.badResponse
        }
        return try await fetch(url)
    }

    static func trending(apiKey: String, page: Int, perPage: Int = GifSearch.pageSize) async throws -> GifPage {
        guard let url = trendingURL(apiKey: apiKey, page: page, perPage: perPage) else {
            throw GiphySearchError.badResponse
        }
        return try await fetch(url)
    }

    private static func fetch(_ url: URL) async throws -> GifPage {
        let (data, response, fromCache) = try await GifNetwork.fetch(url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GiphySearchError.badResponse
        }
        var page = try parse(data)
        page.fromCache = fromCache
        page.rateLimitRemaining = GifNetwork.rateLimitRemaining(http)
        GifNetworkStats.shared.recordAPI(fromCache: fromCache)
        return page
    }
}

/// isaCloud: the search of the chosen provider, one page at a time. The picker uses this, not the provider's own calls.
enum GifSearch {
    static let pageSize = 24
    /// isaCloud: the trending list asks for 50 at once, the most that both APIs allow
    static let trendingPageSize = 50
    /// isaCloud: the picker stops asking for more after this many pages (pageIndex 0, 1 and 2)
    static let maxPages = 3

    /// pageIndex starts at 0. GIPHY: offset = pageIndex * pageSize. KLIPY: page = pageIndex + 1. query nil = trending.
    static func fetch(provider: GifProvider, query: String?, apiKey: String, pageIndex: Int, pageSize: Int = GifSearch.pageSize) async throws -> GifPage {
        switch provider {
        case .giphy:
            let offset = pageIndex * pageSize
            if let query {
                return try await GiphySearch.search(query: query, apiKey: apiKey, offset: offset, limit: pageSize)
            }
            return try await GiphySearch.trending(apiKey: apiKey, offset: offset, limit: pageSize)
        case .klipy:
            if let query {
                return try await KlipySearch.search(query: query, apiKey: apiKey, page: pageIndex + 1, perPage: pageSize)
            }
            return try await KlipySearch.trending(apiKey: apiKey, page: pageIndex + 1, perPage: pageSize)
        }
    }
}

/// isaCloud: the first trending page of each provider, saved on disk, so opening the picker does not spend a request while the
/// list is fresh (the keys are shared by all users, see GifNetwork). The list is shown shuffled. KLIPY allows 6 h of caching; GIPHY
/// sends no cache headers, so its list is kept 1 h.
struct GifTrendingCache {
    struct Entry: Codable, Equatable {
        let provider: String
        let fetchedAt: Date
        let hasMore: Bool
        let gifs: [GiphyGif]
    }

    let directory: URL

    static let shared = GifTrendingCache(directory: GifNetwork.cachesDirectory.appendingPathComponent("gif-trending"))

    /// how long a saved list is used
    static func ttl(for provider: GifProvider) -> TimeInterval {
        switch provider {
        case .klipy: return 6 * 60 * 60
        case .giphy: return 60 * 60
        }
    }

    private func fileURL(for provider: GifProvider) -> URL {
        return directory.appendingPathComponent("\(provider.rawValue).json")
    }

    /// keeps the page as the saved list of its provider; a failure to write is ignored, the list is only a cache
    func save(_ page: GifPage, provider: GifProvider, now: Date = Date()) {
        let entry = Entry(provider: provider.rawValue, fetchedAt: now, hasMore: page.hasMore, gifs: page.gifs)
        guard let data = try? JSONEncoder().encode(entry) else {
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: provider), options: .atomic)
    }

    /// the saved list of the provider; nil when there is none, it cannot be read, or it is older than its TTL
    func load(provider: GifProvider, now: Date = Date()) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: provider)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.provider == provider.rawValue else {
            return nil
        }
        // a date more than a minute in the future is not trusted
        let age = now.timeIntervalSince(entry.fetchedAt)
        guard age >= -60, age <= GifTrendingCache.ttl(for: provider) else {
            return nil
        }
        return entry
    }
}

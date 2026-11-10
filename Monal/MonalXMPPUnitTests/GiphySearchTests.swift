//
//  GiphySearchTests.swift
//  MonalXMPPUnitTests
//
//  The GIF search: the key from the build, the request, and the reading of Giphy's response.
//

import Testing
import Foundation

struct GiphySearchTests {

    @Test("the key comes from the build, and an empty or unresolved one counts as missing")
    func keyFromBuild() {
        #expect(GiphySearch.apiKey(from: ["GiphyAPIKey": "abc123"]) == "abc123")
        #expect(GiphySearch.apiKey(from: ["GiphyAPIKey": "  abc123 \n"]) == "abc123")
        #expect(GiphySearch.apiKey(from: ["GiphyAPIKey": ""]) == nil)
        #expect(GiphySearch.apiKey(from: ["GiphyAPIKey": "$(GIPHY_API_KEY)"]) == nil)
        #expect(GiphySearch.apiKey(from: [:]) == nil)
        #expect(GiphySearch.apiKey(from: nil) == nil)
    }

    @Test("the search request carries the key, the words, the limit and the rating")
    func searchURL() throws {
        let url = try #require(GiphySearch.searchURL(query: "gato feliz", apiKey: "k1"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "api.giphy.com")
        #expect(values["api_key"] == "k1")
        #expect(values["q"] == "gato feliz")
        #expect(values["limit"] == "24")
        #expect(values["rating"] == "g")
    }

    @Test("the search request asks for the page at the given offset, and the first page by default")
    func searchOffset() throws {
        let first = try #require(GiphySearch.searchURL(query: "gato", apiKey: "k1"))
        let later = try #require(GiphySearch.searchURL(query: "gato", apiKey: "k1", offset: 48))
        let firstItems = try #require(URLComponents(url: first, resolvingAgainstBaseURL: false)?.queryItems)
        let laterItems = try #require(URLComponents(url: later, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(firstItems.first { $0.name == "offset" }?.value == "0")
        #expect(laterItems.first { $0.name == "offset" }?.value == "48")
        #expect(laterItems.first { $0.name == "q" }?.value == "gato")
        #expect(laterItems.first { $0.name == "rating" }?.value == "g")
    }

    @Test("the response gives the preview and the animated GIF of each result")
    func parsesResults() throws {
        let json = """
        {"data": [
          {"id": "a1", "images": {
             "fixed_width_small_still": {"url": "https://media.giphy.com/a1/still.gif"},
             "original": {"url": "https://media.giphy.com/a1/giphy.gif"}}},
          {"id": "b2", "images": {"original": {"url": "https://media.giphy.com/b2/giphy.gif"}}},
          {"id": "c3", "images": {
             "fixed_width_small_still": {"url": "https://media.giphy.com/c3/still.gif"},
             "original": {"url": "https://media.giphy.com/c3/giphy.gif"}}}
        ], "meta": {"status": 200}}
        """
        let gifs = try GiphySearch.parse(Data(json.utf8))
        #expect(gifs.count == 2)
        #expect(gifs[0] == GiphyGif(id: "a1", previewURL: URL(string: "https://media.giphy.com/a1/still.gif")!, originalURL: URL(string: "https://media.giphy.com/a1/giphy.gif")!))
        #expect(gifs[1].id == "c3")
    }

    @Test("an unexpected response is an error, not an empty list")
    func badResponse() {
        #expect(throws: GiphySearchError.badResponse) {
            try GiphySearch.parse(Data("{\"oops\": true}".utf8))
        }
        #expect(throws: GiphySearchError.badResponse) {
            try GiphySearch.parse(Data("não é json".utf8))
        }
    }
}

struct GifReactionCountsTests {

    @Test("reactions are counted per emoji, in the order they first appear")
    func countsPerEmoji() {
        let counts = GifReactionCounts.counts(of: ["❤️", "😂", "❤️", "❤️", "👍"])
        #expect(counts.map { $0.emoji } == ["❤️", "😂", "👍"])
        #expect(counts.map { $0.count } == [3, 1, 1])
    }

    @Test("no reactions gives no bubbles")
    func noReactions() {
        #expect(GifReactionCounts.counts(of: []).isEmpty)
    }
}

struct GiphyTrendingTests {

    @Test("the trending list asks Giphy for the trending endpoint with the key and the rating")
    func trendingURL() throws {
        let url = try #require(GiphySearch.trendingURL(apiKey: "k1"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path == "/v1/gifs/trending")
        #expect(values["api_key"] == "k1")
        #expect(values["rating"] == "g")
        #expect(values["q"] == nil)
    }

    @Test("the trending request asks for the page at the given offset, and the first page by default")
    func trendingOffset() throws {
        let first = try #require(GiphySearch.trendingURL(apiKey: "k1"))
        let later = try #require(GiphySearch.trendingURL(apiKey: "k1", offset: 73))
        let firstItems = try #require(URLComponents(url: first, resolvingAgainstBaseURL: false)?.queryItems)
        let laterItems = try #require(URLComponents(url: later, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(firstItems.first { $0.name == "offset" }?.value == "0")
        #expect(laterItems.first { $0.name == "offset" }?.value == "73")
        #expect(laterItems.first { $0.name == "q" } == nil)
    }

    @Test("the preview is the small animated GIF when Giphy sends it")
    func previewIsAnimated() throws {
        let json = """
        {"data": [{"id": "a1", "images": {
           "fixed_width_small": {"url": "https://media.giphy.com/a1/200w.gif"},
           "fixed_width_small_still": {"url": "https://media.giphy.com/a1/200w_s.gif"},
           "original": {"url": "https://media.giphy.com/a1/giphy.gif"}}}]}
        """
        let gifs = try GiphySearch.parse(Data(json.utf8))
        #expect(gifs.first?.previewURL == URL(string: "https://media.giphy.com/a1/200w.gif"))
    }
}

struct KlipySearchTests {

    /// two GIFs, an ad (another type) and an item without the big sizes: only the two GIFs are read
    private let sample = """
    {"result": true, "data": {"data": [
      {"id": 6561878491986958, "slug": "a", "title": "a", "type": "gif", "file": {
         "hd": {"gif": {"url": "https://static.klipy.com/a/hd.gif", "width": 498, "height": 258, "size": 1090997}},
         "md": {"gif": {"url": "https://static.klipy.com/a/md.gif"}},
         "sm": {"gif": {"url": "https://static.klipy.com/a/sm.gif"}},
         "xs": {"gif": {"url": "https://static.klipy.com/a/xs.gif"}}}},
      {"id": 6561878491986959, "type": "gif", "file": {
         "md": {"gif": {"url": "https://static.klipy.com/b/md.gif"}},
         "sm": {"gif": {"url": "https://static.klipy.com/b/sm.gif"}}}},
      {"id": 42, "type": "ad", "file": {
         "hd": {"gif": {"url": "https://static.klipy.com/ad/hd.gif"}},
         "xs": {"gif": {"url": "https://static.klipy.com/ad/xs.gif"}}}},
      {"id": 43, "type": "gif", "file": {
         "xs": {"gif": {"url": "https://static.klipy.com/c/xs.gif"}}}}
    ], "current_page": 1, "per_page": 24, "has_next": true, "meta": {}}}
    """

    @Test("the page reads the GIFs, skips the ads and the items without the URLs, and says whether more follow")
    func parsesPage() throws {
        let page = try KlipySearch.parse(Data(sample.utf8))
        #expect(page.gifs.map { $0.id } == ["klipy-6561878491986958", "klipy-6561878491986959"])
        #expect(page.hasMore)
    }

    @Test("the preview is the extra small GIF, the sent one the HD GIF; the smaller sizes fill in when a size is missing")
    func sizesAndFallbacks() throws {
        let page = try KlipySearch.parse(Data(sample.utf8))
        let first = try #require(page.gifs.first)
        #expect(first.previewURL == URL(string: "https://static.klipy.com/a/xs.gif"))
        #expect(first.originalURL == URL(string: "https://static.klipy.com/a/hd.gif"))
        let second = try #require(page.gifs.last)
        #expect(second.previewURL == URL(string: "https://static.klipy.com/b/sm.gif"))
        #expect(second.originalURL == URL(string: "https://static.klipy.com/b/md.gif"))
    }

    @Test("a last page says there are no more; a string id is read too")
    func lastPageAndStringId() throws {
        let json = """
        {"result": true, "data": {"data": [
          {"id": "777", "type": "gif", "file": {"hd": {"gif": {"url": "https://static.klipy.com/s/hd.gif"}}, "xs": {"gif": {"url": "https://static.klipy.com/s/xs.gif"}}}}
        ], "has_next": false}}
        """
        let page = try KlipySearch.parse(Data(json.utf8))
        #expect(page.gifs.map { $0.id } == ["klipy-777"])
        #expect(page.hasMore == false)
    }

    @Test("an unexpected response is an error, not an empty page")
    func badResponse() {
        #expect(throws: GiphySearchError.badResponse) {
            try KlipySearch.parse(Data("{\"oops\": true}".utf8))
        }
        #expect(throws: GiphySearchError.badResponse) {
            try KlipySearch.parse(Data("não é json".utf8))
        }
    }

    @Test("the search request carries the key in the path, the words, the page, the size and the rating, and no customer id")
    func searchURL() throws {
        let url = try #require(KlipySearch.searchURL(query: "gato feliz", apiKey: "test-key", page: 2))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "api.klipy.com")
        #expect(url.path == "/api/v1/test-key/gifs/search")
        #expect(values["q"] == "gato feliz")
        #expect(values["page"] == "2")
        #expect(values["per_page"] == "24")
        #expect(values["rating"] == "g")
        #expect(values["customer_id"] == nil)
        #expect(values["api_key"] == nil)
    }

    @Test("the trending request has the key in the path and no search words, and no customer id")
    func trendingURL() throws {
        let url = try #require(KlipySearch.trendingURL(apiKey: "test-key", page: 1))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path == "/api/v1/test-key/gifs/trending")
        #expect(values["q"] == nil)
        #expect(values["page"] == "1")
        #expect(values["per_page"] == "24")
        #expect(values["rating"] == "g")
        #expect(values["customer_id"] == nil)
    }
}

struct GifProviderTests {

    @Test("the stored choice wins when its provider has a key")
    func storedChoice() {
        let both = GifKeys(giphy: "test-giphy", klipy: "test-klipy")
        #expect(both.resolved(stored: "klipy") == .klipy)
        #expect(both.resolved(stored: "giphy") == .giphy)
    }

    @Test("a stored choice without a key falls back to the default, then to the first one with a key")
    func fallbacks() {
        #expect(GifKeys(giphy: "test-giphy", klipy: nil).resolved(stored: "klipy") == .giphy)
        #expect(GifKeys(giphy: nil, klipy: "test-klipy").resolved(stored: "giphy") == .klipy)
        #expect(GifKeys(giphy: nil, klipy: "test-klipy").resolved(stored: nil) == .klipy)
    }

    @Test("without a stored choice the default is GIPHY, and a garbage value counts as no choice")
    func defaultAndGarbage() {
        let both = GifKeys(giphy: "test-giphy", klipy: "test-klipy")
        #expect(both.resolved(stored: nil) == .giphy)
        #expect(both.resolved(stored: "tenor") == .giphy)
        #expect(both.resolved(stored: "") == .giphy)
    }

    @Test("with no key at all there is no provider")
    func noKeys() {
        let none = GifKeys(giphy: nil, klipy: nil)
        #expect(none.resolved(stored: "klipy") == nil)
        #expect(none.available.isEmpty)
    }

    @Test("the providers offered are the ones with a key, in the order of the enum")
    func available() {
        #expect(GifKeys(giphy: "test-giphy", klipy: "test-klipy").available == [.giphy, .klipy])
        #expect(GifKeys(giphy: nil, klipy: "test-klipy").available == [.klipy])
    }

    @Test("the keys come from the build, and an unresolved KLIPY key counts as missing")
    func keysFromBundle() {
        #expect(GifKeys.fromBundle(["GiphyAPIKey": "test-giphy", "KlipyAPIKey": "test-klipy"]) == GifKeys(giphy: "test-giphy", klipy: "test-klipy"))
        #expect(GifKeys.fromBundle(["GiphyAPIKey": "test-giphy", "KlipyAPIKey": "$(KLIPY_API_KEY)"]) == GifKeys(giphy: "test-giphy", klipy: nil))
        #expect(GifKeys.fromBundle(nil) == GifKeys(giphy: nil, klipy: nil))
    }
}

struct GifPagingTests {

    @Test("GIPHY asks the page size as the limit and the offset of the page: page 2 of 50 is offset 100")
    func giphyPageSize() throws {
        let url = try #require(GiphySearch.trendingURL(apiKey: "k1", limit: 50, offset: 100))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values["limit"] == "50")
        #expect(values["offset"] == "100")
    }

    @Test("KLIPY asks the page size as per_page and the page from 1: page 2 of 50 is page 3")
    func klipyPageSize() throws {
        let url = try #require(KlipySearch.trendingURL(apiKey: "test-key", page: 3, perPage: 50))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values["page"] == "3")
        #expect(values["per_page"] == "50")
    }
}

struct GifTrendingCacheTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// a cache in a new empty folder, removed when the body ends
    private func withCache(_ body: (GifTrendingCache) throws -> Void) rethrows {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gif-trending-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(GifTrendingCache(directory: directory))
    }

    private func page(_ id: String) -> GifPage {
        let gif = GiphyGif(id: id,
                           previewURL: URL(string: "https://media.giphy.com/\(id)/preview.gif")!,
                           originalURL: URL(string: "https://media.giphy.com/\(id)/original.gif")!)
        return GifPage(gifs: [gif], hasMore: true)
    }

    @Test("a saved list comes back with its GIFs, its flag and its time")
    func roundTrip() {
        withCache { cache in
            cache.save(page("a1"), provider: .giphy, now: start)
            let entry = cache.load(provider: .giphy, now: start.addingTimeInterval(60))
            #expect(entry?.gifs == page("a1").gifs)
            #expect(entry?.hasMore == true)
            #expect(entry?.fetchedAt == start)
            #expect(entry?.provider == "giphy")
        }
    }

    @Test("a GIPHY list expires after 1 hour and a KLIPY list after 6 hours")
    func expires() {
        #expect(GifTrendingCache.ttl(for: .giphy) == 3600)
        #expect(GifTrendingCache.ttl(for: .klipy) == 21600)
        withCache { cache in
            cache.save(page("g1"), provider: .giphy, now: start)
            cache.save(page("k1"), provider: .klipy, now: start)
            #expect(cache.load(provider: .giphy, now: start.addingTimeInterval(3599)) != nil)
            #expect(cache.load(provider: .giphy, now: start.addingTimeInterval(3601)) == nil)
            #expect(cache.load(provider: .klipy, now: start.addingTimeInterval(3601)) != nil)
            #expect(cache.load(provider: .klipy, now: start.addingTimeInterval(6 * 3600 + 1)) == nil)
        }
    }

    @Test("each provider keeps its own list")
    func separateProviders() {
        withCache { cache in
            cache.save(page("g1"), provider: .giphy, now: start)
            cache.save(page("k1"), provider: .klipy, now: start)
            #expect(cache.load(provider: .giphy, now: start)?.gifs.map { $0.id } == ["g1"])
            #expect(cache.load(provider: .klipy, now: start)?.gifs.map { $0.id } == ["k1"])
        }
    }

    @Test("a time far in the future is not trusted")
    func futureTime() {
        withCache { cache in
            cache.save(page("g1"), provider: .giphy, now: start)
            #expect(cache.load(provider: .giphy, now: start.addingTimeInterval(-30)) != nil)
            #expect(cache.load(provider: .giphy, now: start.addingTimeInterval(-120)) == nil)
        }
    }

    @Test("a damaged file is no saved list")
    func corruptFile() throws {
        try withCache { cache in
            try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
            try Data("não é json".utf8).write(to: cache.directory.appendingPathComponent("giphy.json"))
            #expect(cache.load(provider: .giphy, now: start) == nil)
        }
    }
}

struct GiphyGifCodableTests {

    @Test("a GIF is written and read back as it was")
    func roundTrip() throws {
        let gif = GiphyGif(id: "klipy-1",
                           previewURL: URL(string: "https://static.klipy.com/a/xs.gif")!,
                           originalURL: URL(string: "https://static.klipy.com/a/hd.gif")!)
        let data = try JSONEncoder().encode([gif])
        let back = try JSONDecoder().decode([GiphyGif].self, from: data)
        #expect(back == [gif])
    }
}

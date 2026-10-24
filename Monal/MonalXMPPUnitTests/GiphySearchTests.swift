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

//
//  IsaCloudConference.swift
//  Monal
//
//  isaCloud: video conferences (Galene, through the meet-api at meet.isacloud.cc). The app asks the meet-api for a room and
//  puts the room's public link in the chat. The host link (hostURL) is a credential: it is only kept in the keychain of this
//  device, and is never logged or put in a message.
//

import Foundation
import monalxmpp
import SAMKeychain

/// isaCloud: the room the meet-api created, as the app keeps it
struct IsaCloudConferenceRoom: Equatable {
    let roomID: String
    /// the public link, to share in the chat (no token in it)
    let roomURL: URL
    /// the host link: the credential of whoever created the room
    let hostURL: URL
    let hostKey: String
    let expiresAt: Date
}

enum IsaCloudConferenceError: Error, Equatable {
    /// no answer in time, or no connection
    case network
    /// any answer other than 201 (the body is never read into the error)
    case server
    /// a 201 whose body is not the expected JSON, or whose links are not the meet host's
    case badResponse
}

/// isaCloud: the links of the conference service
enum IsaCloudConference {
    static let host = "meet.isacloud.cc"

    /// the room id of a public conference link (https://meet.isacloud.cc/join/<id>); nil for any other URL
    static func roomID(from url: URL) -> String? {
        guard url.scheme == "https", url.host?.lowercased() == host,
              url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            return nil
        }
        let prefix = "/join/"
        //URL.path drops a trailing slash, URLComponents keeps it: "/join/<id>/" is not a conference link
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
        guard path.hasPrefix(prefix) else {
            return nil
        }
        let roomID = String(path.dropFirst(prefix.count))
        guard roomID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            return nil
        }
        return roomID
    }

    /// true for an https link on the conference host (the only links the app opens or stores)
    static func isMeetURL(_ url: URL) -> Bool {
        return url.scheme == "https" && url.host?.lowercased() == host
    }

    /// the name the host shows in the room: the account's display name, or the local part of the JID when it is empty
    static func hostName(for account: xmpp) -> String {
        let displayName = MLContact.ownDisplayName(forAccount: account).trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            return displayName
        }
        let jid = account.connectionProperties.identity.jid ?? ""
        return HelperTools.splitJid(jid)["node"] ?? ""
    }
}

/// isaCloud: the HTTP client of the meet-api. Only the room creation is used by the app; the guest's page does the rest.
enum IsaCloudConferenceApi {
    static let roomsEndpoint = URL(string: "https://meet.isacloud.cc/meet-api/v1/rooms")!

    /// the session has no cookies, no cache and no redirects; the whole request has 15 seconds
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: IsaCloudConferenceNoRedirectDelegate(), delegateQueue: nil)
    }()

    /// asks the meet-api for a room of this host name
    static func createRoom(hostName: String) async throws -> IsaCloudConferenceRoom {
        var request = URLRequest(url: roomsEndpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(IsaCloudConferenceRequestBody(hostName: hostName))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw IsaCloudConferenceError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw IsaCloudConferenceError.badResponse
        }
        return try parse(status: http.statusCode, data: data)
    }

    /// the answer of POST /meet-api/v1/rooms: only a 201 with the expected JSON and the meet host's links is accepted
    static func parse(status: Int, data: Data) throws -> IsaCloudConferenceRoom {
        guard status == 201 else {
            throw IsaCloudConferenceError.server
        }
        guard let body = try? JSONDecoder().decode(IsaCloudConferenceResponseBody.self, from: data),
              let roomURL = URL(string: body.roomURL),
              IsaCloudConference.roomID(from: roomURL) == body.roomID,
              let hostURL = URL(string: body.hostURL),
              IsaCloudConference.isMeetURL(hostURL),
              !body.hostKey.isEmpty,
              let expiresAt = parseDate(body.expiresAt) else {
            throw IsaCloudConferenceError.badResponse
        }
        return IsaCloudConferenceRoom(roomID: body.roomID, roomURL: roomURL, hostURL: hostURL, hostKey: body.hostKey, expiresAt: expiresAt)
    }

    /// RFC 3339 with or without fractional seconds
    private static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

private struct IsaCloudConferenceRequestBody: Encodable {
    let hostName: String
}

private struct IsaCloudConferenceResponseBody: Decodable {
    let roomID: String
    let roomURL: String
    let hostURL: String
    let hostKey: String
    let expiresAt: String
}

private final class IsaCloudConferenceNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        //isaCloud: the redirect is not followed; the 3xx answer then fails as "server"
        completionHandler(nil)
    }
}

/// isaCloud: the host links of this device, one keychain entry per room (account = room id). The value is JSON with hostURL,
/// hostKey, expiresAt and savedAt (epoch seconds). The room the card shows is kept in the defaults only when dismissed.
enum IsaCloudConferenceStore {
    /// posted on the main thread after every save, dismiss or removal
    static let changedNotification = NSNotification.Name("IsaCloudConferenceStore.changed")

    /// the room id the person dismissed from the list card (cleared when a new room is saved)
    static let dismissedRoomDefaultsKey = "isaCloudConferenceDismissedRoom"

    private struct Entry: Codable {
        let hostURL: String
        let hostKey: String
        let expiresAt: TimeInterval
        let savedAt: TimeInterval
    }

    /// serializes this store's keychain writes. SAMKeychain's accessibility type is one global setting, so the write sets it and
    /// writes under this lock; the other keychain code of the app sets its own type under its own lock.
    private static let keychainLock = NSLock()

    /// keeps the host link of a room; a new room also brings the card back (it clears the dismissal)
    @discardableResult
    static func save(roomID: String, hostURL: URL, hostKey: String, expiresAt: Date) -> Bool {
        let entry = Entry(hostURL: hostURL.absoluteString, hostKey: hostKey,
                          expiresAt: expiresAt.timeIntervalSince1970, savedAt: Date().timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(entry), let json = String(data: data, encoding: .utf8) else {
            return false
        }
        var saved = false
        keychainLock.lock()
        SAMKeychain.setAccessibilityType(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        saved = SAMKeychain.setPassword(json, forService: kIsaCloudMeetKeychainName, account: roomID)
        keychainLock.unlock()
        HelperTools.defaultsDB().removeObject(forKey: dismissedRoomDefaultsKey)
        removeExpired(postNotification: false)
        postChanged()
        return saved
    }

    /// the host link of a room, while it is valid: not expired, https and on the meet host. An expired room is removed.
    static func hostURL(forRoomID roomID: String) -> URL? {
        guard let entry = loadEntry(roomID: roomID) else {
            return nil
        }
        if isExpired(entry) {
            deleteEntry(roomID: roomID)
            postChanged()
            return nil
        }
        guard let url = URL(string: entry.hostURL), IsaCloudConference.isMeetURL(url) else {
            return nil
        }
        return url
    }

    /// the room the card of the list shows: the most recent valid room, unless it was dismissed; nil otherwise
    static func activeHostRoom() -> (roomID: String, hostURL: URL)? {
        guard let latest = latestValidRoom(), let url = URL(string: latest.entry.hostURL),
              IsaCloudConference.isMeetURL(url) else {
            return nil
        }
        if HelperTools.defaultsDB().string(forKey: dismissedRoomDefaultsKey) == latest.roomID {
            return nil
        }
        return (latest.roomID, url)
    }

    /// hides the card for the room it shows now (until a new room is saved)
    static func dismiss() {
        guard let latest = latestValidRoom() else {
            return
        }
        HelperTools.defaultsDB().set(latest.roomID, forKey: dismissedRoomDefaultsKey)
        postChanged()
    }

    /// removes the expired rooms from the keychain
    static func removeExpired() {
        removeExpired(postNotification: true)
    }

    // MARK: - private

    /// the most recent room that is not expired (expired ones found on the way are removed); the dismissal is not considered
    private static func latestValidRoom() -> (roomID: String, entry: Entry)? {
        var latest: (roomID: String, entry: Entry)? = nil
        var removed = false
        for roomID in storedRoomIDs() {
            guard let entry = loadEntry(roomID: roomID) else {
                continue
            }
            if isExpired(entry) {
                deleteEntry(roomID: roomID)
                removed = true
                continue
            }
            if latest == nil || entry.savedAt > latest!.entry.savedAt {
                latest = (roomID, entry)
            }
        }
        if removed {
            postChanged()
        }
        return latest
    }

    private static func removeExpired(postNotification: Bool) {
        var removed = false
        for roomID in storedRoomIDs() {
            guard let entry = loadEntry(roomID: roomID), isExpired(entry) else {
                continue
            }
            deleteEntry(roomID: roomID)
            removed = true
        }
        if removed && postNotification {
            postChanged()
        }
    }

    private static func isExpired(_ entry: Entry) -> Bool {
        return entry.expiresAt <= Date().timeIntervalSince1970
    }

    private static func storedRoomIDs() -> [String] {
        let accounts = SAMKeychain.accounts(forService: kIsaCloudMeetKeychainName) ?? []
        return accounts.compactMap { $0[kSAMKeychainAccountKey] as? String }
    }

    private static func loadEntry(roomID: String) -> Entry? {
        guard let json = SAMKeychain.password(forService: kIsaCloudMeetKeychainName, account: roomID),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private static func deleteEntry(roomID: String) {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        _ = SAMKeychain.deletePassword(forService: kIsaCloudMeetKeychainName, account: roomID)
    }

    /// the observers may be on any thread; the notification always goes out on the main thread
    private static func postChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: changedNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: changedNotification, object: nil)
            }
        }
    }
}

/// isaCloud: what the list (Objective-C) uses of the conference card: the host link of the room the card shows, the dismissal and the
/// change notification. The host link is only handed out when it is https on the meet host; it is never logged.
@objcMembers class IsaCloudConferenceBridge: NSObject {
    @objc static let changedNotification = IsaCloudConferenceStore.changedNotification

    /// the host link of the room the card shows (nil when there is no card)
    @objc static func activeHostURL() -> URL? {
        return IsaCloudConferenceStore.activeHostRoom()?.hostURL
    }

    /// hides the card for the room it shows now
    @objc static func dismiss() {
        IsaCloudConferenceStore.dismiss()
    }

    /// removes the expired rooms from the keychain
    @objc static func removeExpired() {
        IsaCloudConferenceStore.removeExpired()
    }
}

//
//  IsaCloudChangelog.swift
//  Monal
//
//  isaCloud: "Novidades do isaCloud", the changelog for users. The releases come from Monal/isaCloud-changelog.json (in the app bundle),
//  generated from CHANGELOG-USERS.md by scripts/isacloud-generate-changelog-json.py. A "batch" is the set of releases the user has not
//  seen yet: the builds after the previous one that was opened, up to the current build. Same rules as the Android app (ChangelogStore).
//  The state lives in UserDefaults.standard (not in defaultsDB: an unset key there crashes, see C18).
//

import SwiftUI

struct IsaCloudChangelogSection: Decodable {
    let title: String
    let items: [String]
}

struct IsaCloudChangelogRelease: Decodable {
    let build: Int
    let date: String?
    let sections: [IsaCloudChangelogSection]
}

@objc class IsaCloudChangelog: NSObject {

    struct Batch {
        // newest first
        let releases: [IsaCloudChangelogRelease]
        let toBuild: Int
        let isUnread: Bool
        let isArchived: Bool

        var isVisible: Bool {
            return !releases.isEmpty && !isArchived && toBuild > 0
        }
    }

    @objc static let changedNotification = Notification.Name("kIsaCloudChangelogChanged")

    private static let lastRunBuildKey = "isaCloudChangelog.lastRunBuild"
    private static let batchFromKey = "isaCloudChangelog.batchFrom"
    private static let batchToKey = "isaCloudChangelog.batchTo"
    private static let firstRunKey = "isaCloudChangelog.firstRun"
    private static let readBuildKey = "isaCloudChangelog.readBuild"
    private static let archivedBuildKey = "isaCloudChangelog.archivedBuild"

    // read once, newest build first
    private static let releases: [IsaCloudChangelogRelease] = loadReleases()

    private static func loadReleases() -> [IsaCloudChangelogRelease] {
        struct ChangelogFile: Decodable {
            let releases: [IsaCloudChangelogRelease]
        }
        guard let url = Bundle.main.url(forResource: "isaCloud-changelog", withExtension: "json") else {
            DDLogError("isaCloud: isaCloud-changelog.json is missing from the app bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ChangelogFile.self, from: data).releases.sorted { $0.build > $1.build }
        } catch {
            DDLogError("isaCloud: could not read isaCloud-changelog.json: \(error)")
            return []
        }
    }

    private static var currentBuild: Int {
        return Int((Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "") ?? 0
    }

    //every release in the JSON, newest first
    static func all() -> [IsaCloudChangelogRelease] {
        return releases
    }

    //call once per launch (in didFinishLaunchingWithOptions): sets the batch from the build that ran last to this one
    @objc static func recordLaunch() {
        let defaults = UserDefaults.standard
        let current = currentBuild
        let previous = defaults.object(forKey: lastRunBuildKey) as? Int
        if let previous = previous, current < previous {
            //downgrade: nothing to show
            defaults.set(false, forKey: firstRunKey)
            defaults.set(0, forKey: batchFromKey)
            defaults.set(0, forKey: batchToKey)
        } else if let previous = previous, current > previous {
            //update: everything after the previous build, so who skipped builds sees all of them
            defaults.set(false, forKey: firstRunKey)
            defaults.set(previous, forKey: batchFromKey)
            defaults.set(current, forKey: batchToKey)
        } else if previous == current && defaults.object(forKey: batchToKey) != nil {
            //same build again: keep the batch
        } else {
            //first run with this feature (or no batch yet): only the news of this build
            defaults.set(true, forKey: firstRunKey)
            defaults.set(0, forKey: batchFromKey)
            defaults.set(current, forKey: batchToKey)
        }
        defaults.set(current, forKey: lastRunBuildKey)
    }

    static func batch() -> Batch {
        let defaults = UserDefaults.standard
        let firstRun = defaults.bool(forKey: firstRunKey)
        let from = defaults.integer(forKey: batchFromKey)
        let to = defaults.integer(forKey: batchToKey)
        let selected: [IsaCloudChangelogRelease]
        if firstRun || from == 0 {
            //only the newest release up to the current build
            selected = releases.first { $0.build <= to }.map { [$0] } ?? []
        } else {
            selected = releases.filter { $0.build > from && $0.build <= to }
        }
        let readBuild = defaults.integer(forKey: readBuildKey)
        let archivedBuild = defaults.integer(forKey: archivedBuildKey)
        return Batch(
            releases: selected,
            toBuild: to,
            isUnread: readBuild < to,
            isArchived: archivedBuild >= to
        )
    }

    @objc static func markRead() {
        let to = batch().toBuild
        guard to > 0, UserDefaults.standard.integer(forKey: readBuildKey) != to else {
            return
        }
        UserDefaults.standard.set(to, forKey: readBuildKey)
        postChanged()
    }

    //hides the item in the chats list until the next update (the next build brings it back)
    @objc static func archive() {
        let to = batch().toBuild
        guard to > 0 else {
            return
        }
        UserDefaults.standard.set(to, forKey: archivedBuildKey)
        postChanged()
    }

    @objc static func unarchive() {
        UserDefaults.standard.set(0, forKey: archivedBuildKey)
        postChanged()
    }

    @objc static var isVisible: Bool {
        return batch().isVisible
    }

    @objc static var isUnread: Bool {
        return batch().isUnread
    }

    //the preview line of the chats list item: "See what changed in build 104", "... in builds 102, 103, 104" or "... in builds 100 to 104"
    @objc static var previewText: String {
        let builds = batch().releases.map { $0.build }.sorted()
        switch builds.count {
        case 0:
            return ""
        case 1:
            return String(format: NSLocalizedString("See what changed in build %@", comment: ""), String(builds[0]))
        case 2...4:
            let list = builds.map { String($0) }.joined(separator: ", ")
            return String(format: NSLocalizedString("See what changed in builds %@", comment: ""), list)
        default:
            return String(format: NSLocalizedString("See what changed in builds %@ to %@", comment: ""), String(builds[0]), String(builds[builds.count - 1]))
        }
    }

    //date of the newest release of the batch
    @objc static var latestDate: String? {
        return batch().releases.first?.date
    }

    private static func postChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }
}

//the news screen: the batch (showAll false, from the chats list) or every release (showAll true, from Settings → About)
struct IsaCloudChangelogView: View {
    let showAll: Bool
    @State private var batch = IsaCloudChangelog.batch()

    private static let allNewsURL = URL(string: "https://github.com/isaitgirl/isaCloud-iOS/blob/isaCloud/CHANGELOG-USERS.md")

    private var releases: [IsaCloudChangelogRelease] {
        return showAll ? IsaCloudChangelog.all() : batch.releases
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                //isaCloud: on top, so it is seen without scrolling through every release (Settings → About shows all of them)
                if !batch.isVisible && !batch.releases.isEmpty {
                    Button {
                        IsaCloudChangelog.unarchive()
                    } label: {
                        Text(NSLocalizedString("Show in chats list", comment: ""))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("isaCloudPink"))
                }
                if releases.isEmpty {
                    Text(NSLocalizedString("No news for now.", comment: ""))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
                ForEach(Array(releases.enumerated()), id: \.offset) { _, release in
                    releaseView(release)
                }
                if let url = IsaCloudChangelogView.allNewsURL {
                    Link(destination: url) {
                        Text(NSLocalizedString("See all news", comment: ""))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(NSLocalizedString("isaCloud news", comment: ""))
        .onAppear {
            IsaCloudChangelog.markRead()
            batch = IsaCloudChangelog.batch()
        }
        .onReceive(NotificationCenter.default.publisher(for: IsaCloudChangelog.changedNotification)) { _ in
            batch = IsaCloudChangelog.batch()
        }
    }

    private func releaseView(_ release: IsaCloudChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(releaseTitle(release))
                .font(.headline)
            ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: section.title)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(Color("isaCloudPink"))
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        itemText(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func releaseTitle(_ release: IsaCloudChangelogRelease) -> String {
        let title = String(format: NSLocalizedString("Build %@", comment: ""), String(release.build))
        if let date = release.date {
            return title + " · " + date
        }
        return title
    }

    //the items are short texts with emoji and, at most, simple markdown (**bold**)
    private func itemText(_ item: String) -> Text {
        if let attributed = try? AttributedString(markdown: item, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(verbatim: item)
    }
}

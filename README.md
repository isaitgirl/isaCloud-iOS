<h1 align="center">isaCloud for iOS</h1>

<p align="center">
  <a href="README.md"><strong>English</strong></a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a>
</p>

<p align="center">
  <img src="docs/logo-isacloud-im-liquidglass-1024.png" width="140" alt="isaCloud for iOS">
</p>

<p align="center"><strong>Instant messaging with the isaCloud touch.</strong><br>
A free, beautiful XMPP client for iPhone, built on top of Monal.</p>

<p align="center">
  <a href="https://isacloud.com.br">isacloud.com.br</a> ·
  <a href="https://github.com/isaitgirl/isaCloud-iOS">Source on GitHub</a> ·
  <a href="CHANGELOG-USERS.md">What's new</a> ·
  <a href="CHANGELOG.md">Technical changelog</a>
</p>

## About

**isaCloud for iOS** is a fork of [Monal](https://monal-im.org), the open-source XMPP client for
iOS and macOS by Thilo Molitor and contributors. It uses the open **XMPP** protocol, so you can talk
to anyone on any federated server — including your own. It is the iPhone sibling of
**isaCloud Messenger** for Android, which is built on Conversations.

The app is distributed under the **BSD 2-Clause** license of Monal (see [LICENSE](LICENSE)). The
source of this fork lives on [GitHub](https://github.com/isaitgirl/isaCloud-iOS).

## Upstream synchronization

isaCloud for iOS tracks Monal and stays in sync with upstream. The working branch is `isaCloud`;
`develop` is kept only as a landing point for Monal commits. Changes in this fork are meant to be
**visual and usability** improvements plus Android parity, and the core of Monal is preserved to
keep future merges cheap. Upstream updates continue to be merged.

## Features

What isaCloud adds on top of Monal (the full list is in the [ROADMAP](ROADMAP.md), in Portuguese):

- 1:1 chats, private groups, and public channels, with a **channel directory** per server.
- End-to-end encryption with **OMEMO**, and a clear padlock and warning when a message would go
  out unencrypted.
- **Stickers** (XEP-0449), a **GIF** picker, and quick reactions, with a **list of who reacted**.
- **Stickers made by you**: crop, add text, save, and favorite.
- **Quote with thumbnail** for photos, GIFs, and stickers, and **swipe to reply**.
- **Select and forward** messages (text and media), plus sharing from other iOS apps.
- Photos and videos from the **camera** or gallery, **photo compression** on send, files, and
  location.
- **Search** by name and by message content (full-text, with jump to the message).
- Open groups and channels at the **first unread message**, with a "read up to here" line.
- **Per-room nickname**, **@ mentions** with autocomplete, and **hats** (XEP-0317).
- Conversation filters (Unread, Contacts, Groups, Channels), account avatar, and **multiple
  accounts**, with the account shown on each conversation.
- Local archiving synchronized with Android, and **private messages in channels**.
- Message bubble colors and text size to your taste, under Settings → Appearance.
- Adapted for iOS 18 to iOS 27, including Liquid Glass.

## Installation

isaCloud for iOS is distributed through **TestFlight** to testers invited by the maintainer. It is
not on the App Store yet. Requires an **iPhone with iOS 18** or newer.

## Build

Requirements:

- A Mac with **Xcode 27.1**;
- **Rust** (the `LibMonalRustSwiftBridge` package is generated from `rust/`);
- **CocoaPods** (`pod install` inside `Monal/`);
- For the GIF picker, a Giphy key in `isaCloud/local/giphy-api-key.txt` (git-ignored).

```bash
git clone --recurse-submodules git@github.com:isaitgirl/isaCloud-iOS.git
cd isaCloud-iOS && git switch isaCloud
cd Monal && pod install
open Monal.xcworkspace        # scheme "Monal"
```

Build and test on both ends of the supported range (iOS 18 and iOS 27). Common build problems
(Rust, `Package.resolved`, SQLite with FTS5, Pods, signing) are covered in
[docs/build-e-branches.md](docs/build-e-branches.md), and publishing in
[docs/publicacao-testflight.md](docs/publicacao-testflight.md).

isaCloud strings live in `isaCloud/localization/<language>.lproj/Localizable.strings` and are
merged on top of Monal's (managed on [Weblate](https://hosted.weblate.org/engage/monal/)) at build
time, so the isaCloud translation wins.

## Security and privacy

- **OMEMO** for encrypted conversations.
- No ad tracking and no analytics service. On-device metrics stay on the device unless you export
  them.
- Push notifications go through the isaCloud push service.

Found a security issue? See [SECURITY.md](SECURITY.md).

## Credits

- **Monal** — Thilo Molitor and contributors. This fork would not exist without their work.
  The upstream [wiki](https://github.com/monal-im/Monal/wiki) and
  [supported XEPs](https://monal-im.org/install/#implemented-xeps) still apply to the app's core.
- **ExyteChat** — the chat view, used through a small [fork](docs/exytechat-fork.md).
- **isaCloud for iOS** — maintained by Isadora / [isacloud.com.br](https://isacloud.com.br).
- License: **BSD 2-Clause** — see [LICENSE](LICENSE). Contributions must stay compatible with it
  (**no GPL**).

## Contributing

Found a bug or have an idea? Open an issue on
[GitHub](https://github.com/isaitgirl/isaCloud-iOS/issues). Every change starts on a new branch
from `isaCloud` and comes back through a pull request to `isaCloud`; see the
[Code of Conduct](CODE_OF_CONDUCT.md). This fork does not send pull requests to the Monal
upstream; changes stay here.

The changelog and internal docs are currently in Portuguese.

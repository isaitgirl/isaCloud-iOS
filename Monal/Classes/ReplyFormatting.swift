//
//  ReplyFormatting.swift
//  Monal
//
//  isaCloud: the lookups of a reply (XEP-0461) that xmpp sendMessage: adds to the stanza: the `to` of the reply, and whether the reply
//  also keeps the older element of a photo, GIF or sticker reply (urn:isacloud:quote:0). The original message is found in the database by
//  the id the reply carries. Only ids and positions go in the stanza, never content (docs/contrato-reply-xep0461.md).
//

import Foundation

@objc(ISACloudReply) public final class ISACloudReply: NSObject {
    /// the original of a reply, found in its chat by the id the reply carries (nil when it is not in the database)
    private static func quotedMessage(quotedId: String, chatJid: String, accountID: NSNumber) -> MLMessage? {
        guard let historyId = DataLayer.sharedInstance().historyId(ofQuotedMessageId: quotedId, inChat: chatJid, forAccount: accountID) else {
            return nil
        }
        let quoted: MLMessage? = MLMessage.createMessage(fromHistoryID: historyId)
        return quoted
    }

    /// the `to` of the reply (a SHOULD in XEP-0461): the author of the original. In a group that is the room with the nick of the author
    /// ("room/nick"); in a one-to-one chat it is the other person's JID, or our own JID when the original is ours. Nil when the original is
    /// not in the database or its author is unknown: the reply then goes without `to`, and the receiver finds the original by its id.
    @objc(replyToForQuotedId:inChat:forAccount:)
    public static func replyTo(quotedId: String, chatJid: String, accountID: NSNumber) -> String? {
        guard let quoted = quotedMessage(quotedId: quotedId, chatJid: chatJid, accountID: accountID) else {
            return nil
        }
        //actualFrom is the room nick of the author in a group, and our own JID in a one-to-one chat when the message is ours
        let author = quoted.actualFrom ?? ""
        if quoted.isMuc {
            return author.isEmpty ? nil : chatJid + "/" + author
        }
        if quoted.inbound {
            return chatJid
        }
        return author.isEmpty ? nil : author
    }

    /// whether the original is a photo, a GIF or a sticker: only a reply to one of them keeps the element urn:isacloud:quote:0, which the
    /// apps that do not read urn:xmpp:reply:0 yet use to show the thumbnail
    @objc(quotesThumbnailForQuotedId:inChat:forAccount:)
    public static func quotesThumbnail(quotedId: String, chatJid: String, accountID: NSNumber) -> Bool {
        guard let quoted = quotedMessage(quotedId: quotedId, chatJid: chatJid, accountID: accountID),
              quoted.messageType == kMessageTypeFiletransfer, !quoted.retracted else {
            return false
        }
        let info: MLFiletransferInfo? = MLFiletransferInfo.createFiletransferInfo(for: quoted)
        let isGif = (info?.mimeType as String?) == "image/gif"
        return quoted.isSticker || isGif || (info?.isImage ?? false)
    }

    /// the end of the fallback of a reply whose body starts with the quote, nil when it does not (see QuoteFormatting.replyFallbackEnd)
    @objc(fallbackEndForBody:)
    public static func fallbackEnd(forBody body: String) -> NSNumber? {
        return QuoteFormatting.replyFallbackEnd(body: body).map { NSNumber(value: $0) }
    }
}

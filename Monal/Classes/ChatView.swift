//
//  ChatView.swift
//  Monal
//
//  Created by Thilo Molitor on 05.09.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import FrameUp
import ExyteChat
import ExyteMediaPicker
import CoreLocation
typealias ExyteChatView = ExyteChat.ChatView


/*
struct MonalViewDefaults: ViewModifier {
    @Binding public var alertPrompt: AlertPrompt?
    
    public func body(content: Content) -> some View {
        content
            //TODO: modernize alert prompt usage in all other swiftui files to be in line with this implementation here
            //TODO: e.g. non-hardcoded dismiss button text and usage of optionalMappedToBool and dismissCallback
            .alert(isPresented: $alertPrompt.optionalMappedToBool()) {
                let callback = alertPrompt!.dismissCallback
                return Alert(title: alertPrompt!.title, message: alertPrompt!.message, dismissButton:.default(alertPrompt!.dismissLabel, action: {
                    if let callback = callback {
                        callback()
                    }
                }))
            }
    }
}

private struct AssociatedMonalViewKeys {
    static var AlertPromptKey = "ml_alertPromptKey"
}

extension View {
    func addMonalViewDefaults() -> some View {
        //see https://medium.com/@marcosantadev/stored-properties-in-swift-extensions-615d4c5a9a58
        modifier(MonalViewDefaults(alertPrompt:Binding(
            get: {
                print("Getter called...")
                return AlertPrompt(
                    title: Text("No OMEMO keys found"),
                    message: Text("This contact may not support OMEMO encrypted messages. Please try to enable encryption again in a few seconds, if you think this is wrong."),
                    dismissLabel: Text("Disable Encryption")
                )
//                 guard let value = objc_getAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey) as? AlertPrompt else {
//                     return nil
//                 }
//                 return value
            },
            set: {
                print("Setting: \(String(describing:$0))")
                if let value = $0 {
                    objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, value, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                } else {
                    objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, nil, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            }
        )))
    }
}

protocol MonalView: View {
    associatedtype Content: View
    @ViewBuilder var content: Self.Content { get }
}

extension MonalView {
    var body: some View {
        content
            .addMonalViewDefaults()
    }
    
    func showAlert(_ prompt: AlertPrompt) {
        objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, prompt, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        content.id(UUID())
    }
}
*/

class ChatViewDefaultsDB: ObservableObject {
    @defaultsDB("SendLastChatState")
    var sendLastChatState: Bool

    @defaultsDB("showKeyboardOnChatOpen")
    var showKeyboardOnChatOpen: Bool

    @defaultsDB("ShowURLPreview")
    var showURLPreview: Bool

    @defaultsDB("ShowGeoLocation")
    var showGeoLocation: Bool

    //isaCloud: reactions as round bubbles over the top corner of the message bubble instead of capsules in its footer
    //(Settings > User Interface > Appearance)
    @defaultsDB("reactionsAboveMessages")
    var reactionsAboveMessages: Bool

    //isaCloud: text size inside the chats, a step relative to the system text size (see ChatTextSize)
    @defaultsDB("chatTextSizeStep")
    var chatTextSizeStep: Int
}

/// isaCloud: the text size inside the chats (bubbles, names, quotes, reactions, time, input bar), as a step relative to the
/// system text size: 0 ("Padrão") is the size the system has, -1 one category smaller, 3 three categories bigger.
/// The steps stop at the smallest and the biggest category the system has.
enum ChatTextSize {
    /// the steps offered in Settings > User Interface > Appearance, in order
    static let steps = [-1, 0, 1, 2, 3]

    static func dynamicTypeSize(system: DynamicTypeSize, step: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        let index = (all.firstIndex(of: system) ?? 3) + step
        return all[min(max(index, 0), all.count - 1)]
    }

    /// the font of the text of a message (15 pt at the system size, like the library's default)
    static func messageFont(system: DynamicTypeSize, step: Int) -> UIFont {
        scaledFont(15, system: system, step: step)
    }

    /// the font of the time under a message (10 pt at the system size, like the library's default)
    static func timeFont(system: DynamicTypeSize, step: Int) -> UIFont {
        scaledFont(10, system: system, step: step)
    }

    private static func scaledFont(_ size: CGFloat, system: DynamicTypeSize, step: Int) -> UIFont {
        let category = contentSizeCategory(dynamicTypeSize(system: system, step: step))
        return UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: size), compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }

    private static func contentSizeCategory(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

struct ChatView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize      //isaCloud: the system text size, see ChatTextSize
    @ObservedObject var chatViewDefaultsDB = ChatViewDefaultsDB()
    
    private var account: xmpp
    @StateObject var voipProcessor: ObservableKVOWrapper<MLVoIPProcessor>
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var selectedContactForContactDetails: ObservableKVOWrapper<MLContact>?
    @State private var alertPrompt: AlertPrompt?
    @State private var confirmationPrompt: ConfirmationPrompt?
    @State private var showDisableEncryptionDialog = false        //isaCloud: anchored to the lock button, see the toolbar
    @StateObject private var overlay = LoadingOverlayState()
    @State private var moderationReason = "Spam"
    @State private var isEditingReason = false
    @State private var blockOnModeration = true
    @State private var messageToModerate: MLMessage?
    // The initial value must not be nil. Otherwise background image rendering won't work correctly.
    // The actual initialization happens in onAppear. It can safely be nil then.
    @State private var backgroundImage: UIImage? = UIImage(systemName: "circle")
    @State var messages: [ChatViewMessage] = []
    /// isaCloud: saves and sends the text messages one after the other, in the order they were sent (see sendTextAtOnce)
    private static let sendQueue = DispatchQueue(label: "im.monal.chatview.send", qos: .userInitiated)
    @State var queuedNewMessages: [ChatViewMessage] = []
    @State private var mucPersonCount = 0      //isaCloud: members of a group / participants of a channel, shown under the name
    @State private var voiceRequests: [[String: AnyObject]] = []
    @State private var isLoadingMamHistory = false
    @State private var messageInsertionTimer: Timer?
    @State private var ownRole = kMucRoleNone
    @StateObject private var inputModel = ChatInputModel()
    @State private var showMediaPicker = false
    @State private var showGifPicker = false
    @State private var showLocationPicker = false
    @State private var showFileImporter = false
    @State private var editSaveClosure: ((String) -> Void)?
    @State private var isTyping = false
    @State private var typingTimer: Timer?

    /// isaCloud: what the picker of destinations forwards: a text, or a file (its message, read again from the database before it is sent)
    private enum ForwardedItem {
        case text(String)
        case file(messageDBId: NSNumber, message: MLMessage)
    }
    @State private var messageToForward: ForwardedItem?       //isaCloud: what is being forwarded (the picker of destinations is shown while it is set)
    //isaCloud: opened from the search in the messages: the chat shows this message in the middle of the screen (nil: the newest ones as always)
    @State private var jumpToHistoryId: NSNumber?
    @State private var jumpScrollParams: ScrollToParams?
    /// a chat is only opened at a message if it takes at most this many messages to get there from the newest ones
    static let maxMessagesToJumpOver = 3000

    init(contact: ObservableKVOWrapper<MLContact>, jumpToHistoryId: NSNumber? = nil) {
        _jumpToHistoryId = State(wrappedValue: jumpToHistoryId)
        _contact = StateObject(wrappedValue:contact)
        _voipProcessor = StateObject(wrappedValue:ObservableKVOWrapper((UIApplication.shared.delegate as! MonalAppDelegate).voipProcessor!))
        account = contact.obj.account!
    }

    enum MessageAction: MessageMenuAction {
        case copy, quote, forward, edit, retract, moderate, delete, resend

        func title() -> String {
            switch self {
                case .copy:
                    NSLocalizedString("Copy", comment: "message menu")
                case .quote:
                    NSLocalizedString("Reply", comment: "message menu: quote the message in the input")
                case .forward:
                    NSLocalizedString("Forward…", comment: "message menu: send the message to other chats")
                case .edit:
                    NSLocalizedString("Edit", comment: "message menu")
                case .retract:
                    NSLocalizedString("Retract", comment: "message menu")
                case .moderate:
                    NSLocalizedString("Moderate", comment: "message menu: moderator removes a message in a group or channel")
                case .delete:
                    NSLocalizedString("Delete Locally", comment: "message menu: removes the message from this device only")
                case .resend:
                    NSLocalizedString("Resend", comment: "message menu: sends a message that failed again")
            }
        }

        func icon() -> Image {
            switch self {
                case .copy:
                    Image(systemName: "doc.on.doc")
                case .quote:
                    Image(systemName: "arrowshape.turn.up.left")
                case .forward:
                    Image(systemName: "arrowshape.turn.up.right")
                case .edit:
                    if #available(iOS 18.0, macCatalyst 18.0, *) {
                        Image(systemName: "bubble.and.pencil")
                    } else {
                        Image(systemName: "square.and.pencil")
                    }
                case .retract, .moderate:
                    Image(systemName: "arrow.uturn.backward.circle")
                case .delete:
                    Image(systemName: "trash")
                case .resend:
                    Image(systemName: "paperplane")
            }
        }

        static func menuItems(for message: ExyteChat.Message) -> [MessageAction] {
            //isaCloud: a message on its way is not saved yet, so only its text can be copied (no edit, retract, forward, quote or resend)
            if (message as! ChatViewMessage).isPending {
                return message.hasText ? [.copy] : []
            }
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            let contact = mlMessage.chatContact
            let account = contact.account!
            if mlMessage.retracted {
                return [.delete]
            }
            if case .error = message.status {
                return [.resend, .delete]
            }
            var availableActions: [MessageAction] = []
            if message.hasText {
                availableActions.append(.copy)
            }
            //isaCloud: a message without text (photo, video, audio, file, location) can be replied to as well, quoting a label
            //(TEMPORARY, until Monal implements XEP-0461: see ChatViewMessage.replyQuoteText)
            if (message as! ChatViewMessage).replyQuoteText != nil {
                availableActions.append(.quote)
            }

            //isaCloud: forwarding (texts and files)
            var hasSendError = false
            if case .error = message.status {
                hasSendError = true
            }
            if (mlMessage.messageType == kMessageTypeText || mlMessage.messageType == kMessageTypeUrl)
                && MessageForward.canForward(text: mlMessage.messageText, isRetracted: mlMessage.retracted, hasSendError: hasSendError) {
                availableActions.append(.forward)
            } else if mlMessage.messageType == kMessageTypeFiletransfer
                && MessageForward.canForwardFile(isRetracted: mlMessage.retracted, hasSendError: hasSendError) {
                availableActions.append(.forward)
            }

            if !mlMessage.inbound && DataLayer.sharedInstance().checkLMCEligible(mlMessage.messageDBId, encrypted: mlMessage.encrypted || contact.isEncrypted, historyBaseID: nil) {
                availableActions.append(.edit)
            }

            if !mlMessage.inbound && (!mlMessage.isMuc || mlMessage.stanzaId != nil) {
                availableActions.append(.retract)
            }
            else if mlMessage.isMuc && mlMessage.stanzaId != nil && kMucRoleModerator.isEqual(DataLayer.sharedInstance().getOwnRole(inGroupOrChannel: contact)) && account.mucProcessor.getRoomFeatures(forMuc: contact.contactJid).contains("urn:xmpp:message-moderate:1") {
                availableActions.append(.moderate)
            } else {
                availableActions.append(.delete)
            }

            return availableActions
        }
    }

    private func showCannotEncryptAlert(_ show: Bool) {
        if show {
            DDLogVerbose("Showing cannot encrypt alert...")
            alertPrompt = AlertPrompt(
                title: Text("Encryption Not Supported"),
                message: Text("This contact does not appear to have any devices that support encryption, please try again later if you think this is wrong."),
                dismissLabel: Text("Close")
            )
        } else {
            alertPrompt = nil
        }
    }
    
    private func showShouldDisableEncryptionConfirmation(_ show: Bool) {
        //isaCloud: a dialog attached to the lock button itself instead of the root action sheet: on iOS 26+ the root one
        //came up as a popover on the navigation bar, cut down to one line
        DDLogVerbose("Showing should disable encryption confirmation: \(show)")
        showDisableEncryptionDialog = show
    }
    
    private func checkOmemoSupport(withAlert showWarning: Bool) {
#if !DISABLE_OMEMO
        if DataLayer.sharedInstance().isAccountEnabled(contact.accountID) {
            var omemoDeviceForContactFound = false
            if !contact.isMuc {
                omemoDeviceForContactFound = account.omemo.knownDevices(forAddressName:contact.contactJid).count > 0
            } else {
                omemoDeviceForContactFound = false
                for participant in DataLayer.sharedInstance().getMembersAndParticipants(ofMuc:contact.contactJid, forAccountID:contact.accountID) {
                    if let participant_jid = participant["participant_jid"] as? String {
                        omemoDeviceForContactFound = omemoDeviceForContactFound || account.omemo.knownDevices(forAddressName:participant_jid).count > 0
                    } else if let participant_jid = participant["member_jid"] as? String {
                        omemoDeviceForContactFound = omemoDeviceForContactFound || account.omemo.knownDevices(forAddressName:participant_jid).count > 0
                    }
                    if omemoDeviceForContactFound {
                        break
                    }
                }
            }
            hideLoadingOverlay(overlay)
            if !omemoDeviceForContactFound && contact.isEncrypted {
                if HelperTools.isContactBlacklistedForEncryption(contact.obj) {
                    // this contact was blacklisted for encryption
                    // --> disable it
                    contact.obj.toggleEncryption(false)
                } else if contact.isMuc && contact.mucType != kMucTypeGroup {
                    // a channel type muc has OMEMO encryption enabled, but channels don't support encryption
                    // --> warn user about this
                    DDLogWarn("Showing alert because omemo is suddenly impossible since group changed to channel: \(self.contact)");
                    confirmationPrompt = ConfirmationPrompt(
                        title: Text("Group suddenly changed to public channel!"),
                        message: Text("This chat suddenly changed from an encrypted private group to an unencrypted public channel! Please contact the administrator of that group/channel if you think this is wrong."),
                        buttons: [
                            .default(
                                Text("Keep encryption enabled"),
                                //don't change anything, just close the alert
                                action: { }
                            ),
                            .destructive(
                                Text("Disable encryption. This is dangerous!"),
                                action: {
                                    contact.obj.toggleEncryption(false)
                                }
                            )
                        ]
                    )
                } else if !contact.isMuc || (contact.isMuc && contact.mucType == kMucTypeGroup) {
                    if showWarning {
                        DDLogWarn("Showing omemo not supported alert for: \(self.contact)")
                        alertPrompt = AlertPrompt(
                            title: Text("No OMEMO keys found"),
                            message: Text("This contact may not support OMEMO encrypted messages. Please try to enable encryption again in a few seconds, if you think this is wrong."),
                            dismissLabel: Text("Disable Encryption")
                        ) {
                            contact.obj.toggleEncryption(false)
                        }
                    } else {
                        DDLogInfo("Trying to fetch omemo keys for: \(self.contact)")

                        // we won't do this twice, because the user won't be able to change isEncrypted to YES,
                        // unless we have omemo devices for that contact
                        showPromisingLoadingOverlay(overlay, headlineView:Text("Loading OMEMO keys"), descriptionView:Text("")).done {
                            // request omemo devicelist
                            account.omemo.subscribeAndFetchDevicelistIfNoSessionExists(forJid:contact.contactJid)
                        }
                    }
                }
            }
        }
#endif
    }

    private func loadChatBackground() {
        var background: UIImage? = MLImageManager.sharedInstance().getBackgroundFor(self.contact.obj)
        // Use the default background if this contact does not have its own
        if background == nil {
            background = MLImageManager.sharedInstance().getBackgroundFor(nil)
        }
        self.backgroundImage = background
    }

    private func sendChatState(isTyping: Bool) {
        // Do not send when the user disabled the feature
        guard chatViewDefaultsDB.sendLastChatState else {
            return
        }

        // Changed state? --> send typing notification
        if isTyping != self.isTyping {
            DDLogVerbose("Sending chatstate isTyping=\(isTyping)")
            MLXMPPManager.sharedInstance().sendChatState(isTyping, to:self.contact.obj)
        }

        // Set internal state
        self.isTyping = isTyping

        // Cancel old timer if existing
        typingTimer?.invalidate()

        // Start new timer if we are currently typing
        if isTyping {
            typingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                // No typing interaction in 5 seconds? --> send out active chatstate (e.g. typing ended)
                if self.isTyping {
                    self.isTyping = false
                    DDLogVerbose("Sending chatstate isTyping=false");
                    MLXMPPManager.sharedInstance().sendChatState(false, to:self.contact.obj)
                }
            }
        }
    }

    private func findOldestStanzaId() -> String? {
        //not all messages in history db have a stanzaId (messages sent by this monal instance won't have one for example)
        //--> search for the oldest message having a stanzaId and use that one
        for msg in self.messages {
            if msg.innerMessage.obj.stanzaId != nil {
                DDLogVerbose("Found oldest stanzaId in currently displayed messages: \(String(describing:msg.innerMessage.obj.stanzaId))")
                return msg.innerMessage.stanzaId
            }
        }

        //history database for this contact is completely empty, use global last stanza id for this mam archive
        if self.contact.isMuc {
            return DataLayer.sharedInstance().lastStanzaId(forMuc:self.contact.contactJid, andAccount:self.account.accountID)
        }
        else {
            return DataLayer.sharedInstance().lastStanzaId(forAccount:self.account.accountID);
        }
    }

    /// isaCloud: new messages reach the list in batches (see the ExyteChat issue below)
    private func enqueueNewMessages(_ newMessages: [ChatViewMessage]) {
        // Insert new messages in batches to work around https://github.com/exyte/Chat/issues/223
        //isaCloud: a message that is already shown (or queued) is not added twice: the history loaded when the chat opens and the notice of a
        //new message can both carry the same one, and ExyteChat aborts the app when two messages have the same id
        var knownIds = Set(messages.compactMap { $0.historyId })
        knownIds.formUnion(queuedNewMessages.map { $0.innerMessage.obj.messageDBId })
        queuedNewMessages.append(contentsOf: newMessages.filter { !knownIds.contains($0.innerMessage.obj.messageDBId) })
        guard !queuedNewMessages.isEmpty else {
            return
        }
        if messageInsertionTimer == nil {
            messageInsertionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                //isaCloud: a message of a day not shown yet and one of a day already shown must not reach the list in the same
                //table update (ExyteChat numbers the sections wrong then and UIKit throws), so the first ones go in a little later
                let calendar = Calendar.current
                let shownDays = Set(messages.map { calendar.startOfDay(for: $0.createdAt) })
                let batch = ChatMessageBatching.split(queuedNewMessages, shownDays: shownDays) { calendar.startOfDay(for: $0.createdAt) }
                queuedNewMessages.removeAll(keepingCapacity: true)
                messageInsertionTimer = nil
                messages.append(contentsOf: batch.shownDays.isEmpty ? batch.newDays : batch.shownDays)
                if !batch.shownDays.isEmpty && !batch.newDays.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        messages.append(contentsOf: batch.newDays)
                    }
                }
            }
            messageInsertionTimer?.tolerance = 0.04
        }
    }

    /// isaCloud: messages that were written to the database without this view hearing about them: the notification extension
    /// (another process) saves the messages of a push while the app is in the background, so coming back to a chat that was left
    /// open showed the old state. Called when the app comes back to the foreground.
    private func loadMissedMessages() {
        guard !isLoadingMamHistory else {
            return
        }
        var knownIds = Set(messages.compactMap { $0.historyId })
        knownIds.formUnion(queuedNewMessages.map { $0.innerMessage.obj.messageDBId })
        let latest = DataLayer.sharedInstance().messages(forContact: contact.contactJid, forAccount: contact.accountID) as? [MLMessage] ?? []
        let missed = latest.filter { !knownIds.contains($0.messageDBId) }
        if !missed.isEmpty {
            DDLogVerbose("Adding \(missed.count) messages that were saved while the chat view was not updating")
            enqueueNewMessages(missed.map { ChatViewMessage($0) })
        }
    }

    private func loadHistory() {
        guard !self.isLoadingMamHistory else {
            DDLogDebug("Not going to load more history because a backscrolling mam query is ongoing for this chat")
            // Don't allow concurrent backscrolling mam fetches.
            // And don't allow loading history from the DB while an mam query is ongoing;
            // this prevents potential message duplication: if a DB history fetch is triggered after the mam query
            // has written some messages to the DB but before it has returned the results, those messages will be
            // inserted twice in the ChatView.
            return
        }
        var beforeId: NSNumber? = nil
        if !messages.isEmpty {
            //isaCloud: the oldest message that is saved (a message on its way has no history id); nil loads the newest ones
            beforeId = messages.first(where: { !$0.isPending })?.historyId
        }
        let oldMessages: [ChatViewMessage] = (DataLayer.sharedInstance().messages(forContact:contact.contactJid, forAccount:contact.accountID, beforeMsgHistoryID:beforeId) as! [MLMessage]).map {ChatViewMessage($0)}
        //insert what we got from the db
        if !oldMessages.isEmpty {
            messages.insert(contentsOf: oldMessages, at:0)
        }

        // if we didn't get enough (or any) messages from the DB, try to get some from MAM
        if oldMessages.count < kMonalBackscrollingMsgCount && !contact.hasReachedMamArchiveTop {
            self.isLoadingMamHistory = true

            guard let oldestStanzaId = self.findOldestStanzaId() else {
                DDLogError("Couldn't find a stanzaId to perform a mam query with! (oldestStanzaId is nil)")
                return
            }
            // now try to load more (older) messages from mam
            DDLogVerbose("Loading more messages from mam before stanzaId \(oldestStanzaId)")
            firstly {
                self.account.setMAMQueryMostRecentFor(self.contact.obj, before: oldestStanzaId)
            }
            .done { returnedMessages in
                let returnedMessages = returnedMessages as! [MLMessage]
                if returnedMessages.isEmpty {
                    DDLogVerbose("Reached the top of the mam archive for \(self.contact.obj.contactJid)")
                    // Don't block the main thread while writing to the db
                    DispatchQueue.global(qos: .default).async {
                        contact.obj.markReachedMamArchiveTop()
                    }
                } else {
                    DDLogVerbose("Got backscrolling mam response: \(returnedMessages.count) messages: \(String(describing:returnedMessages))")
                    // When backscrolling in 1-1 chats, the oldest stanzaId may not correspond to the earliest
                    // message we have, because messages we send don't have a stanzaId => There's a risk of
                    // getting duplicate messages in the messages array => we need to deduplicate.
                    self.messages = OrderedSet(returnedMessages.map {ChatViewMessage($0)} + self.messages).elements
                }
            }
            .catch { error in
                alertPrompt = AlertPrompt(
                    title: Text("Could not fetch messages"),
                    message: Text(error.localizedDescription),
                    dismissLabel: Text("Close")
                )
            }
            .finally {
                self.isLoadingMamHistory = false
            }
        }
    }

    /// isaCloud: sends the text to each destination as a message of ours, with the line that says it was forwarded
    private func forward(_ text: String?, to destinations: [MLContact]) {
        guard let text = text else {
            return
        }
        let body = MessageForward.body(forwarding: text, word: NSLocalizedString("Forwarded", comment: "label on top of a forwarded message: the symbol is put in front"))
        for destination in destinations {
            //a destination without a conversation yet (for example your own notes on another account) shows up in the list of chats
            DataLayer.sharedInstance().addActiveBuddies(destination.contactJid, forAccount: destination.accountID)
            if let sent = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: body, havingType: kMessageTypeText, toContact: destination, isEncrypted: destination.isEncrypted, uploadInfo: nil) {
                //the chat we are in shows it at once when it is one of the destinations
                if destination.isEqual(toContact: self.contact.obj) {
                    messages.append(ChatViewMessage(sent))
                }
            } else {
                DDLogError("Forward: could not send to \(destination)")
            }
        }
    }

    /// isaCloud: sends a file to each destination, one after the other. The file is downloaded once (if it is not on the device yet);
    /// a destination that fails is skipped and the others go on. The alert names the destinations that failed.
    private func forwardFile(_ messageDBId: NSNumber, _ message: MLMessage, to destinations: [MLContact]) async {
        showLoadingOverlay(overlay, headline: "Forwarding…")
        var failed: [MLContact] = []
        if let downloaded = await downloadForForwarding(messageDBId), let cacheURL = downloaded.fileInfo.fileURL {
            let filename = downloaded.fileInfo.filename
            //isaCloud: the emoji of the kind of file goes in the label, the same for every destination
            let emoji = MessageForward.mediaEmoji(isGif: downloaded.fileInfo.mimeType == "image/gif", isImage: downloaded.fileInfo.isImage, isVideo: downloaded.fileInfo.isVideo, isAudio: downloaded.fileInfo.isAudio)
            for destination in destinations {
                if !(await sendForwardedFile(to: destination, cacheURL: cacheURL, filename: filename, emoji: emoji)) {
                    failed.append(destination)
                }
            }
        } else {
            DDLogError("Forward: the file of \(message.messageId) could not be downloaded, nothing was forwarded")
            failed = destinations
        }
        hideLoadingOverlay(overlay)
        if !failed.isEmpty {
            alertPrompt = AlertPrompt(
                title: Text("Could not forward"),
                message: Text(failed.map { $0.contactDisplayName }.joined(separator: ", ")),
                dismissLabel: Text("Close")
            )
        }
    }

    /// isaCloud: the file of a message, downloaded now if it is not on the device yet; nil if that fails or takes longer than two minutes
    private func downloadForForwarding(_ messageDBId: NSNumber) async -> MLMessage? {
        //(the message may not be in the database anymore, so it is read as optional)
        let initial: MLMessage? = MLMessage.createMessage(fromHistoryID: messageDBId)
        guard let initial = initial else {
            return nil
        }
        if initial.fileInfo.downloadState == .complete {
            return initial
        }
        MLFiletransfer.downloadFile(forHistoryID: messageDBId)
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let updated: MLMessage? = MLMessage.createMessage(fromHistoryID: messageDBId)
            guard let updated = updated else {
                return nil
            }
            if updated.fileInfo.downloadState == .complete {
                return updated
            }
            //the download is over without the file: it failed (a failure posts no notice, so the list of transfers is asked)
            if !MLFiletransfer.isFileForHistoryId(inTransfer: messageDBId) {
                return nil
            }
        }
        return nil
    }

    /// isaCloud: uploads the file to the server of one destination and sends it there: the label line first, then the file.
    /// The file is copied under its own name first, because the upload names it after the copy. false if the destination was skipped.
    private func sendForwardedFile(to destination: MLContact, cacheURL: URL, filename: String, emoji: String) async -> Bool {
        guard let account = MLXMPPManager.sharedInstance().getEnabledAccount(forID: destination.accountID) else {
            DDLogError("Forward: no enabled account for a destination, skipping it")
            return false
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            let copy = folder.appendingPathComponent(filename)
            //(copying a big file must not block the screen)
            try await Task.detached {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: cacheURL, to: copy)
            }.value
            let (url, mimeType, size) = try await MLFiletransfer.uploadFile(copy, onAccount: account, withEncryption: destination.isEncrypted)
            //a destination without a conversation yet shows up in the list of chats
            DataLayer.sharedInstance().addActiveBuddies(destination.contactJid, forAccount: destination.accountID)
            //the label and the file go out one after the other, nothing in between
            let label = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: MessageForward.labelOnly(word: NSLocalizedString("Forwarded", comment: "label on top of a forwarded message: the symbol is put in front"), emoji: emoji), havingType: kMessageTypeText, toContact: destination, isEncrypted: destination.isEncrypted, uploadInfo: nil)
            let sent = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: url, havingType: kMessageTypeFiletransfer, toContact: destination, isEncrypted: destination.isEncrypted, uploadInfo: ["mimeType": mimeType, "size": size])
            //the chat we are in shows them at once when it is one of the destinations
            if destination.isEqual(toContact: self.contact.obj) {
                if let label = label {
                    messages.append(ChatViewMessage(label))
                }
                if let sent = sent {
                    messages.append(ChatViewMessage(sent))
                }
            }
            return sent != nil
        } catch {
            DDLogError("Forward: could not upload the file to a destination: \(error.localizedDescription)")
            return false
        }
    }

    /// isaCloud: opens the chat at the message found by the search: loads from the database everything between that message and what is shown,
    /// then scrolls to it (the list loads older messages in blocks, from the newest; this closes the gap at once)
    private func jumpToSearchedMessage() {
        guard let target = jumpToHistoryId else {
            return
        }
        jumpToHistoryId = nil
        let alreadyShown = messages.contains { $0.historyId == target }
        if alreadyShown {
            scrollToSearchedMessage(target)
            return
        }
        guard let oldestShown = messages.first(where: { !$0.isPending })?.historyId, target.intValue < oldestShown.intValue else {
            return
        }
        guard let missing = DataLayer.sharedInstance().messages(forContact: contact.contactJid, forAccount: contact.accountID, aroundMsgHistoryID: target, beforeMsgHistoryID: oldestShown, limit: UInt(ChatView.maxMessagesToJumpOver)) as? [MLMessage] else {
            DDLogWarn("Search: message \(target) is too far back (or gone) to open the chat there")
            return
        }
        //isaCloud: the links of the loaded messages are found in the background first (the detector is slow), so the list does not
        //have to find them on the main thread when it compares the messages; the result is kept in LinkCache
        DispatchQueue.global(qos: .userInitiated).async {
            for mlMessage in missing where !mlMessage.retracted && (mlMessage.messageType == kMessageTypeText || mlMessage.messageType == kMessageTypeUrl) {
                let text = mlMessage.messageText
                _ = ChatViewMessage.attributed(body: MessageForward.split(text)?.rest ?? text, linkColor: .white, isText: mlMessage.messageType == kMessageTypeText)
            }
            DispatchQueue.main.async {
                //(the list may have changed meanwhile: what is shown already is not inserted again, ExyteChat aborts on two messages with the same id)
                let shownIds = Set(messages.compactMap { $0.historyId })
                messages.insert(contentsOf: missing.filter { !shownIds.contains($0.messageDBId) }.map { ChatViewMessage($0) }, at: 0)
                scrollToSearchedMessage(target)
            }
        }
    }

    /// isaCloud: scrolls to a message already in the list (see jumpToSearchedMessage())
    private func scrollToSearchedMessage(_ target: NSNumber) {
        guard let message = messages.first(where: { $0.historyId == target }) else {
            return
        }
        //the list must have taken the new messages before it can scroll to one of them
        //(and once more a moment later: the first scroll goes by the estimated height of the rows, which are measured while the list is drawn)
        //(the second one has another offset: the list only scrolls when the parameters change)
        for (delay, offset) in [(0.4, 0.0), (1.2, 0.5)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                jumpScrollParams = ScrollToParams(messageID: message.id, position: .middle, offset: offset)
            }
        }
    }

    private func uploadAndSendFile(_ localFileURL: URL?) async {
        guard let localFileURL = localFileURL else {
            DDLogError("Couldn't get file location in order to upload it!")
            return
        }
        inputModel.isUploading = true
        do {
            let (url, mimeType, size) = try await MLFiletransfer.uploadFile(localFileURL, onAccount: self.account, withEncryption: self.contact.isEncrypted)
            await MainActor.run {
                guard let newMLMessage = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: url, havingType: kMessageTypeFiletransfer, toContact: self.contact.obj, isEncrypted: self.contact.isEncrypted, uploadInfo: ["mimeType": mimeType, "size": size]) else {
                    inputModel.isUploading = false
                    return
                }
                messages.append(ChatViewMessage(newMLMessage))
            }
        } catch {
            DDLogError("Couldn't upload file! error:  \(error.localizedDescription)")
            alertPrompt = AlertPrompt(
                title: Text("Could not upload file"),
                message: Text(error.localizedDescription),
                dismissLabel: Text("Close")
            )
        }
        inputModel.isUploading = false
    }

    /// isaCloud: the chat input bar (text, attachments, edit) rendered from inputModel
    private func makeInputBar() -> ChatInputBar {
        return ChatInputBar(
            model: inputModel,
            onSend: sendFromInputBar,
            onSaveEdit: saveEditFromInputBar,
            onCancelEdit: {
                inputModel.cancelEdit()
                editSaveClosure = nil
            },
            onAttachPhotos: { showMediaPicker = true },
            onAttachFile: { showFileImporter = true },
            onPasteImage: pasteImageFromClipboard,
            onSearchGif: { showGifPicker = true },
            onShareLocation: { showLocationPicker = true },
            onRemoveAttachment: { inputModel.removeAttachment(at: $0) },
            onSendRecording: { url in
                Task {
                    //isaCloud: the quote in the field is the reply the person was writing, and the audio is that reply: the quote goes
                    //first, marked with the microphone so the reader knows an audio follows, and the audio right after, in order (the
                    //server delivers and archives them in the order they arrive). The audio itself can not carry the quote: its body is
                    //the file address, and the database has no caption field (see docs/decisoes.md).
                    let draftText = inputModel.text
                    if !draftText.isEmpty {
                        let body = draftText.hasPrefix(">") ? draftText + "\n🎤" : draftText
                        inputModel.setText("")
                        sendTextAtOnce(body)
                        //the quote left the field: the stored draft has to go with it, or it comes back the next time the chat opens
                        DispatchQueue.global(qos: .userInitiated).async {
                            DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount: self.account.accountID, withComment: "")
                        }
                    }
                    await uploadAndSendFile(url)
                }
            },
            mentionCandidates: mentionNicks
        )
    }

    /// isaCloud: the nicks of the occupants online in this group or channel, without our own nick (for "@" suggestions)
    private func mentionNicks() -> [String] {
        guard contact.obj.isMuc else {
            return []
        }
        let ownNick = DataLayer.sharedInstance().ownNickNameforMuc(contact.obj.contactJid, forAccount: account.accountID)
        return DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: contact.obj.contactJid, forAccountID: account.accountID)
            .filter { ($0["online"] as? NSNumber)?.boolValue == true }
            .compactMap { $0["room_nick"] as? String }
            .filter { $0 != ownNick }
    }

    /// isaCloud: sends what the input holds: attachments first, then the text (same order as before)
    private func sendFromInputBar() {
        guard let draft = inputModel.send() else {
            return
        }
        if !draft.attachments.isEmpty {
            Task {
                for attachment in draft.attachments {
                    await uploadAndSendFile(attachment.url)
                }
            }
        }
        if !draft.text.isEmpty {
            sendTextAtOnce(draft.text)
        }
        sendChatState(isTyping: false)
        // Clear the draft to show the newly sent message in active chats
        DispatchQueue.global(qos: .userInitiated).async {
            DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount:self.account.accountID, withComment:"")
        }
    }

    /// isaCloud: a text message is in the chat the moment it is sent. It used to be saved and sent on the main thread first, and the main
    /// thread waits when the database is busy with other writes (a few seconds, now and then): the chat stood still and the message came late.
    /// Now a message that is on its way (the spinner takes the place of the check mark) is shown at once, saved and sent in the background,
    /// and swapped for the real one when that is done. The time of the message is still the time it was saved.
    private func sendTextAtOnce(_ text: String) {
        let destination = contact.obj
        let encrypted: Bool = contact.isEncrypted
        let pending = ChatViewMessage.pending(text: text, to: destination, ownJid: account.connectionProperties.identity.jid)
        messages.append(pending)
        ChatView.sendQueue.async {
            let sent = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: text, havingType: kMessageTypeText, toContact: destination, isEncrypted: encrypted, uploadInfo: nil)
            DispatchQueue.main.async {
                finishSending(pending, as: sent, text: text)
            }
        }
    }

    /// isaCloud: the message that was shown at once is swapped for the saved one; if it could not be saved, it goes away and its text goes back
    /// to the input (when that is empty), so nothing the person wrote is lost
    private func finishSending(_ pending: ChatViewMessage, as sent: MLMessage?, text: String) {
        guard messages.contains(where: { $0 === pending }) else {
            return
        }
        guard let sent else {
            messages.removeAll(where: { $0 === pending })
            if inputModel.text.isEmpty {
                inputModel.setText(text)
            }
            return
        }
        //the saved message may have reached the list by another way meanwhile (the list loads what the database has when the app comes
        //back, for example): keep one of it, ExyteChat aborts on two messages with the same id
        messages.removeAll(where: { $0 !== pending && $0.innerMessage.obj.messageDBId == sent.messageDBId })
        queuedNewMessages.removeAll(where: { $0.innerMessage.obj.messageDBId == sent.messageDBId })
        if let index = messages.firstIndex(where: { $0 === pending }) {
            //isaCloud: the message shown while it was on its way takes the saved one, and the list keeps the same object (and id): it only
            //reloads the row, it does not delete and insert another one (that made the chat jump)
            pending.adopt(sent)
        }
    }

    /// isaCloud: sends the place chosen on the map as a location message, as the other clients do
    private func sendLocation(_ coordinate: CLLocationCoordinate2D) {
        let messageText = ChatLocation.geoURI(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let newMLMessage = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: messageText, havingType: kMessageTypeGeo, toContact: self.contact.obj, isEncrypted: self.contact.isEncrypted, uploadInfo: nil) else {
            return
        }
        messages.append(ChatViewMessage(newMLMessage))
    }

    /// isaCloud: saves an edit of a sent message through the closure given by the message menu
    private func saveEditFromInputBar() {
        guard let saved = inputModel.saveEdit() else {
            return
        }
        editSaveClosure?(saved.text)
        editSaveClosure = nil
    }

    /// isaCloud: medias from the picker are copied to attachments; they are uploaded when sent
    private func addPickedMedias(_ medias: [(url: URL, isVideo: Bool)]) {
        for media in medias {
            let kind: ChatInputAttachment.Kind = media.isVideo ? .file : .image
            inputModel.addAttachment(ChatInputAttachment(kind: kind, url: media.url))
        }
    }

    /// isaCloud: the image on the clipboard becomes an image attachment, written to a temporary PNG like the picked photos
    private func pasteImageFromClipboard() {
        guard let image = UIPasteboard.general.image, let data = image.pngData() else {
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paste-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
        } catch {
            return
        }
        inputModel.addAttachment(ChatInputAttachment(kind: .image, url: url))
    }

    /// isaCloud: picked files are copied to a temporary folder, because the security scoped URL is only valid for a moment
    private func addFiles(_ result: Swift.Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copy = folder.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: copy)
                inputModel.addAttachment(ChatInputAttachment(kind: .file, url: copy))
            } catch {
                DDLogError("Could not copy the picked file: \(error)")
            }
        }
    }

    private var encryptionButtonDisabled: Bool {
        //disable encryption button on unsupported muc types
        (contact.isMuc && contact.mucType != kMucTypeGroup) ||
        //disable encryption button for special jids
        HelperTools.isContactBlacklistedForEncryption(contact.obj)
    }

    //isaCloud: group (end to end) and channel (in transit): the lock only tells the state, no action and no glass bubble to tap
    private var encryptionIndicator: some View {
        Group {
            if contact.mucType == kMucTypeGroup {
                Image(systemName: contact.isEncrypted ? "lock.fill" : "lock.open.fill")
                    .foregroundColor(contact.isEncrypted ? Color("isaCloudPink") : .red)
                    .accessibilityLabel(contact.isEncrypted ? Text("Messages are encrypted") : Text("Messages are NOT encrypted"))
            } else {
                //arrows to both sides with a small lock: encrypted on its way to the server and back
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color("isaCloudPink"))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color("isaCloudPink"))
                            .padding(1.5)
                            .background(Circle().fill(Color(UIColor.systemBackground)))
                            .offset(x: 5, y: 6)
                    }
                    .accessibilityLabel(Text("Messages are encrypted in transit"))
            }
        }
        //a tap on the empty bar makes the chat scroll to its first message: swallow it, the lock has no action
        .frame(minWidth: 36, minHeight: 36)
        .contentShape(Rectangle())
        .onTapGesture { }
    }
    
    @ToolbarContentBuilder
    private var encryptionIndicatorToolbarItem: some ToolbarContent {
        if contact.isMuc {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { encryptionIndicator }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { encryptionIndicator }
            }
        }
    }

    //isaCloud: the spinner of the history loading and of the upload is an item of its own without the glass bubble (iOS 26+): inside
    //the bubble of the buttons it made that bubble grow and shrink every time the spinner came and went
    @ToolbarContentBuilder
    private var loadingIndicatorToolbarItem: some ToolbarContent {
        if isLoadingMamHistory || inputModel.isUploading {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            }
        }
    }

    var body: some View {
        ExyteChatView(messages: messages, chatType: .conversation, replyMode: .quote, didSendMessage: { draft in
            if !draft.medias.isEmpty || draft.recording != nil || !draft.files.isEmpty {
                Task {
                    if draft.recording != nil {
                        await uploadAndSendFile(draft.recording!.url)
                    }
                    for media in draft.medias {
                        let localFileURL = await media.getURL()
                        await uploadAndSendFile(localFileURL)
                    }
                    for file in draft.files {
                        await uploadAndSendFile(file.localURL)
                    }
                }
            }
            if !draft.text.isEmpty {
                guard let newMLMessage = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: draft.text, havingType: kMessageTypeText, toContact: self.contact.obj, isEncrypted: self.contact.isEncrypted, uploadInfo: nil) else {
                    return
                }
                messages.append(ChatViewMessage(newMLMessage))
                sendChatState(isTyping: false)
                // Clear the draft to show the newly sent message in active chats
                DispatchQueue.global(qos: .userInitiated).async {
                    DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount:self.account.accountID, withComment:"")
                }
            }
            if let location = draft.staticLocation {
                let messageText = "geo:\(location.latitude),\(location.longitude)"
                guard let newMLMessage = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: messageText, havingType: kMessageTypeGeo, toContact: self.contact.obj, isEncrypted: self.contact.isEncrypted, uploadInfo: nil) else {
                    return
                }
                messages.append(ChatViewMessage(newMLMessage))
            }
        }, messageBuilder: { params in
            // GIFs are shown animated; the other messages keep the ExyteChat bubble
            if let gif = params.message.attachments.first(where: { $0.mimeType == "image/gif" }) {
                GifMessageBubble(
                    url: gif.full,
                    message: params.message,
                    user: params.message.user,
                    isCurrentUser: params.message.user.isCurrentUser,
                    showSender: contact.isMuc,
                    isLastOfSenderGroup: params.positionInGroup == .single || params.positionInGroup == .last,
                    showContextMenu: params.showContextMenuClosure,
                    onReactionsTap: params.showReactionDetailsClosure
                )
            } else if (params.message as! ChatViewMessage).isPending {
                //isaCloud: a message that is still on its way (not saved yet) does not react to touches: no menu, no actions
                params.defaultMessageView()
                    .allowsHitTesting(false)
            } else {
                params.defaultMessageView()
            }
        }, inputViewBuilder: { _ in
            //isaCloud: the field where a new message is typed keeps the system text size (the chat text size is for the messages)
            makeInputBar()
                .dynamicTypeSize(dynamicTypeSize)
        }, messageMenuAction: { (action: MessageAction, defaultActionClosure, message) in
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            let messageDBId = mlMessage.messageDBId
            switch action {
                case .copy:
                    defaultActionClosure(message, .copy)
                case .quote:
                    // the author is only needed where several people write: groups and channels
                    inputModel.quote(author: mlMessage.isMuc ? mlMessage.contactDisplayName : nil, text: (message as! ChatViewMessage).replyQuoteText ?? mlMessage.messageText)
                case .forward:
                    if mlMessage.messageType == kMessageTypeFiletransfer {
                        messageToForward = .file(messageDBId: messageDBId, message: mlMessage)
                    } else {
                        messageToForward = .text(mlMessage.messageText)
                    }
                case .edit:
                    inputModel.startEdit(of: mlMessage.messageId, text: mlMessage.messageText)
                    editSaveClosure = { editedText in
                        Task { @MainActor in
                            self.account.sendMessage(editedText,
                                                     to: self.contact.obj,
                                                     isEncrypted: self.contact.isEncrypted || mlMessage.encrypted,
                                                     isUpload: false,
                                                     andMessageId: UUID().uuidString,
                                                     withLMCId: mlMessage.messageId)

                            // Don't block the main thread while writing to the DB
                            await Task.detached(priority: .userInitiated) {
                                DataLayer.sharedInstance().updateMessageHistory(messageDBId, withText: editedText)
                            }.value

                            MLNotificationQueue.current().post(
                                name: Notification.Name(kMonalUpdatedMessageNotice),
                                object: self.account,
                                userInfo: [
                                    "message": mlMessage,
                                    "contact": self.contact.obj,
                                    "LMCReplaced": true,
                                    "correctedText": editedText,
                                    "reactionsUpdate": false
                                ]
                            )
                        }
                    }
                case .retract:
                    self.account.retractMessage(mlMessage)
                case .moderate:
                    messageToModerate = mlMessage
                case .delete:
                    Task { @MainActor in
                        await Task.detached(priority: .userInitiated) {
                            mlMessage.deleteLocally()
                        }.value

                        self.messages.removeAll(where: {$0.id == message.id})
                        // Update active chats if necessary
                        MLNotificationQueue.current().post(
                            name: Notification.Name(kMonalContactRefresh),
                            object: self.account,
                            userInfo: ["contact": self.contact.obj]
                        )
                    }
                case .resend:
                    // Explicitly schedule this on the main thread, to ensure the update to confirmationPrompt happens.
                    // This is needed for some reason, despite this code being already on the main thread.
                    Task { @MainActor in
                        self.confirmationPrompt = ConfirmationPrompt(
                            title: Text("Retry sending message?"),
                            message: Text("This message failed to send (\(mlMessage.errorType ?? "unknown error")): \(mlMessage.errorReason ?? "unknown reason")"),
                            buttons: [
                                .default(
                                    Text("Retry"),
                                    action: {
                                        Task { @MainActor in
                                            await Task.detached(priority: .userInitiated) {
                                                DataLayer.sharedInstance().clearError(ofMessageId: mlMessage.messageId)
                                            }.value

                                            mlMessage.errorType = ""
                                            mlMessage.errorReason = ""
                                            let isUpload = mlMessage.messageType == kMessageTypeFiletransfer
                                            let isEncrypted = mlMessage.encrypted || self.contact.isEncrypted
                                            self.account.sendMessage(mlMessage.messageText,
                                                                     to: self.contact.obj,
                                                                     isEncrypted: isEncrypted,
                                                                     isUpload: isUpload,
                                                                     andMessageId: mlMessage.messageId)
                                            MLNotificationQueue.current().post(
                                                name: Notification.Name(kMLMessageSentToContact),
                                                object: self.account,
                                                userInfo: ["contact": self.contact.obj]
                                            )
                                        }
                                    }
                                ),
                                .cancel(
                                    Text("Cancel"),
                                    action: { }
                                )
                            ]
                        )
                    }
            }
        })
        /*
        .swipeActions(edge: .leading, performsFirstActionWithFullSwipe: true, items: [
            SwipeAction(action: { (message, defaultActionClosure) in
                defaultActions(message, .reply)
            }, activeFor: { !$0.user.isCurrentUser }, background: .blue) {
                VStack {
                    Image(systemName: "arrowshape.turn.up.left")
                        .imageScale(.large)
                        .foregroundStyle(.white)
                        .frame(height: 30)
                    Text("Reply")
                        .foregroundStyle(.white)
                        .font(.footnote)
                }
            }
        ])
        */
        // isaCloud: pulling a message to the right replies to it, like "Reply" in the message menu
        .onSwipeToReply(activeFor: { message in
            (message as! ChatViewMessage).replyQuoteText != nil
        }, onReply: { message in
            let chatMessage = message as! ChatViewMessage
            guard let text = chatMessage.replyQuoteText else {
                return
            }
            inputModel.quote(author: chatMessage.innerMessage.obj.isMuc ? chatMessage.innerMessage.obj.contactDisplayName : nil, text: text)
        })
        .onMessageReaction(didReactTo: { message, reaction in
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            switch reaction.type {
                case .emoji(let emoji):
                    var currentReactions: NSMutableOrderedSet = []
                    for reactionsInfo in mlMessage.reactions {
                        if reactionsInfo.contact.isSelf {
                            currentReactions = NSMutableOrderedSet(orderedSet: reactionsInfo.reactions)
                        }
                    }
                    if currentReactions.contains(emoji) {
                        currentReactions.remove(emoji)
                    } else {
                        currentReactions.add(emoji)
                    }
                    self.account.sendReactions(currentReactions, for:mlMessage)
            }
        }, canReactTo: { message in
            //isaCloud: a message on its way has no history id yet, so it cannot be reacted to
            if (message as! ChatViewMessage).isPending {
                return false
            }
            //don't allow reactions in mucs without occupant-id support
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            let retval = !mlMessage.isMuc || 
                (mlMessage.stanzaId != nil && self.account.mucProcessor.getRoomFeatures(forMuc:mlMessage.chatContact.contactJid).contains("urn:xmpp:occupant-id:0"))
            DDLogDebug("Checking if we can react to: \(String(describing:mlMessage)) --> \(String(describing:retval))")
            return retval
        }, shouldShowOverviewFor: { _ in
            // who reacted with what is shown by tapping the reactions of a message, not above the long press menu
            false
        })
        .autoFocusTextInputOnChatOpen(chatViewDefaultsDB.showKeyboardOnChatOpen)
        .showUsername(contact.isMuc)
        .scrollTo(jumpScrollParams)      //isaCloud: see jumpToSearchedMessage()
        .messageMenuAnimationDuration(0.15)      //isaCloud: the message menu (reactions, actions) opens sooner than the library's 0.3 s
        .reactionsBelowBubble(!chatViewDefaultsDB.reactionsAboveMessages)       //isaCloud: in the footer, unless the setting asks for the old place
        .setMessageFont(ChatTextSize.messageFont(system: dynamicTypeSize, step: chatViewDefaultsDB.chatTextSizeStep))      //isaCloud: see ChatTextSize
        .setMessageTimeFont(ChatTextSize.timeFont(system: dynamicTypeSize, step: chatViewDefaultsDB.chatTextSizeStep))
        .tapAvatarClosure { user, _ in
            // mentions use only the nick: the verified emoji of the name is not part of it
            inputModel.setText(inputModel.text + "\(ChatNameWithHats.nick(from: user.name)), ")
        }
        .linkPreviewsEnabled(chatViewDefaultsDB.showURLPreview)
        .checkFileSizeClosure { file in
            MLFiletransfer.checkMimeTypeAndSize(forHistoryID: Int(file.id)! as NSNumber)
        }
        .downloadFileClosure { file in
            MLFiletransfer.downloadFile(forHistoryID: Int(file.id)! as NSNumber)
        }
        .filePreviewHardlinksDirectory(HelperTools.filePreviewHardlinksDirectory())
        .enableLoadMore(offset: 10) {
            loadHistory()
        }
        .chatTheme(
            ChatTheme(
                // isaCloud: the messages the user sends are pink, with black text
                colors: ChatTheme.Colors(
                    messageMyBG: IsaCloudBubbleColors.mine,
                    messageMyText: IsaCloudBubbleColors.mineText,
                    messageMyTimeText: IsaCloudBubbleColors.mineTime,
                    sendButtonBackground: IsaCloudBubbleColors.mine
                ),
                //isaCloud: ExyteChat draws nothing for a message that reached the server (its "sent" image is empty), so the
                //message had no icon between the clock and the delivery confirmation: it gets a dotted check in a circle, while the
                //hollow check in a circle (delivered to the device) and the filled one (read) keep the library's icons
                images: self.backgroundImage != nil ?
                    .init(sent: Image(uiImage: IsaCloudStatusIcons.sentToServer), background: ChatTheme.Images.Background(Image(uiImage: self.backgroundImage!))) :
                    .init(sent: Image(uiImage: IsaCloudStatusIcons.sentToServer))
            )
        )
        //isaCloud: the SwiftUI text inside the chat (names, quotes, reactions, input bar) follows the same step as the fonts above.
        //Only the chat's subtree gets it: the sheets and the toolbar, attached after this modifier, keep the system size
        .dynamicTypeSize(ChatTextSize.dynamicTypeSize(system: dynamicTypeSize, step: chatViewDefaultsDB.chatTextSizeStep))
        .sheet(isPresented: $showMediaPicker) {
            //isaCloud: the system picker (see SystemMediaPicker)
            SystemMediaPicker(isPresented: $showMediaPicker, onPicked: { medias in
                addPickedMedias(medias)
            })
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            addFiles(result)
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(onSend: { coordinate in
                sendLocation(coordinate)
            })
        }
        .sheet(isPresented: $showGifPicker) {
            GifPickerView(apiKey: GiphySearch.apiKey(from: Bundle.main.infoDictionary), onPick: { url in
                inputModel.addAttachment(ChatInputAttachment(kind: .animatedGif, url: url))
            })
        }
        .sheet(item: $selectedContactForContactDetails) { selectedContact in
            AnyView(AddTopLevelNavigation(withDelegate:nil, to:ContactDetails(delegate:nil, contact:selectedContact)))
        }
        //TODO: modernize action sheet usage in all other swiftui files to be in line with this implementation here
        //TODO: e.g. same usage like alert prompt below
        .actionSheet(isPresented: $confirmationPrompt.optionalMappedToBool()) {
            ActionSheet(title: confirmationPrompt!.title, message: confirmationPrompt!.message, buttons: confirmationPrompt!.buttons)
        }
        //TODO: modernize alert prompt usage in all other swiftui files to be in line with this implementation here
        //TODO: e.g. non-hardcoded dismiss button text and usage of optionalMappedToBool and dismissCallback
        //somehow the order of alert modifiers is important: they have to come after all sheet modifiers
        .alert(isPresented: $alertPrompt.optionalMappedToBool()) {
            let callback = alertPrompt!.dismissCallback
            return Alert(title: alertPrompt!.title, message: alertPrompt!.message, dismissButton:.default(alertPrompt!.dismissLabel, action: {
                if let callback = callback {
                    callback()
                }
            }))
        }
        .richAlert(isPresented: $messageToModerate, title:Text("Moderating message")) { mlMessage in
            VStack(alignment: .leading) {
                Text("Enter the moderation reason:")
                TextField(NSLocalizedString("Spam", comment: "placeholder for the message moderation reason"), text: $moderationReason, onEditingChanged: { isEditingReason = $0 })
                .submitLabel(.continue)
                .addClearButton(isEditing: isEditingReason, text: $moderationReason)
                
                if let _ = mlMessage.participantJid {
                    Toggle(isOn: $blockOnModeration) {
                        Text("Block this user")
                    }
                }
            }.textFieldStyle(.roundedBorder)
        } buttons: { mlMessage in
            Button(action: {
                let promise = showPromisingLoadingOverlay(self.overlay, headline: "Retracting message", description: "") {
                    self.account.moderateMessage(mlMessage, withReason: moderationReason)
                    // Reset moderationReason to its default value only after the moderation was sent
                    // (`promise` executes after the rest of the `action` closure. So we don't want to
                    // reset moderationReason when the alert is dismissed like other State variables,
                    // because the moderation isn't sent yet at that point.)
                    moderationReason = "Spam"
                    return Guarantee.value(())
                }
                if blockOnModeration, let participantJid = mlMessage.participantJid {
                    let _ = promise.done { _ in
                        showPromisingLoadingOverlay(self.overlay, headlineView: Text("Blocking user"), descriptionView: Text("Blocking \(participantJid)")) {
                            DDLogVerbose("Changing affiliation of \(participantJid) to: \(String(describing:kMucAffiliationOutcast))...")
                            return account.mucProcessor.setAffiliation(kMucAffiliationOutcast, ofUser:participantJid, inMuc:contact.obj.contactJid).toTypedPromise()
                        }.catch { error in
                            alertPrompt = AlertPrompt(
                                title: Text("Error blocking user!"),
                                message: Text(error.localizedDescription),
                                dismissLabel: Text("Close")
                            )
                        }
                    }
                }
                // Reset the State variables (except moderationReason) to their default values, as the alert is dismissed
                messageToModerate = nil
                blockOnModeration = true
            }) {
                Text("Moderate")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
            }
            
            Button(action: {
                messageToModerate = nil
                moderationReason = "Spam"
                blockOnModeration = true
            }) {
                Text("Cancel")
                    .foregroundColor(.accentColor)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                //make sure to take all space available, otherwise we'll get aligned to the center
                //of the navigation bar instead of the leading edge
                ZStack {
                    Color.clear
                    
                    HStack {
                        Button {
                            selectedContactForContactDetails = contact
                        } label: {
                            HStack {
                                Image(uiImage: contact.avatar)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 35, height: 35)

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(contact.contactDisplayName as String)
                                        .fontWeight(.semibold)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    if (contact.isTyping as Bool) {
                                        Text("Typing...")
                                            .font(.footnote)
                                            .foregroundColor(Color(hex: "AFB3B8"))
                                    } else if contact.isMuc && mucPersonCount > 0 {
                                        //isaCloud: how many people are in the group or channel
                                        Text(mucPersonCountLabel(isGroup: contact.obj.mucType == kMucTypeGroup, count: mucPersonCount))
                                            .font(.footnote)
                                            .foregroundColor(Color(hex: "AFB3B8"))
                                    } else if let lastInteractionDate:Date = contact.lastInteractionTime {
                                        TimelineView(.periodic(from: lastInteractionDate, by: 60.0)) { _ in
                                            Text(HelperTools.formatLastInteraction(contact.lastInteractionTime))
                                                .font(.footnote)
                                                .foregroundColor(Color(hex: "AFB3B8"))
                                        }
                                    }
                                }
                            }
                        }
                        // When used in the toolbar, the default button style doesn't have any size constraints.
                        // => use a different button style to ensure the truncation of long contact names.
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                }
            }
            
            loadingIndicatorToolbarItem
            ToolbarItemGroup(placement: .topBarTrailing) {
                if ownRole == kMucRoleVisitor {
                    Button {
                        let _ = showPromisingLoadingOverlay(overlay, headline:"Requesting Voice") {
                            Guarantee { $0(contact.obj.account?.mucProcessor.requestVoice(inMuc:contact.obj.contactJid)) }
                        }
                    } label: {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(Color("isaCloudPink"))
                    }
                }
                
                if contact.isMuc && ownRole == kMucRoleModerator && voiceRequests.count > 0 {
                    Button {
                        //TODO: open sheet with voice requests
                    } label: {
                        Image(systemName: "questionmark.bubble")
                            .foregroundStyle(Color("isaCloudPink"))
                    }
                }
                
                if !(contact.isMuc || contact.isSelf) {
                    Button {
                        let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!
                        if voipProcessor.obj.getActiveCall(with:contact.obj) == nil && !DataLayer.sharedInstance().checkCap("urn:xmpp:jingle-message:0", forUser:contact.contactJid, onAccountID:contact.accountID) {
                            confirmationPrompt = ConfirmationPrompt(
                                title: Text("Missing Call Support"),
                                message: Text("Your contact may not support calls. Your call might never reach its destination."),
                                buttons: [
                                    .default(
                                        Text("Try nevertheless"),
                                        action: {
                                            activeChats.call(contact.obj, withUIKitSender:nil)
                                        }
                                    ),
                                    .cancel(
                                        Text("Cancel"),
                                        action: { }
                                    )
                                ]
                            )
                        } else {
                            activeChats.call(contact.obj, withUIKitSender:nil)
                        }
                    } label: {
                        if (voipProcessor.activeCalls as [MLCall]).contains(where:{ $0.isEqual(to:contact.obj) }) {
                            Image(systemName: "phone.connection.fill")
                                .foregroundStyle(Color("isaCloudPink"))
                        } else {
                            Image(systemName: "phone.fill")
                                .foregroundStyle(Color("isaCloudPink"))
                        }
                    }
                }
                
                //isaCloud: groups and channels only show the state, without an action (the encryption of a group is changed in its details)
                if !contact.isMuc {
                    Button {
                        guard !HelperTools.isContactBlacklistedForEncryption(contact.obj) else {
                            return
                        }
                        if contact.isEncrypted {
                            DDLogVerbose("Showing should disable encryption confirmation...")
                            showShouldDisableEncryptionConfirmation(true)
                        } else {
                            showCannotEncryptAlert(!contact.obj.toggleEncryption(true))
                        }
                    } label: {
                        if contact.isEncrypted {
                            Label {
                                Text("Messages are encrypted")
                            } icon: {
                                Image(systemName: "lock.fill")
                            }
                        } else {
                            Label {
                                Text("Messages are NOT encrypted")
                            } icon: {
                                //isaCloud: red only while the button works; where encryption is not possible (public channels) it stays gray
                                Image(systemName: "lock.open.fill")
                                    .foregroundColor(encryptionButtonDisabled ? nil : .red)
                            }
                        }
                    }
                    .tint(Color("isaCloudPink"))
                    .disabled(encryptionButtonDisabled)
                    .confirmationDialog(Text("Disable encryption?"), isPresented: $showDisableEncryptionDialog, titleVisibility: .visible) {
                        Button("No, keep encryption activated", role: .cancel) { }
                        Button("Yes, deactivate encryption", role: .destructive) {
                            contact.obj.toggleEncryption(false)
                        }
                    } message: {
                        Text("Do you really want to disable encryption for this contact?")
                    }
                }
            }
            encryptionIndicatorToolbarItem
        }
        .sheet(isPresented: Binding(get: { messageToForward != nil }, set: { if !$0 { messageToForward = nil } })) {
            MessageForwardPicker { destinations in
                //(closing the sheet clears the item: it is read before)
                let item = messageToForward
                messageToForward = nil
                switch item {
                case .text(let text)?:
                    forward(text, to: destinations)
                case .file(let messageDBId, let message)?:
                    Task { await forwardFile(messageDBId, message, to: destinations) }
                case nil:
                    break
                }
            }
        }
        .toolbarRole(.editor)       //make sure to never show the title of the previous view in the back bar button
        .canContainExternalLinks()
        .addLoadingOverlay(overlay)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            MLNotificationManager.sharedInstance().currentContact = self.contact.obj
            loadChatBackground()
            mucPersonCount = countMucPersons(of: contact, ownJid: account.connectionProperties.identity.jid)    //isaCloud

            checkOmemoSupport(withAlert:false)
            let messageDraft = DataLayer.sharedInstance().loadMessageDraft(self.contact.contactJid, forAccount:self.account.accountID)
            if let messageDraft, !messageDraft.isEmpty {
                inputModel.setText(messageDraft)
            }
            loadHistory()
            jumpToSearchedMessage()      //isaCloud
            if self.contact.obj.isMuc {
                ownRole = DataLayer.sharedInstance().getOwnRole(inGroupOrChannel: contact.obj) ?? kMucRoleNone
                voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
            }
            ChatViewHelpers.refreshCounter(for: self.contact.obj)
        }
        .onDisappear {
            // When the split view is active, selecting different chats results in the old
            // view's onDisappear executing after the new view's onAppear, thus erroneously
            // making currentContact always nil.
            // This if statement ensures currentContact has the correct value.
            if MLNotificationManager.sharedInstance().currentContact == self.contact.obj {
                MLNotificationManager.sharedInstance().currentContact = nil
            }
            messageInsertionTimer?.invalidate()
            sendChatState(isTyping: false)
            DispatchQueue.global(qos: .userInitiated).async {
                DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount:self.account.accountID, withComment:self.inputModel.text)
                // Update active chats to show the new draft
                MLNotificationQueue.current().post(
                    name: Notification.Name(kMonalContactRefresh),
                    object: self.account,
                    userInfo: ["contact": self.contact.obj]
                )
            }
        }
        .onChange(of: inputModel.text) { oldValue, newValue in
            // Don't send a typing notification if the only change is deletion of characters from the end.
            // This results in better UX, and avoids sending a typing notification after the automatic
            // clearing of the input text when sending a message.
            if oldValue.count > newValue.count && oldValue.starts(with: newValue) {
                return
            }
            // Workaround to avoid sending a typing notification when inserting the draft on chat open.
            // Side-effect: if the user pastes from the clipboard while the input text is empty, a typing
            // notification won't be sent unless they type more characters.
            if oldValue.isEmpty && newValue.count > 1 {
                return
            }
            sendChatState(isTyping: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalOmemoFetchingStateUpdate)).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let notificationJid = notification.userInfo?["jid"] as? String {
                if xmppAccount.accountID == contact.accountID && notificationJid == contact.contactJid {
                    DDLogDebug("Got omemo fetching update: \(contact) --> \(String(describing:notification.userInfo))")
                    if let _ = (notification.userInfo?["isFetching"] as? Bool) {
                        //recheck support and show alert if needed
                        DDLogVerbose("Rechecking omemo support with alert, if needed...")
                        checkOmemoSupport(withAlert:true)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalNewMessageNotice)).receive(on: RunLoop.main)) { notification in
            DDLogVerbose("ChatView got new message notice \(String(describing:notification.userInfo))")

            guard let message = notification.userInfo?["message"] as? MLMessage else {
                unreachable("kMonalNewMessageNotice notification without message!")
            }
            if message.isEqual(self.contact.obj) {
                // Don't insert based on delay timestamp because that would make it possible to fake history entries.
                // Insert new messages in batches to work around https://github.com/exyte/Chat/issues/223
                enqueueNewMessages([ChatViewMessage(message)])
            }
            ChatViewHelpers.refreshCounter(for: self.contact.obj)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalMucParticipantsAndMembersUpdated)).receive(on: RunLoop.main)) { notification in
            //isaCloud: keep the number under the name current
            if let notificationContact = notification.userInfo?["contact"] as? MLContact, notificationContact == contact.obj {
                mucPersonCount = countMucPersons(of: contact, ownJid: account.connectionProperties.identity.jid)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalRefresh)).receive(on: RunLoop.main)) { notification in
            loadMissedMessages()        //isaCloud
            ChatViewHelpers.refreshCounter(for: self.contact.obj)
            voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalFiletransferInfoUpdated)).receive(on: RunLoop.main)) { notification in
            //isaCloud: a received file gets its type and size after the message arrived; show it with them
            guard let updated = notification.userInfo?["message"] as? MLMessage,
                  updated.isEqual(self.contact.obj),
                  let index = messages.firstIndex(where: { $0.historyId == updated.messageDBId }) else {
                return
            }
            messages[index] = ChatViewMessage(updated)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalShareOutboxUpdate)).receive(on: RunLoop.main)) { notification in
            //isaCloud: messages sent from the share sheet go through the outbox; show the sending state and the message here
            guard let shared = notification.userInfo?["contact"] as? MLContact,
                  shared.contactJid == contact.obj.contactJid,
                  shared.accountID == contact.obj.accountID else {
                return
            }
            if let uploading = notification.userInfo?["uploading"] as? NSNumber {
                inputModel.isUploading = uploading.boolValue
            }
            if let message = notification.userInfo?["message"] as? MLMessage {
                messages.append(ChatViewMessage(message))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalMucOwnAffiliationOrRoleChanged)).receive(on: RunLoop.main)) { notification in
            guard let mucContact = notification.userInfo?["contact"] as? MLContact else {
                unreachable("kMonalMucOwnAffiliationOrRoleChanged notification without contact!")
            }
            if self.contact.obj.isMuc && mucContact.isEqual(self.contact.obj) {
                voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
                ownRole = DataLayer.sharedInstance().getOwnRole(inGroupOrChannel: contact.obj) ?? kMucRoleNone
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalMucVoiceRequestsUpdated)).receive(on: RunLoop.main)) { notification in
            guard let mucContact = notification.userInfo?["contact"] as? MLContact else {
                unreachable("kMonalMucVoiceRequestsUpdated notification without contact!")
            }
            if mucContact.isEqual(self.contact.obj) {
                voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalContactHistoryCleared)).receive(on: RunLoop.main)) { notification in
            DDLogVerbose("ChatView got history cleared notice \(String(describing:notification.userInfo))")
            guard let contact = notification.userInfo?["contact"] as? MLContact else {
                unreachable("Notification without contact")
            }
            if contact.isEqual(self.contact.obj) {
                self.messages = []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalBackgroundChanged)).receive(on: RunLoop.main)) { notification in
            loadChatBackground()
        }
        .onReceive(Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification).receive(on: RunLoop.main),
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).receive(on: RunLoop.main)
        )) { notification in
            DDLogVerbose("ChatView of chat \(contact.obj.contactJid) received \(notification.name.rawValue)")
            sendChatState(isTyping: false)
            DispatchQueue.global(qos: .userInitiated).async {
                DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount:self.account.accountID, withComment:self.inputModel.text)
                // Update active chats to show the new draft
                MLNotificationQueue.current().post(
                    name: Notification.Name(kMonalContactRefresh),
                    object: self.account,
                    userInfo: ["contact": self.contact.obj]
                )
            }
        }
    }
}

class ChatViewMessage: ExyteChat.Message {
    @ObservedObject var chatViewDefaultsDB = ChatViewDefaultsDB()
    private(set) var innerMessage: ObservableKVOWrapper<MLMessage>
    let fileInfo: ObservableKVOWrapper<MLFiletransferInfo>?
    private var subscriptions: Set<AnyCancellable> = Set()
    private var innerSubscription: AnyCancellable?
    override var text: String {
        if self.staticLocation != nil {
            return ""
        } else if innerMessage.messageType == kMessageTypeFiletransfer && fileInfo != nil {
            return ""
        }
        return innerMessage.retracted ? NSLocalizedString("This message got retracted", comment: "") : innerMessage.messageText
    }
    override var hasText: Bool {
        return !text.isEmpty
    }
    /// What a reply to this message quotes, or nil when it cannot be replied to (a retracted message, or one without text
    /// that is none of the kinds below). A text message quotes its text. A message without text (photo, video, GIF, audio, file, location) quotes a
    /// short label such as "📷 Photo" (see QuoteFormatting.attachmentLabel).
    /// TEMPORARY: the reply is only a quote in the text of the message until Monal implements XEP-0461 (Message Replies) and
    /// XEP-0428 (Fallback Indication); with them the label is the fallback text, and the thumbnail of a photo and the jump to
    /// the original message become possible. The label says what kind of message it was, not which one.
    var replyQuoteText: String? {
        let mlMessage = innerMessage.obj
        if mlMessage.retracted {
            return nil
        }
        if hasText {
            return mlMessage.messageText
        }
        if staticLocation != nil {
            return QuoteFormatting.attachmentLabel(.location)
        }
        guard mlMessage.messageType == kMessageTypeFiletransfer, let fileInfo = fileInfo else {
            return nil
        }
        //isaCloud: these fields are nullable on a file transfer that has not been downloaded yet, and the KVO wrapper *throws*
        //when a member is nil (it was the crash of 29/10/2026: replyQuoteText -> fileInfo.mimeType -> ObservableKVOWrapperCastingError).
        //Asking for an optional keeps the cast safe.
        if (fileInfo.mimeType as String?) == "image/gif" {
            return QuoteFormatting.attachmentLabel(.gif)
        } else if (fileInfo.isImage as Bool?) == true {
            return QuoteFormatting.attachmentLabel(.photo)
        } else if (fileInfo.isVideo as Bool?) == true {
            return QuoteFormatting.attachmentLabel(.video)
        } else if (fileInfo.isAudio as Bool?) == true {
            return QuoteFormatting.attachmentLabel(.audio)
        }
        return QuoteFormatting.attachmentLabel(.file(name: (fileInfo.filename as String?) ?? ""))
    }
    /// isaCloud: the label line of a forwarded message, in bold (white in our own bubbles)
    private func forwardLabelText(_ label: String) -> AttributedString {
        var attributed = AttributedString(label)
        attributed.inlinePresentationIntent = .stronglyEmphasized
        //white on the pink bubble of our own messages; on the light bubble of what others forward to us white would not be seen
        attributed.foregroundColor = self.user.isCurrentUser ? Color.white : Color.primary
        return attributed
    }
    /// isaCloud: the text of a message: quoted lines ("> ...") are marked as a quote (ExyteChat draws them with bars on their left, see
    /// AttributedString+Quote.swift in our ExyteChat fork); the other lines are shown as usual, with their links
    static func attributed(body text: String, linkColor: Color, isText: Bool) -> AttributedString {
        if isText && QuoteFormatting.containsQuote(text) {
            var result = AttributedString()
            var previousDepth = 0
            for (index, line) in QuoteFormatting.lines(of: text).enumerated() {
                if index > 0 {
                    // the line break between two quoted lines belongs to the quote they share (the smaller depth), so they
                    // make one quote and not two
                    var lineBreak = AttributedString("\n")
                    let shared = min(previousDepth, line.depth)
                    if shared > 0 {
                        lineBreak.quoteDepth = shared
                    }
                    result.append(lineBreak)
                }
                if line.depth > 0 {
                    var quoted = AttributedString(line.text)
                    quoted.quoteDepth = line.depth
                    result.append(quoted)
                } else {
                    result.append(line.text.linkify(linkColor: linkColor))
                }
                previousDepth = line.depth
            }
            return result
        }
        return text.linkify(linkColor: linkColor)
    }
    override var attributedText: AttributedString {
        get {
            // Keep outgoing links in the same color as outgoing text (white) for readability
            let linkColor: Color = self.user.isCurrentUser ? .white : .accentColor

            // isaCloud: the first line of a forwarded text says so, in bold (white in our own bubbles); the rest is the text as always
            if innerMessage.messageType == kMessageTypeText || innerMessage.messageType == kMessageTypeUrl, let forwarded = MessageForward.split(text) {
                return forwardLabelText(forwarded.label) + AttributedString("\n") + Self.attributed(body: forwarded.rest, linkColor: linkColor, isText: innerMessage.messageType == kMessageTypeText)
            }
            //isaCloud: the label sent alone, before a forwarded file (no text under it): drawn the same way
            if innerMessage.messageType == kMessageTypeText, let label = MessageForward.labelAlone(text) {
                return forwardLabelText(label)
            }
            if innerMessage.messageType == kMessageTypeText {
                return Self.attributed(body: text, linkColor: linkColor, isText: true)
            }

            if innerMessage.messageType == kMessageTypeGeo && !chatViewDefaultsDB.showGeoLocation {
                // Link to OpenStreetMap as a fallback for geo messages when inline maps are disabled
                if let location = StaticLocation(geoURIString: innerMessage.obj.messageText),
                    let url = URL(string: "https://www.openstreetmap.org/?mlat=\(location.latitude)&mlon=\(location.longitude)&zoom=15") {
                    var attributed = AttributedString(text)
                    attributed.link = url
                    attributed.underlineStyle = .single
                    attributed.foregroundColor = linkColor
                    return attributed
                }
            }
            return text.linkify(linkColor: linkColor)
        }
        set {}
    }
    override var encrypted: Bool {
        get {
            return innerMessage.encrypted
        }
        set {}
    }
    override var status: Status? {
        get {
            // Incoming messages shouldn't have a status
            if innerMessage.inbound {
                return nil
            }
            //isaCloud: a retracted message is gone; it must not show the sending indicator (the one the Manuela chat showed forever
            //was retracted before it was ever sent, so it kept sent=0 and looked like it was still on its way)
            if innerMessage.retracted {
                return nil
            }
            let errorType = innerMessage.errorType as String?
            let isError = errorType != nil && !errorType!.isEmpty
            switch(innerMessage) {
                case let message where isError && !message.hasBeenReceived:
                    return .error(DraftMessage(id: id, text: text, medias: [], files: [], recording: recording, replyMessage: replyMessage, createdAt: createdAt))
                case let message where message.hasBeenDisplayed:
                    return .readBy([])
                case let message where message.hasBeenReceived:
                    return .received
                case let message where message.hasBeenSent:
                    return .sent
                default:
                    return .sending
            }
        }
        set {}
    }
    override var createdAt: Date {
        get {
            return innerMessage.timestamp
        }
        set {}
    }
    override var reactions: [Reaction] {
        get {
            //TODO: create new wrapper class ChatViewReaction just like we've already done for User and Contact
            var retval: [Reaction] = []
            let reactions: [MLReactionsEntry] = (innerMessage.reactions as [MLReactionsEntry]).sorted(by: { $0.user < $1.user })
            for reactionsInfo in reactions {
                for reaction in reactionsInfo.reactions {
                    //isaCloud: a stable id (the default is a new UUID on every call, which made the same reactions compare as different
                    //on every render, so ExyteChat redid the whole list update several times per second in busy channels)
                    retval.append(Reaction(
                        id: "\(reactionsInfo.contact.id)|\(reaction as! String)",
                        user: ChatViewUser(reactionsInfo.contact as! NSObject&MLContactProtocol),
                        createdAt: reactionsInfo.timestamp,
                        type: .emoji(reaction as! String),
                        status: .sent
                    ))
                }
            }
            return retval
        }
        set {}
    }
    override var files: [File] {
        get {
            guard innerMessage.messageType == kMessageTypeFiletransfer, let fileInfo = fileInfo else {
                return []
            }

            let downloadState = fileInfo.downloadState as DownloadState.RawValue
            let fileID = innerMessage.obj.messageDBId.stringValue
            let isBeingDownloaded = MLFiletransfer.isFileForHistoryId(inTransfer: innerMessage.messageDBId)
            if downloadState == DownloadState.none.rawValue {
                let file = File(id: fileID, localURL: nil, name: fileInfo.filename, downloadState: .none, isBeingDownloaded: isBeingDownloaded)
                return [file]
            } else if downloadState == DownloadState.headers.rawValue {
                let file = File(id: fileID, localURL: nil, name: fileInfo.filename, downloadState: .headers,  isBeingDownloaded: isBeingDownloaded, mimeType: fileInfo.mimeType, size: (fileInfo.size as NSNumber).intValue)
                return [file]
            } else {
                if fileInfo.isImage || fileInfo.isVideo || fileInfo.isAudio {
                    // In these cases the file is included in the `attachments` or `recording` properties
                    return []
                }
                let file = File(id: fileID, localURL: fileInfo.fileURL, name: fileInfo.filename, downloadState: .complete, mimeType: fileInfo.mimeType, size: (fileInfo.size as NSNumber).intValue)
                return [file]
            }
        }
        set {}
    }

    override var attachments: [Attachment] {
        get {
            guard innerMessage.messageType == kMessageTypeFiletransfer,
                let fileInfo = fileInfo,
                (fileInfo.downloadState as DownloadState.RawValue) == DownloadState.complete.rawValue,
                fileInfo.isImage || fileInfo.isVideo else {
                // images and videos with .none and .headers download state are included in the `files` property
                return []
            }

            let attachmentID = innerMessage.obj.messageDBId.stringValue
            if fileInfo.isImage {
                let attachment = Attachment(id: attachmentID, url: fileInfo.fileURL, type: .image, mimeType: fileInfo.mimeType)
                return [attachment]
            } else {
                let thumbnail = fileInfo.thumbnailURL as URL? ?? URL(string: "about:blank")!
                let attachment = Attachment(id: attachmentID, thumbnail: thumbnail, full: fileInfo.fileURL, type: .video, mimeType: fileInfo.mimeType)
                return [attachment]
            }
        }
        set {}
    }
    override var recording: Recording? {
        get {
            guard innerMessage.messageType == kMessageTypeFiletransfer,
                let fileInfo = fileInfo,
                (fileInfo.downloadState as DownloadState.RawValue) == DownloadState.complete.rawValue,
                fileInfo.isAudio else {
                // audio files with .none and .headers download state are included in the `files` property
                return nil
            }

            return Recording(duration: fileInfo.mediaDuration, url: fileInfo.fileURL, mimeType: fileInfo.mimeType)
        }
        set {}
    }
    override var staticLocation: StaticLocation? {
        get {
            guard innerMessage.messageType == kMessageTypeGeo, chatViewDefaultsDB.showGeoLocation else {
                return nil
            }
            return StaticLocation(geoURIString: innerMessage.obj.messageText)
        }
        set {}
    }

    init(_ message: MLMessage) {
//         DDLogVerbode("Creating new ChatViewMessage for MLMessage: \(String(describing:message)): \(Thread.callStackSymbols)")
        self.innerMessage = ObservableKVOWrapper(message)
        if innerMessage.obj.messageType == kMessageTypeFiletransfer {
            self.fileInfo = ObservableKVOWrapper(innerMessage.obj.fileInfo)
        } else {
            self.fileInfo = nil
        }
        let user = ChatViewUser(message.contact as! NSObject&MLContactProtocol)
        // We don't need to properly initialize the properties that we overrode with computed properties
        super.init(id: message.id, user: user, createdAt: Date(), text: "")

        observeInnerMessage()

        // Forward fileInfo changes as ChatViewMessage changes
        fileInfo?.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
    /// Forwards innerMessage changes as ChatViewMessage changes
    private func observeInnerMessage() {
        innerSubscription = innerMessage.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }
    /// isaCloud: the message shown while it was on its way takes the saved message (see ChatView.finishSending): the same object goes on
    /// in the list, and it now follows the saved message (status, reactions, etc.)
    func adopt(_ saved: MLMessage) {
        innerMessage = ObservableKVOWrapper(saved)
        isPending = false
        observeInnerMessage()
        objectWillChange.send()
    }
    /// isaCloud: the text message that was just sent, before it is saved (see ChatView.sendTextAtOnce): not in the database yet, no
    /// history id, not sent yet, so it shows the sending state
    static func pending(text: String, to contact: MLContact, ownJid: String) -> ChatViewMessage {
        let message = MLMessage()
        message.accountID = contact.accountID
        message.buddyName = contact.contactJid
        message.inbound = false
        message.actualFrom = contact.isMuc ? contact.accountNickInGroup : ownJid
        if contact.isMuc {
            message.occupantId = DataLayer.sharedInstance().getOwnOccupantId(forMuc: contact.contactJid, onAccountID: contact.accountID) ?? UUID().uuidString
        }
        message.messageText = text
        message.messageType = kMessageTypeText
        message.timestamp = Date()
        message.encrypted = contact.isEncrypted
        message.reactions = []      //the list reads them on every comparison of messages
        let pending = ChatViewMessage(message)
        //the id of a message is made of the account and the history id, and this one has none yet: two messages on their way would
        //share an id, and ExyteChat aborts on that
        pending.id = "pending|\(UUID().uuidString)"
        pending.isPending = true
        return pending
    }
    /// isaCloud: true only while the message is on its way (adopt(_:) clears it); the id keeps its "pending|" prefix for the rest of the session, so it
    /// cannot be used to tell
    var isPending = false
    /// isaCloud: the history id of a saved message; nil for a message on its way, which is not in the database yet
    var historyId: NSNumber? {
        return isPending ? nil : innerMessage.obj.messageDBId
    }
    public var description: String {
        return "ChatViewMessage<\(String(describing:self.innerMessage))>"
    }
}

class ChatViewUser: ExyteChat.User {
    let innerContact: ObservableKVOWrapper<NSObject&MLContactProtocol>
    private var subscriptions: Set<AnyCancellable> = Set()
    override var name: String {
        get {
            let nick = innerContact.contactDisplayName ?? ""
            // isaCloud: participants of a channel or group show their verified emoji next to the nick
            guard let channel = innerContact.obj as? MLChannelContact else {
                return nick
            }
            return ChatNameWithHats.displayName(nick: nick, hats: MucHatStore.hats(room: channel.mucContact.contactJid, nick: channel.nick, accountID: channel.mucContact.accountID))
        }
        set {}
    }
    override var avatarImage: UIImage? {
        get {
            return innerContact.avatar as UIImage?
        }
        set {}
    }
    init(_ contact: NSObject&MLContactProtocol) {
//         DDLogVerbose("Creating new ChatViewUser for MLContactProtocol: \(String(describing:contact)): \(Thread.callStackSymbols)")
        self.innerContact = ObservableKVOWrapper(contact)
        // We don't need to initialize the properties that we overrode with computed properties
        super.init(id: contact.id, name: "", isCurrentUser: contact.isSelf)

        // Forward innerContact changes as ChatViewUser changes
        innerContact.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        // isaCloud: the hats of this participant change with its presences, so its name is read again then
        if let channel = contact as? MLChannelContact {
            let room = channel.mucContact.contactJid
            NotificationCenter.default.publisher(for: NSNotification.Name(kMonalMucHatsUpdated))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    if (notification.userInfo?["room"] as? String) == room {
                        self?.objectWillChange.send()
                    }
                }
                .store(in: &subscriptions)
        }
    }
    //our parent class forces us to implement this, but it should never be called!
    required init(from decoder: Decoder) throws {
        unreachable("ChatViewUser should never be deserialized!")
    }
    public var description: String {
        return "ChatViewUser<\(String(describing:self.innerContact))>"
    }
}

//
//  SharePickerView.swift
//  shareSheet
//
//  isaCloud: the share extension asks where to send what was shared, in the same picker as "Forward…" in the app, one destination at a time.
//

import SwiftUI
import monalxmpp

//isaCloud: same pink as the app (isaCloudPink asset); the asset lives only in the app bundle, so the extension uses the value
private let shareSheetPink = Color(red: 255.0 / 255.0, green: 0.0 / 255.0, blue: 111.0 / 255.0)

//the strings of this extension are in their own table, so they do not have to travel through the app's Monal translation file
private func shareSheetString(_ key: String) -> String {
    return NSLocalizedString(key, tableName: "ShareSheet", bundle: .main, value: key, comment: "")
}

struct SharePickerView: View {
    let onSend: (MLContact, String) -> Void
    let onCancel: () -> Void
    /// what the contacts list shows, for the accounts that can send; sorted by name and then by address (as in the app)
    private let destinations: [MLContact]

    @State private var searchText = ""
    @State private var selectedKey: String?
    @State private var message = ""
    @State private var sending = false
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40

    init(initialRecipient: MLContact?, onSend: @escaping (MLContact, String) -> Void, onCancel: @escaping () -> Void) {
        self.onSend = onSend
        self.onCancel = onCancel
        //only the contacts of accounts that can send: a disabled account would keep the payload in the outbox forever
        let accounts = (DataLayer.sharedInstance().enabledAccountList() as? [[String: Any]]) ?? []
        let enabledAccountIDs = Set(accounts.compactMap { ($0["account_id"] as? NSNumber)?.intValue })
        destinations = DataLayer.sharedInstance().contactList()
            .filter { enabledAccountIDs.contains($0.accountID.intValue) }
            .filter { $0.isSelf || $0.isMuc || $0.isSubscribedTo || $0.hasOutgoingContactRequest || $0.isSubscribedFrom }
            .sorted { ($0.contactDisplayName.lowercased(), $0.contactJid.lowercased()) < ($1.contactDisplayName.lowercased(), $1.contactJid.lowercased()) }
        //a Siri intent can name the chat to send to: start with it chosen, if it is a destination we can send to
        if let recipient = initialRecipient, destinations.contains(where: { SharePickerView.key($0) == SharePickerView.key(recipient) }) {
            _selectedKey = State(initialValue: SharePickerView.key(recipient))
        } else {
            _selectedKey = State(initialValue: nil)
        }
    }

    private static func key(_ contact: MLContact) -> String {
        return "\(contact.accountID)|\(contact.contactJid)"
    }

    private func canWrite(_ contact: MLContact) -> Bool {
        return MessageForward.canWrite(isMuc: contact.isMuc, role: contact.isMuc ? DataLayer.sharedInstance().getOwnRole(inGroupOrChannel: contact) : nil)
    }

    private var shown: [MLContact] {
        guard !searchText.isEmpty else {
            return destinations
        }
        let search = searchText.lowercased()
        return destinations.filter { $0.contactJid.lowercased().contains(search) || $0.contactDisplayName.lowercased().contains(search) }
    }

    private var selectedContact: MLContact? {
        guard let selectedKey = selectedKey else {
            return nil
        }
        return destinations.first { SharePickerView.key($0) == selectedKey }
    }

    private var canSend: Bool {
        guard let contact = selectedContact else {
            return false
        }
        return canWrite(contact)
    }

    var body: some View {
        NavigationStack {
            Group {
                if destinations.isEmpty {
                    ContentUnavailableView(shareSheetString("No contacts"), systemImage: "person.2.slash")
                } else {
                    List {
                        ForEach(shown, id: \.self) { contact in
                            row(for: contact)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .overlay {
                        if shown.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                }
            }
            .navigationTitle(shareSheetString("Send to"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                messageField
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(shareSheetString("Cancel")) {
                        onCancel()
                    }
                    .disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(shareSheetString("Send")) {
                        send()
                    }
                    .tint(shareSheetPink)
                    .disabled(sending || !canSend)
                }
            }
        }
        .overlay {
            if sending {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    @ViewBuilder
    private func row(for contact: MLContact) -> some View {
        let writable = canWrite(contact)
        let isSelected = selectedKey == SharePickerView.key(contact)
        Button {
            selectedKey = isSelected ? nil : SharePickerView.key(contact)
        } label: {
            HStack(alignment: .center) {
                Image(uiImage: contact.avatar)
                    .resizable()
                    .frame(width: avatarSize, height: avatarSize, alignment: .center)
                VStack(alignment: .leading) {
                    Text(contact.contactDisplayName)
                    if !writable {
                        Text(shareSheetString("You cannot write here"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    //isaCloud: the address of a private group is a random string, meaningless to people: it is only shown in the group's details
                    if !(contact.isMuc && contact.mucType == kMucTypeGroup) {
                        Text(contact.contactJid)
                            .font(.footnote)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                    if let accountJid = HelperTools.accountJidToShow(forAccountID: contact.accountID) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.crop.circle")
                            Text(accountJid)
                        }
                        .font(.caption)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? shareSheetPink : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!writable)
        .opacity(writable ? 1 : 0.45)
    }

    private var messageField: some View {
        VStack(spacing: 0) {
            Divider()
            TextField(shareSheetString("Message (optional)"), text: $message, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func send() {
        guard !sending, let contact = selectedContact, canWrite(contact) else {
            return
        }
        //the extension itself dismisses the sheet once the payloads are queued: from here on, only wait
        sending = true
        onSend(contact, message)
    }
}

/// the Objective-C entry point of the extension: a hosting controller with the picker, the send and cancel callbacks go back to the extension
@objc(SharePickerBridge)
final class SharePickerBridge: NSObject {
    @objc(makeViewControllerWithSend:andCancel:initialRecipient:)
    static func makeViewController(send: @escaping (MLContact, String) -> Void, cancel: @escaping () -> Void, initialRecipient: MLContact?) -> UIViewController {
        let picker = SharePickerView(initialRecipient: initialRecipient, onSend: send, onCancel: cancel)
        return UIHostingController(rootView: picker)
    }
}

//
//  MessageForwardPicker.swift
//  Monal
//
//  isaCloud: the sheet of "Forward…": the contacts, groups, channels and the person's own notes to choose from (up to MessageForward.maxDestinations).
//

import SwiftUI

struct MessageForwardPicker: View {
    let onForward: ([MLContact]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var chosen: [String] = []
    private let destinations: [MLContact]

    init(onForward: @escaping ([MLContact]) -> Void) {
        self.onForward = onForward
        //what the contacts list shows, plus the notes to self; sorted by name
        let all = (DataLayer.sharedInstance().contactList() as? [MLContact]) ?? []
        destinations = all
            .filter { $0.isSelf || $0.isMuc || $0.isSubscribedTo || $0.hasOutgoingContactRequest || $0.isSubscribedFrom }
            .sorted { ($0.contactDisplayName.lowercased(), $0.contactJid.lowercased()) < ($1.contactDisplayName.lowercased(), $1.contactJid.lowercased()) }
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

    var body: some View {
        NavigationStack {
            List {
                ForEach(shown, id: \.self) { contact in
                    let key = MessageForwardPicker.key(contact)
                    let writable = canWrite(contact)
                    let isChosen = chosen.contains(key)
                    let full = !isChosen && chosen.count >= MessageForward.maxDestinations
                    Button {
                        chosen = MessageForward.toggled(chosen, key)
                    } label: {
                        HStack {
                            ContactEntry(contact: contact, additionalContent: {
                                if !writable {
                                    Text("You cannot write here")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }).showingAccount(of: contact)
                            Spacer()
                            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isChosen ? Color("isaCloudPink") : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!writable || full)
                    .opacity(writable && !full ? 1 : 0.45)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(Text("Forward to"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text("Up to \(MessageForward.maxDestinations) chats at once.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Forward" : "Forward (\(chosen.count))") {
                        let contacts = destinations.filter { chosen.contains(MessageForwardPicker.key($0)) }
                        //forwarded first: closing the sheet takes the text of the message away from the chat
                        onForward(contacts)
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                    .tint(Color("isaCloudPink"))
                }
            }
        }
    }
}

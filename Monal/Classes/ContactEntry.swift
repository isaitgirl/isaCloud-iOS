//
//  ContactEntry.swift
//  Monal
//
//  Created by Friedrich Altheide on 28.11.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

struct ContactEntry<AdditionalContent: View>: View {
    let selfnotesPrefix: Bool
    let fallback: String?
    @ViewBuilder let additionalContent: () -> AdditionalContent
    @ScaledMetric(relativeTo:.body) private var size40px: CGFloat = 40
    
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    //isaCloud: the jid of the account this contact belongs to, shown under the contact's own jid (nil: not shown)
    private var accountJid: String? = nil
    //isaCloud: state labels (participation state of groups and channels, "Archived") on the account line, only shown in the contacts lists (see showingArchivedLabel)
    private var showsArchivedLabel = false
    
    init(contact:MLContact, selfnotesPrefix: Bool = true, fallback: String? = nil) where AdditionalContent == EmptyView {
        self.init(contact:contact, selfnotesPrefix:selfnotesPrefix, fallback:fallback, additionalContent:{ EmptyView() })
    }
    
    init(contact:MLContact, fallback: String?) where AdditionalContent == EmptyView {
        self.init(contact:contact, selfnotesPrefix:true, fallback:fallback, additionalContent:{ EmptyView() })
    }
    
    init(contact:MLContact, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.init(contact:contact, selfnotesPrefix:true, additionalContent:additionalContent)
    }
    
    init(contact:MLContact, fallback: String?, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.init(contact:contact, selfnotesPrefix:true, fallback:fallback, additionalContent:additionalContent)
    }
    
    init(contact:MLContact, selfnotesPrefix: Bool, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.init(contact:contact, selfnotesPrefix:selfnotesPrefix, fallback:nil, additionalContent:additionalContent)
    }
    
    init(contact:MLContact, selfnotesPrefix: Bool, fallback: String?, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        //create our own observable object to not trigger rendering for changes, not observed by us, but by an outer view
        _contact = StateObject(wrappedValue: ObservableKVOWrapper<MLContact>(contact))
        self.selfnotesPrefix = selfnotesPrefix
        self.fallback = fallback
        self.additionalContent = additionalContent
    }
    
    var body:some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                Image(uiImage: contact.avatar)
                    .resizable()
                    .frame(width: size40px, height: size40px, alignment: .center)
                VStack(alignment: .leading) {
                    if selfnotesPrefix {
                        // use the if to make sure this view gets updated if the contact display name changes
                        // (the condition is never false, because contactDisplayName can not be nil)
                        if (contact.contactDisplayName as String?) != nil {
                            Text(contact.obj.contactDisplayName(withFallback:fallback))
                        }
                    } else {
                        // use the if to make sure this view gets updated if the contact display name changes
                        // (the condition is never false, because contactDisplayNameWithoutSelfnotesPrefix can not be nil)
                        if (contact.contactDisplayNameWithoutSelfnotesPrefix as String?) != nil {
                            Text(contact.obj.contactDisplayName(withFallback:fallback, andSelfnotesPrefix:false))
                        }
                    }
                    additionalContent()
                    //isaCloud: the address of a private group is a random string, meaningless to people: it is only shown in the group's details
                    if !(contact.isMuc && contact.mucType == kMucTypeGroup) {
                        //isaCloud: in the contacts lists the address gets one full line and is cut in the middle instead of wrapping
                        Text(contact.contactJid as String)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .font(.footnote)
                            .lineLimit(showsArchivedLabel ? 1 : nil)
                            .truncationMode(.middle)
                    }
                    //isaCloud: one line under the address: the account (more than one account only), then the state labels (contacts lists only)
                    if accountJid != nil || (showsArchivedLabel && hasListLabel) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let accountJid = accountJid {
                                //the account gives way (cut in the middle) when the line is too short, the labels never do
                                HStack(spacing: 3) {
                                    Image(systemName: "person.crop.circle")
                                    Text(accountJid)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .font(.caption)
                            }
                            if showsArchivedLabel {
                                stateLabels
                            }
                        }
                    }
                }
            }
        }
    }
    
    //isaCloud: participation state of groups and channels and "Archived", side by side, never cut
    @ViewBuilder
    private var stateLabels: some View {
        if isMucEntry && mucTypeOfEntry == kMucTypeChannel {
            if isParticipating {
                stateLabel(icon: "checkmark", text: "Participant", color: .accentColor)
            } else {
                stateLabel(icon: "person.badge.plus", text: "Join", color: Color(UIColor.secondaryLabel))
            }
        }
        if isMucEntry && mucTypeOfEntry == kMucTypeGroup && !isParticipating {
            stateLabel(icon: "xmark.circle.fill", text: "Not participating", color: Color(UIColor.secondaryLabel))
        }
        if isArchivedEntry {
            //icon (box with an arrow down) makes the label stand out; grey like the other state labels
            stateLabel(icon: "tray.and.arrow.down.fill", text: "Archived", color: Color(UIColor.secondaryLabel))
        }
    }
    
    //(baseline alignment: the archive symbol's arrow sticks out above the tray, so centering pushed the tray down and the text looked too high)
    private func stateLabel(icon: String, text: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .foregroundColor(color)
    }
    
    //isaCloud: with more than one account enabled, the contacts list tells which account each contact belongs to
    func showingAccount(of contact: MLContact) -> Self {
        var copy = self
        copy.accountJid = HelperTools.accountJidToShow(forAccountID: contact.accountID)
        return copy
    }
    
    //isaCloud: the contacts lists show the participation state of groups and channels, and mark archived groups, channels and contacts with "Archived"
    func showingArchivedLabel() -> Self {
        var copy = self
        copy.showsArchivedLabel = true
        return copy
    }
    
    //isaCloud: the wrapper's dynamic members are read with an explicit type (see ObservableKVOWrapper)
    private var isArchivedEntry: Bool {
        let archived: Bool = contact.isArchived
        return archived
    }

    private var isMucEntry: Bool {
        let muc: Bool = contact.isMuc
        return muc
    }

    //isaCloud: true when we participate in the group or channel (it is in our favorites)
    private var isParticipating: Bool {
        let participating: Bool = contact.isInRoster
        return participating
    }

    private var mucTypeOfEntry: String? {
        contact.obj.mucType
    }

    //isaCloud: whether the row has any state label (channels always do: participant or join)
    private var hasListLabel: Bool {
        (isMucEntry && mucTypeOfEntry == kMucTypeChannel) || (isMucEntry && mucTypeOfEntry == kMucTypeGroup && !isParticipating) || isArchivedEntry
    }
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(0))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(1))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(2))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(3))
}

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
    //isaCloud: a small "Archived" label under the jid, only shown in the contacts lists (see showingArchivedLabel)
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
                        Text(contact.contactJid as String)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .font(.footnote)
                    }
                    if let accountJid = accountJid {
                        HStack(spacing: 3) {
                            Image(systemName: "person.crop.circle")
                            Text(accountJid)
                        }
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .font(.caption)
                    }
                    if showsArchivedLabel && isArchivedEntry {
                        //isaCloud: icon (box with an arrow down) and the accent color make the label stand out; below the account, aligned with it
                        //(an HStack like the account row: a Label inside a List gets a wide icon column)
                        //(baseline alignment: this symbol's arrow sticks out above the tray, so centering pushed the tray down and the text looked too high)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Image(systemName: "tray.and.arrow.down.fill")
                            Text("Archived")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }
    
    //isaCloud: with more than one account enabled, the contacts list tells which account each contact belongs to
    func showingAccount(of contact: MLContact) -> Self {
        var copy = self
        copy.accountJid = HelperTools.accountJidToShow(forAccountID: contact.accountID)
        return copy
    }
    
    //isaCloud: the contacts lists mark archived groups and channels (and contacts) with "Archived"
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

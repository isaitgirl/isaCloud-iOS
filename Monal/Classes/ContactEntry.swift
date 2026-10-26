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
                    Text(contact.contactJid as String)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .font(.footnote)
                    if let accountJid = accountJid {
                        HStack(spacing: 3) {
                            Image(systemName: "person.crop.circle")
                            Text(accountJid)
                        }
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .font(.caption)
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

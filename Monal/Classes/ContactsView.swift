//
//  ContactsView.swift
//  Monal
//
//  Created by Matthew Fennell <matthew@fennell.dev> on 10/08/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

struct ContactViewEntry: View {
    private let contact: MLContact
    @Binding private var selectedContactForContactDetails: MLContact?
    private let dismissWithContact: (MLContact) -> ()

    @State private var shouldPresentRemoveContactAlert: Bool = false

    private var removeContactButtonText: LocalizedStringKey {
        if (!isDeletable) {
            return "Cannot delete notes to self"
        }
        return contact.isMuc ? "Remove Conversation" : "Remove Contact"
    }

    private var removeContactConfirmationTitle: LocalizedStringKey {
        contact.isMuc ? "Leave this converstion?" : "Remove \(contact.contactJid) from contacts?"
    }

    private var removeContactConfirmationDetail: LocalizedStringKey {
        contact.isMuc ? "" : "They will no longer see when you are online. They may not be able to access your encryption keys."
    }

    private var isDeletable: Bool {
        //we don't need the kvo observer here, because the selfchat status won't ever change for a given MLContact singleton
        !contact.isSelf
    }

    init (contact: MLContact, selectedContactForContactDetails: Binding<MLContact?>, dismissWithContact: @escaping (MLContact) -> ()) {
        self.contact = contact
        self._selectedContactForContactDetails = selectedContactForContactDetails
        self.dismissWithContact = dismissWithContact
    }

    var body: some View {
        // Apple's list dividers only extend as far left as the left-most text in the view.
        // This means, by default, that the dividers on this screen would not extend all the way to the left of the view.
        // This combination of HStack with spacing of 0, and empty text at the left of the view, is a workaround to override this behaviour.
        // See https://stackoverflow.com/a/76698909
        HStack(spacing: 0) {
            Text("").frame(maxWidth: 0)
            Button(action: { dismissWithContact(contact) }) {
                HStack {
                    ContactEntry(contact: contact).showingAccount(of: contact)
                    Spacer()
                    Button {
                        selectedContactForContactDetails = contact
                    } label: {
                        Image(systemName: "info.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Open contact details")
                }
            }
        }
        .swipeActions(allowsFullSwipe: false) {
            // We do not use a Button with destructive role here as we would like to display the confirmation dialog first.
            // A destructive role would dismiss the row immediately, without waiting for the confirmation.
            Button(removeContactButtonText) {
                shouldPresentRemoveContactAlert = true
            }
            .tint(isDeletable ? .red : .gray)
            .disabled(!isDeletable)
        }
        .confirmationDialog(removeContactConfirmationTitle, isPresented: $shouldPresentRemoveContactAlert, titleVisibility: .visible) {
            Button(role: .cancel) {} label: {
                Text("No")
            }
            Button(role: .destructive) {
                MLXMPPManager.sharedInstance().remove(contact)
            } label: {
                Text("Yes")
            }
        } message: {
            Text(removeContactConfirmationDetail)
        }
    }
}

//isaCloud: one pending contact request: who it is and what to do with it
struct ContactRequestRow: View {
    let contact: MLContact

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContactEntry(contact: contact).showingAccount(of: contact)
            HStack(spacing: 8) {
                //accepting does not leave this screen, so several requests can be answered in a row
                Button {
                    MLXMPPManager.sharedInstance().add(contact)
                } label: {
                    Text("Accept").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("isaCloudPink"))

                Button {
                    MLXMPPManager.sharedInstance().remove(contact)
                } label: {
                    Text("Decline").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color("isaCloudPink"))

                Menu {
                    Button {
                        let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                        appDelegate.openChat(of: contact)
                    } label: {
                        Label("Open Conversation", systemImage: "text.bubble")
                    }
                    Button(role: .destructive) {
                        // deny the request and block the contact
                        MLXMPPManager.sharedInstance().remove(contact)
                        MLXMPPManager.sharedInstance().block(true, contact: contact)
                    } label: {
                        Label("Decline and Block", systemImage: "person.crop.circle.badge.xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .frame(width: 36, height: 32)
                }
                .tint(Color("isaCloudPink"))
                .accessibilityLabel("More options")
            }
        }
        .padding(.vertical, 4)
    }
}

//isaCloud: filter of the segmented control under the search bar
enum ContactsFilter: Int, CaseIterable, Identifiable {
    case all, contacts, groups, channels
    var id: Int { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .all: return "Filter: all"
        case .contacts: return "Filter: contacts"
        case .groups: return "Filter: groups"
        case .channels: return "Filter: channels"
        }
    }
}

struct ContactsView: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var contacts: Contacts
    @State private var searchText: String = ""
    @State private var filter: ContactsFilter = .all
    @State private var showingAddContact = false
    @State private var showingCreateGroup = false
    @State private var showingPublicChannels = false
    @State private var showingAddMenu = false          //isaCloud (TEST): the popover of the "+" button
    @State private var showingInvitation = false       //isaCloud: invite someone (moved here from the add contact screen)
    @State private var showingQRCodeScanner = false    //isaCloud: add via QR code (moved here from the add contact screen)
    @State private var selectedContactForContactDetails: MLContact? = nil
    private let delegate: SheetDismisserProtocol
    private let dismissWithContact: (MLContact) -> ()

    init(contacts: Contacts, delegate: SheetDismisserProtocol, dismissWithContact: @escaping (MLContact) -> ()) {
        self.contacts = contacts
        self.delegate = delegate
        self.dismissWithContact = dismissWithContact
    }

    private static func isNotSelfChatContact(contact: MLContact) -> Bool {
        return !contact.isSelf && ContactsView.shouldDisplayContact(contact)
    }
    
    private static func shouldDisplayContact(_ contact: MLContact) -> Bool {
        return contact.isSubscribedTo || contact.hasOutgoingContactRequest || contact.isSubscribedFrom
    }

    private var contactList: [MLContact] {
        // we want to display an empty contact list if we only have a self-chat
        // that way the image and text explaining how to add contacts will be visible
        let withoutSelfChats = contacts.contacts.filter(ContactsView.isNotSelfChatContact)
        if withoutSelfChats.count == 0 {
            return []
        }
        return contacts.contacts
            .filter(ContactsView.shouldDisplayContact)
            .sorted { ContactsView.sortingCriteria($0) < ContactsView.sortingCriteria($1) }
    }

    private func matchesFilter(_ contact: MLContact) -> Bool {
        switch filter {
        case .all: return true
        case .contacts: return !contact.isMuc
        case .groups: return contact.isMuc && contact.mucType == kMucTypeGroup
        case .channels: return contact.isMuc && contact.mucType == kMucTypeChannel
        }
    }

    //isaCloud: requests are shown for "all" and "contacts", and not while searching
    private var showRequests: Bool {
        return !contacts.requests.isEmpty && searchText.isEmpty && (filter == .all || filter == .contacts)
    }

    private var searchResults: [MLContact] {
        return contactList.filter { matchesFilter($0) && (searchText.isEmpty || searchMatchesContact(contact: $0, search: searchText)) }
    }

    private static func sortingCriteria(_ contact: MLContact) -> (String, String) {
        return (contact.contactDisplayName.lowercased(), contact.contactJid.lowercased())
    }

    private func searchMatchesContact(contact: MLContact, search: String) -> Bool {
        let jid = contact.contactJid.lowercased()
        let name = contact.contactDisplayName.lowercased()
        let search = search.lowercased()

        return jid.contains(search) || name.contains(search)
    }

    private func addMenuRow(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            showingAddMenu = false
            //let the popover go away before opening the next screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(Color("isaCloudPink"))
                    .frame(width: 30)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .font(.callout)     //one point under the body text (16 pt instead of 17 pt), still following the text size of the system
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        List {
            //isaCloud: the contact requests are at the top of the list, where they cannot be missed
            if showRequests {
                Section {
                    ForEach(contacts.requests, id: \.self) { request in
                        ContactRequestRow(contact: request)
                    }
                } header: {
                    Text("Contact requests (\(contacts.requests.count))")
                } footer: {
                    Text("Allowing someone to add you as a contact lets them see your profile picture and when you are online.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(searchResults, id: \.self) { contact in
                ContactViewEntry(contact: contact, selectedContactForContactDetails: $selectedContactForContactDetails, dismissWithContact: dismissWithContact)
            }
        }
        .animation(.default, value: contactList)
        .navigationTitle(Text("Contacts"))
        .navigationBarTitleDisplayMode(.inline) //isaCloud: inline, like the title of the home screen
        .safeAreaInset(edge: .top, spacing: 0) {
            //isaCloud: one list for contacts, groups and channels, switched by this control
            Picker("Filter", selection: $filter) {
                ForEach(ContactsFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .listStyle(.plain)
        .applyClosure { view in
            if contactList.isEmpty {
                view
            } else {
                view.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        .overlay {
            if contactList.isEmpty && contacts.requests.isEmpty {
                ZStack {
                    Color.contacts
                    ContentUnavailableShimView("You need friends for this ride", image: colorScheme == .dark ? .friendsDark : .friends, description: Text("Add new contacts with the + button above. Your friends will pop up here when they can talk"))
                }
            } else if searchResults.isEmpty && !showRequests {
                ZStack {
                    Color.contacts
                    ContentUnavailableShimView.search(text:searchText)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                //isaCloud (TEST): a popover with a width of its own instead of the system Menu, whose width the system decides (labels broke in two lines)
                Button {
                    showingAddMenu = true
                } label: {
                    //isaCloud: no badge here: the pending contact requests are at the top of this list
                    Image(systemName: "plus")
                }
                .tint(Color("isaCloudPink"))
                .accessibilityLabel("Add contact, group or channel")
                .popover(isPresented: $showingAddMenu) {
                    VStack(alignment: .leading, spacing: 0) {
                        addMenuRow("Add New Contact", icon: "person.fill.badge.plus") { showingAddContact = true }
                        Divider()
                        //isaCloud: the invitation and the QR code scanner used to be icons in the toolbar of the add contact screen
                        addMenuRow("Invite to isaCloud", icon: "square.and.arrow.up") { showingInvitation = true }
                        Divider()
                        addMenuRow("Add via QR code", icon: "camera.fill") { showingQRCodeScanner = true }
                        Divider()
                        addMenuRow("Create contact group", icon: "person.3.fill") { showingCreateGroup = true }
                        Divider()
                        addMenuRow("List channels", icon: "number") { showingPublicChannels = true }
                    }
                    .frame(width: 310)
                    .padding(.vertical, 6)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .navigationDestination(isPresented: $showingAddContact) {
            AddContactMenu(delegate: SheetDismisserProtocol(), dismissWithNewContact: dismissWithContact)
        }
        .navigationDestination(isPresented: $showingInvitation) {
            InvitationMenu()
        }
        .sheet(isPresented: $showingQRCodeScanner) {
            NavigationStack {
                MLQRCodeScanner(handleClose: {
                    self.showingQRCodeScanner = false
                })
                .navigationTitle(Text("QR-Code Scanner"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(content: {
                    ToolbarItem(placement: .navigationBarLeading, content: {
                        Button(action: {
                            self.showingQRCodeScanner = false
                        }, label: {
                            Text("Close")
                        })
                    })
                })
            }
        }
        .navigationDestination(isPresented: $showingCreateGroup) {
            CreateGroupMenu(delegate: SheetDismisserProtocol())
        }
        .navigationDestination(isPresented: $showingPublicChannels) {
            PublicChannelsView(dismissWithContact: dismissWithContact)
        }
        .sheet(item: $selectedContactForContactDetails) { selectedContact in
            AnyView(AddTopLevelNavigation(withDelegate: delegate, to: ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(selectedContact))))
        }
    }
}

//isaCloud: creates an invitation to the server of an account (XEP-0401) and shows it as a QR code and a link to share. It used to be an
//icon in the toolbar of the add contact screen; now it is an item of the "+" menu of the contacts.
struct InvitationMenu: View {
    @State private var accounts: [xmpp]
    @State private var selectedAccount: Int = 0
    @State private var result: [String:AnyObject]? = nil
    @State private var errorMessage: String? = nil
    @State private var isCreating = false

    init() {
        //only the accounts whose server can create invitations
        self._accounts = State(wrappedValue: (MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]).filter {
            $0.connectionProperties.discoveredAdhocCommands["urn:xmpp:invite#invite"] != nil
        })
    }

    private func createInvitation() {
        guard accounts.indices.contains(selectedAccount) else {
            return
        }
        let account = accounts[selectedAccount]
        let host = HelperTools.splitJid(account.connectionProperties.identity.jid)["host"] ?? ""
        DDLogVerbose("Trying to create invitation for: \(host)")
        result = nil
        errorMessage = nil
        isCreating = true
        account.createInvitation(completion: {
            let creationResult = $0 as! [String:AnyObject]
            DispatchQueue.main.async {
                isCreating = false
                DDLogVerbose("Got invitation result: \(String(describing:creationResult))")
                if creationResult["success"] as? Bool == true {
                    result = creationResult
                } else {
                    errorMessage = creationResult["error"] as? String ?? ""
                }
            }
        })
    }

    var body: some View {
        Form {
            if accounts.isEmpty {
                Text("None of your connected accounts can create invitations.")
                    .foregroundColor(.secondary)
            } else {
                if accounts.count > 1 {
                    Section {
                        Picker("Use account", selection: $selectedAccount) {
                            ForEach(Array(accounts.enumerated()), id: \.element) { idx, account in
                                Text(account.connectionProperties.identity.jid).tag(idx)
                            }
                        }
                        .onChange(of: selectedAccount) {
                            createInvitation()
                        }
                    }
                }
                Section {
                    if isCreating {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let result = result, let landing = result["landing"] as? String {
                        VStack {
                            Image(uiImage: createQrCode(value: landing))
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .aspectRatio(1, contentMode: .fit)
                            if let expires = result["expires"] as? Date {
                                Text("This invitation will expire on \(expires.formatted(date:.numeric, time:.shortened))")
                                    .font(.footnote)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if let url = URL(string: landing) {
                            ShareLink("Share invitation link", item: url)
                        }
                    } else if let errorMessage = errorMessage {
                        Text("Failed to create invitation")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationBarTitle(Text("Invite to isaCloud"), displayMode: .inline)
        .onAppear {
            if result == nil && !isCreating {
                createInvitation()
            }
        }
    }
}

class Contacts: ObservableObject {
    @Published var contacts: Set<MLContact>
    @Published var requestCount: Int
    @Published var requests: [MLContact]       //isaCloud: the pending contact requests, shown at the top of the list
    private var subscriptions: Set<AnyCancellable> = Set()

    init() {
        self.contacts = Set(DataLayer.sharedInstance().contactList())
        let requests = DataLayer.sharedInstance().allContactRequests() as! [MLContact]
        self.requests = requests
        self.requestCount = requests.count
        subscriptions = [
            NotificationCenter.default.publisher(for: NSNotification.Name(kMonalContactRefresh))
                .receive(on: DispatchQueue.main)
                .sink() { _ in self.refreshContacts() },
            NotificationCenter.default.publisher(for: NSNotification.Name(kMonalContactRemoved))
                .receive(on: DispatchQueue.main)
                .sink() { _ in self.refreshContacts() },
        ]
    }
    
    private func refreshContacts() {
        self.contacts = Set(DataLayer.sharedInstance().contactList())
        let requests = DataLayer.sharedInstance().allContactRequests() as! [MLContact]
        self.requests = requests
        self.requestCount = requests.count
    }
}

//
//  AddContactMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import MobileCoreServices
import UniformTypeIdentifiers

struct AddContactMenu: View {
    var delegate: SheetDismisserProtocol
    static private let jidFaultyPattern = "^([^@]+@)?.+(\\..{2,})?$"

    @State private var enabledAccounts: [xmpp]
    @State private var selectedAccount: Int
    @State private var scannedFingerprints: [NSNumber:Data]?
    @State private var importScannedFingerprints: Bool = false
    @State private var toAdd: String

    @State private var showInvitationError = false
    @State private var showAlert = false
    // note: dismissLabel is not accessed but defined at the .alert() section
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))

    @StateObject private var overlay = LoadingOverlayState()

    @State private var success = false
    @State private var newContact : MLContact?

    @State private var isEditingJid = false

    private let dismissWithNewContact: (MLContact) -> ()
    private let preauthToken: String?

    init(delegate: SheetDismisserProtocol, dismissWithNewContact: @escaping (MLContact) -> (), prefillJid: String = "", preauthToken:String? = nil, prefillAccount:xmpp? = nil, omemoFingerprints: [NSNumber:Data]? = nil) {
        self.delegate = delegate
        self.dismissWithNewContact = dismissWithNewContact
        //self.toAdd = State(wrappedValue: prefillJid)
        self.toAdd = prefillJid
        self.preauthToken = preauthToken
        //only display omemo ui part if there are any fingerprints (the checks below test for nil, not for 0)
        if omemoFingerprints?.count ?? 0 > 0 {
            self.scannedFingerprints = omemoFingerprints
        }
        
        let enabledAccounts = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
        self.enabledAccounts = enabledAccounts
        self.selectedAccount = enabledAccounts.first != nil ? 0 : -1;
        if let prefillAccount = prefillAccount {
            for index in enabledAccounts.indices {
                if enabledAccounts[index].accountID.isEqual(to:prefillAccount.accountID) {
                    self.selectedAccount = index
                }
            }
        }
    }
    
    // FIXME duplicate code from WelcomeLogIn.swift, maybe move to SwiftuiHelpers
    private var toAddEmptyAlert: Bool {
        alertPrompt.title = Text("No Empty Values!")
        alertPrompt.message = Text("Please make sure you have entered a valid jid.")
        return toAddEmpty
    }

    private var toAddInvalidAlert: Bool {
        alertPrompt.title = Text("Invalid Credentials!")
        alertPrompt.message = Text("The jid you want to add should be in in the format user@domain.tld.")
        return toAddInvalid
    }
    
    private func errorAlert(title: Text, message: Text = Text("")) {
        alertPrompt.title = title
        alertPrompt.message = message
        showAlert = true
    }
    
    private func successAlert(title: Text, message: Text) {
        alertPrompt.title = title
        alertPrompt.message = message
        self.success = true // < dismiss entire view on close
        showAlert = true
    }
    
    private var toAddEmpty: Bool {
        return toAdd.isEmpty
    }
    
    private var toAddInvalid: Bool {
        return toAdd.range(of: AddContactMenu.jidFaultyPattern, options:.regularExpression) == nil
    }

    func trustFingerprints(_ fingerprints:[NSNumber:Data]?, for jid:String, on account:xmpp) {
        //we don't untrust other devices not included in here, because conversations only exports its own fingerprint
        if let fingerprints = fingerprints {
            for (deviceId, fingerprint) in fingerprints {
                let address = SignalAddress.init(name:jid, deviceId:deviceId.int32Value)
                let knownDevices = Array(account.omemo.knownDevices(forAddressName:jid))
                if !knownDevices.contains(deviceId) {
                    account.omemo.addIdentityManually(address, identityKey:fingerprint)
                    assert(account.omemo.getIdentityFor(address) == fingerprint, "The stored and created fingerprint should match")
                }
                //trust device/fingerprint if fingerprints match
                let knownFingerprintHex = HelperTools.signalHexKey(with:account.omemo.getIdentityFor(address))
                let addedFingerprintHex = HelperTools.signalHexKey(with:fingerprint)
                if knownFingerprintHex.uppercased() == addedFingerprintHex.uppercased() {
                    account.omemo.updateTrust(true, for:address)
                }
            }
        }
    }
    
    func addJid(jid: String) {
        let account = self.enabledAccounts[selectedAccount]
        let contact = MLContact.createContact(fromJid: jid, andAccountID: account.accountID)
        if contact.isInRoster {
            self.newContact = contact
            //import omemo fingerprints as manually trusted, if requested
            trustFingerprints(self.importScannedFingerprints ? self.scannedFingerprints : [:], for:jid, on:account)
            //only alert of already known contact if we did not import the omemo fingerprints
            if !self.importScannedFingerprints || self.scannedFingerprints?.count ?? 0 == 0 {
                if self.enabledAccounts.count > 1 {
                    self.success = true
                    successAlert(title: Text("Already present"), message: Text("This contact is already in the contact list of the selected account"))
                } else {
                    self.success = true
                    successAlert(title: Text("Already present"), message: Text("This contact is already in your contact list"))
                }
            }
            return
        }
        showPromisingLoadingOverlay(overlay, headline:"Adding...", description:"") {
            account.checkJidType(jid)
        }.done { type in
            let type = type as! String
            if type == "account" {
                let contact = MLContact.createContact(fromJid: jid, andAccountID: account.accountID)
                self.newContact = contact
                MLXMPPManager.sharedInstance().add(contact, withPreauthToken:preauthToken)
                //import omemo fingerprints as manually trusted, if requested
                trustFingerprints(self.importScannedFingerprints ? self.scannedFingerprints : [:], for:jid, on:account)
                successAlert(title: Text("Permission Requested"), message: Text("The new contact will be added to your contacts list when the person you've added has approved your request."))
            } else if type == "muc" {
                showPromisingLoadingOverlay(overlay, headlineView:Text("Adding Group/Channel..."), descriptionView:Text("")) {
                    promisifyMucAction(account:account, mucJid:jid) {
                        account.joinMuc(jid)
                    }
                }.done { _ in
                    self.newContact = MLContact.createContact(fromJid: jid, andAccountID: account.accountID)
                    successAlert(title: Text("Success!"), message: Text("Successfully joined group/channel \(jid)!"))
                }.catch { error in
                    errorAlert(title: Text("Error entering group/channel!"), message: Text(error.localizedDescription))
                }
            }
        }.catch { error in
            errorAlert(title: Text("Error"), message: Text(error.localizedDescription))
        }
    }

    var body: some View {
        let account = self.enabledAccounts[selectedAccount]
        let splitJid = HelperTools.splitJid(account.connectionProperties.identity.jid)
        Form {
            if enabledAccounts.isEmpty {
                Text("Please make sure at least one account has connected before trying to add a contact or channel.")
                    .foregroundColor(.secondary)
            }
            else
            {
                //isaCloud: the pending contact requests are shown at the top of the contacts list (ContactsView), not here
                
                Section(header:Text("Contact and Group/Channel Jids are usually in the format: name@domain.tld")) {
                    if enabledAccounts.count > 1 {
                        Picker("Use account", selection: $selectedAccount) {
                            ForEach(Array(self.enabledAccounts.enumerated()), id: \.element) { idx, account in
                                Text(account.connectionProperties.identity.jid).tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    TextField(NSLocalizedString("Contact-, Group- or Channel-Jid", comment: "placeholder when adding jid"), text: $toAdd, onEditingChanged: { isEditingJid = $0 })
                        .textInputAutocapitalization(.never)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .addClearButton(isEditing: isEditingJid, text:$toAdd)
                        .disabled(scannedFingerprints != nil)
                        .foregroundColor(scannedFingerprints != nil ? .secondary : .primary)
                        .onChange(of: toAdd) {
                            toAdd = toAdd.replacingOccurrences(of: " ", with: "")
                        }

                    if scannedFingerprints != nil && scannedFingerprints!.count > 0 {
                        Section(header: Text("A contact was scanned through the QR code scanner")) {
                            Toggle(isOn: $importScannedFingerprints) {
                                Text("Import and trust OMEMO fingerprints from QR code")
                            }
                        }
                    }
                    
                    if scannedFingerprints != nil {
                        Button(action: {
                            toAdd = ""
                            importScannedFingerprints = true
                            scannedFingerprints = nil
                        }, label: {
                            Text("Clear scanned contact")
                                .foregroundColor(.red)
                        })
                    }
                    
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            showAlert = toAddEmptyAlert || toAddInvalidAlert

                            if !showAlert {
                                let jidComponents = HelperTools.splitJid(toAdd)
                                if jidComponents["host"] == nil || jidComponents["host"]!.isEmpty {
                                    errorAlert(title: Text("Error"), message: Text("Something went wrong while parsing your input..."))
                                    showAlert = true
                                    return
                                }
                                // use the canonized jid from now on (lowercased, resource removed etc.)
                                addJid(jid: jidComponents["user"]!)
                            }
                        }) {
                            scannedFingerprints == nil ? Text("Add") : Text("Add scanned contact")
                        }
                        .disabled(toAddEmpty || toAddInvalid)
                        .buttonStyle(MonalProminentButtonStyle())
                    }
                }
            }
        }
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton:.default(Text("Close"), action: {
                showAlert = false
                if self.success == true {
                    if self.newContact != nil {
                        self.dismissWithNewContact(newContact!)
                    } else {
                        self.delegate.dismiss()
                    }
                }
            }))
        }
        //isaCloud: creating an invitation and scanning a QR code moved to the "+" menu of the contacts (ContactsView), under the add button
        .navigationBarTitle(Text("Add Contact or Channel"), displayMode: .inline)
        .addLoadingOverlay(overlay)
    }
}

struct AddContactMenu_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AddContactMenu(delegate: delegate, dismissWithNewContact: { c in
        })
    }
}

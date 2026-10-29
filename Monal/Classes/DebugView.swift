//
//  LogView.swift
//  Monal
//
//  Created by Zain Ashraf on 3/23/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

class DebugDefaultDB: ObservableObject {
    @defaultsDB("udpLoggerEnabled")
    var udpLoggerEnabled: Bool
    
    @defaultsDB("udpLoggerPort")
    var udpLoggerPort: String
    
    @defaultsDB("udpLoggerHostname")
    var udpLoggerHostname: String
    
    @defaultsDB("udpLoggerKey")
    var udpLoggerKey: String
    
    @defaultsDB("hasCompletedOnboarding")
    var hasCompletedOnboarding: Bool
    
    @defaultsDB("showNewChatView")
    var showNewChatView: Bool
    
    @defaultsDB("debugDtmfSending")
    var debugDtmfSending: Bool
    
    @defaultsDB("debugNSNotifications")
    var debugNSNotifications: Bool
}

struct LogFilesView: View {
    @State private var sortedLogFileInfos: [DDLogFileInfo] = []
    @State private var showShareSheet:Bool = false
    @State private var fileURL: URL?
    @State private var showingDBExportFailedAlert = false
    //isaCloud: importing a database (the file service can not write to the root of the app group container, see HelperTools)
    @State private var showDBImporter = false
    @State private var showingDBImportDoneAlert = false
    @State private var showingDBImportFailedAlert = false
    @State private var showingAvatarResetDoneAlert = false
    
    func refreshSortedLogfiles() {
        if let sortedLogFileInfos = HelperTools.fileLogger?.logFileManager.sortedLogFileInfos {
            self.sortedLogFileInfos = sortedLogFileInfos
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            refreshSortedLogfiles()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("This can be used to export logfiles.\n[Learn how to read them](https://github.com/monal-im/Monal/wiki/Introduction-to-Monal-Logging#view-the-log).")
            List {
                Section(header: Text("Logfiles")) {
                    ForEach(sortedLogFileInfos, id: \.self) { logFileInfo in
                        Button(logFileInfo.fileName) {
                            self.fileURL = HelperTools.compressFile(atPath:logFileInfo.filePath, withLevel:9)
                        }
                    }
                }
                Section(header: Text("Database Files")) {
                    Button("Main Database") {
                        if let dbFile = DataLayer.sharedInstance().exportDB() {
                            self.fileURL = HelperTools.compressFile(atPath:dbFile, withLevel:4)
                        } else {
                            showingDBExportFailedAlert = true
                        }
                    }
                    Button("IPC Database") {
                        if let dbFile = HelperTools.exportIPCDatabase() {
                            self.fileURL = HelperTools.compressFile(atPath:dbFile, withLevel:4)
                        } else {
                            showingDBExportFailedAlert = true
                        }
                    }
                    //isaCloud: replaces the main database with a file chosen here; it is applied when the app is opened again
                    Button("Import Database…") {
                        showDBImporter = true
                    }
                }
                Section(header: Text("Caches")) {
                    //isaCloud: the cached avatars live outside the database; this makes the app download them again (useful after
                    //importing a database, which brings the hashes but not the images)
                    Button("Reset Avatar Cache") {
                        DataLayer.sharedInstance().clearAvatarHashCache()
                        HelperTools.clearAvatarImageCache()
                        showingAvatarResetDoneAlert = true
                    }
                }
            }
            .listStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.interpolatedWindowBackground)
        .alert(isPresented: $showingDBExportFailedAlert) {
            Alert(title: Text("Database Export Failed"), message: Text("Failed to export the database, please check the logfile for errors and try again."), dismissButton: .default(Text("Close")))
        }
        .sheet(isPresented:$fileURL.optionalMappedToBool()) {
            if let fileURL = fileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
        //isaCloud: the chosen file is copied into the app group as "import-sworim.sqlite" and swapped in when the app opens again
        .fileImporter(isPresented: $showDBImporter, allowedContentTypes: [.data, .item]) { result in
            switch result {
                case .success(let url):
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let destination = HelperTools.getContainerURL(forPathComponents: ["import-sworim.sqlite"])
                    let fm = FileManager.default
                    try? fm.removeItem(at: destination)
                    do {
                        try fm.copyItem(at: url, to: destination)
                        print("Database copied for import: \(destination.path)")
                        showingDBImportDoneAlert = true
                    } catch {
                        print("Could not copy the database for import: \(error)")
                        showingDBImportFailedAlert = true
                    }
                case .failure:
                    showingDBImportFailedAlert = true
            }
        }
        .alert("Database imported", isPresented: $showingDBImportDoneAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Close and open the app to apply it. The current database (accounts, chats and messages) will be replaced, and the app will migrate the imported one on the next start.")
        }
        .alert("Avatar cache cleared", isPresented: $showingAvatarResetDoneAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Close and open the app, or wait for the contacts to come online again, so the avatars are downloaded.")
        }
        .alert("Database import failed", isPresented: $showingDBImportFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check the logfile and try again.")
        }
        .onAppear {
            refreshSortedLogfiles()
        }
    }
}

struct UDPConfigView: View {
    @ObservedObject var defaultDB = DebugDefaultDB()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("The UDP logger allows you to livestream the log to the configured IP. Please use a secure key when streaming over the internet!\n[Learn how to receive the log stream](https://github.com/monal-im/Monal/wiki/Introduction-to-Monal-Logging#stream-the-log).")
            Form {
                Section(header: Text("UDP Logger Configuration")) {
                    Toggle(isOn: $defaultDB.udpLoggerEnabled) {
                        Text("Enable")
                    }
                    LabeledContent("Logserver IP:") {
                        TextField("Logserver IP", text: $defaultDB.udpLoggerHostname, prompt: Text("Required"))
                    }
                    LabeledContent("Logserver Port:") {
                        TextField("Logserver Port", text: $defaultDB.udpLoggerPort, prompt: Text("Required"))
                    }.keyboardType(.numberPad)
                    LabeledContent("AES Encryption Key:") {
                        TextField("AES Encryption Key", text: $defaultDB.udpLoggerKey, prompt: Text("Required"))
                    }
                }
            }
            .padding(0)
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.interpolatedWindowBackground)
    }
}

struct CrashTestingView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("The following buttons allow you to forcefully crash the app using several different methods to test the crash handling.")
            List {
                Button("Try to call unknown handler method") {
                    DispatchQueue.global(qos: .default).async(execute: {
                        let handler = MLHandler(delegate: self, handlerName: "IDontKnowThis", andBoundArguments: [:])
                        handler.call(withArguments: nil)
                    })
                }
                Button("Bad Access Crash") {
                    let delegate: AnyClass? = NSClassFromString("MonalAppDelegate")
                    print(delegate.unsafelyUnwrapped.audiovisualTypes())
                }
                Button("MLAssert Crash") {
                    HelperTools.flushLogs(withTimeout: 0.100)
                    MLAssert(false, "MLAssert_example")
                }
                Button("Assertion Crash") {
                    assert(false)
                }
                Button("Fatal Error Crash") {
                    fatalError("fatalError_example")
                }
                Button("Nil Crash") {
                    let crasher:Int? = nil
                    print(crasher!)
                }
            }
            .foregroundColor(.red)
            .listStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.interpolatedWindowBackground)
    }
}

struct ExtraSettingsView: View {
    @State private var showClearedShareAlert = false
    @State private var clearedShareItems = 0
    @ObservedObject var defaultDB = DebugDefaultDB()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Patch level: \(HelperTools.patchLevel())")
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.setValue(HelperTools.patchLevel(), forPasteboardType:UTType.utf8PlainText.identifier as String)
                    UIAccessibility.post(notification: .announcement, argument: "Patch Level ID Copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy patch level")
                .accessibilityHint("Copies the patch level ID to the clipboard")
            }
            List {
                Section(header: Text("Some debug settings:")) {
                    Toggle(isOn: $defaultDB.hasCompletedOnboarding) {
                        Text("Don't show onboarding")
                    }

                    Toggle(isOn: $defaultDB.showNewChatView) {
                        Text("Show new SwiftUI ChatView")
                    }

                    Toggle(isOn: $defaultDB.debugDtmfSending) {
                        Text("Automatically play DTMF tones in all calls")
                    }

                    Toggle(isOn: $defaultDB.debugNSNotifications) {
                        Text("Log *all* NSNotifications")
                    }

                    Button("Reset the state of all accounts") {
                        MLXMPPManager.sharedInstance().resetAllAccountStates()
                    }

                    Button("Clear share sheet queue") {
                        clearedShareItems = Int(DataLayer.sharedInstance().clearShareSheetOutbox())
                        showClearedShareAlert = true
                    }
                    .alert("Share sheet queue cleared", isPresented: $showClearedShareAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("\(clearedShareItems) items removed")
                    }

                    Button("Change app icon to christmas") {
                        UIApplication.shared.setAlternateIconName("AlphaAppIcon-Christmas")
                    }

                    Button("Change app icon to default") {
                        UIApplication.shared.setAlternateIconName(nil)
                    }
                }
            }
            .listStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.interpolatedWindowBackground)
    }
}

struct DebugView: View {
    @StateObject private var overlay = LoadingOverlayState()
    
    var body: some View {
        TabView {
            LogFilesView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Logs")
                }
            UDPConfigView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("UDP Logger")
                }
            CrashTestingView()
                .tabItem {
                    Image(systemName: "bolt.fill")
                    Text("Crash Testing")
                }
            ExtraSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Extra Settings")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .addLoadingOverlay(overlay)
        .navigationBarItems(trailing:Button("Reconnect All") {
            showLoadingOverlay(overlay, headline: "Reconnecting", description: "Will log out and reconnect all (enabled) accounts.") {
                MLXMPPManager.sharedInstance().reconnectAll()
                return after(seconds:3.0)
            }
        })
    }
}

#Preview {
    NavigationStack {
        DebugView()
    }
}

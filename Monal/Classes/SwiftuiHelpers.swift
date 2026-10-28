//
//  ContactDetailsInterface.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

//see https://davedelong.com/blog/2018/01/19/simplifying-swift-framework-development/ for explanation of @_exported
@_exported import Foundation
@_exported import CocoaLumberjack
//@_exported import CocoaLumberjackSwift
@_exported import Logging
@_exported import SwiftUI
@_exported import monalxmpp
@_exported import Combine
import PhotosUI
import UniformTypeIdentifiers
import FLAnimatedImage
import CropViewController
import SafariServices
import WebKit
import NotificationBannerSwift

//see https://stackoverflow.com/a/62207329/3528174
//and https://www.hackingwithswift.com/forums/100-days-of-swiftui/extending-shapestyle-for-adding-colors-instead-of-extending-color/12324
public extension ShapeStyle where Self == Color {
    static var interpolatedWindowBackground: Color { Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.systemBackground : UIColor.secondarySystemBackground }) }
    static var background: Color { Color(UIColor.systemBackground) }
}

@objcMembers
class MonalFloatingNotificationBanner: FloatingNotificationBanner {
    public init(title: String? = nil, subtitle: String? = nil, style: BannerStyle = .info, colors: BannerColorsProtocol? = nil) {
        super.init(
            title: title,
            subtitle: subtitle,
            style: style,
            colors: colors
        )
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
        
class SheetDismisserProtocol: ObservableObject {
    weak var host: UIHostingController<AnyView>? = nil
    func dismiss() {
        host?.dismiss(animated: true)
    }
    func dismissWithoutAnimation() {
        host?.dismiss(animated: false)
    }
    func replace<V>(with view: V) where V: View {
        host?.rootView = AnyView(view)
    }
}

func getContactList(viewContact: (ObservableKVOWrapper<MLContact>?)) -> OrderedSet<ObservableKVOWrapper<MLContact>> {
    if let contact = viewContact {
        if(contact.isMuc) {
            //this uses the account the muc belongs to and treats every other account to be remote,
            //even when multiple accounts of the same monal instance are in the same group
            var contactList : OrderedSet<ObservableKVOWrapper<MLContact>> = OrderedSet()
            for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: contact.contactJid, forAccountID: contact.accountID)) {
                //jid can be participant_jid (if currently joined to muc) or member_jid (if not joined but member of muc)
                guard let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String else {
                    continue
                }
                contactList.append(ObservableKVOWrapper<MLContact>(MLContact.createContact(fromJid: jid, andAccountID: contact.accountID)))
            }
            return contactList
        } else {
            return [contact]
        }
    } else {
        return []
    }
}

//isaCloud: the number the lists behind "Group Members" / "Channel Participants" show (the channel list leaves out ourselves)
func countMucPersons(of contact: ObservableKVOWrapper<MLContact>, ownJid: String) -> Int {
    guard contact.isMuc else {
        return 0
    }
    if contact.obj.mucType == kMucTypeGroup {
        //exactly the list of the group members screen (it merges entries of the same contact)
        return getContactList(viewContact: contact).count
    }
    var nicks = Set<String>()
    for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: contact.obj.contactJid, forAccountID: contact.obj.accountID)) {
        let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String
        if let nick = memberInfo["room_nick"] as? String, jid != ownJid {
            nicks.insert(nick)
        }
    }
    return nicks.count
}

//isaCloud: "X members" for a group, "X participants" for a channel
func mucPersonCountLabel(isGroup: Bool, count: Int) -> String {
    if isGroup {
        return count == 1 ? NSLocalizedString("1 member", comment: "") : String(format: NSLocalizedString("%d members", comment: ""), count)
    }
    return count == 1 ? NSLocalizedString("1 participant", comment: "") : String(format: NSLocalizedString("%d participants", comment: ""), count)
}

func promisifyMucAction(account: xmpp, mucJid: String, action: @escaping () throws -> Void) -> Promise<monal_void_block_t?> {
    return Promise<monal_void_block_t?> { seal in
        DispatchQueue.global(qos: .background).async {
            account.mucProcessor.addUIHandler({_data in let data = _data as! NSDictionary
                let success : Bool = data["success"] as! Bool;
                if !success {
                    seal.reject(data["errorMessage"] as? String ?? "Unknown error!")
                } else {
                    if let callback = data["callback"] {
                        seal.fulfill(objcCast(callback) as monal_void_block_t)
                    } else {
                        seal.fulfill(nil)
                    }
                }
            }, forMuc:mucJid)
            do {
                try action()
            } catch {
                seal.reject(error)
            }
            
        }
    }
}

func mucAffiliationToString(_ affiliation: String?, _ role: String? = nil) -> String {
    if let affiliation = affiliation {
        if affiliation == kMucAffiliationOwner {
            return NSLocalizedString("Owner", comment:"muc affiliation")
        } else if affiliation == kMucAffiliationAdmin {
            return NSLocalizedString("Admin", comment:"muc affiliation")
        } else if affiliation == kMucAffiliationMember {
            return NSLocalizedString("Member", comment:"muc affiliation")
        } else if affiliation == kMucAffiliationNone {
            if role == kMucRoleParticipant {
                return NSLocalizedString("Participant", comment:"muc affiliation")
            } else if role == kMucRoleVisitor {
                return NSLocalizedString("Visitor", comment:"muc affiliation")
            } else {
                return NSLocalizedString("None", comment:"muc affiliation")
            }
        } else if affiliation == kMucAffiliationOutcast {
            return NSLocalizedString("Blocked", comment:"muc affiliation")
        } else if affiliation == kMucActionShowProfile {
            return NSLocalizedString("Open contact details", comment:"muc members list")
        } else if affiliation == kMucActionReinvite {
            return NSLocalizedString("Invite again", comment:"muc invite")
        }
    }
    return NSLocalizedString("<unknown>", comment:"muc affiliation")
}

func mucAffiliationToInt(_ affiliation: String?) -> Int {
    if let affiliation = affiliation {
        if affiliation == kMucAffiliationOwner {
            return 1
        } else if affiliation == kMucAffiliationAdmin {
            return 2
        } else if affiliation == kMucAffiliationMember {
            return 3
        } else if affiliation == kMucAffiliationNone {
            return 4
        } else if affiliation == kMucAffiliationOutcast {
            return 5
        } else if affiliation == kMucActionShowProfile {
            return 1000
        } else if affiliation == kMucActionReinvite {
            return 100
        }
    }
    return 0
}

func mucRoleToInt(_ role: String?) -> Int {
    if let role = role {
        if role == kMucRoleModerator {
            return 1
        } else if role == kMucRoleParticipant {
            return 2
        } else if role == kMucRoleVisitor {
            return 3
        } else if role == kMucRoleNone {
            return 4
        }
    }
    return 0
}

struct CollapsedPickerStyle: ViewModifier {
    let accessibilityLabel: Text
    func body(content: Content) -> some View {
        Menu {
            content
        } label: {
            Button(action: { }) {
                HStack {
                    Spacer().frame(width:8)
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .foregroundColor(.primary)
                    Spacer().frame(width:8)
                }
                .contentShape(Rectangle())
            }
            .frame(width: 24, height: 20)
            .accessibilityLabel(accessibilityLabel)
        }
    }
    
}
extension View {
    func collapsedPickerStyle(accessibilityLabel label: Text) -> some View {
        self.modifier(CollapsedPickerStyle(accessibilityLabel:label))
    }
}

struct TopRight<T: View>: ViewModifier {
    let overlay: T
    public func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            content
            VStack {
                HStack {
                    Spacer()
                    overlay
                }
                Spacer()
            }
        }
    }
}
extension View {
    func addTopRight<T: View>(view overlayClosure: @autoclosure @escaping () -> T) -> some View {
        modifier(TopRight(overlay:overlayClosure()))
    }
    func addTopRight(@ViewBuilder _ overlayClosure: @escaping () -> some View) -> some View {
        modifier(TopRight(overlay:overlayClosure()))
    }
}

struct MonalProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background(Color.accentColor)
            .foregroundColor(Color(UIColor.systemBackground))
            .fontWeight(isEnabled ? .bold : .regular)
            .cornerRadius(10)
    }
}

@ViewBuilder
func buildNotificationStateLabel(_ description: Text, isWorking: Bool) -> some View {
    if(isWorking == true) {
        Label(title: {
            description
        }, icon: {
            Image(systemName: "checkmark.seal")
                .foregroundColor(.green)
        })
    } else {
        Label(title: {
            description
        }, icon: {
            Image(systemName: "xmark.seal")
                .foregroundColor(.red)
        })
    }
}

//see https://github.com/CH3COOH/TOCropViewController/blob/issue/421/Swift/CropViewControllerSwiftUIExample/ImageCropView.swift
public struct ImageCropView: UIViewControllerRepresentable {
    private let configureBlock: (CropViewController) -> Void
    private let originalImage: UIImage
    private let onCanceled: () -> Void
    private let onImageCropped: (UIImage,CGRect,Int) -> Void
    
    @Environment(\.presentationMode) private var presentationMode

    public init(originalImage: UIImage, configureBlock: @escaping (CropViewController) -> Void, onCanceled: @escaping () -> Void, success onImageCropped: @escaping (UIImage,CGRect,Int) -> Void) {
        self.originalImage = originalImage
        self.configureBlock = configureBlock
        self.onCanceled = onCanceled
        self.onImageCropped = onImageCropped
    }

    public func makeUIViewController(context: Context) -> CropViewController {
        let cropController = CropViewController(image: originalImage)
        cropController.delegate = context.coordinator
        configureBlock(cropController)
        return cropController
    }

    public func updateUIViewController(_ uiViewController: CropViewController, context: Context) {
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            onDismiss: { self.presentationMode.wrappedValue.dismiss() },
            onCanceled: self.onCanceled,
            onImageCropped: self.onImageCropped
        )
    }

    final public class Coordinator: NSObject, CropViewControllerDelegate {
        private let onDismiss: () -> Void
        private let onImageCropped: (UIImage,CGRect,Int) -> Void
        private let onCanceled: () -> Void

        init(onDismiss: @escaping () -> Void, onCanceled: @escaping () -> Void, onImageCropped: @escaping (UIImage,CGRect,Int) -> Void) {
            self.onDismiss = onDismiss
            self.onImageCropped = onImageCropped
            self.onCanceled = onCanceled
        }

        public func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
            self.onImageCropped(image, cropRect, angle)
            self.onDismiss()
        }
        
        public func cropViewController(_ cropViewController: CropViewController, didCropToCircularImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
            self.onImageCropped(image, cropRect, angle)
            self.onDismiss()
        }
        
        public func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
            self.onCanceled()
            self.onDismiss()
        }
    }
}

//see here for some ideas used herein: https://blog.logrocket.com/adding-gifs-ios-app-flanimatedimage-swiftui/#using-flanimatedimage-with-swift
struct GIFViewer: UIViewRepresentable {
    typealias UIViewType = FLAnimatedImageView
    @Binding var data: Data

    func makeUIView(context: Context) -> FLAnimatedImageView {
        let imageView = FLAnimatedImageView(frame:.zero)
        let animatedImage = FLAnimatedImage(animatedGIFData:data)
        imageView.animatedImage = animatedImage
        return imageView
    }

    func updateUIView(_ imageView: FLAnimatedImageView, context: Context) {
        let animatedImage = FLAnimatedImage(animatedGIFData:data)
        imageView.animatedImage = animatedImage
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        guard
            let width = proposal.width,
            let height = proposal.height
        else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// isaCloud: the system photo picker for chat attachments (photos and videos, any number). It replaces ExyteMediaPicker, whose grid
/// does not scroll on iOS 27 (the drag selection gesture steals the scroll gesture), and it needs no access to the photo library.
struct SystemMediaPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPicked: ([(url: URL, isVideo: Bool)]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 0       //no limit
        config.preferredAssetRepresentationMode = .current      //send the original file, like before
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding var isPresented: Bool
        let onPicked: ([(url: URL, isVideo: Bool)]) -> Void

        init(isPresented: Binding<Bool>, onPicked: @escaping ([(url: URL, isVideo: Bool)]) -> Void) {
            _isPresented = isPresented
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            isPresented = false
            guard !results.isEmpty else {
                return
            }
            let lock = NSLock()
            let group = DispatchGroup()
            var picked: [Int: (url: URL, isVideo: Bool)] = [:]
            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                let typeIdentifier = isVideo ? UTType.movie.identifier : UTType.image.identifier
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                    defer { group.leave() }
                    guard let url else {
                        DDLogError("Could not load the picked media: \(String(describing: error))")
                        return
                    }
                    //the system deletes this file as soon as the closure returns: keep a copy of it
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    let copy = directory.appendingPathComponent(url.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: url, to: copy)
                    } catch {
                        DDLogError("Could not copy the picked media: \(error)")
                        return
                    }
                    lock.lock()
                    picked[index] = (url: copy, isVideo: isVideo)
                    lock.unlock()
                }
            }
            group.notify(queue: .main) { [onPicked] in
                lock.lock()
                let ordered = picked.keys.sorted().compactMap { picked[$0] }
                lock.unlock()
                onPicked(ordered)
            }
        }
    }
}

//see https://www.hackingwithswift.com/books/ios-swiftui/importing-an-image-into-swiftui-using-phpickerviewcontroller
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {

    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    self.parent.image = image as? UIImage
                }
            }
        }
    }
}

//see https://stackoverflow.com/a/60452526
class DocumentPickerViewController: UIDocumentPickerViewController {
    private let onDismiss: () -> Void
    private let onPick: (URL) -> ()

    init(supportedTypes: [UTType], onPick: @escaping (URL) -> Void, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.onPick = onPick

        super.init(forOpeningContentTypes:supportedTypes, asCopy:true)

        allowsMultipleSelection = false
        delegate = self
    }

    required init?(coder: NSCoder) {
        unreachable("init(coder:) has not been implemented")
    }
}

extension DocumentPickerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick(urls.first!)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onDismiss()
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {
        
    }
}

struct WebView: UIViewRepresentable {
    var url: URL
 
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
 
    func updateUIView(_ webView: WKWebView, context: Context) {
        var request = URLRequest(url: url)
        if HelperTools.defaultsDB().bool(forKey:"useDnssecForAllConnections") {
            request.requiresDNSSECValidation = true;
        }
        webView.load(request)
    }
}

// clear button for text fields, see https://stackoverflow.com/a/58896723/3528174
struct ClearButton: ViewModifier {
    let isEditing: Bool
    @Binding var text: String
    
    public func body(content: Content) -> some View {
        HStack {
            content
                .accessibilitySortPriority(2)
            
            if isEditing, !text.isEmpty {
                Button {
                    self.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .accessibilityLabel(Text("Clear text"))
                }
                .padding(.trailing, 8)
                .accessibilitySortPriority(1)
            }
        }
    }
}
//this extension contains the easy-access view modifier
extension View {
    /// Puts the view in an HStack and adds a clear button to the right when the text is not empty.
    func addClearButton(isEditing: Bool, text: Binding<String>) -> some View {
        modifier(ClearButton(isEditing: isEditing, text:text))
    }
}

//see https://exyte.com/blog/swiftui-tutorial-popupview-library
struct FrameGetterModifier: ViewModifier {
    @Binding var frame: CGRect
    func body(content: Content) -> some View {
        content
        .background(
            GeometryReader { proxy -> AnyView in
                let rect = proxy.frame(in: .global)
                // This avoids an infinite layout loop
                if rect.integral != self.frame.integral {
                    DispatchQueue.main.async {
                        self.frame = rect
                    }
                }
                return AnyView(EmptyView())
            }
        )
    }
}
extension View { 
    func frameGetter(_ frame: Binding<CGRect>) -> some View {
        modifier(FrameGetterModifier(frame: frame))
    }
}

struct NumberlessBadge: View {
    @Binding var notificationCount: Int
    private let size: Int
    private let inset: Int

    var badgeSize: CGFloat {
        CGFloat(integerLiteral: size)
    }

    var edgeInset: CGFloat {
        CGFloat(integerLiteral: inset)
    }

    init(_ notificationCount: Binding<Int>, size: Int = 7, inset: Int = 1) {
        self._notificationCount = notificationCount
        self.size = size
        self.inset = inset
    }

    var body: some View {
        HStack {
            Spacer()
            VStack {
                if notificationCount > 0 {
                    Image(systemName: "circle.fill")
                        .resizable()
                        .frame(width: badgeSize, height: badgeSize)
                        .tint(.red)
                        .padding(.trailing, edgeInset)
                        .padding(.top, edgeInset)
                }
                Spacer()
            }
        }
        .animation(.default, value: notificationCount)
    }
}

struct LinkedText: View {
    let attributed: AttributedString

    init(_ text: String) {
        self.attributed = text.linkify()
    }

    var body: some View {
        Text(attributed)
    }
}

//see https://sarunw.com/posts/sfsafariviewcontroller-in-swiftui/
struct SFSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<Self>) {
        
    }
}

//see https://www.avanderlee.com/swiftui/sfsafariviewcontroller-open-webpages-in-app/
struct ExternalLinkViewModifier: ViewModifier {
    @State private var urlToOpen: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                let openableInSFSafariView = url.scheme == "http" || url.scheme == "https"
                if openableInSFSafariView && HelperTools.defaultsDB().bool(forKey:"useInlineSafari") {
                    urlToOpen = url
                    return .handled
                } else {
                    return .systemAction
                }
            })
            .fullScreenCover(isPresented: $urlToOpen.optionalMappedToBool(), onDismiss: {
                urlToOpen = nil
            }, content: {
                SFSafariView(url: urlToOpen!)
                    .ignoresSafeArea()
            })
    }
}
extension View {
    func canContainExternalLinks() -> some View {
        modifier(ExternalLinkViewModifier())
    }
}

// //see https://stackoverflow.com/a/68291983
// struct OverflowContentViewModifier: ViewModifier {
//     @State private var contentOverflow: Bool = false
//     func body(content: Content) -> some View {
//         GeometryReader { geometry in
//             content
//             .background(
//                 GeometryReader { contentGeometry in
//                     Color.clear.onAppear {
//                         contentOverflow = contentGeometry.size.height > geometry.size.height
//                     }
//                 }
//             )
//             .wrappedInScrollView(when: contentOverflow)
//         }
//     }
// }
// 
// extension View {
//     @ViewBuilder
//     func wrappedInScrollView(when condition: Bool) -> some View {
//         if condition {
//             ScrollView {
//                 self
//             }
//         } else {
//             self
//         }
//     }
// }
// 
// extension View {
//     func scrollOnOverflow() -> some View {
//         modifier(OverflowContentViewModifier())
//     }
// }

// lazy loading of views (e.g. when used inside a NavigationLink) with the additional ability to use a closure to modify/wrap them
// see https://stackoverflow.com/a/61234030/3528174
struct LazyClosureView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    init(withClosure build: @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

// use this to wrap a view into NavigationStack, if it should be the outermost swiftui view of a new view stack
struct AddTopLevelNavigation<Content: View>: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var sizeClass: ObservableKVOWrapper<SizeClassWrapper>
    let build: () -> Content
    let delegate: SheetDismisserProtocol?
    let hidesBackButton: Bool       //isaCloud: the screen has its own back button (at the bottom)
    
    init(withDelegate delegate: SheetDismisserProtocol?, hidesBackButton: Bool = false, to build: @autoclosure @escaping () -> Content) {
        self.build = build
        self.delegate = delegate
        self.hidesBackButton = hidesBackButton

        let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!
        self._sizeClass = StateObject(wrappedValue: ObservableKVOWrapper<SizeClassWrapper>(activeChats.sizeClass))
    }
    
    var body: some View {
        NavigationStack {
            build()
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarBackButtonHidden(true) // will not be shown because swiftui does not know we navigated here from UIKit
                .toolbar {
#if targetEnvironment(macCatalyst)
                    let shouldDisplayBackButton = true
#else
                    let shouldDisplayBackButton = UIUserInterfaceSizeClass(rawValue: sizeClass.horizontal) == .compact && !hidesBackButton
#endif
                    if shouldDisplayBackButton {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action : {
                                //NOTE: since we can get opened from objc, we still need to support our SheetDismisserProtocol
                                if let delegate = self.delegate {
                                    delegate.dismiss()
                                } else {
                                    self.presentationMode.wrappedValue.dismiss()
                                }
                            }) {
                                Image(systemName: "arrow.backward")
                            }
                            .keyboardShortcut(.escape, modifiers: [])
                        }
                    }
                }
        }
    }
}

// TODO: fix those workarounds as soon as we have no storyboards anymore
struct UIKitWorkaround<Content: View>: View {
    let build: () -> Content
    @StateObject private var sizeClass: ObservableKVOWrapper<SizeClassWrapper>
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
        let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!
        self._sizeClass = StateObject(wrappedValue: ObservableKVOWrapper<SizeClassWrapper>(activeChats.sizeClass))
    }
    init(withClosure build: @escaping () -> Content) {
        self.build = build
        let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!
        self._sizeClass = StateObject(wrappedValue: ObservableKVOWrapper<SizeClassWrapper>(activeChats.sizeClass))
    }
    var body: some View {
        let isCompact = UIUserInterfaceSizeClass(rawValue: sizeClass.horizontal) == .compact
        if isCompact || ProcessInfo().isMacCatalystApp {
            // The app is running on an iPhone in portrait mode, or on a Mac
            build().navigationBarTitleDisplayMode(.inline)
        } else {
            // The app is running on an iPad or a big iPhone in landscape mode
            NavigationStack {
                build()
                .navigationBarTitleDisplayMode(.automatic)
            }
        }
    }
}

// properties for use in Alert
struct AlertPrompt {
    var title: Text = Text("")
    var message: Text = Text("")
    var dismissLabel: Text = Text("Close")
    var dismissCallback: monal_void_block_t? = nil
}

// properties for use in actionSheet
struct ConfirmationPrompt {
    var title: Text = Text("")
    var message: Text = Text("")
    var buttons: [ActionSheet.Button] = []
}

extension View {
    /// Applies the given transform.
    ///
    /// Useful for availability branching on view modifiers. Do not branch with any properties that may change during runtime as this will cause errors.
    /// - Parameters:
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: The view transformed by the transform.
    func applyClosure<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> some View {
        transform(self)
    }
}

public extension UIViewController {
    private struct AssociatedKeys {
        static var DisposeCallbackKey = "ml_disposeCallbackKey"
    }
    
    private class DisposeCallback : NSObject {
        let callback: monal_void_block_t
        
        init(withCallback callback: @escaping monal_void_block_t) {
            self.callback = callback
        }
        
        deinit {
            self.callback()
        }
    }
    
    @objc
    var ml_disposeCallback: monal_void_block_t {
        get {
            return withUnsafePointer(to: &AssociatedKeys.DisposeCallbackKey) { pointer in
                if let callback = (objc_getAssociatedObject(self, pointer) as? DisposeCallback)?.callback {
                    return callback
                }
                unreachable("You can't get what you did not set!")
            }
        }
        set {
            withUnsafePointer(to: &AssociatedKeys.DisposeCallbackKey) { pointer in
                objc_setAssociatedObject(self, pointer, DisposeCallback(withCallback: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
}

// Interfaces between ObjectiveC/Storyboards and SwiftUI
@objc
class SwiftuiInterface : NSObject {
    let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!

    @objc
    func makeChatView(for contact: MLContact) -> UIViewController {
        return makeChatView(for: contact, atMessage: nil)
    }

    //isaCloud: opens the chat at a message found by the search in the messages (history id of the message; nil: the newest messages)
    @objc(makeChatViewFor:atMessage:)
    func makeChatView(for contact: MLContact, atMessage historyId: NSNumber?) -> UIViewController {
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        let isCompact = UIUserInterfaceSizeClass(rawValue: activeChats.sizeClass.horizontal.rawValue) == .compact
        @ViewBuilder
        var chatView: some View {
            if isCompact {
                ChatView(contact:ObservableKVOWrapper<MLContact>(contact), jumpToHistoryId: historyId)
            } else {
                NavigationStack {
                    ChatView(contact:ObservableKVOWrapper<MLContact>(contact), jumpToHistoryId: historyId)
                }
            }
        }
        host.rootView = AnyView(chatView)
        // Clip to bounds to avoid the overflowing of the chat background during the chat opening animation
        // (due to the use of .scaledToFill() on the background image)
        host.view.clipsToBounds = true;
        return host
    }
    
    @objc(makeAccountPickerForContacts:andCallType:)
    func makeAccountPicker(for contacts: [MLContact], and callType: UInt) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:AccountPicker(contacts:contacts, callType:MLCallType(rawValue: callType)!)))
        return host
    }
    
    @objc(makeCallScreenForCall:)
    func makeCallScreen(for call: MLCall) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AVCallUI(delegate:delegate, call:call))
        return host
    }
    
    @objc
    func makeContactDetails(_ contact: MLContact) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(contact))))
        return host
    }
    
    @objc(makeImageViewerForCurrentItem:allItems:)
    func makeImageViewerFor(currentItem:MLFiletransferInfo, allItems: [MLFiletransferInfo]) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(MediaItemSwipeView(currentItem: currentItem, allItems: allItems))
        return host
    }
    
    @objc
    func makeOwnOmemoKeyView(_ ownContact: MLContact?) -> UIViewController {
        let host = UIHostingController(rootView:AnyView(EmptyView()))

        @ViewBuilder
        var omemoKeysView: some View {
            if(ownContact == nil) {
                OmemoKeysView(omemoKeys: OmemoKeysForChat(viewContact: nil))
            } else {
                OmemoKeysView(omemoKeys: OmemoKeysForChat(viewContact: ObservableKVOWrapper<MLContact>(ownContact!)))
            }
        }
        host.rootView = AnyView(UIKitWorkaround(omemoKeysView))
        return host
    }

    @objc
    func makeChangePasswordView(for accountID: NSNumber) -> UIViewController {
        let host = UIHostingController(rootView:AnyView(EmptyView()))
            host.rootView = AnyView(UIKitWorkaround(ChangePassword(accountID: accountID)))
        return host
    }

    @objc
    func makeAccountRegistration(_ registerData: [String:AnyObject]?) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:RegisterAccount(delegate:delegate, registerData:registerData)))
        return host
    }

    @objc
    func makeServerDetailsView(for xmppAccount: xmpp) -> UIViewController {
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        host.rootView = AnyView(UIKitWorkaround(ServerDetails(xmppAccount: ObservableKVOWrapper<xmpp>(xmppAccount))))
        return host
    }

    @objc
    func makeBlockedUsersView(for xmppAccount: xmpp) -> UIViewController {
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        host.rootView = AnyView(UIKitWorkaround(BlockedUsers(xmppAccount: xmppAccount)))
        return host
    }

    @objc
    func makePasswordMigration(_ needingMigration: [[String:NSObject]]) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:PasswordMigration(delegate:delegate, needingMigration:needingMigration)))
        return host
    }
    
    @objc(makeAddContactViewWithDismisser:)
    func makeAddContactView(dismisser: @escaping (MLContact) -> ()) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: AddContactMenu(delegate: delegate, dismissWithNewContact: dismisser)))
        return host
    }
    
    @objc
    func makeAddContactView(forJid jid:String, preauthToken: String?, prefillAccount: xmpp?, andOmemoFingerprints omemoFingerprints: [NSNumber:Data]?, withDismisser dismisser: @escaping (MLContact) -> ()) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: AddContactMenu(delegate: delegate, dismissWithNewContact: dismisser, prefillJid: jid, preauthToken: preauthToken, prefillAccount: prefillAccount, omemoFingerprints: omemoFingerprints)))
        return host
    }

    @objc(makeContactsViewWithDismisser:onButton:)
    func makeContactsView(dismisser: @escaping (MLContact) -> (), button: UIBarButtonItem) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        let contactsView = ContactsView(contacts: Contacts(), delegate: delegate, dismissWithContact: dismisser)
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, hidesBackButton: ControlsAtBottom.isOn, to: contactsView))
        host.modalPresentationStyle = .popover
        host.popoverPresentationController?.sourceItem = button
        host.preferredContentSize = host.sizeThatFits(in: CGSize(width: 400, height: 600))
        return host
    }

    @objc
    func makeView(name: String) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        var host: UIHostingController<AnyView>? = nil
        //let host = UIHostingController(rootView:AnyView(EmptyView()))
        switch(name) { // TODO names are currently taken from the segue identifier, an enum would be nice once everything is ported to SwiftUI
            case "DebugView":
                host = UIHostingController(rootView:AnyView(UIKitWorkaround(DebugView())))
            case "WelcomeLogIn":
                host = UIHostingController(rootView:AnyView(AddTopLevelNavigation(withDelegate:delegate, to:WelcomeLogIn(delegate:delegate))))
            case "LogIn":
                host = UIHostingController(rootView:AnyView(UIKitWorkaround(WelcomeLogIn(delegate:delegate))))
            case "AdvancedLogIn":
                host = UIHostingController(rootView:AnyView(UIKitWorkaround(WelcomeLogIn(advancedMode: true, delegate: delegate))))
            case "ChatPlaceholder":
                host = UIHostingController(rootView:AnyView(ChatPlaceholder()))
            case "GeneralSettings" :
                host = UIHostingController(rootView:AnyView(UIKitWorkaround(GeneralSettings())))
            case "ActiveChatsGeneralSettings":
                host = UIHostingController(rootView:AnyView(AddTopLevelNavigation(withDelegate: delegate, to: GeneralSettings())))
            case "ActiveChatsNotificationSettings":
                host = UIHostingController(rootView:AnyView(AddTopLevelNavigation(withDelegate: delegate, to: NotificationSettings())))
            case "OnboardingView":
                host = UIHostingController(rootView:AnyView(createOnboardingView(delegate:delegate)))
            case "OneClickRegistration":
               host = UIHostingController(rootView:AnyView(AddTopLevelNavigation(withDelegate:delegate, to:OneClickRegistration(delegate:delegate))))
            
            default:
                unreachable()
        }
        delegate.host = host!
        return host!
    }
}

//isaCloud: hide the keyboard when tapping outside of text fields or when scrolling
//use .dismissKeyboardOnTapOrScroll() on screens with forms (WelcomeLogIn, RegisterAccount)
struct DismissKeyboardOnTapOrScroll: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.immediately)
            .onAppear { KeyboardDismissTapHandler.shared.enable() }
            .onDisappear { KeyboardDismissTapHandler.shared.disable() }
    }
}

extension View {
    func dismissKeyboardOnTapOrScroll() -> some View {
        modifier(DismissKeyboardOnTapOrScroll())
    }
}

//tap and pan recognizers on the key window, only active while at least one screen using the modifier above is visible
//(nested screens like WelcomeLogIn -> RegisterAccount are counted, so the order of onAppear/onDisappear does not matter)
private final class KeyboardDismissTapHandler: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissTapHandler()
    private var users = 0
    private weak var recognizer: UITapGestureRecognizer?
    private weak var panRecognizer: UIPanGestureRecognizer?     //scrolling: .scrollDismissesKeyboard does not reach nested Forms

    func enable() {
        users += 1
        if recognizer == nil, let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false        //buttons and links keep working
            tap.delegate = self
            window.addGestureRecognizer(tap)
            recognizer = tap

            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.cancelsTouchesInView = false        //scroll views keep scrolling
            pan.delegate = self
            window.addGestureRecognizer(pan)
            panRecognizer = pan
        }
        recognizer?.isEnabled = true
        panRecognizer?.isEnabled = true
    }

    func disable() {
        users = max(0, users - 1)
        recognizer?.isEnabled = users > 0
        panRecognizer?.isEnabled = users > 0
    }

    @objc private func tapped(_ sender: UITapGestureRecognizer) {
        sender.view?.endEditing(true)
    }

    @objc private func panned(_ sender: UIPanGestureRecognizer) {
        if sender.state == .began {
            sender.view?.endEditing(true)
        }
    }

    //touches on text inputs are ignored, so moving from one field to another does not close and reopen the keyboard
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView {
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: isaCloud: controls at the bottom

/// isaCloud: how the bars at the bottom of the screen look ("Controls at the bottom of the screen"): a solid background (never see-through, so the
/// content behind it cannot be mixed up with the controls) and a thin line on top.
enum BottomBarStyle {
    static var background: UIColor { UIColor.secondarySystemBackground }

    static func toolbarAppearance() -> UIToolbarAppearance {
        let appearance = UIToolbarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = UIColor.separator
        return appearance
    }
}

/// isaCloud: the setting "Controls at the bottom of the screen" (Settings > User Interface > Appearance). iPhone only: on the iPad the screens
/// keep their controls at the top. The screens read it each time they are shown or built.
@objc
class ControlsAtBottom : NSObject {
    @objc static var isOn: Bool {
#if targetEnvironment(macCatalyst)
        return false
#else
        return UIDevice.current.userInterfaceIdiom == .phone && HelperTools.defaultsDB().bool(forKey: "controlsAtBottom")
#endif
    }
}

/// isaCloud: the controls of the home screen (account, search and contacts) in a bar fixed at the bottom of the screen, over the list. The
/// background is solid (BottomBarStyle), and the bar rises with the keyboard. The search is a system
/// UISearchBar: while it is used the account and contacts buttons make room for it and the system "Cancel" button shows up.
@objc
final class BottomControlsBar : UIView, UISearchBarDelegate {
    /// the height of the bar above the home indicator: what the list needs to keep clear at its end
    @objc static let contentHeight: CGFloat = 60

    @objc var onAccount: (() -> Void)?
    @objc var onContacts: (() -> Void)?
    @objc var onSearchBegan: (() -> Void)?
    @objc var onSearchChanged: ((String) -> Void)?
    @objc var onSearchEnded: (() -> Void)?

    private let accountButton = UIButton(type: .system)
    private let contactsButton = UIButton(type: .system)
    private let searchBar = UISearchBar()
    private let stack = UIStackView()

    @objc init() {
        super.init(frame: .zero)
        let blur = UIView()     //(the background of the bar, solid)
        blur.backgroundColor = BottomBarStyle.background
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        accountButton.addAction(UIAction { [weak self] _ in self?.onAccount?() }, for: .touchUpInside)
        contactsButton.addAction(UIAction { [weak self] _ in self?.onContacts?() }, for: .touchUpInside)
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = NSLocalizedString("Search", comment: "placeholder of the search field in the bar at the bottom of the screen")
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(accountButton)
        stack.addArrangedSubview(searchBar)
        stack.addArrangedSubview(contactsButton)
        addSubview(stack)

        let side: CGFloat = 44
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            accountButton.widthAnchor.constraint(equalToConstant: side),
            accountButton.heightAnchor.constraint(equalToConstant: side),
            contactsButton.widthAnchor.constraint(equalToConstant: side),
            contactsButton.heightAnchor.constraint(equalToConstant: side),
            searchBar.heightAnchor.constraint(equalToConstant: 56),
            //the height of the content is fixed, so the bar is as tall as its content (plus the space under it) and never grows with the keyboard
            stack.heightAnchor.constraint(equalToConstant: BottomControlsBar.contentHeight - 4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// puts the bar at the bottom of `host`, over its content; it rises with the keyboard
    @objc func install(in host: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor),
            //the content stays above the keyboard, or above the home indicator when there is no keyboard; the blur goes down to the edge
            stack.bottomAnchor.constraint(equalTo: host.keyboardLayoutGuide.topAnchor, constant: -2),
        ])
    }

    @objc func setAccountImage(_ image: UIImage?, accessibilityLabel: String?) {
        accountButton.setImage(image, for: .normal)
        accountButton.accessibilityLabel = accessibilityLabel
    }

    @objc func setContactsImage(_ image: UIImage?, accessibilityLabel: String?) {
        contactsButton.setImage(image, for: .normal)
        contactsButton.accessibilityLabel = accessibilityLabel
    }

    /// leaves the search: clears the text, closes the keyboard and brings the other buttons back
    @objc func endSearch() {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        setSearching(false)
        onSearchEnded?()
    }

    private func setSearching(_ searching: Bool) {
        searchBar.setShowsCancelButton(searching, animated: true)
        UIView.animate(withDuration: 0.25) {
            self.accountButton.isHidden = searching
            self.contactsButton.isHidden = searching
            self.stack.layoutIfNeeded()
        }
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        setSearching(true)
        onSearchBegan?()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        onSearchChanged?(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        endSearch()
    }
}

private extension UIImage {
    /// a transparent 1 pt image (the system back arrow is replaced by it)
    static let clearPixel: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }()
}

/// isaCloud: with the setting "Controls at the bottom of the screen", the screens of one navigation stack (the settings opened from the avatar, and
/// everything that opens from there) keep their title at the top and have their controls in the toolbar at the bottom: the way back on the left, and
/// the buttons of the navigation bar (confirm, close, save...) on the right. The screens are not changed: their buttons are taken from their
/// navigation item as they set them (SwiftUI sets them late and changes them, so the item is watched) and given back when the setting is turned off.
@objc
final class BottomBarNavigation : NSObject, UINavigationControllerDelegate {
    private final class Record {
        var left: [UIBarButtonItem] = []            //the buttons the screen has put on the left of its navigation bar
        var right: [UIBarButtonItem] = []           //and on the right
        var hidesBackButton = false                 //what the screen had asked for before
        var adopted = false
        var observations: [NSKeyValueObservation] = []
        var lastTakenAt: CFTimeInterval = 0         //when the buttons were last taken off the navigation item by us
    }

    private static var associationKey: UInt8 = 0
    private let records = NSMapTable<UIViewController, Record>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var busy = false
    private weak var navigation: UINavigationController?

    override init() {
        super.init()
        //the setting can be turned on or off while screens of the stack are open (it is a screen of this stack): all of them follow at once
        NotificationCenter.default.addObserver(self, selector: #selector(settingMayHaveChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func settingMayHaveChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let navigation = self.navigation else {
                return
            }
            self.updateNavigationBarLook(of: navigation)
            for viewController in navigation.viewControllers {
                self.apply(to: viewController, in: navigation, changedByScreen: false, animated: false)
            }
        }
    }

    /// Puts the screen (and the others of its navigation stack, as they are shown) in the place the setting asks for. Call it when the screen
    /// is about to appear.
    @objc static func adopt(_ viewController: UIViewController) {
        guard let navigation = viewController.navigationController else {
            return
        }
        let adopter: BottomBarNavigation
        if let existing = objc_getAssociatedObject(navigation, &associationKey) as? BottomBarNavigation {
            adopter = existing
        } else {
            adopter = BottomBarNavigation()
            objc_setAssociatedObject(navigation, &associationKey, adopter, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            navigation.delegate = adopter
            //a solid bar: the content never shows through it, and it is not drawn over the end of a table
            let appearance = BottomBarStyle.toolbarAppearance()
            navigation.toolbar.standardAppearance = appearance
            navigation.toolbar.scrollEdgeAppearance = appearance
            navigation.toolbar.compactAppearance = appearance
            navigation.toolbar.isTranslucent = false
        }
        adopter.navigation = navigation
        adopter.updateNavigationBarLook(of: navigation)
        adopter.apply(to: viewController, in: navigation, changedByScreen: false, animated: false)
    }

    /// The navigation bar of the stack: with the controls at the bottom its own back button is invisible from the start (hiding it when a screen is
    /// about to be shown is too late: it shows at the top for the first moments of the transition); without them everything is as it was.
    private var originalBarAppearances: (standard: UINavigationBarAppearance, scrollEdge: UINavigationBarAppearance?, compact: UINavigationBarAppearance?)?

    private func updateNavigationBarLook(of navigation: UINavigationController) {
        let bar = navigation.navigationBar
        if ControlsAtBottom.isOn {
            if originalBarAppearances == nil {
                originalBarAppearances = (bar.standardAppearance, bar.scrollEdgeAppearance, bar.compactAppearance)
            }
            func withoutBackButton(_ source: UINavigationBarAppearance) -> UINavigationBarAppearance {
                let appearance = source.copy()
                let clear = UIImage.clearPixel
                appearance.setBackIndicatorImage(clear, transitionMaskImage: clear)
                let invisible: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear, .font: UIFont.systemFont(ofSize: 1)]
                for style in [appearance.backButtonAppearance, appearance.doneButtonAppearance].map({ $0 }) {
                    for state in [style.normal, style.highlighted, style.disabled, style.focused] {
                        state.titleTextAttributes = invisible
                    }
                }
                return appearance
            }
            if let original = originalBarAppearances {
                bar.standardAppearance = withoutBackButton(original.standard)
                bar.scrollEdgeAppearance = withoutBackButton(original.scrollEdge ?? original.standard)
                bar.compactAppearance = withoutBackButton(original.compact ?? original.standard)
            }
        } else if let original = originalBarAppearances {
            bar.standardAppearance = original.standard
            bar.scrollEdgeAppearance = original.scrollEdge
            bar.compactAppearance = original.compact
            originalBarAppearances = nil
        }
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        updateNavigationBarLook(of: navigationController)
        apply(to: viewController, in: navigationController, changedByScreen: false, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        //SwiftUI puts the buttons of a screen on its navigation item after the screen was shown
        apply(to: viewController, in: navigationController, changedByScreen: false, animated: false)
    }

    private func record(for viewController: UIViewController) -> Record {
        if let existing = records.object(forKey: viewController) {
            return existing
        }
        let created = Record()
        records.setObject(created, forKey: viewController)
        return created
    }

    private func apply(to viewController: UIViewController, in navigation: UINavigationController, changedByScreen: Bool, animated: Bool) {
        if busy {
            return      //a change we made ourselves
        }
        busy = true
        defer { busy = false }
        let record = record(for: viewController)
        let item = viewController.navigationItem

        if ControlsAtBottom.isOn {
            if !record.adopted {
                record.adopted = true
                record.hidesBackButton = item.hidesBackButton
                watch(viewController, in: navigation, record: record)
            }
            //the buttons the screen has set are taken over; when there are none and the screen did not just remove them, the ones taken before stay
            //(SwiftUI puts them in the item groups of the navigation item, UIKit screens in the left and right lists, which are the same thing for UIKit:
            //every button is taken once)
            let currentLeft = BottomBarNavigation.uniqued((item.leftBarButtonItems ?? []) + item.leadingItemGroups.flatMap { $0.barButtonItems })
            let currentRight = BottomBarNavigation.uniqued((item.rightBarButtonItems ?? []) + item.trailingItemGroups.flatMap { $0.barButtonItems })
            if changedByScreen && currentLeft.isEmpty && currentRight.isEmpty && CACurrentMediaTime() - record.lastTakenAt < 0.5 {
                return      //UIKit tells about the buttons we took off a little later: that is not the screen removing them
            }
            if !currentLeft.isEmpty || !currentRight.isEmpty || changedByScreen {
                record.left = currentLeft
                record.right = currentRight
            }
            if item.leftBarButtonItems != nil {
                item.leftBarButtonItems = nil
            }
            if item.rightBarButtonItems != nil {
                item.rightBarButtonItems = nil
            }
            //(the groups are only touched when the screen uses them: setting them on every screen leaves the bar laid out differently afterwards)
            if !item.leadingItemGroups.isEmpty {
                item.leadingItemGroups = []
            }
            if !item.trailingItemGroups.isEmpty {
                item.trailingItemGroups = []
            }
            if navigation.viewControllers.first !== viewController {
                item.hidesBackButton = true     //(the first screen has no back button: leaving it alone keeps the bar as it was)
            }
            record.lastTakenAt = CACurrentMediaTime()

            var items: [UIBarButtonItem] = []
            if let back = backItem(for: viewController, in: navigation) {
                items.append(back)
            }
            items.append(UIBarButtonItem.flexibleSpace())
            //back is on the left; whatever else the screen has (close, cancel, confirm, save) is on the right
            items.append(contentsOf: record.left + record.right)
            viewController.toolbarItems = items.count > 1 ? items : nil
        } else if record.adopted {
            record.observations = []
            record.adopted = false
            item.leftBarButtonItems = record.left.isEmpty ? nil : record.left
            item.rightBarButtonItems = record.right.isEmpty ? nil : record.right
            if navigation.viewControllers.first !== viewController {
                item.hidesBackButton = record.hidesBackButton
            }
            record.left = []
            record.right = []
            viewController.toolbarItems = nil
        }
        if navigation.topViewController === viewController {
            navigation.setToolbarHidden(viewController.toolbarItems?.isEmpty ?? true, animated: animated)
        }
        //the bar keeps the place it had given to the title while the buttons were elsewhere (the title came up next to the "Close" button): it is
        //laid out again once the buttons are back
        DispatchQueue.main.async { [weak navigation] in
            navigation?.navigationBar.setNeedsLayout()
            navigation?.navigationBar.layoutIfNeeded()
        }
    }

    /// the screen may change its buttons later (SwiftUI does, when its state changes): they are taken over again
    private func watch(_ viewController: UIViewController, in navigation: UINavigationController, record: Record) {
        let item = viewController.navigationItem
        let changed: (UINavigationItem, NSKeyValueObservedChange<[UIBarButtonItem]?>) -> Void = { [weak self, weak viewController, weak navigation] _, _ in
            guard let self, let viewController, let navigation else {
                return
            }
            self.apply(to: viewController, in: navigation, changedByScreen: true, animated: false)
        }
        let changedSingle: (UINavigationItem, NSKeyValueObservedChange<UIBarButtonItem?>) -> Void = { [weak self, weak viewController, weak navigation] _, _ in
            guard let self, let viewController, let navigation else {
                return
            }
            self.apply(to: viewController, in: navigation, changedByScreen: true, animated: false)
        }
        let changedGroups: (UINavigationItem, NSKeyValueObservedChange<[UIBarButtonItemGroup]>) -> Void = { [weak self, weak viewController, weak navigation] _, _ in
            guard let self, let viewController, let navigation else {
                return
            }
            self.apply(to: viewController, in: navigation, changedByScreen: true, animated: false)
        }
        record.observations = [
            item.observe(\.leftBarButtonItems, options: [.new], changeHandler: changed),
            item.observe(\.rightBarButtonItems, options: [.new], changeHandler: changed),
            item.observe(\.leftBarButtonItem, options: [.new], changeHandler: changedSingle),
            item.observe(\.rightBarButtonItem, options: [.new], changeHandler: changedSingle),
            item.observe(\.leadingItemGroups, options: [.new], changeHandler: changedGroups),
            item.observe(\.trailingItemGroups, options: [.new], changeHandler: changedGroups),
        ]
    }

    private static func uniqued(_ items: [UIBarButtonItem]) -> [UIBarButtonItem] {
        var seen = Set<ObjectIdentifier>()
        return items.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// the way back, on the left: an arrow and the title of the screen before, as the system's own back button has
    private func backItem(for viewController: UIViewController, in navigation: UINavigationController) -> UIBarButtonItem? {
        guard let index = navigation.viewControllers.firstIndex(of: viewController), index > 0 else {
            return nil
        }
        let previous = navigation.viewControllers[index - 1]
        let title = previous.navigationItem.backButtonTitle ?? previous.navigationItem.title ?? previous.title ?? NSLocalizedString("Back", comment: "")
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.backward", withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))
        configuration.title = title
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = NSLocalizedString("Back", comment: "")
        button.addAction(UIAction { [weak navigation] _ in
            navigation?.popViewController(animated: true)
        }, for: .touchUpInside)
        return UIBarButtonItem(customView: button)
    }
}

/// isaCloud: a list that grows from the bottom up (the first row is the one next to the controls at the bottom of the screen): the list is turned
/// upside down and every row (see bottomUpRow) is turned back. The rows are still a List, so swipe actions, menus and the like keep working.
struct BottomUpList : ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            GeometryReader { geometry in
                content
                    .scaleEffect(x: 1, y: -1)
                    //the navigation bar is not a margin of the list any more (it would show up at the bottom, turned over): the list goes under it
                    //and keeps its own margin at its end, which is the top of the screen
                    .ignoresSafeArea(.container, edges: .top)
                    .contentMargins(.bottom, geometry.safeAreaInsets.top, for: .scrollContent)
            }
        } else {
            content
        }
    }
}

extension View {
    /// isaCloud: see BottomUpList
    func bottomUpList(_ isOn: Bool) -> some View {
        modifier(BottomUpList(isOn: isOn))
    }

    /// isaCloud: turns a row of a bottom up list back (see BottomUpList)
    func bottomUpRow(_ isOn: Bool) -> some View {
        scaleEffect(x: 1, y: isOn ? -1 : 1)
    }
}

/// isaCloud: the system search field (UISearchBar, minimal style) for SwiftUI screens that keep their search at the bottom of the screen
struct BottomSearchField : UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = NSLocalizedString("Search", comment: "placeholder of the search field in the bar at the bottom of the screen")
        searchBar.delegate = context.coordinator
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.keyboardType = .emailAddress
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        if searchBar.text != text {
            searchBar.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator : NSObject, UISearchBarDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: true)
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(false, animated: true)
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            text = ""
            searchBar.text = ""
            searchBar.resignFirstResponder()
        }
    }
}

/// isaCloud: what the search bar of the home screen finds: the names of contacts, groups and channels, and, when the person asks for it,
/// the messages that have the words
final class ChatListSearchModel : ObservableObject {
    @Published var query = ""
    @Published var results: [MLContact] = []
    /// the list shows the messages found instead of the names
    @Published var showMessages = false
    let messages = MessageSearchModel()

    func update(query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = self.query.isEmpty ? [] : (DataLayer.sharedInstance().searchContacts(with: self.query) as? [MLContact] ?? [])
        if self.query.isEmpty {
            showMessages = false
            messages.search("")
        } else if showMessages {
            messages.search(self.query)
        }
    }

    func setShowMessages(_ show: Bool) {
        showMessages = show
        if show {
            messages.search(query, immediately: true)
        }
    }
}

struct ChatListSearchResults : View {
    @ObservedObject var model: ChatListSearchModel
    let onSelect: (MLContact) -> Void
    let onSelectMessage: (MLContact, NSNumber) -> Void

    var body: some View {
        if model.query.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                //two fixed tabs: the names of contacts, groups and channels, or the text of the messages
                Picker("", selection: Binding(get: { model.showMessages }, set: { model.setShowMessages($0) })) {
                    Text("Names").tag(false)
                    Text("Messages in search").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                if model.showMessages {
                    MessageSearchResultsList(model: model.messages, onSelect: onSelectMessage)
                } else if model.results.isEmpty {
                    ContentUnavailableShimView.search(text: model.query)
                } else {
                    List(Array(model.results.enumerated()), id: \.offset) { _, contact in
                        Button {
                            onSelect(contact)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.contactDisplayNameWithoutSelfnotesPrefix)
                                Text(contact.contactJid)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            //the tabs stay at the top, also when there is nothing to show (the view would center what is smaller than the screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// isaCloud: the results view of the home screen's search controller, used by ActiveChatsViewController
@objc
class ChatListSearch : NSObject {
    private let model: ChatListSearchModel
    @objc let resultsController: UIViewController

    @objc
    init(onSelect: @escaping (MLContact) -> Void, onSelectMessage: @escaping (MLContact, NSNumber) -> Void) {
        let model = ChatListSearchModel()
        self.model = model
        resultsController = UIHostingController(rootView: ChatListSearchResults(model: model, onSelect: onSelect, onSelectMessage: onSelectMessage))
        super.init()
    }

    @objc
    func update(query: String) {
        model.update(query: query)
    }
}

/// isaCloud: scene lifecycle (required on iOS 27). The window is still owned by the app delegate, so the scene only hands it over.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    //isaCloud: with scenes, UIKit no longer calls the app delegate's lifecycle methods; they are forwarded from here
    private var hasEnteredForeground = false
    private var appDelegate: UIApplicationDelegate? {
        return UIApplication.shared.delegate
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        if window == nil {
            window = windowScene.windows.first
        }
        (UIApplication.shared.delegate as? MonalAppDelegate)?.window = window
        for context in connectionOptions.urlContexts {
            _ = appDelegate?.application?(UIApplication.shared, open: context.url, options: [:])
        }
        for activity in connectionOptions.userActivities {
            _ = appDelegate?.application?(UIApplication.shared, continue: activity, restorationHandler: { _ in })
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        appDelegate?.applicationDidBecomeActive?(UIApplication.shared)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        //the app state is "background" while a scene launches, so the first foreground has to be handled, too (otherwise the accounts stay in the background state and never connect)
        guard hasEnteredForeground else {
            //launch: everything else was set up by didFinishLaunching, only the flags have to learn that we are in the foreground
            //(unfreezing the accounts here waits for their receive queues, which can be busy for a long time and froze the app)
            hasEnteredForeground = true
            MLXMPPManager.sharedInstance().nowForegroundedAtLaunch()
            return
        }
        appDelegate?.applicationWillEnterForeground?(UIApplication.shared)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        appDelegate?.applicationDidEnterBackground?(UIApplication.shared)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            _ = appDelegate?.application?(UIApplication.shared, open: context.url, options: [:])
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = appDelegate?.application?(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
    }
}

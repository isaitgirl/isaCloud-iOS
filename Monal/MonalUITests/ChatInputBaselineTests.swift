//
//  ChatInputBaselineTests.swift
//  MonalUITests
//
//  Behavior of the chat input that must not regress when the input bar changes.
//  They use the self chat "Notas para si mesmo" (messages only go to our own account).
//

import XCTest

final class ChatInputBaselineTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - helpers

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--disableAnimations"]
        app.launch()
        return app
    }

    /// Opens the self chat from the contacts list. The draft left by an earlier run is cleared, unless the test is checking drafts.
    private func openSelfChat(_ app: XCUIApplication, clearingDraft: Bool = true) {
        let contactsButton = app.buttons["person.2.fill"]
        XCTAssertTrue(contactsButton.waitForExistence(timeout: 30), "chat list did not show up")
        contactsButton.tap()
        let selfChat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notas para si mesmo")).firstMatch
        XCTAssertTrue(selfChat.waitForExistence(timeout: 10), "self chat missing in contacts")
        selfChat.tap()
        XCTAssertTrue(messageField(app).waitForExistence(timeout: 10), "chat input did not show up")
        if clearingDraft {
            clearDraft(app)
        }
    }

    /// removes a draft left by an earlier run, so every test starts with an empty input
    private func clearDraft(_ app: XCUIApplication) {
        let field = messageField(app)
        let value = field.value as? String ?? ""
        guard value.hasPrefix("uitest-") else {
            return
        }
        // the input has a clear button while it has text
        let clear = app.buttons.matching(identifier: "clearTextButton").firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "clear button of the input not shown")
        clear.tap()
        XCTAssertTrue(element(app, label: "microphone").waitForExistence(timeout: 5), "draft could not be cleared")
    }

    private func messageField(_ app: XCUIApplication) -> XCUIElement {
        // the placeholder disappears when the input has text (a draft), so also match the typed value
        // the placeholder is translated (pt-BR: "Escreva uma mensagem..."), so both texts are accepted
        return app.descendants(matching: .any).matching(NSPredicate(format: "placeholderValue IN %@ OR value BEGINSWITH %@", ["Type a message...", "Escreva uma mensagem..."], "uitest-")).firstMatch
    }

    /// any element with this label: the microphone is a button, the attach icon is an image inside a button
    private func element(_ app: XCUIApplication, label: String) -> XCUIElement {
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// the send button of the chat input (a button labelled "arrowSend" in the ExyteChat input)
    private func sendButton(_ app: XCUIApplication) -> XCUIElement {
        return app.buttons.matching(NSPredicate(format: "label == %@", "arrowSend")).firstMatch
    }

    private func uniqueText() -> String {
        return "uitest-\(UUID().uuidString.prefix(8))"
    }

    // MARK: - tests

    func test_emptyInput_showsMicrophoneAndNoSend() throws {
        let app = launchApp()
        openSelfChat(app)
        XCTAssertTrue(element(app, label: "microphone").waitForExistence(timeout: 5))
        XCTAssertFalse(sendButton(app).exists)
    }

    func test_typedText_showsSend_andSendingAddsTheMessage() throws {
        let app = launchApp()
        openSelfChat(app)
        let text = uniqueText()

        messageField(app).tap()
        messageField(app).typeText(text)
        XCTAssertTrue(sendButton(app).waitForExistence(timeout: 5), "send button not shown after typing")
        XCTAssertFalse(element(app, label: "microphone").exists)

        sendButton(app).tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 15), "sent message not shown in the chat")
        XCTAssertTrue(element(app, label: "microphone").waitForExistence(timeout: 5), "microphone not back after sending")
        XCTAssertFalse(sendButton(app).exists)
    }

    func test_draft_isKeptWhenLeavingAndComingBack() throws {
        let app = launchApp()
        openSelfChat(app)
        let text = uniqueText()

        messageField(app).tap()
        messageField(app).typeText(text)
        XCTAssertTrue(sendButton(app).waitForExistence(timeout: 5))

        // leave the chat with the back button in the top left corner (the keyboard may be on screen)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.06)).tap()
        XCTAssertTrue(app.buttons["person.2.fill"].waitForExistence(timeout: 10))
        openSelfChat(app, clearingDraft: false)

        let value = messageField(app).value as? String ?? ""
        XCTAssertTrue(value.contains(text), "draft lost after leaving the chat, got: \(value)")
        // clean up the draft so the next tests start empty
        sendButton(app).tap()
    }

    /// a tap on the microphone starts a locked recording with its controls; deleting it brings the text input back
    /// (needs the microphone permission: xcrun simctl privacy <device> grant microphone br.com.isacloud.messenger)
    func test_microphoneTap_startsRecording_andDeleteReturnsToTheInput() throws {
        let app = launchApp()
        openSelfChat(app)
        let mic = element(app, label: "microphone")
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()
        // the first recording asks for the microphone permission: accept it if the system asks
        let allow = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "Permitir", "OK"])).firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        let delete = app.descendants(matching: .any).matching(identifier: "deleteRecording").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "recording controls not shown")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sendRecording").firstMatch.exists)
        delete.tap()
        XCTAssertTrue(messageField(app).waitForExistence(timeout: 5), "input not back after deleting the recording")
        XCTAssertTrue(element(app, label: "microphone").waitForExistence(timeout: 5))
    }

    /// needs a build with the Giphy key (GIPHY_API_KEY): picking a GIF must add it to the input as an attachment
    func test_gifPicker_tappingAGif_addsItToTheInput() throws {
        let app = launchApp()
        openSelfChat(app)
        element(app, label: "attach").tap()
        let gifItem = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "GIF")).firstMatch
        XCTAssertTrue(gifItem.waitForExistence(timeout: 5), "GIF menu item missing")
        gifItem.tap()
        let firstGif = app.buttons.matching(NSPredicate(format: "label == %@", "GIF")).firstMatch
        XCTAssertTrue(firstGif.waitForExistence(timeout: 20), "no GIF results shown")
        firstGif.tap()
        let remove = app.buttons.matching(NSPredicate(format: "label == %@", "Remove attachment")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 30), "tapped GIF was not added to the input")
    }

    /// the attach menu offers the location; choosing it opens the map, and sending closes it
    /// (needs the location permission: xcrun simctl privacy <device> grant location br.com.isacloud.messenger)
    func test_location_opensMap_andSendingClosesIt() throws {
        let app = launchApp()
        openSelfChat(app)
        element(app, label: "attach").tap()
        // the app runs in Portuguese on the test simulator, so both titles are accepted
        let locationItem = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Location", "Localização"])).firstMatch
        XCTAssertTrue(locationItem.waitForExistence(timeout: 5), "Location menu item missing")
        locationItem.tap()
        let send = app.buttons.matching(NSPredicate(format: "label IN %@", ["Send this location", "Enviar esta localização"])).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "send button of the map not shown")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 15)
        send.tap()
        XCTAssertTrue(send.waitForNonExistence(timeout: 15), "map did not close after sending the location")
    }

    func test_attachButton_opensAttachMenu() throws {
        let app = launchApp()
        openSelfChat(app)
        let attach = element(app, label: "attach")
        XCTAssertTrue(attach.waitForExistence(timeout: 5))
        let before = app.descendants(matching: .any).count
        attach.tap()
        // the attach menu adds options to the screen; it must grow
        let grew = NSPredicate { _, _ in app.descendants(matching: .any).count > before }
        expectation(for: grew, evaluatedWith: NSObject())
        waitForExpectations(timeout: 5)
        // dismiss without choosing anything
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
    }

    // MARK: - reply and edit

    private func sendText(_ app: XCUIApplication, _ text: String) {
        messageField(app).tap()
        messageField(app).typeText(text)
        XCTAssertTrue(sendButton(app).waitForExistence(timeout: 5))
        sendButton(app).tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 15), "message \(text) not shown")
    }

    private func menuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// leaves the chat and opens it again (the keyboard goes away, so the bubbles are reachable)
    private func reopenChat(_ app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["person.2.fill"].waitForExistence(timeout: 10))
        openSelfChat(app)
    }

    /// opens the message menu of a sent message: a 0.6 s long press on the bubble text
    private func openMessageMenu(_ app: XCUIApplication, text: String) {
        let bubble = app.staticTexts[text]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "sent message not visible")
        let frame = bubble.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).press(forDuration: 0.6)
    }

    func test_edit_loadsTheText_andSavingUpdatesTheMessage() throws {
        let app = launchApp()
        openSelfChat(app)
        let original = uniqueText()
        sendText(app, original)
        reopenChat(app)

        openMessageMenu(app, text: original)
        // the menu titles come from ExyteChat ("Edit") and from the app ("Editar"), depending on the language
        let edit = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "Edit", "Editar")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "edit menu item missing")
        edit.tap()

        XCTAssertEqual(messageField(app).value as? String, original, "edit did not load the message text")

        // replace the loaded text: the clear button empties the input, then the new text is typed
        let edited = uniqueText()
        app.buttons.matching(identifier: "clearTextButton").firstMatch.tap()
        messageField(app).tap()
        messageField(app).typeText(edited)
        // in edit mode the trailing button is the checkmark that saves the edit
        let save = app.buttons.matching(identifier: "checkmark").firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "save button of the edit not shown")
        XCTAssertEqual(messageField(app).value as? String, edited, "typed text did not replace the edited text")
        save.tap()
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 15), "edited text not shown")
        XCTAssertFalse(app.staticTexts[original].exists, "original text still shown after editing")
    }
}

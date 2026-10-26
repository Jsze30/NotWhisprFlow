import AppKit
import XCTest
@testable import WhisperFlow

final class PasterTests: XCTestCase {
    func testMissingAccessibilityStillPastesAndKeepsClipboard() {
        checkDelivery(isTextInput: false, before: nil, after: nil, expectedUnconfirmed: true)
    }

    func testOpaqueTextEditorStillPastes() {
        checkDelivery(isTextInput: true, before: nil, after: nil, expectedUnconfirmed: false)
    }

    func testReadableTextEditorPastesSuccessfully() {
        checkDelivery(isTextInput: true, before: "", after: "Hello ", expectedUnconfirmed: false)
    }

    func testRejectedPasteKeepsClipboard() {
        checkDelivery(isTextInput: true, before: "", after: "", expectedUnconfirmed: true)
    }

    func testSwitchingAppsCancelsPasteButKeepsClipboard() {
        checkDelivery(isTextInput: true, before: "", after: "", expectedUnconfirmed: true, switchApp: true)
    }

    private func checkDelivery(isTextInput: Bool, before: String?, after: String?,
                               expectedUnconfirmed: Bool, switchApp: Bool = false) {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.setString("Original clipboard", forType: .string)
        var value = before
        var pasteCount = 0
        var enterCount = 0
        var completed = false
        var environment = Paster.Environment()
        environment.pasteboard = pb
        environment.destination = {
            Paster.Destination(applicationID: 42, isTextInput: isTextInput, value: { value })
        }
        environment.frontmostApplicationID = { switchApp ? 43 : 42 }
        environment.postPaste = {
            XCTAssertEqual(pb.string(forType: .string), "Hello")
            pasteCount += 1
            value = after
        }
        environment.postEnter = { enterCount += 1 }
        environment.schedule = { _, action in action() }
        Paster.paste("Hello", pressEnter: true, environment: environment) { accepted in
            XCTAssertEqual(!accepted, expectedUnconfirmed)
            completed = true
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(pasteCount, switchApp ? 0 : 1)
        XCTAssertEqual(enterCount, expectedUnconfirmed ? 0 : 1)
        XCTAssertEqual(pb.string(forType: .string), "Hello")
    }

    func testUnchangedOrInaccessibleTextCannotConfirmPaste() {
        XCTAssertFalse(Paster.insertionConfirmed(before: nil, after: nil, text: "Hello"))
        XCTAssertFalse(Paster.insertionConfirmed(before: "Hello", after: "Hello", text: "Hello"))
        XCTAssertFalse(Paster.insertionConfirmed(before: "", after: "Other", text: "Hello"))
        XCTAssertFalse(Paster.insertionConfirmed(before: "Hello", after: "Hello world", text: "Hello"))
        XCTAssertTrue(Paster.insertionConfirmed(before: "Before ", after: "Before Hello ", text: "Hello"))
    }

    func testNewCopyDuringPasteIsNotOverwritten() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        var environment = Paster.Environment()
        environment.pasteboard = pb
        environment.destination = { Paster.Destination(applicationID: 42, isTextInput: false, value: { nil }) }
        environment.frontmostApplicationID = { 42 }
        environment.schedule = { _, action in action() }
        environment.postPaste = {
            XCTAssertEqual(pb.string(forType: .string), "Hello ")
            pb.clearContents()
            pb.setString("New user copy", forType: .string)
        }
        Paster.paste("Hello", environment: environment)
        XCTAssertEqual(pb.string(forType: .string), "New user copy")
    }

    func testOrdinaryDictationRemainsAvailableAfterPasteAttempt() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        var environment = Paster.Environment()
        environment.pasteboard = pb
        environment.destination = { Paster.Destination(applicationID: 42, isTextInput: false, value: { nil }) }
        environment.frontmostApplicationID = { 42 }
        environment.schedule = { _, action in action() }
        environment.postPaste = { XCTAssertEqual(pb.string(forType: .string), "Hello ") }
        Paster.paste("Hello", environment: environment)
        XCTAssertEqual(pb.string(forType: .string), "Hello ")
    }

    func testEnterOnlyDoesNotEraseClipboard() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.setString("Previous dictation", forType: .string)
        var environment = Paster.Environment()
        environment.pasteboard = pb
        var enterCount = 0
        environment.postEnter = { enterCount += 1 }
        environment.postPaste = { XCTFail("Empty text should not be pasted") }
        Paster.paste("", pressEnter: true, environment: environment)
        XCTAssertEqual(enterCount, 1)
        XCTAssertEqual(pb.string(forType: .string), "Previous dictation")
    }
}

import AppKit
import XCTest
@testable import WhisperFlow

final class SentenceContinuationTests: XCTestCase {
    func testMidSentenceLowercasesFirstWord() {
        for preceding in ["I went to the", "I went to the ", "Apples, oranges,", "First part;\t", "Room 42 "] {
            XCTAssertEqual(adjust("Store and back.", after: preceding), "store and back.", preceding)
        }
        XCTAssertEqual(adjust("Don't stop.", after: "Please"), "don't stop.")
    }

    func testSentenceStartKeepsCapital() {
        for preceding in [nil, "", "  ", "Done.", "Really? ", "Wow!", "Line one\n", "Title:", "(note) "] {
            XCTAssertEqual(adjust("Store and back.", after: preceding), "Store and back.", preceding ?? "nil")
        }
    }

    func testPronounsNamesAndAcronymsKeepCapital() {
        for text in ["I think so.", "I'm here.", "I’ll go.", "I've seen it.", "API keys work.",
                     "iPhone sales grew.", "John said hi.", "London is far.", "1. First item"] {
            XCTAssertEqual(adjust(text, after: "and then"), text)
        }
    }

    func testVocabularyTermsKeepCapital() {
        XCTAssertEqual(adjust("Whisper Flow works.", after: "and", terms: ["Whisper Flow"]), "Whisper Flow works.")
        XCTAssertEqual(adjust("Deepgram works.", after: "and", terms: ["Deepgram"]), "Deepgram works.")
    }

    func testPasterUsesTextBeforeCursor() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        var environment = Paster.Environment()
        environment.pasteboard = pb
        environment.destination = {
            Paster.Destination(applicationID: 42, isTextInput: true, value: { nil },
                               precedingText: { "I went to the " })
        }
        environment.frontmostApplicationID = { 42 }
        environment.postPaste = {}
        environment.schedule = { _, action in action() }
        Paster.paste("Store.", environment: environment)
        XCTAssertEqual(pb.string(forType: .string), "store. ")
    }

    private func adjust(_ text: String, after preceding: String?, terms: [String] = []) -> String {
        SentenceContinuation.adjust(text, after: preceding, preserving: terms)
    }
}

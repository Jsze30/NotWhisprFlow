import AppKit
import QuartzCore
import XCTest
@testable import WhisperFlow

final class OverlayTests: XCTestCase {
    @MainActor
    func testOpeningDiscardsStartupSpikeButRespondsToSpeechAfterReveal() async throws {
        let view = IndicatorView(frame: NSRect(x: 0, y: 0, width: 83.2, height: 34))
        let pill = try XCTUnwrap(view.layer?.sublayers?.first)
        let bars = Array(try XCTUnwrap(pill.sublayers).prefix(11))
        let opened = expectation(description: "Recording indicators revealed")

        view.setState(.recording) { opened.fulfill() }
        // Simulate the initial hotkey/click spike arriving while the pill expands.
        view.updateLevel(1)
        view.updateLevel(0.8)
        XCTAssertTrue(bars.allSatisfy(\.isHidden))
        CATransaction.flush()
        await fulfillment(of: [opened], timeout: 2)

        XCTAssertTrue(bars.allSatisfy { !$0.isHidden })
        XCTAssertTrue(bars.allSatisfy { abs($0.transform.m22 - 0.1) < 0.001 })
        XCTAssertTrue(bars.allSatisfy { $0.animation(forKey: "hidden") == nil })

        view.updateLevel(0.7)
        XCTAssertEqual(try XCTUnwrap(bars.last).transform.m22, 0.7, accuracy: 0.001)
        XCTAssertTrue(bars.dropLast().allSatisfy { abs($0.transform.m22 - 0.1) < 0.001 })
    }

    @MainActor
    func testInterruptedOpeningCannotRevealOldBars() async throws {
        let view = IndicatorView(frame: NSRect(x: 0, y: 0, width: 83.2, height: 34))
        let pill = try XCTUnwrap(view.layer?.sublayers?.first)
        let bars = Array(try XCTUnwrap(pill.sublayers).prefix(11))
        let openingFinished = expectation(description: "Superseded opening finished")
        let collapsed = expectation(description: "Idle transition finished")

        view.setState(.recording) { openingFinished.fulfill() }
        view.updateLevel(1)
        view.setState(.idle) { collapsed.fulfill() }
        CATransaction.flush()
        await fulfillment(of: [openingFinished, collapsed], timeout: 2)

        view.updateLevel(1)
        XCTAssertTrue(bars.allSatisfy(\.isHidden))
        XCTAssertTrue(bars.allSatisfy { abs($0.transform.m22 - 0.1) < 0.001 })
    }
}

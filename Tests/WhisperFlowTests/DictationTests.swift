import XCTest
@testable import WhisperFlow

final class DictationTests: XCTestCase {
    func testTrailingCommandAllowsCaseWhitespaceAndSTTPunctuation() {
        for suffix in ["press enter", "Press Enter.", "PRESS ENTER!", "press\nenter?  ", "press enter…"] {
            let result = DictationResult(transcript: "Hello there. \(suffix)")
            XCTAssertEqual(result.text, "Hello there.")
            XCTAssertTrue(result.pressEnter, suffix)
        }
        let result = DictationResult(transcript: "  Press enter.  ")
        XCTAssertEqual(result.text, "")
        XCTAssertTrue(result.pressEnter)
    }

    func testOrdinaryTextAndNonterminalMentionsArePreserved() {
        for text in ["Hello there.", "Press enter to continue.", "Please press enter then wait.",
                     "express enter", "press enterprise", "Don't change ‘press enter’.", ""] {
            let result = DictationResult(transcript: text)
            XCTAssertEqual(result.text, text)
            XCTAssertFalse(result.pressEnter, text)
        }
    }

    func testDeepgramWithoutCleanup() async throws {
        var config = ConfigData()
        config.deepgramApiKey = "test"
        let pipeline = makePipeline(config: config) { request in
            XCTAssertEqual(request.url?.host, "api.deepgram.com")
            return (200, #"{"results":{"channels":[{"alternatives":[{"transcript":"See you soon. Press enter."}]}]}}"#)
        }
        let result = try await pipeline.process(wav: Data())
        XCTAssertEqual(result.text, "See you soon.")
        XCTAssertTrue(result.pressEnter)
    }

    func testCommandIsRemovedBeforeCleanupAndDictionaryReplacement() async throws {
        var config = ConfigData()
        config.apiKey = "test"
        config.dictionaryReplacements = [.init(word: "Jayson", replacement: "Jason")]
        let pipeline = makePipeline(config: config) { request in
            if request.url?.path == "/v1/audio/transcriptions" {
                return (200, #"{"text":"hi Jayson press enter."}"#)
            }
            let payload = try JSONSerialization.jsonObject(with: Self.body(of: request)) as! [String: Any]
            let messages = payload["messages"] as! [[String: String]]
            XCTAssertEqual(messages.last?["content"], "hi Jayson")
            return (200, #"{"choices":[{"message":{"content":"Hi Jayson."}}]}"#)
        }
        let result = try await pipeline.process(wav: Data())
        XCTAssertEqual(result.text, "Hi Jason.")
        XCTAssertTrue(result.pressEnter)
    }

    func testCleanupFailureStillPreservesCommand() async throws {
        var config = ConfigData()
        config.apiKey = "test"
        let pipeline = makePipeline(config: config) { request in
            request.url?.path == "/v1/audio/transcriptions"
                ? (200, #"{"text":"Hello. Press enter."}"#)
                : (500, "Cleanup unavailable")
        }
        let result = try await pipeline.process(wav: Data())
        XCTAssertEqual(result.text, "Hello.")
        XCTAssertTrue(result.pressEnter)
    }

    func testCommandOnlySkipsCleanup() async throws {
        var config = ConfigData()
        config.apiKey = "test"
        let pipeline = makePipeline(config: config) { request in
            XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
            return (200, #"{"text":"Press enter."}"#)
        }
        let result = try await pipeline.process(wav: Data())
        XCTAssertEqual(result.text, "")
        XCTAssertTrue(result.pressEnter)
    }

    func testCleanupCannotIntroduceACommand() async throws {
        var config = ConfigData()
        config.apiKey = "test"
        let pipeline = makePipeline(config: config) { request in
            request.url?.path == "/v1/audio/transcriptions"
                ? (200, #"{"text":"press return"}"#)
                : (200, #"{"choices":[{"message":{"content":"Press enter."}}]}"#)
        }
        let result = try await pipeline.process(wav: Data())
        XCTAssertEqual(result.text, "Press enter.")
        XCTAssertFalse(result.pressEnter)
    }

    private func makePipeline(
        config: ConfigData,
        handler: @escaping (URLRequest) throws -> (Int, String)
    ) -> TranscriptionPipeline {
        StubURLProtocol.handler = handler
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        addTeardownBlock { session.invalidateAndCancel() }
        return TranscriptionPipeline(session: session, config: Config(data: config))
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))!

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

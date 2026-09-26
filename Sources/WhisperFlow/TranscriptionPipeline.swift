import Foundation

enum PipelineError: Error, LocalizedError {
    case http(Int, String)
    case decode
    case empty
    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .decode: return "Failed to decode response"
        case .empty: return "Empty transcription"
        }
    }
}

final class TranscriptionPipeline {
    private let session: URLSession
    private let config: Config

    init(session: URLSession = .shared, config: Config = .shared) {
        self.session = session
        self.config = config
    }

    func process(wav: Data) async throws -> DictationResult {
        let raw: String
        if !config.deepgramApiKey.isEmpty {
            raw = try await transcribeDeepgram(wav: wav)
        } else {
            do {
                raw = try await transcribe(wav: wav, model: config.data.transcriptionModel)
            } catch {
                NSLog("[WhisperFlow] transcribe with %@ failed: %@ — falling back to whisper-1",
                      config.data.transcriptionModel, "\(error)")
                raw = try await transcribe(wav: wav, model: "whisper-1")
            }
        }
        NSLog("[WhisperFlow] raw transcript: %@", raw)
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PipelineError.empty
        }
        var result = DictationResult(transcript: raw)
        // A command-only dictation should press Enter without a paste or cleanup call.
        guard !result.text.isEmpty else { return result }
        result.text = SpokenListFormatter.format(result.text)
        if config.data.enableCleanup && !config.apiKey.isEmpty {
            do {
                let cleaned = try await cleanup(text: result.text)
                NSLog("[WhisperFlow] cleaned: %@", cleaned)
                result.text = cleaned
            } catch {
                NSLog("[WhisperFlow] cleanup failed: %@ - using raw text", "\(error)")
            }
        }
        result.text = applyDictionaryReplacements(to: SpokenListFormatter.format(result.text))
        return result
    }

    // MARK: - Transcription

    private func transcribe(wav: Data, model: String) async throws -> String {
        let boundary = "----WhisperFlow\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func part(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        part("model", model)
        part("response_format", "json")
        let vocab = vocabularyTerms().joined(separator: ", ")
        if !vocab.isEmpty {
            part("prompt", vocab)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PipelineError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        struct TR: Decodable { let text: String }
        guard let parsed = try? JSONDecoder().decode(TR.self, from: data) else {
            throw PipelineError.decode
        }
        return parsed.text
    }

    // MARK: - Deepgram

    private func transcribeDeepgram(wav: Data) async throws -> String {
        var comps = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var items: [URLQueryItem] = [
            .init(name: "model", value: "nova-3"),
            .init(name: "smart_format", value: "true"),
            .init(name: "punctuate", value: "true"),
            .init(name: "filler_words", value: "false"),
        ]
        for term in vocabularyTerms() {
            items.append(.init(name: "keyterm", value: term))
        }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("Token \(config.deepgramApiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        req.httpBody = wav

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PipelineError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        struct DG: Decodable {
            struct Results: Decodable {
                struct Channel: Decodable {
                    struct Alt: Decodable { let transcript: String }
                    let alternatives: [Alt]
                }
                let channels: [Channel]
            }
            let results: Results
        }
        guard let parsed = try? JSONDecoder().decode(DG.self, from: data),
              let text = parsed.results.channels.first?.alternatives.first?.transcript else {
            throw PipelineError.decode
        }
        return text
    }

    // MARK: - Cleanup pass

    private func cleanup(text: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let vocab = vocabularyTerms().joined(separator: ", ")
        let vocabLine = vocab.isEmpty ? "" : "\nPreserve these terms exactly when they appear: \(vocab)."
        let rules = replacementRulesDescription()
        let rulesLine = rules.isEmpty ? "" : "\nApply these dictionary replacements exactly: \(rules)."
        let system = """
        You clean up speech-to-text output for dictation. Rules:
        - Fix grammar, punctuation, and capitalization.
        - Remove filler words: um, uh, like, you know, sort of, kind of.
        - Preserve numbered lists with each item on its own line, using 1., 2., 3. prefixes.
        - Keep introductory and closing prose in separate paragraphs around a numbered list.
        - Apply spoken formatting commands: "new paragraph" → \\n\\n, "new line" → \\n, "period" → ., "comma" → ,, "question mark" → ?, "exclamation point" → !.
        - Do NOT add content, opinions, or change meaning. Do NOT wrap in quotes.
        - Return only the cleaned text, nothing else.\(vocabLine)\(rulesLine)
        """

        let payload: [String: Any] = [
            "model": config.data.cleanupModel,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PipelineError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        struct CR: Decodable {
            struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }
            let choices: [Choice]
        }
        let parsed = try JSONDecoder().decode(CR.self, from: data)
        return parsed.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    private func vocabularyTerms() -> [String] {
        var terms: [String] = []
        var seen = Set<String>()

        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            terms.append(trimmed)
        }

        config.customVocabulary
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .forEach { add(String($0)) }

        for rule in config.dictionaryReplacements {
            add(rule.word)
            add(rule.replacement)
        }

        return terms
    }

    private func replacementRulesDescription() -> String {
        config.dictionaryReplacements
            .map { rule -> String? in
                let word = rule.word.trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = rule.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty, !replacement.isEmpty else { return nil }
                return "\(word) -> \(replacement)"
            }
            .compactMap { $0 }
            .joined(separator: "; ")
    }

    private func applyDictionaryReplacements(to text: String) -> String {
        var result = text
        for rule in config.dictionaryReplacements {
            let word = rule.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = rule.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !replacement.isEmpty else { continue }

            let escaped = NSRegularExpression.escapedPattern(for: word)
            let pattern = "(?i)(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
            )
        }
        return result
    }
}

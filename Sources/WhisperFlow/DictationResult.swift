import Foundation

struct DictationResult {
    var text: String
    let pressEnter: Bool

    init(transcript: String) {
        // Interpret commands in the original STT output, before cleanup or dictionary
        // replacements can remove them or turn ordinary text into a command.
        let pattern = #"(?i)(?<![\p{L}\p{N}_])press\s+enter[.!?,;:…]*\s*\z"#
        if let command = transcript.range(of: pattern, options: .regularExpression) {
            text = String(transcript[..<command.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            pressEnter = true
        } else {
            text = transcript
            pressEnter = false
        }
    }
}

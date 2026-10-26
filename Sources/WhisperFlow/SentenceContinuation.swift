import Foundation
import NaturalLanguage

/// STT capitalizes every dictation as if it starts a sentence. When the cursor
/// sits mid-sentence, lowercase the first word so the dictation reads as a continuation.
enum SentenceContinuation {
    static func adjust(_ text: String, after preceding: String?,
                       preserving terms: [String] = Config.shared.vocabularyTerms) -> String {
        guard let preceding, continuesSentence(preceding),
              let wordRange = text.range(of: #"\A\p{Lu}[\p{Ll}'’]*(?![\p{L}\p{N}_])"#,
                                         options: .regularExpression) else { return text }
        let word = String(text[wordRange])
        // "I" and its contractions stay capitalized anywhere in a sentence.
        let pronoun = word.range(of: #"\AI(?:['’](?:m|ll|ve|d))?\z"#, options: .regularExpression) != nil
        guard !pronoun, !terms.contains(where: { $0.split(separator: " ").first.map(String.init) == word }),
              !isName(at: wordRange, in: text) else { return text }
        return text.replacingCharacters(in: wordRange, with: word.lowercased())
    }

    /// True when the text before the cursor ends inside a sentence, e.g. after a word or a comma.
    private static func continuesSentence(_ preceding: String) -> Bool {
        let trimmed = preceding.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        guard let last = trimmed.unicodeScalars.last else { return false }
        return CharacterSet.alphanumerics.contains(last) || ",;".unicodeScalars.contains(last)
    }

    private static func isName(at range: Range<String.Index>, in text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let (tag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
        return [.personalName, .placeName, .organizationName].contains(tag)
    }
}

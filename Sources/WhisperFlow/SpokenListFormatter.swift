import Foundation
import NaturalLanguage

enum SpokenListFormatter {
    private static let numberWords = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen", "twenty"
    ]
    private static let markers = try! NSRegularExpression(
        pattern: #"(?i)(?<!\S)(?:number\s+)?("# + numberWords.joined(separator: "|")
            + #"|[1-9][0-9]*)([.):,]?\s+)(?=\S)(?!(?:hundred|thousand|million|billion|trillion|point)\b)"#
    )

    private struct Marker {
        let number: Int
        let range: Range<String.Index>
        let explicit: Bool
        let separated: Bool
    }

    static func format(_ text: String) -> String {
        let candidates = markers.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match -> Marker? in
                guard let numberRange = Range(match.range(at: 1), in: text),
                      let range = Range(match.range, in: text) else { return nil }
                let token = text[numberRange].lowercased()
                guard let number = Int(token) ?? numberWords.firstIndex(of: token).map({ $0 + 1 }) else {
                    return nil
                }
                let previous = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces).last
                let explicit = text[range].lowercased().hasPrefix("number ")
                    || text[range].contains(where: { ".):,".contains($0) })
                let separated = explicit || previous.map { ",;.!?:\n\r".contains($0) } == true
                return Marker(number: number, range: range, explicit: explicit, separated: separated)
            }

        // Numbers elsewhere in the introduction must not prevent a list from starting.
        for (start, first) in candidates.enumerated() where first.number == 1 {
            var introduction = String(text[..<first.range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let previous = text[..<first.range.lowerBound].trimmingCharacters(in: .whitespaces).last
            let sentenceBoundary = previous.map { ".!?:\n\r".contains($0) } == true
            // An explicit marker also permits an inline lead-in: "Could you one, ...".
            // Bare quantities such as "I need one apple, two bananas" remain prose.
            guard introduction.isEmpty || sentenceBoundary || first.explicit else {
                continue
            }
            if !introduction.isEmpty && !sentenceBoundary {
                introduction = introduction.trimmingCharacters(in: CharacterSet(charactersIn: ",;")) + ":"
            }
            if let formatted = formatList(in: text, candidates: Array(candidates[start...]),
                                          introduction: introduction) {
                return formatted
            }
        }
        return text
    }

    private static func formatList(in text: String, candidates: [Marker], introduction: String) -> String? {
        var list = [candidates[0]]
        for candidate in candidates.dropFirst() {
            let previous = list[list.count - 1]
            let between = String(text[previous.range.upperBound..<candidate.range.lowerBound])
            if candidate.number == list.count + 1 {
                // Prefer a clearly separated marker over a quantity within an item.
                // "one buy 2 apples, two call Mom" keeps the quantity with item one.
                let laterSeparatedMarker = candidates.contains {
                    $0.range.lowerBound > candidate.range.lowerBound
                        && $0.number == candidate.number && $0.separated
                }
                if !candidate.separated && (laterSeparatedMarker || sentenceRanges(in: between).count > 1) {
                    continue
                }
                guard !trimItem(between).isEmpty else { return nil }
                list.append(candidate)
            } else if candidate.separated {
                // A number in a subsequent sentence can belong to closing prose.
                // A broken sequence in the same item is too ambiguous to reformat.
                if sentenceRanges(in: between).count > 1 || endsSentence(between) {
                    break
                }
                return nil
            }
        }
        guard list.count >= 2,
              list.count >= 3 || list.dropFirst().allSatisfy(\.separated) else { return nil }

        var items: [String] = []
        var closing = ""
        for (index, marker) in list.enumerated() {
            let end = index + 1 < list.count ? list[index + 1].range.lowerBound : text.endIndex
            var item = trimItem(String(text[marker.range.upperBound..<end]))
            guard !item.isEmpty else { return nil }
            if index == list.count - 1 {
                // STT sentence boundaries provide the local list-ending signal.
                // Preserve all text after the final item's first sentence as prose.
                let sentences = sentenceRanges(in: item)
                if sentences.count > 1 {
                    let boundary = sentences[1].lowerBound
                    closing = String(item[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    item = String(item[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            items.append("\(index + 1). \(item)")
        }
        return [introduction, items.joined(separator: "\n"), closing]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func trimItem(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
    }

    private static func endsSentence(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".!?".contains($0) } == true
    }

    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.english)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        return ranges
    }
}

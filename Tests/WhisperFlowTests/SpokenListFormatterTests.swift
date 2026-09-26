import XCTest
@testable import WhisperFlow

final class SpokenListFormatterTests: XCTestCase {
    func testSpokenNumbersAndSTTPunctuation() {
        for text in [
            "one this, two that, three this",
            "One this two that three this",
            "1 this, 2 that, 3 this",
            "One, this, two, that, three, this",
            "Number one this, number two that, number three this",
            "1. this; 2. that; 3. this"
        ] {
            XCTAssertEqual(SpokenListFormatter.format(text), "1. this\n2. that\n3. this", text)
        }
    }

    func testTwoItemsAndIntroduction() {
        XCTAssertEqual(SpokenListFormatter.format("Tasks: one buy milk, two call Mom."),
                       "Tasks:\n\n1. buy milk\n2. call Mom.")
        XCTAssertEqual(SpokenListFormatter.format("1. buy milk 2. call Mom"),
                       "1. buy milk\n2. call Mom")
    }

    func testItemPunctuationUnicodeAndExistingFormattingArePreserved() {
        let expected = "1. Buy café supplies.\n2. Call José!\n3. Ask why?"
        XCTAssertEqual(SpokenListFormatter.format("One Buy café supplies. Two Call José! Three Ask why?"),
                       expected)
        XCTAssertEqual(SpokenListFormatter.format(expected), expected)
        XCTAssertEqual(SpokenListFormatter.format("One apples, bananas, and pears; two milk."),
                       "1. apples, bananas, and pears\n2. milk.")
    }

    func testOrdinaryTextCommasAndAmbiguousNumbersStayIntact() {
        for text in [
            "", "Groceries, apples, bananas.", "One thing to remember.",
            "I need one apple, two bananas, three pears.", "One day I saw two birds.",
            "One item, three other items.", "Two apples, three bananas.",
            "1.5 cups, 2.5 cups, 3.5 cups", "one hundred apples, two hundred pears",
            "one, two, three", "one buy milk, two call Mom, four walk the dog"
        ] {
            XCTAssertEqual(SpokenListFormatter.format(text), text)
        }
    }

    func testListsContinuePastNine() {
        let input = (1...12).map { "\($0) task" }.joined(separator: ", ")
        let expected = (1...12).map { "\($0). task" }.joined(separator: "\n")
        XCTAssertEqual(SpokenListFormatter.format(input), expected)
    }

    func testIntroductorySentenceFromDictation() {
        let input = "Let's do this. One, buy milk. Two, calm mom. Three, walk the dog"
        XCTAssertEqual(SpokenListFormatter.format(input),
                       "Let's do this.\n\n1. buy milk.\n2. calm mom.\n3. walk the dog")
    }

    func testInlineLeadInWithExplicitListMarkers() {
        for input in [
            "Okay. Could you one, do this. Two, do that. Three, do that.",
            "Okay. Could you 1. do this. 2. do that. 3. do that.",
            "Okay. Could you number one do this. Number two do that. Number three do that."
        ] {
            let expected = "Okay. Could you:\n\n1. do this.\n2. do that.\n3. do that."
            XCTAssertEqual(SpokenListFormatter.format(input), expected)
            XCTAssertEqual(SpokenListFormatter.format(expected), expected)
        }
    }

    func testInlineLeadInAndClosingParagraph() {
        XCTAssertEqual(SpokenListFormatter.format("Please one, buy milk. Two, call Mom. Thank you."),
                       "Please:\n\n1. buy milk.\n2. call Mom.\n\nThank you.")
        for text in ["I need one apple, two bananas, three pears.",
                     "Could you get one apple and two bananas?", "Could you count one, two, three?"] {
            XCTAssertEqual(SpokenListFormatter.format(text), text)
        }
    }

    func testIntroductionListAndClosingParagraph() {
        let input = "Let's do this. One, buy milk. Two, call Mom. Three, walk the dog. That's all for today. Thanks for helping!"
        let expected = "Let's do this.\n\n1. buy milk.\n2. call Mom.\n3. walk the dog.\n\nThat's all for today. Thanks for helping!"
        XCTAssertEqual(SpokenListFormatter.format(input), expected)
        XCTAssertEqual(SpokenListFormatter.format(expected), expected)
    }

    func testGroceriesDictationWithQuestionAndThankYou() {
        let input = "Hey. I want to buy groceries later today. Could you get me these things? One, milk, two, eggs, three, butter. Thank you."
        let expected = "Hey. I want to buy groceries later today. Could you get me these things?\n\n1. milk\n2. eggs\n3. butter.\n\nThank you."
        XCTAssertEqual(SpokenListFormatter.format(input), expected)
        XCTAssertEqual(SpokenListFormatter.format(expected), expected)
    }

    func testNumbersInIntroductionAndClosingDoNotBreakList() {
        let input = "I have three tasks for today. One buy milk. Two call Mom. Three walk the dog. I should be done in two hours."
        XCTAssertEqual(SpokenListFormatter.format(input),
                       "I have three tasks for today.\n\n1. buy milk.\n2. call Mom.\n3. walk the dog.\n\nI should be done in two hours.")
        let nextNumber = "One buy milk. Two call Mom. Three walk the dog. I will leave in four hours."
        XCTAssertEqual(SpokenListFormatter.format(nextNumber),
                       "1. buy milk.\n2. call Mom.\n3. walk the dog.\n\nI will leave in four hours.")
    }

    func testQuantitiesInsideItemsArePreserved() {
        XCTAssertEqual(SpokenListFormatter.format("one buy 2 apples, two call Mom"),
                       "1. buy 2 apples\n2. call Mom")
    }

    func testAbbreviationsAndDecimalsDoNotEndLastItem() {
        XCTAssertEqual(SpokenListFormatter.format("One buy milk. Two visit Dr. Smith at 3.5 miles away. Then we're done."),
                       "1. buy milk.\n2. visit Dr. Smith at 3.5 miles away.\n\nThen we're done.")
    }

    func testMultipleSentencesInEarlierItemsArePreserved() {
        XCTAssertEqual(SpokenListFormatter.format("One buy milk. Get the whole milk. Two call Mom. Thanks!"),
                       "1. buy milk. Get the whole milk.\n2. call Mom.\n\nThanks!")
    }
}

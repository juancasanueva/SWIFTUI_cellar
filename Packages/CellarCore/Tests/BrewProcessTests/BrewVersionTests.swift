import Testing

@testable import BrewProcess

@Suite("Homebrew version parsing")
struct BrewVersionTests {
    struct ParseCase: Sendable {
        let output: String
        let expected: BrewVersion?
        let comment: String
    }

    static let cases: [ParseCase] = [
        ParseCase(
            output: "Homebrew 6.0.14-38-g1f3abf4",
            expected: BrewVersion(major: 6, minor: 0, patch: 14),
            comment: "a development build drops its git suffix"
        ),
        ParseCase(
            output: "Homebrew 4.0.0",
            expected: BrewVersion(major: 4, minor: 0, patch: 0),
            comment: "the supported floor"
        ),
        ParseCase(
            output: "Homebrew 3.6.21",
            expected: BrewVersion(major: 3, minor: 6, patch: 21),
            comment: "parses fine even though it is too old to use"
        ),
        ParseCase(
            output: "Homebrew 4.2\nHomebrew/homebrew-core (git revision abc; last commit 2024-01-01)",
            expected: BrewVersion(major: 4, minor: 2, patch: 0),
            comment: "a two-component version on the first of several lines"
        ),
        ParseCase(
            output: "  Homebrew 4.1.9  \n",
            expected: BrewVersion(major: 4, minor: 1, patch: 9),
            comment: "surrounding whitespace is not part of the version"
        ),
        ParseCase(
            output: "git version 2.4.0",
            expected: nil,
            comment: "another tool that happens to print a version"
        ),
        ParseCase(
            output: "hello from /bin/echo",
            expected: nil,
            comment: "arbitrary noise from a binary that is not brew"
        ),
        ParseCase(
            output: "",
            expected: nil,
            comment: "no output at all"
        ),
        ParseCase(
            output: "Homebrew",
            expected: nil,
            comment: "the right prefix but no version number"
        ),
    ]

    @Test("brew --version output parses to the expected version", arguments: cases)
    func parsesVersionOutput(testCase: ParseCase) {
        #expect(
            BrewVersion.parse(testCase.output) == testCase.expected,
            "\(testCase.comment): \(testCase.output)"
        )
    }

    @Test("Versions order by major, then minor, then patch")
    func comparableOrdering() {
        let ordered = [
            BrewVersion(major: 3, minor: 6, patch: 21),
            BrewVersion(major: 4, minor: 0, patch: 0),
            BrewVersion(major: 4, minor: 0, patch: 14),
            BrewVersion(major: 4, minor: 2, patch: 0),
            BrewVersion(major: 6, minor: 0, patch: 14),
        ]

        #expect(ordered.sorted() == ordered)
        #expect(ordered.shuffled().sorted() == ordered)
        #expect(BrewVersion(major: 3, minor: 6, patch: 21) < BrewVersion(major: 4, minor: 0, patch: 0))
        #expect(BrewVersion(major: 4, minor: 0, patch: 0) < BrewVersion(major: 4, minor: 0, patch: 1))
    }
}

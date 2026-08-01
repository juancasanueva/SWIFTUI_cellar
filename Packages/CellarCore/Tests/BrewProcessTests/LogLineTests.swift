import Testing

@testable import BrewProcess

@Suite("LogLine value semantics")
struct LogLineTests {
    @Test("Same stream, text, and sequence compare equal")
    func equalWhenAllFieldsMatch() {
        let first = LogLine(stream: .stdout, text: "==> Downloading", sequence: 0)
        let second = LogLine(stream: .stdout, text: "==> Downloading", sequence: 0)

        #expect(first == second)
        #expect(first.stream == .stdout)
        #expect(first.text == "==> Downloading")
        #expect(first.sequence == 0)
    }

    @Test("A differing stream tag breaks equality")
    func streamTagIsPartOfIdentity() {
        let out = LogLine(stream: .stdout, text: "warning: x", sequence: 3)
        let err = LogLine(stream: .stderr, text: "warning: x", sequence: 3)

        #expect(out != err)
        #expect(err.stream == .stderr)
    }

    @Test("A differing sequence breaks equality")
    func sequenceIsPartOfIdentity() {
        let first = LogLine(stream: .stderr, text: "same text", sequence: 1)
        let second = LogLine(stream: .stderr, text: "same text", sequence: 2)

        #expect(first != second)
    }

    @Test("Copying a LogLine across a concurrency boundary preserves its value")
    func copiesAreIndependentValues() async {
        let original = LogLine(stream: .stdout, text: "  leading space kept", sequence: 7)

        let roundTripped = await Task { () -> LogLine in
            var copy = original
            copy = LogLine(stream: copy.stream, text: copy.text, sequence: copy.sequence)
            return copy
        }.value

        #expect(roundTripped == original)
        #expect(roundTripped.text == "  leading space kept")
    }
}

import Foundation
import Testing

@testable import BrewClient

/// The `brew doctor` grammar, row by row (`system-health`, "Doctor evidence
/// preserves every byte and counts every line it cannot group"; design HD2).
///
/// Every test here is a pure function over `Data`. There is no process, no
/// clock and no store anywhere in the suite, which is the point: the hostile
/// shapes a real machine never produces — an empty headline, an orphan detail
/// line, a byte run that is not UTF-8 — are all reachable from a literal.
///
/// **Blank lines are the one thing the grammar drops**, deliberately and
/// visibly: they carry no content, and the captured report uses them as
/// separators *inside* a block as well as between blocks. "Every line is
/// accounted for" therefore means every **non-empty** line, and
/// `everyNonEmptyLineIsAccountedFor` below is what holds the grammar to it.
@Suite("Doctor parser")
struct DoctorParserTests {

    // MARK: - Arrangement

    private static func data(_ text: String) -> Data { Data(text.utf8) }

    /// Every non-empty line of a document, as the grammar's own splitter sees
    /// them — so the accounting assertion is not a second, disagreeing splitter.
    private static func nonEmptyLines(of data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
    }

    // MARK: - HD2 grammar, row by row (2.3)

    @Test("A non-empty line before the first warning is preamble, in order")
    func preambleIsCapturedInOrder() async {
        let evidence = await DoctorParser.parse(
            rawStdout: Data(),
            rawStderr: Self.data("""
            first preamble line
            second preamble line
            Warning: the block that ends the preamble

            """)
        )

        #expect(evidence.preamble == ["first preamble line", "second preamble line"])
        #expect(evidence.warningCount == 1)
        #expect(evidence.issues.isEmpty)
    }

    @Test("`Warning: <headline>` opens a block, and the headline is the remainder")
    func aWarningLineOpensABlock() async {
        let evidence = await DoctorParser.parse(
            rawStdout: Data(),
            rawStderr: Self.data("Warning: Unbrewed header files were found.\n")
        )

        #expect(evidence.warningCount == 1)
        #expect(evidence.warnings.first?.headline == "Unbrewed header files were found.")
        #expect(evidence.warnings.first?.detail.isEmpty == true)
        #expect(evidence.issues.isEmpty)
    }

    @Test("Other non-empty lines while a block is open append to that block's detail, in order")
    func detailLinesAppendInOrder() async {
        let evidence = await DoctorParser.parse(
            rawStdout: Data(),
            rawStderr: Self.data("""
            Warning: first
              detail one
              detail two
            Warning: second
              detail three

            """)
        )

        #expect(evidence.warningCount == 2)
        #expect(evidence.warnings[0].headline == "first")
        #expect(evidence.warnings[0].detail == ["  detail one", "  detail two"])
        #expect(evidence.warnings[1].headline == "second")
        #expect(evidence.warnings[1].detail == ["  detail three"])
    }

    /// A detail line that is not indented still belongs to the open block: the
    /// captured report's second block ends with an unindented `Unexpected header
    /// files:` line, and a grammar that keyed off indentation would drop it.
    @Test("An unindented line while a block is open is still that block's detail")
    func anUnindentedLineIsStillDetail() async {
        let evidence = await DoctorParser.parse(
            rawStdout: Data(),
            rawStderr: Self.data("""
            Warning: something

            Unexpected header files:
              /usr/local/include/node/*

            """)
        )

        #expect(evidence.warningCount == 1)
        #expect(evidence.warnings[0].detail == ["Unexpected header files:", "  /usr/local/include/node/*"])
        #expect(evidence.unknownLines.isEmpty, "a detail line was counted as unknown")
    }

    @Test("An empty headline still records the block, and records `.emptyWarningHeadline`")
    func anEmptyHeadlineStillRecordsTheBlock() async {
        let evidence = await DoctorParser.parse(
            rawStdout: Data(),
            rawStderr: Self.data("Warning: \n  its detail survives\n")
        )

        #expect(evidence.warningCount == 1, "the block was dropped rather than recorded")
        #expect(evidence.warnings[0].headline.isEmpty)
        #expect(evidence.warnings[0].detail == ["  its detail survives"])
        #expect(evidence.issues.contains(.emptyWarningHeadline))
        #expect(evidence.isPartial)
    }

    @Test("An indented line with no open block is an orphan detail line, not preamble")
    func anOrphanDetailLineIsCountedNotDropped() async {
        let report = Self.data("""
          an indented line before any warning
        Warning: the first block

        """)
        let evidence = await DoctorParser.parse(rawStdout: Data(), rawStderr: report)

        #expect(evidence.issues.contains(.orphanDetailLine))
        #expect(evidence.unknownLines.count == 1)
        #expect(
            evidence.unknownLines[0] == Self.data("  an indented line before any warning"),
            "the orphan line is not byte-identical to its input"
        )
        #expect(evidence.preamble.isEmpty, "an indented orphan was filed as preamble")
        #expect(evidence.warningCount == 1)
    }

    @Test("Bytes that are not valid UTF-8 survive as bytes among the unknown lines")
    func undecodableBytesSurviveAsBytes() async {
        var report = Data("Warning: a real block\n".utf8)
        let undecodable = Data([0xFF, 0xFE, 0x80, 0x81])
        report.append(undecodable)
        report.append(0x0A)

        let evidence = await DoctorParser.parse(rawStdout: Data(), rawStderr: report)

        #expect(evidence.issues.contains(.undecodableLine))
        #expect(evidence.unknownLines == [undecodable], "the undecodable run was not preserved verbatim")
        #expect(
            evidence.warnings[0].detail.isEmpty,
            "an undecodable run was lossily decoded into a block's detail"
        )
        // No replacement character was substituted anywhere.
        let rendered = evidence.warnings.flatMap(\.detail).joined() + evidence.preamble.joined()
        #expect(rendered.contains("\u{FFFD}") == false)
        // And the raw stream is still byte-identical to the input.
        #expect(evidence.rawStderr == report)
    }

    // MARK: - The captured run (2.4)

    @Test("The captured warnings run groups its two blocks and keeps their details in order")
    func theCapturedRunIsGroupedFaithfully() async throws {
        let streams = try DoctorFixture.warningsRun
        let evidence = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)

        #expect(evidence.warningCount == 2)
        #expect(evidence.warnings[0].headline == "Some installed formulae are deprecated or disabled.")
        #expect(evidence.warnings[0].detail == [
            "You should find replacements for the following formulae:",
            "    gemini-cli",
            "  ruby@3.1"
        ])
        #expect(evidence.warnings[1].headline == "Unbrewed header files were found in /usr/local/include.")
        #expect(evidence.warnings[1].detail == [
            "If you didn't put them there on purpose they could cause problems when",
            "building Homebrew formulae and may need to be deleted.",
            "Unexpected header files:",
            "  /usr/local/include/node/*"
        ])

        // The preamble is Homebrew's own de-emphasis, and it is captured rather
        // than discarded: it is the reason the doctor weight is the lowest one.
        #expect(evidence.preamble.count == 3)
        #expect(evidence.preamble[0].contains("just used to help the Homebrew maintainers"))

        #expect(evidence.unknownLines.isEmpty)
        #expect(evidence.issues.isEmpty)
        #expect(evidence.isPartial == false)
    }

    /// The accounting rule, over the real capture: nothing is silently dropped.
    @Test("Every non-empty line of the captured run is grouped or counted, never dropped")
    func everyNonEmptyLineIsAccountedFor() async throws {
        let streams = try DoctorFixture.warningsRun
        let evidence = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)

        let inDocument = Self.nonEmptyLines(of: streams.stderr) + Self.nonEmptyLines(of: streams.stdout)
        let accountedFor = evidence.preamble
            + evidence.warnings.flatMap { ["Warning: " + $0.headline] + $0.detail }
            + evidence.unknownLines.map { String(decoding: $0, as: UTF8.self) }

        #expect(inDocument.isEmpty == false, "the document walk found no lines")
        #expect(accountedFor.count == inDocument.count, "a line was dropped or invented")
        #expect(accountedFor.sorted() == inDocument.sorted())
    }

    @Test("The captured stdout is one newline and is not treated as content")
    func aNewlineOnlyStdoutContributesNothing() async throws {
        let streams = try DoctorFixture.warningsRun
        let evidence = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)

        #expect(streams.stdout == Data("\n".utf8))
        #expect(evidence.provenance.documentStream == .stderr)
        #expect(evidence.rawStdout == streams.stdout, "the one-byte stdout was trimmed away")
    }

    // MARK: - The clean run (2.5)

    @Test("A clean run reports zero warnings and zero unknown lines, present rather than absent")
    func aCleanRunIsClean() async throws {
        let streams = try DoctorFixture.cleanRun
        let evidence = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)

        #expect(evidence.warningCount == 0)
        #expect(evidence.unknownLineCount == 0)
        #expect(evidence.warnings.isEmpty)
        #expect(evidence.issues.isEmpty)
        #expect(evidence.isPartial == false)
        #expect(evidence.reportsReady, "the ready sentence was not recognised")
        #expect(evidence.provenance.documentStream == .stdout)
    }

    /// `0` and "nothing was measured" must stay distinguishable, which is the
    /// whole reason the counts are `Int` rather than `Int?`. A document nobody
    /// ever parsed does not exist as an evidence value at all.
    @Test("A clean run's zero is distinguishable from a document that was never parsed")
    func zeroIsDistinguishableFromNeverParsed() async throws {
        let clean = try DoctorFixture.cleanRun
        let parsed = await DoctorParser.parse(rawStdout: clean.stdout, rawStderr: clean.stderr)
        let nothing = await DoctorParser.parse(rawStdout: Data(), rawStderr: Data())

        #expect(parsed.warningCount == 0)
        #expect(nothing.warningCount == 0)
        // Same count, different documents — and the evidence says so.
        #expect(parsed != nothing)
        #expect(parsed.reportsReady)
        #expect(nothing.reportsReady == false)
        #expect(nothing.provenance.documentStream == .neither)
        #expect(parsed.provenance.documentStream == .stdout)
    }

    // MARK: - The hostile fixture, and a wholly unrecognised report (2.6)

    @Test("The hostile fixture yields evidence, never a failure and never an empty document")
    func theHostileFixtureIsToleratedAndCounted() async throws {
        let streams = try DoctorFixture.oddGrouping
        let evidence = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)

        // Four blocks: the empty headline, two adjacent detail-less headlines,
        // and one that does carry detail.
        #expect(evidence.warningCount == 4)
        #expect(evidence.warnings[0].headline.isEmpty)
        #expect(evidence.warnings[1].detail.isEmpty, "an adjacent headline absorbed detail it does not have")
        #expect(evidence.warnings[2].detail.isEmpty)
        #expect(evidence.warnings[3].detail == ["  and here is that detail line"])

        // Every hostile shape became a typed issue rather than a refusal.
        #expect(evidence.issues.contains(.emptyWarningHeadline))
        #expect(evidence.issues.contains(.orphanDetailLine))
        #expect(evidence.issues.contains(.undecodableLine))
        #expect(evidence.isPartial)

        // The orphan and the undecodable run both survive, the second as bytes.
        #expect(evidence.unknownLines.count == 2)
        #expect(evidence.unknownLines[0] == Self.data("  an indented detail line, before any warning has opened"))
        #expect(evidence.unknownLines[1] == Data([0xFF, 0xFE, 0x20, 0x6E, 0x6F, 0x74, 0x20, 0x76,
                                                  0x61, 0x6C, 0x69, 0x64, 0x20, 0x75, 0x74, 0x66,
                                                  0x2D, 0x38, 0x20, 0x80, 0x81]))
        #expect(evidence.rawStderr == streams.stderr)
        #expect(evidence.provenance.documentStream == .stderr)
    }

    /// A report whose shape the grammar does not recognise **at all** — no
    /// warning block and no ready sentence — is partial, not a failure and not a
    /// silent clean. Without this rule an unrecognised document would file its
    /// whole self as "preamble" and report zero warnings, which reads exactly
    /// like a healthy machine.
    @Test("A wholly unrecognised report keeps the whole document and is flagged partial")
    func aWhollyUnrecognisedReportIsPartial() async {
        let report = Self.data("""
        brew rewrote its doctor output
        and none of this is a warning block
        """)
        let evidence = await DoctorParser.parse(rawStdout: Data(), rawStderr: report)

        #expect(evidence.warnings.isEmpty)
        #expect(evidence.preamble.isEmpty, "an unrecognised report was filed as preamble and read as clean")
        #expect(evidence.unknownLines.map { String(decoding: $0, as: UTF8.self) } == [
            "brew rewrote its doctor output",
            "and none of this is a warning block"
        ])
        #expect(evidence.issues.contains(.unrecognisedReport))
        #expect(evidence.isPartial)
        #expect(evidence.reportsReady == false)
        // Never an empty document: the bytes are still there.
        #expect(evidence.rawStderr == report)
    }

    /// The other side of the same rule, so it cannot pass by refusing everything:
    /// a recognised report is **not** reclassified.
    @Test("A recognised report is not reclassified as unrecognised")
    func aRecognisedReportIsNotReclassified() async throws {
        let warnings = try DoctorFixture.warningsRun
        let clean = try DoctorFixture.cleanRun

        let grouped = await DoctorParser.parse(rawStdout: warnings.stdout, rawStderr: warnings.stderr)
        let ready = await DoctorParser.parse(rawStdout: clean.stdout, rawStderr: clean.stderr)

        #expect(grouped.issues.contains(.unrecognisedReport) == false)
        #expect(grouped.preamble.count == 3)
        #expect(ready.issues.contains(.unrecognisedReport) == false)
        #expect(ready.preamble == ["Your system is ready to brew."])
    }

    // MARK: - Determinism and provenance (2.7)

    @Test("Two byte-identical captures produce equal evidence")
    func theSameBytesAlwaysProduceTheSameEvidence() async throws {
        let streams = try DoctorFixture.warningsRun
        let copy = DoctorFixture.Streams(
            stdout: Data(streams.stdout),
            stderr: Data(streams.stderr)
        )

        let first = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)
        let second = await DoctorParser.parse(rawStdout: copy.stdout, rawStderr: copy.stderr)

        #expect(first == second)
        #expect(first.warnings == second.warnings)
        #expect(first.unknownLines == second.unknownLines)
        #expect(first.provenance == second.provenance)
        #expect(first.warningCount == 2, "the comparison is over an empty result")
    }

    @Test("Both raw streams are preserved separately and are never concatenated")
    func bothRawStreamsSurviveUnconcatenated() async throws {
        let streams = try DoctorFixture.warningsRun
        let evidence = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)

        #expect(evidence.rawStdout == streams.stdout)
        #expect(evidence.rawStderr == streams.stderr)
        #expect(evidence.rawStdout != evidence.rawStderr)

        let forwards = streams.stdout + streams.stderr
        let backwards = streams.stderr + streams.stdout
        #expect(evidence.rawStdout != forwards)
        #expect(evidence.rawStdout != backwards)
        #expect(evidence.rawStderr != forwards)
        #expect(evidence.rawStderr != backwards)
    }

    @Test(
        "`documentStream` records where the payload actually arrived",
        arguments: [
            ("", "", DoctorDocumentStream.neither),
            ("Warning: on stdout\n", "", DoctorDocumentStream.stdout),
            ("", "Warning: on stderr\n", DoctorDocumentStream.stderr),
            ("Warning: on stdout\n", "Warning: on stderr\n", DoctorDocumentStream.both),
            ("\n", "Warning: on stderr\n", DoctorDocumentStream.stderr)
        ]
    )
    func documentStreamRecordsWhereThePayloadArrived(
        stdout: String,
        stderr: String,
        expected: DoctorDocumentStream
    ) async {
        let evidence = await DoctorParser.parse(
            rawStdout: Self.data(stdout),
            rawStderr: Self.data(stderr)
        )

        #expect(evidence.provenance.documentStream == expected)
    }

    /// A warning block on stdout is admitted rather than ignored, so a future
    /// brew that moves the payload is *visible in the evidence* instead of being
    /// silently parsed as clean.
    @Test("A warning block on stdout is admitted and recorded as such")
    func aWarningOnStdoutIsAdmitted() async {
        let evidence = await DoctorParser.parse(
            rawStdout: Self.data("Warning: brew moved the payload\n"),
            rawStderr: Data()
        )

        #expect(evidence.warningCount == 1)
        #expect(evidence.warnings[0].headline == "brew moved the payload")
        #expect(evidence.provenance.documentStream == .stdout)
    }

    @Test("The parser version travels with every value")
    func theParserVersionTravelsWithTheEvidence() async throws {
        let streams = try DoctorFixture.warningsRun
        let evidence = await DoctorParser.parse(rawStdout: streams.stdout, rawStderr: streams.stderr)
        let empty = await DoctorParser.parse(rawStdout: Data(), rawStderr: Data())

        #expect(evidence.provenance.parserVersion == 1)
        #expect(empty.provenance.parserVersion == 1)
    }

    /// The signature is the proof: no process, no clock, no store can be passed
    /// in, so the evidence cannot depend on one.
    @Test("The parser reaches no process, clock or store")
    func theParserReachesNoProcessClockOrStore() throws {
        let source = try Self.declarations(of: "DoctorParser.swift")

        for forbidden in ["ProcessLaunching", "Date(", "Date.now", "FileManager", "URLSession", "Store"] {
            #expect(source.contains(forbidden) == false, "DoctorParser reaches \(forbidden)")
        }
        // And the vocabulary it is written against is bytes.
        #expect(source.contains("rawStdout: Data"))
        #expect(source.contains("rawStderr: Data"))
        // `@concurrent` on its own line before the modifier (M1 convention).
        #expect(source.contains("@concurrent\n    public static func parse"))
    }

    private static func declarations(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
    }
}

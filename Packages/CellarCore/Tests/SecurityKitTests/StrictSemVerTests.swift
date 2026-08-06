import Foundation
import Testing

@testable import SecurityKit

/// The typed half of the version boundary.
///
/// ## The number this parser is worth: 78.6%
///
/// Measured over the real 159-formula inventory captured by probe gate U5, not
/// estimated: **125 strict SemVer (78.6%), 9 strict SemVer plus an `_N`
/// revision (5.7%), 25 neither (15.7%)**.
///
/// 78.6% is the honest ceiling on the fix-comparison feature, and the reason it
/// is not 84.3% matters. Fix comparison runs over the **installed** string, not
/// the query version, so the nine revision-suffixed rows are *covered* by OSV
/// and *not comparable* by this parser — which is exactly the spec's `1.2.3_1`
/// versus `1.2.4` scenario, occurring in real life on nine of this machine's
/// formulae.
///
/// `theCorpusClassificationHolds` asserts all three of those numbers, so if the
/// parser drifts in either direction the measured claim fails with it rather
/// than quietly becoming untrue.
@Suite("Strict SemVer")
struct StrictSemVerTests {
    // MARK: - Accept and reject

    @Test(
        "Only MAJOR.MINOR.PATCH parses",
        arguments: [
            // Accepted.
            ("1.2.3", true),
            ("1.2.3-rc.1+build", true),
            ("0.0.0", true),
            ("1.52.1-0", true),
            ("10.20.30", true),
            ("1.2.3+build.5", true),
            ("1.2.3-alpha.beta", true),
            // Rejected.
            ("1.2", false),
            ("1.2.3.4", false),
            ("01.2.3", false),
            ("1.02.3", false),
            ("1.2.03", false),
            ("v1.2.3", false),
            ("1.2.3_1", false),
            ("2024-01-05", false),
            ("r5", false),
            ("8e", false),
            ("", false),
            ("1.2.3-", false),
            ("1.2.3+", false),
            ("1.2.3-01", false),
            ("1.2.3-rc..1", false),
            ("1.2.3 ", false),
            (" 1.2.3", false),
            ("-1.2.3", false)
        ]
    )
    func onlyMajorMinorPatchParses(version: String, accepted: Bool) {
        #expect(
            (StrictSemVer.parse(version) != nil) == accepted,
            "\(version) was \(accepted ? "rejected" : "accepted") against the rule"
        )
    }

    @Test("A parsed version keeps every component it was given")
    func aParsedVersionKeepsItsComponents() throws {
        let version = try #require(StrictSemVer.parse("1.52.1-rc.2+sha.abc"))

        #expect(version.major == 1)
        #expect(version.minor == 52)
        #expect(version.patch == 1)
        #expect(version.prerelease == [.alphanumeric("rc"), .numeric(2)])
        #expect(version.buildMetadata == "sha.abc")
    }

    // MARK: - The corpus

    /// The measured claim, asserted against both captured corpora.
    ///
    /// Every row of the real inventory carries the class it was measured as, so
    /// this walks all 159 and holds the parser to that recorded verdict. It is
    /// the difference between "the parser follows SemVer" and "the parser agrees
    /// with what is actually installed on a Mac".
    @Test("The corpus classification holds, row by row")
    func theCorpusClassificationHolds() throws {
        let rows = try Fixture.corpusRows("Versions/installed-versions.txt")
            .compactMap { row -> (version: String, classification: String)? in
                let fields = row.split(separator: " ")
                guard fields.count == 3 else { return nil }
                return (String(fields[1]), String(fields[2]))
            }

        #expect(rows.count == 159)

        var strict = 0
        var revision = 0
        var neither = 0

        for row in rows {
            let parsed = StrictSemVer.parse(row.version)
            let split = HomebrewRevision.split(row.version)

            switch row.classification {
            case "strict":
                #expect(parsed != nil, "\(row.version) was measured strict and did not parse")
                #expect(split.revision == nil, "\(row.version) grew a revision")
                strict += 1
            case "revision":
                // The version boundary in one row: the installed string is not
                // comparable, and the upstream it was split into is.
                #expect(parsed == nil, "\(row.version) parsed despite its revision suffix")
                #expect(split.revision != nil, "\(row.version) lost its revision")
                #expect(
                    StrictSemVer.parse(split.upstream) != nil,
                    "\(row.version) split to an upstream that does not parse"
                )
                revision += 1
            default:
                #expect(parsed == nil, "\(row.version) was measured unparseable and parsed")
                neither += 1
            }
        }

        #expect(strict == 125)
        #expect(revision == 9)
        #expect(neither == 25)
        #expect(Double(strict) / 159.0 == 125.0 / 159.0)
    }

    /// `pcre2 10.47_1` and Homebrew's own `1.0.1e_1` are the version boundary in
    /// a single string: a packaging revision on an upstream that is **not**
    /// strict SemVer. The lexical split succeeds, and the typed parse then
    /// refuses the upstream it produced. Two rules, two answers, neither one
    /// standing in for the other.
    @Test(
        "A revision suffix on a non-SemVer upstream splits and then still does not parse",
        arguments: ["10.47_1", "1.0.1e_1"]
    )
    func aRevisionOnANonSemVerUpstreamSplitsButDoesNotParse(installed: String) {
        let split = HomebrewRevision.split(installed)

        #expect(split.revision != nil, "the lexical split should have succeeded")
        #expect(StrictSemVer.parse(split.upstream) == nil)
        #expect(StrictSemVer.parse(installed) == nil)
    }

    /// The adversarial corpus: 149 strings Homebrew itself thinks are worth
    /// testing a version parser against. The overwhelming majority must be
    /// rejected, and a handful — the ones that happen to be valid SemVer — must
    /// not be, or "rejects almost everything" would be indistinguishable from
    /// "rejects everything".
    @Test("The adversarial corpus is overwhelmingly rejected, but not entirely")
    func theAdversarialCorpusIsOverwhelminglyRejected() throws {
        let rows = try Fixture.corpusRows("Versions/homebrew-version-spec-corpus.txt")

        #expect(rows.count == 149)

        let accepted = rows.filter { StrictSemVer.parse($0) != nil }

        #expect(accepted.isEmpty == false, "the parser rejected every adversarial string")
        #expect(
            Double(accepted.count) / Double(rows.count) < 0.35,
            "the parser accepted far too much of a corpus built to break parsers"
        )
        for shape in ["R13B", "2017-04-17", "20040914", "8d", "20c", "2007f", "HEAD",
                      "HEAD-abcdef", "1.2.3alpha4", "9.04", "1.01b", "2.08"]
        where rows.contains(shape) {
            #expect(StrictSemVer.parse(shape) == nil, "\(shape) parsed as strict SemVer")
        }
    }

    /// A correction to the phase-2 capture's own commentary, kept as a test so
    /// it cannot drift back.
    ///
    /// `Versions/homebrew-version-spec-corpus.txt` lists `1.2.3-p2` among the
    /// "non-SemVer prerelease spellings" that must be rejected. That is wrong:
    /// `p2` is a perfectly ordinary alphanumeric prerelease identifier and
    /// `1.2.3-p2` is valid SemVer 2.0.0 — structurally identical to the
    /// `1.2.3-rc.1` the task list requires this parser to accept, and to the
    /// real `luv 1.52.1-0` in the installed inventory. `1.2.3alpha4`, listed
    /// beside it, genuinely is invalid.
    ///
    /// Accepting it is also the **safe** direction. Homebrew reads `-p2` as a
    /// patch level *above* `1.2.3` while SemVer orders a prerelease *below* its
    /// release, so the two disagree — and the disagreement makes an installed
    /// `1.2.3-p2` look older than a fix at `1.2.3`, producing a visible false
    /// positive rather than a silent false negative. No installed formula in
    /// the captured inventory has this shape.
    @Test("A hyphenated patch level is valid SemVer, correcting the capture's commentary")
    func aHyphenatedPatchLevelIsValidSemVer() throws {
        let patchLevel = try #require(StrictSemVer.parse("1.2.3-p2"))

        #expect(patchLevel.prerelease == [.alphanumeric("p2")])
        #expect(StrictSemVer.parse("1.2.3alpha4") == nil, "this one really is not SemVer")

        // The disagreement with Homebrew, stated rather than discovered later.
        let release = try #require(StrictSemVer.parse("1.2.3"))
        #expect(patchLevel < release, "SemVer orders a prerelease below its release")
    }

    // MARK: - Ordering

    /// Ordering lives here, not in `HomebrewRevision`, and that separation is
    /// the whole point of the boundary. A `StrictSemVer` is comparable *because*
    /// it is a parsed value: two of them can be ordered without any of the
    /// per-ecosystem version algebra that ordering two Homebrew strings would
    /// require.
    @Test(
        "Precedence follows the SemVer rules, including prerelease and ignored build",
        arguments: [
            ("1.0.0", "2.0.0"),
            ("2.0.0", "2.1.0"),
            ("2.1.0", "2.1.1"),
            ("1.0.0-alpha", "1.0.0"),
            ("1.0.0-alpha", "1.0.0-alpha.1"),
            ("1.0.0-alpha.1", "1.0.0-alpha.beta"),
            ("1.0.0-alpha.beta", "1.0.0-beta"),
            ("1.0.0-beta", "1.0.0-beta.2"),
            ("1.0.0-beta.2", "1.0.0-beta.11"),
            ("1.0.0-beta.11", "1.0.0-rc.1"),
            ("1.0.0-rc.1", "1.0.0")
        ]
    )
    func precedenceFollowsTheSemVerRules(lower: String, higher: String) throws {
        let low = try #require(StrictSemVer.parse(lower))
        let high = try #require(StrictSemVer.parse(higher))

        #expect(low < high, "\(lower) should precede \(higher)")
        #expect(high > low)
        #expect(low != high)
    }

    /// Build metadata is not part of precedence, and two versions differing only
    /// in it are equal *for ordering* while still being distinguishable values.
    @Test("Build metadata is ignored by precedence but kept on the value")
    func buildMetadataIsIgnoredByPrecedence() throws {
        let plain = try #require(StrictSemVer.parse("1.2.3"))
        let built = try #require(StrictSemVer.parse("1.2.3+build.7"))

        #expect((plain < built) == false)
        #expect((built < plain) == false)
        #expect(built.buildMetadata == "build.7")
        #expect(plain.buildMetadata == nil)
    }
}

import Foundation
import Testing

@testable import SecurityKit

/// The lexical half of the version boundary.
///
/// `split` removes a trailing `_<digits>` Homebrew packaging revision and does
/// **nothing else**. It is a decomposition, not an ordering: nothing here is
/// compared, ranked, preferred or decided. That distinction is the reason this
/// file exists as its own file with its own structural guard — the snooze rule
/// one target away is forbidden from ever acquiring a version comparison, and a
/// `<` that leaked into a function named `split` would be the easiest possible
/// way to walk that back without anyone noticing.
///
/// Its failure direction is deliberately safe. Querying upstream `1.2.3` for an
/// installed `1.2.3_1` may surface an advisory the Homebrew revision already
/// patched — a *visible* false positive, which this codebase has repeatedly
/// chosen over a silent false negative.
@Suite("Homebrew revision split")
struct HomebrewRevisionTests {
    // MARK: - The suffix

    @Test("A trailing underscore-digits suffix is removed")
    func aTrailingUnderscoreDigitsSuffixIsRemoved() {
        let split = HomebrewRevision.split("1.2.3_1")

        #expect(split.upstream == "1.2.3")
        #expect(split.revision == 1)
    }

    /// Every `_N` row in the two captured corpora, so the rule is measured
    /// against Homebrew rather than against the author's memory of it.
    ///
    /// Two rows carry more weight than the rest:
    ///
    /// - `pcre2 10.47_1` and Homebrew's own `1.0.1e_1` put a revision suffix on
    ///   an upstream that is **not** strict SemVer. The split succeeds anyway,
    ///   because it is lexical; strict SemVer then rejects the upstream, because
    ///   that is a different rule answering a different question.
    /// - `1.0_0` and `2.1.4_0` write revision **zero explicitly**. `1.0_0` and
    ///   `1.0` are different strings, and the split must report `0` — never
    ///   `nil`, which is what "there was no suffix" means.
    @Test(
        "Every captured revision suffix is split, including revision zero",
        arguments: [
            // Real installed inventory.
            ("8.1.2_1", "8.1.2", 1),
            ("3.8.13_2", "3.8.13", 2),
            ("1.11.1_4", "1.11.1", 4),
            ("1.1.0_2", "1.1.0", 2),
            ("1.2.2_1", "1.2.2", 1),
            ("1.4.0_40", "1.4.0", 40),
            ("3.12.13_4", "3.12.13", 4),
            ("3.1.7_1", "3.1.7", 1),
            ("1.5.7_1", "1.5.7", 1),
            ("10.47_1", "10.47", 1),
            // Homebrew's own `pkg_version_spec.rb` corpus.
            ("1.0_0", "1.0", 0),
            ("1.0_1", "1.0", 1),
            ("1.0_2", "1.0", 2),
            ("1.0.1e_1", "1.0.1e", 1),
            ("1.2.3_4", "1.2.3", 4),
            ("2.0_1", "2.0", 1),
            ("2.1.4_0", "2.1.4", 0)
        ]
    )
    func everyCapturedRevisionSuffixIsSplit(installed: String, upstream: String, revision: Int) {
        let split = HomebrewRevision.split(installed)

        #expect(split.upstream == upstream)
        #expect(split.revision == revision)
    }

    /// Revision zero, stated on its own because `0` and `nil` are two different
    /// answers that a careless `Int(...)` or a truthiness check turns into one.
    @Test("Revision zero is a revision, not an absence")
    func revisionZeroIsNotNil() {
        let explicitZero = HomebrewRevision.split("1.0_0")
        let noSuffix = HomebrewRevision.split("1.0")

        #expect(explicitZero.revision == 0)
        #expect(noSuffix.revision == nil)
        // Two different installed strings, the same upstream, two different
        // answers about the revision. Folding `0` into `nil` would lose the
        // only thing that tells them apart.
        #expect(explicitZero.upstream == noSuffix.upstream)
        #expect(explicitZero.revision != noSuffix.revision)
    }

    // MARK: - Everything else

    @Test(
        "Everything else is returned unchanged",
        arguments: [
            "2024-01-05", "r5", "8e", "1.2.3", "1.2.3_beta", "1.2_3.4",
            // The shapes that look like a suffix and are not.
            "1.2.3_", "1.2.3_1a", "_1", "HEAD", ""
        ]
    )
    func everythingElseIsReturnedUnchanged(version: String) {
        let split = HomebrewRevision.split(version)

        #expect(split.upstream == version)
        #expect(split.revision == nil)
    }

    /// The same claim over both captured corpora in full, so it is a fact about
    /// 159 real installs and 159 adversarial strings rather than about eleven
    /// chosen ones. Every row **without** a `_<digits>` tail must come back
    /// byte-identical.
    @Test("The whole captured corpus is returned unchanged where it carries no suffix")
    func theWholeCorpusIsUnchangedWhereItCarriesNoSuffix() throws {
        let installed = try Fixture.corpusRows("Versions/installed-versions.txt")
            .compactMap { row -> String? in
                let fields = row.split(separator: " ")
                guard fields.count == 3 else { return nil }
                return String(fields[1])
            }
        let adversarial = try Fixture.corpusRows("Versions/homebrew-version-spec-corpus.txt")

        #expect(installed.count == 159)
        #expect(adversarial.count == 149)

        var unchanged = 0
        for version in installed + adversarial where version.contains("_") == false {
            let split = HomebrewRevision.split(version)
            #expect(split.upstream == version, "\(version) was altered")
            #expect(split.revision == nil, "\(version) grew a revision")
            unchanged += 1
        }

        #expect(unchanged >= 290, "the corpus walk ran against almost nothing")
    }

    // MARK: - The structural guard

    /// The trap this whole file exists to keep shut.
    ///
    /// `local-package-metadata` forbids an ordering comparison of Homebrew
    /// version strings anywhere near the snooze decision, because one would
    /// silently suppress a real update forever. `SecurityKit` owns a comparator
    /// and is structurally unreachable from that rule — but *this* file is the
    /// one place in the target that handles a raw Homebrew version string, so it
    /// is the one file where an ordering could be added and look like it
    /// belonged.
    ///
    /// So the file is scanned, with comments stripped, and must contain no
    /// comparison at all. Anchored positively on `split(`, or a moved or renamed
    /// file would pass this by being unreadable.
    ///
    /// `->` is normalised away first. A return arrow is not a comparison, and a
    /// naive substring scan for `>` would ban every function signature and be
    /// satisfiable only by deleting the function — the same failure mode the
    /// `xattr` tool versus `getxattr` C function distinction avoids in
    /// `EgressStructureTests`.
    @Test("The split file contains no comparison operator")
    func theSplitFileContainsNoComparisonOperator() throws {
        let sources = try SecurityKitSources.load()
        let file = try #require(sources.first { $0.name == "HomebrewRevision.swift" })

        #expect(file.code.contains("split("), "the scan did not read the split function")
        #expect(file.code.contains("func"), "the scan read no code")

        let code = file.code.replacingOccurrences(of: "->", with: " ")

        for token in ["<", ">", "compare(", ".numeric", "precedes", "isNewer", "isOlder",
                      "Comparable", "sorted", "max(", "min("] {
            #expect(code.contains(token) == false, "a comparison token leaked in: \(token)")
        }
    }

    /// The negative control for the scan above: pointed at source that *does*
    /// compare, it must object. Without this, `contains` could be broken and the
    /// guard would report green against anything.
    @Test(
        "The comparison scanner detects an ordering it is pointed at",
        arguments: [
            "if installed < fixed { return .stillAffected }",
            "if installed > fixed { return .fixedAtOrBefore }",
            "return lhs.compare(rhs, options: .numeric)",
            "extension HomebrewRevision: Comparable {}",
            "return versions.sorted()"
        ]
    )
    func theComparisonScannerDetectsAnOrdering(violation: String) {
        let tokens = ["<", ">", "compare(", ".numeric", "precedes", "isNewer", "isOlder",
                      "Comparable", "sorted", "max(", "min("]
        let normalised = violation.replacingOccurrences(of: "->", with: " ")

        #expect(
            tokens.contains { normalised.contains($0) },
            "the scanner missed a real ordering: \(violation)"
        )
    }
}

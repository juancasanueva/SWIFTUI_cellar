import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// The curated table is the whole of discovery, so it is the whole of the
/// blast radius.
///
/// U1 measured what happens without curation: name matching against advisory
/// databases is dominated by **identity collisions**. Homebrew's `curl` and
/// RubyGems' `curl` are unrelated software that share four letters; so are
/// `coreutils` the GNU tools and `coreutils` the Rust rewrite. A table built by
/// similarity would report confident, wrong findings against packages the user
/// never installed, and the user has no way to tell those apart from real ones.
///
/// So the table is exact pairs with per-entry provenance, and these tests exist
/// to make three things impossible: an entry nobody justified, a pattern
/// masquerading as a name, and a silent edit that leaves the cache serving
/// results the table no longer agrees with.
@Suite("Ecosystem mapping")
struct EcosystemMappingTests {
    // MARK: - Shape

    @Test("Every entry carries an exact ecosystem, an exact package name and its provenance")
    func everyEntryCarriesAnExactEcosystemAndPackageNameAndItsProvenance() {
        let entries = EcosystemMapping.entries

        #expect(entries.isEmpty == false, "the table is empty, so every check below is vacuous")

        for entry in entries {
            #expect(entry.formulaName.isEmpty == false)
            #expect(entry.ecosystem.isEmpty == false)
            #expect(entry.ecosystemPackageName.isEmpty == false)
            #expect(entry.sharedUpstream.contains("/"), "\(entry.formulaName)")
            #expect(
                entry.provenance.count >= 20,
                "\(entry.formulaName) has a provenance too short to justify anything"
            )
        }
    }

    /// `sharedUpstream` records a repository as `host/owner/repo`, deliberately
    /// **without a scheme**.
    ///
    /// This target's host-literal guard admits exactly two `https://` constants —
    /// the two advisory base URLs — because those are the only hosts it may
    /// reach. Provenance is documentation, not egress, and writing it as a URL
    /// would either weaken that guard into an allow-list or force it to
    /// distinguish URLs that are requested from URLs that are merely cited.
    /// A string that is not a URL cannot become a request by accident.
    @Test("Provenance records a repository, not a reachable URL")
    func provenanceCarriesNoScheme() {
        for entry in EcosystemMapping.entries {
            #expect(
                entry.sharedUpstream.contains("://") == false,
                "\(entry.formulaName) records provenance as a URL"
            )
        }
    }

    /// "Exact" means exact. A pattern, a prefix, a glob or a stray space would
    /// each reintroduce the similarity matching the table exists to replace.
    @Test("No entry is a pattern, a prefix or a padded name")
    func noEntryIsAPatternOrAPrefix() {
        for entry in EcosystemMapping.entries {
            for name in [entry.formulaName, entry.ecosystemPackageName, entry.ecosystem] {
                #expect(name.contains("*") == false, "\(name) looks like a glob")
                #expect(name.contains("?") == false, "\(name) looks like a glob")
                #expect(name.trimmingCharacters(in: .whitespacesAndNewlines) == name)
            }
        }

        // Lookup is exact in both directions of near-miss, or "no patterns"
        // above would be a statement about the literals and not about the
        // function that reads them.
        #expect(EcosystemMapping.entry(forFormula: "bat") != nil)
        #expect(EcosystemMapping.entry(forFormula: "ba") == nil)
        #expect(EcosystemMapping.entry(forFormula: "batx") == nil)
        #expect(EcosystemMapping.entry(forFormula: "BAT") == nil)
        #expect(EcosystemMapping.entry(forFormula: " bat") == nil)
    }

    @Test("Two entries never claim the same formula")
    func theTableHasNoDuplicateFormula() {
        let names = EcosystemMapping.entries.map(\.formulaName)

        #expect(Set(names).count == names.count, "a formula is mapped twice")
    }

    // MARK: - The revision

    /// `mappingRevision` is not decoration: the advisory cache invalidates on it,
    /// so a corrected table can never be masked by a fresh-looking entry. That
    /// only works if the constant actually moves when the table does.
    ///
    /// So the revision carries a fingerprint of the table it describes, and this
    /// test recomputes it. Editing an entry without bumping the revision fails
    /// here — the same discipline `probe-manifest.txt` applies to the fixtures,
    /// applied to the one piece of curated data that is compiled in rather than
    /// captured.
    @Test("The mapping revision is a monotonic constant that moves with the table")
    func theMappingRevisionIsAMonotonicConstant() {
        #expect(EcosystemMapping.revision >= 1)
        #expect(
            EcosystemMapping.fingerprint(of: EcosystemMapping.entries)
                == EcosystemMapping.revisionFingerprint,
            "the table changed without its revision being bumped"
        )
    }

    /// The negative control for the test above. "Nothing changed" is what a
    /// broken fingerprint reports for free, so the fingerprint is pointed at a
    /// table that *did* change and must notice — one altered entry, one added
    /// entry, one removed entry.
    @Test("The fingerprint rejects an edited, a grown and a shrunken table")
    func theFingerprintDetectsEveryKindOfEdit() throws {
        let real = EcosystemMapping.entries
        let baseline = EcosystemMapping.fingerprint(of: real)
        let first = try #require(real.first)

        let edited = [
            EcosystemMappingEntry(
                formulaName: first.formulaName,
                ecosystem: first.ecosystem,
                ecosystemPackageName: first.ecosystemPackageName + "-typo",
                sharedUpstream: first.sharedUpstream,
                provenance: first.provenance
            )
        ] + real.dropFirst()

        let grown = real + [
            EcosystemMappingEntry(
                formulaName: "definitely-not-mapped",
                ecosystem: "crates.io",
                ecosystemPackageName: "definitely-not-mapped",
                sharedUpstream: "example.invalid/nobody/nothing",
                provenance: "a fabricated entry, present only in this negative control"
            )
        ]

        #expect(EcosystemMapping.fingerprint(of: edited) != baseline)
        #expect(EcosystemMapping.fingerprint(of: grown) != baseline)
        #expect(EcosystemMapping.fingerprint(of: Array(real.dropLast())) != baseline)
        // And the control's control: an unedited table still matches, so the
        // three assertions above are about the edits and not about a
        // fingerprint that differs from itself.
        #expect(EcosystemMapping.fingerprint(of: real) == baseline)
    }

    // MARK: - The collisions

    /// The seven names U1 measured as identity collisions.
    ///
    /// Every one of them exists in some advisory database under a name Homebrew
    /// also uses, and in every case it is different software. A future
    /// contributor who adds `curl → RubyGems` because the names match will fail
    /// this test, and the failure will tell them why rather than leaving them to
    /// wonder whether the omission was an oversight.
    @Test(
        "The U1 collision names are deliberately absent",
        arguments: ["curl", "cmake", "coreutils", "git", "gcc", "ncurses", "glib"]
    )
    func theU1CollisionNamesAreDeliberatelyAbsent(name: String) {
        #expect(
            EcosystemMapping.entry(forFormula: name) == nil,
            "\(name) was measured as an identity collision by probe U1 (Engram obs 7451)"
        )
        #expect(
            EcosystemMapping.lookup(PackageID(kind: .formula, name: name))
                == .notCovered(.unmapped)
        )
    }

    // MARK: - The positive anchor

    /// Without this, every absence above would pass against an empty table.
    @Test(
        "The table maps U1's genuine matches, exactly",
        arguments: [
            ("bat", "crates.io", "bat"),
            ("eza", "crates.io", "eza"),
            ("ripgrep", "crates.io", "ripgrep"),
            ("sd", "crates.io", "sd"),
            ("uv", "PyPI", "uv")
        ]
    )
    func theTableActuallyMapsTheGenuineMatches(
        formula: String,
        ecosystem: String,
        packageName: String
    ) throws {
        let entry = try #require(EcosystemMapping.entry(forFormula: formula))

        #expect(entry.ecosystem == ecosystem)
        #expect(entry.ecosystemPackageName == packageName)
        #expect(
            EcosystemMapping.lookup(PackageID(kind: .formula, name: formula)) == .mapped(entry)
        )
    }

    /// The table's whole purpose stated as a number. U1 measured genuine curated
    /// coverage at roughly 3–5% of a real inventory, so a single-digit table
    /// against a 159-formula machine is the *correct* size, not an unfinished
    /// one. A table that had quietly grown to hundreds would mean somebody
    /// started guessing.
    @Test("The table is the size honest curation produces, not the size guessing produces")
    func theTableIsSingleDigit() throws {
        let installed = try Fixture.corpusRows("Versions/installed-versions.txt")
            .compactMap { $0.split(separator: " ").first.map(String.init) }

        #expect(installed.count == 159, "the U5 inventory capture is not the 159-formula capture")

        let mapped = installed.filter { EcosystemMapping.entry(forFormula: $0) != nil }
        let coverage = Double(mapped.count) / Double(installed.count)

        #expect(EcosystemMapping.entries.count < 10)
        #expect(coverage > 0.02, "the table covers nothing of a real inventory")
        #expect(coverage < 0.08, "the table covers more of a real inventory than U1 measured")
    }

    // MARK: - Not covered

    @Test("A package absent from the table is not covered, for the unmapped reason")
    func aPackageAbsentFromTheTableIsNotCoveredUnmapped() {
        #expect(
            EcosystemMapping.lookup(PackageID(kind: .formula, name: "hunk"))
                == .notCovered(.unmapped)
        )
        #expect(
            EcosystemMapping.lookup(PackageID(kind: .formula, name: ""))
                == .notCovered(.unmapped)
        )
    }

    /// A cask is a different gap from an unmapped formula, and the reason has to
    /// say which. `firefox` is not "we have no table entry" — it is "casks are
    /// out of scope", and a user reading the two states must be able to tell.
    @Test("A cask is not covered for the kind reason, even when its name is in the table")
    func aCaskIsNotCoveredForTheKindReason() {
        #expect(
            EcosystemMapping.lookup(PackageID(kind: .cask, name: "firefox"))
                == .notCovered(.kindUnsupported)
        )
        // The sharp case: the *name* is mapped, and the kind still decides.
        #expect(EcosystemMapping.entry(forFormula: "bat") != nil)
        #expect(
            EcosystemMapping.lookup(PackageID(kind: .cask, name: "bat"))
                == .notCovered(.kindUnsupported)
        )
    }
}

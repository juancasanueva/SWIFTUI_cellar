import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The entry model, and the structural half of **PM9**.
///
/// The requirement is that a file-sourced name reaches a command only by
/// constructing the same validated typed identity every other call site
/// constructs. The way that is made true here is not a check somewhere on the
/// path — it is the *shape of the type*: `BrewfileEntry.Kind` holds an
/// already-constructed `TapName`, `FormulaID` or `CaskID` and no raw string at
/// all. A name those initialisers refuse is therefore **unrepresentable as an
/// entry**, and the only thing the parser can do with it is count a skip.
///
/// That is what makes `BrewfilePlan` unable to fail and unable to emit free
/// text: by the time a plan sees an entry, the validation already happened, at
/// the one gate the whole package shares.
@Suite("Brewfile entry model")
struct BrewfileEntryTests {

    private static let acme = TapName("acme/tap")!
    private static let wget = FormulaID(name: "wget")!
    private static let iterm = CaskID(name: "iterm2")!

    // MARK: - PM9 — the identity is already constructed

    @Test("An entry carries a constructed identity, its line number, and nothing raw")
    func anEntryCarriesAConstructedIdentity() throws {
        let tap = BrewfileEntry(kind: .tap(Self.acme, url: nil), lineNumber: 1)
        let formula = BrewfileEntry(kind: .formula(Self.wget), lineNumber: 7)
        let cask = BrewfileEntry(kind: .cask(Self.iterm), lineNumber: 12)

        #expect(tap.lineNumber == 1)
        #expect(formula.lineNumber == 7)
        #expect(cask.lineNumber == 12)

        // The identity comes back out as the typed value that went in.
        guard case .tap(let name, let url) = tap.kind else {
            Issue.record("the tap entry lost its kind")
            return
        }
        #expect(name == Self.acme)
        #expect(url == nil)
        guard case .formula(let formulaID) = formula.kind else {
            Issue.record("the formula entry lost its kind")
            return
        }
        #expect(formulaID.name == "wget")
        #expect(formulaID.id == PackageID(kind: .formula, name: "wget"))
        guard case .cask(let caskID) = cask.kind else {
            Issue.record("the cask entry lost its kind")
            return
        }
        #expect(caskID.id == PackageID(kind: .cask, name: "iterm2"))

        // Identity is the line, so a selection is a set of line numbers and two
        // identical packages on two lines stay two selectable rows.
        #expect(formula.id == 7)
        #expect(BrewfileEntry(kind: .formula(Self.wget), lineNumber: 9).id == 9)
    }

    /// A name the typed identity refuses cannot be turned into an entry at all —
    /// there is nothing to pass to the case.
    @Test(
        "A name the typed identity refuses is unrepresentable as an entry",
        arguments: ["--force", "wget; rm -rf /", "", "   "]
    )
    func aNameTheTypedIdentityRefusesIsUnrepresentableAsAnEntry(name: String) {
        #expect(FormulaID(name: name) == nil)
        #expect(CaskID(name: name) == nil)
        #expect(PackageTarget(kind: .formula, name: name) == nil)
        // And for a tap, the same gate plus the two-component canonical rule.
        #expect(TapName(name) == nil)
    }

    /// The names a real dump actually contains still construct, so the gate is
    /// narrow rather than merely strict.
    @Test(
        "The names a real dump contains still construct",
        arguments: ["wget", "gcc@11", "python@3.12", "font-fira-code", "acme/tap/thing", "dotnet@9"]
    )
    func theNamesARealDumpContainsStillConstruct(name: String) throws {
        let formula = try #require(FormulaID(name: name), "\(name) was refused by the shipped gate")
        #expect(formula.name == name)
    }

    // MARK: - Structural: no case takes a string

    @Test("No case of the entry kind takes a raw string, and no initialiser accepts one")
    func noCaseOfTheEntryKindTakesARawString() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let entry = try #require(sources.first { $0.name == "BrewfileEntry.swift" })

        // The three cases, spelled with their typed identities.
        #expect(entry.code.contains("case tap(TapName, url: URL?)"))
        #expect(entry.code.contains("case formula(FormulaID)"))
        #expect(entry.code.contains("case cask(CaskID)"))

        // And no string-taking way in.
        for bypass in [
            "case tap(String", "case formula(String", "case cask(String",
            "init(kind: PackageKind, name: String", "init(name: String",
            "init?(rawName", "unvalidated"
        ] {
            #expect(
                entry.code.contains(bypass) == false,
                "BrewfileEntry.swift offers a string-taking path: \(bypass)"
            )
        }
    }

    // MARK: - The skip taxonomy (BF4)

    @Test("A skip carries its line number, its raw line, and a reason a consumer can switch on")
    func aSkipCarriesItsLineNumberItsRawLineAndAReason() {
        let skip = BrewfileSkip(
            lineNumber: 4,
            rawLine: "whalebrew \"whalebrew/wget\"",
            reason: .unsupportedEntryKind("whalebrew")
        )

        #expect(skip.lineNumber == 4)
        #expect(skip.rawLine == "whalebrew \"whalebrew/wget\"")
        #expect(skip.reason == .unsupportedEntryKind("whalebrew"))
        #expect(skip.reason.category == .unsupportedEntryKind)
        #expect(skip.id == 4)
    }

    /// The reasons are distinguishable **without reading free text**, which is
    /// what lets a surface group them and count them (BF4).
    @Test("Every reason category is distinct and enumerable")
    func everyReasonCategoryIsDistinctAndEnumerable() {
        let reasons: [BrewfileSkipReason] = [
            .unsupportedEntryKind("mas"),
            .unsupportedOption("postinstall"),
            .rubyConditional,
            .unrepresentableName,
            .unrecognisedLine,
            .undecodableBytes
        ]
        let categories = reasons.map(\.category)

        #expect(Set(categories).count == reasons.count, "two reasons share a category")
        #expect(Set(BrewfileSkipReason.Category.allCases) == Set(categories))
        #expect(BrewfileSkipReason.Category.allCases.count == 6)

        // Two skips of the same category but different detail stay distinct
        // values, so "3 unsupported kinds" and "which three" are both available.
        #expect(BrewfileSkipReason.unsupportedEntryKind("mas") != .unsupportedEntryKind("vscode"))
        #expect(BrewfileSkipReason.unsupportedEntryKind("mas").detail == "mas")
        #expect(BrewfileSkipReason.rubyConditional.detail == nil)
    }

    // MARK: - The document (BF4)

    @Test("A clean document reports a skip count of zero, present rather than absent")
    func aCleanDocumentReportsASkipCountOfZero() {
        let document = BrewfileDocument(
            entries: [BrewfileEntry(kind: .formula(Self.wget), lineNumber: 1)],
            skips: []
        )

        #expect(document.entries.count == 1)
        #expect(document.skips.count == 0)
        #expect(document.isEmpty == false)

        let empty = BrewfileDocument(entries: [], skips: [])
        #expect(empty.isEmpty)
        #expect(empty.skips.count == 0, "an empty document must still report zero, not absence")
    }

    // MARK: - BF5 — the claim records nothing

    @Test("A trust claim is the file author's, and it grants nothing")
    func aTrustClaimIsTheFileAuthorsAndItGrantsNothing() {
        let all = BrewfileTrustClaim(scope: .everything, rawOption: "trusted: true")
        let named = BrewfileTrustClaim(
            scope: .named(formulae: [], casks: ["engram"], commands: []),
            rawOption: "trusted: { casks: [\"engram\"] }"
        )

        #expect(all.rawOption == "trusted: true")
        #expect(named.scope == .named(formulae: [], casks: ["engram"], commands: []))

        // The attribution is a named constant, so a surface cannot accidentally
        // imply Homebrew, the tap or Cellar granted anything.
        #expect(BrewfileTrustClaim.attribution.contains("author"))
        #expect(BrewfileTrustClaim.attribution.lowercased().contains("cellar grants no trust"))
        #expect(BrewfileTrustClaim.attribution.lowercased().contains("homebrew") == false)
    }

    // MARK: - BF5 :115 / DD-8 — the qualifier is stripped at the projection

    /// **DD-8.** The gate stays exactly where it is. `FormulaID(name:
    /// "acme/tap/thing")` still constructs — the case above pins it as a name a
    /// real dump actually contains — and `PackageTarget.init?` and
    /// `MutationName.isSafe` are byte-identical after this change. What changes
    /// is a **projection** on the entry: the identity that will actually be
    /// installed.
    ///
    /// The alternative, a `/` ban on the gate, breaks both ends: `TapName.init?`
    /// is expressed over it and a tap name *is* `owner/repo`, and every
    /// qualified Brewfile line becomes an unrepresentable entry, contradicting
    /// BF5's "no skip counted".
    @Test("Qualified names still construct and project a bare target")
    func qualifiedNamesStillConstructAndProjectABareTarget() throws {
        let formula = BrewfileEntry(
            kind: .formula(try #require(FormulaID(name: "acme/tap/thing"))),
            lineNumber: 1
        )
        let cask = BrewfileEntry(
            kind: .cask(try #require(CaskID(name: "acme/tap/app"))),
            lineNumber: 2
        )
        let bare = BrewfileEntry(
            kind: .formula(try #require(FormulaID(name: "wget"))),
            lineNumber: 3
        )
        let tap = BrewfileEntry(
            kind: .tap(try #require(TapName("acme/tap")), url: nil),
            lineNumber: 4
        )

        // The identity the file named is retained, whole.
        #expect(formula.packageID == PackageID(kind: .formula, name: "acme/tap/thing"))
        #expect(cask.packageID == PackageID(kind: .cask, name: "acme/tap/app"))

        // …while the install target is the bare token brew installs by.
        #expect(formula.installTarget?.name == "thing")
        #expect(formula.installTarget?.kind == .formula)
        #expect(cask.installTarget?.name == "app")
        #expect(cask.installTarget?.kind == .cask)
        #expect(formula.installName == "thing")
        #expect(cask.installName == "app")

        // A bare name projects to itself — the strip is about the qualifier.
        #expect(bare.installTarget?.name == "wget")
        #expect(bare.installName == "wget")

        // A tap entry installs nothing, so it names no install target.
        #expect(tap.installTarget == nil)
        #expect(tap.installName == nil)

        // A degenerate qualified name yields `""`, which does not construct —
        // rather than yielding `tap`, which would install the wrong package.
        let degenerate = BrewfileEntry(
            kind: .formula(try #require(FormulaID(name: "acme/tap/"))),
            lineNumber: 5
        )
        #expect(degenerate.packageID == PackageID(kind: .formula, name: "acme/tap/"))
        #expect(degenerate.installTarget == nil)
        #expect(degenerate.installName == nil)
    }
}

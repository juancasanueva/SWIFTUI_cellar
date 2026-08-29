import Foundation
import Testing

@testable import BrewClient

/// Decoding runs over the captured fixtures in `Fixtures/Npm/`, so the shapes
/// asserted here are shapes the real binary produced rather than shapes this
/// code was written against. `probe-manifest.txt` records which two fixtures are
/// hand-authored and why.
@Suite("npm payload decoding")
struct NpmDecodeTests {
    // MARK: - `ls -g --json --depth=0`

    @Test("Every dependency key becomes one global package")
    func dependenciesBecomePackages() throws {
        let packages = try NpmDecoder.globals(from: NpmFixture.data("ls-g-depth0.json"))

        // Real entries from the capture: one plain name and one scoped one.
        #expect(packages.first { $0.name == "pnpm" }?.version == "10.13.1")
        #expect(packages.first { $0.name == "@openai/codex" }?.version == "0.149.0")
        #expect(packages.count == 23)
    }

    @Test("The prefix's own record is not a package")
    func topLevelRecordIsNotAnEntry() throws {
        let packages = try NpmDecoder.globals(from: NpmFixture.data("ls-g-depth0.json"))

        // The capture's top level is `"name": "lib"` — the prefix directory,
        // not something anybody installed.
        #expect(packages.contains { $0.name == "lib" } == false)
    }

    @Test("A prefix with nothing installed decodes as empty rather than failing")
    func emptyListingIsEmptyNotMalformed() throws {
        // The real capture: `{"name": "lib"}` with no `dependencies` key at all.
        // Treating an absent key as malformed would make a clean machine look
        // broken.
        let packages = try NpmDecoder.globals(from: NpmFixture.data("ls-g-empty.json"))

        #expect(packages.isEmpty)
    }

    @Test("An ELSPROBLEMS listing still yields every package it names")
    func problemsDocumentStillDecodes() throws {
        let packages = try NpmDecoder.globals(from: NpmFixture.data("ls-g-problems.stdout"))

        #expect(packages.map(\.name).sorted() == ["example-cli", "pnpm"])
        #expect(packages.first { $0.name == "example-cli" }?.version == "2.0.0")
    }

    @Test("Packages come back in a stable name order")
    func packagesAreOrderedByName() throws {
        let names = try NpmDecoder.globals(from: NpmFixture.data("ls-g-depth0.json")).map(\.name)

        #expect(names == names.sorted())
    }

    @Test("Truncated JSON is malformed")
    func truncatedListingIsMalformed() throws {
        let full = try NpmFixture.data("ls-g-depth0.json")
        let truncated = full.prefix(full.count / 2)

        #expect(throws: NpmInventoryError.malformedPayload) {
            try NpmDecoder.globals(from: Data(truncated))
        }
    }

    @Test("A dependency entry with no version is malformed, not skipped")
    func entryWithoutVersionIsMalformed() {
        let document = Data(#"{"name":"lib","dependencies":{"pnpm":{"overridden":false}}}"#.utf8)

        #expect(throws: NpmInventoryError.malformedPayload) {
            try NpmDecoder.globals(from: document)
        }
    }

    @Test("A dependencies value of the wrong shape is malformed")
    func wrongShapedDependenciesIsMalformed() {
        let document = Data(#"{"name":"lib","dependencies":["pnpm"]}"#.utf8)

        #expect(throws: NpmInventoryError.malformedPayload) {
            try NpmDecoder.globals(from: document)
        }
    }

    @Test("Keys npm adds that Cellar does not read are ignored, not refused")
    func unreadKeysAreTolerated() throws {
        // `overridden`, `resolved` and a per-entry `problems` array all appear in
        // real captures. Refusing on an unrecognised key would mean the next npm
        // release could blank the list.
        let document = Data("""
        {"name":"lib","version":"0.0.0","dependencies":{
          "pnpm":{"version":"10.13.1","overridden":false,"resolved":"https://x","problems":["p"]}
        }}
        """.utf8)

        let packages = try NpmDecoder.globals(from: document)

        #expect(packages.map(\.name) == ["pnpm"])
        #expect(packages.first?.version == "10.13.1")
    }

    // MARK: - `outdated -g --json`

    @Test("A package is outdated exactly when current differs from latest")
    func outdatednessIsCurrentAgainstLatest() throws {
        let document = Data("""
        {"corepack":{"current":"0.29.4","wanted":"0.29.4","latest":"0.31.0"},
         "typescript":{"current":"5.6.2","wanted":"5.6.2","latest":"5.6.2"}}
        """.utf8)

        let records = try NpmDecoder.outdated(from: document)

        #expect(records["corepack"]?.isOutdated == true)
        #expect(records["corepack"]?.latest == "0.31.0")
        #expect(records["typescript"]?.isOutdated == false)
    }

    @Test("wanted is preserved but never decides outdatedness")
    func wantedIsPreservedAndNotDecisive() throws {
        // A package pinned below `latest` by a range: `wanted` says it is fine,
        // `latest` says it is behind. The upgrade verb reaches `latest`, so the
        // row must offer it — which is the whole reason `wanted` cannot decide.
        let document = Data("""
        {"pnpm":{"current":"10.13.1","wanted":"10.13.1","latest":"11.0.0"}}
        """.utf8)

        let records = try NpmDecoder.outdated(from: document)

        #expect(records["pnpm"]?.wanted == "10.13.1")
        #expect(records["pnpm"]?.isOutdated == true)
        #expect(records["pnpm"]?.latest == "11.0.0")
    }

    @Test("The captured report decodes every entry it names")
    func capturedReportDecodes() throws {
        let records = try NpmDecoder.outdated(from: NpmFixture.data("outdated-g.json"))

        #expect(records.count == 22)
        #expect(records["pnpm"]?.current == "10.13.1")
        #expect(records["@openai/codex"]?.latest == "0.151.0")
        #expect(records.values.allSatisfy { $0.isOutdated })
    }

    @Test("An empty report decodes to no records at all")
    func emptyReportDecodesEmpty() throws {
        let braces = try NpmDecoder.outdated(from: NpmFixture.data("outdated-g-none.stdout"))
        let blank = try NpmDecoder.outdated(from: Data("{}".utf8))

        #expect(braces.isEmpty)
        #expect(blank.isEmpty)
    }

    @Test("npm's error document is malformed rather than an empty report")
    func errorDocumentIsMalformed() throws {
        // The real offline capture writes `{"error": {...}}` to stdout. Read as
        // a package map it would be one entry called `error` with no versions —
        // decoding it as "nothing is outdated" would report a machine as up to
        // date precisely because the check could not run.
        #expect(throws: NpmInventoryError.malformedPayload) {
            try NpmDecoder.outdated(from: NpmFixture.data("outdated-g-offline.stdout"))
        }
    }

    @Test("A record missing latest is malformed")
    func recordWithoutLatestIsMalformed() {
        let document = Data(#"{"pnpm":{"current":"10.13.1","wanted":"10.13.1"}}"#.utf8)

        #expect(throws: NpmInventoryError.malformedPayload) {
            try NpmDecoder.outdated(from: document)
        }
    }

    @Test("Truncated JSON is malformed")
    func truncatedReportIsMalformed() throws {
        let full = try NpmFixture.data("outdated-g.json")

        #expect(throws: NpmInventoryError.malformedPayload) {
            try NpmDecoder.outdated(from: Data(full.prefix(full.count / 2)))
        }
    }

    @Test("Keys npm adds that Cellar does not read are ignored")
    func reportToleratesExtraKeys() throws {
        let document = Data("""
        {"pnpm":{"current":"10.13.1","wanted":"11.0.0","latest":"11.0.0",
                 "dependent":"global","location":"/x","type":"dependencies"}}
        """.utf8)

        let records = try NpmDecoder.outdated(from: document)
        #expect(records["pnpm"]?.latest == "11.0.0")
    }

    // MARK: - The tri-state

    @Test("Not checked, fresh-and-clean, and failed are three distinct states")
    func freshnessIsTriState() {
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let fresh = NpmOutdatedState.fresh([:], at: checkedAt)
        let notChecked = NpmOutdatedState.notChecked(.notYetChecked)
        let failed = NpmOutdatedState.failed(.networkUnavailable)

        #expect(fresh != notChecked)
        #expect(fresh != failed)
        #expect(notChecked != failed)
        // Only `fresh` may ever contribute — or fail to contribute — an answer.
        #expect(fresh.records?.isEmpty == true)
        #expect(notChecked.records == nil)
        #expect(failed.records == nil)
        #expect(fresh.checkedAt == checkedAt)
    }

    @Test("Only a fresh state reads as up to date when nothing is outdated")
    func onlyFreshCanBeUpToDate() {
        #expect(NpmOutdatedState.fresh([:], at: Date()).isUpToDate)
        #expect(NpmOutdatedState.notChecked(.notYetChecked).isUpToDate == false)
        #expect(NpmOutdatedState.failed(.networkUnavailable).isUpToDate == false)
        #expect(NpmOutdatedState.failed(.malformedPayload).isUpToDate == false)

        let outdated = NpmOutdatedState.fresh(
            ["pnpm": NpmOutdatedRecord(current: "1.0.0", wanted: "2.0.0", latest: "2.0.0")],
            at: Date()
        )
        #expect(outdated.isUpToDate == false)
    }

    @Test("A cancelled check is not checked rather than failed")
    func cancellationIsNotAFailure() {
        let state = NpmOutdatedState.notChecked(.cancelled)

        #expect(state.isUpToDate == false)
        #expect(state.failure == nil)
        #expect(NpmOutdatedState.failed(.networkUnavailable).failure == .networkUnavailable)
    }
}

import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The payload's two namespaces describe an installation in two different
/// shapes, and the projection has to accept both without flattening either
/// (installed-inventory II2).
@Suite("Installed snapshot decoding")
struct InstalledDecodeTests {
    // MARK: - Formulae

    @Test("A single-keg formula decodes with its version and install time")
    func singleKegFormulaDecodes() throws {
        let wget = try InstalledFixture.package(.formula, "wget")

        #expect(wget.kegs.count == 1)
        #expect(wget.installedVersion == "1.25.0")
        #expect(wget.installedAt == InstalledFixture.date(1_735_689_600))
        #expect(wget.catalogVersion == "1.25.0")
    }

    @Test("A multi-keg formula appears once and keeps every keg")
    func multiKegFormulaKeepsEveryKeg() throws {
        let inventory = try InstalledFixture.inventory()
        let matches = inventory.packages.filter { $0.name == "openssl@3" }

        #expect(matches.count == 1)
        let openssl = try #require(matches.first)
        #expect(openssl.kegs.count == 2)
        #expect(openssl.kegs.map(\.version).sorted() == ["3.3.2", "3.4.0"])
    }

    /// `linked_keg` is the version brew actually linked, which is not always the
    /// newest one installed. Falling back to "newest" when it *is* present would
    /// silently report the wrong installed version.
    @Test("The linked keg is the primary one, even when a newer keg exists")
    func linkedKegWinsOverTheNewestKeg() throws {
        let openssl = try InstalledFixture.package(.formula, "openssl@3")

        #expect(openssl.installedVersion == "3.3.2")
        #expect(openssl.installedAt == InstalledFixture.date(1_727_740_800))
    }

    @Test("With no linked keg the newest install wins")
    func newestKegIsTheFallback() throws {
        let git = try InstalledFixture.package(.formula, "git")

        #expect(git.installedVersion == "2.48.1")
        #expect(git.installedAt == InstalledFixture.date(1_733_011_200))
    }

    @Test("Formula kegs carry their own on-request marker")
    func kegsCarryTheOnRequestMarker() throws {
        let openssl = try InstalledFixture.package(.formula, "openssl@3")
        let libunistring = try InstalledFixture.package(.formula, "libunistring")

        #expect(openssl.kegs.contains { $0.installedOnRequest })
        #expect(openssl.kegs.contains { !$0.installedOnRequest })
        #expect(libunistring.kegs.allSatisfy { !$0.installedOnRequest })
    }

    // MARK: - Casks

    @Test("A cask's string installed version decodes")
    func caskStringInstalledVersionDecodes() throws {
        let ghostty = try InstalledFixture.package(.cask, "ghostty")

        #expect(ghostty.kegs.count == 1)
        #expect(ghostty.installedVersion == "1.2.3")
        #expect(ghostty.catalogVersion == "1.3.1")
        #expect(ghostty.installedAt == InstalledFixture.date(1_735_689_600))
    }

    @Test("An undeclared auto-update flag is distinguishable from a declared one")
    func undeclaredAutoUpdatesIsNotAnExplicitFalse() throws {
        let ghostty = try InstalledFixture.package(.cask, "ghostty")
        let transmission = try InstalledFixture.package(.cask, "transmission")

        #expect(ghostty.declaresAutoUpdates == true)
        // `nil`, not `false`: the payload never says "this cask does not update
        // itself", it simply says nothing, and those are different facts.
        #expect(transmission.declaresAutoUpdates == nil)
        #expect(transmission.declaresAutoUpdates != false)
    }

    @Test("Both namespaces land in one inventory under the catalog's identity")
    func bothNamespacesShareOneIdentity() throws {
        let inventory = try InstalledFixture.inventory()

        #expect(inventory.packages.count == 10)
        #expect(inventory.package(PackageID(kind: .formula, name: "wget")) != nil)
        #expect(inventory.package(PackageID(kind: .cask, name: "ghostty")) != nil)
        // The same token in the other namespace is a different package, and a
        // miss rather than a wrong hit.
        #expect(inventory.package(PackageID(kind: .cask, name: "wget")) == nil)
    }

    @Test("A tap outside the covered two is still part of the installation")
    func thirdPartyTapRecordsAreKept() throws {
        let tool = try InstalledFixture.package(.formula, "private-tool")

        #expect(tool.tap == "acme/tools")
        #expect(tool.installedVersion == "0.4.1")
    }

    // MARK: - Threat row: untrusted payload

    @Test("Truncated JSON is malformed, not a partial inventory")
    func truncatedJSONIsMalformed() throws {
        let complete = try InstalledFixture.data()
        let truncated = complete.prefix(complete.count / 2)

        #expect(throws: InstalledInventoryError.malformedPayload) {
            try InstalledDecoder.inventory(from: Data(truncated))
        }
    }

    @Test("Bytes that are not the documented envelope are malformed")
    func foreignDocumentIsMalformed() {
        #expect(throws: InstalledInventoryError.malformedPayload) {
            try InstalledDecoder.inventory(from: Data("[1, 2, 3]".utf8))
        }
        #expect(throws: InstalledInventoryError.malformedPayload) {
            try InstalledDecoder.inventory(from: Data("not json at all".utf8))
        }
    }

    @Test("One corrupt record costs that record and nothing else")
    func oneCorruptRecordIsSkippedNotFatal() throws {
        let payload = """
        {
          "formulae": [
            {
              "name": "wget",
              "tap": "homebrew/core",
              "versions": { "stable": "1.25.0" },
              "installed": [{ "version": "1.25.0", "time": 1735689600,
                              "installed_on_request": true }],
              "outdated": false
            },
            { "name": 42, "installed": "this shape is not a formula" },
            {
              "name": "curl",
              "tap": "homebrew/core",
              "versions": { "stable": "8.12.1" },
              "installed": [{ "version": "8.12.1", "time": 1735689600,
                              "installed_on_request": true }],
              "outdated": false
            }
          ],
          "casks": []
        }
        """

        let inventory = try InstalledDecoder.inventory(from: Data(payload.utf8))

        #expect(inventory.packages.map(\.name).sorted() == ["curl", "wget"])
        #expect(inventory.skippedRecordCount == 1)
    }

    @Test("An empty but well-formed envelope is a valid, empty inventory")
    func emptyEnvelopeIsValid() throws {
        let inventory = try InstalledDecoder.inventory(
            from: Data("{\"formulae\": [], \"casks\": []}".utf8)
        )

        #expect(inventory.packages.isEmpty)
        #expect(inventory.skippedRecordCount == 0)
    }

    // MARK: - Off the main actor

    /// A snapshot of realistic size: ~160 records today, several hundred on a
    /// heavily populated machine. The count here is deliberately past the worst
    /// case so the measurement is not a coin toss.
    static let realisticRecordCount = 1_500

    static func realisticPayload(recordCount: Int) -> Data {
        let records = (0..<recordCount).map { index in
            """
            {"name":"package-\(index)","tap":"homebrew/core",\
            "desc":"A synthesised record used to size the decode",\
            "homepage":"https://example.invalid/package-\(index)",\
            "versions":{"stable":"1.\(index).0"},\
            "installed":[{"version":"1.\(index).0","time":\(1_700_000_000 + index),\
            "installed_as_dependency":false,"installed_on_request":true}],\
            "linked_keg":"1.\(index).0","pinned":false,"outdated":false}
            """
        }
        return Data("{\"formulae\":[\(records.joined(separator: ","))],\"casks\":[]}".utf8)
    }

    @MainActor
    @Test("The main actor stays responsive while a realistic payload is decoded")
    func decodeLeavesTheMainActorFree() async throws {
        let payload = Self.realisticPayload(recordCount: Self.realisticRecordCount)
        let finished = Flag()
        let turns = Counter()

        let ticker = Task { @MainActor in
            while !finished.isSet {
                await Task.yield()
                turns.increment()
            }
        }
        await Task.yield()

        let before = turns.value
        let inventory = try await InstalledDecoder.decode(payload)
        let during = turns.value - before
        finished.set()
        await ticker.value

        #expect(inventory.packages.count == Self.realisticRecordCount)
        // Zero while the decode is a synchronous main-actor call: it holds the
        // actor from the first byte to the last. A regression test, not a
        // timing one.
        #expect(during > 0, "no main-actor turn completed while the snapshot was decoded")
    }
}

//
//  AppcastDocumentTests.swift
//  UpdatesTests
//

import Foundation
import Testing

@testable import Updates

/// A failure fixture and the exact typed error it must produce.
struct RejectionCase: Sendable, CustomStringConvertible {
    let fixture: String
    let failure: AppcastValidationFailure

    var description: String { fixture }
}

/// Reads the hand-authored appcast fixtures.
///
/// Hand-authored rather than produced by running `scripts/appcast.sh` inside a
/// test: that would need the signing tool, a private key and network egress
/// inside `swift test`, three things this project forbids. The consequence is
/// stated rather than smoothed — a `cellarTests` structural test pins the script
/// to the element and attribute names this validator requires, which proves the
/// emitter and the validator agree on **names**, not on bytes.
enum AppcastFixtures {
    static let directory: URL = {
        guard let resourceURL = Bundle.module.resourceURL else {
            preconditionFailure("the UpdatesTests bundle has no resource URL")
        }
        return resourceURL.appendingPathComponent("Fixtures")
    }()

    static func text(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}

/// What an appcast document must carry before Cellar treats it as valid.
///
/// Offline, with no network and without the updater framework, so a malformed
/// feed is caught by a test before an installed copy of the app ever fetches it.
@Suite("Appcast document")
struct AppcastDocumentTests {
    // MARK: - T3 — a complete item validates

    /// Every field an update depends on, read back off a real document.
    ///
    /// Each field is asserted against its exact fixture value rather than
    /// against "is present": a validator that returned the right *shape* with the
    /// wrong enclosure URL would be worse than one that rejected the document,
    /// because the caller would download whatever it named.
    @Test("A complete item validates and carries every field an update depends on")
    func aCompleteItemValidates() throws {
        let document = try AppcastDocument.validate(AppcastFixtures.text("valid-single-item.xml"))

        #expect(document.items.count == 1)
        let item = try #require(document.items.first)

        #expect(item.version == "1")
        #expect(item.shortVersionString == "1.0.0")
        #expect(item.edSignature == "c2lnbmF0dXJlLWZpeHR1cmU=")
        #expect(item.length == 12_345_678)
        #expect(item.minimumSystemVersion == "26.0")
        #expect(item.enclosureURL.scheme == "https")
        #expect(item.enclosureURL.host() == "github.com")
        #expect(
            item.enclosureURL.absoluteString
                == "https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v1.0.0/Cellar-1.0.0.zip"
        )
    }

    // MARK: - T4 — one fixture per failure case

    static let rejections: [RejectionCase] = [
        RejectionCase(fixture: "no-channel.xml", failure: .missingChannel),
        RejectionCase(fixture: "missing-signature.xml", failure: .missingSignature(item: 0)),
        RejectionCase(fixture: "missing-length.xml", failure: .nonNumericLength(item: 0)),
        RejectionCase(fixture: "non-numeric-length.xml", failure: .nonNumericLength(item: 0)),
        RejectionCase(fixture: "missing-version.xml", failure: .missingVersion(item: 0)),
        RejectionCase(
            fixture: "missing-short-version-string.xml",
            failure: .missingShortVersionString(item: 0)
        ),
        // Absent and unreadable are the same defect from the consumer's side:
        // there is no short version string to compare. Pinned explicitly so the
        // shared case is a decision rather than an accident.
        RejectionCase(
            fixture: "unreadable-short-version-string.xml",
            failure: .missingShortVersionString(item: 0)
        ),
        RejectionCase(fixture: "insecure-enclosure.xml", failure: .insecureEnclosure(item: 0)),
        RejectionCase(
            fixture: "unexpected-host.xml",
            failure: .unexpectedHost(item: 0, expected: "github.com")
        ),
        RejectionCase(
            fixture: "wrong-minimum-system-version.xml",
            failure: .wrongMinimumSystemVersion(item: 0, found: "15.0")
        ),
        RejectionCase(
            fixture: "missing-minimum-system-version.xml",
            failure: .wrongMinimumSystemVersion(item: 0, found: nil)
        ),
        RejectionCase(fixture: "hyphenated-version.xml", failure: .hyphenatedVersion(item: 0)),
        RejectionCase(fixture: "items-out-of-order.xml", failure: .itemsOutOfOrder)
    ]

    /// Every rejection names itself, and none is partially usable.
    ///
    /// The typed case carries the item's index because a feed grows: "the
    /// signature is missing" is not actionable on a document with eleven items.
    /// Nothing here returns a document with the bad item dropped — a feed that
    /// half-validates is a feed that offers whatever survived the filter.
    @Test("A malformed appcast is rejected with its own named failure", arguments: rejections)
    func aMalformedAppcastIsRejected(rejection: RejectionCase) throws {
        let xml = try AppcastFixtures.text(rejection.fixture)

        #expect(throws: rejection.failure) {
            try AppcastDocument.validate(xml)
        }
    }

    // MARK: - T5 — a merge keeps history

    /// Publishing a new version preserves every previously published item.
    ///
    /// This is the property the whole publication design rests on: the feed is
    /// fetched, one item is prepended, and the result is republished. A merge
    /// that dropped the oldest item would strand every user who skipped a
    /// version, and deleting a published item is never how a bad release is
    /// corrected.
    @Test("A merged document keeps every item, newest first")
    func aMergedDocumentKeepsEveryItem() throws {
        let document = try AppcastDocument.validate(AppcastFixtures.text("valid-merged-history.xml"))

        #expect(document.items.map(\.shortVersionString) == ["1.1.0", "1.0.1", "1.0.0"])
        #expect(document.items.map(\.version) == ["3", "2", "1"])
        #expect(Set(document.items.map(\.enclosureURL)).count == 3)
    }
}

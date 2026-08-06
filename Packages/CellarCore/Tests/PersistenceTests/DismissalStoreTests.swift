import Catalog
import Foundation
import SecurityKit
import SwiftData
import Testing

@testable import Persistence

/// Dismissal: scoped to the exact finding and installed version, enumerable,
/// reversible, and incapable of changing a coverage state
/// (vulnerability-scanning — dismissal is scoped to the exact finding and
/// installed version; an upgrade re-surfaces a dismissed finding).
///
/// Every test here moves exactly one component of the key and asserts the
/// dismissal stops applying, because "scoped to the exact finding" is a claim
/// about what does *not* match — and an over-broad key would satisfy every
/// positive assertion in this file while quietly silencing findings the user
/// never answered.
@MainActor
@Suite("Dismissal store")
struct DismissalStoreTests {
    static let bat = PackageID(kind: .formula, name: "bat")

    static func key(
        advisoryID: String = "GHSA-p24j-h477-76q3",
        cveID: String? = "CVE-2021-36753",
        packageID: PackageID = bat,
        version: String = "0.18.1"
    ) -> DismissalKey {
        DismissalKey(
            advisoryID: advisoryID,
            cveID: cveID,
            packageID: packageID,
            installedVersion: version
        )
    }

    static func store(at url: URL) throws -> DismissalStore {
        DismissalStore(container: try PersistenceContainer.onDisk(at: url))
    }

    // MARK: - Scope (12.4)

    /// Four components, four ways to miss. Each row below differs from the
    /// dismissed finding in exactly one of them.
    @Test("A dismissal is keyed by the exact advisory, kind, name and version")
    func aDismissalIsKeyedByTheExactCveKindNameAndVersion() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            store.dismiss(Self.key())

            #expect(store.isDismissed(Self.key()), "the dismissed finding is not dismissed")

            // A different advisory about the same package at the same version.
            #expect(store.isDismissed(Self.key(advisoryID: "GHSA-4gg8-gxpx-9rph")) == false)
            // The same advisory, but a cask of the same name is different software.
            #expect(
                store.isDismissed(Self.key(packageID: PackageID(kind: .cask, name: "bat"))) == false
            )
            // A different package.
            #expect(
                store.isDismissed(Self.key(packageID: PackageID(kind: .formula, name: "eza"))) == false
            )
            // A different installed version.
            #expect(store.isDismissed(Self.key(version: "0.18.2")) == false)
        }
    }

    /// The whole mechanic of re-surfacing: nothing is invalidated, expired or
    /// swept. The version is part of the key, so an upgrade simply stops
    /// matching — and the row stays, so downgrading back is still answered.
    @Test("A version change re-surfaces the finding with no user action")
    func aVersionChangeReSurfacesTheFindingWithNoUserAction() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            store.dismiss(Self.key(version: "1.0.0"))

            #expect(store.isDismissed(Self.key(version: "1.0.0")))
            #expect(
                store.isDismissed(Self.key(version: "1.1.0")) == false,
                "the dismissal followed the package across an upgrade"
            )
            // The row is not deleted — re-surfacing is a key miss, never a sweep.
            #expect(store.records.count == 1)
            #expect(store.records.first?.version == "1.0.0")
        }
    }

    @Test("Dismissals are enumerable and reversible")
    func dismissalsAreEnumerableAndReversible() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            store.dismiss(Self.key(), note: "upstream disputes it")
            store.dismiss(Self.key(advisoryID: "GHSA-4gg8-gxpx-9rph", cveID: nil))

            #expect(store.records.count == 2)
            #expect(
                Set(store.records.map(\.advisoryID)) == ["GHSA-p24j-h477-76q3", "GHSA-4gg8-gxpx-9rph"]
            )
            let annotated = try #require(store.records.first { $0.note.isEmpty == false })
            #expect(annotated.note == "upstream disputes it")
            #expect(annotated.cveID == "CVE-2021-36753")
            // The advisory with no CVE alias reports none rather than an empty
            // string wearing a CVE's clothes.
            #expect(store.records.contains { $0.cveID == nil })

            store.restore(Self.key())

            #expect(store.isDismissed(Self.key()) == false, "a restored finding is still dismissed")
            #expect(store.records.count == 1)
            #expect(store.isDismissed(Self.key(advisoryID: "GHSA-4gg8-gxpx-9rph", cveID: nil)))
        }
    }

    @Test("A dismissal suppresses no other finding for the same package")
    func aDismissalSuppressesNoOtherFindingForTheSamePackage() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            store.dismiss(Self.key(advisoryID: "GHSA-p24j-h477-76q3"))

            #expect(store.isDismissed(Self.key(advisoryID: "GHSA-p24j-h477-76q3")))
            #expect(store.isDismissed(Self.key(advisoryID: "RUSTSEC-2021-0139")) == false)
            #expect(store.isDismissed(Self.key(advisoryID: "PYSEC-2026-899")) == false)
        }
    }

    /// The reason the stored key names the advisory rather than the CVE.
    ///
    /// `GHSA-`, `RUSTSEC-` and `PYSEC-` records routinely carry no CVE alias. A
    /// CVE-keyed row would file both of these under the empty string, and
    /// dismissing one would silence the other — a finding the user never
    /// answered, disappearing.
    @Test("Two advisories with no CVE alias are dismissed independently")
    func twoAdvisoriesWithoutCveAliasesAreDismissedIndependently() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            let first = Self.key(advisoryID: "RUSTSEC-2021-0139", cveID: nil)
            let second = Self.key(advisoryID: "RUSTSEC-2020-0163", cveID: nil)

            store.dismiss(first)

            #expect(store.isDismissed(first))
            #expect(store.isDismissed(second) == false, "one dismissal silenced an unrelated finding")
            #expect(store.records.count == 1)
        }
    }

    /// OSV adds CVE aliases to existing advisories over time. A dismissal that
    /// stopped applying the day an alias appeared would look exactly like the
    /// re-surfacing an upgrade is supposed to cause — and the user would have
    /// no way to tell the two apart.
    @Test("An alias appearing on the advisory does not undo a dismissal")
    func anAliasAppearingOnTheAdvisoryDoesNotUndoADismissal() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            store.dismiss(Self.key(advisoryID: "RUSTSEC-2021-0139", cveID: nil))

            #expect(
                store.isDismissed(Self.key(advisoryID: "RUSTSEC-2021-0139", cveID: "CVE-2021-45710")),
                "the dismissal was revoked by an alias appearing upstream"
            )
        }
    }

    /// Dismissal is what the matcher consults, so the seam it consults through
    /// is the one under test — not a parallel accessor that happens to agree.
    @Test("The lookup the matcher consults answers exactly what the store stored")
    func theLookupTheMatcherConsultsAgrees() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            store.dismiss(Self.key())

            let lookup: DismissalLookup = store.lookup
            #expect(lookup(Self.key()))
            #expect(lookup(Self.key(version: "0.18.2")) == false)
        }
    }

    @Test("Dismissals survive closing and reopening the store")
    func dismissalsSurviveAReopen() throws {
        try withTemporaryStore { url in
            do {
                let store = try Self.store(at: url)
                store.dismiss(Self.key(), note: "reviewed 2026-08-06")
            }

            let reopened = try Self.store(at: url)
            #expect(reopened.isDismissed(Self.key()))
            #expect(reopened.records.first?.note == "reviewed 2026-08-06")
        }
    }

    // MARK: - The value boundary (12.5)

    /// Persistence publishes values, never `@Model` instances — the
    /// `MetadataStore`/`MetadataLookup` rule, restated for a second store.
    ///
    /// Proven behaviourally rather than by inspection: the records are read,
    /// the store and its container are then dropped entirely, and the values
    /// are read again. A `@Model` instance would be a fault against a context
    /// that no longer exists; a value does not care.
    @Test("Persistence publishes a value snapshot and never a model instance")
    func persistencePublishesAValueSnapshotAndNeverAModelInstance() throws {
        try withTemporaryStore { url in
            var carried: [DismissalRecord] = []
            do {
                let store = try Self.store(at: url)
                store.dismiss(Self.key(), note: "outlives its store")
                carried = store.records
            }

            let record = try #require(carried.first)
            #expect(record.advisoryID == "GHSA-p24j-h477-76q3")
            #expect(record.cveID == "CVE-2021-36753")
            #expect(record.packageID == Self.bat)
            #expect(record.version == "0.18.1")
            #expect(record.note == "outlives its store")
        }
    }

    /// The structural half: no public entry point takes or returns the model.
    ///
    /// A single convenience accessor returning `DismissedCVE` would hand a
    /// context-bound object to a `@MainActor` view and to `SecurityKit`, which
    /// cannot see it at all — and it would compile.
    @Test("No public declaration in the store mentions the model type")
    func noPublicDeclarationMentionsTheModelType() throws {
        let source = SchemaTests.code(in: try Self.source(of: "DismissalStore.swift"))
        let publicDeclarations = source
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("public ") }

        #expect(publicDeclarations.isEmpty == false, "the file parsed to no public declarations")
        for declaration in publicDeclarations {
            #expect(
                declaration.contains("DismissedCVE") == false,
                "a public declaration exposes the model: \(declaration)"
            )
        }
    }

    /// The snapshot is `Sendable`, which is what lets it cross into a
    /// `@Sendable` lookup closure at all. Compile-time, not runtime.
    @Test("The published snapshot is a Sendable value")
    func theSnapshotIsSendable() throws {
        try withTemporaryStore { url in
            let store = try Self.store(at: url)
            store.dismiss(Self.key())
            #expect(Self.requireSendable(store.snapshot).count == 1)
        }
    }

    private static func requireSendable<T: Sendable>(_ value: T) -> T { value }

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Persistence/\(file)"),
            encoding: .utf8
        )
    }
}

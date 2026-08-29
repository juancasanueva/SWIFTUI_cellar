import Catalog
import Foundation
import SwiftData

@testable import Persistence

// The apparatus `MigrationTests` runs on, kept beside it rather than inside it:
// a request spy, the plan V1 actually shipped, and a throwaway schema one
// version ahead of what ships today. None of it is a test; all of it is what
// makes the tests next door mean something.

/// Fails every request it sees, and counts it. Registered only for the duration
/// of the test that installs it.
final class RequestSpy: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var count = 0

    static var observedCount: Int { count }
    static func reset() { count = 0 }

    // swiftlint:disable static_over_final_class
    // `URLProtocol` declares these as overridable class methods; `static` in a
    // final class cannot override one.
    override class func canInit(with request: URLRequest) -> Bool {
        count += 1
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class
    override func startLoading() {}
    override func stopLoading() {}
}

/// The plan V1 actually shipped with: one schema, zero stages.
///
/// Kept so the migration proof can write its fixture with the code that wrote
/// real V1 stores, rather than asking the current plan to produce an old shape
/// and then congratulating itself for reading it back.
enum ShippedV1Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}

/// The plan V2 actually shipped with: two schemas, one stage.
///
/// Kept for the same reason `ShippedV1Plan` is: the V2 → V3 migration proof
/// writes its fixture with the code that wrote real V2 stores — the stores the
/// shipped V3 container must open.
enum ShippedV2Plan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

// MARK: - A throwaway V4, for the migration proof only

/// Adds one optional property to `PackageMeta`, on top of the shipped V3.
/// Exists purely so "`MetadataMigrationPlan` really is a plan, and adding a
/// field really is `.lightweight`" is proven rather than asserted. Nothing
/// ships it.
///
/// `DismissedCVE` is the **real** model rather than another copy: the throwaway
/// only needs to differ from the shipped schema in the one property under test,
/// and a fourth redeclaration would be three more places for the stored shape to
/// drift without anyone noticing.
enum ThrowawaySchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PackageMeta.self, Snooze.self, HistoryEntry.self, DismissedCVE.self]
    }

    @Model
    final class PackageMeta {
        var kindRaw: String = ""
        var name: String = ""
        var isFavorite: Bool = false
        var note: String = ""
        var updatedAt: Date = Date.distantPast
        /// The added field.
        var colorTag: String?

        init(kindRaw: String, name: String) {
            self.kindRaw = kindRaw
            self.name = name
        }
    }

    @Model
    final class Snooze {
        var kindRaw: String = ""
        var name: String = ""
        var snoozedVersion: String = ""
        var createdAt: Date = Date.distantPast

        init(kindRaw: String, name: String, snoozedVersion: String) {
            self.kindRaw = kindRaw
            self.name = name
            self.snoozedVersion = snoozedVersion
        }
    }

    @Model
    final class HistoryEntry {
        var id: UUID = UUID()
        var date: Date = Date.distantPast
        var kindRaw: String = ""
        var name: String = ""
        var verb: String = ""
        var versionFrom: String = ""
        var versionTo: String = ""
        var outcomeRaw: String = ""
        var exitStatus: Int?
        var argv: [String] = []
        var commandText: String = ""
        /// Shipped by V3; the throwaway must carry it to differ from V3 only
        /// in the one property under test.
        var failureTail: [String] = []

        init(id: UUID) { self.id = id }
    }
}

enum ThrowawayMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, ThrowawaySchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: ThrowawaySchemaV4.self)
        ]
    }
}

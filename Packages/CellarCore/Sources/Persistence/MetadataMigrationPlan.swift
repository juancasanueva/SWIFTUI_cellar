import Foundation
import SwiftData

/// The store's migration plan (design D2).
///
/// V1 was genesis and the plan was declared and wired into every container from
/// the first commit anyway, so that adding V2 would be a `MigrationStage`
/// rather than a change of container construction. This is that entry: two
/// lines, exactly as promised, because a container opened without a plan cannot
/// grow one without re-pointing every call site.
///
/// Both stages are `.lightweight` because each version changes the least it
/// can: V2 adds one entity, V3 adds one defaulted column — no renamed property,
/// no changed type, no new non-optional column without a default.
/// `MigrationTests` proves it: a store written at each shipped version opens
/// under the current one with every field intact.
public enum MetadataMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
        ]
    }
}

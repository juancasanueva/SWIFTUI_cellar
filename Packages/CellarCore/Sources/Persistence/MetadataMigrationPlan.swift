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
/// The stage is `.lightweight` because V2 adds one entity and changes nothing
/// else — no renamed property, no changed type, no new non-optional column on an
/// existing model. `MigrationTests` proves both halves: that a V1-written store
/// opens under V2 with every field intact, and that the three V1 models are
/// property-for-property identical.
public enum MetadataMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

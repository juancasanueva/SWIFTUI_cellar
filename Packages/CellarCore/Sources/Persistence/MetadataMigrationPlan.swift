import Foundation
import SwiftData

/// The store's migration plan (design D2).
///
/// One schema, zero stages — V1 is genesis. The plan is declared and wired into
/// every container from the first commit so that adding V2 later is a
/// `MigrationStage.lightweight` entry rather than a change of container
/// construction; a container opened without a plan cannot grow one without
/// re-pointing every call site.
public enum MetadataMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    public static var stages: [MigrationStage] { [] }
}

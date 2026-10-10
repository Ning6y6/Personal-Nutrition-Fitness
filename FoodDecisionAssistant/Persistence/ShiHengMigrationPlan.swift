import SwiftData

/// V1 is frozen. No historical nine/ten-entity migration is claimed without a real fixture.
/// V2 adds a separate table and never fabricates historical goal snapshots.
enum ShiHengMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [VersionedSchemaV1.self, VersionedSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: VersionedSchemaV1.self, toVersion: VersionedSchemaV2.self)]
    }
}

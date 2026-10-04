import SwiftData

/// V1 is frozen. No historical nine/ten-entity migration is claimed without a real fixture.
enum ShiHengMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [VersionedSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

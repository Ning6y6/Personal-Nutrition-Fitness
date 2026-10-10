import SwiftData

/// V2 adds append-only goal versions. Every stored V1 definition remains frozen.
enum VersionedSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        VersionedSchemaV1.models + [PersistentGoalVersion.self]
    }
}

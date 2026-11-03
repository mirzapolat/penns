import SwiftData

/// The store's first released schema. Every later change to `Note` or
/// `Profile` gets a new version (with frozen copies of the old models nested
/// in the old version) and a stage in `PennsMigrationPlan`, so an existing
/// store always opens. iCloud allows additive changes only: never rename or
/// remove an attribute once the CloudKit schema is in Production.
public enum PennsSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [Note.self, Profile.self] }
}

public enum PennsMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [PennsSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

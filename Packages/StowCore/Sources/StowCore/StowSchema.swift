import Foundation
import SwiftData

public enum StowSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [StowItem.self, StowAttachment.self]
    }
}

public enum StowMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [StowSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

@MainActor
public enum StowContainerFactory {
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StowSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: StowMigrationPlan.self, configurations: [configuration])
    }

    public static func local(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: StowSchemaV1.self)
        let configuration = ModelConfiguration("Stow", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: StowMigrationPlan.self, configurations: [configuration])
    }

    public static func sharedHost(appGroupIdentifier: String, cloudKitContainerIdentifier: String) throws -> ModelContainer {
        let schema = Schema(versionedSchema: StowSchemaV1.self)
        let configuration = ModelConfiguration(
            "Stow",
            schema: schema,
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, migrationPlan: StowMigrationPlan.self, configurations: [configuration])
    }
}

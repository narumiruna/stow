import Foundation
import SwiftData

public enum StowSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [StowSchemaV1.StowItem.self, StowSchemaV1.StowAttachment.self]
    }
}

public enum StowSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [StowSchemaV2.StowItem.self, StowSchemaV2.StowAttachment.self, StowSchemaV2.StowRepresentation.self]
    }
}

public enum StowMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [StowSchemaV1.self, StowSchemaV2.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: StowSchemaV1.self, toVersion: StowSchemaV2.self)]
    }
}

@MainActor
public enum StowContainerFactory {
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: StowSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: StowMigrationPlan.self, configurations: [configuration])
    }

    public static func local(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: StowSchemaV2.self)
        let configuration = ModelConfiguration("Stow", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: StowMigrationPlan.self, configurations: [configuration])
    }

    public static func localV1(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: StowSchemaV1.self)
        let configuration = ModelConfiguration("Stow", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func sharedHost(appGroupIdentifier: String, cloudKitContainerIdentifier: String) throws -> ModelContainer {
        let schema = Schema(versionedSchema: StowSchemaV2.self)
        let configuration = ModelConfiguration(
            "Stow",
            schema: schema,
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, migrationPlan: StowMigrationPlan.self, configurations: [configuration])
    }
}

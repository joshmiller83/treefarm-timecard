import Fluent
import SQLKit

/// Version 1 of the schema. Later changes get their own migrations.
struct CreateSchema: AsyncMigration {
    func prepare(on db: any Database) async throws {
        try await db.schema(UserModel.schema)
            .id()
            .field("email", .string, .required)
            .field("display_name", .string, .required)
            .field("password_hash", .string, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "email")
            .create()

        try await db.schema(SessionModel.schema)
            .id()
            .field("user_id", .uuid, .required)
            .field("token_hash", .string, .required)
            .field("device_name", .string, .required)
            .field("created_at", .datetime, .required)
            .field("last_used_at", .datetime, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .unique(on: "token_hash")
            .create()

        try await db.schema(InviteModel.schema)
            .id()
            .field("farm_id", .uuid, .required)
            .field("role", .string, .required)
            .field("note", .string, .required)
            .field("code_hash", .string, .required)
            .field("created_at", .datetime, .required)
            .field("expires_at", .datetime, .required)
            .field("created_by", .uuid)
            .field("used_by", .uuid)
            .field("used_at", .datetime)
            .unique(on: "code_hash")
            .create()

        try await db.schema(ResetCodeModel.schema)
            .id()
            .field("user_id", .uuid, .required)
            .field("code_hash", .string, .required)
            .field("created_at", .datetime, .required)
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .create()

        try await db.schema(RecordModel.schema)
            .id()
            .field("kind", .string, .required)
            .field("entity_id", .uuid, .required)
            .field("farm_id", .uuid, .required)
            .field("owner_user_id", .uuid)
            .field("block_id", .uuid)
            .field("starts_at", .datetime)
            .field("ends_at", .datetime)
            .field("seq", .int64, .required)
            .field("created_seq", .int64, .required)
            .field("updated_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .field("json", .string, .required)
            .unique(on: "farm_id", "kind", "entity_id")
            .unique(on: "seq")
            .create()

        try await db.schema(TreeClaimModel.schema)
            .id()
            .field("farm_id", .uuid, .required)
            .field("season_id", .uuid, .required)
            .field("block_id", .uuid, .required)
            .field("row", .int, .required)
            .field("position", .int, .required)
            .field("mark_id", .uuid, .required)
            .field("shift_id", .uuid, .required)
            .unique(on: "farm_id", "season_id", "block_id", "row", "position")
            .unique(on: "mark_id")
            .create()

        try await db.schema(AppliedMutationModel.schema)
            .field(.id, .uuid, .identifier(auto: false))
            .field("user_id", .uuid, .required)
            .field("farm_id", .uuid, .required)
            .field("result_json", .string, .required)
            .field("created_at", .datetime, .required)
            .create()

        if let sql = db as? any SQLDatabase {
            try await sql.raw("CREATE INDEX records_farm_seq ON records (farm_id, seq)").run()
            try await sql.raw("CREATE INDEX records_farm_kind_owner ON records (farm_id, kind, owner_user_id)").run()
            try await sql.raw("CREATE INDEX records_farm_kind_block ON records (farm_id, kind, block_id)").run()
            try await sql.raw("CREATE INDEX sessions_user ON sessions (user_id)").run()
            try await sql.raw("CREATE INDEX reset_codes_user ON reset_codes (user_id)").run()
            try await sql.raw("CREATE INDEX tree_claims_shift ON tree_claims (shift_id)").run()
            try await sql.raw("CREATE INDEX tree_claims_block ON tree_claims (farm_id, block_id)").run()
        }
    }

    func revert(on db: any Database) async throws {
        for schema in [AppliedMutationModel.schema, TreeClaimModel.schema, RecordModel.schema, ResetCodeModel.schema,
                       InviteModel.schema, SessionModel.schema, UserModel.schema] {
            try await db.schema(schema).delete()
        }
    }
}

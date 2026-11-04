# SQL migration variants — review only

These files are preserved copies of local migration variants that differed from the SQL recorded in the hosted Supabase migration history, or used a non-canonical timestamp.

They are intentionally stored outside `supabase/migrations` so the Supabase CLI will not execute them during `supabase db reset`.

Rules:
- Do not move these files back into `supabase/migrations` without reviewing the SQL diff and writing a new migration with a fresh timestamp.
- The canonical historical migrations in `supabase/migrations` were restored from `supabase_migrations.schema_migrations` on the hosted project.
- The variants are retained only to avoid losing earlier local work.
- Do not apply these variants directly to the hosted database.

Review each file against the canonical migration and current database functions before deciding whether any change should become a new migration.

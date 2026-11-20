# Railway and Supabase deployment

## Railway: Flutter Web service

The Railway service builds the Flutter Web client from the repository's `Dockerfile`.
Keep the Dockerfile builder and the repository root as the build context.

Required service variables:

- `SUPABASE_URL`: the HTTPS URL of the intended Supabase project.
- `SUPABASE_PUBLISHABLE_KEY`: that same project's publishable API key (`sb_publishable_...`) or its legacy anon JWT key (`eyJ...`).

The URL and key must belong to the same Supabase project. A project reference such as `abcdefghijklmnopqrst` is not an API key.

The Dockerfile builds the Flutter web bundle and serves it with Nginx on Railway's `PORT` (default 8080). The `/health` endpoint is served by Nginx. No separate Railway build or start command is required while this Dockerfile is selected.

Do not put a Supabase database password, service-role key, or Supabase access token into this Flutter web service. Anything passed through `--dart-define` is compiled into browser-delivered assets; only the publishable/anon key is appropriate there.

## Supabase database migrations

Database migrations do not belong in Railway environment variables and must not run in the Flutter Docker build or app startup. Railway deploys the web client; Supabase owns PostgreSQL schema, RLS policies, triggers, and RPCs.

This repository has a local-only database CI workflow. It rebuilds the schema from `supabase/migrations` and runs pgTAP against an isolated local Supabase stack. That test workflow does not modify a hosted database.

For a hosted migration release, use a separate, protected GitHub Actions environment and the Supabase CLI:

1. Store `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` as protected GitHub Actions environment secrets.
2. Select the exact intended Supabase project reference. Never mix a URL/key from one project with migrations for another.
3. Run `supabase migration list --linked` to inspect remote history.
4. Run `supabase db push --linked --dry-run` and review every pending migration.
5. Only after the target and migration history are verified, run `supabase db push --linked --yes`.
6. Run `supabase migration list --linked` again and verify the expected versions.

The CLI version should remain pinned to the repository-tested version until the pipeline is deliberately upgraded. Supabase CLI v3 changed remote-target defaults and requires explicit `--remote` for hosted database commands; do not upgrade the pipeline without updating and testing its commands.

If remote schema and migration history disagree, stop and reconcile the history only after proving which SQL has already run. Do not use `--include-all` or `migration repair` as a generic workaround.

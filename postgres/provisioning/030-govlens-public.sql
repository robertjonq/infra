-- 030-govlens-public.sql
--
-- Read-only public role for the govlens.ie marketing + data portal.
-- Connects to the existing `pmem` database (no separate tenant DB —
-- govlens is a read-only view over pmem data, not a separate dataset).
--
-- Scoped tight: SELECT only, on a small whitelist of tables that are
-- safe to expose to an unauthenticated visitor. No writes, no admin,
-- no access to auth / audit / config tables.
--
-- Even if the govlens container is compromised or its .env leaks, the
-- blast radius is: SELECT on aggregate public-record tables, on one
-- database, no other tenant, no write surface.
--
-- Password is passed via psql -v app_pw=... (psql client variable):
--
--   docker compose exec -e GOVLENS_PUBLIC_PASSWORD="$GOVLENS_PUBLIC_PASSWORD" postgres \
--     psql -U postgres -v app_pw="$GOVLENS_PUBLIC_PASSWORD" -f /provisioning/030-govlens-public.sql

\echo 'Applying 030-govlens-public.sql'

-- Role: govlens_public
--   LOGIN only. No superuser, createrole, createdb, replication.
--   Cannot own databases. Cannot create objects anywhere.
SELECT format(
    CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'govlens_public')
         THEN 'ALTER ROLE govlens_public WITH LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L'
         ELSE 'CREATE ROLE govlens_public LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L'
    END,
    :'app_pw'
)
\gexec

-- Allow connection to the pmem database (PUBLIC was revoked in
-- 010-pmem.sql — we need to GRANT CONNECT explicitly).
GRANT CONNECT ON DATABASE pmem TO govlens_public;

-- Inside the pmem DB, grant usage on the public schema and SELECT
-- on the whitelisted tables only.
\c pmem

GRANT USAGE ON SCHEMA public TO govlens_public;

-- Whitelisted tables. Add to this list via a new provisioning file
-- (e.g. 031-govlens-public-extend.sql) as the public surface grows.
GRANT SELECT ON public.councils                TO govlens_public;
GRANT SELECT ON public.meetings                TO govlens_public;
GRANT SELECT ON public.meeting_agenda_items    TO govlens_public;
GRANT SELECT ON public.meeting_extractions     TO govlens_public;

-- Explicitly NOT granted (for the record):
--   officials, committees, committee_memberships, meeting_attendance,
--   meeting_questions, meeting_motions, meeting_cross_references,
--   council_source_candidates, council_source_config, council_config,
--   change_history, fetch_audit, standing_*, officials_aliases,
--   official_evidence, backlog, stories, story_updates, schedule*,
--   any admin/auth tables.
--
-- Grant additional tables only via a new provisioning file after
-- a deliberate review that the data is safe to expose publicly.

\c postgres

\echo 'Done.'

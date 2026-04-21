-- 000-admin-bootstrap.sql
--
-- One-time cluster hardening. Safe to re-run.
--
-- Revokes the default PUBLIC grants that let any connected role create
-- schemas and objects in the default template. Not dangerous on a
-- fresh cluster — just tightens the baseline.
--
-- Intended to be run once, by the built-in `postgres` superuser, on a
-- fresh cluster before any tenant provisioning:
--
--   docker compose exec postgres psql -U postgres -f /provisioning/000-admin-bootstrap.sql
--
-- Parameters: none.

\echo 'Applying 000-admin-bootstrap.sql'

-- Prevent any non-superuser from creating objects in the default
-- database's public schema. Tenants use their own databases; nobody
-- should be scribbling in `postgres`.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Prevent PUBLIC from connecting to databases it shouldn't. Each
-- tenant will GRANT CONNECT to its own role in its own provisioning
-- file.
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;

-- Make the hardening the default for any DB created from template1.
\c template1
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
\c postgres

\echo 'Done.'

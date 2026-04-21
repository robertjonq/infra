-- 010-pmem.sql
--
-- Provisions the `pmem` tenant: one role, one database, scoped grants.
--
-- Runs as the `postgres` superuser. Safe to re-run (idempotent — the
-- CASE expression picks ALTER ROLE vs CREATE ROLE based on whether
-- the role already exists; passwords are rotated on re-run).
--
-- Password is passed in via psql's -v app_pw=... (psql client variable):
--
--   docker compose exec -e PMEM_APP_PASSWORD="$PMEM_APP_PASSWORD" postgres \
--     psql -U postgres -v app_pw="$PMEM_APP_PASSWORD" -f /provisioning/010-pmem.sql
--
-- :'app_pw' is psql-side substitution (quoted string literal). We then
-- use format('%L', ...) server-side so special characters in the
-- password are escaped correctly before \gexec runs the built statement.

\echo 'Applying 010-pmem.sql'

-- Role: pmem
--   LOGIN, explicit NOSUPERUSER/NOCREATEROLE/NOCREATEDB/NOREPLICATION.
--   Owns the pmem database and everything inside it. Cannot touch
--   any other database on the cluster.
SELECT format(
    CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pmem')
         THEN 'ALTER ROLE pmem WITH LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L'
         ELSE 'CREATE ROLE pmem LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L'
    END,
    :'app_pw'
)
\gexec

-- Database: pmem
--   Owned by pmem. Created only if absent; owner can always be fixed
--   on a re-run.
SELECT 'CREATE DATABASE pmem OWNER pmem'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'pmem')
\gexec

ALTER DATABASE pmem OWNER TO pmem;

-- Scope pmem's access: only the pmem database. No CONNECT on the
-- admin `postgres` DB or on any other tenant DB.
REVOKE CONNECT ON DATABASE postgres FROM pmem;
GRANT  CONNECT ON DATABASE pmem     TO   pmem;

-- Inside the pmem database: pmem owns the public schema.
\c pmem
ALTER SCHEMA public OWNER TO pmem;
GRANT ALL ON SCHEMA public TO pmem;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
\c postgres

\echo 'Done.'

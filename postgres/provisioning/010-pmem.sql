-- 010-pmem.sql
--
-- Provisions the `pmem` tenant: one role, one database, scoped grants.
--
-- Runs as the `postgres` superuser. Safe to re-run (idempotent via
-- DO blocks that skip CREATE when the object already exists).
--
-- Password is passed in via psql -v app_pw="$PMEM_APP_PASSWORD":
--
--   docker compose exec -e PMEM_APP_PASSWORD=xxx postgres \
--     psql -U postgres -v app_pw="$PMEM_APP_PASSWORD" -f /provisioning/010-pmem.sql
--
-- Or read from the infra/.env and use the wrapper script (TBD).

\echo 'Applying 010-pmem.sql'

-- Role: pmem
--   LOGIN, explicit NOSUPERUSER/NOCREATEROLE/NOCREATEDB/NOREPLICATION.
--   Owns the pmem database and everything inside it. Cannot touch
--   any other database on the cluster.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pmem') THEN
        EXECUTE format(
            'CREATE ROLE pmem LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L',
            current_setting('app_pw')
        );
    ELSE
        -- Role exists; update password only (idempotent password rotation).
        EXECUTE format(
            'ALTER ROLE pmem WITH LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L',
            current_setting('app_pw')
        );
    END IF;
END
$$;

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

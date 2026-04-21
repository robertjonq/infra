-- 020-ticker.sql
--
-- Provisions the `ticker` tenant: one role, one database, scoped grants.
-- Same shape as 010-pmem.sql.
--
--   docker compose exec -e TICKER_APP_PASSWORD=xxx postgres \
--     psql -U postgres -v app_pw="$TICKER_APP_PASSWORD" -f /provisioning/020-ticker.sql

\echo 'Applying 020-ticker.sql'

-- Role: ticker_app
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ticker_app') THEN
        EXECUTE format(
            'CREATE ROLE ticker_app LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L',
            current_setting('app_pw')
        );
    ELSE
        EXECUTE format(
            'ALTER ROLE ticker_app WITH LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L',
            current_setting('app_pw')
        );
    END IF;
END
$$;

-- Database: ticker
SELECT 'CREATE DATABASE ticker OWNER ticker_app'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'ticker')
\gexec

ALTER DATABASE ticker OWNER TO ticker_app;

REVOKE CONNECT ON DATABASE postgres FROM ticker_app;
GRANT  CONNECT ON DATABASE ticker   TO   ticker_app;

\c ticker
ALTER SCHEMA public OWNER TO ticker_app;
GRANT ALL ON SCHEMA public TO ticker_app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
\c postgres

\echo 'Done.'

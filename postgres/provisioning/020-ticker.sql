-- 020-ticker.sql
--
-- Provisions the `ticker` tenant: one role, one database, scoped grants.
-- Same shape as 010-pmem.sql. See that file's header for the pattern.
--
--   docker compose exec -e TICKER_APP_PASSWORD="$TICKER_APP_PASSWORD" postgres \
--     psql -U postgres -v app_pw="$TICKER_APP_PASSWORD" -f /provisioning/020-ticker.sql

\echo 'Applying 020-ticker.sql'

-- Role: ticker_app
SELECT format(
    CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ticker_app')
         THEN 'ALTER ROLE ticker_app WITH LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L'
         ELSE 'CREATE ROLE ticker_app LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION PASSWORD %L'
    END,
    :'app_pw'
)
\gexec

-- Database: ticker
SELECT 'CREATE DATABASE ticker OWNER ticker_app'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'ticker')
\gexec

ALTER DATABASE ticker OWNER TO ticker_app;

REVOKE CONNECT ON DATABASE postgres FROM ticker_app;

-- Lock down the ticker database to ticker_app only. See 010-pmem.sql
-- for the reasoning (PUBLIC has CONNECT on every new DB by default).
REVOKE CONNECT ON DATABASE ticker FROM PUBLIC;
GRANT  CONNECT ON DATABASE ticker TO   ticker_app;

\c ticker
ALTER SCHEMA public OWNER TO ticker_app;
GRANT ALL ON SCHEMA public TO ticker_app;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
\c postgres

\echo 'Done.'

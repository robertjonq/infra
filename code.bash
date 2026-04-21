#!/bin/bash
# code.bash — ad-hoc verification snippets for the infra-postgres cluster.
#
# Not run as a script — copy/paste blocks as needed. Kept in the repo
# so commands we rely on don't rot in shell history.

# ─── Verify roles ────────────────────────────────────────────────────────
# Expect: postgres = SUPERUSER; pmem + ticker_app = LOGIN only.
docker compose exec postgres psql -U postgres -c "
  SELECT rolname, rolsuper, rolcanlogin, rolcreatedb, rolcreaterole, rolreplication
  FROM pg_roles
  WHERE rolname IN ('postgres','pmem','ticker_app')
  ORDER BY rolname;
"

# ─── Verify databases ────────────────────────────────────────────────────
# Expect: postgres (owner=postgres), pmem (owner=pmem), ticker (owner=ticker_app).
docker compose exec postgres psql -U postgres -c "
  SELECT datname, pg_get_userbyid(datdba) AS owner
  FROM pg_database
  WHERE datistemplate = false
  ORDER BY datname;
"

# ─── Verify tenant isolation ─────────────────────────────────────────────
# Both commands MUST fail with: FATAL: permission denied for database
docker compose exec postgres psql -U pmem       -d ticker -c "SELECT 1" 2>&1 | head -3
docker compose exec postgres psql -U ticker_app -d pmem   -c "SELECT 1" 2>&1 | head -3

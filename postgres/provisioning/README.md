# Postgres provisioning

Authoritative source of truth for every role, database, and grant on
the `infra-postgres` cluster. Every change to cluster membership or
privileges should be expressed as a file in this directory.

## Principles

- **Idempotent.** Every script is safe to re-run. `CREATE ROLE` is
  wrapped in a `DO` block that updates the password if the role
  already exists, so these scripts double as rotation scripts.
- **Runnable in order.** Numeric prefix sets ordering
  (`000-admin-bootstrap` → `010-pmem` → `020-ticker` → …).
- **One file per tenant.** Adding a new project = adding a new file
  and reviewing it via PR.
- **Passwords are never committed.** Scripts take the password as a
  psql variable (`-v app_pw="$VAR"`); the variable is populated from
  `infra/.env` at run time.

## Files

| File | Purpose |
|------|---------|
| `000-admin-bootstrap.sql` | One-time cluster hardening. Revokes PUBLIC grants. Run once on a fresh cluster. |
| `010-pmem.sql` | Creates `pmem` role + `pmem` database. |
| `020-ticker.sql` | Creates `ticker_app` role + `ticker` database. |
| `030-govlens-public.sql` | Creates `govlens_public` read-only role (SELECT on whitelisted pmem tables). No own database — reads pmem data. |

## Tenant onboarding (3-step recipe)

1. **Add a password for the new tenant to `infra/.env`:**
   ```
   FOO_APP_PASSWORD=strong-random-password-here
   ```
2. **Add a provisioning file** `NNN-foo.sql`, copying `020-ticker.sql`
   as a template and replacing role/database names. Commit it to the
   `infra` repo.
3. **Apply it** against the live cluster:
   ```bash
   docker compose exec -e FOO_APP_PASSWORD="$FOO_APP_PASSWORD" \
     postgres psql -U postgres -v app_pw="$FOO_APP_PASSWORD" \
     -f /provisioning/NNN-foo.sql
   ```
   The new role + database exist. The tenant's own compose uses the
   password from their own `.env` to connect.

## Password rotation

Same recipe as onboarding — re-run the provisioning file with a new
password. The `DO` block notices the role already exists and runs
`ALTER ROLE ... PASSWORD` instead of `CREATE ROLE`. Tenant's own
`.env` needs updating separately.

## Running the initial three scripts (first-time setup)

Prerequisite: the infra compose is up, the postgres service is
healthy, the provisioning directory is mounted into the container at
`/provisioning/` (see `infra/docker-compose.yml`).

```bash
# 1. Cluster hardening
docker compose exec postgres psql -U postgres -f /provisioning/000-admin-bootstrap.sql

# 2. pmem tenant
docker compose exec -e PMEM_APP_PASSWORD="$PMEM_APP_PASSWORD" postgres \
    psql -U postgres -v app_pw="$PMEM_APP_PASSWORD" -f /provisioning/010-pmem.sql

# 3. ticker tenant
docker compose exec -e TICKER_APP_PASSWORD="$TICKER_APP_PASSWORD" postgres \
    psql -U postgres -v app_pw="$TICKER_APP_PASSWORD" -f /provisioning/020-ticker.sql

# 4. govlens public (read-only over pmem data)
docker compose exec -e GOVLENS_PUBLIC_PASSWORD="$GOVLENS_PUBLIC_PASSWORD" postgres \
    psql -U postgres -v app_pw="$GOVLENS_PUBLIC_PASSWORD" -f /provisioning/030-govlens-public.sql
```

## Verifying the state afterwards

```sql
-- One superuser (postgres), plus LOGIN-only tenant roles.
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolcanlogin
FROM   pg_roles
WHERE  rolname IN ('postgres', 'pmem', 'ticker_app', 'govlens_public')
ORDER  BY rolname;

-- Three databases (postgres, pmem, ticker) with the right owners.
SELECT datname, pg_get_userbyid(datdba) AS owner
FROM   pg_database
WHERE  datistemplate = false
ORDER  BY datname;

-- govlens_public privileges should be SELECT on the 4 whitelisted tables.
\c pmem
SELECT table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privs
FROM   information_schema.role_table_grants
WHERE  grantee = 'govlens_public'
GROUP  BY table_name
ORDER  BY table_name;
\c postgres
```

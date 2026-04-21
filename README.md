# infra

Shared infrastructure for projects on this host (ubdock). Currently:

- **Postgres 16** — multi-tenant cluster. Each project gets its own
  database + role, provisioned from SQL files in this repo.

Planned:

- **Nginx** — shared reverse proxy with per-tenant server blocks,
  rate limiting, TLS termination.
- **Backup orchestration** — nightly postgres dumps + tenant filedata
  rsync to DEBEAST SMB share.

## Ownership boundary

**infra owns:**

- The admin / superuser account (`postgres`). Password lives in
  `infra/.env` only.
- Creating per-tenant databases and roles. See
  [`postgres/provisioning/`](postgres/provisioning/).
- Scoping grants — each tenant role can access only its own database.
- Cluster-wide concerns: postgres version upgrades, extensions,
  backups, restores, role hygiene.
- Password rotation playbooks.

**Tenants own:**

- Their own app password, stored in their own `.env`.
- Their connection string.
- Their schema migrations (inside their own database only).
- Their file-based data (volume mounts declared in their own compose).

Tenants never have superuser access. Adding a tenant = adding a
provisioning SQL file to this repo (via PR) and applying it.

## Current tenants

| Tenant | Database | Role | Provisioning file |
|--------|----------|------|---|
| pmem (govlens) | `pmem` | `pmem` | [`postgres/provisioning/010-pmem.sql`](postgres/provisioning/010-pmem.sql) |
| ticker | `ticker` | `ticker_app` | [`postgres/provisioning/020-ticker.sql`](postgres/provisioning/020-ticker.sql) |

## Bring-up (first time)

1. Create `infra/.env` from `infra/.env.example` and fill in strong
   random passwords for each variable.
2. `docker compose up -d postgres` — new cluster comes up on the
   `infra_backend` network with only the `postgres` superuser.
3. Apply the three provisioning scripts in order:
   ```bash
   docker compose exec postgres psql -U postgres -f /provisioning/000-admin-bootstrap.sql

   docker compose exec -e PMEM_APP_PASSWORD="$PMEM_APP_PASSWORD" postgres \
       psql -U postgres -v app_pw="$PMEM_APP_PASSWORD" -f /provisioning/010-pmem.sql

   docker compose exec -e TICKER_APP_PASSWORD="$TICKER_APP_PASSWORD" postgres \
       psql -U postgres -v app_pw="$TICKER_APP_PASSWORD" -f /provisioning/020-ticker.sql
   ```
4. Verify using the query in
   [`postgres/provisioning/README.md`](postgres/provisioning/README.md).

No data migration yet — cluster is empty. Data migration from the old
`prp_postgres` volume is a separate exercise.

## Tenant connection from their own compose

Each tenant's `docker-compose.yml`:

```yaml
services:
  app:
    environment:
      - DATABASE_URL=postgresql://pmem:${PMEM_APP_PASSWORD}@infra-postgres:5432/pmem
    networks:
      - infra_backend

networks:
  infra_backend:
    external: true
```

The `infra_backend` network must be created by the infra compose
first (it's declared `external: true` on the tenant side).

## Backup

`scripts/backup.sh` runs nightly at 03:00 via ubdock cron. Dumps all
databases + globals, rsyncs per-tenant filedata volumes, prunes DB
dumps older than 14 days. Output lands on the DEBEAST SMB share at
`/mnt/backup/`.

Cron entry:

```
0 3 * * *  $HOME/projects/infra/scripts/backup.sh >> $HOME/logs/infra-backup.log 2>&1
```

## Migration from the old pmem-owned Postgres (pending)

The old `prp_postgres` volume, attached to the old pmem compose, stays
live and untouched during bring-up. Once the new cluster is validated
empty, data is migrated per tenant:

1. `pg_dump` from old → `pg_restore` into new (as superuser with
   `--no-owner --role=<tenant>`).
2. Flip each tenant's `DATABASE_URL` to point at `infra-postgres`.
3. Restart the tenant's containers.
4. Old cluster retained for ~7 days as rollback, then dropped.

See the Story #56 plan for the full sequencing.

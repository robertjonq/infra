# infra

Shared infrastructure for projects on this host (ubdock):

- **Postgres 16** — multi-tenant cluster. Each project gets its own
  database + role, provisioned from SQL files in this repo.
- **Nginx** — shared reverse proxy with per-tenant server blocks,
  rate limiting, TLS termination. Profile-gated (`--profile nginx`)
  to prevent accidental conflict with other host processes on 80/443.
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
- The shared nginx: rate-limit zones, LAN geo allowlist, scanner
  blocking, TLS config, and `include`-based per-tenant server blocks.
- Let's Encrypt cert renewal plumbing (acme.sh on the host,
  reloadcmd pointing at `infra-nginx`).

**Tenants own:**

- Their own app password, stored in their own `.env`.
- Their connection string.
- Their schema migrations (inside their own database only).
- Their file-based data (volume mounts declared in their own compose).
- Their own `server_name`, `location` routing, and proxy upstreams —
  dropped into `nginx/conf.d/<tenant>.conf` in this repo.

Tenants never have superuser access. Adding a tenant = adding a
provisioning SQL file + an nginx conf file to this repo (via PR) and
applying them.

## Current tenants

| Tenant | Database | Role | Provisioning file |
|--------|----------|------|---|
| pmem (data app, admin) | `pmem` | `pmem` (read+write) | [`postgres/provisioning/010-pmem.sql`](postgres/provisioning/010-pmem.sql) |
| ticker | `ticker` | `ticker_app` (read+write) | [`postgres/provisioning/020-ticker.sql`](postgres/provisioning/020-ticker.sql) |
| govlens-public (marketing site) | `pmem` (shared) | `govlens_public` (SELECT only, whitelisted tables) | [`postgres/provisioning/030-govlens-public.sql`](postgres/provisioning/030-govlens-public.sql) |

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

  web:
    # Container name must match what's referenced in
    # infra/nginx/conf.d/<tenant>.conf (e.g. public-record-web).
    container_name: public-record-web
    networks:
      - infra_backend

networks:
  infra_backend:
    external: true
```

The `infra_backend` network must be created by the infra compose
first (it's declared `external: true` on the tenant side).

## Nginx layout

```
nginx/
├── nginx.conf                (http{} globals: logs, rate-limit zones, geo block, include conf.d)
├── conf.d/
│   └── govlens.conf          (server blocks for therecord.duckdns.org + LAN :80)
└── snippets/
    ├── scanners.conf         (shared scanner-blocking rules, included per server block)
    └── proxy_headers.conf    (standard upstream proxy header set)
```

**Rate-limit zones** (defined once in `nginx.conf`, referenced from any
tenant's server blocks):

| Zone | Rate | Typical use |
|------|------|-------------|
| `per_ip` | 10 req/s | default `/` routes |
| `admin`  | 2 req/s  | `/admin*` |
| `login`  | 5 req/min | `/login` |

**LAN allowlist** (`$lan` variable): 1 for `192.168.50.0/24`, 0 otherwise.
Tenants can gate a server block with `if ($lan = 0) { return 403; }` to
make it LAN-only.

**TLS certs** are issued by acme.sh on the host (DuckDNS DNS-01
challenge) and bind-mounted read-only from `/etc/letsencrypt`. When
adding a new hostname, add it to acme.sh's cert config and reload
infra-nginx.

### Bring nginx up (AFTER the old pmem nginx is stopped)

```bash
docker compose --profile nginx up -d nginx
docker compose exec nginx nginx -t          # validate config inside the running container
docker compose exec nginx nginx -s reload   # pick up conf.d/ changes without restart
```

Host ports 80/443 can only be held by one container at a time — bring
up infra-nginx only in the cutover window (see below).

### acme.sh reloadcmd path

The reloadcmd that fires after every cert renewal needs to point at
this compose, not pmem's:

```
acme.sh --upgrade-account-key --renew -d therecord.duckdns.org \
        --reloadcmd "docker compose -f ~/projects/infra/docker-compose.yml \
                     --profile nginx exec -T nginx nginx -s reload"
```

(Or equivalent via `acme.sh --install-cert --reloadcmd ...`.)

## Cutover from pmem's nginx to infra's

Roughly 30–60 seconds of external-access downtime.

1. On pmem: add `infra_backend` (external) to the `web` service's
   networks in pmem's `docker-compose.yml`. Redeploy pmem. Confirm
   the `public-record-web` container is now on both pmem's default
   network AND `infra_backend`.
2. `docker compose stop nginx` in pmem's compose — frees ports 80/443.
3. `docker compose --profile nginx up -d nginx` in infra — infra-nginx
   binds 80/443 and proxies to `public-record-web:5000` over
   `infra_backend`.
4. Hit `https://therecord.duckdns.org` from off-LAN; verify login +
   2FA flow still works. Hit LAN IP on port 80; verify direct dashboard
   access still works.
5. Update acme.sh reloadcmd on ubdock (see above).
6. When stable (7 days), remove the nginx service from pmem's compose
   entirely.

**Rollback:** stop infra-nginx (`docker compose --profile nginx stop nginx`),
start pmem's nginx (`docker compose up -d nginx` in pmem). No config
changes needed to roll back — both sets of configs stay on disk during
the transition.

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

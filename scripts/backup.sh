#!/bin/bash
# infra/scripts/backup.sh — Nightly backup for shared infra + tenant data.
#
# Runs on ubdock cron at 03:00. Writes to the DEBEAST SMB share mounted
# at /mnt/backup (//192.168.50.161/pmem — share name kept for now).
#
# What it backs up:
#   1. Postgres cluster globals (pg_dumpall --globals-only) — roles + grants
#   2. Per-database dumps (pmem, ticker) in custom format for selective restore
#   3. Tenant filedata volumes (pmem council PDFs/DOCX)
#   4. Ollama logs (pmem's prp_data volume)
#
# Structure:
#   $BACKUP/postgres/globals_YYYY-MM-DD_HHMM.sql.gz
#   $BACKUP/postgres/<db>_YYYY-MM-DD_HHMM.dump
#   $BACKUP/filedata/<tenant>/...  (rsync mirror)
#   $BACKUP/ollama_logs/...
#
# Retention: 14 days of DB dumps; filedata is rsync-mirror (no retention).

set -euo pipefail

BACKUP="/mnt/backup"
INFRA="$HOME/projects/infra"
DATE=$(date +%Y-%m-%d_%H%M)
KEEP_DAYS=14

# Tenant filedata volumes — path on ubdock → name on backup share.
# Add a line per tenant as they come online.
declare -A FILEDATA=(
    ["pmem"]="/mnt/data/pmem/files"
    # ["ticker"]="/mnt/data/ticker/files"   # uncomment if/when ticker grows files
)

# ── Pre-flight ───────────────────────────────────────────────────────────
if ! mountpoint -q "$BACKUP"; then
    echo "[error] $BACKUP is not mounted. Run:"
    echo "  sudo mount -t cifs //192.168.50.161/pmem $BACKUP \\"
    echo "      -o credentials=/etc/cifs-credentials,uid=\$(id -u),gid=\$(id -g)"
    exit 1
fi

COMPOSE="docker compose -f $INFRA/docker-compose.yml"

if ! $COMPOSE ps postgres --format '{{.State}}' | grep -q running; then
    echo "[error] infra-postgres is not running. Check: $COMPOSE ps"
    exit 1
fi

echo "=== infra backup — $DATE ==="

# ── 1. Postgres globals (roles, grants, tablespaces) ─────────────────────
mkdir -p "$BACKUP/postgres"
echo -n "  pg_dumpall --globals-only... "
$COMPOSE exec -T postgres pg_dumpall -U postgres --globals-only \
    | gzip > "$BACKUP/postgres/globals_${DATE}.sql.gz"
du -h "$BACKUP/postgres/globals_${DATE}.sql.gz" | cut -f1

# ── 2. Per-database dumps ────────────────────────────────────────────────
# Discover live databases (exclude templates and the admin db)
DBS=$($COMPOSE exec -T postgres psql -U postgres -At -c \
    "SELECT datname FROM pg_database WHERE datistemplate=false AND datname<>'postgres' ORDER BY datname")

for DB in $DBS; do
    echo -n "  pg_dump $DB... "
    $COMPOSE exec -T postgres pg_dump -U postgres -Fc -d "$DB" \
        > "$BACKUP/postgres/${DB}_${DATE}.dump"
    du -h "$BACKUP/postgres/${DB}_${DATE}.dump" | cut -f1
done

# ── 3. Tenant filedata volumes (rsync mirror) ────────────────────────────
for TENANT in "${!FILEDATA[@]}"; do
    SRC="${FILEDATA[$TENANT]}"
    DST="$BACKUP/filedata/$TENANT"
    if [ -d "$SRC" ]; then
        echo -n "  rsync $TENANT filedata... "
        mkdir -p "$DST"
        rsync -a --delete "$SRC/" "$DST/"
        echo "done"
    else
        echo "  rsync $TENANT filedata: source $SRC missing, skipped"
    fi
done

# ── 4. Ollama logs (pmem container's prp_data volume) ────────────────────
# Only runs if pmem's public-record container exists on this host.
if docker inspect public-record >/dev/null 2>&1; then
    echo -n "  copy ollama_logs... "
    mkdir -p "$BACKUP/ollama_logs"
    docker cp public-record:/app/data/ollama_logs/. "$BACKUP/ollama_logs/" 2>/dev/null \
        && echo "done" \
        || echo "(no logs present)"
fi

# ── 5. Retention — prune DB dumps older than KEEP_DAYS ──────────────────
echo -n "  retention prune (>${KEEP_DAYS}d)... "
find "$BACKUP/postgres/" -maxdepth 1 -type f \
     \( -name 'globals_*.sql.gz' -o -name '*.dump' \) \
     -mtime "+${KEEP_DAYS}" -delete
echo "done"

echo "=== backup complete ==="
ls -lh "$BACKUP/postgres/" | tail -6

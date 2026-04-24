-- 011-pmem-councils-region.sql
--
-- Add `region` column to councils and backfill the three-band grouping
-- govlens uses for regional event display (West / East / South).
--
-- Mapping (static — no NUTS-3 split):
--   West  = Connacht + Ulster   (9 councils)
--   East  = Leinster             (15 councils)
--   South = Munster              (7 councils)
--
-- Applied live on 2026-04-24 via the admin role; this file is the
-- durable record for re-provisioning. Idempotent — ALTER uses IF NOT
-- EXISTS; the UPDATE is safe to rerun (overwrites with the same value).
--
--   docker compose exec postgres \
--     psql -U postgres -d pmem -f /provisioning/011-pmem-councils-region.sql

\echo 'Applying 011-pmem-councils-region.sql'

\c pmem

ALTER TABLE councils ADD COLUMN IF NOT EXISTS region text;

UPDATE councils
SET region = CASE
    WHEN province IN ('Connacht','Ulster') THEN 'West'
    WHEN province = 'Leinster'             THEN 'East'
    WHEN province = 'Munster'              THEN 'South'
    ELSE NULL
END
WHERE level = 'Local';

\c postgres

\echo 'Done.'

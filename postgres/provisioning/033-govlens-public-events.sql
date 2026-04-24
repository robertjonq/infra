-- 033-govlens-public-events.sql
--
-- Extend govlens_public read-only whitelist with council_events.
--
-- Safety review:
--   * council_events stores civic events discovered from public council
--     websites — consultations, workshops, public information sessions,
--     open days, exhibitions. Every row's source_url points to the
--     originating public page.
--   * No PII. Contact/booking fields (booking_url) link to council-hosted
--     forms, not people's details.
--   * This is the content surfaced on govlens /v2's Events tile strip,
--     so the public govlens site needs SELECT access.
--
-- Apply once (idempotent — GRANT is a no-op if already held). Already
-- granted live on 2026-04-24 when the Events tile strip was wired; this
-- file is the durable record.
--
--   docker compose exec postgres \
--     psql -U postgres -d pmem -f /provisioning/033-govlens-public-events.sql

\echo 'Applying 033-govlens-public-events.sql'

\c pmem

GRANT SELECT ON public.council_events TO govlens_public;

\c postgres

\echo 'Done.'

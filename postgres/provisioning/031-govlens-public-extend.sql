-- 031-govlens-public-extend.sql
--
-- Extend govlens_public read-only whitelist with the `committees` table.
--
-- Safety review:
--   * `committees` holds statutory committee names + types per council.
--   * Already publicly visible on pmem at /committees (no auth required).
--   * No PII, no write surface — structural reference data only.
--
-- Needed because the govlens /v2 homepage groups "what's happening" by
-- statutory committee type (Full Council / SPC / Municipal District /
-- Area / LCDC / LCSP), and committee_type lives on committees, not
-- meetings.
--
-- Apply once (idempotent — GRANT is a no-op if already held):
--
--   docker compose exec postgres \
--     psql -U postgres -d pmem -f /provisioning/031-govlens-public-extend.sql

\echo 'Applying 031-govlens-public-extend.sql'

\c pmem

GRANT SELECT ON public.committees TO govlens_public;

\c postgres

\echo 'Done.'

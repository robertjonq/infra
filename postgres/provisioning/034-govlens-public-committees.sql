-- 034-govlens-public-committees.sql
--
-- Extend govlens_public read-only whitelist with `officials` and
-- `committee_memberships`.
--
-- Safety review:
--   * Both tables describe public office-holders performing public
--     representative duties — councillor names, parties, electoral
--     areas, and which statutory committees they sit on. Every row
--     is already published on each council's own website (members
--     pages, committee pages); we are surfacing the same facts in a
--     queryable form.
--   * Contact fields on officials (email, phone) are similarly public
--     — they are the public-facing channels councillors publish for
--     constituent contact. Acceptable to expose at the same level
--     they already exist on council websites.
--   * No private/internal data, no auth, no admin.
--
-- Explicitly NOT-granted in 030 originally — this file is the
-- deliberate policy reversal driven by the govlens /v2 "Know Your
-- Committees" feature, which visualises party representation per
-- statutory committee type. Same safety profile as 032
-- (council_source_candidates) and 033 (council_events).
--
-- Apply once (idempotent — GRANT is a no-op if already held).
-- Already granted live on 2026-04-24 when the Know-Your-Committees
-- card was wired; this file is the durable record.
--
--   docker compose exec postgres \
--     psql -U postgres -d pmem -f /provisioning/034-govlens-public-committees.sql

\echo 'Applying 034-govlens-public-committees.sql'

\c pmem

GRANT SELECT ON public.officials             TO govlens_public;
GRANT SELECT ON public.committee_memberships TO govlens_public;

\c postgres

\echo 'Done.'

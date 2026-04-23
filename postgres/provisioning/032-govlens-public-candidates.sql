-- 032-govlens-public-candidates.sql
--
-- Extend govlens_public read-only whitelist with the
-- `council_source_candidates` table.
--
-- Safety review:
--   * Every row is a URL the crawler found on a public council website.
--     Each URL is already publicly fetchable by anyone — we didn't
--     discover anything private, we just indexed public material.
--   * No PII. Status flags (activated / dismissed / negative_reason /
--     confidence_score) describe admin decisions about indexing, not
--     individuals. Acceptable to expose.
--   * Explicitly noted as "NOT granted" in 030's comments — this file
--     is the deliberate policy reversal on that one table, driven by
--     the need below. The remaining NOT-granted tables (officials,
--     committee_memberships, meeting_attendance, Q&A tables, config,
--     auth, audit, backlog, etc.) are intentionally kept out.
--
-- Needed because the govlens /v2 homepage links each confirmed meeting
-- card to its page on the council's own website (the "view on council
-- site" icon). The meeting-page URL lives on the candidate row as
-- `url` or `found_on`, not on the meeting row itself. Same join also
-- powers any future "show me the original doc" affordances on govlens.
--
-- Apply once (idempotent — GRANT is a no-op if already held):
--
--   docker compose exec postgres \
--     psql -U postgres -d pmem -f /provisioning/032-govlens-public-candidates.sql

\echo 'Applying 032-govlens-public-candidates.sql'

\c pmem

GRANT SELECT ON public.council_source_candidates TO govlens_public;

\c postgres

\echo 'Done.'

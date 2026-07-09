-- Persists the LLM receipt-understanding step's structured output
-- (supabase/functions/_shared/receipt_understanding.ts) verbatim, alongside
-- a `_meta` key (model, latency_ms, prompt_source) on success or `_error` /
-- `_raw` on failure. This is testing-phase debuggability for the new
-- LLM-first enrichment flow in enrich-transaction — not a queryable
-- structured column, just a jsonb blob next to the row it explains.
--
-- Owner-scoped like every other transactions column: no new RLS policy
-- needed, it rides the table's existing per-user policies.

alter table public.transactions
  add column if not exists llm_understanding jsonb;

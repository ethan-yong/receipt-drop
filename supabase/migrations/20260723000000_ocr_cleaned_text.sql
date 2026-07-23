-- Persists the LLM OCR-cleanup step's corrected transcript
-- (services/ocr-api/ocr_api/receipt_understanding.py's `cleaned_ocr_text`/
-- `corrections` fields, opt-in via LLM_CLEANUP_ENABLED) alongside — never
-- replacing — `raw_ocr_text`. `cleaned_ocr_text` is its own text column
-- (mirroring `raw_ocr_text`'s own-column precedent, not folded into the
-- existing `llm_understanding` jsonb blob) so both stay independently
-- queryable; `ocr_corrections` is a compact per-line jsonb record
-- ([{line_index, original, corrected}, ...]) for debugging a bad cleanup
-- pass without re-running OCR.
--
-- Owner-scoped like every other transactions column: no new RLS policy
-- needed, it rides the table's existing per-user policies.

alter table public.transactions
  add column if not exists cleaned_ocr_text text,
  add column if not exists ocr_corrections jsonb;

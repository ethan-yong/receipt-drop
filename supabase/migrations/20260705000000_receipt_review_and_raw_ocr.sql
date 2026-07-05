-- Review queue + parse-evidence columns.
--
-- raw_ocr_text is kept only for failed/low-confidence parses: free labeled
-- data for fixing parser rules. ocr_service_confidence (scan quality) is
-- distinct from ocr_confidence (amount-extraction confidence).

alter table public.transactions
  add column if not exists raw_ocr_text text,
  add column if not exists ocr_service_confidence double precision,
  add column if not exists line_items_confidence double precision,
  add column if not exists parse_failure_reason text;

-- Inline column CHECKs get auto-named <table>_<column>_check.
alter table public.transactions
  drop constraint if exists transactions_pipeline_status_check;
alter table public.transactions
  add constraint transactions_pipeline_status_check
  check (pipeline_status in
    ('provisional', 'enriched', 'failed_enrichment', 'needs_review'));

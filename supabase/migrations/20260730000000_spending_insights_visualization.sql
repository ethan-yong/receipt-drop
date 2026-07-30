-- Visualization Story Agent output: a small, rule-based visual spec
-- (chart type, data source, parameters, highlight, animation) attached to
-- a curated insight by services/ocr-api/ocr_api/insights/visualization_agent.py.
-- Null when no visual strengthens the insight (e.g. streak). Not shown to the
-- user yet — client rendering is a follow-up; this column just carries the
-- contract end-to-end so it's proven out before that work starts.

alter table public.spending_insights
  add column if not exists visualization jsonb;

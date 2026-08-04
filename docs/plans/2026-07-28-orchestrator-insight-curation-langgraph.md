# Feature: Orchestrator-Driven Insight Curation (LangGraph Migration)

## Context

This is a follow-on spec to `docs/plans/2026-07-28-ai-spending-insights.md`,
which is now implemented and live: five deterministic Dart detectors run
on-device after `SyncWorker.run` succeeds, produce a small candidate pool,
and a single LLM "curator" call (Supabase Edge Function `curate-insights` →
`services/ocr-api`'s `insight_curator.py`) dedupes/ranks/rewrites them into
up to 3 friendly sentences, persisted to Postgres and mirrored into Drift
for the Home card and detail view.

This document specifies evolving the **curation half** of that pipeline
(not the on-device detection half, which stays as-is) into an
orchestrator-driven agent system built on LangGraph: an Orchestrator
decides which narrow specialist agents are worth running for a given signal
set (to avoid blindly firing every agent/LLM call), specialist agents each
reason over one domain, and a Critic agent combines/ranks/rewrites their
output — replacing today's single monolithic curator prompt with a graph of
smaller, composable steps, migrated in phases rather than rewritten
wholesale.

This is a technical specification only — no code included. It is meant to
be handed to an implementing engineer or AI coding agent, who will inspect
the current codebase in depth and produce their own implementation plan.
Every file path, function name, and schema field cited below was confirmed
directly against the current codebase (two research passes plus direct
reads of `curate-insights/index.ts`, `insight_curator.py`, and
`dashboard_aggregates.dart`), not assumed from the prior spec.

## Overview

Evolves the existing single-LLM-call "curator" step of AI Spending Insights
into a small LangGraph state graph: a rule-based Orchestrator node routes
each cycle's on-device-generated signals to only the specialist agents
relevant to them, narrow specialist nodes reason over their own domain slice,
and a Critic node dedupes/ranks/rewrites the combined output into the same
≤3-insight, closed-vocabulary format the client already consumes. The
on-device detection layer, the Postgres/Drift persistence layer, and the
Home card/detail-view UI are unchanged — this is a curation-layer
architecture change, not a new user-facing feature.

## Problem Statement

Today's curator (`services/ocr-api/ocr_api/insight_curator.py`) is one LLM
call carrying one system prompt that must simultaneously dedupe, rank, and
rewrite across all five detector domains (spikes, category shifts, habits,
streaks, forecasts) at once. That's adequate at today's scope, but it means
every prompt-tuning change to one insight type risks regressing another
type's phrasing (shared prompt, shared context window), and there's no
mechanism to skip reasoning about domains that have nothing to say this
cycle beyond "the candidate pool happened to be empty for that type." An
orchestrator + specialist-agent split makes "should we even reason about
category behavior this cycle" an explicit, cheap, pre-LLM decision, and lets
each domain's prompt/logic evolve independently.

## Goals

- Introduce an Orchestrator step that decides which specialist analysis
  paths are relevant for a given cycle's signals, without calling an LLM to
  make that decision.
- Give each of the five insight domains (spending anomaly, category
  behavior, merchant habit, motivation/streak, forecast) its own narrow
  agent boundary, so its logic/prompt can be iterated independently of the
  others.
- Preserve every existing safety property: closed type vocabulary, no
  fabricated facts, ≤3 final insights, silent degrade on failure, per-user
  JWT scoping, no raw transactions/OCR text ever reaching an LLM.
- Migrate incrementally in phases that are each independently shippable and
  revertible, with no phase requiring a client (Dart) release.
- Keep or reduce total LLM calls per cycle relative to today wherever
  possible; where a phase genuinely increases call count (specialist LLM
  agents), gate it behind an explicit kill switch.

## Non-Goals

- No changes to the on-device detection layer: `lib/domain/logic/insight_detectors.dart`'s
  five detector functions, `insights_worker.dart`'s guard/re-entrancy logic,
  and the `InsightCandidate` shape all stay exactly as they are. The
  Orchestrator consumes their output as-is.
- No changes to persistence or sync-down: the `spending_insights` Postgres
  table, its RLS, the Drift `local_spending_insights` mirror, and
  `InsightsRepository`'s upsert/dismiss flow are unchanged.
- No changes to the Home card or detail-view UI (`insight_home_card.dart`,
  `insights_detail_screen.dart`) — they already just watch the local mirror
  table and don't know or care how an insight was curated.
- No LLM-based Orchestrator in this migration. The "Decision Logic" section
  below makes this an explicit recommendation, not an open question: routing
  stays rule-based through Phase 3; an LLM orchestrator is deferred
  indefinitely unless Phase 4 personalization produces genuinely open-ended
  routing decisions a fixed table can't express (see Tradeoffs).
- No new insight domains beyond the existing five — same closed vocabulary
  (`spending_spike`, `category_shift`, `habit`, `streak`, `forecast`),
  renamed to specialist-agent framing but not expanded.
- No wire-contract change to the `curate-insights` Edge Function's
  request/response shape through Phase 3 — internal restructuring only, so
  the client needs no changes and no release for Phases 1-3.

## Proposed Solution

Keep the on-device candidate pool exactly as generated today —
`InsightCandidate { type, factKey, facts, severity, templateHint }` — and
treat it as the "signals" the new graph consumes; no Dart changes needed.
Replace the single `call_insight_curator()` LLM call inside
`services/ocr-api` with a LangGraph graph, invoked from the same
`/curate-insights` FastAPI route the Edge Function already calls (route name
and I/O contract unchanged): a `SignalLoader` node validates/sanitizes
incoming candidates (parity with today's `sanitizeCandidates`/
`InsightCandidateIn`), an `Orchestrator` node applies a fixed signal-type →
specialist-agent routing table plus a severity threshold to decide which
specialist nodes to dispatch, those specialist nodes run in parallel via
LangGraph's fan-out and each emit structured (not yet final-prose) candidate
insights for their domain, and a `Critic` node — carrying forward today's
`insight_curator.py` prompt/validation almost unchanged — aggregates,
dedupes, ranks, rewrites into final friendly copy, and hands off to the
existing `Persistence` step (the unchanged Postgres insert + response
shape). Migration happens in four phases (detailed in Implementation
Guidance) that separate "add the graph plumbing" from "add real specialist
LLM calls," so the highest-risk/highest-cost step ships last and behind its
own flag.

## User Experience

No client-visible change for Phases 1-2: same Home card, same detail view,
same insight cadence and copy style, because the Critic node's output
contract is identical to today's curator output contract. Phase 3
(specialist LLM agents) may change insight *phrasing depth* per domain (a
category-behavior insight can reason more specifically about that domain
once it has its own prompt), but the UI surface, dismiss interaction, and
persistence semantics are unchanged throughout. Failure/degraded states are
unchanged: any node failure anywhere in the graph must resolve to "no new
insights this cycle, previously-persisted non-dismissed insights remain
visible" — the same silent-degrade contract `docs/plans/2026-07-28-ai-spending-insights.md`
already established and the client already handles.

## System Impact

- **Client application**: none. `lib/domain/logic/insight_detectors.dart`,
  `lib/data/repositories/insights_worker.dart`,
  `lib/data/repositories/insights_repository.dart`, `lib/data/local/tables.dart`,
  `lib/widgets/insight_home_card.dart`, and
  `lib/features/insights/insights_detail_screen.dart` all require zero changes.
- **Backend services**: `services/ocr-api` gains a new dependency
  (`langgraph`, plus its `langchain-core` transitive dependency) and its
  curation logic moves from `insight_curator.py`'s single function into a
  small graph module set (new `orchestrator.py`, `specialist_agents.py`,
  `graph.py`, alongside the retained `insight_curator.py` logic now living
  in the Critic node). The FastAPI route at `main.py:308-332` changes its
  internal call from `call_insight_curator()` to graph invocation; its
  request/response shape does not change.
- **Database/storage**: none. No new tables, no migration. Phase 4's
  engagement-weighted routing (if pursued) reads the existing
  `spending_insights.dismissed`/`insight_type` columns — already present,
  no schema change needed even then.
- **AI/ML pipeline**: Phases 1-2 keep exactly one LLM call site (moved from
  `insight_curator.py` into the Critic node, same prompt/validation
  approach). Phase 3 adds up to five additional LLM call sites (one per
  specialist agent), but only the subset the Orchestrator selects actually
  fire in a given cycle — typically 1-2 per the signal shapes seen in
  practice, not all 5.
- **Infrastructure**: none beyond the new Python dependency — no new
  service, no new scheduler, consistent with the existing "no cron/
  WorkManager" non-goal from the original insights spec.
- **External integrations**: none new — reuses the existing LLM gateway
  client (`resolve_llm_config()`/`_chat_completions_url()` from
  `receipt_understanding.py`) that `insight_curator.py` already calls.

## Technical Design

**Graph nodes:**

- **SignalLoader**: validates the incoming `candidates` payload against the
  same closed-vocabulary/shape rules `sanitizeCandidates()` (Edge Function)
  and `InsightCandidateIn` (Pydantic model in today's `insight_curator.py`)
  already enforce; caps pool size (today's existing 20-item cap carries
  over); attaches `userId`/`timeframe` metadata into graph state. This is
  the graph's single validation boundary for *input* signals — a second,
  independent validation boundary exists later at specialist-output time
  (see Decision Logic) so a fabricated fact can't be laundered through an
  intermediate node.
- **Orchestrator**: a fixed, rule-based routing table mapping signal
  `type` → one or more specialist agent names (e.g. `spending_spike` →
  `spending_anomaly_agent`; `category_shift` → `category_behavior_agent`;
  `habit` → `merchant_habit_agent`; `streak` → `motivation_agent`;
  `forecast` → `forecast_agent`), plus a per-type severity floor before a
  signal is considered worth dispatching at all (a second-layer confidence
  gate on top of what the on-device detector already decided — see Decision
  Logic for why this doesn't just duplicate the detector's own gating).
  Produces `selectedAgents` in state. If the incoming pool is empty or no
  signal clears its severity floor, the graph short-circuits directly to
  END without touching any specialist or the Critic — zero LLM cost for an
  empty/weak cycle, identical to today's "skip curator entirely" behavior.
- **Specialist agent nodes** (up to five: `spending_anomaly_agent`,
  `category_behavior_agent`, `merchant_habit_agent`, `motivation_agent`,
  `forecast_agent`): each receives only the state slice of signals the
  Orchestrator routed to it — not the full pool, a narrower data-minimization
  boundary than today's curator (which sees every candidate at once).
  Dispatched via LangGraph's parallel `Send` mechanism so only the
  Orchestrator-selected subset actually runs, and the ones that do run
  execute concurrently rather than in a sequential loop (latency
  implication — see Performance Considerations). Each returns zero or more
  structured "insight drafts" (not final prose — see Critic below for why
  final phrasing stays centralized) tied back to the originating
  `factKey`, appended into a shared, reducer-merged state list (see Edge
  Cases for the state-merge risk this implies).
- **Critic**: fan-in point — waits for all dispatched specialist branches,
  then combines their drafts. Carries forward today's `insight_curator.py`
  logic almost unchanged: dedupe by `fact_key`, rank by severity/novelty,
  cap at 3, reject anything whose `fact_key`/`type` doesn't trace back to an
  original signal, and perform the final prose rewrite pass — kept
  centralized here (rather than letting each specialist emit final-ready
  sentences) specifically to guarantee one consistent voice across domains,
  which is the main quality risk once prompts are split across multiple
  agents (see Tradeoffs).
- **Persistence**: unchanged from today — insert into `spending_insights`
  (owner JWT via the Edge Function's scoped Supabase client), return the
  inserted rows in the HTTP response for the client to mirror locally, with
  the same soft-degrade-to-ephemeral-ids fallback on insert failure that
  `curate-insights/index.ts` already implements.

**Edges:** SignalLoader → Orchestrator (always). Orchestrator → conditional
parallel dispatch to each node in `selectedAgents` via LangGraph's `Send`
API, or → END directly if `selectedAgents` is empty. All dispatched
specialist nodes → Critic (fan-in on shared state). Critic → Persistence →
END.

**Where this runs:** entirely inside `services/ocr-api` — LangGraph is a
pure-Python library, Dart/Flutter has no equivalent and none is needed since
signal generation stays on-device and unchanged. The `curate-insights` Edge
Function's role doesn't change: it remains the thin per-user-JWT-scoped BFF
that forwards to `services/ocr-api` and persists the result; only what
happens *inside* ocr-api's `/curate-insights` handler changes, from a single
function call to a graph invocation.

## State Schema

State carried through the graph, and what's allowed at each stage:

- `userId` — used only for Postgres RLS scoping via the Edge Function's
  already-scoped JWT client; must never be included in any specialist/Critic
  LLM prompt payload.
- `timeframe` — metadata only (e.g. cycle timestamp), not itself sent to an
  LLM unless a specific candidate's `facts` already legitimately reference a
  date.
- `signals` — the validated `InsightCandidate` pool from SignalLoader:
  `{type, factKey, facts, severity, templateHint}` per item. This is the
  only "raw-ish" data any node touches, and it's already the structured,
  privacy-minimized shape the client sends today — never raw transactions,
  OCR text, or line items.
- `selectedAgents` — Orchestrator's routing decision: which specialist
  agent names are dispatched this cycle, and (internally) which `signals`
  subset each one receives. Each specialist node is scoped to only its own
  subset, not the full `signals` list.
- `candidateInsights` — the specialist nodes' structured output (drafts,
  not final prose), accumulated via a reducer-merged list so concurrent
  branches don't clobber each other (see Edge Cases). Each entry still
  carries its source `factKey`/`type` for the Critic's no-fabrication check.
- `finalInsights` — Critic's output: ≤3 items of `{type, fact_key, body}`,
  the same shape `curate-insights/index.ts` already validates and persists
  today. This is the only state that reaches Persistence.

## Decision Logic

- **Orchestrator stays rule-based, never an LLM, through Phase 3.** The
  signal vocabulary is a small closed set (5 types); a fixed mapping table
  is sufficient, cheaper, and has zero hallucination surface. An LLM
  orchestrator would add a full LLM round-trip purely to make a decision a
  lookup table already makes correctly — reconsider only if Phase 4
  personalization needs genuinely open-ended routing a table can't express.
- **Orchestrator's severity floor vs. the on-device detector's own
  data-sufficiency gate**: these are not redundant. The on-device detector
  decides "is this real enough to be a candidate at all" (e.g. Spending
  Spike's 2x-baseline threshold); the Orchestrator's floor decides "given
  everything that qualified this cycle, is this one worth a specialist's
  attention" — relevant once/if a cycle has many qualifying signals and the
  cost budget favors picking the strongest few rather than dispatching a
  specialist per weak-but-technically-valid signal. Set the Orchestrator's
  floor at or slightly below each detector's own severity output range
  initially (i.e., permissive — pass through almost everything that
  qualified on-device) rather than inventing new thresholds pre-launch;
  tighten only once real severity-score distributions are observed.
- **Empty or all-sub-threshold candidate pool**: Orchestrator emits an empty
  `selectedAgents`; graph transitions straight to END; no specialist node,
  no Critic call, no LLM cost — identical in spirit to today's existing
  "skip curator entirely" rule.
- **Specialist agent output validation**: each specialist's returned draft
  must reference a `factKey` present in the signals it was actually given
  (not the whole original pool) and a `type` matching that signal's type —
  reject anything that doesn't, exactly mirroring today's
  `validateCurated()`/`parse_curated_insights()` no-fabrication check, just
  applied one boundary earlier than before.
- **Partial specialist failure**: if one dispatched specialist node errors
  or times out while others succeed, the graph must not fail the whole
  cycle — that specialist's contribution is simply absent from the Critic's
  input; Critic proceeds with whatever succeeded. If every dispatched
  specialist fails, Critic receives an empty draft list and the cycle
  produces zero new insights (same terminal behavior as today's curator
  timeout/error path) — never surfaced as an app-visible error.
- **Critic behavior**: unchanged from today's `insight_curator.py` contract
  — dedupe, rank (severity tie-break), cap at 3, reject unlisted `type` or
  missing/duplicate `fact_key`, reject any output whose `fact_key` doesn't
  trace to a source signal it was given. On malformed/unparseable LLM
  output, degrade to the existing `template_fallback()` behavior (unchanged)
  rather than erroring.
- **Kill switches**: extend today's `INSIGHTS_CURATOR_LLM` env-var pattern
  with a second flag gating Phase 3 specifically (e.g.
  `INSIGHTS_SPECIALIST_AGENTS_ENABLED`), independent of the Critic's own
  LLM-vs-template toggle — lets Phase 2 (rule orchestrator + single Critic
  LLM call, functionally identical to today's cost/latency profile) soak in
  production before Phase 3's genuinely more expensive specialist calls are
  enabled for anyone.

## Edge Cases

- **Parallel state-merge clobbering**: if the shared LangGraph state field
  the specialist nodes write into isn't declared with a proper accumulating
  reducer (e.g. `Annotated[list, operator.add]`), concurrent branches can
  overwrite each other's contributions instead of merging — this is the
  single most likely implementation bug in the parallel fan-out and must be
  explicitly tested (see Testing Strategy), not just assumed correct because
  it works in a manual single-branch test.
- **One specialist times out, others succeed**: covered in Decision Logic —
  degrade gracefully, don't fail the cycle.
- **All dispatched specialists fail or time out**: Critic receives nothing;
  cycle yields zero new insights; previously-persisted, non-dismissed
  insights remain visible, matching the existing UX contract.
- **Orchestrator selects an agent whose signal later turns out to have
  sub-threshold severity after some future scoring change**: the routing
  table and the floor check must be re-evaluated together if severity
  scoring ever changes on the Dart side — flag this coupling explicitly so
  a future on-device severity-formula change doesn't silently starve or
  flood the Orchestrator without anyone checking the floor constant.
- **Combined per-cycle timeout budget**: today's Edge Function has a single
  30s (`UPSTREAM_TIMEOUT_MS`) upstream timeout wrapping one LLM hop. Once
  Phase 3 introduces two sequential LLM "hops" in the critical path
  (parallel specialists, then Critic), the existing 30s budget is too tight
  — this must change before Phase 3 ships, not be discovered in production
  (see Performance Considerations for the concrete number).
- **New/sparse-data users**: unchanged — if the on-device detectors produce
  no candidates (as today, e.g. no historical baseline yet), the pool
  arriving at SignalLoader is already empty; no new edge case introduced by
  the graph.

## Performance Considerations

- **Phases 1-2**: unchanged latency/cost profile from today — one LLM hop
  (now living in the Critic node instead of directly in
  `call_insight_curator()`), plus negligible LangGraph graph-execution
  overhead. No timeout budget changes needed yet.
- **Phase 3**: latency becomes `max(dispatched specialist latencies) +
  Critic latency` if specialists genuinely run in parallel (the point of
  using LangGraph's `Send` fan-out rather than a sequential loop) — not the
  sum of all specialist latencies. Still, this is two sequential LLM hops
  in the critical path versus today's one, so worst-case end-to-end latency
  roughly doubles. Given each hop's own call uses the existing
  `LLM_TIMEOUT_SECONDS = 25.0` budget, the wrapping Edge Function timeout
  (today's `UPSTREAM_TIMEOUT_MS = 30_000`) must be raised — to roughly
  50-60s — before Phase 3 ships, or a Critic call will routinely get cut off
  waiting on slow specialists.
- **Cost**: Phases 1-2 add zero LLM calls versus today. Phase 3 adds up to
  5 additional call sites, but real cost per cycle is bounded by how many
  agents the Orchestrator actually selects — per the signal shapes already
  seen in the codebase's own example payloads, typically 1-2 agents per
  cycle, not all 5, so realistic added cost is roughly 1-2 extra LLM calls
  per cycle, not 5. This must still be measured against real traffic before
  considering Phase 3 "cost-neutral enough" — no number here is assumed,
  only bounded.
- **On-device cost**: zero change — detection remains the same pure,
  synchronous, in-memory Dart computation it is today.

## Security Considerations

- **No change to data-minimization boundary at the outer edge**: raw
  transactions, OCR text, and line items still never leave the device or
  reach any LLM — only structured signal facts do, exactly as today.
- **Narrower minimization *within* the graph**: each specialist agent sees
  only its own routed subset of signals, not the full pool — a strictly
  smaller LLM-visible surface per call than today's single curator prompt,
  which sees everything at once. Worth stating as a net privacy
  improvement, not just an architectural change.
- **`userId` must never enter any LLM prompt payload** at any node — it's
  used only for Postgres RLS scoping (via the Edge Function's per-user JWT
  client, unchanged) and must be stripped from whatever state slice is
  handed to specialist/Critic prompt construction. This should be an
  explicit assertion/test, not an implicit assumption, since it's now
  threaded through more state than before.
- **Two independent no-fabrication validation boundaries are now required**,
  not one: specialist output must be checked against the signals it was
  actually given (new boundary) *and* Critic output must still be checked
  against what the specialists (or, in Phases 1-2, the raw signals) actually
  produced (today's existing boundary) — skipping the first would let a
  specialist inject an unsupported fact that the Critic then "launders" into
  final copy under a real `fact_key`, defeating the whole point of
  traceability.
- **RLS/per-user scoping is unaffected**: the Edge Function's JWT-scoped
  Supabase client and the `spending_insights_owner` RLS policy are untouched
  by this migration — the graph runs entirely before the Postgres write,
  which still happens exactly as it does today.

## Tradeoffs

- **Rule-based vs. LLM-based Orchestrator**: rule-based chosen. An LLM
  orchestrator adds a full extra round-trip, cost, and hallucination surface
  to make a decision a 5-entry lookup table already makes deterministically
  and correctly at today's vocabulary size. Only revisit if routing
  decisions become genuinely open-ended (Phase 4 personalization is the
  named candidate, and even that's expected to stay rule-based-with-learned-
  weights rather than jump straight to an LLM — see Non-Goals).
  Note: this recommendation directly answers the "cost optimization"
  question, but it does contradict the letter (not spirit) of "orchestrator
  decides which specialists run" reading as inherently LLM-driven — call
  this out explicitly to the implementing engineer so it isn't silently
  "corrected" back to an LLM orchestrator during implementation without
  re-litigating the reasoning above.
- **Specialists as narrow LLM agents (Phase 3) vs. keeping them as
  deterministic Python transforms indefinitely**: the latter is genuinely
  simpler and cheaper, and would still deliver "narrow, composable curation
  steps" without adding LLM call sites at all. Phase 3's LLM specialists are
  recommended anyway, but only *after* Phases 1-2 have proven the graph
  plumbing, specifically because per-domain LLM reasoning is what plausibly
  improves insight *quality/depth* over today's one-shot rewrite — Phase 3
  should be treated as an experiment to validate against real output
  quality, not an assumed win, and the kill switch exists precisely so it
  can be rolled back without reverting the graph structure itself.
- **Critic keeps the final prose-rewrite pass, rather than letting each
  specialist emit client-ready sentences**: centralizing final phrasing
  avoids an inconsistent-voice risk across five independently-evolving
  prompts — the cost is that Critic remains on the critical path for every
  cycle (can't be skipped once any specialist ran), but that's true of
  today's architecture already, so it's not a regression.
- **LangGraph as a new dependency in `services/ocr-api` vs. hand-rolling the
  same fan-out/fan-in with plain async Python**: LangGraph was requested
  explicitly and gives battle-tested state-reducer/parallel-dispatch
  semantics (the exact mechanism the Edge Cases section flags as the
  highest implementation risk) for less custom code than hand-rolling the
  same guarantees — accepted as the right call given the explicit ask, but
  flagged here as a new dependency surface (its own version upgrades, its
  own failure modes) that wouldn't exist if the team had chosen to stay with
  plain async orchestration instead.
- **Complexity/maintainability, current vs. new**: today's 2-file linear
  flow (Edge Function + one Python function) is trivially easy to reason
  about end-to-end; the graph version trades that for narrower, more
  independently-testable/iterable units at the cost of more moving parts
  (state schema, reducers, conditional routing, multi-node partial-failure
  handling) — a genuine complexity increase that only pays off once
  multiple people are actively iterating on different insight domains'
  prompts independently. For a small team touching this rarely, the
  monolithic curator prompt might remain the pragmatically simpler choice;
  this tradeoff should be weighed honestly against actual team size/cadence,
  not assumed to be a win by default.
- **Latency/cost/complexity/maintainability/UX, current vs. new, summarized**:
  Latency — unchanged in Phases 1-2, roughly doubles in the worst case once
  Phase 3's two sequential LLM hops land (see Performance Considerations).
  Cost — unchanged in Phases 1-2, bounded increase of ~1-2 extra LLM calls
  per cycle in Phase 3 given typical signal shapes, not the full 5.
  Complexity — increases at every phase after Phase 1, most sharply at
  Phase 3 (parallel fan-out, multi-node partial failure); this is the
  primary cost of the whole migration. Maintainability — improves once
  more than one person is actively iterating on different insight domains'
  prompts; roughly neutral-to-worse for a single small team touching this
  rarely. User experience — unchanged through Phase 2; Phase 3 is a bet
  that narrower per-domain reasoning produces measurably better insight
  copy, which should be validated against real output before treating it as
  a win.

## Implementation Guidance

Suggested phase-by-phase order of work (mirrors the requested phase
breakdown, with concrete engineering substance added):

1. **Phase 1 — orchestrator layer, no LangGraph yet.** Add the rule-based
   routing table as a plain Python function inside `services/ocr-api`
   (no new dependency yet), inserted between candidate receipt and the
   existing `call_insight_curator()` call. Its only job this phase: tag
   which candidates clear the severity floor and which specialist-agent
   name they'd map to, purely as an explicit, loggable artifact — runtime
   behavior stays identical to today (still one curator call, over the
   full still-eligible pool). Ships fast, zero risk, establishes the
   interface. Inspect `services/ocr-api/ocr_api/insight_curator.py` and
   `main.py:308-332` first.
2. **Phase 2 — move the curator workflow into a real LangGraph graph.**
   Add the `langgraph` dependency. Build the actual graph with exactly two
   functional nodes: Orchestrator (Phase 1's table, now a real graph node)
   and Critic (today's `insight_curator.py` prompt/validation, ported in
   near-verbatim as the Critic node) — no specialist LLM nodes yet; route
   Orchestrator's output straight to Critic (optionally grouped by
   agent-category for the Critic's own context organization, but still one
   LLM call). This phase's entire purpose is proving the LangGraph plumbing
   (state schema, conditional edges) with zero behavior change and zero new
   LLM call sites — the safest place to catch state-schema mistakes before
   anything user-facing depends on them.
3. **Phase 3 — introduce specialist LLM agents.** Split Critic's single
   prompt into the five narrow specialist nodes described in Technical
   Design, each with its own tightly-scoped system prompt over its routed
   signal slice; Critic becomes a pure aggregator/ranker/final-rewrite pass
   over their structured drafts. Gate entirely behind the new
   `INSIGHTS_SPECIALIST_AGENTS_ENABLED`-style flag. Before enabling in
   production, raise the Edge Function's `UPSTREAM_TIMEOUT_MS` (currently
   30_000 in `supabase/functions/curate-insights/index.ts`) to account for
   the new two-hop critical path (see Performance Considerations).
4. **Phase 4 — adaptive/personalized routing.** Only after Phase 3 has real
   usage data: consider weighting Orchestrator agent selection using
   engagement signals already in the schema (`spending_insights.dismissed`,
   `insight_type`) — e.g. de-prioritize dispatching a specialist whose
   insight type a user consistently dismisses. Keep this rule-based-with-
   learned-weights rather than introducing an LLM orchestrator (see
   Tradeoffs) unless routing genuinely needs to become open-ended.

Files to inspect/touch, in order: `services/ocr-api/ocr_api/insight_curator.py`
(becomes the Critic node's logic home), `services/ocr-api/ocr_api/main.py:308-332`
(route's internal call site changes), `services/ocr-api`'s Python
dependency manifest (add `langgraph`), new
`orchestrator.py`/`specialist_agents.py`/`graph.py` modules alongside it,
and — Phase 3 only — `supabase/functions/curate-insights/index.ts`'s
`UPSTREAM_TIMEOUT_MS` constant. No `lib/`, no `supabase/migrations/`, no
Drift schema changes at any phase.

Primary risk to flag going in: the parallel state-merge reducer bug
described in Edge Cases is the one thing in this whole migration that can
silently produce wrong behavior (dropped specialist output) without any
error being thrown — write the merge test described below before trusting
Phase 3's fan-out in any environment beyond local dev.

## Testing Strategy

- Fixture-based unit tests for the Orchestrator's routing table: given a
  fixed set of signal types/severities, assert the exact `selectedAgents`
  set produced, including the empty-pool and all-sub-threshold cases —
  pure function, same style as the existing `test/insight_detectors_test.dart`
  fixtures (ported to Python/pytest for the ocr-api side).
- A dedicated parallel-fan-out state-merge test: dispatch 3+ specialist
  nodes concurrently against a stub graph and assert all of their
  contributions are present in the Critic's input — this is the test that
  would catch the reducer-clobbering bug called out in Edge Cases; do not
  skip it because a single-branch manual test looked correct.
- A partial-failure test: one specialist node raises/times out, others
  succeed — assert the cycle still completes and Critic receives the
  surviving drafts, never an unhandled exception propagating to the HTTP
  response.
- An all-fail test: every dispatched specialist fails — assert the cycle
  terminates with zero new insights and no app-visible error, matching
  today's timeout/error contract.
- Port today's `insight_curator.py` validation tests (malformed JSON,
  unknown/off-whitelist type, fabricated `fact_key` not present in the
  input) to run against both the new specialist-output validation boundary
  and the Critic's existing validation boundary — both must independently
  reject the same failure classes.
- No new client-side (Dart) tests are needed — the client's contract with
  `curate-insights` doesn't change.

## Rollout Plan

Phases 1-2 require no feature flag beyond normal deploy practice: Phase 1
changes nothing observable; Phase 2 changes internals behind an unchanged
I/O contract, so it can ship straight to production and be verified by
diffing generated-insight output against the pre-migration curator over a
sample of real cycles before fully cutting over. Phase 3 must ship behind
the new `INSIGHTS_SPECIALIST_AGENTS_ENABLED` flag (env-var controlled,
matching today's `INSIGHTS_CURATOR_LLM` pattern — no feature-flag/remote-
config system exists in this codebase, and building one is out of scope
here too), disabled by default, enabled only after the timeout-budget
change and the fan-out state-merge test are both in place. Rollback at any
phase is immediate and safe: flipping the relevant env var back reverts to
the previous node's behavior, and no already-persisted `spending_insights`
rows are affected either way, since persistence shape never changes.
Because every phase is server-only, no client release, staged rollout, or
backward-compatibility window is needed at any point in this migration.

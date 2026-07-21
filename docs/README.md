# Receipt Drop documentation

Index of all project documentation. Start at [`CLAUDE.md`](../CLAUDE.md) for the agent-oriented map; use this file to browse by topic.

## System

| Doc | Description |
|---|---|
| [system/architecture.md](system/architecture.md) | High-level design, data flow, platform-split patterns, production hosting |
| [system/decisions.md](system/decisions.md) | ADR-style log — what changed, why, tradeoffs |

## API & services

| Doc | Description |
|---|---|
| [api/overview.md](api/overview.md) | Edge Functions, OCR API, leaderboard API — endpoints, auth, integrations |
| [api/enrich-transaction.md](api/enrich-transaction.md) | Walkthrough of the enrichment Edge Function control flow |

## Database

| Doc | Description |
|---|---|
| [database/schema.md](database/schema.md) | Postgres schema (cumulative), RLS, storage, RPCs, Drift local schema |

## Plans

| Doc | Description |
|---|---|
| [plans/2026-07-21-ocr-preprocessing-pipeline-upgrade.md](plans/2026-07-21-ocr-preprocessing-pipeline-upgrade.md) | Planned OCR preprocessing improvements (document detection, CLAHE, sharpen) |

## Design

| Doc | Description |
|---|---|
| [design/design_handoff_receipt_flows/](design/design_handoff_receipt_flows/) | HTML handoff mocks for receipt confirm sheet and place picker |

## Archive

Historical planning docs from before the current AI-agent documentation system.

| Doc | Description |
|---|---|
| [archive/superpowers/specs/2026-05-11-receipt-drop-design.md](archive/superpowers/specs/2026-05-11-receipt-drop-design.md) | Original v1 product spec |
| [archive/superpowers/plans/2026-05-11-receipt-drop-v1.md](archive/superpowers/plans/2026-05-11-receipt-drop-v1.md) | Original v1 implementation plan |

## Related (outside `docs/`)

| Path | Description |
|---|---|
| [`.claude/context.md`](../.claude/context.md) | Current in-flight state, incomplete features |
| [`.claude/commands.md`](../.claude/commands.md) | Run, build, test, deploy commands |
| [`memory/feature_graph.md`](../memory/feature_graph.md) | Feature → dependency → file mapping |
| [`memory/bugs.md`](../memory/bugs.md) | Known bugs and workarounds |
| [`memory/experiments.md`](../memory/experiments.md) | Approaches tried and abandoned |
| [`pending-tasks.md`](../pending-tasks.md) | Deliberately deferred backlog |

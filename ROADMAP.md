# Roadmap

> Last updated: 2026-08-09. This roadmap tracks **DbMaster Core** (the desktop client) and its relationship to **DbMaster Server** (the paid automation engine). See [`docs/commerce/pricing.md`](docs/commerce/pricing.md) for the authoritative commercial model.

## Product model

| Product | Price | Role |
|---|---|---|
| **DbMaster Desktop** (this repo) | **Free**, Apache-2.0 | Database client for MySQL, PostgreSQL, SQLite, MongoDB, Redis, Doris, TDengine, SQL Server — unlimited connections, tabs, AI usage |
| **DbMaster Server** | ¥399/year/instance | Self-hosted automation: scheduled Data Sync, health checks, slow-query reports, schema-drift alerts, team collaboration, DDL approvals |

Desktop is the funnel — every manual operation is an advertisement for Server automation. No crippleware, no feature gates in the client.

---

## ✅ Shipped (recent highlights)

### SQL safety review engine (multi-phase)
Real-time safety review before executing SQL in the editor.
- **Rules**: schema compatibility, missing LIMIT, full-table-scan (static + EXPLAIN), SQL injection, large result set, DDL impact analysis
- **Configurable**: 6 rule toggles + unified row-count threshold in Settings (per-rule on/off, adjustable thresholds)
- **DDL lock semantics**: MySQL (INSTANT/INPLACE/COPY), PostgreSQL (ACCESS EXCLUSIVE / SHARE / CONCURRENTLY), SQLite (table-rebuild vs metadata)
- **Inline feedback**: per-line error indicators in the editor gutter; execution-gate dialog with rollback scripts
- **AI integration**: AI agent's schema-impact analysis now carries accurate lock semantics

### PostgreSQL native experience
- Extension browser (pgvector etc.), pgvector panel, JSONB viewer, JSON field extraction (PG `->`/`->>` + MySQL `JSON_EXTRACT` + SQLite `json_extract`)

### Results → insight loop
- Table / chart / card view switching, chart recommendations, statistics summary, PII-aware export, AI trend analysis

### Other
- 8 database types with SSH tunnel support
- AI chat (bring your own API key) + AI Agent (tool-loop)
- Schema Diff, DDL Impact Analysis, Query Plan Visualization
- ER diagrams, visual table editing, stored procedures & triggers
- Multi-language (EN / zh / zh-TW / de / fr / ru), dark/light theme

---

## 🚧 In progress / next up

### Desktop client
- **Inline wave-underlines** for safety findings (currently line-level dots; token-level wave needs `package:highlight` AST offset support)
- **SQLite PRAGMA explorer** (`task_sqlite_native_experience.md` P2)
- **Schema Diff real-DB end-to-end walkthrough** (`task_schema_diff_e2e.md`)
- **Sidebar tree optimization** — extend proven SQL Server logic to other DB types (`task_sidebar_tree_optimization.md`)

### Safety review (deeper)
- Doris / SQL Server / ClickHouse / Oracle DDL lock semantics (PG/SQLite done in B4; the rest need per-DB lock-model research)
- Index recommendation → review pipeline deepening (B2 connected the "apply" button; redundant-index detection is a follow-up)
- CI/CD SQL review + standalone productization (long-term)

---

## 🌐 Distribution

- **GitHub Releases** for Desktop binaries (Windows / macOS / Linux) — **not** the App Store
- Server via Docker single-container on user's own infrastructure
- License: offline Ed25519, machine/instance-bound, issued automatically via [dbmaster.tech](https://dbmaster.tech)

---

## 🤝 Contributing

- See [`AGENTS.md`](AGENTS.md) for workspace conventions (cross-component contracts, `CHANGE:` markers, safety rules)
- Feature specs live in [`specs/`](specs/) (spec-driven development)
- Issue templates: [bug report](.github/ISSUE_TEMPLATE/bug_report.md) / [feature request](.github/ISSUE_TEMPLATE/feature_request.md)

---

## Status legend

- ✅ Shipped — in a tagged commit / release
- 🚧 In progress — actively being worked on
- 📋 Planned — spec'd or next up, not started
- 💤 Deferred — intentionally postponed (see linked task / spec for why)

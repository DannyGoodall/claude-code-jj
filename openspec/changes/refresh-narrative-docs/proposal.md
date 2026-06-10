## Why

The repo has shipped a large batch of capabilities since the top-level narrative
documentation was written — a new `jj-lifecycle` plugin (`jj-release`),
`jj-fleet-status`, multi-orchestrator namespacing, sparse workspace partitions,
worktree-include provisioning, the `jj-concurrent-linear` bindings
(`jj-from-linear` / `jj-linear` / `jj-burndown`), the `jj-openspec` healthcheck /
relay / pipeline / fanout surface, the `jj-absorb` no-dry-run fallback for jj
0.42, the `jj-land` colocated-cleanup + stack-restack work, `jj-pr-fixup`,
`jj-preview`, and the migration of the lifecycle skills into the new
`jj-lifecycle` plugin. The narrative docs predate much of this and have drifted
out of agreement with the canonical specs, the live `SKILL.md` files, and the
current marketplace/plugin layout. Drift in the docs that teach the system is a
correctness problem, not a cosmetic one.

## What Changes

This is a documentation-only, **audit-then-rewrite** change. It produces in-place
edits to the existing narrative docs — **not** a separate report artifact.

- **Audit** each in-scope doc against the current source of truth (canonical
  capability specs, live `SKILL.md` files and plugin manifests, the marketplace
  manifest, and the `jj-concurrent` hooks), recording a precise per-doc delta:
  missing capabilities, renamed / moved / retired skills, outdated command
  lists, superseded architecture claims, dead cross-references, and wrong plugin
  layout.
- **Rewrite** each stale doc *in place* so it reflects current reality. A doc the
  audit finds already accurate is recorded as a no-op (verified, not
  force-rewritten) — per-doc independence is explicit.
- In scope (eight docs): `DESIGN.md`, `JJ_OVERVIEW.md`, `MANUAL.md`,
  `ROADMAP.md`, `README.md` (refreshed in PR #48 — expect minimal residual
  edits), `docs/case-studies/fleet-fanout-2026-06-09.md`,
  `docs/case-studies/linkstack-walkthrough.md` (expected current — verify only,
  likely no-op), and `docs/case-studies/openspec-pipeline-fanout-2026-06-09.md`.
- A final **cross-consistency** pass verifies the docs agree with each other and
  with `marketplace.json` / the plugin manifests / the live skill descriptions
  (plugin names, skill counts, command lists all consistent).
- **No** behavioral, code, or capability-spec changes. No existing `jj-*`
  capability spec is touched.

## Capabilities

### New Capabilities

- `narrative-docs-maintenance`: the requirement that the repo's top-level
  narrative documentation stay accurate against the canonical specs, the live
  `SKILL.md` files and plugin manifests, and the marketplace layout — and the
  audit-then-rewrite, per-doc-independent process by which that accuracy is
  established and maintained.

### Modified Capabilities

<!-- None. This change touches no behavioral capability; it adds only the
     documentation-accuracy requirement above. No `## MODIFIED` / `## REMOVED`
     deltas to any existing jj-* capability spec. -->

## Impact

- **Edited (when applied):** the eight in-scope narrative/documentation files
  listed above. Only docs the audit flags as drifted are rewritten; accurate
  docs are recorded as verified no-ops.
- **Not touched:** any `plugins/**` `SKILL.md` or `plugin.json`,
  `.claude-plugin/marketplace.json`, `openspec/specs/**` (these are the *source
  of truth* the docs are reconciled against, never edited here), the
  `jj-concurrent` hooks, and all source / behavior.
- **Dependencies:** none new. The audit reads existing specs, SKILLs, manifests,
  and hooks; the optional `graphify-out/` knowledge graph may be used as a
  grounding aid for the audit checklist only.

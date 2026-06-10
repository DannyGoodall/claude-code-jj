## Context

The narrative docs (`DESIGN.md`, `JJ_OVERVIEW.md`, `MANUAL.md`, `ROADMAP.md`,
`README.md`, and the `docs/case-studies/*` set) teach and describe the
claude-code-jj plugin family. Since several of them were written, the repo has
shipped a large batch of capabilities: a fourth plugin (`jj-lifecycle`, with
`jj-release`), `jj-fleet-status`, multi-orchestrator namespacing (per-session
manifests + name prefixes + stale sweep), sparse workspace partitions,
worktree-include provisioning, the `jj-concurrent-linear` bindings
(`jj-from-linear` / `jj-linear` / `jj-burndown`), the `jj-openspec` healthcheck /
relay / pipeline / fanout surface, the `jj-absorb` no-dry-run fallback (jj 0.42),
`jj-land` colocated-cleanup + stack-restack, `jj-pr-fixup`, and `jj-preview`.

The current repository reality at authoring time: four plugins
(`jj-concurrent`, `jj-concurrent-openspec`, `jj-concurrent-linear`,
`jj-lifecycle`); the `jj-concurrent` plugin carries eleven skills (`jj-absorb`,
`jj-checkpoint`, `jj-delegate`, `jj-fleet`, `jj-keep-current`, `jj-land`,
`jj-pr`, `jj-pr-fixup`, `jj-preview`, `jj-rewind`, `jj-stacked-pr`),
`jj-concurrent-openspec` one (`jj-openspec`), `jj-concurrent-linear` three
(`jj-burndown`, `jj-from-linear`, `jj-linear`), and `jj-lifecycle` one
(`jj-release`); the canonical specs live under `openspec/specs/`.

This is a documentation-maintenance change: it adds a documentation-accuracy
requirement and performs the audit-then-rewrite the requirement demands. It is
explicitly *not* a behavioral change.

## Goals / Non-Goals

**Goals:**

- Reconcile each in-scope narrative doc to the current source of truth and
  rewrite the stale ones in place.
- Establish and record a clear source-of-truth precedence so future doc audits
  are deterministic.
- Treat each doc independently: an accurate doc is verified, not rewritten.
- Leave the docs mutually consistent and consistent with the manifests.

**Non-Goals:**

- No behavioral, code, or capability-spec changes; no edits to any
  `plugins/**` `SKILL.md` / `plugin.json`, to `marketplace.json`, to
  `openspec/specs/**`, or to the hooks.
- No new docs and no separate report artifact — the deliverable is in-place edits
  to the eight existing docs.
- No `## MODIFIED` / `## REMOVED` deltas to any existing `jj-*` capability spec.

## Decisions

**Decision 1 — Source-of-truth precedence.** The audit reconciles docs against,
in order: (1) `openspec/specs/*/spec.md` (canonical capability specs); (2) the
live `SKILL.md` files under `plugins/*/skills/` and the plugin manifests
`plugins/*/.claude-plugin/plugin.json`; (3) `.claude-plugin/marketplace.json`
(current plugin/marketplace layout); (4) the hooks under
`plugins/jj-concurrent/hooks/`. Older or archived change proposals are NOT a
source of truth; where they disagree with the live artifacts, the live artifacts
win. *Alternative considered:* treating archived change proposals as authoritative
history — rejected, because they describe intended state at proposal time, not
the shipped reality, and are exactly what caused the drift.

**Decision 2 — Per-doc independence.** Each doc is audited and rewritten on its
own. A doc the audit finds accurate is recorded as a verified no-op and left
byte-for-byte unchanged; it is never force-rewritten to "match a house style."
This keeps the diff minimal, reviewable, and attributable per doc. *Alternative
considered:* a uniform rewrite of all eight for consistency — rejected as
needlessly noisy and risky (it would touch `README.md`, refreshed in PR #48, and
the `linkstack-walkthrough.md`, both expected current).

**Decision 3 — Documentation-only scope.** The change edits only the in-scope
docs. If the audit ever finds an authoritative artifact itself wrong, that is
recorded for a separate behavioral change; the doc is still made to match the
current (authoritative) artifact, not the other way around.

**Decision 4 — What counts as a "delta."** A delta is a concrete divergence
between a doc claim and the current authoritative reality — e.g. a missing
capability, a renamed/moved/retired skill, an outdated command or skill list, a
superseded architecture claim, a dead cross-reference, or a wrong plugin layout
(wrong plugin name, wrong skill count, wrong skill-to-plugin assignment). A
stylistic preference is *not* a delta. Each delta is recorded against the
specific doc and the specific authoritative source that contradicts it, so the
rewrite is justified and the audit is auditable.

**Decision 5 — Graphify as an optional grounding aid.** The `graphify-out/`
knowledge graph (`GRAPH_REPORT.md` + `graph.json`, with god nodes and community
clusters of the capability families) MAY be used to build the audit's "what
should the docs describe" checklist — a fast index of the current capability
families. It is a convenience only: the live specs / SKILLs / manifests remain
authoritative over the graph, which is a derived snapshot.

**Decision 6 — Case studies are point-in-time records (resolves Open Question
2, and Open Question 1 for `linkstack-walkthrough.md`).** All three case studies
(`fleet-fanout-2026-06-09.md`, `linkstack-walkthrough.md`,
`openspec-pipeline-fanout-2026-06-09.md`) are a record of the commands the user
**actually ran at that time**. The audit MUST NOT retroactively add capabilities
or commands that did not exist or were not used then — newer commands genuinely
weren't part of that session, and adding them would rewrite history. The only
permitted edit to a case study is correcting a command / skill / plugin
reference the doc **actually shows** that has since been **renamed, moved to a
different plugin, or retired**, so the recorded command no longer names the same
thing today. Absent such a shown-and-since-changed reference, a case study is a
verified no-op. (Open Question 1 for `README.md` is unaffected: README is not a
case study and keeps its normal audit-for-residual-gaps treatment.)

## Risks / Trade-offs

- **The graph is itself a snapshot and can lag reality** → use it only as a
  checklist index; verify every candidate delta against the live spec/SKILL/
  manifest before acting on it.
- **Over-rewriting an already-accurate doc inflates the diff and risks
  regressions** → Decision 2 (per-doc independence; verified no-op) plus a
  recorded audit result per doc.
- **The audit silently misses a capability the docs should mention** → ground the
  checklist in both the spec directory listing and the live skill inventory (and
  optionally the graph's community clusters), then close with the
  cross-consistency pass (Requirement: cross-consistency) that compares stated
  plugin names / skill counts / command lists against the manifests.
- **Scope creep into behavioral fixes** → Decision 3 hard-stops at the doc
  boundary; any authoritative-artifact bug is recorded, not fixed here.

## Migration Plan

Not applicable — documentation-only. No deploy, no rollback surface; the change
is reverted by reverting the doc edits.

## Open Questions

- **RESOLVED (Decision 6):** the three case studies — `linkstack-walkthrough.md`
  plus the two dated ones (`fleet-fanout-2026-06-09.md`,
  `openspec-pipeline-fanout-2026-06-09.md`) — are point-in-time records. They are
  edited ONLY to correct a command/skill/plugin reference they actually show that
  has since been renamed/moved/retired; newer capabilities are never added
  retroactively. Default outcome: verified no-op.
- `README.md` (PR #48) keeps its normal audit-for-residual-gaps treatment
  (Decision 2 / Group 5); expected to be minimal edits, but it is not held to the
  case-study no-retrofit rule since it documents current state, not a past run.

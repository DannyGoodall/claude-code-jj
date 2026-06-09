## 1. Capability home & packaging

- [x] 1.1 Confirm `jj-concurrent-linear` exists as a marketplace plugin (or rely on the in-flight `jj-concurrent-linear` change to add it); add the `jj-linear-reconcile` capability inside that plugin's tree without making it depend on `jj-linear-sync` being canonical.
- [x] 1.2 Author/extend the binding skill `plugins/jj-concurrent-linear/skills/jj-linear/SKILL.md` (or a reconcile-tail extension) with frontmatter declaring the `jj-concurrent` + Linear-MCP requirement; document that it owns no jj/workspace choreography and does not modify the worker report format.
- [x] 1.3 Document the absent-when-disabled behaviour: with the plugin disabled, no umbrella summary and no human-gate sub-issue are produced and reconcile is identical to bare `jj-concurrent`.

## 2. Inputs & manifest resolution

- [x] 2.1 Specify reading the worker's structured JSON report (`workspace`, `changes`, `tests_run`, `blocked_on`, `conflicts_seen`, `notes`) at reconcile — read-only, no new report fields.
- [x] 2.2 Specify consuming the `jj-openspec-binding` reconcile-tail outputs: the verify outcome (pass/fail) and the PR link / integrated change-ids.
- [x] 2.3 Resolve the umbrella issue id from the agent-plan manifest by the reporting worker's `workspace` path; refuse any fallback when no umbrella is recorded (skip + note).

## 3. Structured umbrella summary

- [x] 3.1 Compose the four-section summary (What changed / Root cause / Test results / PR link) mapping each section to its documented source per the design table.
- [x] 3.2 Render any section with no source data as an explicit "none reported"; never fabricate content.
- [x] 3.3 Post the summary as a single comment to the resolved umbrella issue via the Linear MCP.
- [x] 3.4 Add the idempotency guard: on reconcile retry, do not post a byte-identical summary again (guard on the last summary comment for that worker).

## 4. Auto human-gate sub-issue

- [x] 4.1 Define the human-gate trigger: fire only when the report or verify outcome carries a manual/visual-verification signal that automated verify cannot cover; do NOT fire on a fully-automated clean finish.
- [x] 4.2 Ensure a blocker or conflict alone does NOT create a `ready-for-human` sub-issue (it surfaces in the summary's Root-cause section instead).
- [x] 4.3 On trigger, create a Linear sub-issue under the umbrella labelled `ready-for-human`, with a body stating what to verify, why automated verify cannot cover it, and where to look (PR link / route / screenshot target).
- [x] 4.4 Reference in the summary comment that a human-gate sub-issue was raised.

## 5. Failure & edge handling

- [x] 5.1 Treat every Linear call (summary comment, sub-issue create) as best-effort: on MCP unavailable or call failure, skip and surface a non-fatal note in the reconcile report; never block integration or teardown.
- [x] 5.2 Skip-and-note when no umbrella is recorded for the reporting worker; never post to an unrelated issue as a fallback.
- [x] 5.3 Ensure a stalled / no-report worker (resume-in-place) produces no umbrella summary and no human-gate sub-issue until a successor reports.
- [x] 5.4 Handle a missing `ready-for-human` label per the chosen policy (default: require pre-existing label; skip + note if absent).

## 6. Documentation

- [x] 6.1 Document the section→source mapping table and the human-gate trigger as the single source of truth in the skill.
- [x] 6.2 Note the relationship to the in-flight `jj-linear-sync` capability (status sub-issue transitions / blocker comments) and the explicit non-goals (no umbrella/status sub-issue creation here, no PR cross-linking beyond pasting the link).

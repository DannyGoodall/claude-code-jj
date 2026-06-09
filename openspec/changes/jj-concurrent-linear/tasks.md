## 1. Plugin scaffolding & packaging

- [ ] 1.1 Add `jj-concurrent-linear` as a third entry in `.claude-plugin/marketplace.json` (source `./plugins/jj-concurrent-linear`), with a description mirroring `jj-concurrent-openspec`: separate binding, requires `jj-concurrent` + the Linear MCP, enable only in Linear-tracked repos.
- [ ] 1.2 Create the `plugins/jj-concurrent-linear/` tree (skills/ at minimum) following the layout convention of `plugins/jj-concurrent-openspec/`.
- [ ] 1.3 Author the binding skill `plugins/jj-concurrent-linear/skills/jj-linear/SKILL.md` with frontmatter declaring the `jj-concurrent` + Linear-MCP requirement and triggers; document that it owns no jj/workspace choreography and no report-format ownership.

## 2. Dispatch-side ID threading

- [ ] 2.1 Specify, in the skill, how at dispatch the orchestrator records `{ workspacePath → { umbrellaId, subIssueId } }` in the agent-plan manifest for each provisioned worker.
- [ ] 2.2 Document that the worker brief and the worker's JSON report carry NO Linear identifier (worker stays Linear-agnostic).

## 3. Reconcile-side report → Linear mapping

- [ ] 3.1 Implement the reconcile-tail lookup: resolve the sub-issue ID from the manifest by the reporting worker's `workspace` path.
- [ ] 3.2 Implement the clean-finish transition (in-progress → done) when `blocked_on` and `conflicts_seen` are both null, guarded to be idempotent (state-check before transition).
- [ ] 3.3 Implement the blocker comment: when `blocked_on` is non-null, post a comment with the blocker text and do NOT transition to done.
- [ ] 3.4 Implement the conflict comment: when `conflicts_seen` is non-null, post a comment describing the conflict and do NOT transition to done.
- [ ] 3.5 Optionally fold `tests_run` / `changes` / `notes` into the done/blocker comment as context, ensuring they never by themselves drive a state change.

## 4. Failure & edge handling

- [ ] 4.1 Skip-and-note when the Linear MCP is unavailable; ensure workspace integration/teardown proceeds unaffected.
- [ ] 4.2 Skip-and-note when no sub-issue is recorded for the reporting worker; never fall back to the umbrella or a sibling sub-issue.
- [ ] 4.3 Ensure a stalled / no-report worker (resume-in-place) leaves its sub-issue untouched until a successor reports.
- [ ] 4.4 Add a last-comment guard so a reconcile retry does not post a byte-identical blocker comment twice.

## 5. Documentation

- [ ] 5.1 Document the report-field → Linear-update mapping table in the skill (single source of truth).
- [ ] 5.2 Note the relationship to the existing `linear-github-sync` convention (umbrella + sub-issue per change) and the explicit non-goals (no issue creation, no PR cross-linking).

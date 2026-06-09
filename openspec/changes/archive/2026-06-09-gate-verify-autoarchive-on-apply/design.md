## Context

The `jj-concurrent-openspec` plugin's `jj-openspec` skill maps an OpenSpec verb to a **shape** and coordinates a reconcile tail in the primary (orchestrator) workspace. For `apply`, the implementing shape integrates the worker's change and then — per the current `jj-openspec-binding` spec — "verifies, integrates, and pushes/opens a PR". In practice verify is advisory: its result does not gate trunk-advance or PR, and nothing archives the change afterward, so the OpenSpec lifecycle (`openspec/changes/<change>` → sync deltas to `openspec/specs/` → move to `archive/`) stays open after even a clean apply.

Two facts make a verify GATE the right design here. First, the role split (`jj-delegate` / `jj-workspace-worker`): only the orchestrator pushes, mutates refs, and advances trunk — so the orchestrator is exactly where a gate belongs, and workers need no new capability. Second, jj integration never halts and is cheap (conflicts are first-class objects), so integrating a worker's change is NOT the meaningful checkpoint — *correctness against the artifacts* is. Verify already produces that judgement; the only change is to let it decide trunk-advance/PR rather than merely annotate them, and to let a green result close the lifecycle via `/opsx:archive`.

## Goals / Non-Goals

**Goals:**
- Make `/opsx:verify` a hard gate on trunk-advance and PR in the implementing reconcile tail: green ⇒ proceed; non-green ⇒ stop before any trunk/ref mutation and report.
- On green, automatically run `/opsx:archive <change>` so a successful apply syncs delta specs into canonical and moves the change to `archive/` with no human follow-up.
- Run the gate and auto-archive exactly once over the fully reconciled change branch, independent of how many workers produced it.
- Keep the orchestrator/worker role split intact: the gate, the conditional push/PR, and the archive all run in the primary workspace.

**Non-Goals:**
- No change to `/opsx:verify` or `/opsx:archive` internals — the binding owns only WHEN they run and what gates on their outcome.
- No gate or archive for the authoring shapes (`propose`/`new`/`ff`) or `explore`; they remain validate-and-surface, no verify, no merge.
- No new jj/workspace primitives, hooks, or worker-contract changes.
- No partial / per-group archiving — archive runs once on the whole change, only after a green verify over the reconciled branch.

## Decisions

**Decision: Verify is a GATE in the orchestrator's reconcile tail, not in the worker.**
After integrating all worker commits into the one change branch, the orchestrator runs `/opsx:verify <change>` and branches on its result: green ⇒ continue the tail; non-green ⇒ halt the tail before trunk-advance / push / PR. Rationale: only the orchestrator can advance trunk and push (role split), so the gate must live there; the worker contract is untouched. Alternative considered: have the worker self-verify and refuse to report — rejected because verify must run over the *reconciled* branch (which may combine several workers), not any single worker's partial result, and because workers never own integration.

**Decision: Non-green verify stops the reconcile cleanly with no mutation, leaving the integrated change in place for inspection.**
On failure/inconclusive, the orchestrator performs no trunk-advance, no `jj git push`, and opens no PR; the integrated (but un-pushed) change remains so a human or a follow-up apply can inspect and fix it. The failure is surfaced as data (which scenarios/tasks verify flagged). Rationale: never push a change that does not satisfy its own artifacts; jj makes holding an un-integrated-to-trunk change trivial and lossless. Alternative considered: open a draft PR on failure — deferred; v1 keeps the gate strict and silent on refs.

**Decision: A green verify triggers `/opsx:archive` BEFORE push/PR.**
On green, the orchestrator runs `/opsx:archive <change>` — sync delta specs into `openspec/specs/` and move `openspec/changes/<change>` to `openspec/changes/archive/` — and the resulting canonical-spec + archive moves are part of the same change branch that advances to trunk / the PR. Rationale: the PR/trunk state should reflect the *closed* lifecycle (updated canonical specs, archived change), not a half-open one; doing archive before push means a human reviews/merges the final, lifecycle-complete result in one shot. Alternative considered: archive AFTER merge to trunk — rejected because that reintroduces a manual/automated second step decoupled from the apply, exactly the toil this change removes.

**Decision: Gate + auto-archive run once over the reconciled branch, distribution-agnostic.**
Whether the change was implemented by one worker or fanned out across several (per `jj-openspec-fanout`), the tail integrates everything into one change branch first, THEN gates and archives once. Rationale: preserves the existing "tail runs once over the reconciled change" invariant and keeps verify judging the whole, combined result.

## Risks / Trade-offs

- [Flaky/inconclusive verify blocks a correct change] → the gate treats only an unambiguous green as pass; a flaky verify stops the tail (fail-safe toward NOT pushing) and reports, so a human can re-run rather than a bad change slipping through. Trade parallelism/speed for correctness deliberately.
- [Auto-archive on green is destructive to `openspec/changes/<change>` (moves the dir)] → it runs only after a green verify and only in the orchestrator workspace, and it is the standard `/opsx:archive` operation (move + sync), captured on the same change branch under jj so it is fully reversible via `jj op restore`. No data loss risk beyond what `/opsx:archive` already entails.
- [Archive sync conflicts with canonical specs already edited on trunk] → archive's delta-sync runs on the reconciled change branch before push; any conflict surfaces as a first-class jj conflict the orchestrator resolves by editing markers (never interactive `jj resolve`), consistent with the existing integration contract.
- [Behaviour change for callers expecting a PR even on failing verify] → documented as an intentional tightening; the unhappy path now stops-and-reports instead of pushing a non-conforming change. Callers who want the old advisory behaviour are out of scope for v1.

## Migration Plan

Behaviour-only change to the `apply` reconcile tail; no data migration, no new artifacts in target repos. Existing `/jj-openspec apply <change>` calls keep the same happy path shape (integrate → verify → push/PR) but now ALSO archive on green and STOP on non-green. Rollback is reverting the gate (verify back to advisory) and removing the auto-archive step, restoring "always push/PR after verify"; nothing else depends on the new behaviour.

## Open Questions

- On non-green verify, should the orchestrator optionally open a DRAFT PR (with the failure summary) instead of holding the change entirely un-pushed? v1 holds; a draft-on-failure mode is a possible later policy knob.
- Should `/opsx:verify` expose a machine-readable pass/fail/inconclusive result the binding consumes, rather than the binding parsing its output? A structured result would harden the gate; out of scope here, noted for a follow-up opsx change.
- Should auto-archive be suppressible per-invocation (e.g. `/jj-openspec apply <change> --no-archive`) for cases where a human wants to review canonical-spec sync separately? Defaulting to archive-on-green; an opt-out flag is a candidate refinement.

## Why

In the `apply` → implementing reconcile tail today, `/opsx:verify` is advisory: the tail integrates the worker's change, runs verify for information, and then advances trunk and opens a PR regardless of what verify reported. So a change whose implementation does not match its own artifacts can still reach trunk/PR, and the OpenSpec lifecycle never closes on its own — the change sits un-archived in `openspec/changes/` even after a clean, verified implementation, leaving delta specs un-synced to canonical and a stale directory for a human to clean up later.

That is backwards for an automated, lock-free apply pipeline. jj makes integration cheap and never-halting, so the expensive, meaningful gate is *correctness* (does the implementation satisfy the artifacts), not integration. Verify should decide whether the change is allowed onto trunk, and a green verify should immediately complete the lifecycle by archiving — syncing delta specs into canonical and moving the change to `archive/` — so a successful apply leaves no manual follow-up.

## What Changes

- Make `/opsx:verify` a **gate** in the implementing reconcile tail: trunk-advance and PR are now CONDITIONAL on verify passing. The tail integrates the worker's change, then runs `/opsx:verify <change>`; only a green verify proceeds to advance trunk / open a PR.
- On a **failing/inconclusive** verify, the tail STOPS the reconcile before trunk-advance and PR: the integrated change is held (not pushed, no PR), and the failure is reported as data for the orchestrator/human. No trunk mutation, no ref mutation.
- On a **green** verify, the tail automatically runs `/opsx:archive <change>`: it syncs the change's delta specs into the canonical `openspec/specs/` and moves the change directory to `openspec/changes/archive/`, so the OpenSpec lifecycle closes itself as part of a successful apply.
- The verify gate and the auto-archive-on-green step run ONCE over the reconciled change branch, after all worker commits are integrated (preserving the existing "tail runs once over the reconciled change" property regardless of single-worker or fan-out distribution).
- No change to the authoring shapes (`propose`/`new`/`ff`) or `explore`: they still validate-and-surface with no verify and no merge. The gate and auto-archive apply only to the `apply` → implementing shape.

## Capabilities

### Modified Capabilities
- `jj-openspec-binding`: the `apply` → implementing reconcile tail changes from "integrate → verify (advisory) → push/PR" to "integrate → verify (GATE) → on green: archive then push/PR; on non-green: stop before trunk-advance/PR and report". Verify gates trunk-advance and PR; a green verify triggers an automatic `/opsx:archive` (sync delta specs → canonical + move change to `archive/`).

## Impact

- Affects the `jj-concurrent-openspec` plugin (`jj-openspec` skill) only; it changes the reconcile-tail policy the binding hands to / coordinates with `jj-delegate`. No new jj/workspace primitives.
- The orchestrator (primary workspace) owns the gate decision, the conditional trunk-advance / `jj git push` / PR, and the auto-archive step, consistent with the role split: workers never push, verify, or archive.
- Invokes the existing `/opsx:verify` and `/opsx:archive` skills unchanged; the binding owns only WHEN they run and what gates on their result, not their internal rules.
- Tightens the apply contract: a change that fails verify no longer reaches trunk/PR. This is a deliberate, non-breaking-for-callers behaviour change (the happy path — green verify — additionally archives; the unhappy path now stops instead of pushing a non-conforming change).
- Removes manual post-apply archive toil: a successful `/jj-openspec apply <change>` leaves canonical specs updated and the change moved to `archive/` with no human follow-up.

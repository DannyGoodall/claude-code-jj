## Why

A jj stack that was green when it was pushed goes stale the moment trunk moves: its PR may merge dirty, fail CI against the new base, or land code that was only ever tested against an old trunk. jj makes the fix cheap — `jj rebase` never halts and records conflicts as first-class objects rather than dropping the operator into a halted rebase — but nothing in the plugin yet *automates* "detect trunk moved → fetch → rebase the stack → push → re-check CI", nor gates landing behind a green required-checks signal. Without this, the in-flight `/jj-land` (D4) step would either land a stale-but-green PR or block on a manual rebase dance.

## What Changes

- A new orchestrator skill **`/jj-keep-current`** that, given a stack (its tip bookmark, or the current stack), brings it up to date with trunk and reports whether it is safe to land:
  - **CI gate**: query the PR's required checks via `gh pr checks <ref> --required` (falling back to all checks when none are marked required). Landing is **blocked unless the gate is green**; pending checks hold, failing checks block, missing checks (no CI configured) are reported explicitly rather than treated as green.
  - **Trunk-movement detection**: `jj git fetch` the trunk bookmark, then compare the stack's base against the freshly-fetched trunk tip. If trunk has not moved, the rebase step is skipped (no-op fast path).
  - **Never-halt auto-rebase**: when trunk has moved, `jj rebase -b <stack> -d <new-trunk>`. The rebase always succeeds (exit 0); any conflict is surfaced as a first-class conflicted change. A conflicted result **blocks land** and is reported with the conflicted change-ids and paths — the skill never silently resolves and never invokes interactive `jj resolve`.
  - **Push the updated stack**: after a clean (conflict-free) rebase, push the moved bookmark(s) so the PR rebuilds against the new trunk.
  - **Re-check loop**: after pushing, re-run the CI gate against the new head, with a bounded poll (configurable interval + max attempts) for checks that are still pending, so a freshly-triggered CI run is given time to report before the gate verdict is returned.
- **Composition with `/jj-land` (D4, in-flight)**: `/jj-keep-current` is authored as the standalone "is this stack current and green?" precondition that a land flow consults. It defines a clear verdict contract (current + green ⇒ landable; moved/conflicted/red/pending ⇒ not landable, with reason) **without depending on `/jj-land` existing**; if D4 lands, its skill calls this one, but this capability stands alone and is independently testable.
- Stays inside the orchestrator role contract: fetch, rebase, push, and PR/CI queries are orchestrator-only operations; this skill is never run by a worker.

## Capabilities

### New Capabilities
- `jj-keep-current`: the `/jj-keep-current` orchestrator skill — gate landing behind green required CI, detect trunk movement via `jj git fetch`, auto-rebase the stack onto the new trunk with jj's never-halt semantics (conflicts surfaced as first-class objects, never silently resolved), push the updated stack, and run a bounded re-check loop, emitting a single landable / not-landable verdict with a reason.

### Modified Capabilities
<!-- None. This capability *references* jj-delegate's "Integration never halts" requirement as the inherited invariant its rebase relies on, but it does not change any jj-delegate requirement — the reference is one-directional. /jj-land (D4) is in-flight and not canonical, so no existing capability's requirements change here. -->

## Impact

- New skill `plugins/jj-concurrent/skills/jj-keep-current/SKILL.md` (or equivalent) in the **core `jj-concurrent` plugin**; bumps that plugin's version. No new plugin.
- Hard dependency on the `gh` GitHub CLI (authenticated) for PR/CI status and on a colocated jj↔git repo with an `origin` remote and a known trunk bookmark.
- Inherits — does not modify — the `jj-delegate` "Integration never halts" invariant: the rebase here uses the same first-class-conflict semantics.
- Forward-composes with the in-flight `/jj-land` (D4): land consults this skill's verdict. No hard dependency in either direction; this change is mergeable and testable before D4.
- No changes to any target project's application code — this orchestrates fetch/rebase/push and reads CI; it ships no application behaviour.

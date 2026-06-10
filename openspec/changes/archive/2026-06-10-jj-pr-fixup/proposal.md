## Why

When a GitHub PR comes back with review comments, the fixes belong in the original commits, not in a new "address review" commit dangling on top — a reviewer asking to rename a symbol in commit B wants commit B amended, not a fixup commit at HEAD. In a Graphite-style git flow this was the amend-after-review loop done by hand. The jj-concurrent plugin now has the pieces — a worker dispatch mechanism (`jj-delegate`), a hunk-absorbing step (`/jj-absorb`, A4 in-flight), and a push-and-PR step (`/jj-pr`, D1 in-flight) — but nothing that wires them into a single command that reads a PR's review comments, fixes them in a workspace based on the PR head, lands each fix into the commit it belongs to, and re-pushes to update the PR. This change supplies that automated amend-after-review loop.

## What Changes

- A new orchestrator skill **`/jj-pr-fixup`** that, given a PR number/URL, reads that PR's review comments via `gh`, dispatches a worker to address them in a workspace based on the PR head, absorbs the resulting fixes into the right downstack commits, and re-pushes to update the PR — the automated amend-after-review loop.
- **Review comments → worker brief**: the skill SHALL fetch the PR's review comments (review threads, file/line-anchored comments, and the review summary) via `gh` and compose them into a single worker brief that names the workspace path, the base revision (the PR head), and the concrete review items the worker must address — file/line context preserved so the worker can locate each comment. Resolved/outdated threads SHALL be excluded.
- **Worker based on the PR head**: provisioning SHALL base the worker on the revision that is the PR head (`jj workspace add -r <pr-head-rev> <path>`), so the worker's fixes apply on top of exactly the commits under review, per the `jj-delegate` explicit-base-revision rule. The skill SHALL resolve the PR head branch to a local jj revision before provisioning.
- **Absorb fixes into the right commits**: after the worker reports, the orchestrator SHALL land the worker's working-copy fixes into their owning downstack commits via the `/jj-absorb` step (jj's `jj absorb`), so each fix lands in the commit a reviewer was commenting on rather than as a new tip commit. Any hunk with no unambiguous downstack home SHALL be surfaced (per `/jj-absorb`'s remainder handling), not force-fitted.
- **Update the PR after the fixup**: once fixes are absorbed, the orchestrator SHALL re-push and update the PR via the `/jj-pr` push-and-PR step, so the existing PR is updated in place (not duplicated) with the amended commits.
- **Orchestrator-role contract**: `/jj-pr-fixup` is an orchestrator skill — it owns workspace lifecycle, absorb, refs, and push; the dispatched worker only addresses comments inside its workspace and SHALL NOT touch bookmarks or push, per the `jj-delegate` role split. Every command runs non-interactively.
- **Composition, not duplication**: the absorb step and the push-and-PR step are delegated to the `/jj-absorb` and `/jj-pr` skills respectively (referenced conceptually); this change defines only the PR-comment → brief mapping, the PR-head basing, and the orchestration that strings the pieces together.

## Capabilities

### New Capabilities
- `jj-pr-fixup`: the `/jj-pr-fixup` orchestrator skill — read a GitHub PR's review comments via `gh`, compose them into a worker brief, dispatch a worker on a workspace based on the PR head, absorb the worker's fixes into their owning downstack commits, and re-push to update the same PR, all non-interactively and within the orchestrator role.

### Modified Capabilities
<!-- None. This capability composes with jj-absorb-fixup (A4) and jj-github-pr (D1), which are in-flight and not yet in openspec/specs/, and it references jj-delegate's worker-dispatch requirements without changing them. All references are one-directional (this capability points at them), so no delta spec is required. -->

## Impact

- New skill `plugins/jj-concurrent/skills/jj-pr-fixup/SKILL.md` (or equivalent) in the **core `jj-concurrent` plugin**; bumps that plugin's version. No new plugin.
- Hard dependency on the `gh` GitHub CLI (authenticated, with PR-comment read scope) and on a colocated jj↔git repo with an `origin` remote and the PR's head branch fetchable locally.
- Composition dependency (conceptual, at runtime) on the `/jj-absorb` skill (capability `jj-absorb-fixup`, A4) for landing fixes and the `/jj-pr` skill (capability `jj-github-pr`, D1) for the push-and-PR step; it dispatches workers via the `jj-delegate` mechanism. These are referenced, not re-specified.
- No changes to any target project's application code — this orchestrates the orchestrator's own commit stack against an existing PR, it ships no application behaviour.

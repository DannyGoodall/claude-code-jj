## Why

A jj stack of GitHub PRs has no native "merge the whole stack" verb — `gh pr merge` merges one PR at a time, leaves higher PRs pointing at a now-gone base branch, and never syncs the local trunk or cleans up the merged bookmarks and stale workspaces. This was Graphite's `gt merge`: one command that lands a stack bottom-up, waits for CI at each step, restacks the rest, and tidies up. Without it the orchestrator's reconcile tail dead-ends at a pile of open, correctly-stacked PRs that a human must then merge one-by-one in the right order, retargeting bases by hand.

## What Changes

- A new orchestrator skill **`/jj-land`** that, given a jj stack whose changes already have open GitHub PRs, lands the stack **bottom-up**: it derives the merge order from the jj stack (trunk-adjacent change first), and for each PR in turn waits for required CI checks, merges it, retargets the next PR's base, and continues up the stack.
- **Bottom-up merge order from the jj stack**: the skill computes the linear order of changes from trunk upward (via a jj revset over the stack) and merges in exactly that order; it SHALL refuse to merge an upper PR before every PR beneath it has merged.
- **Per-step CI wait**: before merging each PR the skill polls its GitHub checks (`gh pr checks` / `gh pr view`) until required checks pass; on a red check or a wait-timeout it aborts the remaining stack cleanly, leaving merged-so-far PRs merged and the rest open, and reports which step stopped it. No force-merge, no admin-merge override.
- **Base retargeting as lower PRs merge**: after a lower PR merges (and its head branch is deleted/absorbed into trunk), the skill retargets the next-up PR's base to trunk (or to the next surviving lower branch) via `gh pr edit --base`, so each PR is reviewed/merged against the correct base rather than a vanished branch.
- **Post-merge cleanup**: once the stack has landed (or the run stops), the skill runs `jj git fetch` to sync the local trunk with the merged commits, deletes the merged bookmarks locally, and forgets any now-stale linked workspaces — deferring the actual workspace-forget mechanics to the `jj-delegate` Teardown requirement rather than re-implementing them.
- Strictly **orchestrator-role only** (the role that owns refs, bookmarks, push, and fetch); `/jj-land` is never invoked inside a worker. Non-interactive throughout (`jj … --no-pager`, `gh` with explicit flags), and it performs **no force operations**.
- **Composition, not dependency**: `/jj-land` is designed to consume the output of the stacked-PR / push-and-PR work (capability `jj-github-pr`'s `/jj-pr`) — it lands PRs that were opened that way — but it is authored as a standalone capability that does **not** require any in-flight change to be canonical; if those PRs were opened by hand it still lands them.

## Capabilities

### New Capabilities
- `jj-land`: the `/jj-land` orchestrator skill — derive bottom-up merge order from a jj stack of GitHub PRs, wait for required CI at each step, merge each PR, retarget remaining PRs' bases as lower ones land, and perform post-merge cleanup (`jj git fetch` trunk sync, delete merged bookmarks, forget stale workspaces via jj-delegate Teardown). Orchestrator-role-only, non-interactive, no force operations.

### Modified Capabilities
<!-- None. jj-land composes with jj-delegate (it defers workspace forget to that capability's existing Teardown requirement) and with jj-github-pr (it lands the PRs /jj-pr opens), but it changes no requirement of either: the references are one-directional (this capability points at them). No delta spec is required, and jj-github-pr is in-flight, so jj-land does not treat its requirements as canonical. -->

## Impact

- New skill `plugins/jj-concurrent/skills/jj-land/SKILL.md` (or equivalent) in the **core `jj-concurrent` plugin**; bumps that plugin's version. No new plugin.
- Hard dependency on the `gh` GitHub CLI (authenticated) and on a colocated jj↔git repo with an `origin` remote and a trunk branch; assumes each stacked change already has an open GitHub PR (e.g. opened by `/jj-pr`).
- Reuses the `jj-delegate` capability's Teardown requirement for the workspace-forget step rather than duplicating workspace-lifecycle logic; documentation/wiring only, no behaviour change to jj-delegate's spec.
- No changes to any target project's application code — this orchestrates merges, base retargeting, fetch, and cleanup; it ships no application behaviour.

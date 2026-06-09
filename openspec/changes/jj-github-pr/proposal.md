## Why

jj has no native "submit" — `jj git push` moves a bookmark to the remote but never opens or updates a GitHub pull request, and Graphite's `gt submit` (the workflow this plugin replaces) did both in one step. Without a `/jj-pr` skill the orchestrator's reconcile tail dead-ends at a pushed bookmark with no PR, forcing a manual `gh pr create` per change and leaving the PR body unwritten. This change supplies the missing push-and-PR step so `/jj-delegate` and `/jj-openspec apply` can finish their reconcile tail end-to-end.

## What Changes

- A new orchestrator skill **`/jj-pr`** that, given a bookmark: pushes it with `jj git push -b <bookmark>`, then **creates or updates** a GitHub PR for that bookmark via `gh` (create when none exists, update body/title when one does).
- **PR body generation**: the skill composes a what / why / benefit body plus a `Fixes <issue>` line, sourced from the bookmark's commit messages and — when present — the change's OpenSpec `proposal.md` (Why → why, What Changes → what, Impact/benefit → benefit). With no OpenSpec proposal it falls back to commit messages alone.
- **One-time tracking handling**: on a freshly colocated repo a bookmark may be untracked against the remote; the skill performs the one-time `jj bookmark track <name>@origin` (equivalently `jj bookmark track <name> --remote=origin`) when needed, so the first push and subsequent pushes both succeed.
- **Reconcile-tail integration**: `/jj-pr` is the canonical push step the `jj-delegate` reconcile tail and the `jj-openspec apply` shape call after integration, replacing ad-hoc push/PR instructions with one skill.
- The skill stays within the orchestrator role contract: it is the orchestrator (never a worker) that owns refs and push; `/jj-pr` performs exactly the ref/push/PR operations the worker is forbidden from doing.
- **Packaging decision (resolved in design)**: ship `/jj-pr` as part of core `jj-concurrent` rather than a separate `jj-concurrent-github` plugin, with the separate-plugin option recorded as a considered alternative.

## Capabilities

### New Capabilities
- `jj-github-pr`: the `/jj-pr` orchestrator skill — push a bookmark, create-or-update its GitHub PR via `gh`, generate the PR body from commits and any OpenSpec proposal, handle one-time remote tracking, and serve as the reconcile-tail push step for `jj-delegate` and the OpenSpec binding.

### Modified Capabilities
<!-- None. jj-delegate and jj-openspec-binding already describe a "push/PR" reconcile tail abstractly; this change supplies the concrete skill they reference without changing their existing requirements. The reference is one-directional (this capability points at them), so no delta spec is required. -->

## Impact

- New skill `plugins/jj-concurrent/skills/jj-pr/SKILL.md` (or equivalent) in the **core `jj-concurrent` plugin**; bumps that plugin's version. No new plugin.
- Hard dependency on the `gh` GitHub CLI (authenticated) and on a colocated jj↔git repo with an `origin` remote; soft dependency on an `openspec/` directory for richer PR bodies.
- Reconcile-tail prose in the `jj-delegate` and `jj-openspec` skills points at `/jj-pr` (documentation/wiring only, no behaviour change to their specs).
- No changes to any target project's application code — this orchestrates pushes and PRs, it ships no application behaviour.

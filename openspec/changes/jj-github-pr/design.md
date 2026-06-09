## Context

The `jj-concurrent` orchestrator's reconcile tail ends by getting a worker's change onto the remote and into review. `jj git push -b <bookmark>` moves the bookmark to `origin` but, unlike Graphite's `gt submit`, never creates or updates a GitHub PR — jj has no PR concept at all. Today that gap is filled by ad-hoc `gh pr create` instructions duplicated across the `jj-delegate` and `jj-openspec` skills, with the PR body left to the operator. This design covers a single `/jj-pr` skill that owns the push-then-PR step, sourcing a structured PR body from the change's commits and, when present, its OpenSpec proposal. It runs strictly in the orchestrator role (the role that already owns all refs and push); workers are forbidden from these operations by their contract, so `/jj-pr` never runs inside a worker.

## Goals / Non-Goals

**Goals:**
- One idempotent skill that pushes a bookmark and creates-or-updates its GitHub PR.
- A PR body assembled deterministically from commits and, when present, the OpenSpec `proposal.md` (what / why / benefit + `Fixes <issue>`).
- Transparent handling of the one-time `jj bookmark track` need on a freshly colocated repo.
- Drop-in reuse as the reconcile-tail push step for `jj-delegate` and `jj-openspec apply`.

**Non-Goals:**
- Merging, auto-merge, review assignment, or PR-status polling — the skill opens/updates a PR and stops.
- Bookmark creation or naming — the caller (orchestrator/binding) already owns the bookmark; `/jj-pr` only pushes and tracks it.
- Multi-remote / multi-forge support — `origin` + GitHub via `gh` only.
- Stacked-PR base management — the PR targets the repo's default/trunk branch unless a base is passed explicitly.
- Authoring or editing OpenSpec artifacts — it only reads `proposal.md` for body material.

## Decisions

- **Ship in core `jj-concurrent`, not a separate `jj-concurrent-github` plugin.** A pushed-but-PR-less bookmark is the universal dead-end of the *core* reconcile tail, not an OpenSpec-specific concern, so `/jj-pr` belongs beside `jj-delegate`. `gh` is the same baseline tool the worker contract already permits, adding no heavier dependency than core already assumes (colocated git for PRs). *Alternative considered:* a separate `jj-concurrent-github` plugin mirroring the `jj-concurrent-openspec` split — rejected because the OpenSpec split exists to keep OpenSpec triggers out of non-OpenSpec repos, whereas GitHub-PR support has no equivalent "wrong repo" surface (a colocated repo without GitHub simply never invokes `/jj-pr`); a separate plugin would only add an install step for a step the core tail already needs. The option is recorded so a future GitLab/Bitbucket forge could justify extracting a forge layer.
- **Push first, then PR — never assume push creates a PR.** `jj git push -b <bookmark>` is the push primitive; the `gh` call is a distinct second step. This keeps the two failure modes (push rejected vs PR API error) separable and reportable.
- **Create-or-update is detected via `gh`, keyed on the head branch.** The skill queries `gh pr list --head <bookmark> --state open` (or `gh pr view <bookmark>`); zero results → `gh pr create`, one result → `gh pr edit` (body/title). This makes re-running `/jj-pr` after follow-up commits idempotent — the canonical reconcile-tail behaviour where a worker amends and the orchestrator re-pushes.
- **PR body is generated, with a deterministic source precedence.** When `openspec/changes/<change>/proposal.md` exists, map its **Why** → *why*, **What Changes** → *what*, and **Impact**/benefit → *benefit*; otherwise fall back to the bookmark's commit messages (`jj log -r <bookmark>` description bodies). The `Fixes <issue>` line is derived from an explicit issue argument or a `Fixes #N` / issue reference already present in a commit message; when no issue is known the line is omitted rather than guessed. *Alternative considered:* always free-form from commits — rejected because the OpenSpec proposal is the richer, already-reviewed source when present.
- **One-time tracking is conditional, not unconditional.** The skill checks tracking state (e.g. `jj bookmark list --all` / a remote-tracking query) and runs `jj bookmark track <name>@origin` only when the bookmark is untracked against `origin`. Running it unconditionally on an already-tracked bookmark is at best noise and at worst an error, so it is gated.
- **Non-interactive and report-shaped.** Like the rest of the plugin: `jj … --no-pager`, `gh` with explicit flags (`--title`, `--body`/`--body-file`, `--head`, `--base`), no editor spawn. The skill returns the PR URL (and push/track outcomes) so the reconcile tail can surface it.

## Risks / Trade-offs

- **`gh` unauthenticated or absent** → the skill detects this up front (e.g. `gh auth status`) and reports a clear blocker rather than half-pushing; the push step may still have succeeded, so the report distinguishes "pushed, PR not created" from "nothing done".
- **Push rejected (non-fast-forward / diverged remote bookmark)** → reported as a push failure with the jj message; `/jj-pr` does not force-push (force is an orchestrator decision outside this skill's scope).
- **Heuristic proposal-section parsing drifts if the proposal format changes** → the mapping targets the stable `## Why` / `## What Changes` / `## Impact` headers this plugin's own proposals use; on a missing/odd header the skill degrades to commit-message body rather than failing.
- **Wrong `Fixes <issue>` would auto-close the wrong issue** → mitigated by only emitting `Fixes` from an explicit argument or an issue reference already in the commits; never inferred from branch names or free text.
- **Bookmark name ≠ GitHub head branch in exotic setups** → assumed equal (the colocated default); documented as a precondition, not auto-reconciled.

## Migration Plan

Additive: a new skill in an existing plugin. No existing behaviour changes. The `jj-delegate` and `jj-openspec` reconcile-tail prose is updated to call `/jj-pr` where it previously gave inline push/PR steps. Rollback is removing the skill file and reverting that prose; nothing persists state.

## Open Questions

- Should `/jj-pr` accept an explicit `--base` for stacked changes now, or defer until stacked-PR support is designed? (Leaning: accept an optional base argument, default to trunk, but do not manage the stack.)
- Should the PR be opened as a draft by default for agent-produced changes awaiting human review? (Leaning: optional `--draft`, default non-draft, decided by the calling reconcile tail.)

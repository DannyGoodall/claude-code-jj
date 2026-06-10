## Context

The `jj-concurrent` plugin orchestrates worker subagents in linked jj workspaces and reconciles their changes back onto the orchestrator's stack. After a PR is opened (via `/jj-pr`, capability `jj-github-pr`, D1 in-flight) a reviewer leaves comments, and the fixes those comments ask for belong in the *original* commits under review — not in a fresh "address review" commit at the tip. The plugin already has the constituent moves: `jj-delegate` provisions and dispatches workers on an explicit base revision; `/jj-absorb` (capability `jj-absorb-fixup`, A4 in-flight) distributes working-copy hunks into their owning downstack commits; `/jj-pr` pushes and updates the PR. What is missing is the conductor that reads a PR's review comments, turns them into a worker brief, bases the worker on the PR head, then composes absorb + push into the automated amend-after-review loop.

This is authoring-only: the change drafts proposal/design/specs/tasks. No skill is implemented here. The A4 and D1 changes are in-flight and NOT yet in `openspec/specs/`; this design references them conceptually and does not depend on their specs being canonical.

## Goals / Non-Goals

**Goals:**
- A `/jj-pr-fixup` orchestrator skill that, given a PR, reads its review comments via `gh` and runs the full amend-after-review loop non-interactively.
- A deterministic mapping from PR review comments (file/line-anchored threads + review summary, unresolved only) to a single worker brief.
- Worker provisioning based on the PR head revision so fixes apply on top of exactly the commits under review.
- Composition of the existing `/jj-absorb` (land fixes) and `/jj-pr` (push-and-update) steps rather than reimplementing them.

**Non-Goals:**
- No reimplementation of absorb or push/PR logic — those are delegated to `/jj-absorb` and `/jj-pr`. This skill defines only comment→brief mapping, PR-head basing, and the orchestration.
- No worker-side ref/push/bookmark behaviour — the worker only addresses comments inside its workspace, per the `jj-delegate` role split.
- No posting of replies to review threads or marking them resolved on GitHub (a possible later extension; out of scope here).
- No conflict auto-resolution policy beyond what `jj-delegate` already mandates (integration never halts; conflicts are first-class and resolved by editing markers).
- No new plugin and no application-code changes in any target project.

## Decisions

**Decision: Map only unresolved, in-scope review comments into the brief.**
The skill fetches review threads and the review summary via `gh` (e.g. `gh pr view <pr> --json reviews` plus the review-comment API via `gh api`), filters out resolved/outdated threads, and composes one brief that preserves each comment's file + line + body so the worker can locate it. Rationale: feeding resolved or outdated comments produces churn and contradicts what the reviewer currently wants; line anchoring lets the worker act precisely. Alternative considered — pass the worker a raw comment dump and let it filter — rejected because filtering is deterministic orchestration work that belongs to the conductor, not duplicated in every worker.

**Decision: Base the worker on the PR head, resolved to a local jj revision, via explicit `-r`.**
Per `jj-delegate`'s explicit-base-revision rule, the skill resolves the PR head branch to a local jj revision (fetching it if needed) and provisions with `jj workspace add -r <pr-head-rev> <path>`. Rationale: the worker's fixes must apply on top of exactly the commits under review so that absorb can later land each hunk into its owning commit; basing on `@` or trunk would put the fixes against the wrong history. Alternative — base on trunk and cherry-pick — rejected: it detaches the fixes from the commits the reviewer commented on, defeating absorb.

**Decision: Land fixes via `/jj-absorb`, surface the remainder, never force-fit.**
After the worker reports, the orchestrator runs the `/jj-absorb` step over the worker's working-copy fixes so each hunk lands in the downstack commit a reviewer was commenting on. Any hunk with no unambiguous downstack home is surfaced (per `/jj-absorb`'s remainder handling) for deliberate placement, not pushed as-is. Rationale: this is exactly what makes it amend-*into-the-right-commit* rather than a tip fixup, and it reuses A4's previewed, reported absorb instead of re-deriving placement. Alternative — always squash the worker's change into the PR head tip — rejected because it collapses fixes meant for different commits into one, losing the per-commit intent reviewers asked for.

**Decision: Update the PR via `/jj-pr`, idempotently, after absorb.**
Once fixes are absorbed the orchestrator invokes `/jj-pr <bookmark>` to re-push and update the existing PR in place. Rationale: `/jj-pr` already handles create-or-update idempotence and one-time tracking, so the loop closes by reusing it rather than open-coding `jj git push` + `gh pr edit`. Alternative — a bespoke push here — rejected as duplication of D1 with divergent behaviour risk.

**Decision: Ship in core `jj-concurrent`, alongside `/jj-absorb` and `/jj-pr`.**
`/jj-pr-fixup` is the conductor for the same reconcile-tail family, so it ships in core `jj-concurrent` and bumps that plugin's version; no new plugin. Alternative — a separate `jj-concurrent-review` plugin — rejected as over-fragmentation for one composing skill.

**Decision: Reference A4/D1 conceptually; require a runtime preflight, not a spec dependency.**
Because A4 and D1 are in-flight (not in `openspec/specs/`), this change introduces no delta spec modifying them and adds no hard spec dependency. At runtime the skill preflight-checks that the `/jj-absorb` and `/jj-pr` skills are present (and that `gh` is authenticated) and reports a clear blocker if not. Rationale: keeps this capability authorable and validatable today while still composing cleanly once A4/D1 land.

## Risks / Trade-offs

- **A4 or D1 not yet available when this skill runs** → runtime preflight checks for the `/jj-absorb` and `/jj-pr` skills and reports a clear blocker; the skill never silently substitutes an open-coded absorb or push.
- **Review comments anchored to outdated lines after the PR head moved** → the brief preserves the original file/line plus the comment body so the worker can relocate the intent; resolved/outdated threads are excluded up front.
- **A fix maps ambiguously across several downstack commits** → delegated to `/jj-absorb`'s remainder handling: the hunk is surfaced for deliberate placement, never force-fitted.
- **Worker's fixes conflict on integration** → governed by `jj-delegate`'s "integration never halts": the rebase succeeds with a first-class conflict the orchestrator resolves by editing markers, never interactive `jj resolve`.
- **PR head branch not fetchable locally** → resolution-to-local-revision step reports a clear blocker before any workspace is provisioned.
- **`gh` lacking permission to read review comments** → preflight on `gh auth status` and the comment fetch reports a blocker rather than producing an empty brief that looks like "no comments".
- **Authoring-only scope mistaken for implementation** → design and tasks state explicitly that this change drafts artifacts only.

## Migration Plan

Not applicable — authoring-only change introducing a new skill spec. No deployment, data, or rollback concerns. When implemented later via `/opsx:apply`, the skill is additive (a new `SKILL.md` plus a `jj-delegate` prose pointer) and carries no migration. It begins composing with `/jj-absorb` and `/jj-pr` once those land; until then its preflight reports the missing dependency.

## Open Questions

- Exact `gh` surface for review comments — `gh pr view --json reviews,comments` vs `gh api repos/{o}/{r}/pulls/{n}/comments` for line-anchored threads; settle the precise calls at implementation time.
- Whether to post a "fixed in <commit>" reply / mark threads resolved on GitHub after a successful loop — deferred as a later extension, not in this capability.
- How to scope the worker brief when comments span many files — one brief per PR (draft default) vs batching by file; confirm at apply time.
- Preflight probe for presence of the `/jj-absorb` and `/jj-pr` skills (skill-manifest check vs trial invocation) — settle during implementation.

## Context

`plugins/jj-concurrent/hooks/scripts/jj-guard.sh` is a PreToolUse Bash hook. It already:

- extracts the candidate command from the hook payload via `jq`;
- resolves an effective directory from a single leading `cd`;
- walks upward from that directory to find a `.jj` entry, and **fails open** (exit 0) if none is found;
- blocks the universal floor: `rm` on `.jj`/`.git`, raw mutating git, interactive jj.

Its header explicitly states that role rules (bookmarks/push are orchestrator-only) are "enforced by the worker-agent contract in v0.1.0, not here." The `jj-delegate` spec defines the role split: the orchestrator runs in the default workspace and owns all bookmark/ref/push operations; a worker runs in exactly one linked workspace and "SHALL NOT operate on bookmarks, push, or run raw mutating git." Nothing currently enforces the bookmark/push half of that rule — a misbehaving worker can corrupt shared ref state the orchestrator owns.

The guard already locates the governing `.jj` directory during its membership walk. That same `.jj` directory carries an unambiguous, zero-cost signal of role.

## Goals / Non-Goals

**Goals:**

- Enforce the orchestrator-only rule for `jj bookmark …` and `jj git push` against workers, in the guard, so it no longer depends solely on contract prose.
- Keep detection **cheap and hang-proof**: no jj invocation, only filesystem type tests on a path the guard already has.
- Preserve all existing behaviour for the orchestrator and the universal floor for both roles.
- Fail open whenever role is undetermined, so the change can only *add* blocks for clearly-identified workers, never newly block the default workspace.

**Non-Goals:**

- Implementing the hook (this change is authoring-only; implementation lands later via `/opsx:apply`).
- Restricting any worker command beyond `jj bookmark …` and `jj git push` (commit-shaping stays free).
- Detecting *which* orchestrator provisioned the workspace, or reading any orchestrator-written marker file (considered and rejected below).
- Changing the `jj-delegate` role semantics — this change only enforces what that spec already mandates.

## Decisions

### Decision: Detect role from `.jj/repo` type at the located `.jj` directory

In a jj repo, the default (primary) workspace's `.jj/repo` is the **store directory** itself. A linked workspace created by `jj workspace add` has a `.jj/repo` that is a **regular file** containing a relative path back to the default workspace's store. Therefore:

- `.jj/repo` is a directory → default workspace → **orchestrator**.
- `.jj/repo` is a regular file → linked workspace → **worker**.

The guard already computes the `.jj`-containing directory in its upward walk (`$dir/.jj`). Implementation adds, at the point the walk finds `.jj`, a capture of that directory so role can be classified with `test -d "$jjdir/repo"` vs `test -f "$jjdir/repo"`. This is pure POSIX filesystem stat — no process spawn, no jj, cannot hang.

**Alternatives considered:**

- *Invoke `jj workspace root` / `jj root` to compare against the default workspace path.* Rejected: violates the guard's hard rule that it never invokes jj (jj can hang; a guard that hangs on every Bash call is worse than no guard).
- *Have the orchestrator write a marker file (e.g. `.jj/.role-worker`) at provisioning time.* Rejected as the primary mechanism: it adds a provisioning step, can drift from reality (forgotten on manual `jj workspace add`, stale after `jj workspace forget`), and the `.jj/repo` type already encodes the exact same fact with zero coordination. A marker could be a *fallback* signal but adds no value here, so it is left out to keep the surface minimal.
- *Compare `$PWD` against a recorded default-workspace path.* Rejected: requires knowing/storing that path out-of-band; the `.jj/repo` type is self-describing and local.

### Decision: Only workers are restricted; orchestrator and undetermined fail open

The new block fires **only** when role is classified as worker. Orchestrator → allow. Undetermined (`.jj/repo` is neither plain file nor directory — e.g. a symlink or exotic setup) → allow. This guarantees the change is purely additive for clearly-identified workers and can never newly block the default workspace, matching the guard's existing fail-open philosophy.

### Decision: Restrict exactly `jj bookmark …` and `jj git push`

These are the two operations `jj-delegate` reserves for the orchestrator that a worker could plausibly run and that mutate shared refs. Raw `git push` is already covered indirectly (the worker is told to use `gh`/jj; and raw mutating git is already blocked by the universal floor where applicable). Matching follows the existing guard style: anchored `jj[[:space:]]+bookmark([[:space:]]|$)` and `jj[[:space:]]+git[[:space:]]+push([[:space:]]|$)`, with the same `(^|[^[:alnum:]_./-])` left boundary used elsewhere in the script.

### Decision: Update the stale header comment

The header's "Role-specific rules … are enforced by the worker-agent contract in v0.1.0, not here" becomes false. Implementation updates it to describe the new role-detection + worker-restriction block. This is documentation only and carries no behavioural risk.

## Risks / Trade-offs

- **[jj changes its on-disk `.jj/repo` representation]** → The directory-vs-file distinction is a stable, long-standing jj layout (default store dir vs linked-workspace pointer file), but it is an implementation detail of jj rather than a public contract. *Mitigation*: detection fails open on anything that is neither a plain file nor a directory, so a future representation change degrades to "allow" (today's behaviour) rather than wrongly blocking; a regression test on a real linked workspace will catch a true break.
- **[False worker classification blocks a legitimate orchestrator]** → Only possible if the default workspace's `.jj/repo` were ever a regular file, which it is not. *Mitigation*: orchestrator and undetermined both fail open; only an unambiguous linked-workspace pointer file triggers a block.
- **[Worker legitimately needs a bookmark]** → By design it does not — `jj-delegate` makes the orchestrator the sole owner of refs/push. *Mitigation*: the block message tells the worker to report and let the orchestrator integrate, matching the contract.
- **[Effective-directory `cd` parsing already-known limitation]** → Role detection inherits the guard's existing single-leading-`cd` effective-directory resolution; a command that `cd`s mid-string into a different workspace is judged from the leading directory. *Mitigation*: this is a pre-existing, documented limitation of the membership walk, unchanged by this design.

## Migration Plan

This is a guard-hook tightening with no data or API surface. Deploy by shipping the updated `jj-guard.sh`. Rollback is reverting that one file; because the new logic only adds blocks for clearly-identified workers and fails open everywhere else, reverting restores the prior universal-floor-only behaviour with no cleanup. No coordination with running sessions is required.

## Open Questions

- None blocking. (Optional future hardening: a belt-and-braces orchestrator-written marker as a secondary signal — deliberately deferred; the `.jj/repo` type is sufficient and coordination-free.)

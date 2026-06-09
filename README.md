# claude-code-jj

Concurrent multi-agent orchestration for Claude Code on **[Jujutsu (jj)](https://github.com/jj-vcs/jj)** workspaces.

Run many Claude agents on many changes at once — each agent in its own jj
**workspace** (physical file isolation), commits auto-snapshotted so nothing is
lost to a crash, and integration that **never halts** because jj conflicts are
first-class objects rather than a blocked merge.

This is the jj successor to a Graphite/git-worktree orchestration.

**Documentation:**

- [JJ_OVERVIEW.md](JJ_OVERVIEW.md) — new to jj? Start here: the working-copy-as-commit model, colocated jj-on-git, and how jj workspaces differ from git worktrees.
- [MANUAL.md](MANUAL.md) — operating the plugins: the orchestrator/worker contract, workspace lifecycle, `/jj-delegate`, the fan-out, `/jj-fleet`, `/jj-pr`, `/jj-openspec`, the Linear binding, the hooks, and a gotchas/troubleshooting table.
- [DESIGN.md](DESIGN.md) — the design rationale (ADR): why jj over GitButler (shared-tree write race) and over git worktrees (restack-while-checked-out hazard).
- [ROADMAP.md](ROADMAP.md) — the proposed-but-not-yet-built features (OpenSpec proposals under `openspec/changes/`).

## Plugins

| Plugin | What it adds |
|--------|--------------|
| **`jj-concurrent`** | The core. Skills: **`jj-delegate`** (orchestrator/worker lifecycle), **`jj-fleet`** (one at-a-glance status view of all in-flight workers), **`jj-pr`** (push a bookmark + create/update its GitHub PR — the "submit" jj lacks), **`jj-stacked-pr`** (one based PR per bookmark from a stitched stack), **`jj-land`** (land a PR stack bottom-up, CI-gated, retargeting each base to trunk), **`jj-absorb`** (amend-after-review: distribute scattered hunks into their downstack commits), **`jj-checkpoint`** / **`jj-rewind`** (record a named op-log save point before a risky step, then roll back to it), **`jj-preview`** (stand up a throwaway dev environment from any commit/bookmark, then tear it down). Plus the `jj-workspace-worker` agent, a **snapshot hook** (`jj util snapshot` after every edit — closes jj's crash-before-snapshot gap), and a **guard hook** (blocks raw mutating git, interactive jj, and `rm` on the `.jj`/`.git` stores; also enforces the orchestrator-only rule — a worker may not run `jj bookmark`/`jj git push`). Workflow-agnostic. |
| **`jj-concurrent-openspec`** | `jj-openspec` skill — backgrounds an OpenSpec verb (`apply` / `propose` / `new` / `ff` / `relay`) in its own jj workspace, mapping verb → shape → reconcile tail. `apply` can **fan out** across a change's separable `tasks.md` groups, run a **multi-change pipeline** over a *set* of changes (concurrent siblings → independent landings or a stitched stack), and runs `/opsx:verify` as a **gate** that auto-archives on green; `relay` chains author → human go/no-go → apply in one command; a pre-flight **health check** validates artifacts before dispatch. Enable only in OpenSpec repos. |
| **`jj-concurrent-linear`** | `jj-linear` skill — Linear binding over the orchestrator, two halves meeting on the agent-plan manifest: at **dispatch**, auto-create an umbrella issue + one sub-issue per worker and thread their IDs into the manifest; at **reconcile**, map each worker's report to its sub-issue (in-progress → done / blocker comment), post a four-section umbrella summary, and raise a human-gate sub-issue on a manual signal. Separate, separately-enabled binding; enable only in Linear-tracked repos (requires a configured Linear MCP server). |

This marketplace does **not** vendor a jj command reference — it depends on the
excellent read-only [`jj-vcs@toolbox`](https://github.com/schpet/toolbox/tree/main/plugins/jj-vcs)
(schpet), installed unmodified, for the worker's jj vocabulary and
agent-hang rules.

## Prerequisites

```bash
# jj itself, colocated with git so GitHub/PRs still work
brew install jj                       # or your platform's package
cd your-repo && jj git init --colocate

# the jj reference layer (worker vocabulary) — unmodified upstream
claude plugin marketplace add schpet/toolbox
claude plugin install jj-vcs@toolbox

# GitHub CLI — required only if you use /jj-pr (push + open/update a PR)
brew install gh && gh auth login   # or your platform's package
```

`gh` (authenticated) is a prerequisite for the **`/jj-pr`** push-and-PR step and
the reconcile tails that call it. Everything else — `/jj-delegate`, `/jj-fleet`,
the fan-out, local jj — works without it.

## Install

```bash
# from this marketplace (local clone or GitHub)
claude plugin marketplace add /path/to/claude-code-jj   # or DannyGoodall/claude-code-jj
claude plugin install jj-concurrent@claude-code-jj
claude plugin install jj-concurrent-openspec@claude-code-jj   # only for OpenSpec repos
claude plugin install jj-concurrent-linear@claude-code-jj      # only for Linear-tracked repos
```

Restart Claude Code after installing. The hooks (snapshot + guard) take effect
in sessions started after install.

## Quick start

```text
# one worker, one workspace, one change
you:    /jj-delegate "add a rate limiter to the api client" feat/rate-limit
claude: plan: workload, bookmark feat/rate-limit, workspace ../wt-rate-limit,
        base <trunk>. Proceed?
you:    yes
claude: [jj workspace add -r … · bookmark create · dispatch jj-workspace-worker
         (background)] → terminal returns to you; worker edits + shapes commits
         in its workspace; reports JSON.
        [reconcile: verify · jj git push -b feat/rate-limit · jj workspace forget]

# apply an OpenSpec change on its own workspace (add "fan out" to split it across task groups)
you:    /jj-openspec apply timetabling-strand-location-grouping

# while workers run: one status view of the whole fleet
you:    /jj-fleet

# submit a finished bookmark — push + open/update its GitHub PR
you:    /jj-pr feat/rate-limit
```

## Validation

Every functional claim has been exercised end-to-end against **real jj 0.42** in
colocated mode. Summary of what was run and what it proved:

| Area | What was validated | Result |
|------|--------------------|--------|
| **jj substrate** | `workspace add -r @` carries in-flight inputs; snapshot hook captures an edit against live jj; cross-workspace visibility; **integration never halts** (rebase with a real conflict → exit 0, first-class conflict object); stale detection + `jj workspace update-stale` recovery | 6/6 |
| **Single-worker loop** | a real background `jj-workspace-worker` provisioned → worked → reported (~28s), contract-abiding (jj only, no bookmarks/push); **snapshot hook fired** — a discrete `snapshot working copy` op appears in `jj evolog` between the worker's edits and its describe (the crash-gap protection); integrated via an orchestrator-owned bookmark | ✓ |
| **Concurrent multi-worker** | two background workers dispatched in parallel on sibling workspaces (~16–17s, overlapping); **physical isolation proven** — each workspace held only its own file, no clobber; both integrated into one stack | ✓ |
| **Same-file concurrent conflict** | two workers edited the *same line* of one file (1.1.0 vs 2.0.0) in separate workspaces; isolation held (no race); rebase exited 0 and recorded a **first-class conflict**; resolved by editing markers + snapshot (never `jj resolve`) — the exact scenario a shared-working-tree model cannot do safely | ✓ |
| **Colocated jj-on-git** | jj reads the full git history and `jj @-` == `git HEAD`; the colocated commit→bookmark→`jj git push` flow works (one-time `jj bookmark track main --remote=origin` after init) | ✓ |
| **cwd-aware guard** | enforces inside a jj repo / fails open outside; a leading `cd <dir>` is parsed so `cd <non-jj> && git …` is judged from the right directory | 6/6 |
| **`/jj-openspec` relay** | `propose` (authoring) drafts the change artifacts in a workspace; the apply worker bases on the proposal revision (**seed-intent — no seed commit**); `apply` (implementing) writes the code + ticks `tasks.md` | ✓ |

Untested by choice: a *real* jj hang (intermittent by nature — `resume-in-place` is
ready for it, since a stalled worker's edits are already snapshotted).

## Status

**jj-concurrent v0.7.0** · jj-concurrent-openspec v0.2.0 · jj-concurrent-linear v0.3.0
— functionally validated, documented, and self-hosting (the plugin is now
OpenSpec-managed and its features ship via its own jj workers).

The v0.1.x evaluation arc (substrate, single/concurrent workers, same-file
conflict, colocated jj-on-git, the cwd-aware guard, the `/jj-openspec` relay) and
**v0.2.0** (`/jj-fleet`, `/jj-pr`, the OpenSpec apply fan-out, the
`jj-concurrent-linear` binding) are complete — see the Validation table above.

**v0.3.0** adds four features, applied concurrently by the plugin's own workers
and reconciled in one stack (see
[the fan-out case study](docs/case-studies/fleet-fanout-2026-06-09.md)):

- **`/jj-stacked-pr`** — derive the parent chain from a stitched jj stack and open/update one PR per bookmark, each based on its parent (true stacked PRs).
- **`/jj-absorb`** — amend-after-review: preview with `jj absorb --dry-run`, distribute scattered working-copy hunks into their downstack commits, report where each landed.
- **`/jj-checkpoint` + `/jj-rewind`** — record a named op-log save point before a risky integration, then roll the whole repo back to it via `jj op restore`.
- **Guard role enforcement** — the guard hook now blocks `jj bookmark`/`jj git push` from a worker workspace (the orchestrator-only rule, previously contract-only), while still allowing them in the orchestrator's primary workspace.

**v0.4.0** adds **`/jj-land`** — land a stack of GitHub PRs bottom-up, CI-gated,
**retargeting each child PR's base to trunk before merge** and tidying merged
bookmarks/stale workspaces. It directly closes the stacked-merge hazard that once
orphaned upper PRs onto deleted feature branches. (Shipped alongside three new
roadmap proposals authored in the same four-worker fan-out — see [ROADMAP.md](ROADMAP.md).)

**v0.5.0** adds **multi-orchestrator support** (`multi-orchestrator-namespacing`):
per-session agent-plan manifests (`.jj-agent-plan.<session>.json`), per-orchestrator
workspace/bookmark prefixes, a `/jj-fleet` that **unions all sessions**, and a
stale-state startup sweep — so more than one orchestrator can run in a single repo
without clobbering the manifest or colliding on names. It was implemented via the
first **within-a-change** fan-out: three workers each took a separable task group
of the one change (session-id+manifest / naming+cleanup / fleet-union) and were
reconciled into one branch.

**v0.5.1** (`jj-land-colocated-cleanup`) fixes `/jj-land` under colocated jj:
judge merge success by PR **state** (not the `gh pr merge` exit code, which fails
on jj's detached git HEAD), drop `--delete-branch`, and **explicitly delete each
merged PR's remote branch** in cleanup so no stragglers remain — found and fixed
while landing the archive stack (#11–#14).

**v0.6.0** — the workspace & dev-environment batch (3-worker fan-out, landed via
the fixed `/jj-land`): **`/jj-preview <rev>`** (stand up a throwaway dev
environment from any commit/bookmark, then tear it down), **worktree-include
provisioning** (seed a worker's gitignored files from the `.worktreeinclude` /
`.claude/settings.json` declaration instead of ad-hoc `cp`), and **optional
sparse partitions** (`jj workspace add --sparse-patterns` so a worker's tree
materialises only its lane — hard file-ownership).

**v0.6.1** (`jj-land-stack-restack`) completes the `/jj-land` family: it waits for
**mergeability** (not just CI) before each merge, defaults to **`--merge`** for
multi-PR stacks, and **restacks+repushes** the tail after a rewriting merge — so a
stack whose PRs share a file lands without cascade-conflicts. (Found while landing
#16–#19, which needed a manual restack; now encoded in the skill.) **It was then
validated**: the next batch — `jj-concurrent-linear` v0.2.0 below — was landed as a
real 2-PR shared-file stack with the fixed `/jj-land`, which merged cleanly (no
cascade) and left zero remote stragglers.

The guard enforces the universal safety floor (no raw mutating git, no
interactive jj, no `rm` on the VCS store) inside jj repos for both roles, with
cwd-aware repo detection, **plus** the worker bookmark/push restriction above.

**`jj-concurrent-openspec` v0.2.0** — four features applied concurrently by a
second four-worker fan-out, all converging on one file (`jj-openspec/SKILL.md`)
and reconciled through a deliberate **4-way merge**
([case study](docs/case-studies/openspec-pipeline-fanout-2026-06-09.md)): the
`relay` verb (author → human go/no-go → apply in one command), `/opsx:verify` as
a **gate** that auto-archives on green, a pre-flight **health check** of change
artifacts, and a **multi-change pipeline** (`apply` over a set of changes as
concurrent siblings → independent landings or a stitched stack).

**`jj-concurrent-linear` v0.2.0** — the binding grew a **dispatch** half:
`linear-dispatch-issue-creation` (auto-create the umbrella + per-worker sub-issues
at dispatch, thread their IDs into the manifest) and `jj-linear-reconcile-summary`
(a four-section umbrella summary + a human-gate sub-issue at reconcile). Landed as
the shared-file 2-PR stack that validated `/jj-land`'s stack-restack fix.

**v0.7.0** — the jj-native stack & history batch, two new orchestrator skills:
**`/jj-pr-fixup <pr>`** (read an open PR's review comments, fix them in a
workspace based on the PR head, absorb each fix into the commit it belongs to via
`/jj-absorb`, and re-push — the amend-after-review loop end-to-end) and
**`/jj-keep-current`** (detect trunk moved, fetch + rebase the stack, re-check CI,
and gate landing behind a green required-checks signal so a stale-but-green PR
never lands).

**`jj-concurrent-linear` v0.3.0** — the binding's **inbound** half, closing the
board↔fan-out loop: **`/jj-from-linear <issue>`** (one command from a triaged
`ready-for-agent` issue to a dispatched `jj-delegate` worker, with the bookmark
and PR/change back-link derived deterministically from the issue) and
**`/jj-burndown`** (drain a board's `ready-for-agent` issues as a bounded
sliding-window stream of concurrent jj workers, updating each issue as its worker
lands — the board becomes a work queue with jj as the engine).

v0.7.0 and linear v0.3.0 shipped together: **all four remaining roadmap proposals
applied in one 4-worker fan-out**. Because each change added its own new skill
file, the four worker branches were fully disjoint — reconciled by the
orchestrator into a clean 3-PR stack (jj-concurrent skills / linear skills / docs)
and landed via `/jj-land` with no cascade. The ROADMAP backlog is now empty.

**What's next** is captured as OpenSpec proposals — see [ROADMAP.md](ROADMAP.md).
Deliberately deferred (see [DESIGN.md](DESIGN.md) "Open questions"):
smarter guard matching (it
currently matches git/jj *mentions* in a command string, and `git -C <dir>`
slips past — the worker contract is the primary line, the guard a backstop).

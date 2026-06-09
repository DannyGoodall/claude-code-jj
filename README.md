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
| **`jj-concurrent`** | The core. Skills: **`jj-delegate`** (orchestrator/worker lifecycle), **`jj-fleet`** (one at-a-glance status view of all in-flight workers), **`jj-pr`** (push a bookmark + create/update its GitHub PR — the "submit" jj lacks). Plus the `jj-workspace-worker` agent, a **snapshot hook** (`jj util snapshot` after every edit — closes jj's crash-before-snapshot gap), and a **guard hook** (blocks raw mutating git, interactive jj, and `rm` on the `.jj`/`.git` stores). Workflow-agnostic. |
| **`jj-concurrent-openspec`** | `jj-openspec` skill — backgrounds an OpenSpec verb (`apply` / `propose` / `new` / `ff`) in its own jj workspace, mapping verb → shape → reconcile tail. `apply` can **fan out** across a change's separable `tasks.md` groups — one workspace per group, reconciled into one branch. Enable only in OpenSpec repos. |
| **`jj-concurrent-linear`** | `jj-linear` skill — Linear binding over the orchestrator: at the reconcile point, maps each worker's structured JSON report to its Linear sub-issue (in-progress → done on a clean finish, blocker/conflict comment otherwise). Separate, separately-enabled binding; enable only in Linear-tracked repos (requires a configured Linear MCP server). |

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

**jj-concurrent v0.2.0** · jj-concurrent-openspec v0.1.0 · jj-concurrent-linear v0.1.0
— functionally validated, documented, and self-hosting (the plugin is now
OpenSpec-managed and its features ship via its own jj workers).

The v0.1.x evaluation arc (substrate, single/concurrent workers, same-file
conflict, colocated jj-on-git, the cwd-aware guard, the `/jj-openspec` relay) is
complete — see the Validation table above. **v0.2.0** adds, on top of that base:

- **`/jj-fleet`** — one read-only status view across all live workspaces (snapshots siblings first so it is never stale).
- **`/jj-pr`** — push a bookmark and create/update its GitHub PR; wired into both reconcile tails as the submit step.
- **OpenSpec apply fan-out** — `/jj-openspec apply` can split a change across its separable `tasks.md` groups, one workspace per group, reconciled into one branch.
- **`jj-concurrent-linear`** — a third, separately-enabled plugin binding worker reports to Linear sub-issues at reconcile time.

The guard still enforces the universal safety floor (no raw mutating git, no
interactive jj, no `rm` on the VCS store) inside jj repos for both roles, with
cwd-aware repo detection; role-specific enforcement (bookmarks/push are
orchestrator-only) is carried by the worker-agent contract.

**What's next** is captured as OpenSpec proposals — see [ROADMAP.md](ROADMAP.md).
Deliberately deferred (see [DESIGN.md](DESIGN.md) "Open questions"):
workspace-based role detection *in* the guard, sparse-workspace partitions
(`--sparse-patterns`), and smarter guard matching (it currently matches git/jj
*mentions* in a command string, and `git -C <dir>` slips past — the worker
contract is the primary line, the guard a backstop).

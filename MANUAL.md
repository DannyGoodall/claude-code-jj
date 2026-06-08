# jj-concurrent Manual

How to run many Claude Code agents on many changes at once, each isolated in its own [Jujutsu (jj)](https://github.com/jj-vcs/jj) **workspace**, coordinated by an orchestrator.

Companion documents in this repo:

- [README.md](README.md) — what the plugins are and how to install them
- [JJ_OVERVIEW.md](JJ_OVERVIEW.md) — a primer on jj itself (colocated jj-on-git, the working-copy-as-commit model, workspaces vs git worktrees) for people new to it
- [DESIGN.md](DESIGN.md) — the design rationale (why jj over GitButler and git worktrees), as an ADR

New to jj? Read [JJ_OVERVIEW.md](JJ_OVERVIEW.md) first — this manual assumes the vocabulary.

---

## Contents

- [The model in one paragraph](#the-model-in-one-paragraph)
- [How the plugins work](#how-the-plugins-work)
- [Installation & prerequisites](#installation--prerequisites)
- [The orchestrator / worker contract](#the-orchestrator--worker-contract)
- [Workspace lifecycle](#workspace-lifecycle)
- [Single worker: /jj-delegate](#single-worker-jj-delegate)
- [Concurrent fan-out: many workers](#concurrent-fan-out-many-workers)
- [Orchestrating OpenSpec changes: /jj-openspec](#orchestrating-openspec-changes-jj-openspec)
- [The hooks (snapshot + guard)](#the-hooks-snapshot--guard)
- [Orchestrator jj quick reference](#orchestrator-jj-quick-reference)
- [Gotchas & troubleshooting](#gotchas--troubleshooting)

---

## The model in one paragraph

One Claude session is the **orchestrator**, living in the repository's primary (default) jj workspace. For each unit of work it provisions a **jj workspace** — a separate working directory with its own working-copy commit, sharing the one `.jj`/`.git` object store — and dispatches a **worker** subagent into it. Workers edit files in their own directory (physical isolation: concurrent agents cannot clobber each other), shape their own jj commits, and report back. The orchestrator owns everything repo-wide: workspace lifecycle, all bookmark/ref operations, pushing, and integration. Because jj rebases never fail (conflicts are first-class objects) and jj operations are lock-free, integration **never halts** — and because jj auto-snapshots the working copy (reinforced by a snapshot hook), a crashed worker loses nothing.

---

## How the plugins work

| Component | File | What it does |
|-----------|------|--------------|
| Skill: `jj-delegate` | `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` | The mechanism — resolve workload → provision workspace → dispatch worker(s) → integrate. Workflow-agnostic. |
| Worker agent: `jj-workspace-worker` | `plugins/jj-concurrent/agents/jj-workspace-worker.md` | A constrained subagent: works in one workspace, jj only, never bookmarks/push/raw-git, with a structured JSON report. |
| Snapshot hook | `plugins/jj-concurrent/hooks/scripts/jj-snapshot.sh` | PostToolUse on edits — runs `jj util snapshot` so an agent crash before its next jj command never loses the last edit. |
| Guard hook | `plugins/jj-concurrent/hooks/scripts/jj-guard.sh` | PreToolUse on Bash — blocks raw mutating git, interactive jj, and `rm` on the `.jj`/`.git` stores. Only enforces inside a jj repo. |
| Skill: `jj-openspec` | `plugins/jj-concurrent-openspec/skills/jj-openspec/SKILL.md` | OpenSpec binding over `jj-delegate`: backgrounds an OpenSpec verb (`apply`/`propose`/`new`/`ff`) on a workspace, mapping verb → shape. Separate plugin — enable only in OpenSpec repos. |

The jj **command vocabulary** the worker uses is *not* vendored here — it comes from the read-only [`jj-vcs@toolbox`](https://github.com/schpet/toolbox/tree/main/plugins/jj-vcs) plugin, installed unmodified.

---

## Installation & prerequisites

```bash
# jj itself, colocated with git so GitHub/PRs keep working
brew install jj                       # or your platform's package
cd your-repo && jj git init --colocate

# the jj reference layer (worker vocabulary) — unmodified upstream
claude plugin marketplace add schpet/toolbox
claude plugin install jj-vcs@toolbox

# this marketplace
claude plugin marketplace add DannyGoodall/claude-code-jj   # or a local clone path
claude plugin install jj-concurrent@claude-code-jj
claude plugin install jj-concurrent-openspec@claude-code-jj   # only for OpenSpec repos
```

Restart Claude Code after installing — hooks, the worker agent, and the skills load at session start.

**One-time colocated-repo step:** after `jj git init --colocate` on a repo that already has a remote, the local `main` bookmark does not auto-track the remote. Before your first `jj git push`:

```bash
jj bookmark track main --remote=origin
```

---

## The orchestrator / worker contract

| Role | Lives in | Owns |
|------|----------|------|
| **Orchestrator** | the primary (default) workspace | workspace lifecycle (`jj workspace add`/`forget`), **all** `jj bookmark` + `jj git push` + ref ops, integration, the agent-plan manifest, the issue tracker |
| **Worker** | one jj workspace each | edits in its directory + shaping its own commits (`jj new`/`jj describe -m`). Never bookmarks, never pushes, never raw mutating git. |

This split is the **safety model for colocated concurrency**: jj's official docs note that concurrent modification of a colocated repo is not yet thoroughly tested and *could* lose bookmark pointers (never commits — those are content-addressed). Serializing every ref/bookmark/push through the single orchestrator removes that risk. The guard hook enforces the "no raw git, no interactive jj, no destroying the store" floor for both roles; the bookmarks/push-are-orchestrator-only rule is carried by the worker-agent contract.

---

## Workspace lifecycle

```
provision ──> dispatch ──> work ──> integrate ──> teardown
(orchestr.)   (orchestr.)  (worker)  (orchestr.)   (orchestr.)
```

**Provision** (orchestrator):

```bash
jj workspace add -r <base-rev> ../wt-<slug>    # -r is REQUIRED — see "seed intent" below
```

**Seed intent — no seed commit, but pick the base revision deliberately.** git worktrees only contain *committed* files, which forced a "seed commit" of untracked inputs. jj has no staging and no untracked limbo — your inputs are already in the working-copy commit `@`. But `jj workspace add` defaults to basing the new workspace on `@`'s **parent**, which would *miss* anything in `@`. So pass `-r` explicitly:

- need the worker to see in-flight inputs (e.g. a just-authored OpenSpec change folder)? → `-r @` (after confirming `@` is clean), or `-r <a curated change-rev>`.
- starting from trunk? → `-r <trunk-bookmark>`.

Because jj auto-snapshots *everything not gitignored* into `@`, base workers on a **clean** revision — not a `@` polluted with incidental working-tree churn (the jj-flavoured "no stage-all").

**Per-workspace environment is real** — each workspace is its own directory. Install dependencies and copy gitignored env files the workload needs (`cp .env.local ../wt-<slug>/`). If the workload runs the app, assign it a distinct port in the dispatch brief.

**Teardown** (after integration):

```bash
jj workspace forget <name>     # forget the workspace association
rm -rf ../wt-<slug>            # the directory only — NEVER the repo .jj
```

A bookmark on the worker's commit keeps it referenced after the workspace is forgotten; without one, an abandoned working-copy commit just becomes unreferenced (still recoverable via `jj op log`).

---

## Single worker: /jj-delegate

```text
you:    /jj-delegate "add a rate limiter to the api client" feat/rate-limit
claude: plan — workload, bookmark feat/rate-limit, workspace ../wt-rate-limit,
        base <trunk>. Proceed?
you:    yes
claude: [jj workspace add -r <trunk> ../wt-rate-limit · dispatch jj-workspace-worker
         (background)] → terminal returns to you. Worker edits + shapes commits in
         its workspace; reports JSON.
        [reconcile: review/verify · jj bookmark · jj git push · jj workspace forget]
```

The workload is either a **skill invocation** the worker runs via its Skill tool (e.g. `/opsx:apply my-change`) or a plain **slice spec** (what to build + acceptance criteria). Background dispatch is the default — the session stays free and you can launch more workers.

---

## Concurrent fan-out: many workers

The headline capability. Dispatch several workers in one message — each on a **sibling workspace** off trunk, each on an independent slice. They run in parallel in physically separate directories, so concurrent edits cannot collide.

```text
you: Fan out: implement the auth helper and the api client independently,
     one jj worker each, in parallel.
```

```bash
# orchestrator provisions two sibling workspaces off trunk
jj workspace add -r main ../wt-auth
jj workspace add -r main ../wt-api
# then dispatches two background jj-workspace-worker subagents, one per workspace
```

Each worker writes only its own files. When they report, the orchestrator integrates each — for example stitching the siblings into a stack:

```bash
jj rebase -s <api-change> -d <auth-change>   # sibling -> stack; ALWAYS exit 0
jj bookmark set main -r <api-change>          # advance trunk through both
```

**No prune-before-restack barrier.** With git worktrees, a restack rewrites refs repo-wide and *fails* on a branch checked out in another worktree — hence Graphite's hard "prune all worktrees before any restack" rule. jj has no such hazard: operations are lock-free and rebases never fail. The only thing to mind is **staleness** — don't move a revision a *live* workspace builds on; if one goes stale, `jj workspace update-stale` in that workspace recovers it (it is a recoverable state, not a failed operation).

**Situational awareness:** `jj log` does not auto-snapshot sibling workspaces, so a plain log can show stale state. Snapshot each live workspace first, then log:

```bash
for ws in ../wt-*; do jj -R "$ws" util snapshot >/dev/null 2>&1; done
jj log -r 'all()'
```

---

## Orchestrating OpenSpec changes: /jj-openspec

The `jj-concurrent-openspec` plugin binds the orchestrator to OpenSpec. One entry point, the verb selects the **shape**:

| Verb(s) | Shape | Worker produces | Reconcile tail |
|---------|-------|-----------------|----------------|
| `apply` | **Implementing** | code + ticked `tasks.md` | integrate → `/opsx:verify` → issue tracker → push/PR |
| `propose` / `new` / `ff` | **Authoring** | change artifacts under `openspec/changes/<name>/` | validate + surface for review; bookmark only; **no verify, no merge** |
| `explore` | **Interactive** | (a thinking partner) | not a default background candidate — run it inline |

### Case study: propose then apply (validated end-to-end)

```text
# 1. Author the change on its own workspace
you:    /jj-openspec propose "document the jj evaluation in docs/jj-eval-note.md"
claude: [provision wt off trunk · dispatch worker → /opsx:propose →
         creates openspec/changes/document-jj-eval-note/{proposal,design,specs,tasks}.md]
        [reconcile: openspec validate · bookmark change/document-jj-eval-note · report]

# 2. Apply it — the apply worker bases on the PROPOSAL revision (seed intent)
you:    /jj-openspec apply document-jj-eval-note
claude: [jj workspace add -r change/document-jj-eval-note ../wt-apply   ← proposal present,
         no seed commit needed · dispatch worker → /opsx:apply → implements +
         ticks tasks.md, committed together]
        [reconcile: /opsx:verify · integrate the stack base→proposal→impl · push/PR]
```

The crux: the apply worker is based on the revision that *already contains* the proposal (`-r change/<slug>`). There is no seed-commit dance — jj just points the workspace at it.

---

## The hooks (snapshot + guard)

### Snapshot hook (PostToolUse: Edit/Write/MultiEdit/NotebookEdit)

jj snapshots the working copy only when a jj command runs. An agent that edits files and then crashes *before* any jj command would lose that last edit. The hook runs `jj util snapshot` after every edit — so every change is captured into the workspace's working-copy commit and is recoverable via `jj evolog` / `jj op restore`. It is fail-open and time-bounded (a stuck snapshot can never wedge the agent), and only acts inside a jj repo.

You can see it working in `jj evolog` on any worker change: a discrete `snapshot working copy` operation appears between the worker's edits and its `describe`.

### Guard hook (PreToolUse: Bash)

A cheap, hang-proof, string-matching backstop. It **only enforces inside a jj repo** (it walks up for `.jj`, parsing a leading `cd <dir>` so `cd <non-jj-repo> && git …` is judged from the right directory) and blocks:

- **raw mutating git** (`commit`/`add`/`checkout`/`reset`/`rebase`/`merge`/…) — corrupts jj state in a colocated repo. Read-only git (`log`/`status`/`show`/`diff`) and `gh` stay allowed.
- **interactive jj** (`jj resolve`/`arrange`/`diffedit`/`config edit`/`sparse edit`, `-i`/`--interactive`) — hangs an agent session that has no TTY.
- **`rm` targeting `.jj`/`.git`** — never delete the VCS store to "fix" a hang; recovery is orchestrator-only via `jj op restore`.

It never invokes jj (so it cannot itself hang). Known limits (the worker contract is the primary line, the guard is the backstop): it matches git/jj *mentions* in a command string, not only invocations, and `git -C <dir> <verb>` slips past. Role-specific rules (bookmarks/push are orchestrator-only) are enforced by the worker contract, not the guard, in this version.

---

## Orchestrator jj quick reference

| Need | Command |
|------|---------|
| Provision a worker workspace | `jj workspace add -r <base-rev> ../wt-<slug>` |
| List workspaces | `jj workspace list` |
| See all changes (incl. workers') | `jj log -r 'all()'` (snapshot siblings first) |
| Inspect a worker's change | `jj show <change> --summary` / `jj file list -r <change>` |
| Integrate a sibling onto another | `jj rebase -s <src> -d <dest>` (never halts) |
| Move trunk forward | `jj bookmark set main -r <change>` |
| Finalize + push (colocated) | `jj commit -m "…"` → `jj bookmark set main -r @-` → `jj git push -b main` |
| Resolve a conflicted change | edit the conflict markers in files (NOT `jj resolve`) |
| Recover from a bad operation | `jj op log` → `jj op restore <op>` |
| Tear down a workspace | `jj workspace forget <name>` + `rm -rf ../wt-<slug>` |

Use `--no-pager` and `-m` everywhere (automation has no editor); `--ignore-working-copy` for read-only inspection.

---

## Gotchas & troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `jj git push` → "Non-tracking remote bookmark main@origin exists" | colocated repo's local bookmark doesn't track the remote yet | `jj bookmark track main --remote=origin`, then push |
| Worker `jj status` → "The working copy is stale" | the orchestrator rewrote a revision the workspace built on | `jj workspace update-stale` in that workspace (recoverable, not a failure) |
| Guard blocks git in a non-jj repo you cd into | the guard judged from the session cwd | fixed in current versions via leading-`cd` parsing; for `git -C <dir>` (a known gap) just run from within the dir |
| `jj log` shows stale sibling-workspace state | jj doesn't auto-snapshot other workspaces | snapshot each live workspace first, then log |
| opsx CLI prints `Rules for 'tasks' must be an array…` noise | a pre-existing repo schema-config quirk | harmless; unrelated to the change; ignore |
| A `jj` command hangs for minutes | a known jj rough edge under heavy use | do NOT retry blindly and NEVER `rm` `.jj`; the orchestrator recovers via `jj op restore`. A stalled worker's work is already snapshotted — resume a fresh worker in the same workspace |
| Worker died without a report | stall / watchdog kill | **resume-in-place**: its edits are snapshotted; inspect with `jj evolog`, dispatch a fresh worker into the SAME workspace to continue |

**Colocated three-way overlay:** if a repo is git + another tool (e.g. GitButler) + jj at once, jj reads and stays in sync, but two tools want to manage the one working copy — watch for contention, and prefer a clone for throwaway jj experiments.

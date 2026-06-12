# jj-concurrent Manual

How to run many Claude Code agents on many changes at once, each isolated in its own [Jujutsu (jj)](https://github.com/jj-vcs/jj) **workspace**, coordinated by an orchestrator.

Companion documents in this repo:

- [README.md](README.md) — what the plugins are and how to install them
- [JJ_OVERVIEW.md](JJ_OVERVIEW.md) — a primer on jj itself (colocated jj-on-git, the working-copy-as-commit model, workspaces vs git worktrees) for people new to it
- [DESIGN.md](DESIGN.md) — the design rationale (why jj over GitButler and git worktrees), as an ADR
- [ROADMAP.md](ROADMAP.md) — proposed-but-not-yet-built features, as OpenSpec proposals under `openspec/changes/`
- [docs/case-studies/linkstack-walkthrough.md](docs/case-studies/linkstack-walkthrough.md) — **learn by walkthrough:** one beginner builds one tiny web app using every plugin feature, each with what you type in Claude and the jj/`gh`/Linear commands it abstracts

New to jj? Read [JJ_OVERVIEW.md](JJ_OVERVIEW.md) first — this manual assumes the vocabulary. Prefer learning by example? The [linkstack walkthrough](docs/case-studies/linkstack-walkthrough.md) runs through every feature as a story.

---

## Contents

- [The model in one paragraph](#the-model-in-one-paragraph)
- [How the plugins work](#how-the-plugins-work)
- [Installation & prerequisites](#installation--prerequisites)
- [The orchestrator / worker contract](#the-orchestrator--worker-contract)
- [Workspace lifecycle](#workspace-lifecycle)
- [Single worker: /jj-delegate](#single-worker-jj-delegate)
- [Concurrent fan-out: many workers](#concurrent-fan-out-many-workers)
- [Watching the fleet: /jj-fleet](#watching-the-fleet-jj-fleet)
- [Submitting a bookmark: /jj-pr](#submitting-a-bookmark-jj-pr)
- [Cutting a release: /jj-release](#cutting-a-release-jj-release)
- [Orchestrating OpenSpec changes: /jj-openspec](#orchestrating-openspec-changes-jj-openspec)
- [Reporting to Linear: /jj-linear](#reporting-to-linear-jj-linear)
- [The hooks (snapshot + guard)](#the-hooks-snapshot--guard)
- [Publishing & updating the plugins](#publishing--updating-the-plugins)
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
| Skill: `jj-fleet` | `plugins/jj-concurrent/skills/jj-fleet/SKILL.md` | One read-only at-a-glance status view of all in-flight workers: snapshots every live workspace first, then joins jj state with the agent-plan manifest's per-slice status/blocker/workload. Orchestrator-only. |
| Skill: `jj-pr` | `plugins/jj-concurrent/skills/jj-pr/SKILL.md` | The "submit" jj lacks — push a bookmark (`jj git push -b`) and create-or-update its GitHub PR via `gh`, generating a what/why body from the change's commits and any `proposal.md`. Orchestrator-only. |
| Skill: `jj-stacked-pr` | `plugins/jj-concurrent/skills/jj-stacked-pr/SKILL.md` | When fan-out siblings were stitched into one linear stack, derive the parent chain from the jj topology and open/update one PR per bookmark **based on its parent** (composing `/jj-pr`). Orchestrator-only. |
| Skill: `jj-land` | `plugins/jj-concurrent/skills/jj-land/SKILL.md` | Land a stack of GitHub PRs **bottom-up**: wait for CI at each step, **retarget each child PR's base to trunk before merging** (so the stack can't orphan its upper PRs onto deleted branches), then tidy merged bookmarks + stale workspaces. The safe "merge the whole stack" verb. Orchestrator-only; needs `gh`. |
| Skill: `jj-absorb` | `plugins/jj-concurrent/skills/jj-absorb/SKILL.md` | Amend-after-review — preview placement (by `jj absorb --dry-run` where available, else an op-log `jj op show -p` review + one-command `jj op restore` undo on a jj that lacks `--dry-run`, e.g. 0.42), distribute scattered working-copy hunks into the downstack commit that last touched those lines, report where each landed, leave ambiguous hunks for manual placement. Orchestrator-only. |
| Skill: `jj-checkpoint` (record + rewind verbs) | `plugins/jj-concurrent/skills/jj-checkpoint/` | Op-log safety net — `/jj-checkpoint <label>` records the current `jj op` id in the manifest before a risky step; `/jj-checkpoint rewind [label]` rolls the whole repo back to it via `jj op restore` after a confirmation summary. Orchestrator-only. |
| Skill: `jj-preview` | `plugins/jj-concurrent/skills/jj-preview/SKILL.md` | Stand up a throwaway dev environment from any commit/bookmark — provision an isolated `../wt-preview-<slug>` via `jj workspace add -r`, seed its env + a distinct port, run the app, report URL+PID, then tear down. Read-only to history (never bookmarks/pushes/archives). Orchestrator-only. |
| Skill: `jj-pr-fixup` | `plugins/jj-concurrent/skills/jj-pr-fixup/SKILL.md` | The amend-after-review loop over an **already-open PR**: read the PR's review comments, fix them in a workspace based on the PR head, absorb each fix into the commit it belongs to (composing `/jj-absorb`), and re-push so the PR updates in place. Orchestrator-only; needs `gh`. |
| Skill: `jj-keep-current` | `plugins/jj-concurrent/skills/jj-keep-current/SKILL.md` | Keep a stack current against a moved trunk: detect trunk advanced → `jj git fetch` → `jj rebase` the stack → push → re-check CI, and **gate landing behind a green required-checks signal** so a stale-but-green PR never lands. Orchestrator-only; needs `gh`. |
| Skill: `jj-release` | `plugins/jj-lifecycle/skills/jj-release/SKILL.md` | Cut a GitHub release for the repo at one commit — relay-shaped prepare → go/no-go gate → publish. **Tag-only** (the tag *is* the version; no manifest edited), `vMAJOR.MINOR.PATCH`; SemVer bump auto-proposed but **always confirmed**; **CI gate on the target commit** (not a PR); **0.x → pre-release ON** by default; optional **opaque artifacts hook**; server-side tag via `gh release create --target`; **refuses** an existing tag. Ships in its **own `jj-lifecycle` plugin** — usable without the concurrency/OpenSpec plugins. Orchestrator-only; needs `gh`. |
| Worker agent: `jj-workspace-worker` | `plugins/jj-concurrent/agents/jj-workspace-worker.md` | A constrained subagent: works in one workspace, jj only, never bookmarks/push/raw-git, with a structured JSON report. |
| Snapshot hook | `plugins/jj-concurrent/hooks/scripts/jj-snapshot.sh` | PostToolUse on edits — runs `jj util snapshot` so an agent crash before its next jj command never loses the last edit. |
| Guard hook | `plugins/jj-concurrent/hooks/scripts/jj-guard.sh` | PreToolUse on Bash — blocks raw mutating git, interactive jj, `rm` on the `.jj`/`.git` stores, and (v0.3.0) `jj bookmark`/`jj git push` from a worker workspace. Only enforces inside a jj repo. |
| Skill: `jj-openspec` | `plugins/jj-concurrent-openspec/skills/jj-openspec/SKILL.md` | OpenSpec binding over `jj-delegate`: backgrounds an OpenSpec verb (`apply`/`propose`/`new`/`ff`/`relay`) on a workspace, mapping verb → shape. `apply` fans out across `tasks.md` groups, runs a multi-change pipeline over a *set* of changes, and gates on `/opsx:verify` (auto-archives on green); `relay` chains author → go/no-go → apply; a pre-flight health check validates artifacts first. Separate plugin — enable only in OpenSpec repos. |
| Skill: `jj-linear` | `plugins/jj-concurrent-linear/skills/jj-linear/SKILL.md` | Linear binding over the orchestrator (two halves): at **dispatch**, auto-create an umbrella + per-worker sub-issues and thread their IDs into the manifest; at **reconcile**, map each worker's report to its sub-issue (in-progress → done / blocker comment), post a four-section umbrella summary, and raise a human-gate sub-issue on a manual signal. Separate plugin — enable only in Linear-tracked repos; needs the Linear MCP server. |
| Skill: `jj-from-linear` | `plugins/jj-concurrent-linear/skills/jj-from-linear/SKILL.md` | The binding's **inbound** half: turn one triaged `ready-for-agent` Linear issue into a dispatched `jj-delegate` worker, with the bookmark and PR/change back-link derived deterministically from the issue. Separate plugin; needs the Linear MCP server. |
| Skill: `jj-burndown` | `plugins/jj-concurrent-linear/skills/jj-burndown/SKILL.md` | Drain a board's `ready-for-agent` issues as a bounded **sliding-window** stream of concurrent jj workers (default window 3), updating each issue as its worker lands — the board becomes a work queue with jj as the engine. Separate plugin; needs the Linear MCP server. |

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

# GitHub CLI — required only if you use /jj-pr (push a bookmark + open/update its PR)
brew install gh && gh auth login

# this marketplace
claude plugin marketplace add DannyGoodall/claude-code-jj   # or a local clone path
claude plugin install jj-concurrent@claude-code-jj
claude plugin install jj-lifecycle@claude-code-jj             # /jj-release — standalone, no concurrency needed
claude plugin install jj-concurrent-openspec@claude-code-jj   # only for OpenSpec repos
claude plugin install jj-concurrent-linear@claude-code-jj      # only for Linear-tracked repos
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

## Watching the fleet: /jj-fleet

Once more than one worker is in flight, you want one view of the whole fleet, not a manual sweep of `jj workspace list` + `jj log` + "which slice was that again?". `/jj-fleet` renders exactly that — a single read-only status table joining jj state with the orchestrator's agent-plan manifest:

```text
you: /jj-fleet
claude: WORKSPACE        SLICE              CHANGE     STATUS       BLOCKER
        ../wt-auth       auth-helper        kpqr…      working      —
        ../wt-api        api-client         lmno…      reported ✓   —
        ../wt-export     csv-export         stuv…      conflict ×   rebase onto auth
```

It is **strictly read-only** and orchestrator-only: it runs in the primary workspace, **snapshots every live workspace first** (`jj util snapshot` per workspace, so siblings are never shown stale — the same trick the fan-out section uses before `jj log`), then reads jj state and overlays the manifest's per-slice `status` / `blocker` / `workload`. It never touches bookmarks, push, or any worker's commits. Use it any time during a fan-out to decide what to reconcile, what to nudge, and what is blocked.

---

## Submitting a bookmark: /jj-pr

`jj git push` moves a bookmark to the remote but never opens a pull request — jj has no "submit". `/jj-pr` is that missing step, in one orchestrator action:

```text
you: /jj-pr feat/rate-limit
claude: [jj git push -b feat/rate-limit  (one-time: jj bookmark track … --remote=origin if needed)]
        [gh: no PR exists → create it, body generated from the change's commits + any proposal.md]
        → https://github.com/you/repo/pull/123
```

Given a bookmark it:

1. pushes with `jj git push -b <bookmark>` (handling the one-time `jj bookmark track <name> --remote=origin` that a freshly colocated repo needs);
2. checks GitHub via `gh` — **creates** the PR if none exists, **updates** it if one does (idempotent — safe to re-run after more commits);
3. generates a what / why / benefit body from the change's commits and, if present, the OpenSpec `proposal.md`.

It is **orchestrator-only** — it owns refs and push, so it is never invoked inside a worker — and it is the reconcile-tail "submit" step for both `/jj-delegate` and `/jj-openspec apply`. Requires a colocated jj↔git repo with an `origin` remote and an authenticated `gh`.

---

## Cutting a release: /jj-release

The reconcile tail ends at `/jj-land`: work gets merged, but nothing then cuts a GitHub **release**. `/jj-release` is that missing "ship a milestone" step, and it ships in its **own `jj-lifecycle` plugin** — a release-only user can install just that plugin, without any of the concurrency or OpenSpec plugins. It is **relay-shaped**: a PREPARE phase does everything computable, then a **single human go/no-go gate**, then a PUBLISH phase that runs only on "go".

```text
you: /jj-release
claude: [target = main HEAD; CI gate on that COMMIT's check-runs — green]
        [last tag v0.1.0; a feat: since → propose v0.2.0; 0.x → pre-release ON]
        RELEASE SUMMARY (version, target, CI, pre-release, draft, assets, notes)
        Publish? (go / no)
you: go
        → gh release create v0.2.0 --target <sha> --notes-file … --prerelease
        → https://github.com/you/repo/releases/tag/v0.2.0
```

The policies worth knowing:

- **Tag-only versioning.** The git **tag is the version** — `/jj-release` creates the tag and the release and **edits no file**. It never bumps `plugin.json`/`package.json`/`Cargo.toml`. Repo manifest versions may diverge from the release tag; that is acceptable by design (it neither reads them for mutation nor reconciles them). Tag format is `vMAJOR.MINOR.PATCH`.
- **Version is always confirmed.** A SemVer bump is auto-proposed from conventional commits since the last tag (`feat`→minor, `fix`→patch, breaking/`!`→major), but the human **always** confirms or overrides at the gate — even an argument-supplied version is still confirmed. On a **first release** (no prior tag) it offers **no default** and asks outright; on non-conventional history it also just asks.
- **0.x → pre-release ON by default.** GitHub does not infer pre-release from the version string; this is the skill's **policy** (SemVer says 0.x is unstable). `1.x`+ defaults to OFF. Either way the flag shows in the gate summary and is overridable there.
- **CI gate on the target commit.** By release time the originating PR is merged, so the gate reads the **commit's** check-runs and combined status (`gh api repos/{owner}/{repo}/commits/{sha}/check-runs` and `…/status`), **not** `gh pr checks`. A red or still-pending check **refuses** the release (a manual release outside the plugin remains the user's prerogative).
- **Refuses an existing release.** Tags are immutable; unlike `/jj-pr`'s create-or-update, `/jj-release` **refuses** when a release for the tag already exists and asks for a new version — it never overwrites a published artifact.
- **Artifacts hook boundary.** Attaching built assets is **optional and opaque**: supply a project's build command and the skill runs it and uploads whatever files it emits — it **ships no build logic of its own** and never interprets how anything is built. With no command you get a clean source-only release (GitHub's auto-generated source archive).
- **Server-side tag creation.** The tag is created on the remote at the target sha via `gh release create <tag> --target <sha>` — sidestepping jj 0.42's missing native tag creation and the guard hook's block on raw `git tag`.

It is **orchestrator-only** and **non-interactive** (`--no-pager`, no `-i`, no editor — human input arrives only through the relay gate); it makes no commit, edits no file, and force-pushes nothing. Requires a colocated jj↔git repo with an `origin` remote and an authenticated `gh` with release-create scope.

---

## Orchestrating OpenSpec changes: /jj-openspec

The `jj-concurrent-openspec` plugin binds the orchestrator to OpenSpec. One entry point, the verb selects the **shape**:

| Verb(s) | Shape | Worker produces | Reconcile tail |
|---------|-------|-----------------|----------------|
| `apply` | **Implementing** | code + ticked `tasks.md` | integrate → `/opsx:verify` **(gate)** → on green: `/opsx:archive` → issue tracker → push/PR; non-green: **stop** and report |
| `propose` / `new` / `ff` | **Authoring** | change artifacts under `openspec/changes/<name>/` | validate + surface for review; bookmark only; **no verify, no archive, no merge** |
| `relay` | **Composite** | author → human go/no-go gate → apply, in one command | authoring tail at the gate; on *go*, the implementing tail seeded from the proposal revision |
| `explore` | **Interactive** | (a thinking partner) | not a default background candidate — run it inline |

Two further `apply` capabilities (binding v0.2.0): a **pre-flight health check** validates a change's artifacts and filters known-harmless opsx stderr *before* a workspace is provisioned; and a **multi-change pipeline** takes a *set* of changes and applies them as concurrent siblings — independent landings, or a stitched stack submitted via `/jj-stacked-pr`. Full detail lives in the `jj-openspec` SKILL.md (§B/§4c/§P, §6, §3.5).

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

### Apply fan-out: one change across its task groups

A large `apply` need not run in a single worker. When a change's `tasks.md` has **separable groups** (independent sections that don't depend on each other's output), `/jj-openspec apply` can fan out — one worker per group, each on its own sibling workspace based on the proposal revision, all reconciled into one change branch:

```text
you:    /jj-openspec apply timetabling-strand-location-grouping  (fan out across task groups)
claude: plan — groups: [schema, loader, ui]; 3 sibling workspaces off
        change/timetabling-strand-location-grouping. Proceed?
you:    yes
claude: [3 background workers, one per group → each ticks its own tasks.md section]
        [reconcile: snapshot all · integrate the three into one stack on the change branch ·
         merge the ticked tasks.md · /opsx:verify the whole change · /jj-pr]
```

This is the [concurrent fan-out](#concurrent-fan-out-many-workers) mechanism applied to a single OpenSpec change instead of independent slices. The same rules hold: physical isolation per workspace, integration never halts, snapshot siblings before logging. Only split groups that are genuinely independent — overlapping groups just produce conflicts to resolve at reconcile (recoverable, but pointless work). The reconcile tail merges the per-group `tasks.md` ticks, verifies the change as a whole, then submits via `/jj-pr`.

---

## Reporting to Linear: /jj-linear

The `jj-concurrent-linear` plugin is a **separate, separately-enabled binding** — enable it only in Linear-tracked repos; it needs a configured Linear MCP server (`mcp__linear-server__*`). It does one job, at the orchestrator's **reconcile point**: take each background worker's structured JSON report and reflect it onto that worker's Linear sub-issue.

| Worker outcome | Linear action |
|----------------|---------------|
| clean finish | transition the sub-issue **in-progress → done** |
| blocker / conflict | post a **comment** with the blocker/conflict detail; leave status as-is |

It threads the umbrella + sub-issue IDs captured at **dispatch**, keyed by the worker's **workspace path**, so each report lands on the right issue. The worker itself stays Linear-agnostic — it only ever emits its JSON report; all Linear I/O is the orchestrator's, at reconcile. There is no issue *creation* and no PR cross-linking in this version (PR submission is `/jj-pr`'s job); this binding is purely report → sub-issue status.

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
- **`jj bookmark` / `jj git push` from a worker workspace** (since v0.3.0) — the orchestrator-only rule, now enforced in the guard, not just the worker contract. The guard classifies the role from the workspace (`.jj/repo` is a directory in the orchestrator's primary workspace, a file in a linked worker workspace) and blocks bookmark/push only when the role is `worker`; the orchestrator's primary workspace is unaffected, and it fails open when the role is unknown or outside any jj repo.

It never invokes jj (so it cannot itself hang). Known limits (the worker contract is the primary line, the guard is the backstop): it matches git/jj *mentions* in a command string, not only invocations, and `git -C <dir> <verb>` slips past — and because it string-matches, even a non-interactive `jj resolve --list` is blocked (resolve conflicts by editing markers instead, which is the prescribed workflow anyway).

---

## Publishing & updating the plugins

This section is for the **maintainer** of this marketplace, not the consumer. There are two distinct loops that are easy to conflate: the **publish** side (shipping new plugin versions from this repo) and the **consume** side (refreshing an installed copy so the new versions actually load). The trap in the middle: editing a file under `plugins/` does **nothing** to a session that installed from the marketplace until you bump the version, push, refresh, reinstall, **and restart** — and hooks never hot-reload.

### Where versions live

| File | Carries a version? | Role |
|------|--------------------|------|
| `.claude-plugin/marketplace.json` | **No** — descriptions only | Lists the four plugins; served straight from the GitHub repo |
| `plugins/<name>/.claude-plugin/plugin.json` | **Yes** (`"version"`) | The **only** signal that an update exists — what `claude plugin marketplace update` compares against |

Because the marketplace manifest has no versions, the per-plugin `version` in `plugin.json` is the entire update mechanism. Merging to `main` **is** the publish step — there is no separate registry to push to. (`/jj-release` cuts a GitHub *release tag*, which is **tag-only** and does **not** bump `plugin.json`; the marketplace ignores release tags. The two are independent.)

### Publish runbook (maintainer)

```text
1. Edit the skill / hook / agent files under plugins/<plugin>/...
2. Bump "version" in each CHANGED plugin's plugins/<name>/.claude-plugin/plugin.json
   (only the plugins you actually touched — SemVer: fix→patch, feat→minor, breaking→major)
3. If behaviour changed, update the description in BOTH places, kept in parallel:
     - plugins/<name>/.claude-plugin/plugin.json  ("description")
     - .claude-plugin/marketplace.json            (that plugin's entry)
4. Validate locally (mirrors CI — see below)
5. Commit on a branch and open a PR (you may be on a detached HEAD: `* (no branch)` — branch first)
6. Merge to main  ← this is the publish
```

**Validate locally before pushing** — the same three gates CI runs (`.github/workflows/ci.yml`), plus the skills linter:

```bash
# JSON manifests parse
for f in .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json; do
  python3 -m json.tool "$f" >/dev/null && echo "ok $f"
done
# hook scripts (error severity)
shellcheck -S error plugins/*/hooks/scripts/*.sh
# OpenSpec specs/changes (only if you touched them)
openspec validate --all --strict
# skills lint
python3 scripts/lint-skills.py
```

### Make the update live (consume side — also the dev-loop gap)

After the new versions are on `main`, **nothing in a running session changes** until you refresh and reinstall. For each plugin you bumped:

```bash
claude plugin marketplace update claude-code-jj          # refresh the manifest from GitHub
claude plugin install jj-concurrent@claude-code-jj        # reinstall each CHANGED plugin
claude plugin install jj-lifecycle@claude-code-jj
claude plugin install jj-concurrent-openspec@claude-code-jj
claude plugin install jj-concurrent-linear@claude-code-jj
```

Then **quit and restart Claude Code**. Newly installed skills, the worker agent, and the snapshot + guard hooks only take effect in a session started *after* install — **hooks do not hot-reload**.

**Tighter inner loop while iterating.** Registering the marketplace from a **local clone path** instead of GitHub lets a `marketplace update` + reinstall pick up working-tree edits **without a push**:

```bash
claude plugin marketplace add /Users/dannygoodall/Dev/Code/claude-code-jj   # local path
# ...edit, then: marketplace update + reinstall + restart, no commit needed
```

Switch the registration back to `DannyGoodall/claude-code-jj` for the real publish so you're testing what consumers actually get.

### Consumers updating their installed copy

Anyone else picks up your published bumps with the same two commands (no push, no restart trap they need to know the internals of):

```bash
claude plugin marketplace update claude-code-jj
claude plugin install <plugin>@claude-code-jj   # for each plugin they use
# then restart Claude Code
```

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
| `jj git fetch` → `Concurrent checkout` / `Failed to update Git HEAD ref` | another process touched the working copy mid-checkout (e.g. the PostToolUse snapshot hook, or a concurrent jj command) — common when a manual jj op races a live orchestrator session in the same workspace | **Nothing is lost** — jj records divergent operations and auto-merges them. Just **re-run a jj command** (`jj st`); if it reports stale, `jj workspace update-stale`; then `jj new main` to re-parent `@` and re-sync git HEAD. Never `rm` `.jj` (recover via `jj op log` / `jj op restore`). Avoid by not running a manual `jj git fetch` while an orchestrator session is active in the same workspace |

**Colocated three-way overlay:** if a repo is git + another tool (e.g. GitButler) + jj at once, jj reads and stays in sync, but two tools want to manage the one working copy — watch for contention, and prefer a clone for throwaway jj experiments.

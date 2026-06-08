# Jujutsu (jj): An Introduction for the Concurrent-Agent Workflow

A primer on [Jujutsu (jj)](https://github.com/jj-vcs/jj) for people who are new to it — written for the specific reason this repository exists: running **many AI agents on many changes at once**. It covers jj's mental model, how it sits *on top of* git (colocated mode), how its **workspaces** differ from git worktrees, the everyday commands, and finally how the `jj-concurrent` plugins use all of it.

Companion documents in this repo:

- [README.md](README.md) — what the plugins are and how to install them
- [MANUAL.md](MANUAL.md) — operating the plugins (orchestrator/worker, workspace lifecycle, the skills)
- [DESIGN.md](DESIGN.md) — why jj was chosen over GitButler and git worktrees, as an ADR

---

## Contents

- [Why jj for agents](#why-jj-for-agents)
- [The mental model](#the-mental-model)
- [Colocated: jj on top of git](#colocated-jj-on-top-of-git)
- [Workspaces (and how they differ from git worktrees)](#workspaces-and-how-they-differ-from-git-worktrees)
- [Everyday commands](#everyday-commands)
- [Gotchas for newcomers](#gotchas-for-newcomers)
- [How the plugin uses jj](#how-the-plugin-uses-jj)
- [Further reading](#further-reading)

---

## Why jj for agents

Three jj properties make it unusually well-suited to autonomous, concurrent agents — each one removes a specific failure mode of the alternatives:

1. **Workspaces give physical isolation.** Multiple working directories share one object store. Two agents editing the same repo at the same time are in *different folders* — they cannot clobber each other's files. (GitButler's "virtual branches" share one working tree, so concurrent writers race at the filesystem level; jj does not.)

2. **The working copy is always already committed.** jj automatically snapshots the working copy into a commit on (almost) every command. There is no staging area, no "uncommitted changes" to lose. An agent's work is durable the moment jj next runs — and a [PostToolUse snapshot hook](MANUAL.md#the-hooks-snapshot--guard) closes even the gap between an edit and that next command.

3. **Integration never blocks.** jj rebases and merges *always succeed*; if there is a conflict, it is recorded as a first-class object inside the resulting commit and resolved later. There is no "merge halted, fix this now" that stops a pipeline. Combined with a lock-free operation log (concurrent jj processes never corrupt state), this means an orchestrator can integrate many agents' work without the restack hazards that git worktrees carry.

The price is youth: jj is newer, and colocated (jj + git) concurrency is officially "not yet thoroughly tested" — it *could* lose a bookmark pointer (never a commit; those are content-addressed). The plugin's orchestrator-owns-all-refs rule is the mitigation.

---

## The mental model

### The working-copy commit (`@`)

In git you have a working directory, a staging area (index), and commits. In jj there is no index, and **the working copy itself is a commit** — referred to as `@`. When you change files and run any jj command, jj updates `@` to match. You never `git add`; you just edit, and jj snapshots.

To give `@` a message you `jj describe -m "…"`. To start a *new* change on top, `jj new` (the old `@` becomes a normal commit; a fresh empty `@` sits on top). That is the core loop: **edit → describe → new**.

### Change IDs vs commit IDs

Every change has a stable **change ID** (letters `k`–`z`, e.g. `qszrxqys`) that survives rewrites (amending, rebasing), and a **commit ID** (git-style hex, e.g. `c4140719`) that changes each time the content changes. You refer to work by its change ID; the commit ID is the underlying git object. `jj log` shows both.

### Anonymous changes, no branch required

You do not create a branch to start work. You just work; `@` is an anonymous change. Names for sharing (git branches) are added later as **bookmarks** (see colocated section). This is why an orchestrator can spin up a worker's change with no branch ceremony.

### First-class conflicts

A rebase that conflicts does **not** stop. jj records the conflict inside the commit (the commit is marked conflicted, `×` in the log) and the operation succeeds. You resolve it later by editing the conflict markers in the files, then the commit becomes clean. `jj log -r 'conflicts()'` finds conflicted changes. This is what makes "integrate N agents' work" a non-blocking step.

### The operation log

Every jj operation (snapshot, describe, rebase, bookmark move…) is recorded in the **operation log** (`jj op log`). It is an undo history for the *whole repo*: `jj op restore <op>` returns the repository to any prior state. This is the orchestrator's safety net — far more powerful than git's reflog, and the reason "never `rm` the `.jj` store to fix a problem" is an absolute rule: the recovery is always `jj op restore`, not deletion.

---

## Colocated: jj on top of git

This repository — and the repos the plugin targets — run jj in **colocated** mode: jj and git share the same working directory. You get jj's model while keeping git as the collaboration substrate (GitHub, PRs, `gh`).

```bash
cd your-repo
jj git init --colocate      # adds .jj alongside the existing .git
```

After this both `.jj` and `.git` exist. jj imports the git history; `jj log` shows your git commits; `jj @-` (the parent of the working copy) tracks `git HEAD`.

### Bookmarks ≈ branches

jj's equivalent of a git branch is a **bookmark**. In a colocated repo a bookmark exports to a git branch. Key commands:

```bash
jj bookmark list --all-remotes        # see local + remote bookmarks
jj bookmark create <name> -r <rev>    # create a bookmark at a revision
jj bookmark set <name> -r <rev>       # move a bookmark
jj bookmark track main --remote=origin  # ONE-TIME after colocating a repo with a remote
jj git push -b <name>                 # push a bookmark to the git remote
jj git fetch                          # fetch from the git remote
```

**The colocated gotcha worth knowing up front:** after `jj git init --colocate` on a repo that already has a remote, the local `main` bookmark does **not** automatically track `origin/main`. The first `jj git push` will error with "Non-tracking remote bookmark main@origin exists" — run `jj bookmark track main --remote=origin` once, and pushing works thereafter.

### Reading git, the safe way

In a colocated repo, **read-only git is fine** (`git log`, `git status`, `git show`, `git diff`) but **mutating git corrupts jj state** — use jj for commits, rebases, branch moves. The plugin's [guard hook](MANUAL.md#the-hooks-snapshot--guard) enforces exactly this line.

---

## Workspaces (and how they differ from git worktrees)

A **workspace** is a second working directory attached to the same jj repo — its own working-copy commit, sharing the one object store. It is the unit of physical isolation for a worker agent.

```bash
jj workspace add -r <rev> ../wt-feature   # new workspace, working copy based on <rev>
jj workspace list                          # all workspaces
jj workspace forget <name>                 # detach a workspace
jj workspace update-stale                  # recover a stale workspace (see below)
```

Workspaces resemble git worktrees but file off many of the sharp edges that make worktrees hostile to automation:

| | git worktree | jj workspace |
|---|---|---|
| **Tied to** | a **branch** (refuses if that branch is checked out elsewhere) | a **revision** (jj moves it freely) |
| **Working copy** | files **+ a staging index** | files **+ an auto-snapshotted working-copy commit** (no index) |
| **Uncommitted work** | lives in the dir/index; lost if clobbered | snapshotted into the working-copy commit on every jj command (or the hook) → recoverable |
| **Concurrent ops on the shared repo** | restack/rebase rewrites refs repo-wide and **fails** on a branch checked out elsewhere | **lock-free**; rebases never fail (first-class conflicts); other workspaces merely go **stale** |
| **The danger to manage** | a hard, blocking **ref conflict** (needs prune-before-restack) | soft, recoverable **staleness** (`jj workspace update-stale`) |
| **Integration conflict** | merge **halts**, pipeline blocks | recorded in a commit, resolve later — never blocks |

**Staleness** is the one new concept. If you rewrite a revision that another workspace's working-copy commit is built on, that workspace becomes *stale* — its next `jj status` says so, and `jj workspace update-stale` reconciles it (materializing any conflict for resolution). It is a recoverable state, never a failed operation. The orchestrator avoids it by not moving a revision a *live* worker builds on; when it happens legitimately (a rebase during integration), `update-stale` is the one-liner fix.

The one-line takeaway: **a worktree pins a branch and the failure mode is a hard blocking ref conflict; a workspace pins a revision and the failure mode is soft, recoverable staleness.**

---

## Everyday commands

| Need | jj |
|------|----|
| See working-copy status | `jj status` |
| See history | `jj log` (`-r 'all()'` for everything) |
| Set the current change's message | `jj describe -m "feat: …"` |
| Start a new change | `jj new -m "…"` |
| Commit current + start next (one step) | `jj commit -m "…"` |
| Move/squash work between changes | `jj squash` / `jj rebase` |
| Inspect a change | `jj show <change> --summary` |
| List files at a revision | `jj file list -r <rev>` |
| Undo the last operation | `jj undo` (or `jj op restore <op>`) |
| Make a bookmark / push it | `jj bookmark create …` / `jj git push -b …` |
| Add / recover / drop a workspace | `jj workspace add` / `update-stale` / `forget` |

For automation, always pass `-m` (no editor), `--no-pager`, and `--ignore-working-copy` for read-only inspection. The full per-command reference is the [`jj-vcs` skill](https://github.com/schpet/toolbox/tree/main/plugins/jj-vcs) this plugin depends on.

---

## Gotchas for newcomers

1. **No staging.** There is no `git add`. You edit, jj snapshots the whole working copy into `@`. To split work, use `jj split`; to move hunks, `jj squash --interactive` (avoid `-i` in automation).
2. **Don't mutate with git in a colocated repo.** `git commit`/`rebase`/`checkout` corrupt jj's view. Use jj; read-only git is fine.
3. **Bookmark tracking after colocate.** The one-time `jj bookmark track main --remote=origin` (above).
4. **`jj log` doesn't snapshot other workspaces.** In a multi-workspace setup, snapshot each first for an accurate cross-workspace view.
5. **Never delete `.jj` to fix something.** `jj op restore` is the recovery. Deleting the store is the one irreversible mistake (an agent once "debugged" a hang with `rm -rf .jj`).
6. **Change IDs (`k`–`z`) are not commit IDs (hex).** Refer to work by change ID; it survives rewrites.
7. **Occasional hangs.** jj can hang under heavy use; the fix is patience or `jj op restore`, never force.

---

## How the plugin uses jj

Everything above is what *you* would type. The `jj-concurrent` plugins teach a Claude Code orchestrator to do it — and to do it safely with many agents at once:

| jj concept | How the plugin uses it |
|------------|------------------------|
| Workspace | One per worker agent — the physical isolation that makes concurrency safe |
| Auto-snapshot + the snapshot hook | Worker edits are always captured; a crashed worker loses nothing; resume-in-place is free |
| First-class conflicts + lock-free ops | The orchestrator integrates many workers without a blocking merge or a prune-before-restack barrier |
| Bookmarks, `jj git push` | Orchestrator-only — the safety model for colocated concurrency |
| Operation log | The orchestrator's undo button (`jj op restore`) |
| `jj workspace add -r <rev>` | "Seed intent" — bases a worker on the revision that already holds its inputs, with no seed-commit ceremony |

See [MANUAL.md](MANUAL.md) for the operating detail and [DESIGN.md](DESIGN.md) for why this beats the GitButler and git-worktree alternatives.

---

## Further reading

- [Jujutsu docs](https://docs.jj-vcs.dev/) — official documentation
- [Working copy](https://docs.jj-vcs.dev/latest/working-copy/) and [Concurrency](https://docs.jj-vcs.dev/latest/technical/concurrency/) — the model this plugin leans on
- [`jj-vcs@toolbox`](https://github.com/schpet/toolbox/tree/main/plugins/jj-vcs) — the comprehensive jj command reference this plugin depends on (installed unmodified)
- [Avoid losing work with jj for AI agents](https://www.panozzaj.com/blog/2025/11/22/avoid-losing-work-with-jujutsu-jj-for-ai-coding-agents/) — the snapshot-gap and its hook fix
- [Running parallel AI agents with jj workspaces](https://geirsson.com/jj-workspaces) — real-world multi-agent practice (and its pitfalls)

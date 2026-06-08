# claude-code-jj

Concurrent multi-agent orchestration for Claude Code on **[Jujutsu (jj)](https://github.com/jj-vcs/jj)** workspaces.

Run many Claude agents on many changes at once — each agent in its own jj
**workspace** (physical file isolation), commits auto-snapshotted so nothing is
lost to a crash, and integration that **never halts** because jj conflicts are
first-class objects rather than a blocked merge.

This is the jj successor to a Graphite/git-worktree orchestration. The design
rationale — including why jj over GitButler (shared-tree write race) and over
git worktrees (restack-while-checked-out hazard) — is in
[DESIGN.md](DESIGN.md).

## Plugins

| Plugin | What it adds |
|--------|--------------|
| **`jj-concurrent`** | The core: `jj-delegate` skill (orchestrator/worker lifecycle), the `jj-workspace-worker` agent, a **snapshot hook** (`jj util snapshot` after every edit — closes jj's crash-before-snapshot gap), and a **guard hook** (blocks raw mutating git, interactive jj, and `rm` on the `.jj`/`.git` stores). Workflow-agnostic. |
| **`jj-concurrent-openspec`** | `jj-openspec` skill — backgrounds an OpenSpec verb (`apply` / `propose` / `new` / `ff`) in its own jj workspace, mapping verb → shape → reconcile tail. Enable only in OpenSpec repos. |

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
```

## Install

```bash
# from this marketplace (local clone or GitHub)
claude plugin marketplace add /path/to/claude-code-jj   # or DannyGoodall/claude-code-jj
claude plugin install jj-concurrent@claude-code-jj
claude plugin install jj-concurrent-openspec@claude-code-jj   # only for OpenSpec repos
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

# apply an OpenSpec change on its own workspace
you:    /jj-openspec apply timetabling-strand-location-grouping
```

## Status

v0.1.0 — initial scaffold. The guard enforces the universal safety rules
(no raw mutating git, no interactive jj, no `rm` on the VCS store) for both
roles; role-specific enforcement (bookmarks/push are orchestrator-only) is
carried by the worker-agent contract for now. See DESIGN.md "Open questions"
for what is deliberately deferred (smoke spike, sparse-workspace partitions,
workspace-based role detection in the guard).

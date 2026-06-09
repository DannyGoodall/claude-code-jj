# Case study: a 4-worker fan-out, observed with `/jj-fleet`

**Date:** 2026-06-09 · **jj:** 0.42.0 (colocated on git) · **Repo:** this one (`claude-code-jj`), self-hosting

This is a literal record of one real exercise: an orchestrator (one Claude Code
session) fanned out **four concurrent background workers**, each applying a
different OpenSpec roadmap proposal in its own jj workspace, while `/jj-fleet`
rendered the in-flight status. It then reconciled all four into one stack —
including a genuine 3-way merge conflict — and tore the workspaces down. Every
command and output below is what actually ran.

It doubles as a worked demonstration of the headline claim: *many agents, many
changes, physical isolation, integration that never halts.*

---

## 0. The goal

Smoke-test [`/jj-fleet`](../../plugins/jj-concurrent/skills/jj-fleet/SKILL.md) with
a realistic multi-worker fan-out, and in doing so apply four of the active
roadmap proposals. The four were picked for **independence** and
**mostly-disjoint files**, one from each surface:

| Change | Tasks | Surface |
|--------|-------|---------|
| `workspace-aware-guard-role-enforcement` | 10 | the guard hook (`jj-guard.sh`) |
| `jj-absorb-fixup` | 14 | new skill `/jj-absorb` |
| `jj-stacked-pr` | 18 | new skill `/jj-stacked-pr` |
| `jj-op-checkpoint` | 21 | new skills `/jj-checkpoint` + `/jj-rewind` |

Known in advance: three of them register their skill in
`plugins/jj-concurrent/.claude-plugin/plugin.json` and edit
`jj-delegate/SKILL.md §5`, so those two files would conflict **at integration**
(never mid-flight — workers are physically isolated). That conflict was left in
deliberately: it is the most instructive part.

---

## 1. Setup — provision four sibling workspaces

The orchestrator owns workspace lifecycle and all bookmarks. Base everything on
`main` (each `openspec/changes/<name>/` folder is already committed there, so the
workers see their proposals with **no seed commit** needed).

```bash
jj git fetch                                  # "pull"; advances tracked bookmarks
jj workspace add -r main ../wt-absorb         # → "Added 186 files"
jj workspace add -r main ../wt-checkpoint
jj workspace add -r main ../wt-guard-role
jj workspace add -r main ../wt-stacked-pr
```

`jj workspace list` then shows four siblings, each with its own working-copy
commit off `main`:

```
default:       nzovyklw a288f022 (empty)
wt-absorb:     kostkqrq f62afb30 (empty)
wt-checkpoint: mmokuuvl 879076d6 (empty)
wt-guard-role: kqsruokz fe292b5c (empty)
wt-stacked-pr: omvttolz e62d88c9 (empty)
```

One bookmark per workspace, then the gitignored agent-plan manifest that
`/jj-fleet` reads:

```bash
jj bookmark create feat/jj-absorb       -r kostkqrq
jj bookmark create feat/jj-op-checkpoint -r mmokuuvl
jj bookmark create feat/guard-role      -r kqsruokz
jj bookmark create feat/jj-stacked-pr   -r omvttolz
```

`.jj-agent-plan.json` (one slice per worker — the join source for the fleet view):

```json
{
  "base": "main",
  "slices": [
    { "workspace": "../wt-absorb",     "bookmark": "feat/jj-absorb",        "status": "in-flight", "workload": "/opsx:apply jj-absorb-fixup" },
    { "workspace": "../wt-checkpoint",  "bookmark": "feat/jj-op-checkpoint", "status": "in-flight", "workload": "/opsx:apply jj-op-checkpoint" },
    { "workspace": "../wt-guard-role",  "bookmark": "feat/guard-role",       "status": "in-flight", "workload": "/opsx:apply workspace-aware-guard-role-enforcement" },
    { "workspace": "../wt-stacked-pr",  "bookmark": "feat/jj-stacked-pr",    "status": "in-flight", "workload": "/opsx:apply jj-stacked-pr" }
  ]
}
```

---

## 2. Dispatch — four background workers

Each is a `jj-concurrent:jj-workspace-worker` subagent dispatched in the
**background** (the jj workspace *is* the isolation — not a harness worktree).
The brief gives each worker its workspace path, bookmark, base, and the
workload (`/opsx:apply <change>`), plus a scope limit: *implement only your own
change's files; do NOT touch README/MANUAL/ROADMAP — the orchestrator folds
documentation in at reconcile.* The worker contract itself (workspace
containment, no bookmarks/push, non-interactive jj) lives in the agent
definition and is not restated.

All four launched from one message — provisioning serialized through the
orchestrator, the workers then ran genuinely in parallel.

---

## 3. The fleet command — four passes

`/jj-fleet` is **strictly read-only**. Each invocation (a) snapshots every live
workspace first (`jj -R <ws> util snapshot`) so no sibling shows stale, then (b)
reads jj state read-only, then (c) joins the manifest's `status`/`workload` onto
the live rows by workspace path.

### Pass 1 — t≈0 (just dispatched)

All four tracked, each holding its bookmark, all `empty=yes` — no files written
yet. Nothing stale, nothing conflicted.

### Pass 2 — mid-flight (the money shot)

A background poll fired the moment ≥2 workspaces went non-empty. Snapshotting the
siblings first, then reading:

```markdown
| Workspace      | Change   | Conflict | Files | Status    | Workload                                            |
| -------------- | -------- | -------- | ----- | --------- | --------------------------------------------------- |
| wt-absorb      | kostkqrq | —        | 1     | in-flight | /opsx:apply jj-absorb-fixup                          |
| wt-checkpoint  | mmokuuvl | —        | 1     | in-flight | /opsx:apply jj-op-checkpoint                         |
| wt-guard-role  | kqsruokz | —        | 2     | in-flight | /opsx:apply workspace-aware-guard-role-enforcement   |
| wt-stacked-pr  | omvttolz | —        | 0     | in-flight | /opsx:apply jj-stacked-pr                            |
```

Three workers actively writing files; `wt-stacked-pr` still spinning up. No
conflicts, no staleness — **physical isolation holding while four agents edit the
same repo concurrently.**

### Pass 3 — one done, three in-flight (the join in action)

After the first worker reported, its manifest slice flipped to `done`:

```markdown
| Workspace      | Change   | Description (live)                          | Conflict | Files | Status    |
| -------------- | -------- | ------------------------------------------- | -------- | ----- | --------- |
| wt-guard-role  | kqsruokz | feat(jj-guard): enforce orchestrator-only … | —        | 2     | done ✓    |
| wt-absorb      | kostkqrq | (in progress)                               | —        | 3     | in-flight |
| wt-checkpoint  | mmokuuvl | (in progress)                               | —        | 4     | in-flight |
| wt-stacked-pr  | omvttolz | (in progress)                               | —        | 4     | in-flight |
```

The **Description / Conflict / Files** columns come from live `jj` (always the
source of truth); the **Status** column is the manifest join. A stale manifest
can never misreport change state — that is the two-source design.

### Final pass — all done

All four described and `done`, conflict-free in their own workspaces. The
`jj log` of the four sibling bookmarks shows the textbook fan-out shape:

```
○  mmokuuvl  feat/jj-op-checkpoint  | feat(jj-concurrent): add /jj-checkpoint and /jj-rewind …
│ ○  kostkqrq  feat/jj-absorb        | feat(jj-absorb): add /jj-absorb amend-after-review skill
├─╯
│ ○  omvttolz  feat/jj-stacked-pr    | feat(jj-concurrent): add /jj-stacked-pr orchestrator skill
├─╯
│ ○  kqsruokz  feat/guard-role       | feat(jj-guard): enforce orchestrator-only bookmark/push …
├─╯
◆  xpwksvvy  main  | Merge pull request #1 …
```

**Timings (worker self-reported):** guard-role ~162s, stacked-pr ~217s, absorb
~254s, checkpoint ~274s. They overlapped throughout — wall-clock ≈ the slowest,
not the sum.

---

## 4. What the workers found (real outcomes, not just "done")

- **guard-role** — 10/10 tasks, smoke-tested: a worker workspace blocks
  `jj bookmark set`/`jj git push` (exit 2) while allowing `jj new`/`jj describe`;
  the orchestrator workspace allows bookmark+push; the universal floor (raw
  `git commit`, `jj resolve`, `rm -rf .jj`) blocks for both roles; fails open
  outside a jj repo. Touched only `jj-guard.sh` → **no shared-file conflict.**
- **jj-absorb** — 14/14 tasks. **Real-world finding:** jj 0.42.0 ships
  `jj absorb` but **not** `jj absorb --dry-run`. The skill's preview-before-mutate
  preflight correctly fires its `BLOCKER` on this version (the spec-mandated
  outcome) — so the case study surfaced a genuine version constraint, not a bug.
- **jj-stacked-pr** — 17/18 tasks; `openspec validate` passes. It correctly
  **deferred task 7.2** (a live PR exercise needing authenticated `gh` + push —
  forbidden by the worker contract) and left it for the orchestrator.
- **jj-op-checkpoint** — 21/21 tasks; new `/jj-checkpoint` + `/jj-rewind` skills,
  round-trip `jj op restore` exercised in a scratch repo.

---

## 5. Reconcile — integration that never halts

Stack the four onto `main`, clean one first. **jj rebases always exit 0**;
conflicts become first-class objects in the resulting commits, not a blocked
pipeline:

```bash
jj rebase -s kostkqrq -d kqsruokz    # absorb onto guard-role   → clean (disjoint files)
jj rebase -s omvttolz -d kostkqrq    # stacked-pr onto absorb   → CONFLICT recorded, exit 0
jj rebase -s mmokuuvl -d omvttolz    # checkpoint onto stacked-pr → CONFLICT recorded, exit 0
```

The stack afterwards — the two upper commits carry first-class conflicts:

```
×  mmokuuvl  ✗CONFLICT feat(jj-concurrent): add /jj-checkpoint and /jj-rewind …
×  omvttolz  ✗CONFLICT feat(jj-concurrent): add /jj-stacked-pr orchestrator skill
○  kostkqrq  ✓ feat(jj-absorb): add /jj-absorb amend-after-review skill
○  kqsruokz  ✓ feat(jj-guard): enforce orchestrator-only bookmark/push for workers
```

### Resolving by editing markers (never `jj resolve`)

Materialize a conflicted commit (`jj edit <change> --config
ui.conflict-marker-style=git`) and the two files show 2-sided markers. Both
merges were mechanical:

- **`plugin.json`** — base `0.2.0`; each side bumped to `0.3.0` and appended its
  own skill to the description. Resolution = `0.3.0` + **all four** skill
  descriptions.
- **`jj-delegate/SKILL.md §5`** — each side inserted its reconcile-tail prose
  (`/jj-absorb` amend step; `/jj-stacked-pr` stacked-submit paragraph;
  `/jj-checkpoint`+`/jj-rewind` risky-step save point). Resolution = keep all
  three additions in a coherent order.

A worth-noting guard interaction: `jj resolve --list` was **blocked by the guard
hook** — it string-matches `jj resolve` as interactive (it does not parse flags).
That is the intended posture: the skill resolves by editing markers directly, so
the block cost nothing. (A known guard limitation, documented as such.)

After editing, `jj util snapshot` records each resolution; the child commit
re-evaluates against the now-resolved parent. Final state — **every commit
clean, zero markers left:**

```
@  kqnrutvo  (empty)            ← orchestrator's docs commit starts here
○  mmokuuvl  ✓ feat(jj-concurrent): add /jj-checkpoint and /jj-rewind …
○  omvttolz  ✓ feat(jj-concurrent): add /jj-stacked-pr orchestrator skill
○  kostkqrq  ✓ feat(jj-absorb): add /jj-absorb amend-after-review skill
○  kqsruokz  ✓ feat(jj-guard): enforce orchestrator-only bookmark/push for workers
◆  xpwksvvy  main
```

This is the exact scenario a shared-working-tree model (e.g. GitButler) cannot do
safely: four concurrent same-repo writers never raced (separate workspaces); the
only contention surfaced at **integration**, as a first-class conflict resolved
deliberately.

---

## 6. Results

- **plugin.json → 0.3.0**, valid JSON, description covers all four new steps.
- **7 skills** in `jj-concurrent` (added `jj-absorb`, `jj-checkpoint`,
  `jj-rewind`, `jj-stacked-pr` alongside `jj-delegate`, `jj-fleet`, `jj-pr`).
- **All four OpenSpec changes validate** (`Change '<name>' is valid`).
- **Four workspaces torn down** (`jj workspace forget` + `rm -rf` the dir —
  never the `.jj` store); commits preserved via their bookmarks in the stack.
- Documentation folded into README/MANUAL and the four changes removed from
  `ROADMAP.md` (orchestrator as the single doc writer — so the shared doc files
  never became a fifth conflict).

**~30s of orchestrator setup, four workers in parallel, one deliberate 3-way
conflict resolved in two edits, zero lost work, zero stalls, zero raw git.**

---

## Appendix — commands reference

```bash
# Provision (orchestrator)
jj git fetch
jj workspace add -r main ../wt-<slug>
jj bookmark create feat/<slug> -r <workspace-@>
# … write .jj-agent-plan.json …

# Observe (read-only, any time)
for ws in ../wt-*; do jj -R "$ws" util snapshot; done   # /jj-fleet snapshot pass
jj workspace list --no-pager                            # stale flags
jj log -r '<ws @>' --ignore-working-copy --no-pager     # held change + conflict flag

# Reconcile (orchestrator)
jj rebase -s <src> -d <dest>                            # never halts
jj edit <conflicted> --config ui.conflict-marker-style=git
#   …edit markers in files…  then:
jj util snapshot                                        # records the resolution

# Teardown (orchestrator)
jj workspace forget <name> && rm -rf ../wt-<slug>
```

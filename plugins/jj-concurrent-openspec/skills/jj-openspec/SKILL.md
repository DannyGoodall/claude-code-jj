---
name: jj-openspec
description: |
  Background an OpenSpec workflow verb in its own jj workspace via the
  jj-concurrent orchestrator. Maps the verb to a shape (implementing vs
  authoring) and the right reconcile tail. For `apply`, can fan a single
  change out across several concurrent jj workers — one workspace per
  separable tasks.md group — and reconcile them into one change branch.
  Triggers: /jj-openspec <verb> [change], "apply <change> on a jj workspace",
  "fan out apply across task groups", "draft a proposal in the background",
  "propose/new/ff <change> with a jj worker". Requires: a jj repo (ideally
  colocated), the jj-concurrent plugin (jj-delegate + jj-workspace-worker),
  an openspec/ directory, and the opsx skills available in-session.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-openspec — OpenSpec verbs on jj workspaces

A thin binding: resolve the OpenSpec-specific parameters, then hand off to the
`jj-delegate` skill (jj-concurrent plugin) with `/opsx:<verb> <args>` as the
workload. This skill owns nothing about jj/workspace choreography (that is
jj-delegate's) and nothing about OpenSpec artifact rules (those are the opsx
skills'). If either changes, this binding should not need to.

## The verb → shape map

OpenSpec verbs share inference (change-name resolution, bookmark naming, issue
tracker) and differ only in **shape** — what the worker produces and how you
reconcile it:

| Verb(s) | Shape | What the worker produces | Reconcile tail |
|---------|-------|--------------------------|----------------|
| `apply` | **Implementing** | code changes + ticked tasks.md | integrate → `/opsx:verify` → issue-tracker update → `/jj-pr` push/PR |
| `propose` / `new` / `ff` | **Authoring** | the change artifacts under `openspec/changes/<name>/` (proposal/design/specs/tasks) | surface artifacts for review; bookmark only; **no verify, no merge-to-main** (nothing is implemented yet) |
| `explore` | **Interactive** | (a thinking partner — file output only when asked) | NOT a default background candidate. Only background as "autonomous exploration → a written findings doc" when the user explicitly asks. Otherwise run it inline, not via a worker. |

The **implementing (`apply`)** shape supports two **distributions**:

- **single-worker** (default and fallback) — one worker for the whole change.
- **per-group fan-out** (optimization) — one concurrent worker per *separable*
  `tasks.md` group, all reconciled into **one** change branch.

Fan-out is opt-in **by data**, default-safe **by policy**: it is attempted only
when separability detection (§A) finds ≥2 qualifying separable groups; otherwise
apply transparently runs the single-worker distribution. Fan-out never changes
the final reconciled result relative to single-worker — it only changes how the
work is distributed. Only the `apply` shape fans out; `propose`/`new`/`ff` and
`explore` are always single-worker / inline.

## 1. Resolve the verb + change

- **verb** — first token of the arguments (`apply`, `propose`, `new`, `ff`,
  `explore`). If absent, infer from context; if still unclear, ask.
- **change name** — in order: explicit argument → the change under discussion
  → for implementing verbs, `openspec list --json` filtered to changes with
  unticked tasks (use it if exactly one); else ask.
- For **apply**: validate the change exists and is apply-ready
  (`openspec status --change "<name>" --json`). If apply-required artifacts are
  missing, stop and tell the user to author the change first (a `propose` run).
- For **propose/new/ff**: the change may not exist yet — that is the point.

## 2. Derive the bookmark

- **Implementing**: `feat/<short-slug>` from the change name.
- **Authoring**: `change/<short-slug>` (signals it is a proposal, not an
  implementation, so reviewers and the merge step treat it accordingly).

## 3. Base revision — what the worker's workspace must contain

This is where the verbs differ in provisioning (and where jj removes the git
seed-commit ceremony — see jj-delegate §3):

- **apply**: the change's `openspec/changes/<name>/` artifacts must already
  exist on the base revision. They are usually already present and snapshotted
  in `@` (jj has no untracked limbo). Base the worker on the curated revision
  that holds them: pass `jj-delegate` a base-rev of `@` (after confirming `@`
  is clean) or a dedicated change-rev. If the artifacts are NOT yet committed
  anywhere clean, describe the current change first (`jj describe -m
  "docs(openspec): <name> change artifacts"`) so there is a named revision to
  base on — this is the jj-light analog of the old seed commit (a describe, not
  an add+commit dance).
- **propose/new/ff**: base on trunk; the worker CREATES the artifacts in its
  workspace.

## A. Separability detection (apply only — picks the distribution)

Before dispatch, the `apply` shape decides **single-worker vs fan-out** by
analysing the change's `tasks.md`. This is the only OpenSpec-aware decomposition
the binding owns; everything physical stays jj-delegate's. The procedure is
cheap, conservative, and biased toward the safe single-worker fallback.

1. **Partition into task groups.** Read the change's `tasks.md` and split it into
   groups by its structure — each top-level `##` heading / numbered section
   (`## 1. …`, `## 2. …`) is one group, with its `- [ ]` task lines as members.
   If `tasks.md` has no group structure (a flat list, no `##`/numbered sections),
   treat the whole file as a single group ⇒ no fan-out.
2. **Derive each group's file area.** From the group's task lines, collect every
   target path the tasks reference: explicit file/dir mentions (e.g.
   `src/api/foo.ts`, `docs/**`, a `path/like/this`) **plus** the file areas of
   the spec deltas that group implements (the `specs/<capability>/…` the tasks
   point at). Record the union as the group's *file area*. If a group's tasks
   name no derivable path at all, record its area as **undeterminable**.
3. **Separability test.** Two groups are **separable** only when BOTH hold:
   - their file areas are **disjoint** (no path/glob intersection), AND
   - there is **no stated cross-group ordering dependency** (neither group's
     prose says it depends on / follows / requires the other's completion).
   An **undeterminable** area is never disjoint from anything ⇒ any group with an
   undeterminable area is **non-separable**. Overlapping areas ⇒ non-separable.
   A stated ordering dependency ⇒ non-separable. Fail safe toward single-worker
   whenever the test is unsure.
4. **Compute the separable-group set + minimum-benefit gate.** Collect the groups
   that are mutually separable (pairwise-disjoint, dependency-free, determinable).
   Apply the gate: fan out only when the separable set has **≥2 groups of
   non-trivial size** (skip near-empty / single-task groups not worth a whole
   workspace). If the gate is **met** → mark the change for **fan-out** with that
   group set. If **not met** → mark the change for **single-worker**.

This detection is policy, not a spec requirement: the gate (group count / size)
is a tunable knob, and any ambiguity resolves to single-worker.

## 4. Hand off to jj-delegate (distribution-aware)

Invoke the `jj-delegate` skill. The shape from §1 and the distribution from §A
decide whether you hand off **one** workload or **several concurrent siblings**.

### 4a. Single-worker distribution (default / fallback — all verbs)

This is the existing hand-off, **unchanged**:

- **workload (skill form)**: `/opsx:<verb> <change-or-args>` — the worker
  invokes the opsx skill (fallback skill names: `opsx:apply` →
  `openspec-apply-change`, `opsx:propose` → `openspec-propose`, etc.). For
  `apply`, the dispatch brief tells the worker to work through `tasks.md` via
  the skill (which owns task selection + checkbox discipline), never hand-edit
  artifacts outside it, and commit the ticked `tasks.md` alongside the
  implementation so progress travels with the workspace.
- **bookmark**: from §2.
- **base-rev**: from §3.

jj-delegate runs the confirm → provision → dispatch (background by default) →
reconcile lifecycle. Every non-fan-out case lands here: one group, overlapping
areas, an ordering dependency, an undeterminable area, an ungrouped `tasks.md`,
or any verb other than `apply`.

### 4b. Per-group fan-out distribution (apply, gate met from §A)

When §A marks the change for fan-out, hand jj-delegate **one group-scoped
workload per separable group**, as **concurrent siblings** all based on the
change's proposal revision (the §3 apply base-rev). For each separable group N:

- **workload (group-scoped)**: `/opsx:apply <change>` with an explicit
  instruction to **implement ONLY group N's tasks and mark ONLY group N's
  checkboxes** in `tasks.md`, leaving all other groups' tasks and checkboxes
  untouched, and to stay within group N's recorded file area. (No `--group`
  flag exists on `/opsx:apply` today; the scoping lives in the instruction
  string — see the binding's design Open Questions for a possible future flag.)
- **bookmark / base-rev**: the same change bookmark (§2) and the same proposal
  base-rev (§3) for every sibling — they are siblings on one branch, not
  separate branches.

Hand all group-scoped workloads to `jj-delegate` as concurrent siblings and let
it own **every** provisioning, dispatch, and integration choreography
(`jj workspace add -r <base-rev>` per group, background dispatch, never-halting
integration). The binding adds no jj/workspace mechanics; it only supplies the
per-group workload strings and the reconcile policy in §5.

## 5. Reconcile tail (after jj-delegate integrates the worker's commits)

**Implementing (`apply`)**, in the primary workspace. The verify → push/PR tail
runs **exactly once over the reconciled change branch**, identically for both
distributions — the only difference is how many workers feed into it.

**Reconcile-into-one-change (fan-out only — first):**

1. Integrate each group worker's commits, as they report, into **ONE** change
   branch for the change (stack / merge the sibling changes onto one another) —
   never separate per-group branches. This is the same branch the single-worker
   path would have produced.
2. Disjoint areas reconcile without conflict. On any overlapping content, rely
   on jj's **never-halting** integration: the integration still succeeds (exit
   0) and jj records the overlap as a **first-class conflict** on the change.
   Resolve it deliberately by **editing the conflict markers in the file**
   before proceeding — **never** the interactive `jj resolve`.
3. `tasks.md` is shared across groups, but each worker marked ONLY its own
   group's checkboxes, so the checkbox hunks are **disjoint lines** and reconcile
   cleanly. If a true overlap appears in `tasks.md` (or anywhere), resolve it by
   editing markers as in step 2 before continuing.
4. Only once every group's commits are reconciled onto the one change branch
   (every group's tasks present and ticked) do you run the verify/push tail
   below — once, over the combined result.

(Single-worker distribution skips the reconcile-into-one step: jj-delegate has
already integrated the lone worker onto the change branch.)

**Verify → push/PR tail (both distributions):**

1. Run `/opsx:verify <change>` against the integrated result (check out / log
   the worker's commits; jj makes them visible without a checkout dance).
2. If the project links changes to an issue tracker (e.g. a Linear umbrella
   issue per change), update it with the push/PR link and status.
3. Run the push-and-PR step [`/jj-pr <bookmark>`](../../../jj-concurrent/skills/jj-pr/SKILL.md):
   it pushes the bookmark (`jj git push -b <bookmark>`, handling one-time
   `jj bookmark track`) and creates-or-updates the GitHub PR via `gh`, sourcing
   the body from this change's `openspec/changes/<name>/proposal.md`. Report:
   change, bookmark, PR, verify outcome, remaining unticked tasks.

**Authoring (`propose`/`new`/`ff`)**, in the primary workspace:

1. Run `openspec validate <change>` on the drafted artifacts.
2. Surface them for review — either push the `change/<slug>` bookmark and open
   a draft PR, or simply report the new `openspec/changes/<name>/` tree for the
   user to inspect. Do NOT merge to main and do NOT verify (there is no
   implementation yet).
3. Report: change name, the artifacts created, validate outcome, and the
   natural next step (`/jj-openspec apply <name>` once the proposal is agreed).

## Variants

- **Background** is the default (the session stays free; another `/jj-openspec`
  or `/jj-delegate` can run a second independent slice concurrently).
- **Foreground** ("and wait") — passes through to jj-delegate's foreground mode.
- **Relay** (author then apply): run `/jj-openspec propose <name>`; once the
  proposal is agreed, run `/jj-openspec apply <name>` — the apply worker bases
  on the revision the authoring run produced.

## Worked example: two disjoint groups fanned out into one branch

A change `add-export` has this `tasks.md`:

```
## 1. Export API
- [ ] 1.1 Add `src/api/export.ts` endpoint
- [ ] 1.2 Wire `src/api/router.ts` to the export endpoint

## 2. Export docs
- [ ] 2.1 Document the export endpoint in `docs/export.md`
- [ ] 2.2 Add a usage example to `docs/examples/export.md`
```

`/jj-openspec apply add-export` resolves the verb (apply → implementing) and the
change, derives bookmark `feat/add-export`, and bases on the proposal revision.

**Separability detection (§A):** Group 1's file area is `src/api/**`; Group 2's
is `docs/**`. The areas are **disjoint**, neither group's prose states a
dependency on the other, both groups are non-trivial — so the separable set is
`{Group 1, Group 2}`, ≥2, gate met ⇒ **fan-out**.

**Dispatch (§4b):** two concurrent siblings to `jj-delegate`, both on
`feat/add-export` / the proposal base-rev:

- Worker A — `/opsx:apply add-export`, instructed to implement ONLY group 1's
  tasks and tick ONLY 1.1/1.2.
- Worker B — `/opsx:apply add-export`, instructed to implement ONLY group 2's
  tasks and tick ONLY 2.1/2.2.

**Reconcile (§5):** as each reports, jj-delegate integrates its commits onto the
one `feat/add-export` branch. Worker A's `src/api/**` edits and Worker B's
`docs/**` edits are disjoint ⇒ no conflict. In `tasks.md`, A ticked lines 1.1/1.2
and B ticked lines 2.1/2.2 — disjoint hunks ⇒ they merge cleanly into a single
fully-ticked `tasks.md`. Verify → push/PR runs **once** over the combined branch.

The resulting branch is identical to what a single worker would have produced —
all four tasks done on `feat/add-export` — only the work was distributed across
two workspaces. (Had Group 2 also touched `src/api/**`, or said "after the API
lands", detection would mark them non-separable and apply would run the
single-worker path instead.)

## Fallback guarantee (identical end result)

Fan-out is **always** an optimization, never a correctness requirement. The
single-worker distribution (§4a) is the default and the fallback for **every**
non-fan-out case: one task group, overlapping file areas, a stated ordering
dependency, an undeterminable area, an ungrouped `tasks.md`, the gate not met,
or any verb other than `apply`. Whichever distribution runs, the reconciled
change branch ends with the **same** completed tasks and the **same** verify →
push/PR tail — fan-out only changes how the work is distributed, never the
result. If fan-out detection is ever unsure, it resolves to single-worker.

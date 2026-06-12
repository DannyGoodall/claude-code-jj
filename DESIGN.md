# ADR 0002 — Multi-agent orchestration on jj (Jujutsu) workspaces

- **Status:** Accepted (proposed 2026-06-08; built and shipped). The four-layer architecture below was implemented as the marketplace's four plugins — `jj-concurrent`, `jj-concurrent-openspec`, `jj-concurrent-linear`, and the later `jj-lifecycle` — with the `jj-delegate` mechanism, the `jj-openspec` binding, and the guard + snapshot hooks all live. This ADR records the design as decided; the live `SKILL.md` files, plugin manifests, `MANUAL.md`, and `ROADMAP.md` track what subsequently shipped on top of it.
- **Context note:** This is a *process/tooling* ADR (how this repo is developed by multiple Claude agents at once), not a product-domain decision. It records the design we will build before we build it.
- **Supersedes / replaces direction:** the Graphite (`gt`) + git-worktree orchestration captured in the archived memory at `docs/protected-memory/graphite-tooling-archived-2026-06-08.md` (the `gt-delegate` / `gt-apply` / `gt-guard` fork). That work is sound but its substrate — git worktrees + Graphite restacks — carries hazards this ADR's substrate removes.
- **Related:** OpenSpec (`opsx:*` skills); Linear (`Points2026` team) issue/PR convention; the read-only jj reference plugin `jj-vcs@toolbox` (schpet/toolbox); ADR 0001 (test strategy the workers must honour).

## Context

We want **multiple Claude agents working on multiple simultaneous changes** in this repo, coordinated by an orchestrator, each producing reviewable PRs. We built this once on Graphite: an **orchestrator** in the primary checkout dispatched **workers**, one per linked **git worktree** (sibling branches off trunk), with a guard hook enforcing roles, background dispatch by default, an OpenSpec binding (`gt-apply`) over a generic mechanism (`gt-delegate`), and Linear umbrella/sub-issues.

Two alternative substrates were then evaluated against the same requirement:

- **GitButler** — rejected as the concurrency substrate. Its virtual branches give *logical* isolation (one shared working tree, changes assigned to lanes post-hoc), not *physical* isolation. Two agents editing the same file at the same moment race at the filesystem level — a lost write GitButler never sees as a conflict. Excellent for a human organising their own work; unsafe for N autonomous agents hammering one working directory.
- **jj (Jujutsu)** — chosen. jj is "git worktrees with the automation-hostile sharp edges removed." Its **workspaces** restore the physical isolation GitButler lacked, while its model removes the specific hazards that made the Graphite/worktree orchestration the brittle layer.

Four jj properties drive this decision, each against a pain we actually hit:

| jj property | What it removes |
|---|---|
| **Workspaces** (`jj workspace add`) — separate directory + working-copy commit per agent, shared `.jj`/`.git` store | GitButler's shared-tree write race. Each agent edits its own directory. |
| **Automatic working-copy snapshot** — every jj command commits the working copy if it changed; no index, no staging | The lost-uncommitted-work risk *and* the git seed-commit ceremony (see Decision §6). |
| **Lock-free concurrent ops** (operation-log 3-way merge) — two jj processes never corrupt state | The restack-while-checked-out failure that forced Graphite's whole prune-before-restack guard. |
| **First-class conflicts** — rebase/merge *always succeeds*; conflicts live in commits, resolved later | The reconcile halt: `gt sync` stopping mid-cascade on conflict needing triage. |

The one caveat carried forward honestly: jj is younger; colocated (jj+git) concurrency is officially *under-tested* and "might conceivably lose some bookmark pointers" (never commits — content-addressed); and real multi-agent users report occasional unexplained multi-minute `jj` hangs. The role discipline and resume pattern below mitigate all three.

## Decision

### 1. Four-layer architecture — depend on the substrate skill, build the rest

| Layer | Provider | Status |
|---|---|---|
| **1. jj vocabulary + agent-hang rules** (every subcommand; `--ignore-working-copy` for reads; non-interactive-only; `--git`/`json(self)` output) | **`jj-vcs@toolbox` (schpet) — used UNMODIFIED** | exists |
| **2. Mechanism: `jj-delegate`** — workspace lifecycle, role split, dispatch, integrate | **we build** | new |
| **3. Binding: `jj-openspec`** — OpenSpec verb → shape → workspace + reconcile tail; Linear | **we build** | new |
| **+ Enforcement: guard hook + snapshot hook** | **we build** | new |

**Depend, do not fork.** The Graphite fork carried permanent merge surface because the worker agent and guard hooks lived *inside* the plugin we had to modify. schpet's jj plugin is pure read-only reference, **auto-regenerated from jj manpages** (`generate-jj-docs.ts`, ~130 files) — forking it would be maximally painful to track. So we install it as-is (the worker's command knowledge, a soft dependency the way `gt-stack-worker` depended on `opsx`), and put everything novel in our own sibling marketplace.

### 2. `jj-delegate` (mechanism) — workflow-agnostic, one worker, one workspace

Direct port of `gt-delegate`, simplified by jj. Lifecycle:

1. **Resolve** workload (skill-form `/opsx:apply <change>` or plain spec-form), bookmark name, workspace path.
2. **Provision:** `jj workspace add -r <base-rev> ../wt-<slug>` then (orchestrator-side) create the bookmark. Base-rev is the curated revision carrying any inputs the workload needs (§6).
3. **Dispatch** ONE `jj-workspace-worker` subagent into that workspace — **background by default** (orchestrator keeps the session; another `jj-delegate` can run a sibling concurrently).
4. **Integrate** on report: the worker's commits are already visible in the shared store; the orchestrator rebases/lands them. **Integration never halts** — conflicts become first-class objects resolved deliberately, not a blocked pipeline.
5. **Report** to the user.

Workload shapes are identical to Graphite's: a worker can run any skill, so `opsx:propose|new|ff|apply` all dispatch through this one mechanism. No per-verb macro.

### 3. `jj-openspec` (binding) — one entry point, verb dispatches to a shape

The OpenSpec verbs split into **two shapes** that share inference (change-name resolution → args → conversation → `openspec list`; bookmark naming; Linear umbrella) and differ only in the **reconcile tail**:

| OpenSpec verb | Shape | Reconcile tail |
|---|---|---|
| `apply` | **Implementing** | integrate → `opsx:verify` → Linear update → PR. (The gt-apply path.) |
| `propose` / `new` / `ff` | **Authoring** | surface drafted artifacts for review; bookmark only; **no verify, no merge-to-main** (nothing is implemented yet — it is a proposal). |
| `explore` | **Interactive (special)** | NOT a default background candidate (it is a thinking partner). Optional "autonomous exploration → findings doc" mode only when explicitly asked. |

So: **one `jj-openspec` binding skill that branches verb → shape**, over the single generic `jj-delegate`. This is barely more than `gt-apply` was, and keeps all OpenSpec knowledge in one place rather than scattering N macro commands.

### 4. Role split — survives from Graphite, and shrinks

| Role | Lives in | Owns |
|---|---|---|
| **Orchestrator** | primary workspace | workspace lifecycle (`jj workspace add`/`forget`), **all bookmark/ref ops**, `jj git push`, integration, the agent-plan manifest, Linear |
| **Worker** | one jj workspace each | edits in its directory + shaping **its own** commits (`jj new`/`jj describe -m`). Never touches bookmarks, never pushes, never raw git. |

The guard that enforces this is **smaller than `gt-guard`**. Graphite's guard mainly existed to block repo-wide restacks while worktrees were attached (restack rewrites refs and *fails* on a branch checked out elsewhere). jj's op-log makes concurrent ops safe and its rebase cannot fail, so that whole hazard class evaporates. The remaining guard duties:

- Block **raw `git`** commands inside a workspace (the cardinal colocated-jj sin — corrupts jj state).
- Block **interactive jj** that hangs automation (`jj resolve`, `jj arrange`, `jj diffedit`, `jj config edit`, `-i` variants, editor prompts) — the hang-trap list schpet's skill already enumerates.
- Keep **bookmark / `jj git push`** operations orchestrator-only.

### 5. The snapshot hook — required, not optional

jj's safety net is *pull*, not *push*: it snapshots the working copy **when a jj command runs**. An agent that edits files and then crashes **before any jj command** loses that last edit. We close the gap with a **PostToolUse hook running `jj util snapshot`** (the script-grade primitive: snapshots only if changed) after every `Edit|Write|MultiEdit`. With this hook, every agent edit is auto-captured into the workspace's working-copy commit — the property GitButler claimed but could not safely deliver, here backed by physical isolation. Recovery surface: `jj evolog` (working-copy history), `jj op restore` (whole-repo undo).

This makes **resume-in-place bulletproof**: a stalled worker's last edit is already a commit, so a fresh worker continues in the same workspace with nothing to salvage by hand.

### 6. Seeding — ceremony gone, intent remains (one flag)

The git seed-commit existed because a fresh worktree contained only *committed* files, so a just-proposed (untracked) `openspec/changes/<name>/` was invisible and had to be `git add`-ed + committed first.

Under jj this root cause is gone: **no staging, auto-snapshot, content-addressed — there is no untracked limbo.** The artifacts are part of `@` as soon as any jj command (or the snapshot hook) runs. What remains is a one-flag *intent*: `jj workspace add` defaults to basing the new workspace on the **parent** of the current working-copy commit, which would miss artifacts sitting in `@`. So base it explicitly:

```
jj workspace add -r @ ../wt-<slug>      # or -r <curated change-rev>
```

**New discipline (the jj-flavoured "no stage-all"):** because jj auto-snapshots *everything not gitignored* into `@`, the orchestrator must base workers on a **clean, curated** revision — never a `@` polluted with incidental `.claude/settings.local.json` churn or other in-flight baggage. The failure mode shifts from Graphite's silent "worker has no artifacts" to "base on the right revision" — louder and one flag wide.

### 7. Colocated repo; orchestrator owns all refs

We keep a **colocated** repo (`jj git init --colocate`) so GitHub/PRs/`gh` still work. This is jj's officially under-tested concurrency zone, so the mitigation is exactly the role split: workers only ever **edit + auto-commit in their own workspace**; every `jj bookmark` / `jj git push` / ref mutation **serialises through the orchestrator** in the primary workspace. Commits are never at risk (content-addressed); only bookmark pointers are, and only the orchestrator moves them.

### 8. Linear + dispatch discipline — carried over verbatim

Umbrella issue per change + sub-issues; PR cross-linked both ways; background dispatch by default with a foreground "and wait" fallback; commit-per-task-group so the workspace is the durable progress record; the worker contract (containment, command hygiene, never raw git) lives in the worker agent definition, not restated per dispatch.

## Consequences

**Positive**

- The GitButler showstopper (shared-tree write race) is gone — physical isolation via workspaces.
- The Graphite fragilities are gone: no prune-before-restack hazard (lock-free ops), no reconcile halt (first-class conflicts), no seed-commit dance (auto-snapshot), near-free resume-in-place (snapshot hook).
- One shared object store: no N× clone, no N× `bun install` is *still* required per workspace (working copies are separate directories — see trade-offs), but commits are instantly visible across workspaces for orchestrator situational awareness (`jj log` over all workspaces).
- Smaller guard; the dangerous-op class it once policed mostly cannot occur.
- The mechanism/binding split keeps OpenSpec and jj decoupled, as it did for Graphite.

**Negative / trade-offs**

- **Youth & under-tested colocated concurrency.** Mitigated by orchestrator-owns-all-refs; commits are safe regardless.
- **Reported `jj` hangs** in heavy multi-agent use. Mitigated by the existing watchdog + resume-in-place (safer here than under Graphite).
- **New hazard: stale working copies.** Editing a change that is an ancestor of another workspace marks it stale → `jj workspace update-stale`. This is the jj analog of prune-before-restack, but *gentler*: a recoverable state, not a failed operation. `jj log` does not auto-snapshot sibling workspaces — the orchestrator needs a snapshot-all-then-log alias for accurate cross-workspace status.
- **Per-workspace environment still needed.** Each workspace is a real directory → its own `node_modules`, its own `.env.local` copy. The disk/`bun install` cost is the same as git worktrees; only the VCS hazards differ.
- **We build layers 2–3 + hooks ourselves.** schpet/jj-vcs is layer 1 only.

## Appendix — jj workspaces vs git worktrees (high level)

The role of workspaces here is **major**: they are the isolation backbone, the thing that makes concurrent agents safe. Conceptually:

| | git worktree | jj workspace |
|---|---|---|
| **Tied to** | a **branch** (refuses if that branch is checked out elsewhere) | a **revision** / working-copy commit (jj moves it freely) |
| **Shared store** | one `.git` | one `.jj` (+ colocated `.git`) |
| **Working copy** | files **+ an index/staging area** | files **+ an auto-snapshotted working-copy commit** (no index, no staging) |
| **Uncommitted work** | lives in the dir/index; lost if clobbered | snapshotted into the working-copy commit on every jj command (or our hook) → recoverable |
| **Concurrent ops on shared repo** | restack/rebase rewrites refs repo-wide and **fails** on a branch checked out elsewhere → the prune-before-restack hazard | **lock-free** op-log; rebases never fail (first-class conflicts); other workspaces merely go **stale** |
| **The danger to police** | **ref rewriting across worktrees** (what `gt-guard` enforced) | **staleness** (`jj workspace update-stale` — recoverable, not a failure) |
| **Integration conflict** | merge **halts**, manual resolve, pipeline blocks | integration **always succeeds**, conflict stored in a commit, resolve later |
| **Cleanup** | `git worktree remove` + prune; harness leaves changed worktrees locked | `jj workspace forget` + delete dir; abandoned working-copy commits are just commits |

The one-line shift: **a worktree pins a branch and the failure mode is a hard, blocking ref conflict; a workspace pins a revision and the failure mode is soft, recoverable staleness.** Almost every place the Graphite design needed a guard or a strict ordering, jj turns the underlying operation into one that cannot fail or corrupt — so the orchestration gets simpler, not just different.

## Open questions (to resolve before/while building)

1. **Smoke spike first.** Two jj workspaces, two background agents, integrate — de-risk the youth/hang concern before committing to the full plugin (the way we smoke-tested background dispatch on Graphite).
2. **Sparse workspaces as soft partitions?** `jj workspace add --sparse-patterns` can scope a worker's working copy to just its files — a lighter-touch answer to file-partitioning than a hard path guard. Worth evaluating, not assuming.
3. **`jj op` integration mechanics** (`jj op integrate`, `--no-integrate-operation`) for the orchestrator's reconcile step — how much explicit control we want vs. jj's automatic op-log merge.
4. **Authoring-shape output review.** For `propose`/`new`/`ff` workers, decide whether artifacts are surfaced as a draft PR, a bookmark for inline review, or just reported — and whether the orchestrator runs `openspec validate` at reconvene.

## References

- Archived Graphite design: `docs/protected-memory/graphite-tooling-archived-2026-06-08.md`
- jj concurrency model: <https://docs.jj-vcs.dev/latest/technical/concurrency/>
- jj working copy / workspaces: <https://docs.jj-vcs.dev/latest/working-copy/>
- Snapshot-gap for agents (panozzaj): <https://www.panozzaj.com/blog/2025/11/22/avoid-losing-work-with-jujutsu-jj-for-ai-coding-agents/>
- jj for agents (slavakurilyak): <https://slavakurilyak.com/posts/use-jujutsu-not-git>
- Parallel agents on jj workspaces (geirsson): <https://geirsson.com/jj-workspaces>
- Substrate reference plugin (depend, unmodified): <https://github.com/schpet/toolbox/tree/main/plugins/jj-vcs>
- Minimal solo-agent jj skill (vocabulary precedent): <https://github.com/danverbraganza/jujutsu-skill>

## Concurrency axes (jj-openspec: pipeline vs fan-out) — full rationale

Compressed in the jj-openspec SKILL.md (§Two orthogonal concurrency axes,
§Fallback guarantee); preserved here in full.

The `apply` shape has two independent concurrency axes that compose without
coupling. They are **orthogonal**: the pipeline operates BETWEEN changes (one
worker per change, distinct bookmarks/revisions); fan-out operates INSIDE one
change (several workers per change, one shared bookmark). A pipeline member MAY
itself fan out internally, and neither policy needs to know about the other.
Use the pipeline to land a backlog of independent ready changes concurrently;
use fan-out to parallelize the disjoint task groups *within* one of those
changes.

Fan-out is **always** an optimization, never a correctness requirement. The
single-worker distribution is the default and the fallback for **every**
non-fan-out case: one task group, overlapping file areas, a stated ordering
dependency, an undeterminable area, an ungrouped `tasks.md`, the gate not met,
or any verb other than `apply`. Whichever distribution runs, the reconciled
change branch ends with the **same** completed tasks and the **same** verify →
push/PR tail — fan-out only changes how the work is distributed, never the
result. If fan-out detection is ever unsure, it resolves to single-worker.

The **pipeline** carries the same guarantee on the across-changes axis. It is
**always** an optimization, never a correctness requirement: it engages only
when the change-set resolution confirms ≥2 distinct apply-ready changes. The
**single-change apply** is the default and the fallback for **every**
sub-threshold case — a single change, an empty set after exclusions, or a set
that reduces to one after de-duplication / overlap exclusion. Applying a change
via the pipeline yields the **same reconciled result** for that change as
applying it on its own; the pipeline only changes that several changes are
applied concurrently, never any individual change's outcome. If the resolved
set ever reduces below two, apply runs the single-change path with no pipeline
overhead.

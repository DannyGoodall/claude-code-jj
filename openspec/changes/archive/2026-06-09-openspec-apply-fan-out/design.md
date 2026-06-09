## Context

The `jj-concurrent-openspec` plugin's `jj-openspec` skill maps an OpenSpec verb to a shape and hands a workload to the workflow-agnostic `jj-delegate` orchestrator. For `apply`, the implementing shape today dispatches exactly one `jj-workspace-worker` running `/opsx:apply <change>` for the whole change, then verifies, integrates, and pushes/opens a PR.

`jj-delegate` already supports concurrent siblings (background dispatch by default, one workspace per workload via `jj workspace add -r <base-rev>`) and never-halting integration (jj records conflicts as first-class objects rather than blocking). What is missing is an OpenSpec-aware policy that decomposes ONE change into several concurrent workloads and reconciles them into one change branch. This is the unique jj payoff: physical per-workspace isolation lets several writers progress one logical change at once, which a shared working tree (GitButler) or restack-while-checked-out worktrees cannot do safely.

A change's `tasks.md` is conventionally organized into task groups (numbered sections / headed groups), and OpenSpec convention (the project's "tasks.md API enumeration" lesson) maps verbs in spec scenarios to enumerated server-function tasks — so groups frequently align to disjoint file areas. That alignment is the lever this design pulls.

## Goals / Non-Goals

**Goals:**
- Let `/jj-openspec apply` split one change across several concurrent group-scoped workers when `tasks.md` groups touch disjoint file areas.
- Reconcile all group workers into ONE change branch, then run the existing verify → push/PR tail once.
- Preserve the exact single-worker behaviour as the default and the fallback; fan-out is a pure distribution optimization with an identical end result.
- Reuse `jj-delegate` primitives (concurrent siblings, base-revision provisioning, never-halting integration) without adding new jj/workspace mechanics.

**Non-Goals:**
- No new jj primitives, hooks, or worker-contract changes (`jj-workspace-worker` is untouched; it just receives a task-scoped workload string).
- No fan-out for the authoring shapes (`propose`/`new`/`ff`) or `explore`.
- No cross-change fan-out (that is plain `jj-delegate` of multiple changes); this is intra-change only.
- No automatic re-decomposition of `tasks.md` content; the binding reads the groups as authored, it does not rewrite them.

## Decisions

**Decision: Separability is decided from declared/derived file areas per task group, not from task semantics.**
The binding partitions `tasks.md` into groups (by its heading/numbering structure), derives each group's file area from the paths its tasks reference (explicit file/dir mentions and the spec deltas they implement), and marks two groups separable only when their areas are disjoint AND there is no stated cross-group ordering dependency. Rationale: a file-area test is cheap, conservative, and directly predicts integration conflicts. Alternatives considered: (a) static code analysis of intended edits — too heavy and unavailable pre-implementation; (b) trusting authors to tag groups `@parallel` — viable later but should not be required for v1. When an area is undeterminable, the group is non-separable (fail safe toward single-worker).

**Decision: Scope a worker to a group by narrowing its workload string, not by forking opsx.**
Each group worker runs the standard `/opsx:apply <change>` with an explicit instruction to implement ONLY group N's tasks and mark ONLY group N's checkboxes. Rationale: keeps the opsx skills and the worker contract unchanged; the binding owns only "which tasks". Alternative considered: a new `--group` flag on `/opsx:apply` — cleaner long-term but couples this change to an opsx change; deferred to Open Questions.

**Decision: Reconcile into one change branch by stacking siblings, conflicts resolved by the orchestrator.**
Group workers are concurrent siblings on the change's proposal revision; the orchestrator integrates them one onto another into a single change for the change (the same branch the single-worker path would produce). Disjoint areas reconcile without conflict; an unexpected overlap becomes a first-class conflict the orchestrator resolves by editing markers (never interactive `jj resolve`), exactly as `jj-delegate` already specifies. Rationale: reuses the never-halting integration contract verbatim. Verify runs once over the reconciled branch so the PR is identical in shape to single-worker.

**Decision: Fan-out is opt-in by data, default-safe by policy.**
The orchestrator attempts fan-out only when it finds ≥2 separable groups; otherwise it transparently runs the existing single-worker apply. Rationale: zero regression risk and no contract change to `/jj-openspec apply <change>`.

## Risks / Trade-offs

- [Mis-detected separability — two "disjoint" groups actually edit a shared file] → never-halting integration turns this into a first-class conflict at reconcile, which the orchestrator resolves deliberately; the end result still matches single-worker. Detection is conservative (undeterminable ⇒ non-separable) to keep this rare.
- [`tasks.md` checkbox contention — two workers both write `tasks.md`] → `tasks.md` is a shared file across all groups, so concurrent edits to it will conflict on reconcile by design; mitigation: each worker marks ONLY its own group's checkboxes, so the conflicting hunks are disjoint lines and reconcile cleanly (jj merges non-overlapping hunks), and any true overlap is resolved by the orchestrator.
- [Over-eager fan-out spawns many workspaces for tiny groups] → keep a minimum-benefit threshold (≥2 separable groups, and groups of non-trivial size) and otherwise fall back; tune as a policy knob, not a spec requirement.
- [Ordering dependencies hidden in prose] → when a dependency cannot be ruled out, treat the groups as non-separable (fallback), trading some parallelism for correctness.

## Migration Plan

Additive and behind a data condition — no migration. Existing `/jj-openspec apply <change>` invocations are unchanged unless the target change happens to have ≥2 separable groups, in which case the result branch is identical and only the distribution differs. Rollback is removing the fan-out branch from the binding, leaving the single-worker path intact.

## Open Questions

- Should `/opsx:apply` gain a first-class `--group`/`--tasks` scoping flag (cleaner than an instruction string), as a follow-up opsx change?
- Should authors be able to annotate `tasks.md` groups (e.g. `@area src/api`, `@depends-on`) to make separability explicit rather than derived? Derivation is sufficient for v1; annotations are a possible later refinement.
- What is the right minimum group size / count threshold before fan-out is worth the workspace overhead?

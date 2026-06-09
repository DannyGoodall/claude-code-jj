## Context

The `jj-concurrent-openspec` plugin's `jj-openspec` skill maps an OpenSpec verb to a shape and hands a workload to the workflow-agnostic `jj-delegate` orchestrator. For `apply`, the implementing shape dispatches one `jj-workspace-worker` running `/opsx:apply <change>` for ONE change, then verifies, integrates, and pushes/opens a PR.

`jj-delegate` already supports concurrent siblings (background dispatch by default, one workspace per workload via `jj workspace add -r <base-rev>`), explicit base-revision provisioning so a worker carries exactly the inputs it needs, and never-halting integration (jj records conflicts as first-class objects rather than blocking). What is missing is an OpenSpec-aware policy that takes a SET of independent changes and lands them concurrently.

This is the **across-changes axis** of concurrency. It is deliberately orthogonal to `openspec-apply-fan-out`, which is the **within-a-change axis** (one change split into per-task-group concurrent workers reconciled into one branch). Pipeline operates BETWEEN changes (one worker per whole change); fan-out operates INSIDE one change (several workers per change). The two compose without coupling: a pipeline member may itself fan out, but neither policy needs to know about the other.

The unique jj payoff is the same in both axes: physical per-workspace isolation lets several writers progress at once, which a shared working tree (GitButler) or restack-while-checked-out worktrees cannot do safely.

## Goals / Non-Goals

**Goals:**
- Let `/jj-openspec apply` accept a SET of changes (explicit list or selector) and land them as concurrent apply-shape siblings — one workspace per change, each on that change's own proposal revision.
- Decide integration mode per declared dependency: independent landings by default, a stitched stack (topological order) when inter-change dependencies are declared.
- Run each change's existing apply-shape verify tail over its own result, then a thin pipeline-level reconcile that orders landings/stack and emits one summary.
- Preserve the exact single-change apply behaviour as default and fallback; the pipeline is a pure distribution optimization with identical per-change results.
- Reuse `jj-delegate` primitives (concurrent siblings, base-revision provisioning, never-halting integration) with no new jj/workspace mechanics.

**Non-Goals:**
- No new jj primitives, hooks, or worker-contract changes (`jj-workspace-worker` is untouched; it just receives a normal single-change `/opsx:apply` workload).
- No within-a-change decomposition — that is `openspec-apply-fan-out`; the pipeline treats each change as an opaque unit.
- No automatic dependency inference from change content; inter-change dependencies are taken as DECLARED (e.g. in proposal/metadata), and absence of a declaration means independent.
- No collapsing of per-change verify results; each change is verified and reported on its own.
- No authoring-shape pipeline (`propose`/`new`/`ff`/`explore` are unaffected).

## Decisions

**Decision: The change set is supplied as an explicit list or a selector, always resolved to a concrete confirmed set before dispatch.**
The binding accepts either a literal list of change names or a selector (glob/query over `openspec/changes/` plus OpenSpec status). Either form is resolved to a de-duplicated list of changes that exist and are apply-ready, and that resolved list is confirmed before any worker spawns. Rationale: a confirmed concrete set makes dispatch deterministic and keeps the orchestrator from spawning workers for non-existent or unready changes. Alternative considered: dispatch directly from a selector lazily — rejected because it hides the actual fan-out width and risks dispatching unready work.

**Decision: One whole-change apply-shape worker per change, each based on that change's OWN proposal revision.**
Each change is dispatched as a `jj-delegate` concurrent sibling running the standard `/opsx:apply <change>`, with the workspace based on that change's proposal revision (per `jj-openspec-binding`). Rationale: each change's artifacts must be present in its worker's workspace, and different changes may live on different revisions; basing per-change is the only correct seed. Alternative considered: base all workers on a single common revision — rejected because it would not guarantee each change's proposal artifacts are present.

**Decision: Integration mode is independent landings by default, stitched stack only on declared dependencies (topological order; cycles abort).**
With no declared inter-change dependency, completed changes land independently onto trunk in whatever order they report. When dependencies are declared within the set, the orchestrator integrates them as a stitched stack in a topological order of those dependencies; a cycle aborts stacking with an explicit error rather than choosing arbitrarily. Rationale: independent is the safe, order-free default for genuinely independent changes; stacking is only meaningful when a real ordering exists. All integration rides `jj-delegate`'s never-halting contract, so an unexpected overlap becomes a first-class conflict the orchestrator resolves by editing markers (never interactive `jj resolve`). Alternative considered: always stack in supplied order — rejected because it invents a dependency that may not exist and serializes independent landings.

**Decision: Per-change verify tails stay per-change; the pipeline adds only a reconcile/summary layer.**
Each change runs the existing apply-shape verify tail over its own reconciled result; the pipeline never runs one change's verify over another's result and never merges two changes' verify outcomes. On top, a thin reconcile layer orders the landings/stack and emits a single summary (landed / stacked / conflicted / failed per change). Rationale: keeps each change's PR/result identical in shape to a solo apply, while still giving one operator-level view. A failed/blocked member does not block independent members — its workspace is left intact for inspection, per `jj-delegate` teardown rules.

**Decision: Single-change fallback is the default-safe behaviour for any set that reduces below two apply-ready changes.**
If the resolved set has fewer than two distinct apply-ready changes (a single change, an empty set after exclusions, or only duplicates/overlaps), the binding runs the existing single-change apply with no pipeline overhead. Rationale: zero regression risk and no contract change to `/jj-openspec apply <change>`.

## Risks / Trade-offs

- [Two "independent" changes actually edit a shared file] → never-halting integration turns the overlap into a first-class conflict at integration time, which the orchestrator resolves deliberately; each change's own verify still runs over its resolved result. Set members are confirmed distinct up front to keep this rare.
- [Declared dependencies are wrong or missing, producing a bad stack] → default is independent landings (no stacking), so a missing declaration degrades to safe independent landing; a wrong cycle aborts explicitly rather than silently choosing an order.
- [Wide fan-out spawns many workspaces at once] → the change set is confirmed before dispatch so the operator sees the width; `jj-delegate` owns the concurrency, and the pipeline can cap or batch as a policy knob (not a spec requirement).
- [A failing member leaves an intact workspace that accumulates] → intact-on-failure is intentional for inspection; cleanup follows `jj-delegate` teardown once the operator resolves or abandons that member.

## Migration Plan

Additive and behind a data condition — no migration. Existing `/jj-openspec apply <change>` invocations are unchanged. The pipeline path is reached only when `apply` is given a set of two or more distinct apply-ready changes. Rollback is removing the pipeline entry from the binding, leaving the single-change apply path intact.

## Open Questions

- How are inter-change dependencies DECLARED — proposal front-matter, a pipeline-call argument, or a manifest? v1 can accept them as an explicit argument to the pipeline call and treat absence as independent.
- What is the right maximum concurrent width / batching policy before workspace overhead outweighs the gain?
- Should the pipeline offer a "stack everything in supplied order" override for operators who want a deliberate stack without per-change dependency declarations?
- Should the pipeline summary be emitted as structured data (for an orchestrating skill to consume) in addition to human-readable text?

## Context

`jj-delegate` provisions each worker its own linked jj workspace. Edits are physically isolated per directory, but every linked workspace materialises the **full** working tree of its base revision. When the orchestrator fans out concurrent workers over disjoint file lanes, "you own these files" is a soft instruction in the workload prose — the worker can still see and write any file in the repo. A cross-lane edit is only discovered at integration, as a conflict or a silent overwrite of another worker's intent.

jj supports sparse working copies: `jj workspace add --sparse-patterns <glob...>` (and `jj sparse set` on an existing workspace) restrict which paths materialise on disk. Paths outside the set are simply not checked out. This change layers that mechanism onto provisioning so the orchestrator can, optionally, turn a disjoint-file lane into a physical boundary.

Constraints carried from the existing capability: the worker contract is non-interactive (no `jj sparse edit`), the orchestrator owns all workspace lifecycle and refs, and the base-revision seed-intent rule is fixed.

## Goals / Non-Goals

**Goals:**
- Let the orchestrator optionally scope a worker's workspace to a declared pattern set so it physically cannot touch out-of-lane files.
- Keep it opt-in and per-worker: full-tree provisioning stays the default and is byte-for-byte unchanged when no partition is given.
- Make the full-tree-tooling trade-off explicit so sparse partitions are chosen deliberately, not by default.
- Ensure a sparse worker still receives the paths its workload must *read*, not only those it edits.

**Non-Goals:**
- Auto-deriving partitions from a change's `tasks.md` (the orchestrator/binding decides partitions; this capability only consumes them).
- Changing the base-revision seed-intent rule, bookmark/ref ownership, integration, or teardown.
- Making sparse partitioning mandatory for fan-out, or coupling it to the `jj-openspec-fanout` distribution.
- Solving whole-repo verification inside a sparse tree (explicitly out of scope — see Decisions).

## Decisions

**Decision: Use `jj workspace add --sparse-patterns` at provisioning time, not a post-add `jj sparse set`.**
Provisioning is a single orchestrator step; folding the partition into the `workspace add` invocation keeps the worker's first on-disk state already-sparse, so there is no transient window where the full tree exists. Rationale over the alternative (add full, then `jj sparse set` to narrow): the narrowing alternative momentarily materialises out-of-lane files and adds a second mutating step; `--sparse-patterns` at add time avoids both. `jj sparse set` remains the fallback only if a pinned jj version lacks the flag.

**Decision: Partition = edit-paths ∪ read-paths, supplied by the orchestrator.**
The orchestrator (or the binding above it) knows the lane's edit set; it SHALL widen that to include paths the workload reads (the invoked skill's inputs, shared in-lane context). Rationale: a partition scoped to edits-only would starve a worker of context it legitimately needs and produce spurious missing-file failures. Alternative considered — always include a fixed "common" prefix (e.g. config, lockfiles) — rejected as too coarse; the read-set is workload-specific and best decided per dispatch.

**Decision: Sparse is opt-in; absence of the option preserves today's behaviour exactly.**
A worker with no partition gets the full tree via the unchanged `jj workspace add -r <base> <path>` path. Rationale: the overwhelming majority of workloads need the full tree to build/test; making sparse the default would break them. Sparse is a sharp tool for self-contained lanes.

**Decision: Verification that needs the full tree does not run inside a sparse workspace.**
When a workload's verification needs whole-repo tooling, the orchestrator either declines the sparse option for that worker (provisions full-tree) or runs the verification outside the sparse workspace (e.g. after integration into a full-tree revision). Rationale: a sparse working copy genuinely lacks the files; type-checkers and whole-suite runners will error on absent imports. This is documented in provisioning guidance so the operator chooses with eyes open.

## Risks / Trade-offs

- **Build/test tooling needs the full tree** → Documented as a hard precondition; the orchestrator only chooses sparse for lanes whose verification is self-contained, else provisions full-tree or verifies elsewhere. This is the central trade-off and is encoded as a normative requirement, not just prose.
- **Partition too narrow starves the worker of read context** → The edit ∪ read rule is a requirement; the worker treats absent out-of-lane files as expected, and the orchestrator widens the partition rather than the worker improvising across the repo.
- **Overlapping partitions across siblings would re-introduce soft ownership** → The orchestrator SHALL choose non-overlapping partitions; overlap defeats the guarantee and is called out explicitly.
- **jj version lacks `--sparse-patterns`** → Fallback to `jj sparse set` on the freshly added workspace (one extra non-interactive step); never `jj sparse edit` (interactive, blocked by the worker contract).
- **A sparse worker tries to grow its own tree** → The worker contract forbids it from reshaping its own sparse scope; only the orchestrator owns provisioning. If a worker discovers it genuinely needs an out-of-lane file, it STOPs and reports rather than widening scope itself.

## Migration Plan

Documentation/skill-prose change only; no runtime migration. Adoption is incremental: existing delegations keep full-tree provisioning untouched, and operators opt into sparse partitions per fan-out as confidence grows. Rollback is trivial — omit the sparse option and provisioning reverts to the current full-tree path.

## Open Questions

- Exact glob/fileset syntax to standardise in the guidance (jj fileset expressions vs. plain path globs) — to be pinned against the repo's jj version during implementation.
- Whether to offer a convenience that derives the read-set from a lane's edit-set plus a declared "shared roots" list, or leave the full partition explicit per dispatch (leaning explicit for now).

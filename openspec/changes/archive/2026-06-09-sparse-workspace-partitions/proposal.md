## Why

When `jj-delegate` fans out concurrent workers, disjoint-file ownership is a **soft convention**: the orchestrator tells each worker "you own these files," but every worker's linked workspace materialises the entire working tree, so nothing stops a confused or over-eager worker from editing a file in another worker's lane. That latent cross-lane edit only surfaces as a conflict (or worse, a silent clobber of intent) at integration time. jj's `jj workspace add --sparse-patterns` can scope a workspace's working copy to only a declared set of paths, so files outside that set never materialise on disk — making "these are the only files you touch" a structural guarantee instead of a request.

## What Changes

- The orchestrator gains an **optional sparse-partition option** when provisioning a worker: it MAY pass the worker's file partition as a sparse pattern set so the worker's workspace materialises only those paths. A worker provisioned this way physically cannot read or write files outside its lane.
- Sparse provisioning is **opt-in and per-worker**: omitting it preserves today's full-tree behaviour exactly. The orchestrator decides per fan-out whether hard partitions are worth their trade-offs.
- The orchestrator SHALL ensure each worker's pattern set always includes the paths the workload needs to *function* (e.g. the workload/skill's own inputs), not only the paths it is expected to edit, so a sparse worker is not starved of context it legitimately needs to read.
- **Trade-offs are documented**, not hidden: a sparse working copy omits files, so build/test tooling that needs the full tree (resolving imports across the repo, type-checking against untracked-here modules, running a whole-repo suite) will not work inside a sparsely-provisioned workspace. The orchestrator SHALL only choose sparse partitions when the workload's verification does not require the full tree, or SHALL run that verification elsewhere.
- Sparse partitions are an **isolation tool layered on the existing provisioning requirement**; they change *what materialises* in the workspace, not the base-revision seed-intent rule (which still governs *which commit* the workspace starts from).

## Capabilities

### New Capabilities
<!-- None. This feature extends an existing capability rather than introducing a new one. -->

### Modified Capabilities
- `jj-delegate`: the workspace-provisioning requirement gains an optional sparse-partition facet — provisioning MAY scope a worker's workspace to a declared pattern set so disjoint-file ownership becomes a physical guarantee, with the full-tree trade-offs and the "include what the workload must read" rule made explicit.

## Impact

- Affected skill prose: `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` (provisioning section) gains the optional `--sparse-patterns` provisioning path and its trade-off guidance; `plugins/jj-concurrent/skills/jj-workspace-worker/*` worker-contract prose notes that a worker may find its tree deliberately sparse and must not treat missing-outside-lane files as an error.
- Affected command surface: orchestrator provisioning calls become `jj workspace add -r <base> --sparse-patterns <glob...> <path>` when the option is taken; unchanged otherwise.
- Dependencies: relies on `jj workspace add --sparse-patterns` (and `jj sparse set`) being available in the pinned jj version; the non-interactive contract is preserved (no `jj sparse edit`).
- No target-project application code changes — this is orchestration/isolation behaviour only.

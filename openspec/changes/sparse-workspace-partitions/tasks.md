## 1. Provisioning: optional sparse partition

- [x] 1.1 In `plugins/jj-concurrent/skills/jj-delegate/SKILL.md`, extend the provisioning section to accept an optional per-worker sparse partition (a pattern set) alongside the existing explicit base revision
- [x] 1.2 Implement the provisioning command form `jj workspace add -r <base> --sparse-patterns <glob...> <path>` for the sparse case, and document `jj sparse set` on the freshly added workspace as the fallback when the pinned jj version lacks `--sparse-patterns`
- [x] 1.3 Keep the no-partition path byte-for-byte unchanged (`jj workspace add -r <base> <path>`), so full-tree provisioning remains the default
- [x] 1.4 State that the sparse choice never affects the base-revision seed-intent rule (partition governs which files materialise, not which revision)

## 2. Partition construction (edit ∪ read)

- [x] 2.1 Document that the orchestrator builds each worker's partition as edit-paths ∪ read-paths, covering paths the workload reads to function as well as paths it edits
- [x] 2.2 Add guidance that concurrent siblings' partitions MUST be non-overlapping, so the absence of out-of-lane files is the enforcement mechanism

## 3. Worker contract for sparse trees

- [x] 3.1 In `plugins/jj-concurrent/skills/jj-workspace-worker/*`, note that a worker may find its tree deliberately sparse and MUST treat absent out-of-partition files as expected, not as a missing-file error
- [x] 3.2 Reaffirm that the worker never reshapes its own sparse scope (no `jj sparse edit`); if it genuinely needs an out-of-lane file it STOPs and reports rather than widening scope itself

## 4. Full-tree-tooling trade-off

- [x] 4.1 Document the hard trade-off: a sparse working copy omits files, so whole-repo build/type-check/test tooling will not work inside it
- [x] 4.2 Specify the decision rule: choose sparse only when the worker's in-workspace verification is self-contained; otherwise provision that worker full-tree or run verification outside the sparse workspace
- [x] 4.3 Record the trade-off and decision rule in the provisioning guidance so the choice is deliberate

## 5. Validation

- [x] 5.1 Run `openspec validate sparse-workspace-partitions --strict` and resolve any structural errors
- [x] 5.2 Confirm the delta against `openspec/specs/jj-delegate/spec.md` archives cleanly (MODIFIED requirement header matches the existing requirement name exactly)
- [x] 5.3 Exercise both provisioning paths against a scratch jj repo: a sparse worker (verify out-of-lane files are absent and a cross-lane edit is impossible) and a full-tree worker (verify unchanged behaviour)

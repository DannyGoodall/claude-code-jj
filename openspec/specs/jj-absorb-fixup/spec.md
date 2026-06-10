# jj-absorb-fixup Specification

## Purpose
TBD - created by archiving change jj-absorb-fixup. Update Purpose after archive.
## Requirements
### Requirement: Absorb working-copy hunks into downstack commits

The plugin SHALL provide an orchestrator skill `/jj-absorb` that runs `jj absorb` over the working-copy changes so each hunk is moved into the downstack commit that last touched those lines — the jj analog of the amend-after-review loop. The skill SHALL accept an optional fileset and an optional `--into <rev>`/downstack-target argument to scope which changes are absorbed, and SHALL run `jj absorb` non-interactively (`--no-pager`, no `-i`).

#### Scenario: Scattered review fixes are distributed downstack

- **WHEN** `/jj-absorb` is invoked with working-copy hunks that each belong to a different downstack commit
- **THEN** the skill runs `jj absorb` so each hunk is moved into the downstack commit that last modified those lines
- **AND** the working copy is left with only the hunks that could not be placed

#### Scenario: Absorb is scoped to a fileset

- **WHEN** `/jj-absorb <fileset>` is invoked with a fileset argument
- **THEN** only hunks matching that fileset are passed to `jj absorb`
- **AND** hunks outside the fileset remain untouched in the working copy

### Requirement: Per-hunk landing report

After the mutating run, the skill SHALL report where each absorbed hunk landed, keyed to the destination change-id and that change's description, so the orchestrator can see the result of the amend at a glance. The report SHALL distinguish hunks that were absorbed from hunks that were left in the working copy.

#### Scenario: Landing report names the destination commit per hunk

- **WHEN** `jj absorb` has distributed two hunks into two different downstack commits
- **THEN** the skill reports each hunk's destination change-id and description
- **AND** the report lists the absorbed hunks separately from any left in the working copy

### Requirement: Ambiguous remainder left for manual placement

A hunk with no unambiguous downstack home SHALL be left in the working copy (jj's default behaviour) rather than dropped or force-fitted into an arbitrary commit. The skill SHALL explicitly call out each such remaining hunk and point the orchestrator at the manual options (`jj squash --into <rev>` or shaping a fresh change), and SHALL NOT invoke any interactive command to place it.

#### Scenario: Unabsorbed hunk is surfaced, not dropped

- **WHEN** a working-copy hunk has no unambiguous downstack commit to absorb into
- **THEN** that hunk remains in the working copy
- **AND** the skill reports it as needing manual placement, naming `jj squash --into <rev>` as the manual option
- **AND** the skill does not silently drop the hunk or invoke an interactive command

### Requirement: Orchestrator-role and non-interactive contract

The skill SHALL run only in the orchestrator role, operating on the orchestrator's own change stack. It SHALL NOT move bookmarks, perform `jj git push`, or run raw mutating git, and SHALL run every command non-interactively (`--no-pager`; no `-i`/`--interactive`; no editor spawn). The skill SHALL preflight-check that the installed `jj` supports `jj absorb` and SHALL report a clear blocker when it does not. The skill SHALL detect whether `jj absorb` supports `--dry-run` and select either the dry-run preview path or the op-log review-and-undo fallback accordingly; a missing `--dry-run` SHALL NOT be reported as a blocker and SHALL NOT cause the skill to refuse to absorb.

#### Scenario: Skill stays within the orchestrator contract

- **WHEN** `/jj-absorb` runs
- **THEN** it only reshapes the orchestrator's own commits via `jj absorb`
- **AND** it performs no bookmark, push, or raw mutating git operation

#### Scenario: Missing absorb support is reported, not improvised

- **WHEN** the installed `jj` does not support `jj absorb` at all
- **THEN** the skill reports a clear blocker
- **AND** it does not hang on a prompt and does not fall back to a different mutating command

#### Scenario: Missing dry-run selects the fallback, not a blocker

- **WHEN** the installed `jj` supports `jj absorb` but not `jj absorb --dry-run`
- **THEN** the skill selects the op-log review-and-undo fallback path
- **AND** it does not report a blocker and does not refuse to absorb

### Requirement: Reconcile-tail amend step for delegate

The skill SHALL be usable as the amend-after-review step the `jj-delegate` reconcile tail invokes when a review pass leaves scattered fixes across the stack, providing the single absorb-and-report action that tail calls rather than ad-hoc "amend each commit" instructions.

#### Scenario: Delegate reconcile tail calls the skill after review

- **WHEN** the `jj-delegate` orchestrator has review fixes scattered across a worker's integrated stack
- **THEN** it invokes `/jj-absorb` to distribute the fixes into their downstack commits and report the landings

### Requirement: Placement preview by dry-run or by op-log review-and-undo

The skill SHALL surface the planned hunk-to-commit placement so the orchestrator can judge the amend, and SHALL adapt to whether the installed `jj absorb` supports `--dry-run`:

- **When `jj absorb --dry-run` is available**, the skill SHALL produce the dry-run preview first (which hunk would land in which commit) and SHALL run the mutating `jj absorb` only after; when the dry-run shows that nothing can be absorbed, the skill SHALL report that and SHALL NOT run a mutating absorb.
- **When `jj absorb --dry-run` is NOT available** (e.g. jj 0.42, which ships `jj absorb` without `--dry-run`), the skill SHALL instead: capture the current operation id as a reversible pre-absorb checkpoint; run the mutating `jj absorb`; read the resulting hunk-to-commit placement from `jj op show -p` of the absorb operation; and present that placement together with the exact one-command undo `jj op restore <pre-absorb-op>` so an unsatisfactory absorb can be rolled back as a whole. The skill SHALL NOT report a missing `--dry-run` as a blocker, and SHALL NOT auto-undo — it presents the placement and the undo command, leaving the decision to the operator or calling skill.

In both modes the post-conditions are identical: the orchestrator can see the hunk-to-commit placement, nothing is silently dropped, and an undesired result is recoverable — by declining to run (dry-run mode) or by `jj op restore` (fallback mode). All commands run non-interactively (`--no-pager`; no `-i`).

#### Scenario: Preview-first when dry-run is supported

- **WHEN** `/jj-absorb` is invoked on a jj whose `jj absorb` supports `--dry-run`
- **THEN** the skill first runs `jj absorb --dry-run` and reports the planned hunk-to-commit placement
- **AND** only then runs the mutating `jj absorb`

#### Scenario: Reviewable-undo fallback when dry-run is unsupported

- **WHEN** `/jj-absorb` is invoked on a jj whose `jj absorb` does not support `--dry-run`
- **THEN** the skill captures the pre-absorb operation id, runs the mutating `jj absorb`, and reports the resulting placement read from `jj op show -p`
- **AND** it surfaces the exact `jj op restore <pre-absorb-op>` command that undoes the whole absorb
- **AND** it does not report a blocker for the missing `--dry-run`

#### Scenario: Nothing to absorb is reported without a lingering mutation

- **WHEN** no working-copy hunk has a downstack home
- **THEN** in dry-run mode the skill reports "nothing to absorb" and runs no mutating absorb
- **AND** in fallback mode the mutating `jj absorb` moves nothing, the skill observes an empty `jj op show -p` for the absorb op, reports "nothing to absorb", and the captured checkpoint need never be restored


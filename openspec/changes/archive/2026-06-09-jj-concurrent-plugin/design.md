## Context

The full rationale (why jj over GitButler and git worktrees) lives in the repo's [DESIGN.md](../../../DESIGN.md) ADR. This design note records the decisions specific to *building the plugin* that this change implements.

## Goals / Non-Goals

**Goals:** physical per-worker isolation; crash-safe worker work; non-halting integration; a workflow-agnostic mechanism with a thin OpenSpec binding on top; enforcement of the role split sufficient for colocated-concurrency safety.

**Non-Goals:** vendoring a jj command reference (we depend on `jj-vcs@toolbox`); shipping application behaviour; supporting non-colocated jj (PRs need git interop).

## Decisions

- **Workspaces are the isolation unit.** One jj workspace per worker — separate directory + working-copy commit, shared object store. This is what GitButler's shared tree could not provide safely.
- **Mechanism / binding split.** `jj-delegate` is workflow-agnostic (a workload is any skill invocation or slice spec); `jj-openspec` is a separate, separately-enableable plugin so non-OpenSpec repos never see it. Mirrors the proven graphite-openspec split.
- **Background dispatch by default.** The orchestrator keeps the session and can fan out more workers; foreground is opt-in.
- **Snapshot is a hook, not a worker duty.** jj snapshots on its own commands, but an agent can crash between an edit and its next jj command; a PostToolUse hook running `jj util snapshot` closes that gap. Fail-open and time-bounded so a jj hang can never wedge the agent.
- **Guard is a cheap string-matching backstop, never invokes jj.** It enforces only inside a jj repo (cheap `.jj` walk), so it cannot hang and cannot break non-jj repos. The worker contract is the primary enforcement line; the guard is defence-in-depth.
- **Orchestrator owns all refs.** Colocated-concurrency is officially under-tested and could lose bookmark pointers; serialising every bookmark/push through the single orchestrator removes the risk (commits are content-addressed and never at risk).
- **Seed intent, not seed ceremony.** jj has no untracked limbo, so there is no seed commit — but `jj workspace add` defaults to the parent of `@`, so the base revision is passed explicitly with `-r`.

## Risks / Trade-offs

- [jj is young; colocated concurrency under-tested] → orchestrator-owns-all-refs; commits safe regardless.
- [occasional jj hangs reported] → snapshot/guard hooks never invoke jj; resume-in-place recovers a stalled worker (its work is already snapshotted).
- [guard string-matching matches mentions, and `git -C` slips past] → accepted; the worker contract is the primary line, guard is a backstop.

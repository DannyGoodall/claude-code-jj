# jj-workspace-worker Specification

## Purpose
TBD - created by archiving change jj-concurrent-plugin. Update Purpose after archive.
## Requirements
### Requirement: Workspace containment

The worker agent SHALL work only in the jj workspace path it was given. It SHALL NOT touch the primary (default) workspace or any sibling workspace — no `cd` into them, no editing their files. Work that genuinely cannot run from the worker's workspace SHALL be left undone and reported, never worked around.

#### Scenario: Worker never touches other workspaces

- **WHEN** the worker runs, including tests against shared local services
- **THEN** all of its file and VCS operations occur within its own workspace

### Requirement: jj-only version control

The worker SHALL use jj for all version control and SHALL NOT run raw mutating git (`commit`/`add`/`checkout`/`reset`/`rebase`/…), which corrupts jj state in a colocated repo. Read-only git and `gh` are permitted. The worker SHALL NOT create or move bookmarks and SHALL NOT push — those belong to the orchestrator.

#### Scenario: Worker shapes commits with jj only

- **WHEN** the worker records its work
- **THEN** it uses `jj describe`/`jj new`/`jj squash` (non-interactively) and never raw mutating git, bookmarks, or push

### Requirement: Commit-per-task-group durability

The worker SHALL shape its work into coherent commits as it goes (a commit per task group where practical), because the workspace's commits are the durable progress record that makes resume-in-place loss-free.

#### Scenario: Progress survives a mid-run failure

- **WHEN** the worker has described one or more changes and then fails
- **THEN** a successor resumes from the last described change with nothing lost

### Requirement: Non-interactive command hygiene

The worker SHALL run only non-interactive commands: jj with `-m` and `--no-pager` (and `--ignore-working-copy` for reads), test runners in single-run mode, no dev servers, no editor- or TUI-spawning jj subcommands. If a jj command hangs it SHALL stop and report, and SHALL never delete anything under `.jj`/`.git`.

#### Scenario: No hanging commands

- **WHEN** the worker needs to run tests or inspect history
- **THEN** it uses single-run/non-interactive forms that cannot block on a prompt

### Requirement: Workflow-skill invocation

When the workload names a workflow skill, the worker SHALL invoke it via the Skill tool rather than hand-editing that workflow's files, and SHALL stop and report if the named skill is unavailable.

#### Scenario: Worker runs a named workflow skill

- **WHEN** the workload is "invoke `/opsx:apply <change>`"
- **THEN** the worker invokes that skill and follows its rules for the files it owns

### Requirement: Structured JSON report

The worker's final message SHALL be a structured JSON object reporting its workspace, the change-ids it shaped, whether it was blocked or hit conflicts, tests run, and notes — consumed by the orchestrator as data. `submitted` is always false (workers never push).

#### Scenario: Orchestrator consumes the report

- **WHEN** the worker finishes
- **THEN** it returns the JSON report and the orchestrator integrates based on it


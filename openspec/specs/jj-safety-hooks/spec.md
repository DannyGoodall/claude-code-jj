# jj-safety-hooks Specification

## Purpose
TBD - created by archiving change jj-concurrent-plugin. Update Purpose after archive.
## Requirements
### Requirement: Snapshot hook closes the crash-before-snapshot gap

A PostToolUse hook on edit tools (`Edit`/`MultiEdit`/`Write`/`NotebookEdit`) SHALL run `jj util snapshot` so that every agent edit is captured into the workspace's working-copy commit. This closes the gap where an agent edits files and then crashes before its next jj command would have snapshotted them. The hook SHALL be fail-open and time-bounded (a stuck snapshot can never wedge the agent) and SHALL act only inside a jj repository.

#### Scenario: Edit captured without an explicit jj command

- **WHEN** an agent edits a file and no jj command is run afterward
- **THEN** the snapshot hook records the edit into the working-copy commit
- **AND** the edit is recoverable via `jj evolog` / `jj op restore`

#### Scenario: Hook never blocks the agent

- **WHEN** a `jj util snapshot` would hang or error
- **THEN** the hook times out / fails open and the agent's edit proceeds

### Requirement: Guard hook blocks state-corrupting and hang-inducing commands

A PreToolUse hook on Bash SHALL block, with an explanatory message, the commands that corrupt jj state, hang an agent, or destroy the repository: raw **mutating git** (`commit`/`add`/`checkout`/`reset`/`rebase`/`merge`/…), **interactive jj** (`resolve`/`arrange`/`diffedit`/`config edit`/`sparse edit`, `-i`/`--interactive`), and **`rm` targeting `.jj`/`.git`**. Read-only git and `gh` SHALL remain allowed. The guard SHALL be cheap and SHALL NOT invoke jj (so it cannot itself hang).

The guard SHALL enforce these rules **only inside a jj repository** and SHALL fail open (allow) outside one — its purpose is protecting jj state, so blocking raw git in a non-jj repo would wrongly break ordinary git workflows. Repository membership SHALL be determined by a cheap upward filesystem walk for a `.jj` entry (no jj invocation).

The guard SHALL determine the **effective directory** for that membership check by parsing a single leading `cd <dir>` in the command — including a `(cd <dir>` subshell prefix and quoted, relative, absolute, or `~` targets — so a `cd <directory> && <command>` is judged from the target directory rather than the session's working directory. Arbitrary mid-command directory changes remain judged from the leading directory (a documented limitation).

#### Scenario: Raw mutating git blocked in a jj repo

- **WHEN** an agent runs `git commit` inside a jj repository
- **THEN** the guard blocks it with a message to use jj (read-only git and gh stay allowed)

#### Scenario: Destroying the VCS store is refused

- **WHEN** a command would `rm` a path under `.jj`/`.git`
- **THEN** the guard blocks it (recovery is orchestrator-only via `jj op restore`)

#### Scenario: Fails open outside a jj repo

- **WHEN** a mutating git command runs with no `.jj` in the effective directory's ancestry
- **THEN** the guard allows it (ordinary git workflows in non-jj repos are unaffected)

#### Scenario: cwd resolved from a leading cd

- **WHEN** the session's working directory is a jj repo but the command is `cd <non-jj-repo> && git add -A`
- **THEN** the guard judges membership from the target directory and allows the git command


## MODIFIED Requirements

### Requirement: Guard hook blocks state-corrupting and hang-inducing commands

A PreToolUse hook on Bash SHALL block, with an explanatory message, the commands that corrupt jj state, hang an agent, or destroy the repository: raw **mutating git** (`commit`/`add`/`checkout`/`reset`/`rebase`/`merge`/…), **interactive jj** (`resolve`/`arrange`/`diffedit`/`config edit`/`sparse edit`, `-i`/`--interactive`), and **`rm` targeting `.jj`/`.git`**. These form a **universal floor** enforced for BOTH the orchestrator and worker roles. Read-only git and `gh` SHALL remain allowed. The guard SHALL be cheap and SHALL NOT invoke jj (so it cannot itself hang).

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

#### Scenario: Universal floor applies to both roles

- **WHEN** either an orchestrator or a worker runs a command in the universal floor (raw mutating git, interactive jj, or `rm` on the store)
- **THEN** the guard blocks it regardless of role

## ADDED Requirements

### Requirement: Guard detects its workspace role and blocks worker ref operations

The guard hook SHALL cheaply detect whether it is running as the **orchestrator** (the repository's default workspace) or a **worker** (a linked jj workspace), and SHALL block the operations the `jj-delegate` role split reserves for the orchestrator — `jj bookmark …` and `jj git push` — when, and only when, it is running as a worker.

Role detection SHALL be **cheap and hang-proof** and SHALL NOT invoke jj. It SHALL reuse the `.jj` directory already located by the guard's upward membership walk and inspect `.jj/repo`: a regular **file** (a pointer to the default workspace's store) means a **linked workspace = worker**; a **directory** (the store itself) means the **default workspace = orchestrator**. The check SHALL use only filesystem type tests (e.g. `test -f` / `test -d`).

When the role is **orchestrator**, or when the role cannot be determined (e.g. `.jj/repo` is neither a plain file nor a directory), the guard SHALL **allow** `jj bookmark …` and `jj git push` — failing open preserves the orchestrator's legitimate ownership of ref and push operations and never wrongly blocks the default workspace.

Worker restriction applies only to ref/push operations; the worker's own commit-shaping commands (`jj new`/`describe`/`squash`/`split`/`rebase` within its workspace) SHALL remain allowed.

#### Scenario: Worker blocked from bookmark operations

- **WHEN** a worker (a linked workspace where `.jj/repo` is a regular file) runs `jj bookmark set my-feature`
- **THEN** the guard blocks it with a message that bookmarks are orchestrator-only

#### Scenario: Worker blocked from pushing

- **WHEN** a worker runs `jj git push`
- **THEN** the guard blocks it with a message that push is orchestrator-only

#### Scenario: Orchestrator allowed to manage bookmarks and push

- **WHEN** the orchestrator (the default workspace where `.jj/repo` is a directory) runs `jj bookmark set` or `jj git push`
- **THEN** the guard allows it

#### Scenario: Worker commit-shaping stays allowed

- **WHEN** a worker runs `jj new -m "…"` or `jj describe -m "…"` in its own workspace
- **THEN** the guard allows it (only bookmark/push are restricted for workers)

#### Scenario: Role detection never invokes jj

- **WHEN** the guard determines its role on any Bash call
- **THEN** it uses only filesystem type tests on the already-located `.jj/repo` and never runs a jj command, so it cannot hang

#### Scenario: Undetermined role fails open

- **WHEN** the role cannot be classified (`.jj/repo` is neither a plain file nor a directory)
- **THEN** the guard allows `jj bookmark …` and `jj git push` (fail open, preserving prior universal-floor-only behaviour)

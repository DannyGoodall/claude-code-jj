# jj-release Specification

## Purpose
TBD - created by archiving change add-jj-release. Update Purpose after archive.
## Requirements
### Requirement: Relay-shaped release flow
The `/jj-release` skill SHALL follow a relay shape: a PREPARE phase that gathers everything needed, a single human GO/NO-GO gate, and a PUBLISH phase that only runs on an explicit "go". The skill SHALL NOT publish a release without passing through the gate.

#### Scenario: Prepare then gate then publish
- **WHEN** the user invokes `/jj-release`
- **THEN** the skill resolves the target commit, runs the CI gate, computes the proposed version, generates notes, and gathers any optional assets, then presents a single summary (version, target sha, notes, pre-release flag, draft flag, asset list) and waits for an explicit go/no-go
- **AND** it publishes only after the user says "go"

#### Scenario: User declines at the gate
- **WHEN** the user responds "no" / "cancel" at the gate
- **THEN** the skill makes no tag, no release, and no remote changes, and reports that nothing was published

### Requirement: Tag-only versioning
The skill SHALL treat the git tag as the sole source of the release version and SHALL NOT edit any manifest or version file (e.g. `plugin.json`, `package.json`, `Cargo.toml`). Tags SHALL use the format `vMAJOR.MINOR.PATCH`.

#### Scenario: Tag carries the version
- **WHEN** a release is published for version `0.1.0`
- **THEN** the skill creates the tag `v0.1.0` and changes no files in the repository working tree

#### Scenario: Repo version diverges from manifest versions
- **WHEN** the repo's internal manifests declare unrelated versions (e.g. a plugin at `0.7.1`)
- **THEN** the skill neither reads those for mutation nor reconciles them; the divergence is acceptable

### Requirement: SemVer bump proposal with mandatory confirmation
The skill SHALL propose a SemVer bump derived from conventional-commit prefixes since the last tag (`feat`→minor, `fix`→patch, a breaking change / `!` → major) and SHALL ALWAYS require the human to confirm or override the proposed version before publishing. When commits are not parseable as conventional commits, the skill SHALL fall back to asking for the version outright.

#### Scenario: Auto-proposed bump confirmed
- **WHEN** the commits since the last tag include a `feat:` and several `fix:` commits
- **THEN** the skill proposes a minor bump and asks the user to confirm or override before publishing

#### Scenario: Non-conventional commits
- **WHEN** the commits since the last tag are not conventional-commit formatted
- **THEN** the skill does not guess a bump and instead asks the user for the version directly

### Requirement: First-release handling
When the repository has no prior release tag, the skill SHALL NOT assume a default initial version and SHALL ask the user for the initial version explicitly.

#### Scenario: No prior tag
- **WHEN** `/jj-release` runs in a repo with zero existing tags/releases
- **THEN** the skill detects there is no baseline, asks the user for the initial version (no default offered), and proceeds with that version after confirmation

### Requirement: Release notes generation and in-conversation editing
The skill SHALL generate release notes from the commits/PRs merged since the last tag, and SHALL allow the user to amend those notes in conversation before the gate. The skill MAY optionally publish the release as a GitHub draft as a rendered preview before final publication.

#### Scenario: Generated notes edited before publish
- **WHEN** the skill presents generated notes and the user asks to add a "Highlights" section or remove a line
- **THEN** the skill regenerates the notes with the requested change and re-presents them before any publication

#### Scenario: Draft preview
- **WHEN** the user asks to preview the release rendered on GitHub before going live
- **THEN** the skill may create the release as a draft, report its URL, and only publish (un-draft) on a subsequent "go"

### Requirement: Pre-release default for 0.x versions
When the chosen version is in the `0.x` range, the skill SHALL default the GitHub `--prerelease` flag to ON, and SHALL allow the user to override it at the gate.

#### Scenario: 0.x defaults to pre-release
- **WHEN** the confirmed version is `0.1.0`
- **THEN** the skill marks the release as a pre-release by default and shows this in the gate summary, where the user can override it

#### Scenario: 1.x is not pre-release by default
- **WHEN** the confirmed version is `1.2.0`
- **THEN** the skill does not default to pre-release

### Requirement: CI gate on the target commit
The skill SHALL refuse to publish a release unless the required CI checks on the **target commit** are green. The check status SHALL be read from the commit directly (commit check-runs / combined status), not from a pull request, because the originating PR is merged by release time. Failing or still-pending checks SHALL block publication with a clear message.

#### Scenario: Green checks allow release
- **WHEN** the target commit's required checks have all concluded successfully
- **THEN** the skill permits publication to proceed to the gate

#### Scenario: Red or pending checks block release
- **WHEN** the target commit has a failing or still-pending required check
- **THEN** the skill refuses to publish, reports which check is not green, and notes that a manual release outside the plugin is the user's prerogative

### Requirement: Refuse to overwrite an existing release
The skill SHALL refuse to publish when a GitHub release already exists for the target tag, reporting a clear message that tags are immutable and a new version must be chosen. It SHALL NOT create-or-update an existing release in place.

#### Scenario: Tag already released
- **WHEN** a release for tag `v0.1.0` already exists and the user attempts to release `v0.1.0` again
- **THEN** the skill refuses with a clear message and does not modify the existing release

### Requirement: Optional opaque artifacts hook
The skill SHALL provide an optional seam for attaching release assets: a project-supplied command that produces artifact files. The skill SHALL run that command if provided and upload whatever files it emits, but SHALL NOT contain any build logic of its own. Producing artifacts is the repo owner's responsibility.

#### Scenario: No artifacts hook supplied
- **WHEN** the user provides no artifacts command
- **THEN** the skill publishes a source-only release (GitHub's auto-generated source archive) with no attached assets

#### Scenario: Artifacts hook supplied
- **WHEN** the user supplies an artifacts command
- **THEN** the skill runs it, collects the emitted files, lists them in the gate summary, and uploads them to the release on publish — without interpreting how they were built

### Requirement: Server-side tag creation
The skill SHALL create the release tag on the remote via `gh release create <tag> --target <sha>` rather than creating a local git tag, so that it works without native jj tag-creation support and is not blocked by a guard hook that forbids raw `git tag`.

#### Scenario: Tag created at publish
- **WHEN** the skill publishes a release for a tag that does not yet exist
- **THEN** it passes the target commit sha to `gh release create --target` and the tag is created server-side at that commit

### Requirement: Orchestrator-only, non-interactive operation
The skill SHALL run only in the primary/default workspace as an orchestrator operation and SHALL NEVER be invoked inside a worker. All commands SHALL be non-interactive (`--no-pager`, no `-i`/`--interactive`, no spawned editor); human input SHALL be collected through the relay gate.

#### Scenario: Never run in a worker
- **WHEN** release work is needed during a delegated workflow
- **THEN** publishing is performed by the orchestrator after integration, never by a worker

#### Scenario: No interactive prompts
- **WHEN** the skill runs any `jj`, `git`, or `gh` command
- **THEN** it uses non-interactive flags and never opens an editor; the only human interaction point is the relay gate

### Requirement: Packaged in the jj-lifecycle plugin
`/jj-release` SHALL ship in a new `jj-lifecycle` plugin, separate from `jj-concurrent`, `jj-concurrent-openspec`, and `jj-concurrent-linear`, and SHALL be installable and usable without those plugins present.

#### Scenario: Release-only installation
- **WHEN** a user installs only the `jj-lifecycle` plugin
- **THEN** `/jj-release` is available and functional without requiring any concurrency or OpenSpec plugin


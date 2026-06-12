# skill-doc-budget — delta

## ADDED Requirements

### Requirement: Frontmatter description budget

Every plugin SKILL.md frontmatter description SHALL be at most 1024 characters, with a working target of 700. A description SHALL consist of one sentence stating what the skill does, at most 4 trigger phrases, and hard preconditions only. Any operative detail removed from a description during a trim SHALL be verified to exist in the skill body (moved there if absent) before the trim commits — descriptions route invocation; bodies carry procedure.

#### Scenario: Over-budget description fails lint

- **WHEN** a plugin SKILL.md frontmatter description exceeds 1024 characters
- **THEN** the skill lint exits non-zero naming the file and its character count

#### Scenario: Trimmed detail is moved, not dropped

- **WHEN** a description trim removes an operative detail (a precondition, a flag, a refusal rule)
- **THEN** that detail exists in the skill body after the trim
- **AND** the trim commit does not rely on the detail being "implied"

#### Scenario: Trigger lists are capped

- **WHEN** a description's trigger list is rewritten
- **THEN** at most 4 trigger phrases remain, keeping the strongest distinct intents (for a multi-verb skill, at least one trigger per verb)

### Requirement: Single-sourced shared contract

The shared orchestration contract (substrate knowledge comes from the installed jj-vcs skill; orchestrator-only / never invoked inside a worker; non-interactive jj — `--no-pager`, no `-i`, no editor; never raw mutating git; never delete `.jj`) SHALL live in exactly one canonical home (`jj-delegate` SKILL.md §Roles & shared conventions). Every other skill SHALL replace repeated boilerplate paragraphs with a single reference line that restates only the binding essentials (orchestrator-only, non-interactive) inline. Constraints unique to a skill SHALL NOT be removed or relocated. References that cross a plugin boundary SHALL use the prose name of the canonical section, not a relative file path, because plugins install as separate directory trees.

#### Scenario: Boilerplate prose appears at most once per file

- **WHEN** the skill lint scans a SKILL.md for the known boilerplate prose markers outside fenced code blocks
- **THEN** each marker occurs at most once in that file

#### Scenario: Skill-unique constraints survive

- **WHEN** repeated contract paragraphs are collapsed to the reference line
- **THEN** every constraint that appears in only that skill remains in that skill's body verbatim or strengthened

#### Scenario: Cross-plugin reference has no relative path

- **WHEN** a skill outside the jj-concurrent plugin references the canonical contract section
- **THEN** the reference is by prose name, with no relative link that would dangle in an installed plugin cache

### Requirement: Within-file non-duplication

A SKILL.md SHALL state each constraint once: a Guardrails (or equivalent) section SHALL NOT restate the Preconditions section, role/read-only assertions SHALL appear at most once per file, and steps that perform no action beyond confirming a prior assertion (pure ceremony) SHALL be removed.

#### Scenario: Mirrored guardrails are collapsed

- **WHEN** a skill's Guardrails section only restates its Preconditions
- **THEN** the file keeps one of the two sections (the one with operative ordering) and the other is removed

#### Scenario: Repeated role assertions are deduplicated

- **WHEN** a file asserts orchestrator-only or read-only more than once outside fenced code blocks
- **THEN** only the first assertion remains

### Requirement: Lint enforcement for skill docs

The repo SHALL provide a lint script for plugin SKILL.md files that exits non-zero when: any frontmatter description exceeds 1024 characters; any relative link or intra-file anchor in a plugin SKILL.md points at a missing file or heading; any known boilerplate prose marker occurs more than once per file outside fenced code blocks; or a required frontmatter key (`name`, `description`) is missing. The lint SHALL run green at every stage boundary of a skill-doc restructure.

#### Scenario: Broken relative link fails lint

- **WHEN** a SKILL.md links to `references/examples.md` and that file does not exist at the resolved path
- **THEN** the lint exits non-zero naming the file and the dangling link

#### Scenario: Lint gates every stage commit

- **WHEN** a stage of a skill-doc restructure is about to commit
- **THEN** the lint has been run and is green for that tree

### Requirement: Content preservation across restructures

Before a skill-doc restructure begins, a manifest tool SHALL snapshot every fenced code block and every table in each plugin SKILL.md (normalized, content-keyed). After each stage, the tool SHALL verify each snapshotted item still exists somewhere in the repo — the same file, a `references/` file, `DESIGN.md`, or a `scripts/` file. An item allowed to vanish SHALL require an explicit per-item allowlist entry, and all allowlisted drops SHALL be reported, so deletions are deliberate, never accidental.

#### Scenario: Moved content passes the check

- **WHEN** a worked example's code block moves from a SKILL.md into `references/examples.md`
- **THEN** the content check matches it by normalized content and passes

#### Scenario: Vanished content fails the check

- **WHEN** a snapshotted code block or table exists nowhere in the repo after a stage
- **AND** it has no allowlist entry
- **THEN** the check exits non-zero identifying the item and its source file

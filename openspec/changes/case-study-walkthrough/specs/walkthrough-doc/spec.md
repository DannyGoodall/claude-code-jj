## ADDED Requirements

### Requirement: Complete feature coverage

The walkthrough SHALL demonstrate every user-facing capability of all three plugins. Each capability under `openspec/specs/` (the eleven `jj-concurrent` skills, the `jj-workspace-worker` agent, the snapshot + guard hooks, the `jj-openspec` binding with its fan-out / pipeline / healthcheck behaviours, and the three Linear skills), plus each OpenSpec mode (propose, apply, new+ff, relay), SHALL map to at least one section of the document. A coverage matrix included in the document SHALL make the mapping explicit so completeness is checkable.

#### Scenario: Every capability maps to a section

- **WHEN** a reader cross-references the coverage matrix against `openspec/specs/`
- **THEN** every capability appears against at least one section number
- **AND** the four OpenSpec modes (propose, apply, new+ff, relay) each appear against at least one section

### Requirement: Consistent per-section template

Every section that demonstrates a specific feature SHALL carry three highlighted elements: a **Skill** callout naming the plugin skill in use, a **Tip** callout with one or more tips specific to that feature, and an **Under the hood** block showing the equivalent `jj` / `gh` / Linear-MCP commands the plugin abstracts.

#### Scenario: A feature section has all three highlighted elements

- **WHEN** any numbered feature section is read
- **THEN** it contains a Skill callout, a Tip callout, and an Under-the-hood command block
- **AND** the Under-the-hood block names real `jj` / `gh` / Linear-MCP commands, not pseudo-code

### Requirement: With-and-without OpenSpec, foreground-and-background

The narrative SHALL show development both **with** OpenSpec (propose / apply / new+ff / relay) and **without** it (changes that touch no spec), and SHALL show Claude used both in the **foreground** (direct edits in the main session) and as **delegated background** workers.

#### Scenario: Both OpenSpec and non-OpenSpec changes appear

- **WHEN** the document is read end to end
- **THEN** at least one change is made through an OpenSpec mode and at least one change is made with no OpenSpec involvement
- **AND** at least one task is done in the foreground and at least one is delegated to a background worker

### Requirement: GitHub full-time, Linear occasionally, both issue trackers

The narrative SHALL use GitHub as the full-time backend (PRs and ad-hoc issues) and Linear occasionally (the planned-feature agent queue), and SHALL include both a GitHub issue and a Linear issue, under a stated rule for which tracker is used when.

#### Scenario: Both trackers appear with a stated rule

- **WHEN** a reader looks for issue tracking
- **THEN** at least one GitHub issue and at least one Linear issue drive a change
- **AND** the document states the rule distinguishing when each tracker is used

### Requirement: CI introduced late in the timeline

The narrative SHALL run large portions of the work with **no CI**, and SHALL introduce CI near the end. Features whose behaviour depends on CI (the CI-gated land, the red-check abort, keep-current's green gate) SHALL appear **after** the CI chapter; earlier land operations SHALL use the no-CI path.

#### Scenario: CI-dependent features follow the CI chapter

- **WHEN** the CI-dependent sections are located
- **THEN** they all appear after the section that introduces CI
- **AND** every land shown before that section uses the no-CI path

### Requirement: Illustrative, not executed

The walkthrough SHALL be illustrative. It SHALL NOT create a real GitHub repository or touch a real Linear board, and the sample application's code SHALL appear as inline snippets only, not as real files committed to this repository.

#### Scenario: No real external artifacts are created

- **WHEN** the document and the repository are inspected after the change lands
- **THEN** no sample-app source files exist in the repository outside the document's inline snippets
- **AND** the commands shown are presented as representative, not as a captured live transcript

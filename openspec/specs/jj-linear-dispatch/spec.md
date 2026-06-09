# jj-linear-dispatch Specification

## Purpose
TBD - created by archiving change jj-linear-dispatch. Update Purpose after archive.
## Requirements
### Requirement: Dispatch a worker from a single Linear issue

The binding SHALL provide a `/jj-from-linear <issue>` command that accepts a single Linear issue identifier (e.g. `PTS-18`) or issue URL, resolves it through the configured Linear MCP server, and dispatches exactly one `jj-delegate` worker from it. The command SHALL produce exactly one workload and one bookmark per invocation; fanning out across an umbrella's sub-issues is out of scope (the `jj-delegate` mechanism may be invoked repeatedly for that). The command SHALL own no jj/workspace choreography and no OpenSpec artifact rules; it resolves the issue, selects the workload form, derives the bookmark, records issue identity, and hands off to `jj-delegate`.

#### Scenario: Triaged issue becomes a dispatched worker in one command

- **WHEN** `/jj-from-linear PTS-18` is invoked and `PTS-18` resolves through the Linear MCP
- **THEN** the binding composes a single `jj-delegate` workload from the issue and dispatches one worker for it
- **AND** it performs no bookmark/ref operation or integration itself, leaving those to the orchestrator

#### Scenario: One issue yields one workload and one bookmark

- **WHEN** the command processes a resolved issue
- **THEN** it produces exactly one workload and one issue-derived bookmark
- **AND** it does not fan out across any sub-issues of the issue

### Requirement: Issue body maps to one of two workload forms

The binding SHALL map the resolved issue to one of two `jj-delegate` workload forms. If the issue references an **existing OpenSpec change** — a change name carried in a recognised reference marker that resolves to a real `openspec/changes/<name>/` directory — the workload SHALL be the **opsx shape over that change** (a skill invocation the worker runs, e.g. `/opsx:apply <name>` for the implementing shape), dispatched through `jj-delegate` directly or via the `jj-openspec` binding where that binding is enabled. Otherwise the workload SHALL be a **slice spec** whose brief is the issue body (title and description). The referenced-change form SHALL take precedence over the slice-spec form when both could apply.

#### Scenario: Issue referencing an existing change dispatches the opsx workload

- **WHEN** the issue body carries a reference marker naming change `harden-structure-force-purge` and `openspec/changes/harden-structure-force-purge/` exists
- **THEN** the workload is the opsx shape over that change handed to `jj-delegate`
- **AND** the issue body is NOT dispatched as a free-text slice spec

#### Scenario: Issue with no change reference dispatches the body as a slice spec

- **WHEN** the issue carries no recognised OpenSpec-change reference marker
- **THEN** the workload is a slice spec whose brief is the issue's title and description
- **AND** a `jj-delegate` worker is dispatched on that slice spec

#### Scenario: Referenced-change form wins over slice-spec form

- **WHEN** an issue both names a resolvable existing change and contains prose that could read as a slice spec
- **THEN** the binding selects the referenced-change workload
- **AND** does not dispatch the prose as a slice spec

### Requirement: Unresolved change reference fails closed

When the issue references an OpenSpec change by name but no `openspec/changes/<name>/` directory exists, the binding SHALL STOP and surface the unresolved reference without dispatching a worker. It SHALL NOT fall back to dispatching the issue body as a slice spec, and SHALL NOT author a new OpenSpec change in response.

#### Scenario: Typo'd or missing change reference is surfaced, not dispatched

- **WHEN** the issue references change `harden-structure-force-purg` (a typo) which does not resolve to a real change directory
- **THEN** the binding stops and reports the unresolved reference
- **AND** does not dispatch the issue body as a slice spec
- **AND** does not create a new OpenSpec change

### Requirement: Bookmark name derived deterministically from the issue identifier

The binding SHALL derive the worker's bookmark name as a pure function of the Linear issue identifier — the identifier lowercased and kebab-normalised (e.g. `PTS-18` → `pts-18`), optionally under a stable configured prefix (e.g. `linear/pts-18`). The derivation SHALL be deterministic, so that re-dispatching the same issue, or a resume-in-place successor for the same issue, targets the same bookmark. The binding SHALL NOT itself create or move the bookmark; that remains the orchestrator's sole responsibility per `jj-delegate`. The binding only supplies the derived name.

#### Scenario: Same issue derives the same bookmark across dispatches

- **WHEN** `/jj-from-linear PTS-18` is invoked, and later re-invoked for `PTS-18`
- **THEN** both invocations derive the identical bookmark name from the issue identifier
- **AND** the binding supplies that name to the orchestrator rather than creating the bookmark itself

#### Scenario: Bookmark name is collision-resistant and legible

- **WHEN** the binding derives a bookmark for issue `PTS-23`
- **THEN** the name is a kebab-normalised form of `PTS-23` (optionally under a configured prefix)
- **AND** because Linear identifiers are team-unique, the name does not collide with the bookmark of a different issue

### Requirement: Issue identity is threaded to the PR/change link-back, never to the worker

The binding SHALL keep the dispatched worker Linear-agnostic: the worker brief and the worker's JSON report SHALL contain no Linear identifier, and the worker SHALL NOT be given the Linear MCP. The originating issue identity SHALL instead travel two orchestrator-owned channels: (1) the issue-derived **bookmark name**, which surfaces on the resulting branch/PR; and (2) the orchestrator's **agent-plan manifest**, where the dispatch records the issue identifier and issue URL keyed by the worker's workspace path. This recorded identity is what lets the orchestrator reference the originating issue when it opens the PR/change, and lets a separate outbound report→Linear step locate the issue. This binding SHALL NOT itself update Linear status or open the PR.

#### Scenario: Worker receives no Linear identifier

- **WHEN** the binding dispatches a worker for an issue
- **THEN** the worker's brief contains no Linear identifier and the worker has no Linear MCP in its tool surface
- **AND** the worker's JSON report contains no Linear identifier

#### Scenario: Issue identity recorded in the manifest by workspace path

- **WHEN** the binding dispatches a worker into workspace `W` for issue `PTS-18`
- **THEN** it records the issue identifier and URL in the orchestrator's manifest keyed by workspace path `W`
- **AND** that recorded identity is available for the orchestrator's PR link-back and for any downstream outbound Linear step

#### Scenario: PR/change link-back carries the originating issue

- **WHEN** the orchestrator later opens the PR/change for the dispatched work
- **THEN** the originating issue identifier is available to it via the issue-derived bookmark name and the manifest record
- **AND** the binding itself performs no Linear status update

### Requirement: Separately enabled for Linear-tracked repos only

The inbound command SHALL ship as part of the `jj-concurrent-linear` plugin, requiring the `jj-concurrent` plugin and a configured Linear MCP server, so that repositories without Linear (or without a desire to grant Linear access) never surface the `/jj-from-linear` trigger and never issue Linear calls. The reach to the `jj-openspec` (OpenSpec) binding for the referenced-change workload form SHALL be optional: where that binding is absent, the referenced-change workload SHALL still dispatch via plain `jj-delegate` as a skill invocation the worker runs.

#### Scenario: Command absent in a non-Linear repo

- **WHEN** the `jj-concurrent` plugin is enabled but `jj-concurrent-linear` is not
- **THEN** `/jj-from-linear` is unavailable and no Linear calls are made

#### Scenario: Linear MCP unavailable or issue does not resolve

- **WHEN** the command is invoked but the Linear MCP is unreachable or the issue identifier does not resolve
- **THEN** the binding stops before provisioning any workspace or bookmark and reports the failure
- **AND** no worker is dispatched

#### Scenario: Referenced-change form works without the OpenSpec binding

- **WHEN** an issue references a resolvable existing change but the `jj-openspec` binding is not enabled
- **THEN** the workload still dispatches via plain `jj-delegate` as the opsx skill invocation the worker runs through its Skill tool


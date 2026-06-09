## ADDED Requirements

### Requirement: Pre-flight health check gates dispatch for existing-change verbs

The `jj-openspec` binding SHALL, after resolving the target change and its base revision and before handing off to `jj-delegate`, run a pre-flight health check that executes `openspec validate <change>` against the resolved target change. For any verb that targets an **existing** change (`apply`, `verify`, `archive`, `continue`, and `ff` when the change already exists), a non-zero validation result (after noise filtering) SHALL abort dispatch — no workspace is provisioned — and surface the failure as an operator-facing blocker.

#### Scenario: Malformed existing change aborts before provisioning

- **WHEN** `/jj-openspec apply <change>` is invoked and `openspec validate <change>` exits non-zero after noise filtering
- **THEN** the binding aborts dispatch, provisions no workspace, and reports a blocker naming the change and the validation failure

#### Scenario: Well-formed existing change proceeds to dispatch

- **WHEN** `/jj-openspec apply <change>` is invoked and `openspec validate <change>` exits zero (ignoring known-harmless stderr noise)
- **THEN** the health check passes and the binding hands the verb invocation to `jj-delegate` unchanged

### Requirement: Health check is a no-op for new-change authoring verbs

For authoring verbs that create a **new** change (`propose`, `new`, and `ff` when the change does not yet exist), the health check SHALL be a no-op: it SHALL NOT run `openspec validate` against a non-existent change and SHALL NOT block dispatch. The binding SHALL decide new-versus-existing by whether the resolved change directory already exists.

#### Scenario: Proposing a brand-new change skips validation

- **WHEN** `/jj-openspec propose <idea>` resolves to a change name whose directory does not yet exist
- **THEN** the health check records "skipped (new change)" and dispatch proceeds without running `openspec validate`

#### Scenario: ff on an existing change is gated, ff on a new change is skipped

- **WHEN** `/jj-openspec ff <change>` is invoked
- **THEN** the check runs `openspec validate <change>` as a hard gate if the change directory exists, and is skipped as a no-op if it does not

### Requirement: Noise-filtering wrapper strips only known-harmless stderr

The health check SHALL run `openspec`/opsx CLI invocations through a noise-filtering wrapper that drops stderr lines matching an explicit, named allow-list of known-harmless schema-config patterns (including the `Rules for 'tasks' must be an array…` and `Unknown artifact ID in rules…` warnings). Every stderr line not matching the allow-list SHALL pass through unchanged, and the wrapper SHALL NOT alter the process exit code.

#### Scenario: Known-harmless warning is filtered out

- **WHEN** `openspec validate` emits a stderr line matching an allow-list pattern (e.g. `Unknown artifact ID in rules…`)
- **THEN** the wrapper omits that line from the surfaced output while leaving the exit code unchanged

#### Scenario: Unrecognised stderr passes through

- **WHEN** `openspec validate` emits a stderr line that matches no allow-list pattern
- **THEN** the wrapper surfaces that line unchanged so a genuine error is never hidden

#### Scenario: Exit code is preserved through filtering

- **WHEN** the wrapped command exits non-zero but its only stderr lines are on the allow-list
- **THEN** the wrapper still reports the non-zero exit code so a real failure is never masked by filtering

### Requirement: Allow-list is explicit, specific, and fails open

The noise allow-list SHALL be an explicit, documented set of patterns anchored to the specific known-harmless phrases, specific enough that a genuine error line is never matched. Any stderr line the allow-list does not recognise SHALL be shown (fail open), never silently swallowed.

#### Scenario: A novel warning is not swallowed

- **WHEN** a new opsx stderr warning appears that is not present in the allow-list
- **THEN** the wrapper surfaces it rather than dropping it, so allow-list drift produces visible noise rather than hidden errors

### Requirement: Missing openspec CLI is a distinct blocker

Before validating, the wrapper SHALL preflight-check that the `openspec` CLI is available. If the CLI is absent, the health check SHALL report a distinct "openspec CLI not found" blocker rather than letting the missing binary present as a validation failure.

#### Scenario: openspec CLI absent

- **WHEN** the health check runs and the `openspec` CLI is not on PATH
- **THEN** the binding reports a clear "openspec CLI not found" blocker and does not misreport it as a malformed change

### Requirement: Blocker is distinguishable from worker failure

When the health check aborts dispatch, the binding SHALL emit a single operator-facing blocker containing the change name, the noise-filtered validation output, and the instruction to fix the change artifacts and re-dispatch — distinct in form from a worker-execution failure, so the operator can tell "malformed change" from "worker errored".

#### Scenario: Operator can tell why dispatch stopped

- **WHEN** the health check fails and aborts dispatch
- **THEN** the blocker names the change, shows the filtered validation output, and instructs the operator to fix the artifacts and re-dispatch, without implying a worker ran

### Requirement: Health check owns no jj or workspace choreography

The health check SHALL run in the orchestrator before hand-off and SHALL NOT provision workspaces, move bookmarks, run any mutating jj command, or push. It SHALL only read and validate change artifacts and run CLI invocations non-interactively (no `-i`, no editor). It adds a gate to the existing dispatch path described in the `jj-openspec-binding` capability without changing how verbs map to shapes or how `jj-delegate` choreographs workspaces.

#### Scenario: Check performs no version-control mutation

- **WHEN** the health check runs for any verb
- **THEN** it provisions no workspace, mutates no jj state, moves no bookmark, and performs no push — it only validates and reports

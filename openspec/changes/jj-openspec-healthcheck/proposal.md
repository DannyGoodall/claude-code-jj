## Why

When the `jj-openspec` binding dispatches a worker for a verb that targets an existing change (`apply`, `continue`, `ff`, `verify`, `archive`), it trusts that the change's artifacts are well-formed and only discovers structural problems *after* a workspace is provisioned and a worker has burned a turn — the failure surfaces as confusing worker output rather than a clear operator-facing blocker. Separately, `openspec validate` and the opsx CLI emit a known set of harmless schema-config warnings on stderr (e.g. `Rules for 'tasks' must be an array…`, `Unknown artifact ID in rules…`) that, mixed into worker/orchestrator output, train operators to ignore stderr — so a *genuine* error hides in plain sight.

## What Changes

- A new pre-flight **health check** the `jj-openspec` binding runs *before* it hands a change-targeting verb to `jj-delegate`: it runs `openspec validate <change>` against the resolved target change on the base revision and surfaces any real problem as an operator-facing blocker, so a malformed change never reaches workspace provisioning.
- A **noise-filtering wrapper** around opsx/`openspec` CLI invocations that strips the known-harmless schema-config stderr lines (matched against an explicit, named allow-list of noise patterns) while passing every other stderr line and the process exit code through unchanged — so only genuine errors reach the operator.
- The health check is **advisory-by-shape**: for authoring verbs (`propose`/`new`/`ff` of a *new* change) there is no pre-existing change to validate, so the check is a no-op; for verbs targeting an *existing* change it is a hard gate that aborts dispatch on validation failure (after noise filtering).
- A clear, single **blocker report** when the check fails: the change name, the (noise-filtered) validation output, and the instruction to fix the artifacts before re-dispatching — distinguishing "your change is malformed" from "the worker failed".
- **Slots into the existing dispatch path** described in `openspec/specs/jj-openspec-binding`: the binding resolves OpenSpec parameters, *then* runs the health check, *then* hands off to `jj-delegate`. It adds a gate; it does not change how the binding maps verbs to shapes or how `jj-delegate` choreographs workspaces.

## Capabilities

### New Capabilities
- `jj-openspec-healthcheck`: a pre-flight `openspec validate` gate plus a noise-filtering CLI wrapper, used by the `jj-openspec` binding before dispatch — validate the target change on its base revision, filter known-harmless opsx schema-config stderr, and abort dispatch with a clear operator-facing blocker on any genuine validation failure.

### Modified Capabilities
<!-- None. The jj-openspec-binding spec already describes dispatch as "resolve OpenSpec params, then hand off to jj-delegate"; this change inserts a pre-flight gate that the binding calls without changing any existing binding requirement. The reference is one-directional (this capability points at jj-openspec-binding for where it slots in), so no delta spec is required. -->

## Impact

- New skill/wrapper `plugins/jj-concurrent-openspec/skills/jj-openspec-healthcheck/` (or a shared step within the existing `jj-openspec` binding skill) in the **`jj-concurrent-openspec` binding plugin**; bumps that plugin's version. No new plugin.
- Hard dependency on the `openspec` CLI being present and on `openspec validate` accepting a change name; the wrapper SHALL preflight-check the CLI and report a clear blocker when absent.
- The known-harmless stderr noise patterns are captured as an explicit, documented allow-list so the filter never silently swallows a new, unrecognised stderr line.
- Dispatch-path prose in the `jj-openspec` binding skill references the health check as the pre-flight step before `jj-delegate` hand-off (documentation/wiring only; no behaviour change to the binding's spec requirements).
- No changes to any target project's application code and no changes to the opsx artifact rules — this gates the orchestrator's own dispatch and only reads/validates change artifacts.

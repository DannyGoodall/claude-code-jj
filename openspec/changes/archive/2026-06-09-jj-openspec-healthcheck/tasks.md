## 1. Noise-filtering wrapper

- [x] 1.1 Define the explicit, named allow-list of known-harmless opsx/openspec stderr patterns (anchored to `Rules for 'tasks' must be an array…` and `Unknown artifact ID in rules…`), documented in one place
- [x] 1.2 Implement the wrapper that runs an `openspec`/opsx CLI invocation, drops only allow-list-matching stderr lines, passes every other stderr line through unchanged, and preserves the process exit code verbatim
- [x] 1.3 Add the `openspec` CLI preflight-presence check that emits a distinct "openspec CLI not found" blocker when the binary is absent

## 2. Pre-flight health check

- [x] 2.1 Implement the health-check step that, given a resolved change name and base revision, runs `openspec validate <change>` through the noise-filtering wrapper
- [x] 2.2 Implement shape-aware gating: hard gate for existing-change verbs (`apply`, `verify`, `archive`, `continue`, `ff`-on-existing); no-op for new-change verbs (`propose`, `new`, `ff`-on-new), deciding new-vs-existing by whether the change directory exists
- [x] 2.3 Implement the abort-on-failure path: on non-zero filtered validation, emit a single operator-facing blocker (change name + filtered output + "fix artifacts and re-dispatch") and provision no workspace
- [x] 2.4 Ensure the check performs no jj/workspace mutation (no provisioning, no bookmark moves, no push) and runs all CLI calls non-interactively

## 3. Binding integration

- [x] 3.1 Wire the health check into the `jj-openspec` binding between OpenSpec parameter resolution and `jj-delegate` hand-off
- [x] 3.2 Update the `jj-openspec` binding skill prose to document the pre-flight health check as the step before `jj-delegate` hand-off (wiring/documentation only, no change to binding spec requirements)
- [x] 3.3 Bump the `jj-concurrent-openspec` plugin version to reflect the new capability

## 4. Validation

- [x] 4.1 Add/run checks covering each spec scenario: malformed-change abort, well-formed pass-through, new-change skip, ff new-vs-existing branching, allow-list filtering, unknown-stderr pass-through, exit-code preservation, missing-CLI blocker, blocker-vs-worker-failure distinguishability, and no-mutation invariant
- [x] 4.2 Run `openspec validate jj-openspec-healthcheck` and confirm it passes (ignoring known-harmless stderr noise)

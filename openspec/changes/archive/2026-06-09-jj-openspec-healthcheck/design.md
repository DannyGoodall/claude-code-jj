## Context

The `jj-concurrent-openspec` plugin's `jj-openspec` binding (spec: `openspec/specs/jj-openspec-binding`) is a thin layer: it resolves OpenSpec-specific parameters (change name, bookmark, base revision), maps the verb to a *shape* (implementing / authoring / interactive), and hands the verb invocation to `jj-delegate` as the workload. `jj-delegate` then provisions a workspace and runs a worker.

Two gaps live in that hand-off:

1. **No pre-flight validation.** For verbs that target an *existing* change (`apply`, `continue`, `ff` on an existing change, `verify`, `archive`), the binding assumes the change's artifacts are well-formed. If they are not, the failure is discovered late — inside a provisioned workspace, in worker output — where it reads as "the worker failed" rather than "the change is malformed". Workspace provisioning and a worker turn are wasted.

2. **Stderr noise.** `openspec validate` and other opsx CLI calls emit a stable set of harmless schema-config warnings on stderr (observed: `Rules for 'tasks' must be an array…`, `Unknown artifact ID in rules…`). When these are interleaved with genuine output, operators learn to ignore stderr — and a real error hides among the noise.

This change inserts a pre-flight **health check** between parameter resolution and `jj-delegate` hand-off, and a **noise-filtering wrapper** so only genuine errors surface. It is authoring-only here: this document and the specs/tasks define the behaviour; no plugin code is written.

## Goals / Non-Goals

**Goals:**
- Catch a malformed target change *before* a workspace is provisioned, and report it as an operator-facing blocker that names the change and the actual validation failure.
- Filter only an explicit, named allow-list of known-harmless opsx stderr lines, passing every other stderr line and the real exit code through unchanged.
- Slot cleanly into the existing dispatch path without changing how the binding maps verbs to shapes or how `jj-delegate` choreographs workspaces.
- Be shape-aware: a hard gate for existing-change verbs, a no-op for new-change authoring verbs.

**Non-Goals:**
- Not changing `openspec validate` itself, nor the opsx artifact rules (the noise originates in schema config the opsx skills own; we filter its *display*, we do not fix its *source* here).
- Not validating *new* changes that do not yet exist (propose/new of a brand-new change has nothing to validate).
- Not owning any jj/workspace choreography (that stays with `jj-delegate`) — the health check runs in the orchestrator before hand-off.
- Not running the worker's own validation/verify tail; this is strictly a pre-dispatch gate.
- No suppression of *unknown* stderr — anything not on the allow-list is always shown.

## Decisions

**1. Gate placement: in the binding, after param resolution, before `jj-delegate`.**
The binding already resolves the change name and base revision. The health check runs there, against the resolved change on the resolved base revision, so the validation reflects exactly what the worker's workspace will be based on. Rationale: validating earlier (before resolution) lacks the base revision; validating later (inside the worker) defeats the purpose. Alternative considered: make it a `jj-delegate` concern — rejected because `jj-delegate` is workflow-agnostic and knows nothing about `openspec validate`; OpenSpec-specific gating belongs in the binding.

**2. Shape-aware gating.** The check keys off the verb's shape (already computed by the binding):
- Verbs targeting an *existing* change (`apply`, `verify`, `archive`, `continue`, and `ff` when the change already exists) → **hard gate**: run `openspec validate <change>`, noise-filter, and on non-zero exit abort dispatch with a blocker.
- Authoring verbs creating a *new* change (`propose`, `new`, `ff` of a non-existent change) → **no-op**: nothing exists to validate; record "skipped (new change)".
Rationale: avoids a spurious "change not found" blocker on the very verbs whose job is to *create* the change.

**3. Noise filter is an explicit allow-list, not a heuristic.** The wrapper carries a small, documented list of regex/substring patterns for the known-harmless lines. A stderr line is dropped only if it matches a pattern; everything else passes through. The process exit code is never altered. Rationale: a heuristic ("hide warnings") risks swallowing a genuine, novel warning. An explicit list fails *open* (shows unknown lines) rather than *closed*. Alternative considered: parse opsx structured/JSON output and ignore stderr entirely — rejected because not all opsx/openspec invocations emit machine-readable stderr, and the noise specifically rides on stderr today; the allow-list is robust to that.

**4. Blocker is distinct from worker failure.** On gate failure the binding emits a single operator-facing blocker: change name + noise-filtered validation output + "fix the change artifacts and re-dispatch". It does *not* provision a workspace. Rationale: the operator must be able to tell "malformed change" (fix artifacts) from "worker errored" (re-run / inspect workspace) at a glance.

**5. CLI-absence is its own blocker.** Before validating, the wrapper preflight-checks that the `openspec` CLI is available. If absent, it reports a clear "openspec CLI not found" blocker rather than letting a missing binary masquerade as a validation failure.

## Risks / Trade-offs

- **Allow-list drift** → If opsx changes its harmless-warning wording, an old pattern stops matching and the (still harmless) line resurfaces as noise. Mitigation: the filter fails open (shows the line) — annoying, never dangerous; the allow-list lives in one documented place to update.
- **Over-broad noise pattern accidentally hides a real error** → A pattern written too loosely could swallow a genuine line. Mitigation: patterns are anchored to the specific known phrases, not generic ("must be an array", "Unknown artifact ID in rules"), and the spec requires patterns be specific enough that a genuine error is never matched; exit code is always preserved so a real *failure* is never hidden even if a line is.
- **`ff` ambiguity (new vs existing change)** → `ff` can target either. Mitigation: the gate decides new-vs-existing by whether the change directory already exists; only existing changes are gated. The spec pins this rule.
- **Validation lag on a moving base** → The check validates the resolved base revision; if the orchestrator's stack moves between check and dispatch, the worker could see a different state. Mitigation: out of scope for the typical synchronous dispatch; the check runs immediately before hand-off, so the window is negligible. Noted as an open consideration rather than a guarded invariant.

## Open Questions

- Should the health check optionally run in a `--report-only` advisory mode (warn but still dispatch) for operators who want to proceed past a known-soft validation issue? Default is hard-gate; an advisory escape hatch is deferred unless an operator need emerges.
- Should the noise allow-list be operator-extensible via config, or stay code-owned? Starting code-owned (one documented list); revisit if repos surface their own stable harmless lines.

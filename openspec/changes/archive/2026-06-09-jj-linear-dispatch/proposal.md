## Why

Triage already happens in Linear: a slice is scoped, written up, and labelled ready-for-agent as an issue (or sub-issue). But putting a `jj-delegate` worker on that issue is a manual hop — a human re-reads the issue, hand-copies the slice spec or the referenced change name into a `/jj-delegate` brief, and invents a bookmark. The issue is already the source of truth; what is missing is a one-command bridge from a triaged Linear issue to a dispatched jj worker, with the bookmark and the PR/change-back-link derived deterministically from the issue itself.

## What Changes

- A new **`/jj-from-linear <issue>`** command (shipped in the opt-in `jj-concurrent-linear` plugin) that reads a single Linear issue and dispatches a `jj-delegate` worker from it, so triage-in-Linear is followed by exactly one command to put a worker on the slice.
- A defined **issue-body → workload mapping** with two forms: (a) **referenced opsx change** — the issue body/links name an existing OpenSpec change, so the workload is the authoring/implementing shape over that change (handed to `jj-delegate`, or to `jj-openspec` where that binding is enabled); (b) **slice spec** — the issue body itself is the brief, dispatched as a plain `jj-delegate` slice-spec workload. Detection rules and precedence are specified.
- **Deterministic bookmark naming from the issue identifier** (e.g. `pts-18` → a stable, collision-resistant bookmark), so re-dispatch and resume-in-place target the same bookmark and the orchestrator's ref ownership is preserved.
- A **link-back contract**: the resulting PR/change references the originating Linear issue (issue identifier in the bookmark and surfaced for the PR body/branch), and the dispatch records the issue identity in the orchestrator's manifest so a downstream report→Linear step (the separate `jj-linear-sync` direction) can find the right issue. This change does NOT itself update Linear status.
- Packaging: the command lives in the already-proposed `jj-concurrent-linear` plugin, requiring `jj-concurrent` + a configured Linear MCP; absent (no trigger, no Linear calls) where the plugin is not enabled.

## Capabilities

### New Capabilities
- `jj-linear-dispatch`: the inbound Linear→worker binding — the `/jj-from-linear <issue>` command, the issue-body→workload mapping (referenced opsx change vs slice spec), the issue-id→bookmark naming rule, the PR/change→issue link-back contract, and the separately-enabled-plugin packaging requiring `jj-concurrent` and the Linear MCP.

### Modified Capabilities
<!-- None. This capability layers over jj-delegate's existing workload forms and bookmark/ownership model and over jj-openspec-binding's verb→shape mapping without changing either spec. It is complementary to (and independent of) the in-flight jj-linear-sync capability, which owns the opposite, outbound report→Linear direction; this change does not depend on that one being canonical. -->

## Impact

- Adds a `/jj-from-linear` command (a skill) to the `jj-concurrent-linear` plugin tree (`plugins/jj-concurrent-linear/`), the same opt-in plugin that hosts the outbound `jj-linear-sync` binding. No new marketplace entry beyond the one already introduced by the `jj-concurrent-linear` change.
- Hard dependency on the `jj-concurrent` plugin (`jj-delegate` mechanism, bookmark/ownership model) and on a configured Linear MCP server for reading the issue. Soft, optional reach to `jj-concurrent-openspec` (`jj-openspec`) when the issue references an opsx change and that binding is enabled.
- No change to `jj-delegate`, `jj-workspace-worker`, `jj-safety-hooks`, the worker JSON report shape, or the `jj-openspec-binding` spec — this capability only reads a Linear issue and composes an existing workload form.
- No change to any target project's application code.

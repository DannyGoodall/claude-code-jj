## Context

The `jj-openspec` binding maps an OpenSpec verb to a **shape** and hands off to the generic `jj-delegate` mechanism with the opsx verb invocation as the workload. Two shapes already exist and are stable: the **authoring** shape (`propose`/`new`/`ff` → draft artifacts on the worker's revision, validate, surface for review; bookmark only, no verify, no merge) and the **implementing** shape (`apply` → integrate → verify → push/PR). The binding already carries a provisioning rule that an apply worker is **based on the proposal revision** (seed-intent, no seed commit) so the drafted artifacts are present in the implementing worker's workspace.

What is missing is a single entry point for the most common real workflow: "draft this, let me look, then build it." Today that is two human-initiated commands — `/jj-openspec propose <idea>`, then, after manually reading the result, `/jj-openspec apply <name>` with the base revision re-derived by hand. This change adds a `relay` verb that composes the two existing shapes with a human go/no-go gate between them, so the operator issues one command and the proposal-revision base flows automatically from the approved draft.

Constraints carried from the existing capability: the binding owns no jj/workspace choreography (that is `jj-delegate`'s) and no OpenSpec artifact rules (those are the opsx skills'); workers never own refs or push; provisioning is seed-intent (base revision, no seed commit); the worker contract is non-interactive.

## Goals / Non-Goals

**Goals:**
- Add a `relay` verb that chains authoring → human gate → implementing as one command.
- Reuse the **existing** authoring and implementing shapes unchanged; the relay owns only their ordering and the gate.
- Make the gate a **hard** human go/no-go: the implementing leg never dispatches without an explicit go.
- Seed the implementing leg from the approved proposal revision via the binding's **existing** apply-worker-base rule (seed-intent, no seed commit), resolving that revision from the authoring leg's report rather than re-prompting the human.
- Leave every existing single-shape verb byte-for-byte unchanged.

**Non-Goals:**
- Defining new jj/workspace choreography (provisioning, integration, teardown stay `jj-delegate`'s) or new OpenSpec artifact rules (those stay the opsx skills').
- Auto-approving the gate, adding a timeout, or any "skip the human" mode — the gate is always a human decision in this change.
- Looping the relay (re-draft → re-gate) or batching multiple ideas; the relay is a single draft → gate → apply pass.
- Changing the reconcile tail of either shape, or how PRs/bookmarks are named.

## Decisions

**Decision: `relay` is a composite verb that sequences the two existing shapes, not a third shape.**
The verb-to-shape mapping gains `relay` → composite (authoring-leg → gate → implementing-leg). Each leg dispatches the *same* shape the corresponding single-shape verb already uses, so authoring still validates-and-surfaces with no merge, and implementing still integrates → verifies → push/PR. Rationale over the alternative (a bespoke "relay shape" with its own reconcile tail): a bespoke shape would duplicate and risk drifting from the two proven shapes; composition keeps a single source of truth for each shape and confines the new surface area to ordering + gate.

**Decision: The gate is a mandatory halt between legs; no auto-advance.**
After the authoring leg reports, the binding surfaces the drafted artifacts and stops, requiring an explicit human go/no-go before the implementing leg is even provisioned. Rationale: the whole point of the workflow is that a human reviews the draft before code is written; auto-advancing would defeat it. A no-go must be cheap and non-destructive — it leaves the proposal revision intact for revision or discard and dispatches nothing further. Alternative considered — advance optimistically and let the human abort the apply mid-flight — rejected: it wastes a provisioned implementing worker and muddies the "nothing built without sign-off" guarantee.

**Decision: The implementing leg's base is the proposal revision, resolved from the authoring leg's report.**
The relay reuses the binding's existing "apply worker is based on the proposal revision" rule: the implementing worker's workspace starts from the revision carrying the approved artifacts (seed-intent), with no seed commit. The relay obtains that revision from the authoring leg's structured report (the worker reports the change-id/revision it drafted on) rather than asking the human to re-type the change name or revision at the gate. Rationale: re-deriving the base by hand is exactly the friction this change removes; threading the revision through the gate makes the hand-off automatic while still honouring the existing seed-intent rule. Alternative considered — define a new seeding mechanism for the relay — rejected as redundant; the existing rule already does precisely this.

**Decision: Existing single-shape verbs are untouched.**
`relay` is added alongside `propose`/`new`/`ff`/`apply`/`explore`; none of their mappings, gates (they have none), or reconcile tails change. Rationale: the relay is additive composition, and existing callers must see no behavioural change. This is encoded as a normative requirement, not left implicit.

## Risks / Trade-offs

- **Gate left pending indefinitely (human never decides)** → The relay simply stays parked at the gate with the proposal revision intact; nothing is built and nothing is lost. No timeout/auto-advance is introduced (a non-goal), so the worst case is an un-acted-on draft, identical to today's standalone `propose`.
- **Proposal revision drifts before the human says go (e.g. the draft is revised after the authoring leg reported)** → The implementing leg bases on the revision the authoring leg reported; if the human revised the draft, they re-run the relay (or a standalone `apply`) against the new revision. The relay does not silently re-resolve a moving target.
- **Composing two shapes could leak relay-specific behaviour into a shape** → Mitigated by the requirement that the legs are the existing shapes unchanged; the relay touches only ordering and the gate. Any shape-internal change belongs to that shape's own requirement, not the relay.
- **A no-go could be misread as "discard the draft"** → The requirement is explicit: no-go leaves the proposal revision intact for the human to revise or discard; the relay itself deletes nothing.

## Migration Plan

Documentation/skill-prose change only; no runtime migration. The `relay` verb is purely additive in `plugins/jj-concurrent-openspec/skills/jj-openspec/SKILL.md`: existing verbs keep their behaviour, and `relay` becomes available the moment the prose ships. Rollback is trivial — remove the `relay` mapping and the binding reverts to today's single-shape-only behaviour; no other verb is affected.

## Open Questions

- Exactly how the authoring leg reports its proposal revision to the gate (structured field name in the worker report vs. the binding reading `jj log` for the drafted change) — to be pinned during implementation against the worker-report shape `jj-delegate` already defines.
- Whether the gate surface should also run `openspec validate` on the draft before presenting it (leaning yes — the authoring shape already validates, so the gate can just surface that result rather than re-running it).

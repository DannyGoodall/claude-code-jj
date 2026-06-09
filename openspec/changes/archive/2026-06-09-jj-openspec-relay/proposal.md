## Why

Today `/jj-openspec` runs exactly one OpenSpec verb per invocation: `propose` drafts artifacts and stops at review, `apply` implements an *already-drafted* change. Going from a raw idea to merged code therefore takes two separate human-initiated commands with a manual hand-off in between — the operator must notice the proposal landed, read it, and then remember to issue a second `/jj-openspec apply <name>` pointed at the right revision. The most common real workflow ("draft this, let me look, then build it") has no single entry point, and the apply step's base-revision wiring is re-derived by hand each time instead of flowing automatically from the proposal the human just approved.

## What Changes

- Add a **relay flow** to the `jj-openspec` binding, triggered as `/jj-openspec relay <idea>`, that chains the existing authoring and implementing shapes into one command: draft proposal → **human go/no-go gate** → apply, based on the approved proposal revision.
- The relay's first leg dispatches the **existing authoring shape** (an `/opsx:propose`/`new`/`ff` worker that drafts artifacts on its own revision and surfaces them — no verify, no merge), exactly as `/jj-openspec propose` does today. The relay composes that shape; it does not reimplement authoring.
- After the authoring worker reports, the relay **SHALL halt and surface the drafted artifacts for an explicit human go/no-go**. It SHALL NOT auto-advance to apply. A no-go ends the relay with the proposal revision intact for revision or discard; a go advances to the apply leg.
- On go, the relay dispatches the **existing implementing shape** (an `/opsx:apply <change>` worker with the integrate → verify → push/PR reconcile tail), exactly as `/jj-openspec apply` does today.
- The apply leg's worker SHALL be **based on the approved proposal revision** (seed-intent: the worker's workspace starts from the revision that already carries the drafted artifacts, with **no seed commit**), reusing the binding's existing "apply worker is based on the proposal revision" rule rather than introducing a new seeding mechanism.
- The relay owns only the **composition and the gate**: which shape runs when, and the pause between them. It introduces no new jj/workspace choreography (that stays `jj-delegate`'s) and no new OpenSpec artifact rules (those stay the opsx skills').
- Non-relay invocations are **unchanged**: `/jj-openspec propose` and `/jj-openspec apply` keep their single-shape behaviour exactly; `relay` is an additional verb, not a change to the existing ones.

## Capabilities

### New Capabilities
<!-- None. This feature extends an existing capability rather than introducing a new one. -->

### Modified Capabilities
- `jj-openspec-binding`: the verb-to-shape mapping gains a composite `relay` verb that chains the authoring shape and the implementing shape with a mandatory human go/no-go gate between them, where the implementing leg is seeded (seed-intent, no seed commit) from the proposal revision the human approved.

## Impact

- Affected skill prose: `plugins/jj-concurrent-openspec/skills/jj-openspec/SKILL.md` — the verb-mapping section gains the `relay` verb (composite shape = authoring-leg → gate → implementing-leg) and the gate semantics (halt-and-surface, go/no-go, no auto-advance).
- Affected command surface: a new trigger form `/jj-openspec relay <idea>`; existing `propose`/`new`/`ff`/`apply`/`explore` triggers are untouched.
- Dependencies: relies on the already-shipped authoring shape, implementing shape, and the "apply worker based on the proposal revision" provisioning rule from `jj-openspec-binding`, and on `jj-delegate` for the underlying workspace mechanism. No new external dependency.
- No target-project application code changes — this is orchestration/binding behaviour only.

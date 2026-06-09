## 1. Verb-to-shape mapping: add `relay`

- [x] 1.1 In `plugins/jj-concurrent-openspec/skills/jj-openspec/SKILL.md`, extend the verb-mapping section so `relay` maps to a composite shape: authoring-leg → human gate → implementing-leg
- [x] 1.2 State explicitly that `relay` introduces no new shape — each leg dispatches the existing authoring shape and existing implementing shape unchanged; the relay owns only ordering and the gate
- [x] 1.3 Add the `/jj-openspec relay <idea>` trigger form to the skill's trigger/description prose

## 2. First leg: authoring

- [x] 2.1 Document that the relay's first leg dispatches the authoring shape exactly as `/jj-openspec propose` does (draft artifacts on the worker's revision, validate, surface; no verify, no merge)
- [x] 2.2 Specify that the authoring leg's report must carry the proposal revision (change-id/revision the artifacts were drafted on) so the gate can thread it to the implementing leg

## 3. Human go/no-go gate

- [x] 3.1 Document the gate: after the authoring leg reports, the binding halts and surfaces the drafted artifacts for an explicit human go/no-go, and never auto-advances
- [x] 3.2 Specify the go path: dispatch the implementing leg against the drafted change
- [x] 3.3 Specify the no-go path: dispatch no implementing leg; leave the proposal revision intact for the human to revise or discard (the relay deletes nothing)

## 4. Second leg: implementing, seeded from the proposal revision

- [x] 4.1 Document that on go the relay dispatches the implementing shape exactly as `/jj-openspec apply` does (integrate → verify → push/PR)
- [x] 4.2 Specify that the implementing leg is based on the approved proposal revision via the binding's existing apply-worker-base rule (seed-intent, no seed commit)
- [x] 4.3 Specify that the base revision is resolved from the authoring leg's reported result, not re-supplied by the human at the gate

## 5. Non-relay verbs unchanged

- [x] 5.1 Confirm in prose that `propose`/`new`/`ff`/`apply`/`explore` keep their single mapped shape with no gate and no composition
- [x] 5.2 Add a regression note that `relay` is additive — no existing verb's mapping, gate (none), or reconcile tail changes

## 6. Validation

- [x] 6.1 Run `openspec validate jj-openspec-relay --strict` and resolve any structural errors
- [x] 6.2 Confirm the delta against `openspec/specs/jj-openspec-binding/spec.md` archives cleanly (the MODIFIED requirement header "OpenSpec verb maps to a shape" matches the existing requirement name exactly)
- [x] 6.3 Walk the relay end-to-end on a scratch jj+openspec repo: `/jj-openspec relay <idea>` drafts, halts at the gate; a go applies seeded from the proposal revision; a no-go leaves the proposal intact and dispatches nothing

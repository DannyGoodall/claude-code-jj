# jj-openspec — worked examples

Companion to [the skill](../SKILL.md). The flagship within-a-change fan-out
example lives inline there; these three cover the verify GATE outcomes, the
across-changes pipeline, and the stitched stack.

## The verify GATE (green archives + opens a PR; non-green holds)

Both branches start the same: `/jj-openspec apply <change>` provisions the
worker(s), and jj-delegate integrates their commits onto the one change branch.
Then the orchestrator runs the gate (§5) **once** over the reconciled branch.

**Green apply — archives, then opens a PR.** `/opsx:verify <change>` over the
reconciled branch reports an unambiguous green (every scenario/task satisfied).
The orchestrator continues the tail: it runs `/opsx:archive <change>`, which
syncs the change's delta specs into `openspec/specs/` and moves
`openspec/changes/<change>/` to `openspec/changes/archive/<change>/` — captured
as commits on the **same** change branch. It then runs `/jj-pr <bookmark>`,
pushing the bookmark and opening the GitHub PR over the lifecycle-complete
result (updated canonical specs + archived change), and reports: change,
bookmark, PR URL, `verify: green`, `archived: yes`. A human reviews and merges
one PR that already reflects the closed lifecycle — no manual archive follow-up.

**Failing apply — holds the change un-pushed with a reported reason.**
`/opsx:verify <change>` over the reconciled branch reports a failure (say,
scenario `payment refunds a captured charge` has no implementation, and task
`3.2 wire the refund webhook` is ticked but absent). The gate **stops the tail
immediately**: the orchestrator runs **no** `/opsx:archive`, **no**
trunk-advance, **no** `jj git push`, opens **no** PR. The integrated change sits
on its bookmark, un-pushed, for inspection. The orchestrator reports it as data:
`verify: failed`, the failing scenario(s)/task(s), and the change/bookmark
holding the un-pushed work — so a human or a follow-up `/jj-openspec apply
<change>` can fix the gap. Nothing reached trunk or a PR. (A flaky/inconclusive
verify takes this same fail-safe stop-and-report path.)

## A set of independent changes landed concurrently

Three ready changes — `add-export`, `add-import`, `tidy-logs` — touch disjoint
areas with no inter-change dependency.

`/jj-openspec apply add-export add-import tidy-logs` resolves the verb (apply →
implementing) and the **set** (§B). Each is confirmed to exist and be apply-ready
(`openspec status … --json`); the confirmed set is `{add-export, add-import,
tidy-logs}`, width 3 ⇒ **pipeline** (§4c).

**Dispatch (§4c):** three concurrent siblings to `jj-delegate`, each a whole
change on its OWN bookmark and OWN proposal base-rev:

- Worker 1 — `/opsx:apply add-export` on `feat/add-export`, based on
  add-export's proposal revision.
- Worker 2 — `/opsx:apply add-import` on `feat/add-import`, based on
  add-import's proposal revision.
- Worker 3 — `/opsx:apply tidy-logs` on `feat/tidy-logs`, based on tidy-logs'
  proposal revision.

**Reconcile (§P):** no dependency declared ⇒ **independent landings**. As each
worker reports, jj-delegate integrates it onto trunk and that change's OWN §5
verify → `/jj-pr` tail runs over its OWN result. If `tidy-logs` reports a
blocker, `add-export` and `add-import` still land and verify; `tidy-logs` is
reported **failed** with its workspace left intact. Pipeline summary:
`add-export → landed (PR #N)`, `add-import → landed (PR #M)`,
`tidy-logs → failed (blocker: …, workspace intact)`.

## A declared-dependency stitched stack

Two changes where `add-export-ui` declares a dependency on `add-export-api`
(the UI needs the API's types).

`/jj-openspec apply add-export-api add-export-ui` with the declared dependency
`add-export-ui → add-export-api`. The set is ≥2 apply-ready ⇒ pipeline (§4c);
each is dispatched as a concurrent sibling on its own bookmark/proposal-rev.

**Reconcile (§P):** a dependency is declared ⇒ **stitched stack**. The
topological order is `add-export-api` below `add-export-ui`. After each member's
own §5 verify, the pipeline stacks them in that order and opens the PRs via
`/jj-stacked-pr` (base of `feat/add-export-ui` = `feat/add-export-api`, base of
`feat/add-export-api` = trunk). Pipeline summary:
`add-export-api → stacked (base trunk)`, `add-export-ui → stacked (base
add-export-api)`. (Had the two declared a *cycle*, §P step 3 would abort stacking
with an explicit error rather than invent an order.)

---
name: jj-from-linear
description: |
  Inbound Linear→worker binding over the jj-concurrent orchestrator: one
  command bridges a triaged Linear issue to a dispatched jj-delegate worker.
  /jj-from-linear <issue> resolves a single Linear issue through the Linear
  MCP, maps it to exactly one jj-delegate workload in one of two forms —
  referenced opsx change (the issue names an existing openspec/changes/<name>/,
  dispatched as the opsx shape over it) or slice spec (the issue body is the
  brief) — derives a deterministic bookmark from the issue identifier
  (PTS-18 → pts-18, optionally under a stable prefix), records { issueId,
  issueUrl } in the agent-plan manifest keyed by workspace path, and hands off
  to jj-delegate. The worker stays Linear-agnostic; link-back to the PR/change
  rides the issue-derived bookmark + the manifest record. It fails closed when
  the Linear MCP is unreachable, the issue does not resolve, or a referenced
  change does not exist. It owns no jj/workspace choreography (that is
  jj-delegate's) and no OpenSpec artifact rules (those are the opsx skills').
  Triggers: /jj-from-linear, /jj-from-linear <issue>, "dispatch a worker from
  this Linear issue", "put a jj worker on PTS-18", "run this triaged Linear
  issue as a jj-delegate slice". Requires: the jj-concurrent plugin
  (jj-delegate + jj-workspace-worker) and a configured Linear MCP server
  (mcp__linear-server__*); optional reach to the jj-openspec binding. Enable
  only in Linear-tracked repos.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-from-linear — a triaged Linear issue → one dispatched jj worker

The **inbound** Linear direction: from a triaged Linear issue to a dispatched
`jj-delegate` worker, in **one command**. Triage already scoped the slice,
wrote it up, and labelled it `ready-for-agent`. The remaining gap is the
*first* hop — issue → worker — which today is manual: a human re-reads the
issue, hand-copies the brief or the change name into a delegate call, and
invents a bookmark. `/jj-from-linear <issue>` closes that hop.

It is the **mirror** of the outbound `jj-linear` binding (worker report →
Linear sub-issue update). The two are complementary, touch **disjoint**
lifecycle points (dispatch vs reconcile), and share only the opt-in plugin
packaging and the **manifest-keyed-by-workspace-path** convention. This binding
does **not** depend on the outbound direction being canonical.

It layers **only** over `jj-delegate`'s existing workload forms and
bookmark/ownership model (and, optionally, over `jj-openspec`'s verb→shape
mapping). It owns **no** jj/workspace choreography (that is `jj-delegate`'s) and
**no** OpenSpec artifact rules (those are the opsx skills'). Its single job:
resolve the issue, pick the workload form, derive the bookmark, record issue
identity, and hand off.

It requires the `jj-concurrent` plugin and a configured Linear MCP server
(`mcp__linear-server__*`). Where this plugin is **not** enabled, the
`/jj-from-linear` trigger is **absent** and **no Linear calls are made** — the
orchestrator behaves exactly as the bare `jj-concurrent` mechanism does.

## Relationship to `linear-github-sync` and to the outbound `jj-linear`

This binding automates the **first hop** of the existing `linear-github-sync`
convention. That convention models each fan-out as an **umbrella issue** with
**one sub-issue per slice/worker**, each carrying a `ready-for-agent` label.
Triage (or the outbound `jj-linear` dispatch half) already produced those
issues; this binding **reads** one of them and dispatches a worker from it. It
does **not** create issues, sub-issues, or umbrellas.

- **Inbound (this binding, `jj-from-linear`):** Linear issue → `jj-delegate`
  worker, at the **dispatch** edge. Reads the issue; never writes Linear.
- **Outbound (`jj-linear`):** worker JSON report → Linear sub-issue status, at
  the **reconcile** edge. Writes Linear; never reads the issue body.

They meet only on the agent-plan manifest keyed by workspace path. If the
outbound direction never lands, this command still works end-to-end — the
`{ issueId, issueUrl }` it records is simply unconsumed.

## 1. Scope — one issue, one workload, one bookmark

`/jj-from-linear <issue>` is a **single-slice bridge**. Per invocation it
produces **exactly one** workload and **exactly one** bookmark, and dispatches
**exactly one** `jj-delegate` worker.

- **`<issue>`** is a single Linear issue **identifier** (e.g. `PTS-18`) or a
  single Linear issue **URL**.
- **No fan-out across an umbrella's sub-issues.** Putting workers on many
  sub-issues is the existing `jj-delegate` concurrency, invoked repeatedly —
  not this command. Coupling this binding to umbrella structure would duplicate
  `jj-delegate`'s own fan-out; one-issue-one-worker keeps the contract sharp.

It performs **no** bookmark/ref operation and **no** integration itself —
those are the orchestrator's, per `jj-delegate`.

## 2. Resolve the issue (fail closed)

1. Take the `<issue>` argument and **resolve it through the Linear MCP**
   (`mcp__linear-server__*`) — by identifier or by URL — into the issue's
   title, description/body, and stable identifier + URL.
2. **Fail closed before any provisioning** when either of these holds:
   - the **Linear MCP is unreachable**, or
   - the **issue identifier / URL does not resolve** to a real issue.

   On either failure, **STOP and report it**. Provision **no** workspace,
   derive/create **no** bookmark, dispatch **no** worker — there is nothing to
   clean up. The issue is the **whole input**, so the inbound direction must
   **fail closed** (unlike the outbound direction, whose best-effort/non-fatal
   stance applies because Linear is a side-channel there, not the input).

## 3. Issue body → workload (two forms, with precedence)

Inspect the resolved issue and select **one** of two `jj-delegate` workload
forms. **Referenced-change wins** when both could apply.

### 3.1 Form A — referenced opsx change (precedence)

Detect a **change reference**: a recognised marker in the issue body/links that
names an OpenSpec change. Recognised markers include:

- an `OpenSpec:` or `opsx:` line naming a change, e.g. `OpenSpec: harden-structure-force-purge`;
- an `openspec/changes/<name>` path appearing in the body or a link;
- a fenced/inline change identifier presented as the change to apply.

**The reference is only valid if it resolves** to a real
`openspec/changes/<name>/` directory in the repo.

When it resolves, the workload is the **opsx shape over that change** — a
**skill invocation the worker runs** through its Skill tool. By default the
implementing shape, `/opsx:apply <name>`; the verb may be carried explicitly by
the issue when it names a different opsx verb (propose/new/ff → authoring,
explore → interactive), in which case map to that verb.

- Where the **`jj-openspec` binding is enabled**, hand the change off through
  it so it maps the verb to its shape and resolves OpenSpec-specific parameters.
- Where the **`jj-openspec` binding is absent**, the workload still dispatches
  via **plain `jj-delegate`** as the opsx skill invocation the worker runs
  through its Skill tool. The `jj-openspec` binding is an **optimisation, not a
  hard dependency**.

The issue body is **NOT** dispatched as a free-text slice spec in this form — a
named, already-formalised change is a stronger contract than prose, and
re-deriving intent from the prose would discard the authoring/implementing
rigor the change already encodes.

### 3.2 Form B — slice spec

When **no** recognised change-reference marker is present, the workload is a
**slice spec** whose brief is the issue's **title and description**. A
`jj-delegate` worker is dispatched directly on that slice spec — the worker
implements it as a plain brief, binding-agnostic.

### 3.3 Precedence

When an issue **both** names a resolvable existing change **and** contains prose
that could read as a slice spec, select the **referenced-change** workload
(§3.1). Do **not** dispatch the prose as a slice spec.

### 3.4 Unresolved reference → fail closed

When the issue references a change by name but **no `openspec/changes/<name>/`
directory exists** (a typo, or a not-yet-authored change), **STOP and surface
the unresolved reference**. Do **NOT**:

- fall back to dispatching the issue body as a slice spec, and
- author a new OpenSpec change in response.

Silent fallback would hide a triage error and dispatch a worker against the
wrong intent; inventing a change is the authoring flow's job, not this binding's.
Surfacing keeps the two forms unambiguous.

## 4. Derive the bookmark (deterministic, from the issue id)

Derive the worker's bookmark name as a **pure function of the issue
identifier**:

- take the Linear issue **identifier** (e.g. `PTS-18`),
- **lowercase** and **kebab-normalise** it → `pts-18`,
- optionally under a **stable configured prefix** (e.g. `linear/` → `linear/pts-18`).

Properties this guarantees:

- **Deterministic / pure.** Re-dispatching the **same** issue, or a
  **resume-in-place** successor for the same issue, derives the **identical**
  bookmark name — preserving the orchestrator's single-owner-of-refs model and
  making the issue ↔ bookmark ↔ PR chain legible.
- **Collision-resistant.** Linear identifiers are **team-unique**, so the
  derived name does not collide with the bookmark of a *different* issue. (Never
  derive from the issue *title* — titles change and collide — nor from a random
  suffix, which breaks deterministic re-dispatch/resume.)

The binding **supplies** this name to the orchestrator. It **never creates or
moves the bookmark itself** — that remains the orchestrator's sole
responsibility per `jj-delegate`, which is also where any pre-existing
same-named bookmark is detected rather than clobbered.

## 5. Thread issue identity (worker stays Linear-agnostic)

The dispatched worker is **Linear-agnostic**:

- the worker's **dispatch brief carries no Linear identifier** the worker must
  use or echo,
- the worker's **JSON report carries no Linear identifier**, and
- the worker is **not** given the Linear MCP in its tool surface.

The originating issue identity travels **two orchestrator-owned, non-worker
channels** instead:

1. **The bookmark name** (§4), issue-id-derived, which the orchestrator owns and
   which surfaces on the eventual branch/PR.
2. **The agent-plan manifest**, where the dispatch records, additively:

   ```
   { workspacePath → { issueId, issueUrl } }
   ```

   keyed by the worker's **provision-time workspace path** — the **same stable
   key** the outbound `jj-linear` binding uses. This makes the dispatch resolve
   to the right issue without this binding and that one being coupled: this
   binding only **writes** `issueId`/`issueUrl`; it never reads the outbound
   mapping. (The manifest's physical location and full schema are owned by
   `jj-delegate`; this binding adds only these two optional fields.)

Putting Linear into the worker would leak identifiers/credentials into every
workspace, couple the worker contract to Linear, and let a dying worker leave a
half-written link — so it is held out on both this and the outbound binding.

## 6. Link-back is established at dispatch, realised at PR time

This command does **not** open the PR/change — per `jj-delegate` the
orchestrator's reconcile tail does. The link-back contract this binding
**guarantees** is:

- the **issue identifier is present in the bookmark name** (so the branch/PR
  carries it), and
- the **issue identity is recorded in the manifest** keyed by workspace path.

The orchestrator MAY use the manifest entry to put the issue reference (e.g.
`Closes PTS-18`, a Linear magic-word, or the issue URL) into the PR body when it
opens the PR. Whether Linear is **updated** in response is the **separate
outbound** direction (`jj-linear`). This binding itself performs **no Linear
status update** and opens **no PR**.

## 7. Packaging — separately enabled for Linear-tracked repos only

The `/jj-from-linear` command ships as a thin skill inside the
`jj-concurrent-linear` plugin, alongside the outbound `jj-linear` binding. It
**requires** the `jj-concurrent` plugin (`jj-delegate` + `jj-workspace-worker`)
and a **configured Linear MCP server**.

- **Plugin not enabled** → `/jj-from-linear` is **absent**, no triggers, **no
  Linear calls**; the orchestrator behaves exactly as bare `jj-concurrent`.
- **Linear MCP unreachable / issue does not resolve** → fail closed before any
  provisioning (§2); no worker dispatched.
- **`jj-openspec` binding absent** → the referenced-change workload still
  dispatches via plain `jj-delegate` as the opsx skill invocation the worker
  runs (§3.1).

## Summary

`/jj-from-linear <issue>` is the **inbound** one-command bridge: resolve one
Linear issue through the Linear MCP (**fail closed** if unreachable or
unresolved), map it to **one** `jj-delegate` workload — **referenced opsx
change** (precedence) or **slice spec** — **fail closed** on an unresolved
change reference, derive a **deterministic issue-id bookmark** (`PTS-18` →
`pts-18`, optionally prefixed), record `{ issueId, issueUrl }` in the manifest
keyed by workspace path, and **hand off** to `jj-delegate`. The worker stays
Linear-agnostic; link-back rides the issue-derived bookmark + the manifest
record; opening the PR and any Linear status update are **not** this binding's
job. Complementary to, and independent of, the outbound `jj-linear` direction.

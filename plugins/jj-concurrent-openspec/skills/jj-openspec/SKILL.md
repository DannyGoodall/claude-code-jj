---
name: jj-openspec
description: |
  Background an OpenSpec workflow verb in its own jj workspace via the
  jj-concurrent orchestrator. Maps the verb to a shape (implementing vs
  authoring) and the right reconcile tail. Triggers: /jj-openspec <verb>
  [change], "apply <change> on a jj workspace", "draft a proposal in the
  background", "propose/new/ff <change> with a jj worker". Requires: a jj repo
  (ideally colocated), the jj-concurrent plugin (jj-delegate + jj-workspace-worker),
  an openspec/ directory, and the opsx skills available in-session.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-openspec — OpenSpec verbs on jj workspaces

A thin binding: resolve the OpenSpec-specific parameters, then hand off to the
`jj-delegate` skill (jj-concurrent plugin) with `/opsx:<verb> <args>` as the
workload. This skill owns nothing about jj/workspace choreography (that is
jj-delegate's) and nothing about OpenSpec artifact rules (those are the opsx
skills'). If either changes, this binding should not need to.

## The verb → shape map

OpenSpec verbs share inference (change-name resolution, bookmark naming, issue
tracker) and differ only in **shape** — what the worker produces and how you
reconcile it:

| Verb(s) | Shape | What the worker produces | Reconcile tail |
|---------|-------|--------------------------|----------------|
| `apply` | **Implementing** | code changes + ticked tasks.md | integrate → `/opsx:verify` → issue-tracker update → push/PR |
| `propose` / `new` / `ff` | **Authoring** | the change artifacts under `openspec/changes/<name>/` (proposal/design/specs/tasks) | surface artifacts for review; bookmark only; **no verify, no merge-to-main** (nothing is implemented yet) |
| `explore` | **Interactive** | (a thinking partner — file output only when asked) | NOT a default background candidate. Only background as "autonomous exploration → a written findings doc" when the user explicitly asks. Otherwise run it inline, not via a worker. |

## 1. Resolve the verb + change

- **verb** — first token of the arguments (`apply`, `propose`, `new`, `ff`,
  `explore`). If absent, infer from context; if still unclear, ask.
- **change name** — in order: explicit argument → the change under discussion
  → for implementing verbs, `openspec list --json` filtered to changes with
  unticked tasks (use it if exactly one); else ask.
- For **apply**: validate the change exists and is apply-ready
  (`openspec status --change "<name>" --json`). If apply-required artifacts are
  missing, stop and tell the user to author the change first (a `propose` run).
- For **propose/new/ff**: the change may not exist yet — that is the point.

## 2. Derive the bookmark

- **Implementing**: `feat/<short-slug>` from the change name.
- **Authoring**: `change/<short-slug>` (signals it is a proposal, not an
  implementation, so reviewers and the merge step treat it accordingly).

## 3. Base revision — what the worker's workspace must contain

This is where the verbs differ in provisioning (and where jj removes the git
seed-commit ceremony — see jj-delegate §3):

- **apply**: the change's `openspec/changes/<name>/` artifacts must already
  exist on the base revision. They are usually already present and snapshotted
  in `@` (jj has no untracked limbo). Base the worker on the curated revision
  that holds them: pass `jj-delegate` a base-rev of `@` (after confirming `@`
  is clean) or a dedicated change-rev. If the artifacts are NOT yet committed
  anywhere clean, describe the current change first (`jj describe -m
  "docs(openspec): <name> change artifacts"`) so there is a named revision to
  base on — this is the jj-light analog of the old seed commit (a describe, not
  an add+commit dance).
- **propose/new/ff**: base on trunk; the worker CREATES the artifacts in its
  workspace.

## 4. Hand off to jj-delegate

Invoke the `jj-delegate` skill with:

- **workload (skill form)**: `/opsx:<verb> <change-or-args>` — the worker
  invokes the opsx skill (fallback skill names: `opsx:apply` →
  `openspec-apply-change`, `opsx:propose` → `openspec-propose`, etc.). For
  `apply`, the dispatch brief tells the worker to work through `tasks.md` via
  the skill (which owns task selection + checkbox discipline), never hand-edit
  artifacts outside it, and commit the ticked `tasks.md` alongside the
  implementation so progress travels with the workspace.
- **bookmark**: from §2.
- **base-rev**: from §3.

jj-delegate runs the confirm → provision → dispatch (background by default) →
reconcile lifecycle.

## 5. Reconcile tail (after jj-delegate integrates the worker's commits)

**Implementing (`apply`)**, in the primary workspace:

1. Run `/opsx:verify <change>` against the integrated result (check out / log
   the worker's commits; jj makes them visible without a checkout dance).
2. If the project links changes to an issue tracker (e.g. a Linear umbrella
   issue per change), update it with the push/PR link and status.
3. Push / open the PR (`jj git push -b <bookmark>` + `gh pr create`, or your
   forge flow). Report: change, bookmark, PR, verify outcome, remaining
   unticked tasks.

**Authoring (`propose`/`new`/`ff`)**, in the primary workspace:

1. Run `openspec validate <change>` on the drafted artifacts.
2. Surface them for review — either push the `change/<slug>` bookmark and open
   a draft PR, or simply report the new `openspec/changes/<name>/` tree for the
   user to inspect. Do NOT merge to main and do NOT verify (there is no
   implementation yet).
3. Report: change name, the artifacts created, validate outcome, and the
   natural next step (`/jj-openspec apply <name>` once the proposal is agreed).

## Variants

- **Background** is the default (the session stays free; another `/jj-openspec`
  or `/jj-delegate` can run a second independent slice concurrently).
- **Foreground** ("and wait") — passes through to jj-delegate's foreground mode.
- **Relay** (author then apply): run `/jj-openspec propose <name>`; once the
  proposal is agreed, run `/jj-openspec apply <name>` — the apply worker bases
  on the revision the authoring run produced.

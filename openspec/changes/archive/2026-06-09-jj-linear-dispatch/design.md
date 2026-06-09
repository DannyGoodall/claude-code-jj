## Context

`jj-concurrent` defines a `jj-delegate` orchestrator that fans out `jj-workspace-worker` subagents, each in its own jj workspace. A workload is one of two forms (from the `jj-delegate` spec): a **skill invocation** the worker runs via its Skill tool (e.g. `/opsx:apply <change>`), or a plain **slice spec** the worker implements directly. The orchestrator owns all bookmark/ref operations and integration; the worker owns only its own commits and stays binding-agnostic.

`jj-openspec-binding` layers over that mechanism: it maps an OpenSpec **verb** to a **shape** (apply → implementing; propose/new/ff → authoring; explore → interactive) and resolves OpenSpec-specific parameters (change name, bookmark naming, base revision) before handing off to `jj-delegate`. It owns no jj/workspace choreography and no OpenSpec artifact rules.

Teams here triage in Linear: a slice is scoped as an issue (or sub-issue under an umbrella), written up, and labelled ready-for-agent (`docs/agents/triage-labels.md`, the `linear-github-sync` convention). The remaining gap is the *first* hop — from a triaged issue to a dispatched worker. Today that hop is manual: a human re-reads the issue, copies the brief or change name into a delegate call, and invents a bookmark. This change closes that hop with `/jj-from-linear <issue>`.

This is the **inbound** Linear direction (issue → worker). It is the mirror of the in-flight `jj-concurrent-linear` change's `jj-linear-sync` capability, which is the **outbound** direction (worker report → Linear sub-issue update). The two are complementary, touch disjoint lifecycle points (dispatch vs reconcile), and share only the opt-in plugin packaging and the manifest-keyed-by-workspace-path convention. This design does not depend on `jj-linear-sync` being canonical.

## Goals / Non-Goals

**Goals:**
- One command — `/jj-from-linear <issue>` — that reads a single Linear issue and dispatches a `jj-delegate` worker from it.
- A precise, two-form mapping from the issue to a `jj-delegate` workload: **referenced opsx change** (the issue names an existing OpenSpec change) vs **slice spec** (the issue body is the brief), with deterministic detection and precedence.
- A deterministic, collision-resistant **bookmark name derived from the Linear issue identifier**, stable across re-dispatch and resume-in-place.
- A **link-back contract** so the resulting PR/change carries the originating issue identity, and the dispatch records that identity in the orchestrator's manifest for a downstream outbound step to consume.
- Opt-in packaging in the `jj-concurrent-linear` plugin, requiring `jj-concurrent` + a Linear MCP; absent where not enabled.

**Non-Goals:**
- Updating Linear issue status or posting comments — that is the outbound `jj-linear-sync` direction; this command only *reads* the issue and *records* its identity.
- Creating issues, sub-issues, or umbrellas — triage produced the issue already.
- Opening the PR or doing the integration — that is the orchestrator's reconcile tail per `jj-delegate`; this command stops at dispatch + identity recording.
- Owning jj/workspace choreography or OpenSpec artifact rules — those belong to `jj-delegate` and the opsx skills respectively; this binding composes them.
- Authoring the OpenSpec change when one is referenced — if the issue names a change that does not yet exist, that is surfaced, not invented here.

## Decisions

**Decision: The command reads exactly one issue and produces exactly one workload + one bookmark.**
`/jj-from-linear <issue>` takes a single Linear issue identifier (e.g. `PTS-18`) or URL, resolves it via the Linear MCP, and composes a single `jj-delegate` dispatch. Fan-out across many issues (an umbrella's sub-issues) is explicitly out of scope for this command — it is a single-slice bridge that the existing `jj-delegate` concurrency can be invoked over repeatedly. *Alternative considered:* accept an umbrella and fan out every sub-issue. Rejected — that couples this binding to umbrella structure and duplicates `jj-delegate`'s own fan-out; one-issue-one-worker keeps the contract sharp and composes cleanly.

**Decision: Two workload forms, with referenced-opsx-change taking precedence over slice-spec.**
The binding inspects the resolved issue for a **reference to an existing OpenSpec change**: a change name appearing in a recognised marker (e.g. an `OpenSpec:`/`opsx:` line, a `openspec/changes/<name>` path, or a fenced change identifier) that resolves to a real `openspec/changes/<name>/`. If found, the workload is the **opsx shape over that change** (handed to `jj-delegate`, or to `jj-openspec` where the OpenSpec binding is enabled, which maps the verb to its shape). Otherwise the workload is a **slice spec** whose brief is the issue body (title + description). Precedence is referenced-change first because a named change is a stronger, already-formalised contract than free-text. *Alternative considered:* always treat the body as a slice spec and ignore change references. Rejected — it would discard an existing OpenSpec contract and re-derive intent from prose, losing the authoring/implementing rigor the change already encodes.

**Decision: A referenced change that does not resolve is a surfaced error, not an invented change.**
If the issue references a change name but no `openspec/changes/<name>/` exists, the command STOPS and reports the unresolved reference rather than falling back to slice-spec or authoring a new change. This keeps the two forms unambiguous and prevents a typo'd reference from silently dispatching the whole issue body as a brief. *Alternative considered:* fall back to slice-spec on an unresolved reference. Rejected — silent fallback hides triage errors and can dispatch a worker against the wrong intent.

**Decision: Bookmark name is derived deterministically from the issue identifier.**
The bookmark is `<issue-id-slug>` (the Linear issue identifier lowercased and kebab-normalised, e.g. `PTS-18` → `pts-18`), optionally with a stable, configured prefix (e.g. `linear/pts-18`). The derivation is a pure function of the issue identifier, so re-dispatching the same issue, or a resume-in-place successor, targets the **same** bookmark — preserving the orchestrator's single-owner-of-refs model and making the issue↔bookmark↔PR chain legible. The slug is collision-resistant because Linear identifiers are unique within a team. *Alternative considered:* derive the bookmark from the issue title or a random suffix. Rejected — titles change and collide; randomness breaks the deterministic re-dispatch/resume property and the legible link-back.

**Decision: The worker stays Linear-agnostic; issue identity lives in the bookmark and the manifest, never in the worker brief.**
Consistent with `jj-delegate` (workers own only their commits) and with the outbound binding's stance, the dispatched worker receives only its workload (slice spec or opsx invocation) and its workspace — no Linear identifier and no Linear MCP in its tool surface. The originating issue identity travels two non-worker channels: (1) the **bookmark name** (issue-id-derived), which the orchestrator already owns and which surfaces on the eventual PR/branch; (2) the **orchestrator's agent-plan manifest**, where the dispatch records `{ workspacePath → { issueId, issueUrl } }` keyed by workspace path — the same stable key the outbound `jj-linear-sync` binding uses, so a downstream report→Linear step can find the right issue without this command and that one being coupled. *Alternative considered:* pass the issue ID into the worker brief so the worker links back itself. Rejected — it leaks Linear identifiers into every workspace, couples the worker contract to Linear, and a dying worker could leave a half-written link.

**Decision: Link-back is established at dispatch (bookmark + manifest), realised at PR time by the orchestrator.**
This command does not open the PR; per `jj-delegate` the orchestrator's reconcile tail does. The link-back contract this binding guarantees is: the issue identifier is present in the bookmark name (so the branch/PR carries it) and the issue identity is recorded in the manifest keyed by workspace path. The orchestrator MAY use the manifest entry to put the issue reference (e.g. `Closes PTS-18` / a Linear magic-word or URL) into the PR body when it opens the PR. Whether Linear is *updated* in response is the separate outbound direction. *Alternative considered:* have this command open the PR with the link. Rejected — opening the PR is the orchestrator's owned step; this binding only supplies the identity needed for the link.

**Decision: Mirror `jj-concurrent-openspec` / `jj-concurrent-linear` packaging.**
The command ships as a thin `jj-from-linear` skill inside `plugins/jj-concurrent-linear/skills/`, alongside the outbound binding skill. Frontmatter declares the hard requirement on `jj-concurrent` + the Linear MCP and the triggers (`/jj-from-linear`, "dispatch a worker from this Linear issue"). It owns no jj/workspace choreography (that is `jj-delegate`'s) and no OpenSpec artifact rules (those are the opsx skills'); it resolves the issue, picks the workload form, derives the bookmark, records identity, and hands off.

## Risks / Trade-offs

- **Ambiguous issue body — is it a change reference or a slice spec?** → Mitigated by a single explicit detection rule (a recognised change-reference marker that resolves to a real `openspec/changes/<name>/`); anything else is a slice spec, and a marker that fails to resolve is a surfaced error, never a silent fallback.
- **Linear MCP unavailable or the issue identifier does not resolve** → The command STOPS before dispatch and reports it; no workspace is provisioned and no bookmark is created, so there is nothing to clean up. (Best-effort/non-fatal behaviour belongs to the outbound direction; the inbound direction must fail closed because the issue is the whole input.)
- **Bookmark collision with an unrelated existing bookmark** → Mitigated by the issue-id-derived (optionally prefixed, e.g. `linear/`) namespace; Linear identifiers are team-unique, and the orchestrator (sole ref owner) is the one that creates/moves the bookmark, so a pre-existing same-named bookmark is detected by the orchestrator rather than clobbered.
- **Referenced change exists but the OpenSpec binding (`jj-openspec`) is not enabled** → The workload still dispatches via plain `jj-delegate` as a skill invocation (`/opsx:apply <change>` or the relevant verb) the worker runs through its Skill tool; the `jj-openspec` binding is an optimisation, not a hard dependency.
- **Coupling to the in-flight `jj-linear-sync` change** → Avoided: this binding only *writes* identity into the manifest (an additive `{ issueId, issueUrl }` keyed by workspace path) and never reads or depends on the outbound mapping. If `jj-linear-sync` never lands, the inbound command still works end-to-end; the manifest entry is simply unconsumed.
- **Manifest schema is owned by `jj-delegate`** → This binding only adds optional `issueId`/`issueUrl` fields keyed by workspace path and coordinates with the manifest format if/when it is formalised; it asserts no other manifest structure.

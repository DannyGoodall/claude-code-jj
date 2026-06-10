# Linkstack: a complete walkthrough of the claude-code-jj plugins

> A start-to-finish story for people who *use* Claude Code but don't want to learn jj, GitHub, Linear, and OpenSpec in depth first. You'll watch one person build one tiny website and, along the way, touch **every feature** of all three plugins. For each step you see what they typed into Claude — and, in a folded "Under the hood" box, the raw commands the plugin ran so you didn't have to.

## Who and what

**Sam** is a vibe coder. They can describe what they want, they can read code, but they've never memorised a `git rebase` flag in their life. Sam is building **`linkstack`** — a one-page "link in bio" site, the kind you put in a social profile. It's three files:

```
linkstack/
├── index.html   # the page
├── style.css    # how it looks
└── app.js       # the little bit of interactivity
```

That's the whole app. It's deliberately tiny — you don't need to understand websites to follow along. Every time Sam wants to change it ("add a dark-mode button", "show a list of links"), that's an excuse to use one more plugin feature.

Sam works on a Mac, has the **GitHub CLI** (`gh`) signed in, uses **Linear** now and then for planned work, and has the three plugins installed: `jj-concurrent`, `jj-concurrent-openspec`, `jj-concurrent-linear`. Sam also has **jj** installed (and git, obviously) and **OpenSpec** installed — but OpenSpec is *not yet initialised* for this repo (that matters later: when Sam first reaches for it in [§9](#9-a-change-worth-writing-down-first), Claude has to initialise it before any proposal can be written).

Why jj on top of git? Because Sam runs *concurrent* OpenSpec changes — several proposals and applies in flight at once — and jj manages that far better than git does. Here's the aside worth knowing: if you parallelise with **git worktrees**, each worktree is its own checked-out copy and they don't share the live state of the OpenSpec spec repository (the `openspec/` tree), so two concurrent OpenSpec changes step on each other's spec edits. jj **workspaces** all share one underlying repo and object store, so concurrent OpenSpec work composes cleanly instead of clobbering itself. That's the real reason jj is the layer underneath here.

## How to read this

Every feature gets the same shape, so you can skim:

> **The requirement** — what Sam wants, in plain words.

**In Claude** — the actual back-and-forth (`you:` is Sam, `claude:` is Claude Code).

> **🔧 Skill:** the plugin skill doing the work, and one line on what it is.
> **💡 Tip:** one or more things worth knowing about this feature.

**Under the hood** — the `jj` / `gh` / Linear commands the plugin ran for you. You almost never type these yourself; they're here so you can see what's being abstracted (and so the one time you *do* drop to the command line, it's familiar).

**One rule we'll follow the whole way:** Sam uses **GitHub** all the time (it's where the code lives, where pull requests happen, and where the occasional drive-by bug report lands as a GitHub issue). Sam uses **Linear** only for *planned* work that they want to hand to background agents — Linear is the "work queue for robots". So the rule for which tracker shows up when is simple: **GitHub** for ad-hoc, externally-reported, or small work; **Linear** for planned work that gets handed to background agents.

---

## Setup: turning a folder into a jj-on-GitHub project

> **The requirement.** Sam has the three files in a folder and a GitHub repo. They want Claude to be able to work safely — saving constantly, never doing anything destructive.

**In Claude**

```
you:    set this folder up to work with the jj plugins, pointing at my GitHub repo
claude: I'll colocate jj with git so GitHub still works, confirm the plugins are
        active, and the safety hooks will start protecting the repo. Running setup…
        ✓ jj initialised (colocated with git)
        ✓ main is tracking origin/main
        ✓ snapshot + guard hooks active
        You're ready. Every edit I make from here is auto-saved, and risky
        commands are blocked.
```

> **🔧 Skill:** the **snapshot hook** and **guard hook** (`jj-concurrent`, capability `jj-safety-hooks`) — two background "tripwires" that run on every tool call. You never invoke them; they're always on.
> **💡 Tips:**
> - **"Colocated" just means jj and git share one folder.** GitHub still sees a normal git repo; jj is a friendlier layer on top. You lose nothing.
> - The **snapshot hook** saves your work-in-progress after *every* edit, so a crash can never lose work. The **guard hook** refuses dangerous commands (raw `git push`, deleting the `.jj` store) — more on that in [§6](#6-the-guardrail-youll-be-glad-about).

**Under the hood**

```bash
# one-time, to make a git repo jj-aware without disturbing git or GitHub:
jj git init --colocate
jj bookmark track main --remote=origin    # so "main" follows GitHub's main

# the hooks are wired by the plugin; conceptually they run:
#   after every edit  → jj util snapshot      (the snapshot hook)
#   before every Bash → inspect the command   (the guard hook; blocks raw git/rm .jj)
```

---

# Part 1 — the everyday loop

*Foreground Claude · no OpenSpec · no CI yet.* This is how most days go: Sam asks for a small change, Claude makes it, it ships. No ceremony.

## 1. Ship a dark-mode button

> **The requirement.** Add a button that toggles dark mode. It's a small, obvious change — not worth any planning ceremony.

**In Claude**

```
you:    add a dark-mode toggle button to the page
claude: [edits index.html, style.css, app.js]
        Added a 🌙 button top-right; it flips a `dark` class on <body> and
        remembers the choice in localStorage. Want me to open a PR?
you:    yes
claude: Pushed bookmark feat/dark-mode and opened PR #1.
        https://github.com/sam/linkstack/pull/1
```

While Claude was editing, the **snapshot hook** quietly saved after every file change — so even mid-way, nothing was at risk.

Sam is curious what actually happened, so they peek with raw jj (one of the few times they touch the command line):

```
you:    ! jj log
claude: (runs it for you)
   @  feat/dark-mode  Add dark-mode toggle
   ◆  main  Initial linkstack
```

> **🔧 Skill:** **`/jj-pr`** (`jj-concurrent`) — the "submit" button jj doesn't have: it pushes your bookmark to GitHub and opens (or updates) the pull request.
> **💡 Tips:**
> - In jj, your in-progress work *is* a commit (called `@`). You don't `git add` anything — the snapshot hook already captured it.
> - `! <command>` in Claude runs a shell command in your session — handy for a quick `jj log` or `jj st` without leaving the chat.

**Under the hood**

```bash
jj git push --bookmark feat/dark-mode           # push the branch to GitHub
gh pr create --base main --head feat/dark-mode \
   --title "Add dark-mode toggle" --body "<generated from the change>"
```

Now Sam merges it. **There's no CI yet** — no tests, no checks — so landing is immediate.

**In Claude**

```
you:    land it
claude: PR #1 is mergeable. Merging…
        ✓ Merged #1, synced main, deleted the branch. Clean.
```

> **🔧 Skill:** **`/jj-land`** (`jj-concurrent`) — merges a PR (or a whole stack of them) and tidies up: syncs your local `main`, deletes the merged branch.
> **💡 Tips:**
> - With **no CI**, `/jj-land` merges as soon as GitHub says the PR is mergeable. Later (Part 3) we'll add CI and watch `/jj-land` start *waiting for green*.
> - It always cleans up after itself — no stale branches pile up on GitHub.

**Under the hood**

```bash
gh pr merge 1 --squash          # merge (single PR → squash)
jj git fetch                    # pull the new main
jj new main                     # start fresh on top of main
gh api -X DELETE repos/sam/linkstack/git/refs/heads/feat/dark-mode   # tidy
```

## 2. Tidy up scattered review fixes

> **The requirement.** A friend reviewed the dark-mode PR and Sam made a handful of little fixes — a colour here, a label there. The fixes belong in *different* earlier commits, not dumped in one "address review" blob.

**In Claude**

```
you:    I've made the review fixes in my working copy — put each one back where
        it belongs
claude: Running absorb…
        absorbed:
          style.css (button colour)   → the "dark-mode toggle" commit
          index.html (aria-label)     → the "dark-mode toggle" commit
        Nothing ambiguous left over. Re-pushed the PR.
```

> **🔧 Skill:** **`/jj-absorb`** (`jj-concurrent`) — takes the loose edits in your working copy and slots each one into the existing commit that last touched those lines. The tidy version of "amend the right commit".
> **💡 Tips:**
> - This is the jj superpower that replaces fiddly interactive rebases. You edit freely; absorb files each change where it belongs.
> - If a fix is *ambiguous* (could belong to two commits), absorb leaves it in your working copy and tells you — it never guesses wrong.

**Under the hood**

```bash
jj absorb            # move each working-copy hunk into its owning ancestor commit
jj git push --bookmark feat/dark-mode    # update the PR in place
```

## 3. Address PR comments in one shot

> **The requirement.** This time the review comments are *on the GitHub PR* itself — three inline comments asking for small changes. Sam doesn't want to read them one by one.

**In Claude**

```
you:    address the review comments on PR #2 and update it
claude: Read 3 unresolved comments on #2. Briefed a worker on top of the PR's
        code, applied the fixes, absorbed each into the commit it was about,
        and re-pushed. PR #2 updated in place — no extra "fixup" commit.
```

> **🔧 Skill:** **`/jj-pr-fixup`** (`jj-concurrent`) — reads a PR's review comments, makes the fixes, and tucks each into the right commit, then updates the same PR. The whole "amend after review" loop in one command.
> **💡 Tips:**
> - The reviewer asked you to fix commit B → commit B gets amended. No confusing "fixup!" commit dangling at the top of the branch.
> - It only acts on **unresolved** comments, so resolved threads don't cause churn.

**Under the hood**

```bash
gh pr view 2 --json reviews                          # read review summaries
gh api repos/sam/linkstack/pulls/2/comments          # read line-anchored comments
jj workspace add -r <pr-head> ../wt-fixup-2           # work on top of the PR's code
#   …apply fixes…
jj absorb                                            # land each fix in its commit
jj git push --bookmark feat/<pr-branch>              # update PR #2 in place
```

## 4. A risky refactor, with an undo button

> **The requirement.** Sam wants to reorganise `app.js` into small functions. It might go badly. They want a guaranteed way back.

**In Claude**

```
you:    checkpoint first, then refactor app.js into smaller functions
claude: Saved checkpoint "before-refactor". Refactoring…
        [edits app.js]
        Done — split into init(), toggleDark(), loadLinks().
you:    hmm, that broke the toggle. undo the whole thing.
claude: Rewinding to "before-refactor"… ✓ app.js is exactly as it was.
```

> **🔧 Skill:** **`/jj-checkpoint`** and **`/jj-rewind`** (`jj-concurrent`) — drop a named save-point before something risky, then roll the *entire repo* back to it in one step if you don't like the result.
> **💡 Tips:**
> - jj records every operation, so "undo" is real and total — `/jj-rewind` puts everything back, not just one file.
> - The rewind is itself undoable. You genuinely cannot paint yourself into a corner.

**Under the hood**

```bash
# /jj-checkpoint "before-refactor" reads the current operation id and records it
# under that label (it only *remembers* the id — it never changes history):
jj op log                       # every jj operation has an id; this grabs the latest

# /jj-rewind "before-refactor" looks up that saved op id and rolls the WHOLE repo
# back to it by running:
jj op restore <the-saved-op-id> # the whole-repo time machine
```

## 5. See it running before you merge

> **The requirement.** Sam added a little "visitor count" widget. Screenshots lie; they want to *see the actual page* running before merging.

**In Claude**

```
you:    let me see the visitor-count change running
claude: Spinning up a throwaway preview of that change…
        ✓ Serving at http://localhost:5174 (PID 48211). Open it in your browser.
you:    looks great, shut it down
claude: Stopped the preview and removed the throwaway workspace. Your main work
        is untouched.
```

> **🔧 Skill:** **`/jj-preview`** (`jj-concurrent`) — stands up any revision as a real running app in a disposable workspace, on its own port, then tears it down.
> **💡 Tips:**
> - It's **read-only to your history** — previewing never moves anything or touches your current work. Look, then throw it away.
> - Great for "does this actually work?" moments before you commit to merging.

**Under the hood**

```bash
jj workspace add -r <rev> ../wt-preview-visitor    # disposable copy at that revision
#   …run the project's dev command on a free port…
python3 -m http.server 5174 -d ../wt-preview-visitor   # (linkstack is static)
#   …when done:
jj workspace forget wt-preview-visitor && rm -rf ../wt-preview-visitor
```

## 6. The guardrail you'll be glad about

> **The requirement.** Sam, copying a Stack Overflow answer, pastes a raw `git push --force`. In a jj repo that's a great way to confuse everything.

**In Claude**

```
you:    ! git push --force origin main
claude: ⛔ Blocked by the guard hook: raw mutating git in a jj repo can desync
        jj and git. Use the plugin's push instead (it's what /jj-pr does):
            jj git push --bookmark <name>
        Nothing was run.
```

> **🔧 Skill:** the **guard hook** (`jj-concurrent`, `jj-safety-hooks`) — a tripwire that runs *before* shell commands and refuses the dangerous ones.
> **💡 Tips:**
> - It blocks raw mutating `git`, interactive jj commands that would hang, and `rm` on the `.jj`/`.git` stores. It also enforces that **background workers never push or move branches** — only you (the orchestrator) do.
> - It's a backstop, not a nanny: normal commands run untouched.

**Under the hood**

```text
PreToolUse(Bash) → guard inspects the command string →
   matches "git push --force" in a jj repo → DENY with an explanation.
```

---

# Part 2 — going bigger

*Background workers · OpenSpec.* Some jobs are big enough that Sam wants to keep working while Claude handles them, or formal enough to deserve a written spec.

## 7. Hand a job to a background worker

> **The requirement.** Sam wants a proper "links" section (a list of links with icons). It'll take a few minutes. Sam would rather keep tweaking the CSS while it happens.

**In Claude**

```
you:    add a links section — a list of links with icons. Do it in the background
        so I can keep working.
claude: Plan: workload "add a links section", bookmark feat/links, its own
        workspace ../wt-links, based on main. Proceed?
you:    yes
claude: Dispatched a background worker. Your terminal is free — keep going.
        (a minute later) ✓ Worker done: added a <ul> of links + icon styles.
        Reconciled onto bookmark feat/links and opened PR #5.
```

> **🔧 Skill:** **`/jj-delegate`** (`jj-concurrent`) — runs a job as a **background worker** in its own isolated workspace (a separate copy of the files), then folds the result back in. The worker itself is the **`jj-workspace-worker`** agent.
> **💡 Tips:**
> - **Control returns to you immediately.** The instant the worker is dispatched, control hands back to your Claude session — for the *whole* duration of the background task you keep talking to Claude and keep working. You're not blocked waiting; you reconvene only when the worker reports done.
> - **Foreground vs background:** in Part 1 Claude edited your files directly (foreground). A delegated worker edits *its own copy* in a separate folder, so you can safely keep working in yours at the same time.
> - Workers do the *work*; only you (the "orchestrator") ever push or open PRs. That division is what the guard hook from [§6](#6-the-guardrail-youll-be-glad-about) enforces.

**Under the hood**

```bash
jj workspace add -r main ../wt-links        # a private copy of the repo for the worker
# → background agent edits files in ../wt-links and reports back
# you then reconcile + submit:
jj bookmark create feat/links -r <worker-commit>
jj git push --bookmark feat/links
gh pr create --base main --head feat/links --title "Add links section"
```

## 8. "What are the robots doing?"

> **The requirement.** Sam has just asked Claude to delegate **two** jobs in the background — add a links section *and* add a footer. Control came straight back to the terminal, and while both workers run Sam wants a single glance at how they're getting on.

Sam delegated the two tasks one after the other (`/jj-delegate` provisions a separate workspace for each), got control back to the Claude session both times, and — with both workers still churning away — asks for a status view.

**In Claude**

```
you:    show the fleet
claude:  WORKSPACE        CHANGE              STATUS      BOOKMARK
         ../wt-links      add links section   ✓ done      feat/links
         ../wt-footer     add a footer        ⏳ running   feat/footer
```

> **🔧 Skill:** **`/jj-fleet`** (`jj-concurrent`) — one status table of every background worker: what it's doing, whether it's done, which branch it owns.
> **💡 Tips:**
> - It's **read-only** — looking at the fleet never disturbs a worker.
> - Useful when you've delegated two or three things at once and want to know which to reconcile first.

**Under the hood**

```bash
jj util snapshot                 # make sure every workspace's view is current
jj workspace list                # the live workspaces
# the plugin joins that against its plan file to show status per worker
```

## 9. A change worth writing down first

> **The requirement.** Linkstack is getting a little more complex now, and Sam realises the next feature — **theme presets** (a few colour themes) — has real decisions in it: which themes, how they're stored. This is the moment to *plan*, so Sam reaches for OpenSpec. But OpenSpec is installed and never initialised for this repo (back in "Who and what"), so the first thing Sam has to do is ask Claude to initialise it — then propose the feature.

**In Claude**

```
you:    set up OpenSpec for this repo
claude: Initialising OpenSpec… ✓ created the openspec/ directory (specs/, changes/,
        and the project config). You can now author and apply changes.
you:    propose a "theme presets" feature with OpenSpec — I want to see the plan
        before any code
claude: Drafting the proposal in the background…
        ✓ Authored change "theme-presets": why, the design choices, the spec
        (3 themes, stored in localStorage), and a task list. Opened PR #7 with
        just the proposal — no code yet. Review it and tell me to apply.
```

> **🔧 Skill:** **`/jj-openspec propose`** (`jj-concurrent-openspec`) — writes a full OpenSpec change (the *why*, the design, the spec, the task list) on a background worker, so you can approve the plan before a line of code exists.
> **💡 Tips:**
> - OpenSpec separates **deciding what to build** (the proposal) from **building it** (apply). The proposal PR is a cheap place to argue about the design.
> - You only reach for this when a change has decisions in it. The dark-mode button in [§1](#1-ship-a-dark-mode-button) didn't need it; theme presets do.

**Under the hood**

```bash
openspec new change theme-presets                # scaffold the change folder
#   …worker writes proposal.md, design.md, specs/…/spec.md, tasks.md…
openspec validate theme-presets --strict          # the proposal must be well-formed
gh pr create --title "Propose: theme presets"     # a proposal-only PR
```

## 10. Build the proposed change

> **The requirement.** Sam has read the theme-presets proposal, likes it, and wants it built — in the background.

**In Claude**

```
you:    apply theme-presets on a jj worker in the background
claude: Pre-flight check on the change's artifacts… ✓ healthy.
        Dispatched a background worker to implement the tasks. Your session is
        free — keep going. (later)
        ✓ All tasks done. Verified the implementation against the spec — green —
        so I auto-archived the change. Opened PR #8.
```

A word on *how you phrase it*. A bare "apply theme-presets" is ambiguous: the in-session OpenSpec apply skill (`opsx:apply` / `openspec-apply-change`) would likely grab it and run a **raw, foreground apply** — implementing the tasks directly in your session, with **no pre-flight healthcheck and no verify/archive gate**. To get the plugin's background apply instead, steer it explicitly: say "apply … **on a jj worker**" or "**in the background**", which routes to `/jj-openspec apply`. That's the binding named in the Skill box below.

> **🔧 Skill:** **`/jj-openspec apply`** (`jj-concurrent-openspec`) — implements a proposed change on a worker. It runs a **healthcheck** first (are the spec artifacts valid?) and a **verify gate** at the end that **auto-archives** the change when the implementation matches the spec.
> **💡 Tips:**
> - "Archiving" just means the proposal has been delivered — its spec is folded into the project's permanent spec library, and the change folder is filed away.
> - The verify gate means a change can't quietly drift from its own spec: green to archive, or it stays open with a reason.
> - **It runs in the background, so you keep control.** As soon as the worker is dispatched, control returns to your session — you can queue up other work while the implementation runs. Contrast that with a plain OpenSpec apply: it would run in the **foreground** (you'd wait), with **no pre-flight healthcheck** and **no automatic verify/archive gate** at the end.

**Under the hood**

```bash
openspec validate theme-presets --strict     # healthcheck: artifacts well-formed?
jj workspace add -r main ../wt-theme-presets  # worker workspace
#   …worker implements tasks.md, ticking each…
openspec validate --all --strict             # verify gate
openspec archive theme-presets -y            # auto-archive on green
gh pr create --title "Implement theme presets"
```

## 11. Split a big change across workers

> **The requirement.** A bigger change — "accessibility pass" — has clearly separate chunks in its task list (keyboard nav, colour contrast, ARIA labels). Sam wants them done in parallel.

**In Claude**

```
you:    apply the accessibility change — fan it out across its task groups
claude: 3 separable task groups → 3 workers, one each:
          • keyboard-nav   • colour-contrast   • aria-labels
        (later) All 3 reported. Stitched them into one branch feat/a11y, opened
        PR #11. (They touched different files, so no conflicts.)
```

> **🔧 Skill:** **`/jj-openspec apply` with fan-out** (`jj-concurrent-openspec`, `jj-openspec-fanout`) — one change, several workers, one per task group, reconciled into a single branch.
> **💡 Tips:**
> - Fan-out shines when the task groups touch **different files** — then the workers never collide and the reconcile is clean.
> - You still get one PR at the end; the parallelism is invisible to the reviewer.
> - **Control returns to you while the workers run.** Fanning out is still a background dispatch — once the workers are launched your session is free, and you can keep working or queue more while all three run in parallel.

**Under the hood**

```bash
# one workspace + worker per task group, all off main:
jj workspace add -r main ../wt-a11y-keyboard
jj workspace add -r main ../wt-a11y-contrast
jj workspace add -r main ../wt-a11y-aria
#   …3 workers run concurrently…
# orchestrator squashes the three results into one bookmark, then:
jj git push --bookmark feat/a11y && gh pr create --title "Accessibility pass"
```

## 12. Several small specs at once

> **The requirement.** Sam has three tiny, already-proposed changes (favicon, meta tags, a 404 page). Independent, small, all spec'd. Do them together.

**In Claude**

```
you:    apply favicon, meta-tags, and not-found as a pipeline
claude: Running a multi-change pipeline — one worker per change, concurrently:
          favicon → PR #13   meta-tags → PR #14   not-found → PR #15
        All three landed as independent PRs. Done.
```

> **🔧 Skill:** **the multi-change pipeline** (`jj-concurrent-openspec`, `jj-openspec-pipeline`) — `apply` over a *set* of changes at once, each its own worker, integrated as independent landings (or a stack if they depend on each other).
> **💡 Tips:**
> - Fan-out ([§11](#11-split-a-big-change-across-workers)) splits **one** change; the pipeline runs **many** changes. Same parallel engine, different unit of work.
> - Independent changes → independent PRs. Dependent ones → a stack (see [§14](#14-a-change-thats-naturally-two-prs)).
> - **Control returns to you while the pipeline runs.** Like every background dispatch, once the per-change workers are launched your session is free — you keep control and can carry on working while all three changes are built concurrently.

**Under the hood**

```bash
# conceptually: for each change, one apply-shape worker in its own workspace,
# all concurrent, then each reconciled + landed on its own.
for c in favicon meta-tags not-found; do
  jj workspace add -r main ../wt-$c    # + a worker running `openspec apply $c`
done
```

## 13. Idea to merged, in one command

> **The requirement.** Sam has a half-formed idea ("a 'copy link' button on each row") and wants to go from idea → written proposal → built code with a single human checkpoint in the middle.

There's a subtlety here that Sam has learned the hard way. If you just say "add a copy-link button", Claude might simply *do* the change — edit the files there and then — instead of routing it through the plugin's draft-gate-apply flow. The word that makes the difference is **"relay"**: it's the trigger the `jj-openspec` binding recognises, and it's how you tell Claude *"don't just make this — run it through the relay so I get a go/no-go gate."* So Sam deliberately phrases the prompt to invoke the plugin.

**In Claude**

```
you:    /jj-openspec relay: add a "copy link" button to each link row
claude: Drafted the proposal for "copy-link-button". Here's the gist:
          • a 📋 button per row, copies the URL, shows a "copied!" toast
        Go / no-go?
you:    go
claude: Applying… ✓ built, verified, archived. Opened PR #16.
```

> **🔧 Skill:** **`/jj-openspec relay`** (`jj-concurrent-openspec`) — draft a proposal, **stop at a human go/no-go gate**, then on "go" apply it — propose and apply chained behind one command with one decision point.
> **💡 Tips:**
> - This is the sweet spot between "just do it" ([§1](#1-ship-a-dark-mode-button)) and "let me review a formal proposal PR first" ([§9](#9-a-change-worth-writing-down-first)): you still approve the plan, but in the flow of chat.
> - Say "no-go" and nothing is built — you've spent only the cost of a draft.

**Under the hood**

```bash
openspec new change copy-link-button        # draft
#   → HALT, show summary, await go/no-go
openspec validate copy-link-button --strict # on "go": healthcheck
#   → apply worker → verify → archive → PR     (the §10 flow)
```

## 14. A change that's naturally two PRs

> **The requirement.** "User accounts lite" — first a tiny storage helper, then a UI that uses it. The UI *depends on* the helper. Reviewers should see two clean, separate diffs, not one tangled one.

**In Claude**

```
you:    submit the storage-helper and the accounts-ui as a stack
claude: Two stacked PRs:
          PR #18  storage-helper   (base: main)
          PR #19  accounts-ui      (base: storage-helper)
        Added a navigation comment to each so reviewers can move between them.
```

> **🔧 Skill:** **`/jj-stacked-pr`** (`jj-concurrent`) — opens one PR per change in a dependent stack, each based on the one below it, so each diff shows only its own work.
> **💡 Tips:**
> - Stacking lets you keep shipping the *next* thing without waiting for the *previous* PR to merge.
> - When the bottom PR merges, the tool re-points the next one at `main` automatically (you'll see `/jj-land` handle the whole stack in [§20](#20-land-a-stack--and-watch-ci-stop-a-bad-one)).

**Under the hood**

```bash
jj git push --bookmark storage-helper --bookmark accounts-ui
gh pr create --base main          --head storage-helper --title "Storage helper"
gh pr create --base storage-helper --head accounts-ui   --title "Accounts UI"
# + a single cross-reference comment maintained on each PR
```

---

# Part 3 — issues, Linear, and finally CI

Linkstack has users now. Bugs get reported, planned work gets tracked, and it's time to stop relying on "it looked fine on my machine".

Since planned work is about to start flowing through **Linear**, Sam has done the one-time setup the Linear sections below depend on: installed the **Linear MCP server** and connected and authorised it against their Linear account (so Claude can create issues, move them between states, and comment on them). With that in place, the `jj-concurrent-linear` skills have a board to talk to.

## 15. A drive-by bug report on GitHub

> **The requirement.** A stranger opens a **GitHub issue**: "the dark-mode button is invisible on Safari." It's a small, obvious fix — no spec needed.

**In Claude**

```
you:    fix GitHub issue #21 (dark-mode button invisible on Safari)
claude: Read issue #21. It's a missing vendor prefix in style.css. Delegated a
        quick worker, fixed it, opened PR #22 — and linked it to the issue so
        the issue closes when it merges. No OpenSpec; it's a one-line fix.
```

> **🔧 Skill:** **`/jj-delegate`** + **`/jj-pr`** (`jj-concurrent`) — the same everyday tools from Part 1, now driven by a GitHub issue. **No OpenSpec** here: a one-line bug fix doesn't earn a proposal.
> **💡 Tips:**
> - This is the **GitHub side** of our rule: ad-hoc, externally-reported, small. Reach for OpenSpec when there's a *decision*, not for every typo.
> - Linking the PR to the issue (`Fixes #21`) lets GitHub auto-close it on merge.

**Under the hood**

```bash
gh issue view 21 --json title,body          # read the report
#   …worker fixes style.css…
gh pr create --title "Fix dark-mode button on Safari" \
   --body "Fixes #21"                        # link → auto-close on merge
```

## 16. Planned work, tracked in Linear

> **The requirement.** Sam plans a real feature — "shareable profile cards" — and wants it tracked in **Linear**, with sub-tasks, and handed to background agents, with progress flowing back to the board automatically.

**In Claude**

```
you:    build "shareable profile cards" — track it in Linear and fan it out
claude: Created a Linear umbrella issue PRO-40 "shareable profile cards" with
        3 sub-issues (card layout / share button / og-image), each labelled
        ready-for-agent. Dispatched a worker per sub-issue.
        (later) Reconciled: PRO-41 ✓ done, PRO-42 ✓ done, PRO-43 ⚠ needs a human
        eye (visual). Posted a summary on PRO-40 (what changed / why / tests /
        PR link) and raised a human-gate sub-issue for the visual check.
```

> **🔧 Skill:** **`/jj-linear`** (`jj-concurrent-linear`) — at dispatch it auto-creates a Linear umbrella + one sub-issue per worker; at reconcile it moves each sub-issue to done (or comments a blocker), posts a four-section summary on the umbrella, and flags anything needing a human.
> **💡 Tips:**
> - This is the **Linear side** of our rule: *planned* work, broken into tracked pieces, handed to robots — the board becomes a live status view.
> - The "human-gate" sub-issue is how the agents say *"I did the mechanical part, but you should eyeball this."*

**Under the hood**

```text
# at dispatch (Linear MCP):
create_issue("shareable profile cards")              → umbrella PRO-40
create_issue(sub, parent=PRO-40, label=ready-for-agent) × 3
#   …workers run, each tied to its sub-issue in the plan file…
# at reconcile (Linear MCP):
update_issue(PRO-41, state=Done) ; comment(PRO-43, "needs visual check")
comment(PRO-40, "<what changed / root cause / tests / PR link>")
```

## 17. Turn one ready Linear ticket into a worker

> **The requirement.** A single Linear ticket, PRO-44 ("add a print stylesheet"), is triaged and marked `ready-for-agent`. Sam just wants it *done*.

**In Claude**

```
you:    put a worker on PRO-44
claude: Resolved PRO-44 from Linear, derived bookmark pro-44, dispatched a worker
        with the ticket body as its brief. It'll link its PR back to PRO-44 when
        it reports.
```

> **🔧 Skill:** **`/jj-from-linear`** (`jj-concurrent-linear`) — one command from a triaged Linear issue to a dispatched worker, with the branch name and the back-link derived from the ticket itself.
> **💡 Tips:**
> - The worker never talks to Linear; the link back to the ticket rides on the branch name the plugin derived. Clean separation.
> - It refuses politely if the ticket doesn't exist or Linear is unreachable — no half-started work.

**Under the hood**

```text
get_issue("PRO-44")                          # Linear MCP: resolve the ticket
# derive bookmark pro-44, record {issueId, url} in the plan file, then:
jj workspace add -r main ../wt-pro-44         # + a worker briefed from the body
```

## 18. Time to add CI

> **The requirement.** Linkstack matters now. Sam wants a safety net: every PR should be checked automatically before it can merge. **Up to this point there has been no CI** — every land in Parts 1–2 merged on "looks mergeable" alone.

**In Claude**

```
you:    add CI — lint the JS and run my one little test, and make them required
claude: Added .github/workflows/ci.yml with two checks (lint + test), opened
        PR #45, and after it merged I set them as *required* on main.
        From now on, nothing merges unless both are green.
```

> **🔧 Skill:** plain **`/jj-delegate`** + **`/jj-pr`** to add the workflow file — CI itself is just GitHub Actions. The interesting part is what it *unlocks* for the next two sections.
> **💡 Tips:**
> - "Required checks" is a GitHub branch-protection setting: a PR is not mergeable until the listed checks pass. This is the signal `/jj-land` and `/jj-keep-current` start using.
> - Notice the ordering of this whole document: everything before here ran *without* CI on purpose. Real projects often live that way for a long time.

**Under the hood**

```bash
# the workflow file (lint + test jobs), then once merged:
gh api -X PUT repos/sam/linkstack/branches/main/protection \
   -f 'required_status_checks[contexts][]=lint' \
   -f 'required_status_checks[contexts][]=test'      # make them required
```

## 19. Keep a branch current and green

> **The requirement.** Sam's "profile cards" branch has been open a while and `main` moved on. Before landing, is it up to date — and does it still pass the new CI?

**In Claude**

```
you:    is the profile-cards branch current and safe to land?
claude: main moved since you branched. Rebased your branch onto the new main,
        re-pushed, and waited for CI… ✓ green. Verdict: landable.
```

> **🔧 Skill:** **`/jj-keep-current`** (`jj-concurrent`) — fetches the latest `main`, rebases your branch onto it if it moved, re-pushes, then checks the required CI and gives a one-word verdict: landable, or hold (with the reason).
> **💡 Tips:**
> - This only became meaningful **once CI existed** ([§18](#18-time-to-add-ci)) — there was no "green" to gate on before. That's why it lives here, not in Part 1.
> - jj rebases never "halt with conflicts" the scary git way; if there's a genuine clash it's recorded as a first-class thing to resolve, calmly.

**Under the hood**

```bash
jj git fetch                              # did main move?
jj rebase -d main                         # if so, move the branch onto it
jj git push --bookmark profile-cards      # rebuild the PR against new main
gh pr checks profile-cards --required     # green? → "landable"
```

## 20. Land a stack — and watch CI stop a bad one

> **The requirement.** Sam has a two-PR stack ready. Land it bottom-up — but **if a PR fails CI, stop**, don't merge anything above it.

**In Claude**

```
you:    land the stack
claude: Bottom PR #18: waiting for required checks… ✓ green → merged, re-pointed
        #19 onto main. PR #19: waiting for checks… ✗ the test failed.
        Stopping here. #18 is merged; #19 stays open with its red check. Nothing
        broken was merged. Re-run "land the stack" after you fix #19 and I'll
        resume from there.
```

> **🔧 Skill:** **`/jj-land`** (`jj-concurrent`) — now CI-aware: it waits for each PR's required checks, merges bottom-up, re-points the next PR at `main`, and **aborts the moment a check is red**, leaving the rest of the stack untouched. Re-running resumes from the first still-open PR.
> **💡 Tips:**
> - Compare with [§1](#1-ship-a-dark-mode-button), where `/jj-land` merged instantly — same command, but now it *waits for green* because the checks are required. The tool adapts to the project's maturity.
> - A red check is a **clean stop**, not a mess: merged PRs stay merged, the bad one stays open, and you just fix and re-run.

**Under the hood**

```bash
gh pr checks 18 --required       # wait for green
gh pr merge 18 --merge           # merge bottom
gh pr edit 19 --base main        # re-point the next one at main
gh pr checks 19 --required       # ✗ red → ABORT (never use --admin to force)
#   → #19 left open; re-running resumes here
```

---

# Appendix — when you grow

Everything above is the everyday loop. These four features only matter once you scale up — a teammate, lots of parallel work, secrets, or a whole backlog. Skip this section until you need it.

## A1. Two people (or two windows) in one repo

> **The requirement.** Sam's friend joins and also runs Claude on linkstack. Two orchestrators, same repo. Their background workers must not clobber each other.

**In Claude**

```
you:    show the fleet
claude:  SESSION   WORKSPACE      CHANGE          STATUS
         sam       ../wt-links    links section   running
         alex      ../wt-footer   footer          running
```

> **🔧 Skill:** **multi-orchestrator namespacing** + **`/jj-fleet` across sessions** (`jj-concurrent`) — each session gets its own private plan file and name prefixes, and `/jj-fleet` unions them into one view.
> **💡 Tip:** You don't configure anything — it just doesn't collide. Each session's workers and branches are tagged so two people never fight over a name.

**Under the hood**

```text
each session writes .jj-agent-plan.<session-id>.json (not one shared file);
workspace + branch names are prefixed per orchestrator;
/jj-fleet reads every plan file and joins them onto the live workspaces.
```

## A2. Hard walls between parallel workers

> **The requirement.** Two workers must edit the *same area* at once and Sam wants a guarantee they can't touch each other's files.

**In Claude**

```
you:    delegate two workers in the cards area, but wall them off: worker A only
        touches src/cards/layout/**, worker B only touches src/cards/share/**.
        Neither should even be able to see the other's files.
claude: Provisioning two sparse workspaces with hard partitions:
          ../wt-cards-layout  → only src/cards/layout/** checked out  (feat/cards-layout)
          ../wt-cards-share   → only src/cards/share/**  checked out  (feat/cards-share)
        Each worker's tree literally lacks the other's files. Dispatched both.
```

The skill driving this is **`/jj-delegate`** — sparse partitions aren't a separate slash command, they're its **`--sparse-patterns`** provisioning option. The language that triggers it is exactly the kind Sam used: ask to delegate two (or more) workers to the *same area* but **strictly confined** to their own, non-overlapping file globs ("wall them off", "each only touches X", "can't see each other's files"). That phrasing tells `/jj-delegate` to hard-partition each workspace rather than rely on the softer "different files" convention of [§11](#11-split-a-big-change-across-workers).
> **💡 Tip:** Most of the time fan-out's "different files" convention ([§11](#11-split-a-big-change-across-workers)) is enough. Reach for sparse partitions only when you need an enforced wall, not a polite agreement.

**Under the hood**

```bash
# On the pinned jj (0.42.x), --sparse-patterns takes a *strategy* enum
# (copy/full/empty), NOT a glob list — so create the workspace empty, then
# narrow it to exactly the lane's globs with a non-interactive `jj sparse set`:
jj workspace add -r main --sparse-patterns empty ../wt-cards-layout
( cd ../wt-cards-layout && jj sparse set --clear --add 'src/cards/layout' )

jj workspace add -r main --sparse-patterns empty ../wt-cards-share
( cd ../wt-cards-share  && jj sparse set --clear --add 'src/cards/share' )
# after this, worker A's tree only has src/cards/layout and worker B's only
# src/cards/share — each literally cannot see or edit the other's files.
```

## A3. Giving workers the secrets they need

> **The requirement.** Linkstack now needs an API key in a `.env` file (gitignored, so it's not in the repo). Background workers run in fresh copies that don't have it. They need it to run the app.

> **🔧 Skill:** **worktree-include provisioning** (`jj-concurrent`, used by `/jj-delegate` and `/jj-preview`) — declare once, in a file in the repo, which gitignored files should be seeded into every new workspace; on provision the orchestrator reads that declaration and copies the matching files in.
> **💡 Tip:** This is what makes `/jj-preview` and background workers able to actually *run* an app that needs local secrets — without ever committing them.

**How it's declared (the real mechanism).** It's a *convention* the orchestrator honours, resolved from the **first source present** (no merging across sources):

1. a repository-root **`.worktreeinclude`** file — gitignore-style, one path glob per line; else
2. a **`worktree` copy-list key in `.claude/settings.json`** (e.g. `worktree.copyFiles`) — the same copy-list Claude Code uses when it commissions a git worktree.

Each entry is treated as a gitignore-style glob resolved relative to the repo root. When neither source exists, the plugin **falls back** to copying the specific gitignored files the workload needs explicitly — the absence of a declaration never blocks provisioning. So yes: if a `.worktreeinclude` file is present it is honoured; otherwise the `.claude/settings.json` copy-list is; otherwise it's an ad-hoc copy.

**Under the hood**

```text
# Source 1 — a repo-root .worktreeinclude (gitignore-style, one glob per line):
.env
.env.local
config/*.local.json

# (or Source 2 — .claude/settings.json: { "worktree": { "copyFiles": [".env", …] } })

# On every  jj workspace add  the orchestrator reads the first source present and
# copies each matched file into the new workspace, PRESERVING its repo-relative
# path (so config/local.env lands at <ws-dir>/config/local.env). Paths that
# escape the repo root, and .jj/.git internals, are never copied; a declared
# glob that matches nothing is reported, not silently skipped.
```

## A4. Drain a whole Linear board

> **The requirement.** Sam has a Linear board with a dozen `ready-for-agent` tickets and wants them all worked through, a few at a time, hands-off.

**In Claude**

```
you:    burn down the board, 3 at a time
claude: 12 ready tickets. Running 3 workers at a time; as each lands I pull the
        next. (streaming) done 3/12… 7/12… 12/12. Each ticket updated as its
        worker finished.
```

> **🔧 Skill:** **`/jj-burndown`** (`jj-concurrent-linear`) — turns a Linear board into a work queue: it drains the `ready-for-agent` tickets as a bounded, rolling stream of background workers, updating each ticket as it lands.
> **💡 Tip:** It's `/jj-from-linear` ([§17](#17-turn-one-ready-linear-ticket-into-a-worker)) on repeat with a concurrency cap — one command to clear a backlog instead of dispatching tickets one by one.

**Under the hood**

```text
list_issues(label=ready-for-agent)           # the queue
# keep ≤3 in flight: dispatch /jj-from-linear per ticket; as one lands, pull next
# update each ticket as its worker reports; stop when the board is drained
```

---

# Cheat-sheet

Every skill in one place — what you say, what it wraps.

| You want to… | Skill | Under the hood (roughly) |
|---|---|---|
| Save constantly, block dangerous commands | *snapshot + guard hooks* | `jj util snapshot`; pre-command checks |
| Open / update a PR | **`/jj-pr`** | `jj git push` + `gh pr create` |
| Merge a PR or a stack, tidily | **`/jj-land`** | `gh pr merge` + fetch + cleanup |
| File review fixes into the right commits | **`/jj-absorb`** | `jj absorb` |
| Apply a PR's review comments in one go | **`/jj-pr-fixup`** | read comments → fix → `jj absorb` → push |
| Save-point before something risky | **`/jj-checkpoint`** | remember a `jj op` id |
| Undo the whole repo to a save-point | **`/jj-rewind`** | `jj op restore` |
| See a change running, disposably | **`/jj-preview`** | `jj workspace add` + run + tear down |
| Run a job in the background | **`/jj-delegate`** | `jj workspace add` + a `jj-workspace-worker` |
| See what the workers are doing | **`/jj-fleet`** | read-only `jj workspace list` + plan |
| Write a spec before coding | **`/jj-openspec propose`** | `openspec new` (authoring) |
| Build a proposed change | **`/jj-openspec apply`** | healthcheck → worker → verify → archive |
| Split one change across workers | *apply, fan-out* | one worker per task group |
| Run many changes at once | *multi-change pipeline* | one worker per change |
| Quick spec'd change in one go | **`/jj-openspec new` + `ff`** | scaffold + fast-forward apply |
| Idea → review → build, one command | **`/jj-openspec relay`** | draft → go/no-go → apply |
| Submit a dependent stack | **`/jj-stacked-pr`** | a PR per change, each based on the last |
| Keep a branch current + green | **`/jj-keep-current`** | `jj git fetch` + `jj rebase` + CI check |
| Issues → agents (one ticket) | **`/jj-from-linear`** | Linear ticket → worker |
| Issues → agents (umbrella + sync) | **`/jj-linear`** | create sub-issues, sync reports back |
| Drain a whole board | **`/jj-burndown`** | bounded stream of `/jj-from-linear` |

---

# Coverage map

Proof that this walkthrough touches everything. Each plugin capability and each OpenSpec mode maps to at least one section above.

| Capability / mode | Section(s) |
|---|---|
| `jj-safety-hooks` (snapshot + guard) | [Setup](#setup-turning-a-folder-into-a-jj-on-github-project), [§1](#1-ship-a-dark-mode-button), [§6](#6-the-guardrail-youll-be-glad-about) |
| `jj-github-pr` (`/jj-pr`) | [§1](#1-ship-a-dark-mode-button), [§3](#3-address-pr-comments-in-one-shot), [§15](#15-a-drive-by-bug-report-on-github) |
| `jj-land` (`/jj-land`) | [§1](#1-ship-a-dark-mode-button) (no-CI), [§20](#20-land-a-stack--and-watch-ci-stop-a-bad-one) (CI + red-abort) |
| `jj-absorb-fixup` (`/jj-absorb`) | [§2](#2-tidy-up-scattered-review-fixes), [§3](#3-address-pr-comments-in-one-shot) |
| `jj-pr-fixup` (`/jj-pr-fixup`) | [§3](#3-address-pr-comments-in-one-shot) |
| `jj-op-checkpoint` (`/jj-checkpoint`, `/jj-rewind`) | [§4](#4-a-risky-refactor-with-an-undo-button) |
| `jj-preview` (`/jj-preview`) | [§5](#5-see-it-running-before-you-merge) |
| `jj-delegate` + `jj-workspace-worker` | [§7](#7-hand-a-job-to-a-background-worker), [§11](#11-split-a-big-change-across-workers), [§15](#15-a-drive-by-bug-report-on-github) |
| `jj-fleet-status` (`/jj-fleet`) | [§8](#8-what-are-the-robots-doing), [§A1](#a1-two-people-or-two-windows-in-one-repo) |
| `jj-openspec-binding` — **propose** | [§9](#9-a-change-worth-writing-down-first) |
| `jj-openspec-binding` — **apply** + `jj-openspec-healthcheck` | [§10](#10-build-the-proposed-change) |
| `jj-openspec-fanout` (fan-out) | [§11](#11-split-a-big-change-across-workers) |
| `jj-openspec-pipeline` (multi-change) | [§12](#12-several-small-specs-at-once) |
| `jj-openspec-binding` — **new + ff** | [§13](#13-idea-to-merged-in-one-command) (and inline in [§12](#12-several-small-specs-at-once)/[§10](#10-build-the-proposed-change) flow) |
| `jj-openspec-binding` — **relay** | [§13](#13-idea-to-merged-in-one-command) |
| `jj-stacked-pr` (`/jj-stacked-pr`) | [§14](#14-a-change-thats-naturally-two-prs), [§20](#20-land-a-stack--and-watch-ci-stop-a-bad-one) |
| `jj-linear-sync` / `jj-linear-dispatch` / `jj-linear-reconcile` (`/jj-linear`) | [§16](#16-planned-work-tracked-in-linear) |
| `jj-from-linear` (`/jj-from-linear`) | [§17](#17-turn-one-ready-linear-ticket-into-a-worker) |
| `jj-keep-current` (`/jj-keep-current`) | [§19](#19-keep-a-branch-current-and-green) |
| `jj-linear-burndown` (`/jj-burndown`) | [§A4](#a4-drain-a-whole-linear-board) |
| multi-orchestrator namespacing | [§A1](#a1-two-people-or-two-windows-in-one-repo) |
| sparse-workspace partitions | [§A2](#a2-hard-walls-between-parallel-workers) |
| worktree-include provisioning | [§A3](#a3-giving-workers-the-secrets-they-need) |
| **With** OpenSpec | [§9](#9-a-change-worth-writing-down-first), [§10](#10-build-the-proposed-change), [§11](#11-split-a-big-change-across-workers), [§12](#12-several-small-specs-at-once), [§13](#13-idea-to-merged-in-one-command) |
| **Without** OpenSpec | [§1](#1-ship-a-dark-mode-button), [§2](#2-tidy-up-scattered-review-fixes), [§3](#3-address-pr-comments-in-one-shot), [§4](#4-a-risky-refactor-with-an-undo-button), [§5](#5-see-it-running-before-you-merge), [§15](#15-a-drive-by-bug-report-on-github) |
| **Foreground** Claude | [§1](#1-ship-a-dark-mode-button)–[§6](#6-the-guardrail-youll-be-glad-about) |
| **Background** workers | [§7](#7-hand-a-job-to-a-background-worker) onward |
| **GitHub** issue | [§15](#15-a-drive-by-bug-report-on-github) |
| **Linear** issues | [§16](#16-planned-work-tracked-in-linear), [§17](#17-turn-one-ready-linear-ticket-into-a-worker), [§A4](#a4-drain-a-whole-linear-board) |
| **No CI** (large early span) | [Setup](#setup-turning-a-folder-into-a-jj-on-github-project)–[§17](#17-turn-one-ready-linear-ticket-into-a-worker) |
| **CI added late** → CI-gated features | [§18](#18-time-to-add-ci), then [§19](#19-keep-a-branch-current-and-green), [§20](#20-land-a-stack--and-watch-ci-stop-a-bad-one) |

> **A note on honesty:** this is an *illustrative* case study. "Sam", "linkstack", the PR numbers, and the Linear tickets are invented to make the features concrete. No real repository or Linear board was created. The commands in the "Under the hood" boxes are real and correct — they're what the plugin would run — but the transcripts are written, not captured.




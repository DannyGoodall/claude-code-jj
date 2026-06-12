#!/usr/bin/env python3
"""Content-preservation manifest for plugin SKILL.md restructures.

snapshot: extract every fenced code block and table from each plugin SKILL.md,
          whitespace-normalized and content-hash-keyed, into the baseline JSON.
check:    every baseline item must still exist somewhere in the repo (any .md,
          .sh, or .py file under plugins/, docs/, scripts/, or repo-root .md) —
          same file, a references/ file, DESIGN.md, or a scripts/ file all count.
          Deliberate deletions need --allow-drop <hash> (repeatable); anything
          else that vanished fails the check.

Matching is by normalized content, not path, so moves don't false-flag.
Stdlib only. Exit non-zero on failure.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import sys

SKILL_GLOB = "plugins/*/skills/*/SKILL.md"
BASELINE = "scripts/skill-content-baseline.json"
SEARCH_GLOBS = [
    "plugins/**/*.md", "plugins/**/*.sh", "plugins/**/*.py",
    "docs/**/*.md", "scripts/**/*", "*.md",
]


def normalize(text):
    lines = [l.rstrip() for l in text.strip().splitlines()]
    return "\n".join(l.strip() for l in lines if l.strip())


def extract_items(path):
    """Yield (kind, normalized_content, first_line) for fences and tables."""
    text = open(path, encoding="utf-8").read()
    items = []
    for m in re.finditer(r"^([ \t]*)(```|~~~)[^\n]*\n(.*?)^\1\2[ \t]*$", text, re.S | re.M):
        body = m.group(3)
        if normalize(body):
            items.append(("fence", normalize(body)))
    # tables: runs of consecutive lines starting with '|'
    run = []
    for line in text.splitlines() + [""]:
        if line.lstrip().startswith("|"):
            run.append(line)
        else:
            if len(run) >= 2:
                items.append(("table", normalize("\n".join(run))))
            run = []
    return items


def snapshot(root):
    out = {}
    for path in sorted(glob.glob(os.path.join(root, SKILL_GLOB))):
        for kind, content in extract_items(path):
            h = hashlib.sha256(content.encode()).hexdigest()[:16]
            entry = out.setdefault(h, {"kind": kind, "sources": [], "preview": content.splitlines()[0][:80],
                                       "content": content})
            rel = os.path.relpath(path, root)
            if rel not in entry["sources"]:
                entry["sources"].append(rel)
    with open(os.path.join(root, BASELINE), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print(f"snapshot: {len(out)} unique items from {len(glob.glob(os.path.join(root, SKILL_GLOB)))} SKILL.md files -> {BASELINE}")
    return 0


def corpus(root):
    seen, blobs = set(), []
    for g in SEARCH_GLOBS:
        for path in glob.glob(os.path.join(root, g), recursive=True):
            if not os.path.isfile(path) or path in seen:
                continue
            seen.add(path)
            try:
                blobs.append(normalize(open(path, encoding="utf-8").read()))
            except (UnicodeDecodeError, OSError):
                continue
    return "\n@@FILE@@\n".join(blobs)


def check(root, allow_drops):
    baseline = json.load(open(os.path.join(root, BASELINE), encoding="utf-8"))
    haystack = corpus(root)
    missing, dropped = [], []
    for h, entry in sorted(baseline.items()):
        if entry["content"] in haystack:
            continue
        if h in allow_drops:
            dropped.append((h, entry))
        else:
            missing.append((h, entry))
    for h, e in dropped:
        print(f"DROPPED (allowed) {h} [{e['kind']}] from {','.join(e['sources'])}: {e['preview']}")
    for h, e in missing:
        print(f"FAIL missing {h} [{e['kind']}] from {','.join(e['sources'])}: {e['preview']}")
    print(f"check: {len(baseline)} items, {len(missing)} missing, {len(dropped)} allowed drops")
    return 1 if missing else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["snapshot", "check"])
    ap.add_argument("--root", default=".")
    ap.add_argument("--allow-drop", action="append", default=[], metavar="HASH")
    args = ap.parse_args()
    if args.command == "snapshot":
        return snapshot(args.root)
    return check(args.root, set(args.allow_drop))


if __name__ == "__main__":
    sys.exit(main())

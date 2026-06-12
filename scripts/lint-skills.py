#!/usr/bin/env python3
"""Lint plugin SKILL.md files (skill-doc-budget capability).

Rules (each can be waived with --skip <rule>):
  desc-length   frontmatter description >1024 chars fails (>700 warns)
  frontmatter   required keys (name, description) must be present
  links         relative links and intra-file anchors must resolve
  boilerplate   known shared-contract prose markers at most once per file,
                counted OUTSIDE fenced code blocks (commands in fences are fine)

Exit non-zero on any failure. Stdlib only.
"""

import argparse
import glob
import os
import re
import sys

HARD_DESC_LIMIT = 1024
SOFT_DESC_LIMIT = 700

# Prose markers of the shared contract; each may appear at most once per file
# outside fenced code blocks (jj-delegate's canonical section is exempt).
BOILERPLATE_MARKERS = [
    "Substrate knowledge",
    "never invoked inside a worker",
    "--no-pager",
]
CANONICAL_HOME = os.path.join("jj-delegate", "SKILL.md")

SKILL_GLOB = "plugins/*/skills/*/SKILL.md"


def parse_frontmatter(text):
    """Return (dict of top-level keys -> raw value string, fm_text) or (None, None)."""
    m = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None, None
    fm = m.group(1)
    keys = {}
    current = None
    buf = []
    for line in fm.splitlines():
        km = re.match(r"^([A-Za-z_][\w-]*):(.*)$", line)
        if km:
            if current is not None:
                keys[current] = "\n".join(buf)
            current = km.group(1)
            buf = [km.group(2).strip()]
        else:
            buf.append(line)
    if current is not None:
        keys[current] = "\n".join(buf)
    return keys, fm


def description_text(raw):
    """Normalize a YAML scalar (plain, |, >, |-, >-) to its content text."""
    lines = raw.splitlines()
    if lines and re.match(r"^[|>][+-]?\s*$", lines[0].strip()):
        lines = lines[1:]
    body = [re.sub(r"^  ", "", l, count=1) for l in lines]
    return "\n".join(body).strip()


def strip_fences(text):
    """Remove fenced code blocks; return remaining prose lines."""
    out, in_fence = [], False
    for line in text.splitlines():
        if re.match(r"^\s*(```|~~~)", line):
            in_fence = not in_fence
            continue
        if not in_fence:
            out.append(line)
    return "\n".join(out)


def github_slug(heading):
    slug = heading.strip().lower()
    slug = re.sub(r"[`*_~]", "", slug)
    slug = re.sub(r"[^\w\s-]", "", slug, flags=re.UNICODE)
    slug = re.sub(r"\s+", "-", slug.strip())
    return slug


def headings_of(text):
    return [m.group(2) for m in re.finditer(r"^(#{1,6})\s+(.*)$", strip_fences(text), re.M)]


def check_file(path, skip, failures, warnings):
    text = open(path, encoding="utf-8").read()
    keys, _ = parse_frontmatter(text)

    if "frontmatter" not in skip:
        if keys is None:
            failures.append(f"{path}: no YAML frontmatter block")
            return
        for req in ("name", "description"):
            if req not in keys or not keys[req].strip():
                failures.append(f"{path}: missing required frontmatter key '{req}'")

    if keys and "description" in keys and "desc-length" not in skip:
        desc = description_text(keys["description"])
        n = len(desc)
        if n > HARD_DESC_LIMIT:
            failures.append(f"{path}: description {n} chars (> {HARD_DESC_LIMIT} hard limit)")
        elif n > SOFT_DESC_LIMIT:
            warnings.append(f"{path}: description {n} chars (> {SOFT_DESC_LIMIT} target)")

    if "links" not in skip:
        prose = strip_fences(text)
        slugs = {github_slug(h) for h in headings_of(text)}
        for m in re.finditer(r"\[[^\]]*\]\(([^)\s]+)\)", prose):
            target = m.group(1)
            if re.match(r"^[a-z]+://", target) or target.startswith("mailto:"):
                continue
            frag = None
            if "#" in target:
                target, frag = target.split("#", 1)
            if target:
                resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
                if not os.path.exists(resolved):
                    failures.append(f"{path}: dangling relative link '{m.group(0)}'")
                    continue
                if frag and resolved.endswith(".md"):
                    tslugs = {github_slug(h) for h in headings_of(open(resolved, encoding="utf-8").read())}
                    if frag.lower() not in tslugs:
                        failures.append(f"{path}: anchor '#{frag}' not found in {resolved}")
            elif frag and frag.lower() not in slugs:
                failures.append(f"{path}: intra-file anchor '#{frag}' not found")

    if "boilerplate" not in skip and not path.endswith(CANONICAL_HOME):
        prose = strip_fences(text)
        for marker in BOILERPLATE_MARKERS:
            count = prose.count(marker)
            if count > 1:
                failures.append(
                    f"{path}: boilerplate marker '{marker}' appears {count}x outside code fences (max 1)"
                )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--skip", action="append", default=[],
                    choices=["desc-length", "frontmatter", "links", "boilerplate"])
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.root, SKILL_GLOB)))
    if not files:
        print("lint-skills: no SKILL.md files found", file=sys.stderr)
        return 2

    failures, warnings = [], []
    for path in files:
        check_file(path, set(args.skip), failures, warnings)

    for w in warnings:
        print(f"WARN  {w}")
    for f in failures:
        print(f"FAIL  {f}")
    print(f"lint-skills: {len(files)} files, {len(failures)} failures, {len(warnings)} warnings")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

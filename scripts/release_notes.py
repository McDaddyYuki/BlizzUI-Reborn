#!/usr/bin/env python3
"""Prints the CHANGELOG.md section for one version (used as release notes).

usage: release_notes.py <version>
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
version = sys.argv[1].lstrip("v")
lines = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read().splitlines()
out, inside = [], False
for line in lines:
    if line.startswith("## "):
        if inside:
            break
        inside = re.match(r"##\s+" + re.escape(version) + r"\b", line) is not None
        continue
    if inside:
        out.append(line)
if not out:
    sys.exit("CHANGELOG.md has no '## %s' section" % version)
body = "\n".join(out).strip()
print(body)
print("\n---\nInstall: download **BlizzUIReborn-%s.zip** below and extract the `BlizzUIReborn` folder into `Interface\\AddOns\\`." % version)

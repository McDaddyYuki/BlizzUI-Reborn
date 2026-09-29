#!/usr/bin/env python3
"""Builds the installable release ZIP: dist/BlizzUIReborn-<version>.zip

The ZIP holds one folder, BlizzUIReborn/, ready to copy into
Interface/AddOns/: the .toc, the Lua files it lists, and the player docs.
The output is reproducible (sorted entries, fixed timestamps).

usage: package.py <version>      (e.g. 0.7.0; must match the .toc and Core.lua)
"""
import os, re, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "BlizzUIReborn"
DOCS = {"README.md": "README.md", "CHANGELOG.md": "CHANGELOG.md", "PROVENANCE.md": "PROVENANCE.md", "LICENSE": "LICENSE.txt"}
FIXED_TIME = (2026, 1, 1, 0, 0, 0)


def toc_files(toc_path):
    files = []
    for line in open(toc_path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def toc_version(toc_path):
    for line in open(toc_path, encoding="utf-8"):
        m = re.match(r"##\s*Version:\s*(\S+)", line)
        if m:
            return m.group(1)


def core_version():
    src = open(os.path.join(ROOT, ADDON, "Core.lua"), encoding="utf-8").read()
    m = re.search(r'A\.version\s*=\s*"([^"]+)"', src)
    return m and m.group(1)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    version = sys.argv[1].lstrip("v")
    toc = os.path.join(ROOT, ADDON, ADDON + ".toc")
    problems = []
    if toc_version(toc) != version:
        problems.append("the .toc says %s, not %s" % (toc_version(toc), version))
    if core_version() != version:
        problems.append("Core.lua says %s, not %s" % (core_version(), version))
    if problems:
        sys.exit("Version mismatch: " + "; ".join(problems))
    entries = [(ADDON + "/" + ADDON + ".toc", toc)]
    for f in toc_files(toc):
        path = os.path.join(ROOT, ADDON, f)
        if not os.path.isfile(path):
            sys.exit("Listed in the .toc but missing: " + f)
        entries.append((ADDON + "/" + f, path))
    for src, dst in DOCS.items():
        entries.append((ADDON + "/" + dst, os.path.join(ROOT, src)))
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", "%s-%s.zip" % (ADDON, version))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        folder = zipfile.ZipInfo(ADDON + "/", FIXED_TIME)
        folder.external_attr = 0o40755 << 16
        z.writestr(folder, b"")
        for name, path in sorted(entries):
            info = zipfile.ZipInfo(name, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            data = open(path, "rb").read().replace(b"\r\n", b"\n")
            z.writestr(info, data)
    print(out)


if __name__ == "__main__":
    main()

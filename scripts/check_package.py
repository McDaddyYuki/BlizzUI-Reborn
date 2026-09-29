#!/usr/bin/env python3
"""Checks a release ZIP before it is published.

- one top-level folder, BlizzUIReborn/, with the .toc inside
- every file the .toc lists is present; no Lua file the .toc doesn't list
- only this project's file types (.toc, .lua, .md, .txt); nothing large
- versions agree (.toc, Core.lua, and the expected version if given)
- no removed third-party dataset and no bundled boss-mod module code
- no game-installation or account files (WTF, SavedVariables, other addons)

usage: check_package.py <zip> [version]
"""
import re, sys, zipfile

ADDON = "BlizzUIReborn"
ALLOWED_EXT = (".toc", ".lua", ".md", ".txt")
MAX_BYTES = 1024 * 1024
# markers of the removed DBM-derived dataset and of boss-mod module code
FORBIDDEN_CODE = [
    r"\bTimelineData\b", r"DBM:NewMod\s*\(", r":SetCreatureID\s*\(", r":NewTimer\s*\(", r":NewAnnounce\s*\(",
    r"BigWigs:NewBoss\s*\(", r":RegisterEnableMob\s*\(", r"\bmod:RegisterCombat\s*\(",
]
FORBIDDEN_PATH = [r"(^|/)WTF/", r"SavedVariables", r"(^|/)Interface/AddOns/", r"\.(exe|dll|bat|cmd|ps1|sh|so|dylib)$",
                  r"(^|/)(DBM|BigWigs|Carbonite|Bagnon|Questie)[^/]*/"]


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    path = sys.argv[1]
    want = sys.argv[2].lstrip("v") if len(sys.argv) == 3 else None
    errors = []
    z = zipfile.ZipFile(path)
    names = [n for n in z.namelist() if not n.endswith("/")]
    tops = {n.split("/")[0] for n in z.namelist()}
    if tops != {ADDON}:
        errors.append("top-level entries must be exactly %s/ (found %s)" % (ADDON, sorted(tops)))
    toc_name = ADDON + "/" + ADDON + ".toc"
    if toc_name not in names:
        errors.append("missing " + toc_name)
        toc = ""
    else:
        toc = z.read(toc_name).decode("utf-8")
    listed = [ADDON + "/" + l.strip().replace("\\", "/") for l in toc.splitlines() if l.strip() and not l.startswith("#")]
    for f in listed:
        if f not in names:
            errors.append(".toc lists a missing file: " + f)
    for n in names:
        if not n.lower().endswith(ALLOWED_EXT):
            errors.append("unexpected file type: " + n)
        if n.endswith(".lua") and n not in listed:
            errors.append("Lua file not loaded by the .toc: " + n)
        if z.getinfo(n).file_size > MAX_BYTES:
            errors.append("file over 1 MB: " + n)
        for p in FORBIDDEN_PATH:
            if re.search(p, n, re.I):
                errors.append("file that doesn't belong in the release: " + n)
        if n.endswith((".lua", ".toc")):
            text = z.read(n).decode("utf-8", "replace")
            for p in FORBIDDEN_CODE:
                if re.search(p, text):
                    errors.append("%s contains %s (removed dataset or boss-mod module code)" % (n, p))
    m = re.search(r"##\s*Version:\s*(\S+)", toc)
    toc_ver = m and m.group(1)
    core = ADDON + "/Core.lua"
    core_ver = None
    if core in names:
        m = re.search(r'A\.version\s*=\s*"([^"]+)"', z.read(core).decode("utf-8"))
        core_ver = m and m.group(1)
    if toc_ver != core_ver:
        errors.append("version mismatch: .toc %s, Core.lua %s" % (toc_ver, core_ver))
    if want and toc_ver != want:
        errors.append("version mismatch: expected %s, .toc says %s" % (want, toc_ver))
    if not re.match(r"^" + re.escape(ADDON) + r"-\d+\.\d+\.\d+([-.][0-9A-Za-z.]+)?\.zip$", path.replace("\\", "/").split("/")[-1]):
        errors.append("file name should be %s-<version>.zip" % ADDON)
    if errors:
        print("Package check FAILED:")
        for e in errors:
            print("  - " + e)
        sys.exit(1)
    print("Package check passed: %s (%d files, version %s)" % (path, len(names), toc_ver))


if __name__ == "__main__":
    main()

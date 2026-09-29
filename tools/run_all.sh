#!/bin/bash
# Runs every scenario test plus the Lua 5.1 syntax/API lint.
# LUA selects the interpreter (default: lua5.1 if installed, else lua).
cd "$(dirname "$0")"
LUA="${LUA:-$(command -v lua5.1 || command -v lua || echo ./lua)}"
export BR_TEST_TMP="${BR_TEST_TMP:-$(pwd)/../.test-tmp}"
mkdir -p "$BR_TEST_TMP"
SV="$BR_TEST_TMP/sv.lua"
"$LUA" version.lua
fail=0
for t in ../tests/t*.lua; do
  case "$t" in
    *t07_reload_b*) "$LUA" run.lua "$t" "$SV" || fail=1 ;;
    *t14_migrate*) "$LUA" run.lua "$t" ../tests/sv_v1.lua || fail=1 ;;
    *t16_hidescrolling*) "$LUA" run.lua "$t" ../tests/sv_v1b.lua || fail=1 ;;
    *t31_knowledge_reload_b*) "$LUA" run.lua "$t" "$BR_TEST_TMP/sv_knowledge.lua" || fail=1 ;;
    *) "$LUA" run.lua "$t" || fail=1 ;;
  esac
done
python3 lint51.py ../BlizzUIReborn || fail=1
echo "OVERALL: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail

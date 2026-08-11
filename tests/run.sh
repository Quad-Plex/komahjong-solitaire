#!/usr/bin/env bash
# Official test suite runner for mahjong.koplugin.
#
# Usage:  tests/run.sh   (run from anywhere)
#
# Stages, in order:
#   1. luac -p  syntax check every plugin and test .lua file
#   2. luacheck lint the plugin (skipped with a note if luacheck is missing)
#   3. mahjonglogic.lua embedded self-tests (pure Lua, no mocks)
#   4. manifest-listed headless harnesses (real plugin + shared KOReader stubs)
#
# Any failing stage exits non-zero.

set -euo pipefail
cd "$(dirname "$0")"
export TESTS_DIR="$(pwd)"
shopt -s globstar nullglob

PLUGIN="../mahjong.koplugin"

echo "==> 1/4 syntax check (luac -p)"
for f in "$PLUGIN"/*.lua; do
    luac -p "$f"
done
for f in **/*.lua; do
    luac -p "$f"
done
echo "    OK"

echo "==> 2/4 lint (luacheck)"
if command -v luacheck >/dev/null 2>&1; then
    luacheck "$PLUGIN"/
else
    echo "    luacheck not installed — skipping"
fi

echo "==> 3/4 logic self-tests (mahjonglogic.lua, mahjonglayouts.lua, mahjongstats.lua)"
lua "$PLUGIN/mahjonglogic.lua"
lua "$PLUGIN/mahjonglayouts.lua"
lua "$PLUGIN/mahjongstats.lua"

echo "==> 4/4 manifest headless harnesses"
mapfile -t TEST_FILES < <(lua - "$TESTS_DIR/manifest.lua" <<'LUA'
local manifest = dofile(arg[1])
local seen = {}
for _, entry in ipairs(manifest) do
    assert(type(entry.path) == "string" and entry.path ~= "", "manifest entry has no path")
    assert(not seen[entry.path], "duplicate manifest entry: " .. entry.path)
    seen[entry.path] = true
    local file = io.open(entry.path, "r")
    assert(file, "manifest target does not exist: " .. entry.path)
    file:close()
    print(entry.path)
end
LUA
)
for t in "${TEST_FILES[@]}"; do
    if output="$(lua "$t" 2>&1)"; then
        echo "    OK  tests/$t"
    else
        echo "-- tests/$t FAILED"
        printf '%s\n' "$output"
        exit 1
    fi
done

echo
echo "ALL TEST SUITES PASSED"

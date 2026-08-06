#!/usr/bin/env bash
# Official test suite runner for mahjong.koplugin.
#
# Usage:  tests/run.sh   (run from anywhere)
#
# Stages, in order:
#   1. luac -p  syntax check every plugin .lua file
#   2. luacheck lint the plugin (skipped with a note if luacheck is missing)
#   3. mahjonglogic.lua embedded self-tests (pure Lua, no mocks)
#   4. tests/us*.lua headless harnesses (real plugin + shared KOReader stubs)
#
# Any failing stage exits non-zero.

set -euo pipefail
cd "$(dirname "$0")"
export TESTS_DIR="$(pwd)"

PLUGIN="../mahjong.koplugin"

echo "==> 1/4 syntax check (luac -p)"
for f in "$PLUGIN"/*.lua; do
    luac -p "$f"
done
echo "    OK"

echo "==> 2/4 lint (luacheck)"
if command -v luacheck >/dev/null 2>&1; then
    luacheck "$PLUGIN"/
else
    echo "    luacheck not installed — skipping"
fi

echo "==> 3/4 logic self-tests (mahjonglogic.lua, mahjongstats.lua)"
lua "$PLUGIN/mahjonglogic.lua"
lua "$PLUGIN/mahjongstats.lua"

echo "==> 4/4 headless harnesses"
for t in us01_shell.lua us03_icons.lua us06_board.lua us06_paint.lua board_updates.lua us07_gameplay.lua us08_features.lua us09_score.lua us10_persistence.lua us11_timer.lua hud_bar.lua us12_stats.lua us13_stats.lua us14_layouts.lua us15_spider.lua us16_bridge.lua us17_pause.lua us18_penalties.lua us19_autosolve.lua us21_picker.lua; do
    echo "-- tests/$t"
    lua "$t"
done

echo
echo "ALL TEST SUITES PASSED"

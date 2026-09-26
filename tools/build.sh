#!/usr/bin/env bash
# Builds the installer package and the demo place, then runs the offline checks.
#   tools/build.sh            (needs rojo, lune; selene optional)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rojo build installer.project.json -o build/SicilyUpgrade.rbxm
rojo build default.project.json -o build/SicilyDemo.rbxl
lune run tools/lune/package.luau build/SicilyUpgrade.rbxm build/SicilyDemo.rbxl
if command -v selene >/dev/null; then selene src; fi
tmp="$(mktemp -d)"
lune run tools/lune/test-characters.luau build/SicilyDemo.rbxl "$tmp/rigs"
lune run tools/lune/test-horses.luau build/SicilyDemo.rbxl "$tmp/horses"
lune run tools/lune/test-riding.luau build/SicilyDemo.rbxl
lune run tools/lune/test-weapons.luau build/SicilyDemo.rbxl "$tmp/weapons"
lune run tools/lune/test-gunplay.luau build/SicilyDemo.rbxl "$tmp/gunplay"
lune run tools/lune/test-combat.luau build/SicilyDemo.rbxl
lune run tools/lune/build-town.luau build/SicilyDemo.rbxl "$tmp/town"
echo "Built build/SicilyUpgrade.rbxm and build/SicilyDemo.rbxl"

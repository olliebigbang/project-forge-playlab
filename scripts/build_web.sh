#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="$($repo_root/scripts/find_godot.sh)"
mkdir -p "$repo_root/build/web"
"$godot_bin" --headless --path "$repo_root" --export-release "Web" "$repo_root/build/web/index.html"
test -f "$repo_root/build/web/index.html" || { echo "Web export failed; verify Godot 4.7.1 Web templates." >&2; exit 1; }


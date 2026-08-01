#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="$($repo_root/scripts/find_godot.sh)"
exec "$godot_bin" --path "$repo_root" "$@"


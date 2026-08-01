#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidates=(
  "$repo_root/.tools/Godot_v4.7.1-stable_win64_console.exe"
  "$repo_root/.tools/Godot_v4.7.1-stable_win64.exe"
)

if command -v godot4 >/dev/null 2>&1; then candidates+=("$(command -v godot4)"); fi
if command -v godot >/dev/null 2>&1; then candidates+=("$(command -v godot)"); fi
candidates+=("/c/Users/Eddie L/AppData/Local/Temp/godot4.exe")

for candidate in "${candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    version="$($candidate --version 2>/dev/null || true)"
    if [[ -z "$version" ]] && command -v powershell.exe >/dev/null 2>&1; then
      version="$(powershell.exe -NoProfile -Command "(Get-Item -LiteralPath '$candidate').VersionInfo.ProductVersion" | tr -d '\r')"
    fi
    if [[ "$version" == 4.7.1* ]]; then
      printf '%s\n' "$candidate"
      exit 0
    fi
  fi
done

echo "Godot 4.7.1 was not found." >&2
exit 1

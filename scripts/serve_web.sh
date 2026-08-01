#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test -f "$repo_root/build/web/index.html" || { echo "Run ./scripts/build_web.sh first." >&2; exit 1; }
echo "Serving Forge Playlab at http://localhost:8060"
python3 -m http.server 8060 --directory "$repo_root/build/web"


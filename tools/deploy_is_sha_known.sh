#!/usr/bin/env bash
set -euo pipefail
SHA="${1:-}"; [ -n "$SHA" ] || { echo "uso: $0 SHA"; exit 2; }
git cat-file -t "$SHA" >/dev/null 2>&1 && echo "✓ existe en este repo" || { echo "✗ NO existe en este repo"; exit 3; }

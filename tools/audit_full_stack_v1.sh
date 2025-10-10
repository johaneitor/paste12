#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-https://paste12-rmsk.onrender.com}}"
OUTDIR="${2:-${OUTDIR:-./p12-audit}}"
mkdir -p "$OUTDIR"

# 1. Static checks summary should be prepared separately

# 2. (Optional) Local tests would go here

# 3. Remote audit
"$(dirname "$0")/patchless_audit_remote_deep_full_v1.sh" "$BASE" "$OUTDIR"

# 4. Summary
{
  echo "PASS/FAIL SUMMARY"
  echo "- py_compile: SEE 01-static-checks.txt"
  echo "- POST /api/notes: $(jq -r '.ok? // .status // .error? // "unknown"' "$OUTDIR/api-notes-post.json" 2>/dev/null || echo unknown)"
} > "$OUTDIR/SUMMARY.txt" || true

echo "OK"
#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/sdcard/Download}"
pkg="$(ls -1dt "$ROOT"/p12-prod-* 2>/dev/null | head -1)"
[[ -n "$pkg" && -d "$pkg" ]] || { echo "ERROR: no encontré paquete p12-prod-* en $ROOT"; exit 2; }

manifest="$pkg/manifest.tsv"
tmp="$(mktemp)"
cleanup(){ rm -f "$tmp"; }
trap cleanup EXIT

# sha256 portátil (Termux tiene sha256sum; fallback a Python)
sha256(){ 
  if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'
  else python - <<PY "$1"
import sys,hashlib
p=sys.argv[1]; print(hashlib.sha256(open(p,'rb').read()).hexdigest())
PY
  fi
}

printf "path\tsize_bytes\tsha256\n" > "$manifest"
while IFS= read -r -d '' f; do
  sz=$(stat -c '%s' "$f" 2>/dev/null || stat -f '%z' "$f")
  h="$(sha256 "$f")"
  rp="${f#$pkg/}"
  printf "%s\t%s\t%s\n" "$rp" "$sz" "$h" >> "$manifest"
done < <(find "$pkg" -type f -print0 | sort -z)

echo "OK: manifest → $manifest"

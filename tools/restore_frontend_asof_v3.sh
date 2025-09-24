#!/usr/bin/env bash
set -euo pipefail
ASOF="${1:-}"; [ -n "$ASOF" ] || { echo "uso: $0 'YYYY-MM-DD HH:MM'"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
paths=(backend/static/index.html frontend/index.html)

for p in "${paths[@]}"; do
  [ -f "$p" ] || { echo "✗ falta $p"; exit 1; }
done

# workspace temporal robusto (Termux-friendly)
WORK="$(mktemp -d 2>/dev/null || true)"
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
  WORK="${TMPDIR:-$HOME}/tmp.restore.$TS"
  mkdir -p "$WORK"
fi
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

git fetch -q origin main || true
echo "== buscando commits anteriores a: $ASOF =="

declare -A rev
for p in "${paths[@]}"; do
  cid="$(git rev-list -1 --before="$ASOF" origin/main -- "$p" 2>/dev/null || true)"
  [ -z "$cid" ] && cid="$(git rev-list -1 --before="$ASOF" HEAD -- "$p" 2>/dev/null || true)"
  [ -n "$cid" ] || { echo "✗ no hallé commit para $p"; exit 1; }
  rev["$p"]="$cid"
  echo "  $p  <-  $(printf '%.10s' "$cid")"
done

backup() { local f="$1"; cp -f "$f" "${f}.pre_restore.$TS.bak"; }

restore_one() {
  local p="$1"; local cid="${rev[$p]}"
  local tmp="$WORK/$(echo "$p" | tr '/:' '__')"
  git show "$cid:$p" > "$tmp" || { echo "✗ git show falló para $p"; exit 1; }
  local sz; sz="$(wc -c < "$tmp" | tr -d ' ')"
  if [ "$sz" -lt 200 ]; then
    echo "✗ tamaño sospechoso para $p ($sz bytes). Aborto."; exit 1
  fi
  backup "$p"
  cp -f "$tmp" "$p"
  echo "✓ restaurado $p ($sz bytes) desde $(printf '%.10s' "$cid")"
}

for p in "${paths[@]}"; do restore_one "$p"; done

ensure_marker() {
  local f="$1" tmp
  # p12-safe-shim
  if ! grep -qi 'name="p12-safe-shim"' "$f"; then
    tmp="$WORK/ins.$$"; awk 'BEGIN{d=0}{print}/<head[^>]*>/ && !d{print "<meta name=\"p12-safe-shim\" content=\"1\">"; d=1}' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "  + meta p12-safe-shim en $(basename "$f")"
  fi
  # p12-single
  if ! grep -qi 'name="p12-single"' "$f"; then
    tmp="$WORK/ins2.$$"; awk 'BEGIN{d=0}{print}/<head[^>]*>/ && !d{print "<meta name=\"p12-single\" content=\"1\">"; d=1}' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "  + meta p12-single en $(basename "$f")"
  fi
}

for p in "${paths[@]}"; do ensure_marker "$p"; done

echo "== tamaños finales =="
for f in "${paths[@]}"; do printf "%8s  %s\n" "$(wc -c < "$f" | tr -d ' ')" "$f"; done

git add -f "${paths[@]}"
git commit -m "revert(frontend): restore index as of $ASOF + meta shim/single (safe,idempotente)" || true
echo "Ahora: git push origin main"

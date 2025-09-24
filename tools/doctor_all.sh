#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

say(){ printf "%s\n" "$*"; }
hr(){ printf "%s\n" "---------------------------------------------"; }

# ---------- Deploy vs HEAD ----------
say "== DEPLOY VS HEAD =="
LOCAL="$(git rev-parse HEAD | head -c 40 2>/dev/null || true)"
REMOTE="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
say "Local:  ${LOCAL:-<n/a>}"
say "Remote: ${REMOTE:-<sin valor>}"
if [ -n "${LOCAL:-}" ] && [ -n "${REMOTE:-}" ] && [ "$LOCAL" = "$REMOTE" ]; then
  say "✓ producción = HEAD local"
else
  say "✗ producción != HEAD local (ojo con auto-deploy o caché de build)"
fi
hr

# ---------- Raíz / bridge / cache ----------
say "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):|server:|cf-cache-status:)/{print}'
hr
say "== INDEX PASTEL / =="
HTML="$(curl -fsS "$BASE/")"
echo "$HTML" | grep -qm1 -- '--teal:#8fd3d0' && say "✓ token pastel" || say "✗ token pastel ausente"
echo "$HTML" | grep -qi '<title> *Paste12 *</title>' && say "✓ <title>Paste12</title>" || say "✗ título Paste12 ausente"
echo "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*> *Paste12 *<' && say "✓ h1.brand Paste12" || say "✗ h1.brand ausente"
echo "$HTML" | grep -qi 'id="tagline".*(Reta|secreto|Confiesa)' && say "✓ tagline lúdico" || say "✗ tagline ausente"
hr

# ---------- Health & paginación ----------
say "== HEALTH & PAGINACIÓN =="
curl -sI "$BASE/api/health" | head -n1
HEADERS="$(curl -si "$BASE/api/notes?limit=2")"
echo "$HEADERS" | sed -n '1,20p' | grep -i -E '^link:|^x-next-cursor:' || true
body="$(curl -fsS "$BASE/api/notes?limit=2")"
count="$(printf "%s" "$body" | jq -r '.items|length' 2>/dev/null || echo 0)"
[ "$count" -ge 1 ] && say "✓ feed items: $count" || say "✗ feed vacío"
hr

# ---------- Smoke de likes (1x persona) ----------
say "== SMOKE LIKES (1x persona) =="
NEW="$(curl -fsS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"doctor like smoke"}' | jq -r '.item.id')"
say "nota nueva id: $NEW"
L1="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes')"
L2="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" | jq -r '.likes')"
if [ "$L1" = "$L2" ]; then say "✓ dedupe misma FP ($L1)"; else say "✗ dedupe falló ($L1 -> $L2)"; fi
L3="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: a' | jq -r '.likes')"
L4="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: b' | jq -r '.likes')"
L5="$(curl -fsS -X POST "$BASE/api/notes/$NEW/like" -H 'X-FP: c' | jq -r '.likes')"
say "likes tras 3 FPs nuevas: $L3 -> $L4 -> $L5"
hr

# ---------- Terms & Privacy ----------
say "== TERMS & PRIVACY =="
curl -sI "$BASE/terms"   | head -n1
curl -sI "$BASE/privacy" | head -n1
hr

# ---------- Diagnóstico opcional ----------
say "== BRIDGE-STATE (si existe) =="
curl -fsS "$BASE/api/bridge-state" 2>/dev/null | jq . || say "(endpoint ausente, opcional)"

say "== RESUMEN =="
say "- Deploy en HEAD local:   $([ "$LOCAL" = "$REMOTE" ] && echo OK || echo NO)"
say "- Bridge activo en /:     $(curl -sI "$BASE/" | grep -qi '^x-wsgi-bridge:' && echo SI || echo NO)"
say "- no-store en /:          $(curl -sI "$BASE/" | grep -qi '^cache-control:.*no-store' && echo SI || echo NO)"
say "- UI pastel visible:      $(echo "$HTML" | grep -qm1 -- '--teal:#8fd3d0' && echo SI || echo NO)"

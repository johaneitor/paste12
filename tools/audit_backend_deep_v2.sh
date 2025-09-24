#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
[ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

pick_dest() {
  for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/storage/downloads" "$HOME/Download" "$HOME/downloads"; do
    if [ -d "$d" ] 2>/dev/null && [ -w "$d" ] 2>/dev/null; then echo "$d"; return; fi
  done
  mkdir -p "$HOME/downloads"; echo "$HOME/downloads"
}
DEST="$(pick_dest)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="$DEST/backend-audit-$TS.txt"
TMP="${TMPDIR:-/tmp}/ba.$$"; mkdir -p "$TMP"

say(){ echo -e "$*" | tee -a "$OUT" >/dev/null; }
hr(){ say "\n---------------------------------------------"; }

echo "# Backend Audit — $TS" > "$OUT"
say "- BASE: $BASE"
say "- Destino: $OUT"

#### 0) Health + CORS (preflight)
hr; say "== HEALTH =="; curl -fsS "$BASE/api/health" | tee -a "$OUT" >/dev/null; echo >> "$OUT"
hr; say "== PRELIGHT (OPTIONS /api/notes) =="; curl -fsS -D "$TMP.h.opt" -o /dev/null -X OPTIONS "$BASE/api/notes" || true
sed -n '1,25p' "$TMP.h.opt" | tee -a "$OUT" >/dev/null

#### 1) Listado inicial (graba Link/X-Next-Cursor)
hr; say "== LIST (limit=5) =="; curl -fsS -D "$TMP.h.list1" "$BASE/api/notes?limit=5" -o "$TMP.b.list1"
sed -n '1,12p' "$TMP.h.list1" | tee -a "$OUT" >/dev/null
cat "$TMP.b.list1" >> "$OUT"
NEXT="$(awk -F'[<>]' 'tolower($0) ~ /^link:/ {print $2}' "$TMP.h.list1" | sed -n '1p')"
XNEXT="$(sed -n 's/^X-Next-Cursor: //Ip' "$TMP.h.list1" | tail -n1)"

#### 2) Crear nota (JSON -> esperamos 400 si el backend exige forma; luego fallback FORM 201)
hr; say "== CREATE (JSON) esperado 4xx si 'text_required' ==";
curl -sS -o "$TMP.b.cjson" -w "status:%{http_code}\n" -H 'Content-Type: application/json' \
  --data '{"text":"hola"}' "$BASE/api/notes" | tee -a "$OUT" >/dev/null
cat "$TMP.b.cjson" >> "$OUT"
hr; say "== CREATE (FORM fallback) 201 =="
TEXT="audit $TS — 1234567890 abcdefghij texto suficientemente largo"
curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=$TEXT" "$BASE/api/notes" | tee "$TMP.b.cform" >/dev/null
ID="$(sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p' "$TMP.b.cform")"
say "id=$ID"

#### 3) Like / View / Get-by-ID
hr; say "== LIKE =="; curl -fsS -X POST "$BASE/api/notes/$ID/like" | tee -a "$OUT" >/dev/null
hr; say "== VIEW =="; curl -fsS -X POST "$BASE/api/notes/$ID/view" | tee -a "$OUT" >/dev/null
hr; say "== GET BY ID =="; curl -fsS "$BASE/api/notes/$ID" | tee -a "$OUT" >/dev/null

#### 4) TTL y expiración
hr; say "== TTL check (timestamp vs expires_at) ==";
curl -fsS "$BASE/api/notes/$ID" -o "$TMP.note.json"
jq -r '"timestamp: \(.item.timestamp)\nexpires_at: \(.item.expires_at)"' "$TMP.note.json" 2>/dev/null || \
  sed -n 's/.*"timestamp":"\([^"]*\)".*"expires_at":"\([^"]*\)".*/timestamp: \1\nexpires_at: \2/p' "$TMP.note.json" \
  | tee -a "$OUT" >/dev/null

#### 5) Paginación: 2 páginas (limit=5)
hr; say "== PAGINATION x2 ==";
P1="$BASE/api/notes?limit=5"
curl -fsS -D "$TMP.h.p1" "$P1" -o "$TMP.b.p1" >/dev/null
NP1="$(awk -F'[<>]' 'tolower($0) ~ /^link:/ {print $2}' "$TMP.h.p1" | sed -n '1p')"
echo "next1: ${NP1:-"(sin Link)"}" | tee -a "$OUT" >/dev/null
if [ -n "$NP1" ]; then
  curl -fsS -D "$TMP.h.p2" "$BASE$NP1" -o "$TMP.b.p2" >/dev/null
  NP2="$(awk -F'[<>]' 'tolower($0) ~ /^link:/ {print $2}' "$TMP.h.p2" | sed -n '1p')"
  echo "next2: ${NP2:-"(fin)"}" | tee -a "$OUT" >/dev/null
fi

#### 6) Reports => eliminación/ocultamiento (umbral 5 por defecto)
hr; say "== REPORTS => threshold ==";
for i in 1 2 3 4 5; do curl -fsS -X POST "$BASE/api/notes/$ID/report" | tee -a "$OUT" >/dev/null; echo >> "$OUT"; done
hr; say "== GET after reports (esperado 404 si se oculta) ==";
curl -sS -D "$TMP.h.404" -o /dev/null "$BASE/api/notes/$ID" || true
sed -n '1,8p' "$TMP.h.404" | tee -a "$OUT" >/dev/null

#### 7) Single-note page (?id=)
hr; say "== SINGLE NOTE HTML flag (?id=$ID) ==";
curl -fsS "$BASE/?id=$ID&_=$(date +%s)" -o "$TMP.single.html"
if grep -qi 'data-single-note="1"' "$TMP.single.html" || grep -qi 'name="p12-single"' "$TMP.single.html"; then
  echo "OK: flags single-note presentes" | tee -a "$OUT" >/dev/null
else
  echo "⚠ sin flags explícitas (frontend debería renderizar igual la nota única)" | tee -a "$OUT" >/dev/null
fi

hr; echo "Listo. Informe -> $OUT"

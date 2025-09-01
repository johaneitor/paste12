#!/data/data/com.termux/files/usr/bin/bash
# Paquete de auditoría remota para PASTE12 (Termux)
# Uso: ./collect_remote_pack.sh https://tu-dominio.com
set -Eeuo pipefail

BASE="${1:-}"
[ -z "$BASE" ] && { echo "Uso: $0 https://tu-dominio[:puerto]"; exit 2; }
case "$BASE" in http://*|https://*) ;; *) BASE="https://$BASE";; esac
BASE="${BASE%/}"

# Storage para guardar en Downloads
[ -d "$HOME/storage" ] || termux-setup-storage || true

TS="$(date +%F_%H%M)"
HOST="$(echo "$BASE" | sed -E 's#https?://##; s#/.*$##; s#[^a-zA-Z0-9._-]#_#g')"
PACK="audit_pack_${HOST}_$TS"
OUTDIR="./$PACK"
DL_DIR="$HOME/storage/downloads/$PACK"

mkdir -p "$OUTDIR" "$DL_DIR"

# Helpers
curl_h(){ curl -sS -k -D "$1" -o "$2" "$3" || true; }
curl_s(){ curl -sS -k "$@" || true; }
status(){ curl -sS -k -o /dev/null -w "%{http_code}" "$1"; }

echo "$BASE" > "$OUTDIR/app_url.txt"

# 1) /api/health
curl_h "$OUTDIR/health.json.headers" "$OUTDIR/health.json" "$BASE/api/health"

# 2) GET / (index)
curl_h "$OUTDIR/index.headers" "$OUTDIR/index.html" "$BASE/"

# 3) Assets referenciados desde index
grep -Eo '(href|src)="[^"]+"' "$OUTDIR/index.html" \
  | sed 's/^[^"]*"\(.*\)"/\1/' | sort -u > "$OUTDIR/index_assets.list" || true
# Descargar headers de cada asset
while read -r a; do
  [ -z "$a" ] && continue
  case "$a" in http://*|https://*) URL="$a" ;; /*) URL="$BASE$a" ;; *) continue ;; esac
  H="$OUTDIR/asset_$(echo "$a" | sed 's#[^a-zA-Z0-9._-]#_#g').headers"
  curl -sS -k -D "$H" -o /dev/null "$URL" || true
done < "$OUTDIR/index_assets.list"

# 4) /api/notes sample
curl_h "$OUTDIR/notes.headers" "$OUTDIR/notes.json" "$BASE/api/notes?limit=5&active_only=1&wrap=1"
NOTE_ID="$(grep -Eo '"id"[[:space:]]*:[[:space:]]*[0-9]+' "$OUTDIR/notes.json" | head -n1 | grep -Eo '[0-9]+' || true)"
[ -z "$NOTE_ID" ] && NOTE_ID=1
echo "$NOTE_ID" > "$OUTDIR/selected_note_id.txt"

# 5) like/report/alias (corta cuerpos a 512 bytes)
curl -sS -k -X POST "$BASE/api/notes/$NOTE_ID/like" -D "$OUTDIR/like.headers" -o "$OUTDIR/like.body" || true
head -c 512 "$OUTDIR/like.body" > "$OUTDIR/like.preview"; rm -f "$OUTDIR/like.body"

curl -sS -k -X POST "$BASE/api/reports" -H 'Content-Type: application/json' \
  -d "{\"content_id\":\"$NOTE_ID\"}" -D "$OUTDIR/report.headers" -o "$OUTDIR/report.body" || true
head -c 512 "$OUTDIR/report.body" > "$OUTDIR/report.preview"; rm -f "$OUTDIR/report.body"

curl -sS -k -X POST "$BASE/api/notes/$NOTE_ID/report" -D "$OUTDIR/report_alias.headers" -o "$OUTDIR/report_alias.body" || true
head -c 512 "$OUTDIR/report_alias.body" > "$OUTDIR/report_alias.preview"; rm -f "$OUTDIR/report_alias.body"

# 6) CORS preflight
curl -sS -k -X OPTIONS "$BASE/api/reports" \
  -H "Origin: $BASE" \
  -H "Access-Control-Request-Method: POST" \
  -D "$OUTDIR/cors_reports.headers" -o /dev/null || true

# 7) Endpoints de diagnóstico opcionales (si existen)
curl_h "$OUTDIR/debug_urlmap.json.headers" "$OUTDIR/debug_urlmap.json" "$BASE/api/debug-urlmap"
curl_h "$OUTDIR/diag_import.json.headers" "$OUTDIR/diag_import.json" "$BASE/api/diag-import"

# 8) Resumen
{
  echo "REMOTE AUDIT SUMMARY — $BASE — $TS"
  echo "Health:   $(status "$BASE/api/health")"
  echo "Index:    $(status "$BASE/")"
  echo "Notes:    $(status "$BASE/api/notes?limit=1")"
  echo "Like:     $(curl -sS -k -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/$NOTE_ID/like")"
  echo "Reports:  $(curl -sS -k -o /dev/null -w "%{http_code}" -X POST "$BASE/api/reports" -H 'Content-Type: application/json' -d "{\"content_id\":\"$NOTE_ID\"}")"
  echo "AliasRpt: $(curl -sS -k -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes/$NOTE_ID/report")"
  echo "CORS:     $(curl -sS -k -o /dev/null -w "%{http_code}" -X OPTIONS "$BASE/api/reports" -H "Origin: $BASE" -H "Access-Control-Request-Method: POST")"
} > "$OUTDIR/_SUMMARY.txt"

# 9) Copiar al directorio de Downloads y comprimir
cp -a "$OUTDIR/." "$DL_DIR/"
( cd "$HOME/storage/downloads" && zip -qr "${PACK}.zip" "$PACK" )
echo "✅ Paquete listo:"
echo " - Carpeta: $DL_DIR"
echo " - ZIP:     $HOME/storage/downloads/${PACK}.zip"
echo "Subí esa carpeta o el ZIP al nuevo proyecto."

#!/data/data/com.termux/files/usr/bin/bash
# Auditoría remota paste12 — pasa la BASE_URL como primer argumento (https://tudominio)
set -Eeuo pipefail

BASE="${1:-}"
[ -z "$BASE" ] && { echo "Uso: $0 https://tu-dominio[:puerto][/prefijo]"; exit 2; }
case "$BASE" in http://*|https://*) ;; *) BASE="https://$BASE";; esac
BASE="${BASE%/}"

# Enable storage for logs (primera vez puede pedir permiso)
[ -d "$HOME/storage" ] || termux-setup-storage || true

TS="$(date +%F_%H%M)"
HOST="$(echo "$BASE" | sed -E 's#https?://##; s#/.*$##; s#[^a-zA-Z0-9._-]#_#g')"
OUT="$HOME/storage/downloads/remote_audit_${HOST}_$TS.txt"

# Helpers
line(){ printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'; }
hdr(){ echo; echo "## $*"; }
curl_slim(){ curl -sS -k "$@"; }             # -k por si hay cert sin cadena completa
curl_head(){ curl -sS -k -D - -o /dev/null "$@"; }
status_of(){ curl -sS -k -o /dev/null -w "%{http_code}" "$@"; }

echo "🌐 Remote audit paste12 — $BASE — $TS" | tee "$OUT"
line | tee -a "$OUT"

# 1) /api/health
hdr "1) /api/health"
curl_head "$BASE/api/health" | tee -a "$OUT"

# 2) GET / (index) — capturar headers y detectar CSP & cabeceras de seguridad
hdr "2) GET / (index + cabeceras)"
TMPH="$(mktemp)"; TMPI="$(mktemp)"
curl -sS -k -D "$TMPH" -o "$TMPI" "$BASE/" || true
awk 'BEGIN{IGNORECASE=1}
/^(strict-transport-security|x-frame-options|x-content-type-options|referrer-policy|permissions-policy|content-security-policy):/ {print}' "$TMPH" | tee -a "$OUT"
echo >>"$OUT"
echo "# Título y enlaces estáticos del index:" | tee -a "$OUT"
grep -Eo '<title>[^<]*' "$TMPI" | head -n1 | sed 's/^/< /' | tee -a "$OUT"
grep -Eo '(href|src)="[^"]+"' "$TMPI" | sed 's/^[^"]*"\(.*\)"/\1/' | sort -u | tee -a "$OUT"

# 3) Verificar assets referenciados en index (existencia y código)
hdr "3) Assets referenciados (status)"
while read -r asset; do
  [ -z "$asset" ] && continue
  case "$asset" in http://*|https://*) URL="$asset" ;; /*) URL="$BASE$asset" ;; *) continue ;; esac
  code=$(status_of "$URL")
  printf " - %-60s %s\n" "$URL" "$code" | tee -a "$OUT"
done < <(grep -Eo '(href|src)="[^"]+"' "$TMPI" | sed 's/^[^"]*"\(.*\)"/\1/' | sort -u)

# 4) /api/notes (obtener un id para pruebas)
hdr "4) /api/notes?limit=5 — sample"
NOTES_JSON="$(curl_slim "$BASE/api/notes?limit=5&active_only=1&wrap=1" || true)"
echo "$NOTES_JSON" | sed -E 's/","/","\
/g' | head -n 20 | tee -a "$OUT"
NOTE_ID=""
# Intento simple de extraer el primer "id" (sin jq)
NOTE_ID="$(echo "$NOTES_JSON" | grep -Eo '"id"[[:space:]]*:[[:space:]]*[0-9]+' | head -n1 | grep -Eo '[0-9]+' || true)"
[ -z "$NOTE_ID" ] && NOTE_ID="1"
echo "→ NOTE_ID para tests: $NOTE_ID" | tee -a "$OUT"

# 5) POST like y report
hdr "5) POST like/report (códigos y fragmentos)"
echo "- /api/notes/$NOTE_ID/like"
curl -sS -k -X POST "$BASE/api/notes/$NOTE_ID/like" -D - -o - | head -c 400 | tee -a "$OUT" || true
echo
echo "- /api/reports (JSON)"
curl -sS -k -X POST "$BASE/api/reports" -H 'Content-Type: application/json' \
  -d "{\"content_id\":\"$NOTE_ID\"}" -D - -o - | head -c 400 | tee -a "$OUT" || true
echo
echo "- alias /api/notes/$NOTE_ID/report"
curl -sS -k -X POST "$BASE/api/notes/$NOTE_ID/report" -D - -o - | head -c 400 | tee -a "$OUT" || true
echo

# 6) Preflight CORS sobre /api/reports
hdr "6) OPTIONS (CORS preflight) /api/reports"
curl_head -X OPTIONS "$BASE/api/reports" \
  -H "Origin: $BASE" \
  -H "Access-Control-Request-Method: POST" | tee -a "$OUT"

# 7) Resumen de salud rápida
hdr "7) Resumen"
printf "Health:   %s\n" "$(status_of "$BASE/api/health")" | tee -a "$OUT"
printf "Index:    %s\n" "$(status_of "$BASE/")" | tee -a "$OUT"
printf "Notes:    %s\n" "$(status_of "$BASE/api/notes?limit=1")" | tee -a "$OUT"
printf "Like:     %s\n" "$(status_of -X POST "$BASE/api/notes/$NOTE_ID/like")" | tee -a "$OUT"
printf "Reports:  %s\n" "$(status_of -X POST "$BASE/api/reports" -H 'Content-Type: application/json' -d "{\"content_id\":\"$NOTE_ID\"}")" | tee -a "$OUT"
printf "AliasRpt: %s\n" "$(status_of -X POST "$BASE/api/notes/$NOTE_ID/report")" | tee -a "$OUT"
printf "CORS:     %s\n" "$(status_of -X OPTIONS "$BASE/api/reports" -H "Origin: $BASE" -H "Access-Control-Request-Method: POST")" | tee -a "$OUT"

echo
line | tee -a "$OUT"
echo "📝 Informe guardado en: $OUT" | tee -a "$OUT"

# 8) Tips si algo falla
echo "Tips: si ves 404 en /api/reports, el alias /api/notes/<id>/report puede existir o viceversa." | tee -a "$OUT"
echo "      si faltan cabeceras HSTS/XFO/XCTO/Referrer-Policy, falta hardening en backend." | tee -a "$OUT"

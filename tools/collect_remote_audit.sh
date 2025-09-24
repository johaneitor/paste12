#!/usr/bin/env bash
set -euo pipefail

# === Config ===
APP="${APP:-}"
[ -n "$APP" ] || { echo "[!] Setea APP, ej: export APP=https://tu-app.onrender.com"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$HOME/paste12_audit_$TS"
ZIP="/sdcard/Download/paste12_remote_audit_$TS.zip"

mkdir -p "$OUTDIR"

# utilidad curl segura
curlj() { curl -sS -H 'Accept: application/json' "$@"; }

log() { echo "[$(date +%H:%M:%S)] $*"; }

# === Recolección ===
log "App: $APP"
echo "$APP" > "$OUTDIR/app_url.txt"

# 1) diag/import
log "GET /api/diag/import"
curlj "$APP/api/diag/import" | tee "$OUTDIR/diag_import.json" >/dev/null || true

# 2) health
log "GET /api/health"
curlj "$APP/api/health" | tee "$OUTDIR/health.json" >/dev/null || true

# 3) version
log "GET /api/version"
curl -sS "$APP/api/version" | tee "$OUTDIR/version.raw" >/dev/null || true

# 4) urlmap filtrado
log "GET /api/debug-urlmap"
curlj "$APP/api/debug-urlmap" | tee "$OUTDIR/debug_urlmap.json" >/dev/null || true

# 5) notes diag (si existe)
log "GET /api/notes/diag"
curl -sS "$APP/api/notes/diag" | tee "$OUTDIR/notes_diag.raw" >/dev/null || true

# 6) intentar reparar interacciones (idempotente)
log "POST /api/notes/repair-interactions"
curl -sS -X POST "$APP/api/notes/repair-interactions" | tee "$OUTDIR/repair_interactions.raw" >/dev/null || true

# 7) primer ID de nota y pruebas ix/*
log "GET /api/notes?page=1"
curl -sS "$APP/api/notes?page=1" | tee "$OUTDIR/notes_page1.raw" >/dev/null || true

ID="$(jq -r '.[0].id // empty' "$OUTDIR/notes_page1.raw" 2>/dev/null || true)"
if [ -z "${ID:-}" ]; then
  log "No hay notas — creando una 'probe'"
  curl -sS -X POST -H 'Content-Type: application/json' \
    -d '{"text":"probe","hours":24}' \
    "$APP/api/notes" | tee "$OUTDIR/note_create.raw" >/dev/null || true
  ID="$(jq -r '.id // empty' "$OUTDIR/note_create.raw" 2>/dev/null || true)"
fi
echo "${ID:-}" > "$OUTDIR/note_id.txt"

if [ -n "${ID:-}" ]; then
  log "POST /api/ix/notes/$ID/like"
  curl -si -X POST "$APP/api/ix/notes/$ID/like"  | tee "$OUTDIR/ix_like.http"  >/dev/null || true
  log "POST /api/ix/notes/$ID/view"
  curl -si -X POST "$APP/api/ix/notes/$ID/view"  | tee "$OUTDIR/ix_view.http"  >/dev/null || true
  log "GET  /api/ix/notes/$ID/stats"
  curl -si      "$APP/api/ix/notes/$ID/stats"    | tee "$OUTDIR/ix_stats.http" >/dev/null || true
fi

# 8) informe rápido en texto
{
  echo "=== paste12 remote audit ($TS) ==="
  echo "APP: $APP"
  echo
  echo "--- diag/import ---"
  cat "$OUTDIR/diag_import.json" 2>/dev/null || true
  echo
  echo "--- health ---"
  cat "$OUTDIR/health.json" 2>/dev/null || true
  echo
  echo "--- version (raw) ---"
  cat "$OUTDIR/version.raw" 2>/dev/null || true
  echo
  echo "--- urlmap (filtrado por /api/(notes|ix)) ---"
  if command -v jq >/dev/null 2>&1; then
    jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))' "$OUTDIR/debug_urlmap.json" 2>/dev/null || true
  else
    cat "$OUTDIR/debug_urlmap.json" 2>/dev/null || true
  fi
  echo
  echo "--- notes diag (raw) ---"
  cat "$OUTDIR/notes_diag.raw" 2>/dev/null || true
  echo
  echo "--- repair-interactions (raw) ---"
  cat "$OUTDIR/repair_interactions.raw" 2>/dev/null || true
  echo
  echo "--- notes page1 (raw) ---"
  cat "$OUTDIR/notes_page1.raw" 2>/dev/null || true
  echo
  echo "--- chosen note id ---"
  cat "$OUTDIR/note_id.txt" 2>/dev/null || true
  echo
  if [ -n "${ID:-}" ]; then
    echo "--- ix like (HTTP) ---"
    sed -n '1,140p' "$OUTDIR/ix_like.http" 2>/dev/null || true
    echo
    echo "--- ix view (HTTP) ---"
    sed -n '1,140p' "$OUTDIR/ix_view.http" 2>/dev/null || true
    echo
    echo "--- ix stats (HTTP) ---"
    sed -n '1,200p' "$OUTDIR/ix_stats.http" 2>/dev/null || true
  fi
} | sed $'s/\r$//' > "$OUTDIR/_SUMMARY.txt"

# 9) empaquetar en zip a /sdcard/Download
log "Empaquetando en: $ZIP"
cd "$OUTDIR/.."
zip -r "$ZIP" "$(basename "$OUTDIR")" >/dev/null

log "[OK] Listo: $ZIP"
echo "$ZIP"

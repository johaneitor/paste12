#!/bin/bash
# Auditoría frontend-backend: verifica API /api/notes, CORS, publicación, like, view, paginación y TTL
timestamp=$(date +%Y%m%d%H%M%S)
logfile="/sdcard/Download/fe-be-audit-${timestamp}.txt"
echo "=== Auditoría Frontend-Backend - $(date) ===" > "$logfile"

BASE="https://paste12-rmsk.onrender.com"   # Ajustar base URL del servidor backend

# 1. Verificar GET /api/notes
echo "-- GET /api/notes --" >> "$logfile"
resp=$(curl -sfSL -X GET "${BASE}/api/notes")
if echo "$resp" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
  echo "OK: /api/notes GET respondió JSON válido." >> "$logfile"
else
  echo "ERROR: /api/notes GET no devolvió JSON válido." >> "$logfile"
fi

# 2. Verificar preflight OPTIONS (CORS) y revisar cabeceras
echo "-- Verificación CORS (OPTIONS) --" >> "$logfile"
origin="http://example.com"
cors_headers=$(curl -si -X OPTIONS -H "Origin: $origin" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: Content-Type" "${BASE}/api/notes")
if echo "$cors_headers" | grep -qi "Access-Control-Allow-Origin"; then
  echo "OK: ACAO presente." >> "$logfile"
else
  echo "ERROR: ACAO ausente." >> "$logfile"
fi
if echo "$cors_headers" | grep -qi "Access-Control-Allow-Methods"; then
  echo "OK: ACAM (métodos permitidos) presente." >> "$logfile"
else
  echo "ERROR: ACAM ausente." >> "$logfile"
fi
if echo "$cors_headers" | grep -qi "Access-Control-Allow-Headers"; then
  echo "OK: ACAH (headers permitidos) presente." >> "$logfile"
else
  echo "ERROR: ACAH ausente." >> "$logfile"
fi
if echo "$cors_headers" | grep -qi "Access-Control-Max-Age"; then
  echo "OK: Access-Control-Max-Age presente." >> "$logfile"
else
  echo "INFO: Access-Control-Max-Age no presente (usar si aplica)." >> "$logfile"
fi

# 3. Crear nota de prueba (POST /api/notes)
echo "-- Creación de nota de prueba --" >> "$logfile"
note_json='{"title":"Test","body":"Texto de prueba","reports":0}'
create_resp=$(curl -sfSL -H "Content-Type: application/json" -X POST -d "$note_json" "${BASE}/api/notes")
if echo "$create_resp" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
  echo "OK: JSON válido al crear nota." >> "$logfile"
else
  echo "ERROR: Respuesta inválida al crear nota." >> "$logfile"
fi
note_id=$(echo "$create_resp" | grep -oP '"id"\s*:\s*\K[0-9]+')
if [ -n "$note_id" ]; then
  echo "Nota creada con ID=$note_id." >> "$logfile"
else
  echo "ERROR: No se obtuvo ID de nota." >> "$logfile"
fi

# 4. Like y view de la nota creada
for action in "like" "view"; do
  if [ -n "$note_id" ]; then
    echo "-- /api/notes/$note_id/$action --" >> "$logfile"
    resp_action=$(curl -sfSL "${BASE}/api/notes/${note_id}/${action}")
    if echo "$resp_action" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null; then
      echo "OK: JSON válido en $action." >> "$logfile"
    else
      echo "ERROR: JSON inválido en $action." >> "$logfile"
    fi
  fi
done

# 5. Verificar paginación (Link: rel=\"next\")
echo "-- Verificar paginación --" >> "$logfile"
list_headers=$(curl -si "${BASE}/api/notes")
if echo "$list_headers" | grep -q 'Link:.*rel="next"'; then
  echo "OK: Header 'Link: rel=\"next\"' presente." >> "$logfile"
else
  echo "INFO: No se encontró paginación (Link rel=\"next\") en encabezados." >> "$logfile"
fi

# 6. Verificar TTL/Cache en encabezados
if echo "$list_headers" | grep -qi "Cache-Control"; then
  cache_val=$(echo "$list_headers" | grep -i "Cache-Control")
  echo "INFO: Cache-Control presente: $cache_val" >> "$logfile"
else
  echo "INFO: Cache-Control ausente en /api/notes." >> "$logfile"
fi

# 7. Probar duplicados (si aplica)
echo "-- Prueba de duplicados --" >> "$logfile"
dup_resp=$(curl -sfSL -H "Content-Type: application/json" -X POST -d "$note_json" "${BASE}/api/notes")
if echo "$dup_resp" | grep -q '"deduped":false'; then
  echo "WARN: nota duplicada detectada (deduped=false)." >> "$logfile"
else
  echo "INFO: campo deduped no encontrado o deduplicación diferente." >> "$logfile"
fi

echo "=== Fin de auditoría FE-BE ===" >> "$logfile"

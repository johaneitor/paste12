#!/bin/bash
echo "Patch 1: Corrigiendo /api/health para devolver JSON..."
# Buscar archivo que define la ruta /api/health
file_h=$(grep -R "route('/api/health" -l . || grep -R "route(\"/api/health" -l .)
if [ -n "$file_h" ]; then
  # Asegurar que jsonify esté importado
  if ! grep -q "jsonify" "$file_h"; then
    sed -i "0,/from flask import/s/from flask import \(.*\)/from flask import \1, jsonify/" "$file_h"
  fi
  # Reemplazar respuesta 'OK' o 'ok' por JSON {"ok": True}
  sed -i "s/return\s\+\"OK\"/return jsonify({'ok': True})/" "$file_h"
  sed -i "s/return\s\+'OK'/return jsonify({'ok': True})/" "$file_h"
  sed -i "s/return\s\+\"ok\"/return jsonify({'ok': True})/" "$file_h"
  sed -i "s/return\s\+'ok'/return jsonify({'ok': True})/" "$file_h"
  echo "-> Endpoint /api/health parcheado en $file_h"
else
  echo "(!) No se encontró ruta /api/health en el proyecto."
fi

#!/bin/bash
echo "Patch 3: Agregando cabecera Link para paginación en /api/notes..."
file_main=$(grep -R "route('/api/notes" -l . || grep -R "route(\"/api/notes" -l .)
if [ -n "$file_main" ]; then
  # Asegurar importación de request (necesaria para after_request)
  if ! grep -q "request" "$file_main"; then
    sed -i "0,/from flask import/s/from flask import \(.*\)/from flask import \1, request/" "$file_main"
  fi
  # Añadir función after_request para adjuntar Link si existe un cursor "next"
  cat >> "$file_main" <<'PYCODE'

# Agregar cabecera Link y CORS a respuestas de /api/notes
@app.after_request
def add_link_header(response):
    # Permitir CORS en todas las respuestas de la API
    if request.path.startswith('/api/'):
        response.headers['Access-Control-Allow-Origin'] = '*'
    # Si la respuesta corresponde a GET /api/notes con paginación, agregar Link
    if request.path == '/api/notes' and response.is_json:
        try:
            data = response.get_json()
        except Exception:
            data = None
        if data and isinstance(data, dict) and data.get('next'):
            xn = data['next']
            if xn and 'cursor_ts' in xn and 'cursor_id' in xn:
                response.headers['Link'] = f"</api/notes?cursor_ts={xn['cursor_ts']}&cursor_id={xn['cursor_id']}>; rel=\"next\""
    return response
PYCODE
  echo "-> Función after_request añadida en $file_main (Link header en paginación)"
else
  echo "(!) No se pudo aplicar patch Link (archivo no encontrado)."
fi

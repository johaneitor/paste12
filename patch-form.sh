#!/bin/bash
echo "Patch 4: Soporte a formulario en POST /api/notes..."
file_main=$(grep -R "route('/api/notes" -l . || grep -R "route(\"/api/notes" -l .)
if [ -n "$file_main" ]; then
  # Insertar bloque para transformar datos de formulario a JSON al inicio del manejo POST
  post_line=$(grep -n "if request.method == 'POST'" "$file_main" | cut -d: -f1)
  if [ -n "$post_line" ]; then
    sed -i "$((post_line+1))a\\
        # Soporte a POST de formulario (convierte a JSON si Content-Type no es JSON)\\
        data = request.get_json(silent=True) or {}\\
        if not data.get('text'):\\
            if 'text' in request.form: data['text'] = request.form['text']\\
            if 'ttl_hours' in request.form: data['ttl_hours'] = request.form['ttl_hours']\\
        # A partir de aquí, 'data' contiene texto (y ttl_hours si enviado) para crear la nota" "$file_main"
    echo "-> Lógica de fallback de formulario añadida en $file_main"
  else
    echo "(!) No se encontró bloque POST en $file_main"
  fi
else
  echo "(!) No se pudo aplicar patch Form (archivo no encontrado)."
fi

#!/bin/bash
echo "Patch 2: Agregando soporte CORS a /api/notes (OPTIONS)..."
# Buscar archivo de backend que define la ruta /api/notes
file_main=$(grep -R "route('/api/notes" -l . || grep -R "route(\"/api/notes" -l .)
if [ -n "$file_main" ]; then
  # Incluir 'OPTIONS' en los métodos permitidos de la ruta /api/notes
  sed -i "s/\(['\"]GET['\"]\s*,\s*['\"]POST['\"]\s*\)/\1,'OPTIONS'/" "$file_main"
  # Asegurar importación de make_response (para construir respuesta vacía con headers)
  if ! grep -q "make_response" "$file_main"; then
    sed -i "0,/from flask import/s/from flask import \(.*\)/from flask import \1, make_response/" "$file_main"
  fi
  # Insertar manejo explícito de OPTIONS al inicio de la función /api/notes
  def_line=$(grep -n "def [a-zA-Z_]*notes" "$file_main" | cut -d: -f1)
  if [ -n "$def_line" ]; then
    insert_line=$((def_line+1))
    sed -i "${insert_line}a\\
    # Manejo de preflight CORS\\
    if request.method == 'OPTIONS':\\
        res = make_response('', 204)\\
        res.headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'\\
        res.headers['Access-Control-Allow-Headers'] = 'Content-Type'\\
        res.headers['Access-Control-Allow-Origin'] = '*'\\
        res.headers['Access-Control-Max-Age'] = '600'\\
        return res" "$file_main"
  fi
  echo "-> Soporte OPTIONS /api/notes añadido en $file_main"
else
  echo "(!) No se encontró ruta /api/notes en el proyecto."
fi

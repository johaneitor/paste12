#!/bin/bash
echo "Patch 5: Manejo seguro de /like, /view, /report..."
# Buscar archivo(s) con endpoints /like, /view, /report
actions_file=$(grep -R "route('/api/notes/<" -l . || grep -R 'route("/api/notes/<' -l .)
if [ -n "$actions_file" ]; then
  for action in like view report; do
    def_line=$(grep -n "def ${action}" "$actions_file" | cut -d: -f1)
    if [ -n "$def_line" ]; then
      sed -i "$((def_line+1))a\\
    # Comprobación de existencia de nota\\
    note = Note.query.get(note_id)\\
    if not note:\\
        return {'ok': False, 'error': 'Nota no encontrada'}, 404" "$actions_file"
      echo "-> Validación en def ${action} agregada (${actions_file})"
    fi
  done
else
  echo "(!) No se encontraron endpoints like/view/report."
fi

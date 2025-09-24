#!/usr/bin/env bash
set -euo pipefail
echo "== Buscando marcador en wsgiapp.py =="
grep -n "WSGI EARLY PIN: rutas mínimas para diagnóstico" -n wsgiapp.py || { echo "No se ve el bloque."; exit 1; }
echo
echo "== Últimas 120 líneas de wsgiapp.py (para inspección) =="
nl -ba wsgiapp.py | tail -n 120

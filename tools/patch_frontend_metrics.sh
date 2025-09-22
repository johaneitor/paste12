#!/bin/bash
echo "== Insertando bloque de métricas (views) en frontend/index.html =="

HTML_FILE="frontend/index.html"
METRIC_SNIPPET='class="views"'

if grep -q "$METRIC_SNIPPET" "$HTML_FILE"; then
    echo "El bloque de métricas 'views' ya existe en $HTML_FILE. Sin cambios."
else
    echo "Agregando span de 'views' en $HTML_FILE..."
    sed -i -E 's/· 👁 (\$\{it\.views\?\?0\})/· <span class="views">👁 \1<\/span>/' "$HTML_FILE"
    # Verificación rápida:
    if grep -q "$METRIC_SNIPPET" "$HTML_FILE"; then
        echo "$HTML_FILE parchado correctamente con bloque de métricas ✅"
    else
        echo "ERROR: No se pudo insertar el bloque de métricas en $HTML_FILE. ⚠️"
    fi
fi

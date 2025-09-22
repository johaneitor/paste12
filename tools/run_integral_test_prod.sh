#!/bin/bash
echo "== Ejecutando test integral en producción y analizando resultados =="

BASE="https://paste12-rmsk.onrender.com"
OUTPUT_FILE="/tmp/test_integral_output.txt"

echo "Probando base URL: $BASE"
# Ejecutar el test integral y capturar salida
bash tools/test_exec_integral_v12.sh "$BASE" | tee "$OUTPUT_FILE"

echo ""
echo "== Análisis de resultados conocidos =="

# Advertencias de CORS (Access-Control-Allow-Origin ausente)
if ! grep -qi 'access-control-allow-origin' "$OUTPUT_FILE"; then
    echo "WARNING: Falta 'Access-Control-Allow-Origin' en las respuestas (posible problema CORS)."
fi

# Advertencia si falta encabezado Link en la lista de notas
if ! grep -qi 'link: ' "$OUTPUT_FILE"; then
    echo "WARNING: Falta encabezado 'Link' en la respuesta de paginación."
fi

# Advertencias sobre códigos de error conocidos en operaciones like/view/report
if grep -q 'like   -> 500' "$OUTPUT_FILE"; then
    echo "WARNING: La operación 'Like' en nota inexistente devolvió 500 (esperado 404)."
fi
if grep -q 'report -> 500' "$OUTPUT_FILE"; then
    echo "WARNING: La operación 'Report' en nota inexistente devolvió 500 (esperado 404)."
fi
if grep -q 'view   -> 404' "$OUTPUT_FILE"; then
    echo "NOTE: La operación 'View' en nota inexistente devolvió 404 (para confirmar comportamiento esperado)."
fi

#!/bin/bash
# Script: final_verify.sh
# Propósito: Ejecuta todos los tests integrales y produce un resumen final de aprobación (PASS/FAIL).
# Uso: ./final_verify.sh [URL_BASE]
#    (URL_BASE es opcional; si no se indica se usará la predeterminada de producción.)
# Descripción:
# - Llama al script run_tests.sh para ejecutar todas las pruebas.
# - Captura la salida de los tests y analiza patrones de posibles fallos (códigos 500, meta faltante, etc).
# - Muestra la salida completa de las pruebas y luego un resumen indicando éxito o fallos.
# 
# Notas:
# - Los criterios de FAIL se basan en patrones conocidos de error en la salida de tests (e.g., "-> 500", "single: body").
# - Asegúrese de ejecutar primero fix_backend.sh para aplicar correcciones antes de esta verificación final.

set -e

# Usar el script de tests unificado y capturar su salida
OUTPUT=$(./run_tests.sh "$@" 2>&1)

# Mostrar la salida completa de las pruebas para referencia
echo "$OUTPUT"

# Analizar la salida en busca de indicadores de fallo
# Se consideran fallos: códigos 5xx en resultados de endpoints, meta de single ausente (single: body), o cualquier "FAIL" explícito.
if echo "$OUTPUT" | grep -qE '->\s*5[0-9]{2}|single:\s*body|FAIL'; then
    echo -e "\nResumen: ❌ Algunas pruebas **FALLARON**. Por favor revisar los detalles arriba."
    if echo "$OUTPUT" | grep -q "-> 500"; then
        echo " - Detectado código 500 en alguna respuesta de API (debe ser corregido a 404 u otro código esperado)."
    fi
    if echo "$OUTPUT" | grep -q "single: body"; then
        echo " - La metaetiqueta p12-single no se encontró en el <head> para vista individual (debería estar presente)."
    fi
    # (Agregar otros análisis detallados si se desea)
else
    echo -e "\nResumen: ✅ **TODOS los tests pasaron** correctamente. Backend en verde."
fi

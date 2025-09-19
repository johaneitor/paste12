#!/bin/bash
# Script: run_tests.sh
# Propósito: Ejecuta de forma unificada todos los suites de prueba integrales del backend Paste12.
# Uso: ./run_tests.sh [URL_BASE]
#    (Si no se indica URL_BASE, usará la predeterminada del despliegue en Render.)
# Descripción:
# - Define la URL base para las pruebas (por defecto https://paste12-rmsk.onrender.com).
# - Ejecuta secuencialmente los scripts de prueba: test_suite_all, test_suite_negative_v5, test_like_view, check_reported_count.
# - Muestra la salida completa de cada suite para análisis manual.
# 
# Requisitos: Deben existir los scripts de prueba en tools/ con permisos de ejecución.

set -e

# Determinar URL base (argumento o variable de entorno BASE_URL), por defecto la URL pública de Paste12
BASE_URL_DEFAULT="https://paste12-rmsk.onrender.com"
BASE="${1:-${BASE_URL:-$BASE_URL_DEFAULT}}"
export BASE

echo "Usando URL base: $BASE"
echo "Iniciando ejecución de todos los tests integrados..."

# Ejecutar cada suite de pruebas con separación visible
echo -e "\n===== Ejecutando test_suite_all.sh ====="
tools/test_suite_all.sh

echo -e "\n===== Ejecutando test_suite_negative_v5.sh ====="
tools/test_suite_negative_v5.sh

echo -e "\n===== Ejecutando test_like_view.sh ====="
tools/test_like_view.sh

echo -e "\n===== Ejecutando check_reported_count.sh ====="
tools/check_reported_count.sh

echo -e "\n===== Fin de ejecución de tests ====="

#!/bin/bash
# Verificación SEO básica: título, descripción, enlaces legales
timestamp=$(date +%Y%m%d%H%M%S)
logfile="/sdcard/Download/seo-audit-${timestamp}.txt"
echo "=== Auditoría SEO - $(date) ===" > "$logfile"

SITE_URL="https://paste12-rmsk.onrender.com"  # Ajustar URL

html=$(curl -sfL --max-time 20 "$SITE_URL")
if [ -z "$html" ]; then
  echo "ERROR: No se pudo obtener el HTML para SEO." >> "$logfile"
else
  # Título
  title_count=$(echo "$html" | grep -ci '<title>')
  if [ "$title_count" -eq 0 ]; then
    echo "ERROR: Falta etiqueta <title> para SEO." >> "$logfile"
  elif [ "$title_count" -gt 1 ]; then
    echo "ERROR: Múltiples <title> encontradas ($title_count)." >> "$logfile"
  else
    title_text=$(echo "$html" | grep -oiP '(?<=<title>).*(?=</title>)')
    echo "OK: <title> presente: \"$title_text\"." >> "$logfile"
  fi

  # Meta descripción
  desc_count=$(echo "$html" | grep -ci '<meta name="description"')
  if [ "$desc_count" -eq 0 ]; then
    echo "ERROR: Falta <meta name=\"description\">." >> "$logfile"
  elif [ "$desc_count" -gt 1 ]; then
    echo "ERROR: Múltiples meta description ($desc_count)." >> "$logfile"
  else
    desc_text=$(echo "$html" | grep -oiP '(?<=<meta name="description" content=").*?(?=")')
    desc_len=${#desc_text}
    echo "OK: meta descripción presente (longitud $desc_len). Contenido: \"$desc_text\"" >> "$logfile"
    if [ "$desc_len" -gt 160 ]; then
      echo "WARN: Descripción larga (>160 car.) según mejores prácticas11." >> "$logfile"
    fi
  fi

  # Enlaces a términos y privacidad
  for link in "/terms" "/privacy"; do
    if echo "$html" | grep -qi "href=\"[^\"]*${link}\""; then
      echo "OK: link a ${link} presente." >> "$logfile"
    else
      echo "ERROR: link a ${link} NO encontrado." >> "$logfile"
    fi
  done

  echo "=== Fin de auditoría SEO ===" >> "$logfile"
fi

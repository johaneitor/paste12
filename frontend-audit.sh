#!/bin/bash
# Auditoría avanzada del frontend: verifica HTML, meta etiquetas y AdSense
timestamp=$(date +%Y%m%d%H%M%S)
logfile="/sdcard/Download/frontend-audit-${timestamp}.txt"
echo "=== Auditoría Frontend - $(date) ===" > "$logfile"

# 1. Descargar el HTML de la web
SITE_URL="https://paste12-rmsk.onrender.com"  # Ajustar la URL del frontend
echo "Descargando HTML de $SITE_URL..." >> "$logfile"
html=$(curl -sfL --max-time 30 "$SITE_URL")
if [ -z "$html" ]; then
  echo "ERROR: No se pudo obtener el HTML." >> "$logfile"
else
  # Guardar respaldo del HTML original
  backup="/sdcard/Download/frontend-backup-${timestamp}.html"
  echo "$html" > "$backup"
  if [ -s "$backup" ]; then
    echo "INFO: Respaldo guardado en $backup" >> "$logfile"
  else
    echo "ERROR: No se creó el respaldo HTML." >> "$logfile"
  fi

  # 2. Verificar <!DOCTYPE html>
  if echo "$html" | grep -qi '<!doctype html>'; then
    echo "OK: Doctype HTML5 presente." >> "$logfile"
  else
    echo "ERROR: Falta <!DOCTYPE html>." >> "$logfile"
  fi

  # 3. Verificar <html lang="..">
  if echo "$html" | grep -qi '<html[^>]*lang='; then
    echo "OK: Atributo lang en <html> presente." >> "$logfile"
  else
    echo "WARN: No se encontró atributo lang en <html>." >> "$logfile"
  fi

  # 4. Título y descripción únicas
  title_count=$(echo "$html" | grep -ci '<title>')
  if [ "$title_count" -eq 0 ]; then
    echo "ERROR: Falta etiqueta <title>." >> "$logfile"
  elif [ "$title_count" -gt 1 ]; then
    echo "ERROR: Múltiples etiquetas <title> ($title_count)." >> "$logfile"
  else
    title_text=$(echo "$html" | grep -oiP '(?<=<title>).*(?=</title>)')
    len=${#title_text}
    echo "OK: <title> presente (longitud $len caracteres)." >> "$logfile"
  fi

  desc_count=$(echo "$html" | grep -ci '<meta name="description"')
  if [ "$desc_count" -eq 0 ]; then
    echo "ERROR: Falta <meta name=\"description\">." >> "$logfile"
  elif [ "$desc_count" -gt 1 ]; then
    echo "ERROR: Múltiples meta description ($desc_count)." >> "$logfile"
  else
    desc_text=$(echo "$html" | grep -oiP '(?<=<meta name="description" content=").*?(?=")')
    desc_len=${#desc_text}
    echo "OK: meta description presente (longitud $desc_len caracteres)." >> "$logfile"
    if [ "$desc_len" -gt 160 ]; then
      echo "WARN: Descripción excede 160 caracteres (sugerido máximo 155-1602)." >> "$logfile"
    fi
  fi

  # 5. Detectar y eliminar scripts duplicados
  echo "$html" | grep -oi '<script[^>]*>' | sort | uniq -c > /tmp/scripts_list.txt
  dup_scripts=$(awk '$1>1 {print $2}' /tmp/scripts_list.txt)
  if [ -n "$dup_scripts" ]; then
    echo "WARN: scripts duplicados encontrados:" >> "$logfile"
    echo "$dup_scripts" | sed 's/^/  - /' >> "$logfile"
    # (Aquí se podría eliminar uno de los duplicados si se desea automatizar)
  else
    echo "OK: No hay <script> duplicados detectados." >> "$logfile"
  fi

  # 6. Verificar Google AdSense (ca-pub ID)
  if echo "$html" | grep -q 'ca-pub-[0-9]\+'; then
    pub_ids=$(echo "$html" | grep -o 'ca-pub-[0-9]\+')
    unique_ids=$(echo "$pub_ids" | uniq | wc -l)
    if [ "$unique_ids" -eq 1 ]; then
      echo "OK: ID de AdSense encontrado ($pub_ids)." >> "$logfile"
    else
      echo "ERROR: IDs de AdSense múltiples o conflictivos ($unique_ids)." >> "$logfile"
    fi
  else
    echo "ERROR: No se encontró ID de AdSense (ca-pub) en el HTML." >> "$logfile"
  fi

  # 7. Buscar restos de versiones antiguas en <head>
  if echo "$html" | grep -qi 'version='; then
    echo "INFO: Posible dato de versión antigua presente en el código." >> "$logfile"
  fi
  if echo "$html" | grep -qi '<!--'; then
    echo "INFO: Comentarios HTML detectados (verificar si sobran)." >> "$logfile"
  fi

  echo "=== Fin de auditoría frontend ===" >> "$logfile"
fi

#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 https://host}"
tmpdir="$(mktemp -d)"
html="$tmpdir/index.html"

echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|cache-control:|cf-cache-status:|server:)/{print}'

echo "== DESCARGO / (sin caché) =="
curl -fsS -H 'Cache-Control: no-cache' "$BASE/" -o "$html"
bytes=$(wc -c <"$html" | tr -d ' ')
sha=$(sha256sum "$html" | awk '{print $1}')
echo "tamaño: ${bytes} bytes   sha256: $sha"

# --- Heurísticas HTML ---
hits=0
grep -q -- '--teal:#8fd3d0' "$html" && { echo "• token pastel en HTML"; hits=$((hits+1)); }
grep -qi 'Publicar' "$html"        && { echo "• botón Publicar detectado"; hits=$((hits+1)); }
grep -q '⋯' "$html"                && { echo "• menú ⋯ detectado"; hits=$((hits+1)); }
grep -qi 'Compartir' "$html"       && { echo "• acción Compartir detectada"; hits=$((hits+1)); }
grep -qi 'Reportar' "$html"        && { echo "• acción Reportar detectada"; hits=$((hits+1)); }

if [ "$hits" -ge 2 ]; then
  echo "== RESULTADO: OK UI (HTML markers) =="
  rm -rf "$tmpdir"
  exit 0
fi

# --- Buscar CSS externos y revisar tokens allí ---
echo "== Busco CSS referenciados =="
mapfile -t css_hrefs < <(awk -v IGNORECASE=1 '
  /<link/ && /stylesheet/ && /href=/ {
    while (match($0, /href="[^"]+"/)) {
      href=substr($0, RSTART+6, RLENGTH-7);
      print href;
      $0=substr($0, RSTART+RLENGTH);
    }
  }' "$html" | sort -u)

ok_css=0
for href in "${css_hrefs[@]:-}"; do
  # Resolver URL absoluta
  case "$href" in
    http://*|https://*) url="$href" ;;
    /*)                  url="${BASE%/}$href" ;;
    *)                   url="${BASE%/}/$href" ;;
  esac
  echo "→ CSS: $url"
  cssf="$tmpdir/$(basename "$href" | tr -cd '[:alnum:]._-')"
  if curl -fsS "$url" -o "$cssf"; then
    if grep -q -- '--teal:#8fd3d0' "$cssf"; then
      echo "   ✓ token pastel en CSS"
      ok_css=1
      break
    fi
  fi
done

if [ "$ok_css" -eq 1 ]; then
  echo "== RESULTADO: OK UI (CSS markers) =="
  rm -rf "$tmpdir"
  exit 0
fi

echo "== RESULTADO: NO se detectó token pastel ni marcadores suficientes en HTML/CSS =="
echo "Pistas:"
echo " - Primeras líneas con <style> o encabezado:"
awk 'NR<=40 && /<style|<header|<main|<section|<button|Publicar|Compartir|Reportar|⋯/ {print NR": "$0}' "$html" || true
rm -rf "$tmpdir"
exit 1

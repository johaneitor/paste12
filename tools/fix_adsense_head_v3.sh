#!/usr/bin/env bash
set -euo pipefail

CLIENT_ID="${1:-}"
HTML="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.adsense.bak"

if [[ -z "$CLIENT_ID" ]]; then
  echo "Uso: $0 ca-pub-XXXXXXXXXXXXXXX"; exit 2
fi
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 3; }

cp -f "$HTML" "$BAK"
echo "[fix-adsense] Backup: $BAK"

python - <<PY
import io, re, sys
p = "$HTML"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# Elimina duplicados/obsoletos del tag adsbygoogle (lo dejamos limpio)
s = re.sub(r'\s*<script[^>]*pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js[^>]*></script>\s*', '\n', s, flags=re.I)

# Asegura <head>…</head>
if "<head" not in s.lower() or "</head>" not in s.lower():
    # si el archivo es atípico, lo insertamos al comienzo
    s = "<head></head>\n" + s

tag = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={"""'"""}{"""'"""}"{"""'"""}>{CLIENT_ID}{"""'"""}{"""'"""}{"""'"""}' \
      f'" crossorigin="anonymous"></script>'

# Inserta justo antes de </head> si no está
if "adsbygoogle.js?client=" not in s:
    s = s.replace("</head>", tag + "\n</head>")
else:
    # si está, asegura que tenga el client correcto
    s = re.sub(r'(adsbygoogle\.js\?client=)[^"&>]+', r'\1' + CLIENT_ID, s)

# Limpia service worker (para evitar HTML viejo del cache)
s = re.sub(r'^\s*//\s*SW:? .*$','', s, flags=re.M)
s = re.sub(r'.*serviceWorker\.register.*\n?', '', s)
s = re.sub(r'.*navigator\.serviceWorker.*\n?',   '', s)

# Normaliza múltiples saltos
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[fix-adsense] index.html actualizado")
else:
    print("[fix-adsense] index.html ya estaba OK")
PY

echo "[fix-adsense] Hecho."

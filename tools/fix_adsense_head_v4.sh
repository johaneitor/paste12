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

# Pasamos el client al bloque Python por env
ADS_CLIENT="$CLIENT_ID" python - <<'PY'
import io, os, re, sys
p = "frontend/index.html"
client = os.environ.get("ADS_CLIENT","").strip()
if not client:
    print("ERROR: ADS_CLIENT vacío"); sys.exit(4)

with io.open(p, "r", encoding="utf-8") as f:
    s = f.read()
orig = s

# Quita cualquier <script ... adsbygoogle.js ...> previo
s = re.sub(r'\s*<script[^>]*pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js[^>]*></script>\s*',
           '\n', s, flags=re.I)

# Asegura <head> y </head>
if "</head>" not in s.lower():
    s = "<head></head>\n" + s

tag = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={client}" crossorigin="anonymous"></script>'

# Inserta justo antes de </head>
if "adsbygoogle.js?client=" not in s:
    s = s.replace("</head>", tag + "\n</head>")
else:
    s = re.sub(r'(adsbygoogle\.js\?client=)[^"&>]+', r'\1'+re.escape(client), s)

# Elimina registros de Service Worker para evitar HTML cacheado
s = re.sub(r'.*serviceWorker\.register.*\n?', '', s)
s = re.sub(r'.*navigator\.serviceWorker.*\n?',   '', s)

# Limpieza menores
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    with io.open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("[fix-adsense] index.html actualizado")
else:
    print("[fix-adsense] index.html ya estaba OK")
PY

echo "[fix-adsense] Hecho."

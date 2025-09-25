#!/usr/bin/env bash
set -euo pipefail
HTML="${1:-frontend/index.html}"
ADSENSE_ID_IN="${2:-${ADSENSE_ID:-}}"

[[ -f "$HTML" ]] || { echo "[reconcile] ERROR: falta $HTML"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="$HTML.$TS.reconcile.bak"
cp -f "$HTML" "$BAK"
echo "[reconcile] Backup: $BAK"

python - <<'PY' "$HTML" "$ADSENSE_ID_IN"
import io, os, re, sys

path = sys.argv[1]
adsense_in = sys.argv[2] if len(sys.argv) > 2 else ""

s = io.open(path, "r", encoding="utf-8").read()
orig = s

def once(regex, repl, flags=re.I|re.S):
    nonlocal s
    if re.search(regex, s, flags):
        return False
    s = re.sub(r"(</head>)", repl + r"\1", s, flags)
    return True

def ensure_footer_links():
    nonlocal s
    has_terms  = re.search(r'href=["\']/terms["\']', s, re.I) is not None
    has_priv   = re.search(r'href=["\']/privacy["\']', s, re.I) is not None
    if has_terms and has_priv:
        return "footer-ok"
    if re.search(r"</footer>", s, re.I):
        if not has_terms:
            s = re.sub(r"(</footer>)", '  <a href="/terms">Términos y Condiciones</a>\n\\1', s, flags=re.I)
        if not has_priv:
            s = re.sub(r"(</footer>)", '  <a href="/privacy">Política de Privacidad</a>\n\\1', s, flags=re.I)
        return "footer-patched"
    # no footer: insert minimal before </body>
    if re.search(r"</body>", s, re.I):
        s = re.sub(r"(</body>)",
                   '\n<footer style="margin-top:2rem;opacity:.85">'
                   '<a href="/terms">Términos y Condiciones</a> · '
                   '<a href="/privacy">Política de Privacidad</a>'
                   '</footer>\n\\1', s, flags=re.I)
        return "footer-added"
    return "footer-missing-body"

# 0) H1 duplicados: conservar el primero, quitar repetidos iguales o con el mismo texto
h1s = re.findall(r"<h1[^>]*>.*?</h1>", s, re.I|re.S)
if len(h1s) > 1:
    first = h1s[0]
    txt0  = re.sub(r"<.*?>", "", first, flags=re.S).strip().lower()
    kept = [first]
    def same_text(h):
        return re.sub(r"<.*?>","",h,flags=re.S).strip().lower()==txt0
    rest = [h for h in h1s[1:] if same_text(h)]
    for h in rest:
        s = s.replace(h, "")
    # squeeze multiple blank lines
    s = re.sub(r"\n{3,}", "\n\n", s)

# 1) Detectar/asegurar AdSense META + loader
meta_rx = re.compile(r'<meta\s+name=["\']google-adsense-account["\']\s+content=["\']([^"\']+)["\']\s*/?>', re.I)
script_rx = re.compile(r'googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=([^"&]+)', re.I)

meta_m = meta_rx.search(s)
script_m = script_rx.search(s)
detected = None

if meta_m:
    detected = meta_m.group(1).strip()
elif script_m:
    detected = script_m.group(1).strip()

client = (os.environ.get("ADSENSE_ID","") or (sys.argv[2] if len(sys.argv)>2 else "") or detected or "").strip()
if not client:
    # intenta inferir de un comentario común
    hint = re.search(r'ca-pub-[0-9]{10,}', s)
    if hint: client = hint.group(0)

if not client:
    # no abortamos: reconciliamos lo demás y avisamos
    print("[reconcile] WARN: no pude inferir ca-pub-XXXX; se mantiene el HTML tal cual en AdSense.")

# insertar/actualizar META
if client:
    if meta_m:
        s = meta_rx.sub(f'<meta name="google-adsense-account" content="{client}">', s)
    else:
        # si no hay </head>, crea uno básico
        if "</head>" not in s.lower():
            s = "<!doctype html>\n<head>\n</head>\n" + s
        once(r'google-adsense-account',
             f'<meta name="google-adsense-account" content="{client}">\n')

# insertar/actualizar SCRIPT loader
if client and not script_m:
    loader = ('<script async '
              'src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client='
              f'{client}'
              '" crossorigin="anonymous"></script>\n')
    once(r'pagead2\.googlesyndication', loader)

# 2) Asegurar bloque #p12-stats y <span class="views">
stats_id_rx = re.compile(r'id=["\']p12-stats["\']', re.I)
has_stats = stats_id_rx.search(s) is not None
if not has_stats:
    # insertar tras primer <h1> o al inicio del <body>
    block = ('<div id="p12-stats" class="p12-stats" '
             'style="margin:.75rem 0;opacity:.9;font:14px/1.4 system-ui,Segoe UI,Roboto,Arial">'
             '<span class="views">0</span> views · '
             '<span class="likes">0</span> likes · '
             '<span class="reports">0</span> reports'
             '</div>\n')
    if h1s:
        s = s.replace(h1s[0], h1s[0] + "\n" + block)
    elif re.search(r"<body[^>]*>", s, re.I):
        s = re.sub(r"(<body[^>]*>)", r"\1\n"+block, s, flags=re.I)
    else:
        s = block + s
else:
    # si existe, asegurar <span class="views">
    s = re.sub(r'(<div[^>]+id=["\']p12-stats["\'][^>]*>)(.*?)</div>',
               lambda m: (m.group(1) +
                          (m.group(2) if re.search(r'class=["\']views["\']', m.group(2), re.I)
                           else '<span class="views">0</span> views · ') +
                          '</div>'),
               s, flags=re.I|re.S)

# 3) Desduplicar #p12-stats si hubiera más de uno (renombra otros ids como -legacy y ocúltalos)
ids = re.findall(r'id=["\']p12-stats["\']', s, re.I)
if len(ids) > 1:
    first_done = False
    def repl(m):
        nonlocal first_done
        if not first_done:
            first_done = True
            return m.group(0)
        return m.group(0).replace('p12-stats','p12-stats-legacy')
    s = re.sub(r'id=["\']p12-stats["\']', repl, s, flags=re.I)
    # ocultar legacies por CSS inline
    if 'p12-stats-legacy' in s and '</head>' in s.lower():
        s = re.sub(r'(</head>)',
                   '<style>#p12-stats-legacy{display:none!important}</style>\\1', s, flags=re.I)

# 4) Footer legal
footer_state = ensure_footer_links()

# 5) Limpiezas menores
s = re.sub(r'\n{3,}', '\n\n', s)

changed = (s != orig)
if changed:
    io.open(path, "w", encoding="utf-8").write(s)

print("[reconcile] META:", "OK" if re.search(r'google-adsense-account', s, re.I) else "MISS")
print("[reconcile] LOADER:", "OK" if re.search(r'googlesyndication\.com/pagead/js/adsbygoogle', s, re.I) else "MISS")
print("[reconcile] VIEWS:", "OK" if re.search(r'id=["\']p12-stats["\'][\s\S]*class=["\']views["\']', s, re.I) else "MISS")
print("[reconcile] H1 dupes:", "CLEAN" if len(re.findall(r'<h1[^>]*>.*?</h1>', s, re.I|re.S))==1 else "CHECK")
print("[reconcile] Footer:", footer_state)
print("[reconcile] write:", "yes" if changed else "no-change")
PY

echo "[reconcile] Hecho."

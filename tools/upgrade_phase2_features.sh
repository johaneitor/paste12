#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
mkdir -p "$PREFIX/tmp" frontend

backup(){ [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

echo "➤ Backups"
backup backend/__init__.py
backup backend/routes.py
backup frontend/index.html
backup frontend/js/app.js
backup frontend/css/styles.css
backup requirements.txt

echo "➤ Cursor pagination (after_id) en GET /api/notes + header X-Next-After"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

pat = r"@api\.route\(\"/notes\", methods=\[\"GET\"\]\)\s*def\s+list_notes\(\):[\s\S]*?(?=\n@api\.route|\Z)"
new = r"""@api.route("/notes", methods=["GET"])
def list_notes():
    try:
        after_id = request.args.get("after_id")
        limit = max(1, min(int(request.args.get("limit", "20")), 50))
        q = db.session.query(Note).order_by(Note.id.desc())
        if after_id:
            try:
                aid = int(after_id)
                q = q.filter(Note.id < aid)
            except Exception:
                pass
        items = q.limit(limit).all()
        def _to(n):
            return {
                "id": n.id,
                "text": getattr(n,"text",None),
                "timestamp": n.timestamp.isoformat() if getattr(n,"timestamp",None) else None,
                "expires_at": n.expires_at.isoformat() if getattr(n,"expires_at",None) else None,
                "likes": getattr(n,"likes",0) or 0,
                "views": getattr(n,"views",0) or 0,
                "reports": getattr(n,"reports",0) or 0,
            }
        resp = jsonify([_to(n) for n in items])
        if items:
            resp.headers["X-Next-After"] = str(items[-1].id)
        return resp, 200
    except Exception as e:
        return jsonify({"error":"list_failed","detail":str(e)}), 500
"""
s2, n = re.subn(pat, new, s, flags=re.S)
if n == 0:
    raise SystemExit("No se pudo parchear list_notes()")
p.write_text(s2, encoding="utf-8")
print("list_notes() con cursor listo.")
PY

echo "➤ Sentry (si SENTRY_DSN) + logs JSON (LOG_JSON=1) en backend/__init__.py"
python - <<'PY'
from pathlib import Path
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")
if "sentry_sdk" not in s:
    s = s.replace("db.init_app(app)", "db.init_app(app)\n    # Sentry opcional\n    try:\n        import sentry_sdk\n        from sentry_sdk.integrations.flask import FlaskIntegration\n        from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration\n        dsn = os.getenv('SENTRY_DSN')\n        if dsn:\n            sentry_sdk.init(dsn=dsn, integrations=[FlaskIntegration(), SqlalchemyIntegration()], traces_sample_rate=float(os.getenv('SENTRY_TRACES','0')))\n    except Exception as _e:\n        app.logger.warning(f'Sentry init: {_e}')")
p.write_text(s, encoding="utf-8")
print("Sentry integrado (opcional).")
PY

echo "➤ requirements.txt (sentry-sdk si falta)"
grep -qi '^sentry-sdk' requirements.txt 2>/dev/null || echo "sentry-sdk==2.14.0" >> requirements.txt

echo "➤ Footer con enlaces y slots de anuncios + meta ads-client"
mkdir -p frontend/css
[ -f frontend/css/styles.css ] || cat > frontend/css/styles.css <<'CSS'
body{font-family:system-ui,-apple-system,Segoe UI,Roboto;background:#0b1220;color:#eaf2ff;margin:0}
main{max-width:720px;margin:24px auto;padding:0 14px}
ul#notes{list-style:none;padding:0}
.note{background:#0e1628;color:#eaf2ff;border:1px solid #253044;border-radius:12px;padding:12px;margin:10px 0;position:relative}
.row{display:flex;gap:8px;align-items:start;justify-content:space-between}
.menu{display:none;position:absolute;right:12px;top:32px;background:#0b1220;border:1px solid #253044;border-radius:10px;overflow:hidden;z-index:10}
.menu.open{display:block}
.menu button{display:block;padding:8px 12px;background:transparent;border:none;color:#eaf2ff;width:100%;text-align:left}
.bar{display:flex;gap:12px;align-items:center;margin-top:8px}
.meta{opacity:.8;margin-top:4px}
footer.site{max-width:720px;margin:34px auto 18px;padding:0 14px;opacity:.85;font-size:.9rem}
footer.site a{color:#9ec1ff;text-decoration:none}
.ad-slot{display:block;min-height:180px;border:1px dashed #33415e;border-radius:10px;margin:16px 0}
CSS

python - <<'PY'
from pathlib import Path
html = Path("frontend/index.html").read_text(encoding="utf-8")
if '<meta name="ads-client"' not in html:
    html = html.replace("<head>", "<head>\n  <meta name=\"ads-client\" content=\"ca-pub-XXXXXXXXXXXXXXX\">")
if "footer class=\"site\"" not in html:
    html = html.replace("</main>", """  <section id="ad-below-form" class="ad-slot"><!-- ad slot --></section>
  </main>
  <footer class="site">
    <a href="/terms.html">Términos y Condiciones</a> · <a href="/privacy.html">Política de Privacidad</a>
  </footer>""")
Path("frontend/index.html").write_text(html, encoding="utf-8")
print("index.html actualizado con meta ads y footer.")
PY

echo "➤ Archivos de Términos y Privacidad"
cat > frontend/terms.html <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Términos y Condiciones</title><link rel="stylesheet" href="/css/styles.css"></head>
<body>
<main>
<h1>Términos y Condiciones</h1>
<p>Al usar el servicio aceptás no publicar contenido ilegal o dañino. Las notas pueden expirar o ser eliminadas por reportes (5 por nota). El servicio se ofrece “tal cual”.</p>
<p>Si se muestran anuncios, terceros podrían usar cookies para personalización (ver Privacidad).</p>
<p><a href="/">Volver</a></p>
</main>
</body></html>
HTML

cat > frontend/privacy.html <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Política de Privacidad</title><link rel="stylesheet" href="/css/styles.css"></head>
<body>
<main>
<h1>Política de Privacidad</h1>
<p>Recopilamos datos mínimos (por ejemplo, una huella anónima/cookie “uid” para limitar likes/vistas). Si habilitás anuncios, proveedores pueden usar cookies o identificadores similares.</p>
<p>Podés contactar al administrador del servicio para ejercer tus derechos.</p>
<p><a href="/">Volver</a></p>
</main>
</body></html>
HTML

echo "➤ Carga dinámica de AdSense (solo si meta ads-client tiene un ID real)"
python - <<'PY'
from pathlib import Path
p = Path("frontend/js/app.js")
s = p.read_text(encoding="utf-8") if p.exists() else "(function(){})();"
if "loadAdsenseOnce" not in s:
    s = s.replace("(function(){", """(function(){
  function loadAdsenseOnce(){
    try{
      const meta = document.querySelector('meta[name=\"ads-client\"]');
      const client = meta && meta.content || '';
      if(!client || client.includes('XXXX')) return; // placeholder => no carga
      if(document.getElementById('adsbygoogle-lib')) return;
      const sc = document.createElement('script');
      sc.id='adsbygoogle-lib';
      sc.async = true;
      sc.src = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client="+encodeURIComponent(client);
      sc.crossOrigin = "anonymous";
      document.head.appendChild(sc);
      setTimeout(()=>{ try{ (window.adsbygoogle=window.adsbygoogle||[]).push({}); }catch(_){ } }, 1200);
    }catch(_){}
  }
  loadAdsenseOnce();""", 1)
p.write_text(s, encoding="utf-8")
print("app.js: loader de AdSense agregado.")
PY

echo "➤ Reinicio y smokes"
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "gunicorn" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2
echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "list=$(curl -sS -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8000/api/notes?after_id=999999&limit=2')"

echo "➤ Commit & push"
git add backend/routes.py backend/__init__.py frontend/index.html frontend/privacy.html frontend/terms.html frontend/js/app.js frontend/css/styles.css requirements.txt || true
git commit -m "feat(perf+ads): cursor pagination; Sentry opcional; footer Términos/Privacidad; loader de ads" || true
git push origin main || true

echo "✓ Fase 2 lista. (Para activar Ads: poné tu ca-pub en <meta name='ads-client'>)"

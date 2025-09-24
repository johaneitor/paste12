#!/usr/bin/env bash
set -Eeuo pipefail

# Detectar carpeta estática (frontend/public/static…)
pick_static() {
  for d in frontend public static dist build; do
    [ -d "$d" ] && { echo "$d"; return; }
  done
  echo "public"
}
STATIC_DIR="$(pick_static)"
mkdir -p "$STATIC_DIR/js" "$STATIC_DIR/css"

backup(){ [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

echo "→ usando estático: $STATIC_DIR"
backup "$STATIC_DIR/index.html"
backup "$STATIC_DIR/js/app.js"
backup "$STATIC_DIR/css/styles.css"

############################################
# 1) CSS: alto contraste + utilidades
############################################
cat >> "$STATIC_DIR/css/styles.css" <<'CSS'

/* --- Overrides accesibles (alto contraste) --- */
:root{
  --bg:#0f141d;         /* fondo app */
  --card:#ffffff;       /* tarjeta nota */
  --text:#0b1220;       /* texto sobre tarjeta clara */
  --muted:#4a617b;      /* meta en tarjeta */
  --link:#9fd1ff;
}
html,body{background:var(--bg);}
a{color:var(--link);}
[hidden], .is-hidden{display:none !important;}

.note{background:var(--card); color:var(--text);}
.note .txt{color:var(--text);}
.note .meta{color:var(--muted);}
.note .bar .like{background:#ffe5ea;border:1px solid #ffc2cf;color:#8a1030}

.topbar{background:#0e1420;color:#eaf2ff;}
.topbar a{color:#cfe3ff}

.footer{
  color:#9fb3cc; font-size:13px; text-align:center;
  border-top:1px solid #273249; padding:12px 16px; margin-top:16px;
}
.footer a{color:#9fd1ff; text-decoration:none; margin:0 8px}

/* Consent reusa esquema oscuro */
.consent{background:#0f141d;color:#eaf2ff}
.consent a{color:#9fd1ff}
.consent button{background:#1c2431;border:1px solid #273249;color:#dfeaff}
CSS

############################################
# 2) index.html: footer + consent fiable
############################################
cat > "$STATIC_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>paste12</title>
  <link rel="stylesheet" href="/css/styles.css">
  <!-- Ads (sólo cambia tu client y slot cuando tengas el ID) -->
  <link rel="preconnect" href="https://pagead2.googlesyndication.com">
  <link rel="preconnect" href="https://googleads.g.doubleclick.net">
  <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-XXXXXXXXXXXXXXXX" crossorigin="anonymous"></script>
</head>
<body>
  <header class="topbar">
    <h1 style="margin:0">Notas</h1>
  </header>

  <!-- Bloque de anuncio responsivo -->
  <section class="adwrap" style="max-width:860px;margin:12px auto">
    <ins class="adsbygoogle"
         style="display:block"
         data-ad-client="ca-pub-XXXXXXXXXXXXXXXX"
         data-ad-slot="1234567890"
         data-ad-format="auto"
         data-full-width-responsive="true"></ins>
    <script>(adsbygoogle = window.adsbygoogle || []).push({});</script>
  </section>

  <main class="container">
    <form id="noteForm" style="display:grid;gap:8px;margin-top:8px">
      <textarea name="text" placeholder="Escribe tu nota…" required></textarea>
      <input type="number" id="hours" name="hours" value="24" min="1" max="720">
      <button type="submit">Publicar</button>
      <span id="status"></span>
    </form>
    <ul id="notes" style="list-style:none;padding:0;margin:16px 0"></ul>
  </main>

  <footer class="footer">
    <a href="/terms.html">Términos</a> ·
    <a href="/privacy.html">Privacidad</a>
  </footer>

  <!-- Consentimiento -->
  <div id="consent" class="consent is-hidden" aria-hidden="true"
       style="position:fixed;left:0;right:0;bottom:0;padding:10px 14px;display:flex;gap:10px;align-items:center;z-index:9998">
    Usamos cookies/localStorage (por ejemplo, para contar vistas y mostrar anuncios).
    Al continuar aceptás nuestros <a href="/terms.html">Términos</a> y
    <a href="/privacy.html">Política de Privacidad</a>.
    <button id="consentAccept" style="margin-left:auto">Aceptar</button>
  </div>

  <script src="/js/app.js?v=5"></script>
  <script>
  // Banner de consentimiento fiable
  document.addEventListener('DOMContentLoaded', function(){
    try{
      var c = document.getElementById('consent');
      var b = document.getElementById('consentAccept');
      var has = (localStorage.getItem('consent') === '1');
      if (has) { c.classList.add('is-hidden'); c.setAttribute('hidden',''); c.setAttribute('aria-hidden','true'); }
      else     { c.classList.remove('is-hidden'); c.removeAttribute('hidden'); c.setAttribute('aria-hidden','false'); }
      b && b.addEventListener('click', function(){
        try{ localStorage.setItem('consent','1'); }catch(e){}
        c.classList.add('is-hidden'); c.setAttribute('hidden',''); c.setAttribute('aria-hidden','true');
      });
    }catch(e){}
  });
  </script>
</body>
</html>
HTML

############################################
# 3) JS: asegurar nota legible y mantener funciones
#    (no tocamos tus endpoints; sólo conservamos versión)
############################################
# Si ya existe app.js con nuestras funciones, no lo sobreescribimos.
# Sólo forzamos el cache-bust con ?v=5 en index.html (arriba).

############################################
# 4) Smokes rápidos (local)
############################################
SERVER="http://127.0.0.1:8000"
echo "→ Smokes:"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health" || true
curl -sS -o /dev/null -w "list=%{http_code}\n"   "$SERVER/api/notes" || true

############################################
# 5) Commit
############################################
git add "$STATIC_DIR/index.html" "$STATIC_DIR/css/styles.css"
git commit -m "fix(ui): alto contraste en notas; footer con Términos/Privacidad; consentimiento fiable; preconnect + cache-busting" || true
echo "✓ Listo. Sube con: git push origin main"

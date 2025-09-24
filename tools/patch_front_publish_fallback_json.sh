#!/usr/bin/env bash
set -euo pipefail

HTML="${1:-frontend/index.html}"
[[ -f "$HTML" ]] || HTML="index.html"
[[ -f "$HTML" ]] || { echo "No encuentro $HTML"; exit 1; }

cp -a "$HTML" "$HTML.bak.$(date +%s)"

# Inyectamos un <script id="shim-publish-fallback"> antes de </body> si no existe
if grep -q 'id="shim-publish-fallback"' "$HTML"; then
  echo "→ shim publish ya presente, no hago nada"
  exit 0
fi

awk '
  /<\/body>/ && !done {
    print "<script id=\"shim-publish-fallback\">"
    print "(function(){"
    print "  const _origFetch = window.fetch;"
    print "  async function parseMaybeJSON(res){"
    print "    try { return await res.clone().json(); } catch(_){"
    print "      try {"
    print "        const t = await res.clone().text();"
    print "        const m = /\\bid\\s*=\\s*(\\d+)/i.exec(t);"
    print "        if(m) return { id: parseInt(m[1],10) };"
    print "      } catch(__) {}"
    print "      return null;"
    print "    }"
    print "  }"
    print "  // Hook suave: solo para POST /api/notes"
    print "  window.fetch = async function(input, init){"
    print "    const url = (typeof input===\"string\"?input:(input&&input.url)||\"\");"
    print "    const isNotesPost = /\\/api\\/notes\\b/.test(url) && (!init|| (init.method||\"POST\").toUpperCase()===\"POST\");"
    print "    const res = await _origFetch(input, init);"
    print "    if(isNotesPost && res && res.ok){"
    print "      const j = await parseMaybeJSON(res);"
    print "      if(j && !res._shim_json){"
    print "        // Creamos un Response JSON para el consumidor original"
    print "        const blob = new Blob([JSON.stringify(j)], {type: \"application/json\"});"
    print "        const patched = new Response(blob, res);"
    print "        // marcamos para evitar doble parsing en cadenas posteriores"
    print "        patched._shim_json = true;"
    print "        return patched;"
    print "      }"
    print "    }"
    print "    return res;"
    print "  };"
    print "})();"
    print "</script>"
    print
    done=1
  }
  { print }
' "$HTML" > "$HTML.tmp"

mv "$HTML.tmp" "$HTML"
echo "✓ shim de publish fallback inyectado en $HTML"

#!/usr/bin/env bash
set -euo pipefail
mkdir -p backend/static

seed_if_empty(){ # $1 ruta, $2 título
  local f="$1" ; local title="$2"
  if [[ ! -s "$f" ]]; then
    cat > "$f" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>${title} — paste12</title>
<body>
<h1>${title}</h1>
<p>Este contenido por defecto se mostrará hasta que subas tu versión definitiva.</p>
<p>Commit: $(git rev-parse HEAD)</p>
</body>
HTML
    echo "Seeded $f"
  else
    echo "OK $f (existe con contenido)"
  fi
}
seed_if_empty "backend/static/terms.html" "Términos y condiciones"
seed_if_empty "backend/static/privacy.html" "Política de Privacidad"

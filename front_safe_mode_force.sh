#!/usr/bin/env bash
set -Eeuo pipefail
ts=$(date +%s)
f="frontend/index.html"
bak="$f.bak.$ts"
mkdir -p frontend
cp -a "$f" "$bak" 2>/dev/null || true

cat > "$f" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>paste12</title>
  <link rel="preload" href="/css/styles.css" as="style">
  <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
  <main>
    <h1 class="sr-only">Notas recientes</h1>
    <div id="feed"></div>
  </main>
  <script src="/js/app.js?v=__TS__" defer></script>
</body>
</html>
HTML

sed -i "s/__TS__/$ts/g" "$f"

echo "Backup guardado en: $bak"
echo "Scripts activos ahora:"
grep -n '<script' "$f" || true

git add "$f"
git commit -m "front(safe-mode): minimal index (solo app.js) v=$ts" || true
git push -u origin main

echo
echo "✅ Listo. Tras el redeploy, abre: https://paste12-rmsk.onrender.com/?v=$ts"

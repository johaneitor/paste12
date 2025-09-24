#!/usr/bin/env bash
set -euo pipefail
f="wsgiapp/__init__.py"
[ -f "$f" ] || { echo "no existe $f"; exit 2; }

echo "== GREP rutas/guardas likes =="
nl -ba "$f" | grep -nE 'class +_(LikesGuard|LikesWrapper)|def +_handle_like|/api/notes/.+?/like|/api/like/'
echo "== ¿wrapper aplicado a app? =="
grep -nE 'app *= *_Likes(Wrap|Guard)\(app\)' "$f" || echo "(aviso) no se ve app = _Likes*(app)"

echo "== ¿tabla like_log y unique index? =="
grep -nE 'CREATE TABLE IF NOT EXISTS like_log|uq_like_note_fp|ON CONFLICT' "$f" || echo "(aviso) no se ven DDL/índices de like_log en $f"

echo "== Firma de _handle_like =="
grep -nE 'def +_handle_like\(self, environ, start_response, note_id\)' "$f" || echo "(aviso) _handle_like no localizado)"

echo "== Path matching en __call__ =="
nl -ba "$f" | sed -n '1,999p' | awk '
  BEGIN{in_call=0}
  /def __call__\(self, environ, start_response\):/{in_call=1}
  in_call==1{print}
  in_call==1 && /^ {4,}def /{exit}
'

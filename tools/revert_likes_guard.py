#!/usr/bin/env python3
import pathlib, re
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
s = re.sub(r'\n# === APPEND-ONLY: Likes 1×persona.*?class _LikesGuard:.*?^(\s*def |\Z)', '\n\\1', s, flags=re.S|re.M)
s = re.sub(r'\n# --- envolver con guard de likes 1×persona.*?app = _LikesGuard\(app\).*?pass\s*\n', '\n', s, flags=re.S)
P.write_text(s, encoding="utf-8")
print("reverted: _LikesGuard eliminado")

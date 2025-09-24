#!/usr/bin/env bash
set -euo pipefail
shopt -s globstar nullglob

FOUND_FILE=""
for F in backend/**/*.py backend/*.py; do
  if grep -qE 'class\s+ViewLog\s*\(' "$F"; then
    FOUND_FILE="$F"
    break
  fi
done

if [[ -z "${FOUND_FILE:-}" ]]; then
  echo "❌ No pude encontrar 'class ViewLog' en backend/*.py"
  exit 1
fi

echo "→ Parcheando $FOUND_FILE"

python - "$FOUND_FILE" <<'PY'
import re, sys
from pathlib import Path

fname = Path(sys.argv[1])
code = fname.read_text(encoding="utf-8")

# === 1) asegurar "import sqlalchemy as sa" sin romper from __future__ ni docstring ===
lines = code.splitlines()
has_sa = any(re.match(r'\s*import\s+sqlalchemy\s+as\s+sa\b', L) for L in lines)
if not has_sa:
    insert_at = 0
    # after all __future__ imports
    while insert_at < len(lines) and re.match(r'\s*from\s+__future__\s+import\b', lines[insert_at]):
        insert_at += 1
    # skip module docstring if present
    if insert_at < len(lines) and re.match(r'\s*(?:"""|\'\'\')', (lines[insert_at] or "")):
        q = lines[insert_at].strip()[:3]
        insert_at += 1
        while insert_at < len(lines) and q not in lines[insert_at]:
            insert_at += 1
        if insert_at < len(lines):
            insert_at += 1
    lines.insert(insert_at, "import sqlalchemy as sa")
    code = "\n".join(lines)

# === 2) localizar cuerpo de class ViewLog y añadir .day si falta ===
m_cls = re.search(r'(class\s+ViewLog\s*\(.*?\)\s*:\s*)(.+?)(?:\nclass\s|\Z)', code, re.S)
if not m_cls:
    print("WARN: no se encontró el cuerpo de ViewLog", file=sys.stderr)
else:
    head, body = m_cls.group(1), m_cls.group(2)
    has_day = re.search(r'^\s*day\s*=\s*db\.Column\(', body, re.M) is not None
    if not has_day:
        # insertar tras view_date=... si existe, si no al inicio del cuerpo
        ins = "    day = db.Column(db.Date, nullable=False, default=sa.func.current_date())\n"
        m_vd = re.search(r'^\s*view_date\s*=\s*db\.Column\([^\n]*\)\s*$', body, re.M)
        start_body = m_cls.start(2)
        if m_vd:
            pos = start_body + m_vd.end()
            code = code[:pos] + "\n" + ins + code[pos:]
        else:
            code = code[:start_body] + "\n" + ins + code[start_body:]
        print("OK: añadido ViewLog.day")

fname.write_text(code, encoding="utf-8")
PY

git add "$FOUND_FILE" || true
git commit -m "fix(models): ensure ViewLog.day (Date, not null, default current_date())" || true
git push origin main
echo "✅ Push hecho. Cuando el deploy esté activo, probamos /view."

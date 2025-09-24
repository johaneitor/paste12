#!/usr/bin/env bash
set -euo pipefail
# Usa el mismo URI que wsgiapp (o cámbialo si querés otro archivo)
export SQLALCHEMY_DATABASE_URI="${SQLALCHEMY_DATABASE_URI:-sqlite:///data.db}"

python - <<'PY'
from sqlalchemy import inspect
from wsgiapp import app
from backend import db
import backend.models  # asegura que las tablas estén registradas

with app.app_context():
    insp = inspect(db.engine)
    have = set(insp.get_table_names())
    print("Antes:", sorted(have))
    db.create_all()
    have = set(insp.get_table_names())
    print("Después:", sorted(have))
PY

echo "✓ DB inicializada en ${SQLALCHEMY_DATABASE_URI}"

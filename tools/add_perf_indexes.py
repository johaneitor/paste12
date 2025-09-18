#!/usr/bin/env python3
import os, sys
SQL = """
CREATE INDEX IF NOT EXISTS ix_note_ts_id_desc ON note (timestamp DESC, id DESC);
CREATE INDEX IF NOT EXISTS ix_note_id ON note (id);
CREATE INDEX IF NOT EXISTS ix_like_log_note_fp ON like_log(note_id, fingerprint);
"""
def via_sqlalchemy():
    from sqlalchemy import create_engine, text
    url=os.getenv("DATABASE_URL") or os.getenv("DB_URL")
    if not url:
        # intenta resolver usando el entrypoint del proyecto
        import importlib
        mod=importlib.import_module("wsgiapp.__init__")
        eng=mod._engine()  # type: ignore
    else:
        eng=create_engine(url)
    with eng.begin() as cx:
        for stmt in [s.strip() for s in SQL.strip().split(";") if s.strip()]:
            cx.execute(text(stmt))
    print("✓ índices aplicados")
if __name__=="__main__":
    via_sqlalchemy()

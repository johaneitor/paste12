import os, sys
from importlib import import_module

# Candidatos (el primero que exista se usa)
CANDIDATES = [
    "app:app",          # app.py con app = Flask(...)
    "run:app",          # run.py con app = ...
    "render_entry:app", # si existiera
    "entry_main:app",   # si existiera
]

_last_err = None
app = None

def _try_with(spec: str):
    os.environ["APP_MODULE"] = spec
    # Reimport limpio del shim para respetar APP_MODULE
    if "patched_app" in sys.modules:
        del sys.modules["patched_app"]
    pa = import_module("patched_app")
    return getattr(pa, "app")

# --- Bootstrap DB (solo Postgres, idempotente) ---
try:
    from sqlalchemy import create_engine, text
    url = os.environ.get("DATABASE_URL", "")
    if url.startswith("postgres"):
        eng = create_engine(url, pool_pre_ping=True)
        with eng.begin() as cx:
            cx.execute(text("""
                CREATE TABLE IF NOT EXISTS note(
                    id SERIAL PRIMARY KEY,
                    title TEXT,
                    url TEXT,
                    summary TEXT,
                    content TEXT,
                    timestamp TIMESTAMPTZ DEFAULT NOW(),
                    likes INT DEFAULT 0,
                    views INT DEFAULT 0,
                    reports INT DEFAULT 0,
                    author_fp VARCHAR(64)
                )
            """))
            cx.execute(text("ALTER TABLE note ADD COLUMN IF NOT EXISTS author_fp VARCHAR(64)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_timestamp ON note (timestamp DESC, id DESC)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_likes ON note (likes)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_views ON note (views)"))
            cx.execute(text("CREATE INDEX IF NOT EXISTS idx_note_reports ON note (reports)"))
except Exception as e:
    print(f"[wsgiapp] Bootstrap DB omitido: {e}")

# --- Resolver app probando candidatos ---
for spec in CANDIDATES:
    try:
        app = _try_with(spec)
        print(f"[wsgiapp] APP_MODULE -> {spec}")
        break
    except Exception as e:
        _last_err = e

if app is None:
    raise RuntimeError(f"No pude resolver APP_MODULE (probados {CANDIDATES}). Último error: {_last_err!r}")

# --- /api/deploy-stamp (si es Flask) ---
try:
    from flask import Flask, jsonify
    if isinstance(app, Flask):
        _commit = os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or ""
        _stamp  = os.environ.get("DEPLOY_STAMP") or ""
        @app.get("/api/deploy-stamp")
        def _deploy_stamp():
            return jsonify(ok=True, commit=_commit, stamp=_stamp), 200
except Exception as e:
    print(f"[wsgiapp] deploy-stamp omitido: {e}")

#!/usr/bin/env python3
import pathlib, sys

P = pathlib.Path("wsgiapp/__init__.py")
src = P.read_text(encoding="utf-8", errors="ignore")

if "P12_DIAG_MW_V1" in src:
    print("Ya estaba aplicado (P12_DIAG_MW_V1).")
    sys.exit(0)

APPEND = r"""
# === P12_DIAG_MW_V1: diag/import + deploy-stamp middleware (append-only, idempotente) ===
try:
    import os, json, datetime, re
    _inner_app = application  # conserva tu app original

    def _mask_db_url(u):
        try:
            return re.sub(r'://[^@]*@', '://****:****@', u or "")
        except Exception:
            return u or ""

    def _json_bytes(obj):
        return json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")

    def _diag_app(environ, start_response):
        path = (environ.get("PATH_INFO") or "/")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        # /api/deploy-stamp — pequeño JSON con commit y fecha de deploy
        if path == "/api/deploy-stamp":
            stamp = {
                "ok": True,
                "deploy": {
                    "commit": os.getenv("RENDER_GIT_COMMIT") or os.getenv("COMMIT_SHA") or os.getenv("SOURCE_VERSION") or "",
                    "date": os.getenv("RENDER_GIT_COMMIT_TIMESTAMP") or datetime.datetime.utcnow().isoformat()+"Z",
                }
            }
            body = _json_bytes(stamp)
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                      ("Cache-Control","no-store"), ("Content-Length", str(len(body)))])
            return [body]

        # /diag/import — snapshot JSON (habilitado por P12_DIAG=1; por defecto ON)
        if path == "/diag/import":
            allow = (os.getenv("P12_DIAG","1").lower() in ("1","true","yes","on"))
            if method == "OPTIONS":
                start_response("204 No Content", [("Content-Length","0"), ("Access-Control-Max-Age","86400")])
                return [b""]
            if not allow:
                # responde limpio, pero sin cuerpo (cierre explícito)
                start_response("204 No Content", [("Content-Length","0"), ("Cache-Control","no-store")])
                return [b""]

            keys = [
                "RENDER","RENDER_SERVICE_ID","RENDER_INSTANCE_ID","RENDER_EXTERNAL_URL",
                "RENDER_GIT_COMMIT","RENDER_GIT_COMMIT_TIMESTAMP",
                "PYTHON_VERSION","DATABASE_URL","SOURCE_VERSION","GIT_COMMIT","TZ"
            ]
            env = {}
            for k in keys:
                v = os.getenv(k, "")
                if k == "DATABASE_URL" and v:
                    v = _mask_db_url(v)
                env[k] = v

            payload = {
                "ok": True,
                "deploy": {
                    "commit": env.get("RENDER_GIT_COMMIT") or env.get("SOURCE_VERSION") or env.get("GIT_COMMIT") or "",
                    "date": env.get("RENDER_GIT_COMMIT_TIMESTAMP",""),
                },
                "env": env
            }
            body = _json_bytes(payload)
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                      ("Cache-Control","no-store"), ("Content-Length", str(len(body)))])
            return [body]

        # resto: pasa a tu app original
        return _inner_app(environ, start_response)

    application = _diag_app
except Exception:
    # En caso de error, no rompemos la app
    pass
# === /P12_DIAG_MW_V1 ===
"""

P.write_text(src.rstrip()+"\n"+APPEND, encoding="utf-8")
print("OK: middleware de diagnóstico anexado (P12_DIAG_MW_V1).")

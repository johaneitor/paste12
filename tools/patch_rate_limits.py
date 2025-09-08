#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = False

BLOCK = r'''
# === Outermost: RateLimits (idempotent, append-only) ===
try:
    _RATE_LIMITS_WRAPPED
except NameError:
    import io, time, json as _json_mod
    from datetime import timedelta
    try:
        from sqlalchemy import text as _text
    except Exception:
        _text = None

    def _rl_fingerprint(environ):
        try:
            # preferir helper interno si existe
            return _fingerprint(environ)  # type: ignore[name-defined]
        except Exception:
            ua = environ.get("HTTP_USER_AGENT","")[:256]
            ip = (environ.get("HTTP_CF_CONNECTING_IP") or
                  environ.get("HTTP_X_FORWARDED_FOR","").split(",")[0].strip() or
                  environ.get("REMOTE_ADDR","") or "")
            fp = f"{ip}|{ua}"
            try:
                import hashlib; return hashlib.sha1(fp.encode("utf-8")).hexdigest()[:16]
            except Exception:
                return fp[:32] or "anon"

    class _RateLimitWrapper:
        _ddl_done = False
        def __init__(self, inner):
            self.inner = inner

        def _ensure_table(self):
            if self._ddl_done or _text is None:
                return
            try:
                with _engine().begin() as cx:  # type: ignore[name-defined]
                    cx.execute(_text("""
CREATE TABLE IF NOT EXISTS rate_log(
  id BIGSERIAL PRIMARY KEY,
  fp VARCHAR(64) NOT NULL,
  user_id BIGINT NULL,
  action VARCHAR(32) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)"""))
                    cx.execute(_text("""CREATE INDEX IF NOT EXISTS ix_rate_log_fp_act_created
ON rate_log(fp, action, created_at DESC)"""))
            except Exception:
                pass
            self._ddl_done = True

        def _limited(self, fp, user_id, action, burst_n, burst_secs, quota_n, quota_secs):
            if _text is None:
                return False, 0
            # Devolver True si excede: primero ventana corta (burst), luego cuota larga
            try:
                with _engine().begin() as cx:  # type: ignore[name-defined]
                    q = cx.execute(_text("""
SELECT
  SUM(CASE WHEN created_at > NOW() - INTERVAL :b_secs THEN 1 ELSE 0 END) AS burst_cnt,
  SUM(CASE WHEN created_at > NOW() - INTERVAL :q_secs THEN 1 ELSE 0 END) AS quota_cnt
FROM rate_log
WHERE fp=:fp AND action=:act
"""), {
    "b_secs": f"{int(burst_secs)} seconds",
    "q_secs": f"{int(quota_secs)} seconds",
    "fp": fp, "act": action
}).first()
                burst_cnt = int(q[0] or 0)
                quota_cnt = int(q[1] or 0)
                if burst_cnt >= burst_n:
                    return True, int(burst_secs)
                if quota_cnt >= quota_n:
                    return True, int(quota_secs)
            except Exception:
                return False, 0
            return False, 0

        def _log(self, fp, user_id, action):
            if _text is None: return
            try:
                with _engine().begin() as cx:  # type: ignore[name-defined]
                    cx.execute(_text("INSERT INTO rate_log(fp,user_id,action) VALUES(:fp,:uid,:act)"),
                               {"fp": fp, "uid": user_id, "act": action})
            except Exception:
                pass

        def _json429(self, start_response, action, retry_after):
            body = _json_mod.dumps({"ok": False, "error": "rate_limited",
                                    "action": action, "retry_after": retry_after}).encode("utf-8")
            hdrs = [("Content-Type","application/json; charset=utf-8"),
                    ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                    ("Retry-After", str(int(retry_after))),
                    ("Content-Length", str(len(body)))]
            start_response("429 Too Many Requests", hdrs)
            return [body]

        def __call__(self, environ, start_response):
            try:
                self._ensure_table()
                path = (environ.get("PATH_INFO") or "")
                method = (environ.get("REQUEST_METHOD") or "GET").upper()
                fp = _rl_fingerprint(environ)
                user_id = None  # placeholder (cuando exista auth)
                # Regla fuerte: POST /api/notes => 1 cada 5 minutos
                if method == "POST" and path.rstrip("/") == "/api/notes":
                    limited, retry = self._limited(fp, user_id, "post", burst_n=1, burst_secs=300,
                                                   quota_n=1, quota_secs=300)
                    if limited:
                        return self._json429(start_response, "post", retry)
                    # log intentos (éxito o no) para frenar spam
                    self._log(fp, user_id, "post")
                # Reglas: like/report/view bursts/cuotas
                elif method == "POST" and path.startswith("/api/notes/") and path.endswith(("/like","/report","/view")):
                    if path.endswith("/like"):   act="like"
                    elif path.endswith("/report"):act="report"
                    else:                        act="view"
                    limited, retry = self._limited(fp, user_id, act, burst_n=5, burst_secs=10,
                                                   quota_n=60, quota_secs=3600)
                    if limited:
                        return self._json429(start_response, act, retry)
                    self._log(fp, user_id, act)
            except Exception:
                pass
            return self.inner(environ, start_response)

    try:
        app = _RateLimitWrapper(app)  # type: ignore[name-defined]
    except Exception:
        pass
    _RATE_LIMITS_WRAPPED = True
'''
if "class _RateLimitWrapper" not in s:
    if not s.endswith("\n"): s += "\n"
    s += "\n" + BLOCK.strip() + "\n"
    changed = True

if changed:
    bak = W.with_suffix(".py.patch_rate_limits.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: rate-limits (post/like/report/view) | backup=", bak.name)

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")

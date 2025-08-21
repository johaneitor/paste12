import os, hashlib, datetime, traceback
from sqlalchemy import event
from flask import request, has_request_context

def _log(msg):
    try:
        with open("/tmp/author_fp_hook.log","a") as f:
            ts = datetime.datetime.now().isoformat(timespec="seconds")
            f.write(f"[{ts}] %s\n" % msg)
    except Exception:
        pass

Note = None
_errs = []
for modname in ("backend.models", "backend.models.note"):
    try:
        mod = __import__(modname, fromlist=["*"])
        cand = getattr(mod, "Note", None)
        if cand is not None:
            Note = cand
            break
    except Exception as e:
        _errs.append(f"{modname}: {e!r}")

if Note is None:
    _log("ERROR importando Note: " + " | ".join(_errs))
else:
    _log("OK import Note: " + repr(Note))

def _fp() -> str:
    if not has_request_context():
        return "noctx"
    ip = (request.headers.get("X-Forwarded-For", "")
          or request.headers.get("CF-Connecting-IP", "")
          or (request.remote_addr or ""))
    ua = request.headers.get("User-Agent", "")
    salt = os.environ.get("FP_SALT", "")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

if Note is not None:
    has_attr = hasattr(Note, "author_fp")
    _log("Note tiene atributo author_fp: %s" % has_attr)
    @event.listens_for(Note, "before_insert")
    def note_before_insert(mapper, connection, target):
        try:
            if not getattr(target, "author_fp", None):
                target.author_fp = _fp()
                _log("Set author_fp en before_insert")
            else:
                _log("author_fp ya venía seteado")
        except Exception as ex:
            _log("ERROR before_insert: " + repr(ex))
            _log(traceback.format_exc())

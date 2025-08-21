# Registra hooks para modelos (se importa por efectos secundarios)
import os, hashlib
from sqlalchemy import event
from flask import request, has_request_context

# Import flexible del modelo Note
try:
    from backend.models import Note  # type: ignore
except Exception:
    try:
        from backend.models.note import Note  # type: ignore
    except Exception as e:
        raise RuntimeError("No pude importar Note desde backend.models ni backend.models.note") from e

def _fp() -> str:
    if not has_request_context():
        return "noctx"
    ip = (
        request.headers.get("X-Forwarded-For", "")
        or request.headers.get("CF-Connecting-IP", "")
        or (request.remote_addr or "")
    )
    ua = request.headers.get("User-Agent", "")
    salt = os.environ.get("FP_SALT", "")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

@event.listens_for(Note, "before_insert")
def note_before_insert(mapper, connection, target):
    # Rellena author_fp si viene vacío
    if not getattr(target, "author_fp", None):
        try:
            target.author_fp = _fp()
        except Exception:
            # Fallback duro si no hay request-context
            target.author_fp = "noctx"

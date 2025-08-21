from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
import sqlite3, os

# Ajusta si tu DB vive en otra ruta:
DB_PATH = os.getenv("PASTE12_DB", "app.db")
REPORT_THRESHOLD = 5

router = APIRouter(prefix="/api/reports", tags=["reports"])

class ReportIn(BaseModel):
    content_id: str = Field(..., min_length=1)
    reason: str | None = None
    reporter_id: str | None = None

def get_conn():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    # PRAGMAs seguros para rendimiento
    pragmas = [
        "PRAGMA journal_mode=WAL;",
        "PRAGMA synchronous=NORMAL;",
        "PRAGMA temp_store=MEMORY;",
        "PRAGMA busy_timeout=5000;",
        "PRAGMA foreign_keys=ON;"
    ]
    for p in pragmas:
        try:
            conn.execute(p)
        except Exception:
            pass
    return conn

@router.post("/")
def create_report(payload: ReportIn, request: Request):
    client = request.headers.get("x-forwarded-for") or (request.client.host if request.client else "anon")
    reporter = payload.reporter_id or client
    conn = get_conn()
    try:
        conn.execute(
            "INSERT INTO reports(content_id, reporter_id, reason) VALUES(?,?,?)",
            (payload.content_id, reporter, payload.reason),
        )
        conn.commit()
    except Exception:
        conn.close()
        raise HTTPException(status_code=409, detail="Reporte duplicado del mismo usuario")

    cur = conn.execute("SELECT COUNT(*) AS c FROM reports WHERE content_id=?", (payload.content_id,))
    count = int(cur.fetchone()[0])

    if count >= REPORT_THRESHOLD:
        conn.execute(
            "INSERT OR IGNORE INTO flagged_content(content_id) VALUES(?)",
            (payload.content_id,)
        )
        # Ejemplo: si tienes tabla posts, descomenta:
        # conn.execute("UPDATE posts SET status='hidden' WHERE id=?", (payload.content_id,))
        conn.commit()
    conn.close()
    return {"ok": True, "count": count}

@router.get("/{content_id}")
def get_report_count(content_id: str):
    conn = get_conn()
    cur = conn.execute("SELECT COUNT(*) AS c FROM reports WHERE content_id=?", (content_id,))
    c = int(cur.fetchone()[0])
    conn.close()
    return {"content_id": content_id, "count": c}

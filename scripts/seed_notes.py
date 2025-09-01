import json, os, time
from datetime import datetime
from sqlalchemy import create_engine, text

dburl = os.environ.get("DATABASE_URL", "sqlite:///app.db")
eng = create_engine(dburl, pool_pre_ping=True)

# intenta cargar ./notes.json si existe; sino mete 3 notas de ejemplo
payload = []
if os.path.isfile("notes.json"):
    try:
        payload = json.load(open("notes.json","r",encoding="utf-8"))
        if isinstance(payload, dict): payload = payload.get("notes", [])
    except Exception:
        payload = []
if not payload:
    payload = [
        {"title":"Nota demo 1","url":"https://example.com/1","summary":"Demo 1"},
        {"title":"Nota demo 2","url":"https://example.com/2","summary":"Demo 2"},
        {"title":"Nota demo 3","url":"https://example.com/3","summary":"Demo 3"},
    ]

with eng.begin() as cx:
    for n in payload:
        cx.execute(text("""
            INSERT INTO note(title,url,summary,content,timestamp,likes,views,reports,author_fp)
            VALUES (:title,:url,:summary,:content,:ts,0,0,0,:fp)
        """), {
            "title": n.get("title","(sin título)"),
            "url": n.get("url"),
            "summary": n.get("summary"),
            "content": n.get("content"),
            "ts": datetime.utcnow(),
            "fp": None
        })
print(f"✔ insertadas {len(payload)} notas")

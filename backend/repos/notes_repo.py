from backend.models import db, Note

def create_note(text: str, now, expires_at, author_fp: str) -> Note:
    n = Note(text=text, timestamp=now, expires_at=expires_at, author_fp=author_fp)
    db.session.add(n)
    db.session.commit()
    return n

def list_notes(page: int, per_page: int):
    return (Note.query
            .order_by(Note.timestamp.desc())
            .limit(per_page)
            .offset((page - 1) * per_page)
            .all())

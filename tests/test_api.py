import pytest
import sys, os
from datetime import datetime, timedelta
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from backend import create_app, db
from backend.models import Note
from flask import json

@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"
    with app.app_context():
        db.create_all()
    return app.test_client()

def test_create_and_get_notes(client):
    r = client.post("/api/notes", json={"text": "hola mundo"})
    assert r.status_code == 201
    r = client.get("/api/notes")
    assert r.status_code == 200
    data = r.get_json()
    assert isinstance(data, list)
    assert any("hola mundo" in n["text"] for n in data)

def test_expired_note_hidden_from_active_feed(client):
    create = client.post("/api/notes", json={"text": "voy a expirar", "hours": 1})
    assert create.status_code == 201
    note_id = create.get_json()["id"]

    with client.application.app_context():
        note = Note.query.get(note_id)
        note.expires_at = datetime.utcnow() - timedelta(hours=1)
        db.session.commit()

    feed = client.get("/api/notes?wrap=1&active_only=1")
    assert feed.status_code == 200
    items = feed.get_json().get("items") if isinstance(feed.get_json(), dict) else feed.get_json()
    ids = [n["id"] for n in items]
    assert note_id not in ids

    detail = client.get(f"/api/notes/{note_id}")
    assert detail.status_code == 200
    assert detail.get_json()["id"] == note_id

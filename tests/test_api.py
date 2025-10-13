import pytest
import sys, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from backend import create_app, db
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

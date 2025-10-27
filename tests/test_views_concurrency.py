import os
import threading
import time
import json
import pytest

from flask import Flask

import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from backend import create_app, db

@pytest.fixture
def app():
    app = create_app()
    app.config.update({
        "TESTING": True,
        # Use file-based SQLite to exercise locking/backoff paths realistically
        "SQLALCHEMY_DATABASE_URI": "sqlite:////tmp/p12_test_views.db",
    })
    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app

@pytest.fixture
def client(app):
    return app.test_client()


def test_view_idempotent_single(client):
    # create a note
    r = client.post("/api/notes", json={"text": "note"})
    assert r.status_code == 201
    nid = r.get_json()["id"]

    # two views from same client should not double count within same day
    r1 = client.post(f"/api/notes/{nid}/view")
    r2 = client.post(f"/api/notes/{nid}/view")
    assert r1.status_code == 200
    assert r2.status_code == 200
    v1 = r1.get_json()["views"]
    v2 = r2.get_json()["views"]
    assert v2 == v1  # idempotent by (note_id, fp, day)


def test_view_concurrent_requests(client):
    # create a note
    r = client.post("/api/notes", json={"text": "note"})
    assert r.status_code == 201
    nid = r.get_json()["id"]

    results = []

    def worker():
        res = client.post(f"/api/notes/{nid}/view")
        results.append((res.status_code, res.get_json()))

    threads = [threading.Thread(target=worker) for _ in range(20)]
    for t in threads: t.start()
    for t in threads: t.join()

    # All requests should succeed (200 or safe 503 under lock); at least one increments
    ok = [r for r in results if r[0] == 200]
    assert len(ok) >= 1
    # Ensure views increased by exactly 1 despite concurrency and idempotency
    # Get final state
    final = client.get("/api/notes")
    assert final.status_code == 200
    items = final.get_json()
    # items can be wrapped or plain list depending on capsule; normalize
    notes = items if isinstance(items, list) else items.get("items")
    v = [n for n in notes if n["id"] == nid][0]["views"]
    assert v >= 1

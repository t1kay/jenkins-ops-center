import psycopg
import pytest

from app import main


@pytest.fixture
def client():
    main.app.config["TESTING"] = True
    with main.app.test_client() as c:
        yield c


def _raise_db_error(*_args, **_kwargs):
    raise psycopg.OperationalError("connection refused")


def test_index(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.get_json()["app"] == "jenkins-ops-app"


def test_health_ok(client, monkeypatch):
    monkeypatch.setattr(main, "db_ping", lambda: None)
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["status"] == "ok"
    assert body["db"] == "ok"


def test_health_db_down(client, monkeypatch):
    monkeypatch.setattr(main, "db_ping", _raise_db_error)
    resp = client.get("/health")
    assert resp.status_code == 503
    assert resp.get_json()["db"] == "down"


def test_list_notes(client, monkeypatch):
    fake = [{"id": 1, "text": "hello", "created_at": "2026-01-01T00:00:00"}]
    monkeypatch.setattr(main, "list_notes", lambda: fake)
    resp = client.get("/notes")
    assert resp.status_code == 200
    assert resp.get_json()["notes"] == fake


def test_create_note(client, monkeypatch):
    monkeypatch.setattr(main, "add_note", lambda text: 42)
    resp = client.post("/notes", json={"text": "  buy milk  "})
    assert resp.status_code == 201
    assert resp.get_json() == {"id": 42, "text": "buy milk"}


@pytest.mark.parametrize("payload", [{}, {"text": ""}, {"text": "   "}])
def test_create_note_requires_text(client, payload):
    resp = client.post("/notes", json=payload)
    assert resp.status_code == 400


def test_create_note_too_long(client):
    resp = client.post("/notes", json={"text": "x" * 501})
    assert resp.status_code == 400


def test_notes_db_down(client, monkeypatch):
    monkeypatch.setattr(main, "list_notes", _raise_db_error)
    resp = client.get("/notes")
    assert resp.status_code == 503

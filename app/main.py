"""Small notes web app used as the deploy target for the Jenkins pipelines.

Endpoints:
    GET  /         basic info (env, version)
    GET  /notes    list notes
    POST /notes    add a note: {"text": "..."}
    GET  /health   app + database status (200 ok / 503 degraded)
"""

import os

import psycopg
from flask import Flask, jsonify, request

APP_ENV = os.getenv("APP_ENV", "dev")
APP_VERSION = os.getenv("APP_VERSION", "dev")
DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://app:app@localhost:5432/app"
)
MAX_NOTE_LENGTH = 500

app = Flask(__name__)


def _connect():
    return psycopg.connect(DATABASE_URL, connect_timeout=3)


def init_db():
    with _connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS notes (
                id         SERIAL PRIMARY KEY,
                text       TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )


def db_ping():
    with _connect() as conn:
        conn.execute("SELECT 1")


def list_notes():
    init_db()
    with _connect() as conn:
        rows = conn.execute(
            "SELECT id, text, created_at FROM notes ORDER BY id DESC LIMIT 100"
        ).fetchall()
    return [
        {"id": r[0], "text": r[1], "created_at": r[2].isoformat()} for r in rows
    ]


def add_note(text):
    init_db()
    with _connect() as conn:
        row = conn.execute(
            "INSERT INTO notes (text) VALUES (%s) RETURNING id", (text,)
        ).fetchone()
    return row[0]


@app.get("/")
def index():
    return jsonify(app="jenkins-ops-app", env=APP_ENV, version=APP_VERSION)


@app.get("/notes")
def get_notes():
    try:
        return jsonify(notes=list_notes())
    except psycopg.Error as exc:
        return jsonify(error="database unavailable", detail=str(exc)), 503


@app.post("/notes")
def create_note():
    data = request.get_json(silent=True) or {}
    text = str(data.get("text", "")).strip()
    if not text:
        return jsonify(error="field 'text' is required"), 400
    if len(text) > MAX_NOTE_LENGTH:
        return jsonify(error=f"text longer than {MAX_NOTE_LENGTH} chars"), 400
    try:
        note_id = add_note(text)
    except psycopg.Error as exc:
        return jsonify(error="database unavailable", detail=str(exc)), 503
    return jsonify(id=note_id, text=text), 201


@app.get("/health")
def health():
    try:
        db_ping()
        db_status = "ok"
    except psycopg.Error:
        db_status = "down"
    ok = db_status == "ok"
    body = {
        "status": "ok" if ok else "degraded",
        "db": db_status,
        "env": APP_ENV,
        "version": APP_VERSION,
    }
    return jsonify(body), 200 if ok else 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))

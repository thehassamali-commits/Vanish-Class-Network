"""
Field Sync Server - starter skeleton.

Contract (what the mobile app relies on):
  GET  /health                      -> {"status": "ok"}
  POST /sync/push                   -> push local changes
  GET  /sync/pull?since=<cursor>    -> records changed after cursor
  GET  /records/{id}                -> current server copy of one record

Versioning model:
  Each record has a server-side `version` (starts at 1 after first accept).
  A client sends `base_version`: the version it last saw for that record
  (0 if it created the record offline).
  If base_version matches the server's version, the write is accepted and
  version increments. Otherwise it is a conflict.

STUDENT TODO (graded in the viva):
  1. Conflict policy: decide what happens when base_version is stale.
     The starter returns the server copy and does nothing else.
     Choose and justify a strategy (last-write-wins by timestamp,
     field-level merge, keep both, ask the user, etc.).
  2. Idempotency: a phone may resend a push after a timeout. Each change
     carries a push_id. A repeated push_id must not create duplicate writes
     or bump versions twice.
  3. Deletes: add tombstones so deletions sync to other devices.
  4. Document your choices in API_SPEC.md before coding.
"""

import json
import sqlite3
from contextlib import contextmanager
from typing import Any, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DB_PATH = "server.db"
PULL_PAGE_SIZE = 100

app = FastAPI(title="Field Sync Server (starter)")


# ---------- database helpers ----------

@contextmanager
def db_conn():
    """One connection per request block. Commits on success, rolls back on error."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db() -> None:
    with db_conn() as db:
        db.execute("""
            CREATE TABLE IF NOT EXISTS records (
                id      TEXT PRIMARY KEY,
                data    TEXT NOT NULL,      -- JSON blob from the client
                version INTEGER NOT NULL,
                seq     INTEGER NOT NULL    -- global change counter, used as pull cursor
            )
        """)
        db.execute("CREATE INDEX IF NOT EXISTS idx_records_seq ON records(seq)")
        db.execute("""
            CREATE TABLE IF NOT EXISTS counters (
                name  TEXT PRIMARY KEY,
                value INTEGER NOT NULL
            )
        """)
        db.execute("INSERT OR IGNORE INTO counters(name, value) VALUES ('seq', 0)")


def next_seq(db: sqlite3.Connection) -> int:
    db.execute("UPDATE counters SET value = value + 1 WHERE name = 'seq'")
    return db.execute("SELECT value FROM counters WHERE name = 'seq'").fetchone()[0]


def row_to_record(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "data": json.loads(row["data"]),
        "version": row["version"],
        "seq": row["seq"],
    }


init_db()


# ---------- request models ----------

class Change(BaseModel):
    id: str
    base_version: int               # 0 = client created this record offline
    data: dict[str, Any]
    push_id: Optional[str] = None   # STUDENT TODO: use for idempotency


class PushRequest(BaseModel):
    device_id: str
    changes: list[Change]


# ---------- endpoints ----------

@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/records/{record_id}")
def get_record(record_id: str):
    with db_conn() as db:
        row = db.execute("SELECT * FROM records WHERE id = ?", (record_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="record not found")
    return row_to_record(row)


@app.post("/sync/push")
def push(req: PushRequest):
    accepted: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []

    with db_conn() as db:
        for change in req.changes:
            row = db.execute(
                "SELECT * FROM records WHERE id = ?", (change.id,)
            ).fetchone()
            server_version = row["version"] if row else 0

            if change.base_version == server_version:
                new_version = server_version + 1
                seq = next_seq(db)
                db.execute(
                    "INSERT OR REPLACE INTO records (id, data, version, seq) "
                    "VALUES (?, ?, ?, ?)",
                    (change.id, json.dumps(change.data), new_version, seq),
                )
                accepted.append({"id": change.id, "version": new_version})
            else:
                # STUDENT TODO: replace this with your conflict policy.
                # The starter only reports the conflict and returns the server copy.
                conflicts.append({
                    "id": change.id,
                    "client_base_version": change.base_version,
                    "server": row_to_record(row) if row else None,
                })

    return {"accepted": accepted, "conflicts": conflicts}


@app.get("/sync/pull")
def pull(since: int = 0):
    with db_conn() as db:
        rows = db.execute(
            "SELECT * FROM records WHERE seq > ? ORDER BY seq LIMIT ?",
            (since, PULL_PAGE_SIZE),
        ).fetchall()

    records = [row_to_record(r) for r in rows]
    cursor = records[-1]["seq"] if records else since
    return {
        "records": records,
        "cursor": cursor,
        "has_more": len(records) == PULL_PAGE_SIZE,
    }

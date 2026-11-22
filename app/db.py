"""Stores analysis results and answers history questions about senders."""

import sqlite3
from datetime import datetime, timezone

# Local database file; on AWS this is replaced by RDS.
DB_PATH = "history.db"


def get_connection():
    """Open a database connection whose rows can be read by column name."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """Create the checks table if it does not exist yet."""
    with get_connection() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS checks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                checked_at TEXT NOT NULL,
                sender TEXT,
                subject TEXT,
                score INTEGER NOT NULL,
                verdict TEXT NOT NULL
            )
        """)


def save_check(result):
    """Save one analysis result returned by detector.analyze."""
    with get_connection() as conn:
        # ? placeholders let sqlite3 insert the values safely (no SQL injection).
        conn.execute(
            "INSERT INTO checks (checked_at, sender, subject, score, verdict) "
            "VALUES (?, ?, ?, ?, ?)",
            (datetime.now(timezone.utc).isoformat(timespec="seconds"),
             result["sender"], result["subject"],
             result["score"], result["verdict"]),
        )


def recent_checks(limit=20):
    """Return the latest checks, newest first, as a list of dicts."""
    with get_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM checks ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
    return [dict(row) for row in rows]


def sender_flagged_before(sender):
    """Return True if this sender was classified as phishing in an earlier check."""
    with get_connection() as conn:
        row = conn.execute(
            "SELECT COUNT(*) FROM checks WHERE sender = ? AND verdict = 'phishing'",
            (sender,),
        ).fetchone()
    return row[0] > 0

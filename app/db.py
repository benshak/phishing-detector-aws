"""Stores analysis results and answers history questions about senders.

Locally the history lives in a SQLite file. On AWS the servers get DB_HOST
and the other DB_* environment variables, and the same code uses PostgreSQL on RDS.
"""

import os
import sqlite3
from datetime import datetime, timezone

import cache

# Set only on the EC2 servers; when it is missing we are running locally.
DB_HOST = os.environ.get("DB_HOST")
# Local database file, used only when DB_HOST is not set.
DB_PATH = "history.db"

if DB_HOST:
    # Imported only on AWS, so running locally does not need PostgreSQL.
    import psycopg2
    from psycopg2.extras import RealDictCursor

    # psycopg2 marks a value with %s, and PostgreSQL numbers rows with SERIAL.
    PLACEHOLDER = "%s"
    ID_COLUMN = "id SERIAL PRIMARY KEY"
else:
    PLACEHOLDER = "?"
    ID_COLUMN = "id INTEGER PRIMARY KEY AUTOINCREMENT"

# The history table on the page is read on every page view, so it is kept in the cache.
RECENT_LIMIT = 20
RECENT_KEY = f"recent_checks:{RECENT_LIMIT}"
# Safety net: even if a clear is missed, a cached copy lives at most 60 seconds.
RECENT_TTL_SECONDS = 60


def get_connection():
    """Open a connection to RDS on AWS, or to the local SQLite file."""
    if DB_HOST:
        return psycopg2.connect(
            host=DB_HOST,
            port=os.environ.get("DB_PORT", "5432"),
            dbname=os.environ["DB_NAME"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            connect_timeout=5,
            # Rows come back as dicts, like sqlite3.Row below.
            cursor_factory=RealDictCursor,
        )
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def run_query(sql, params=(), fetch=False):
    """Run one SQL statement, commit it and close the connection.

    SQL is written with ? placeholders and converted for the current database.
    Returns the rows when fetch is True.
    """
    sql = sql.replace("?", PLACEHOLDER)
    conn = get_connection()
    try:
        cursor = conn.cursor()
        # Values are passed separately from the SQL, which prevents SQL injection.
        cursor.execute(sql, params)
        rows = cursor.fetchall() if fetch else None
        conn.commit()
        return rows
    finally:
        # Always close, even after an error, so connections do not pile up on RDS.
        conn.close()


def init_db():
    """Create the checks table if it does not exist yet."""
    run_query(f"""
        CREATE TABLE IF NOT EXISTS checks (
            {ID_COLUMN},
            checked_at TEXT NOT NULL,
            sender TEXT,
            subject TEXT,
            score INTEGER NOT NULL,
            verdict TEXT NOT NULL
        )
    """)


def save_check(result):
    """Save one analysis result returned by detector.analyze."""
    run_query(
        "INSERT INTO checks (checked_at, sender, subject, score, verdict) "
        "VALUES (?, ?, ?, ?, ?)",
        (
            datetime.now(timezone.utc).isoformat(timespec="seconds"),
            result["sender"],
            result["subject"],
            result["score"],
            result["verdict"],
        ),
    )
    # The history just changed, so the cached copy is out of date. The cache is shared,
    # so clearing it here makes both servers read the fresh history.
    cache.delete(RECENT_KEY)


def recent_checks():
    """Return the latest checks, newest first, as a list of dicts.

    Read from the cache when possible; otherwise from the database, then cached.
    """
    cached = cache.get_json(RECENT_KEY)
    if cached is not None:
        return cached
    rows = run_query(
        "SELECT * FROM checks ORDER BY id DESC LIMIT ?", (RECENT_LIMIT,), fetch=True
    )
    checks = [dict(row) for row in rows]
    cache.set_json(RECENT_KEY, checks, RECENT_TTL_SECONDS)
    return checks


def sender_flagged_before(sender):
    """Return True if this sender was classified as phishing in an earlier check."""
    rows = run_query(
        "SELECT COUNT(*) AS total FROM checks WHERE sender = ? AND verdict = 'phishing'",
        (sender,),
        fetch=True,
    )
    return rows[0]["total"] > 0

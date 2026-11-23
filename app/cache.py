"""Shared cache (ElastiCache Redis) that sits in front of the database.

On AWS the servers get REDIS_HOST, and both servers use the same cache, so
when one server clears an entry, the other server stops seeing it too.
Locally there is no REDIS_HOST, and every function here just reports "no cache".
If Redis is down, the app logs a warning and reads from the database instead,
so the cache can only make the app faster, never take it down.
"""

import json
import logging
import os

# Set only on the EC2 servers; when it is missing we run without a cache.
REDIS_HOST = os.environ.get("REDIS_HOST")

if REDIS_HOST:
    # Imported only on AWS, so running locally does not need Redis.
    import redis

    # Short timeouts: a slow cache must not make the page slow.
    client = redis.Redis(
        host=REDIS_HOST,
        port=int(os.environ.get("REDIS_PORT", "6379")),
        socket_connect_timeout=1,
        socket_timeout=1,
    )
else:
    client = None


def get_json(key):
    """Return the cached value for key, or None on a miss or when there is no cache."""
    if client is None:
        return None
    try:
        value = client.get(key)
    except redis.RedisError as error:
        logging.warning("Cache unavailable, reading from the database: %s", error)
        return None
    # One log line per lookup, so hits and misses can be followed in CloudWatch Logs.
    logging.info("cache=%s key=%s", "hit" if value is not None else "miss", key)
    return json.loads(value) if value is not None else None


def set_json(key, value, ttl_seconds):
    """Store value under key; Redis deletes it by itself after ttl_seconds."""
    if client is None:
        return
    try:
        client.set(key, json.dumps(value), ex=ttl_seconds)
    except redis.RedisError as error:
        logging.warning("Cache unavailable, value not stored: %s", error)


def delete(key):
    """Remove key, so the next read goes to the database and gets fresh data."""
    if client is None:
        return
    try:
        client.delete(key)
    except redis.RedisError as error:
        logging.warning("Cache unavailable, could not clear %s: %s", key, error)

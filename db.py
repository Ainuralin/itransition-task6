"""Database access. The application never generates fake fields in Python."""

import os
from contextlib import contextmanager
import psycopg
from dotenv import load_dotenv

load_dotenv()


@contextmanager
def connection(timeout_ms=30000):
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        raise RuntimeError(
            "DATABASE_URL is missing. Copy .env.example to .env and enter your PostgreSQL connection string."
        )
    with psycopg.connect(
        url, connect_timeout=15, autocommit=True, prepare_threshold=None
    ) as conn:
        conn.execute(
            "SELECT set_config('statement_timeout', %s, false)", (str(timeout_ms),)
        )
        yield conn


def catalog():
    with connection() as conn:
        return conn.execute("CALL sqlfaker.catalog_info(NULL)").fetchone()[0]


def generate(locale, seed, batch, size):
    with connection() as conn:
        return conn.execute(
            "CALL sqlfaker.generate_batch(%s, %s, %s, %s, NULL)",
            (locale, seed, batch, size),
        ).fetchone()[0]


def benchmark(locale, seed, count, size=100):
    with connection(timeout_ms=300000) as conn:
        return conn.execute(
            "CALL sqlfaker.benchmark(%s, %s, %s, %s, NULL)", (locale, seed, count, size)
        ).fetchone()[0]

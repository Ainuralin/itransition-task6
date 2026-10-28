"""Install SQL procedures and load versioned static lookup data."""

from pathlib import Path
import hashlib
import csv
from db import connection

ROOT = Path(__file__).resolve().parent
TABLES = {
    "locales": "code,label,country,calling_code,postal_digits",
    "names": "locale,kind,gender,slot,value,latin",
    "places": "locale,slot,region,city,district",
    "streets": "locale,slot,value",
}


def initialize():
    digest = hashlib.sha256()
    for table in TABLES:
        digest.update(table.encode("utf-8"))
        digest.update(
            (ROOT / "data" / f"{table}.csv")
            .read_text(encoding="utf-8-sig")
            .encode("utf-8")
        )
    checksum = digest.hexdigest()
    with connection(timeout_ms=120000) as conn, conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(6241028)")
        conn.execute((ROOT / "sql/01_schema.sql").read_text(encoding="utf-8"))
        stored = conn.execute(
            "SELECT version, checksum FROM sqlfaker.dataset WHERE id=1"
        ).fetchone()
        if stored and stored != ("1.0", checksum):
            raise RuntimeError(
                "The installed lookup version differs from these files. Keep the existing v1 data unchanged or install a new version in a separate database."
            )
        if not stored:
            for table, columns in TABLES.items():
                with (ROOT / "data" / f"{table}.csv").open(
                    encoding="utf-8", newline=""
                ) as source:
                    rows = csv.reader(source)
                    next(rows)
                    placeholders = ",".join(["%s"] * len(columns.split(",")))
                    with conn.cursor() as cursor:
                        cursor.executemany(
                            f"INSERT INTO sqlfaker.{table} ({columns}) VALUES ({placeholders})",
                            rows,
                        )
            conn.execute(
                "INSERT INTO sqlfaker.dataset(id,version,checksum) VALUES (1,%s,%s)",
                ("1.0", checksum),
            )
        conn.execute((ROOT / "sql/02_procedures.sql").read_text(encoding="utf-8"))
    print("SQL Faker 1.0: procedures installed; lookup data ready.")


if __name__ == "__main__":
    initialize()

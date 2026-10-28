"""Small Flask interface for the SQL Faker stored procedures."""

from pathlib import Path
import os
import logging
from flask import Flask, jsonify, render_template, request
from markupsafe import Markup
import markdown
import psycopg
import db

ROOT = Path(__file__).resolve().parent
app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 8192


def arguments():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        raise ValueError("Expected a JSON object.")
    locale = payload.get("locale", "zh-CN")
    if not isinstance(locale, str) or locale not in {"zh-CN", "ko-KR"}:
        raise ValueError("Choose China or South Korea.")

    def integer(key, default, low, high):
        value = payload.get(key, default)
        if (
            isinstance(value, bool)
            or not str(value).isascii()
            or not str(value).isdigit()
        ):
            raise ValueError(f"{key} must be a whole number.")
        value = int(value)
        if value < low or value > high:
            raise ValueError(f"{key} must be between {low} and {high}.")
        return value

    return payload, locale, integer


@app.errorhandler(ValueError)
def bad_request(exc):
    return jsonify(error=str(exc)), 400


@app.errorhandler(RuntimeError)
def not_ready(exc):
    return jsonify(error=str(exc)), 503


@app.errorhandler(psycopg.Error)
def database_error(exc):
    if exc.sqlstate == "22023":
        return (
            jsonify(error=exc.diag.message_primary or "Invalid generation parameters."),
            400,
        )
    logging.getLogger(__name__).warning(
        "Database request failed (%s)", type(exc).__name__
    )
    return (
        jsonify(
            error="The database is unavailable or has not been initialized. Check DATABASE_URL and run python init_db.py."
        ),
        503,
    )


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/docs")
def documentation():
    body = markdown.markdown(
        (ROOT / "docs/procedures.md").read_text(encoding="utf-8"),
        extensions=["tables", "fenced_code", "toc"],
    )
    return render_template("docs.html", content=Markup(body))


@app.get("/api/catalog")
def catalog():
    return jsonify(db.catalog())


@app.get("/api/health")
def health():
    info = db.catalog()
    if not info.get("version") or len(info.get("locales", [])) < 2:
        raise RuntimeError("Lookup data is incomplete.")
    return jsonify(status="ok", version=info["version"])


@app.post("/api/users")
def users():
    _, locale, integer = arguments()
    seed = integer("seed", 42, 0, 2147483647)
    batch = integer("batch", 0, 0, 999999)
    size = integer("size", 10, 1, 100)
    if (batch + 1) * size > 1000000:
        raise ValueError("This batch exceeds the limit of 1,000,000 positions.")
    rows = db.generate(locale, seed, batch, size)
    return jsonify(
        locale=locale,
        seed=seed,
        batch=batch,
        size=size,
        start=batch * size + 1,
        end=batch * size + len(rows),
        users=rows,
        version="1.0",
    )


@app.post("/api/benchmark")
def benchmark():
    _, locale, integer = arguments()
    seed = integer("seed", 42, 0, 2147483647)
    count = integer("count", 1000, 100, 10000)
    return jsonify(db.benchmark(locale, seed, count, 100))


if __name__ == "__main__":
    app.run(
        host=os.environ.get("HOST", "127.0.0.1"),
        port=int(os.environ.get("PORT", "5000")),
        debug=False,
    )

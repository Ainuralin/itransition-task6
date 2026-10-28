import re
import numpy as np
import pytest
from app import app
import db
from init_db import initialize


@pytest.fixture(scope="session", autouse=True)
def database():
    initialize()


@pytest.mark.parametrize("locale", ["zh-CN", "ko-KR"])
def test_replay_and_seed_change(locale):
    first = db.generate(locale, 42, 0, 10)
    db.generate(locale, 99, 5, 10)
    assert db.generate(locale, 42, 0, 10) == first
    assert db.generate(locale, 43, 0, 10) != first
    assert len({x["email"] for x in first}) == 10


def test_partition_and_last_position():
    a = db.generate("zh-CN", 42, 0, 20)
    assert a[:10] == db.generate("zh-CN", 42, 0, 10)
    assert a[10:] == db.generate("zh-CN", 42, 1, 10)
    assert db.generate("ko-KR", 0, 99999, 10)[-1]["position"] == 999999


@pytest.mark.parametrize("locale", ["zh-CN", "ko-KR"])
def test_native_fields_and_variations(locale):
    rows = db.generate(locale, 123, 0, 100)
    assert len({x["title"] for x in rows}) >= 2
    assert len({x["phone"]["formatted"].count("-") for x in rows}) >= 2
    assert {x["gender"] for x in rows} == {"F", "M"}
    assert len({x["physical"]["blood_group"] for x in rows}) == 4
    for x in rows:
        assert x["full_name"] == x["family_name"] + x["given_name"]
        assert len(x["email"].split("@")[0]) <= 64
        assert x["email"].isascii()
        assert x["email"].endswith(("@example.com", "@example.net", "@example.org"))
        assert re.fullmatch(
            r"\+86\d{11}" if locale == "zh-CN" else r"\+8210\d{8}", x["phone"]["e164"]
        )
        assert re.fullmatch(
            r"\d{6}" if locale == "zh-CN" else r"\d{5}", x["address"]["postcode"]
        )
        assert -90 <= x["coordinates"]["latitude"] <= 90
        assert -180 <= x["coordinates"]["longitude"] <= 180


def test_sphere_equal_area_and_normal_samples():
    rows = []
    for page in range(3):
        rows.extend(db.generate("zh-CN", 2026, page, 1000))
    z = np.sin(np.radians([x["coordinates"]["latitude"] for x in rows]))
    longitude = np.array([x["coordinates"]["longitude"] for x in rows])
    # Equal increments of sin(latitude), not latitude, define equal-area bands.
    bands = np.histogram(z, bins=np.linspace(-1, 1, 11))[0]
    expected = len(rows) / 10
    assert ((bands - expected) ** 2 / expected).sum() < 35
    cells = np.histogram2d(
        z, longitude, bins=[np.linspace(-1, 1, 6), np.linspace(-180, 180, 9)]
    )[0]
    expected = len(rows) / 40
    assert ((cells - expected) ** 2 / expected).sum() < 80
    assert abs(np.corrcoef(z, longitude)[0, 1]) < 0.07
    for key, sd, means in [
        ("height_cm", 7, {"F": 163, "M": 175}),
        ("weight_kg", 9, {"F": 60, "M": 75}),
    ]:
        standard = np.array(
            [(x["physical"][key] - means[x["gender"]]) / sd for x in rows]
        )
        assert abs(standard.mean()) < 0.08
        assert 0.92 < standard.std(ddof=1) < 1.08
        assert 0.65 < (abs(standard) < 1).mean() < 0.72


def test_catalog_size_and_storage_procedures():
    info = db.catalog()
    assert len(info["locales"]) == 2 and info["version"] == "1.0"
    for locale in info["locales"]:
        combinations = (
            locale["family_names"]
            * locale["given_names"]
            * locale["places"]
            * locale["streets"]
        )
        assert combinations > 1000000
    with db.connection() as conn:
        routines = conn.execute(
            "SELECT proname,prokind FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='sqlfaker'"
        ).fetchall()
        assert len(routines) >= 10
        assert all(kind == "p" for _, kind in routines)
        definitions = conn.execute(
            "SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='sqlfaker'"
        ).fetchall()
        assert not any(
            re.search(r"\b(random|setseed)\s*\(", definition, re.I)
            for (definition,) in definitions
        )


def test_sql_benchmark_count_and_replay_checksum():
    first = db.benchmark("ko-KR", 42, 105, 100)
    second = db.benchmark("ko-KR", 42, 105, 100)
    assert first["users"] == 105 and first["json_bytes"] > 10000
    assert first["seconds"] > 0 and first["users_per_second"] > 0
    assert first["checksum"] == second["checksum"]


def test_web_endpoints_use_sql_and_documentation():
    client = app.test_client()
    assert client.get("/").status_code == 200
    assert client.get("/api/health").json["status"] == "ok"
    doc = client.get("/docs")
    assert doc.status_code == 200 and b"generate_batch" in doc.data
    payload = {"locale": "ko-KR", "seed": 42, "batch": 0, "size": 10}
    first = client.post("/api/users", json=payload)
    assert first.status_code == 200
    assert first.json["users"] == db.generate("ko-KR", 42, 0, 10)
    assert client.post("/api/users", json=payload).json == first.json
    for broken in [
        dict(payload, seed=-1),
        dict(payload, seed=True),
        dict(payload, batch=100000),
        dict(payload, locale="missing"),
        dict(payload, size=101),
        dict(payload, seed="1.5"),
    ]:
        assert client.post("/api/users", json=broken).status_code == 400
    assert client.post("/api/users", json=[]).status_code == 400


def test_web_benchmark():
    response = app.test_client().post(
        "/api/benchmark", json={"locale": "zh-CN", "seed": 42, "count": 100}
    )
    assert response.status_code == 200
    assert response.json["users"] == 100
    assert response.json["users_per_second"] > 0

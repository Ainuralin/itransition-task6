CREATE SCHEMA IF NOT EXISTS sqlfaker;

CREATE TABLE IF NOT EXISTS sqlfaker.locales (
    code text PRIMARY KEY,
    label text NOT NULL,
    country text NOT NULL,
    calling_code text NOT NULL,
    postal_digits integer NOT NULL CHECK (postal_digits IN (5, 6))
);

CREATE TABLE IF NOT EXISTS sqlfaker.names (
    locale text NOT NULL REFERENCES sqlfaker.locales(code),
    kind text NOT NULL CHECK (kind IN ('family', 'given')),
    gender text NOT NULL CHECK (gender IN ('F', 'M', 'X')),
    slot integer NOT NULL CHECK (slot > 0),
    value text NOT NULL,
    latin text NOT NULL,
    PRIMARY KEY (locale, kind, gender, slot)
);

CREATE TABLE IF NOT EXISTS sqlfaker.places (
    locale text NOT NULL REFERENCES sqlfaker.locales(code),
    slot integer NOT NULL CHECK (slot > 0),
    region text NOT NULL,
    city text NOT NULL,
    district text NOT NULL,
    PRIMARY KEY (locale, slot)
);

CREATE TABLE IF NOT EXISTS sqlfaker.streets (
    locale text NOT NULL REFERENCES sqlfaker.locales(code),
    slot integer NOT NULL CHECK (slot > 0),
    value text NOT NULL,
    PRIMARY KEY (locale, slot)
);

CREATE TABLE IF NOT EXISTS sqlfaker.dataset (
    id integer PRIMARY KEY CHECK (id = 1),
    version text NOT NULL,
    checksum text NOT NULL,
    installed_at timestamptz NOT NULL DEFAULT now()
);

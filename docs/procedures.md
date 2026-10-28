# SQL Faker procedure reference

A small PostgreSQL library for repeatable synthetic contacts in Simplified Chinese (`zh-CN`) and Korean (`ko-KR`). The Python application calls this library and displays its results. It does not generate fake fields.

## Quick start

Install the schema, lookup data and procedures with `python init_db.py`, using the connection string in `DATABASE_URL`. PostgreSQL 15 or newer is required. The project includes a PostgreSQL 17 Docker configuration.

Generate the first ten contacts:

```sql
CALL sqlfaker.generate_batch('zh-CN', 42, 0, 10, NULL);
```

Read the next batch:

```sql
CALL sqlfaker.generate_batch('zh-CN', 42, 1, 10, NULL);
```

Switch to South Korea:

```sql
CALL sqlfaker.generate_batch('ko-KR', 42, 0, 10, NULL);
```

`CALL` returns one row containing an output named `users`, a JSONB array of contact objects. Pass `NULL` for each `OUT` argument in a top-level call. `INOUT` arguments return their updated value alongside the other outputs.

## Batch arguments and positions

| Argument      | Meaning                 | Allowed values                           |
| ------------- | ----------------------- | ---------------------------------------- |
| `locale_code` | Language and country    | `zh-CN`, `ko-KR`                         |
| `seed_value`  | Reproducible scenario   | Integer 0–2147483647                     |
| `batch_index` | Zero-based batch number | Nonnegative integer                      |
| `batch_size`  | Contacts in this batch  | 1–1000 in SQL, 1–100 through the web API |
| `users`       | Output JSONB array      | Pass `NULL` when calling                 |

The first record position is `batch_index × batch_size`. Positions are zero-based and must stay within 0–999999. The displayed `number` is position + 1. A batch must fit completely within that range.

Changing the batch size changes pagination, not record identity. Batch 0 of size 20 contains exactly the same records as batches 0 and 1 of size 10. Reopening a saved locale, seed, batch and size reproduces that batch.

## Contact structure

| Field                                    | Meaning                                                 |
| ---------------------------------------- | ------------------------------------------------------- |
| `id`, `position`, `number`, `locale`     | Stable identifier and position                          |
| `family_name`, `given_name`, `full_name` | Name components, surname first                          |
| `display_name`, `title`                  | Local spacing and optional form of address              |
| `latin_name`                             | Approximate ASCII transliteration from the lookup table |
| `gender`                                 | Name group used for the sample, F or M                  |
| `address`                                | Formatted address and individual components             |
| `coordinates`                            | Latitude and longitude sampled over the whole sphere    |
| `physical`                               | Height, weight, eye color and blood group               |
| `phone`                                  | Varied display format and normalized E.164-like value   |
| `email`                                  | ASCII address on an example domain                      |

Coordinates are deliberately independent of the address. Confining them to China or South Korea would not produce a uniform sample over the entire sphere. The street/building/postcode combinations are fictional, not verified mailing locations. Phone numbers follow plausible national shapes and can coincide with real numbers. The email domains are `example.com`, `example.net` and `example.org`.

## How reproducibility works

For each record, `generate_user` hashes this exact UTF-8 string:

```text
sqlfaker-v1|locale|seed|absolute_position
```

It takes the first 15 hexadecimal digits of PostgreSQL's built-in MD5 result, interprets them as a positive 60-bit integer, reduces it modulo 2147483646 and adds 1. This initializes a local Park–Miller state. MD5 is used only to mix deterministic identifiers, not for passwords or security.

Each helper receives that local state through `INOUT` and returns the advanced state. Calls from other users, previous batches, database sessions and connection order do not change the result. There is no call to `random()`, `setseed()` or a shared sequence.

The guarantee applies to library and lookup version 1.0. Reordering or changing lookup values changes the mapping. The installer records a dataset checksum and refuses to silently replace an existing different dataset. Keep versioned data stable. Floating-point mathematical results are rounded for display; cross-platform implementations can differ at a last rounding boundary, so exact replay is guaranteed on the same PostgreSQL environment and library version.

## Procedure reference

### uniform

```sql
CALL sqlfaker.uniform(12345, 0.0, 1.0, NULL);
```

Arguments: `state bigint INOUT`, `lower_bound float8`, `upper_bound float8`, `value float8 OUT`.

Advances the state using `state = state × 48271 mod 2147483647`. The starting state must be 1–2147483646. `u = state / 2147483647` lies strictly between 0 and 1, so `ln(u)` is safe. The returned value is `lower + (upper − lower) × u`. Equal bounds give a constant. Use finite numeric bounds with lower ≤ upper.

For a discrete selection among N values, the other procedures request a value between 0 and N and take its floor. The small finite-state discretization of this pseudorandom generator is not a cryptographic guarantee.

### normal

```sql
CALL sqlfaker.normal(12345, 170.0, 7.0, NULL);
```

Arguments: `state bigint INOUT`, `mean_value float8`, `deviation float8`, `value float8 OUT`.

Consumes two uniform draws and applies Box–Muller:

```text
z = sqrt(-2 × ln(u1)) × cos(2 × pi × u2)
value = mean + deviation × z
```

The standard deviation must be nonnegative. No clipping or rejection is applied. Physical measurements are rounded to one decimal place after generation.

### load_catalog

```sql
CALL sqlfaker.load_catalog('zh-CN', NULL);
```

Arguments: `locale_code text`, `catalog jsonb OUT`.

Loads the locale metadata, ordered family and given-name arrays, place tuples and streets. Called once per batch instead of querying the lookup tables for every field. Rejects unknown locales and incomplete data.

### person_name

Arguments: `state bigint INOUT`, `catalog jsonb`, `person jsonb OUT`.

Chooses a name group, family name, given name and presentation variant. Chinese names concatenate the family name and given name; one variant adds `先生` or `女士`. Korean variants include concatenated or spaced names and optional `님` or `씨`. A Western middle name is not added.

The returned internal `email_stem` contains ASCII family and given-name forms. `generate_user` uses it for email and removes it from the public object.

### address

Arguments: `state bigint INOUT`, `catalog jsonb`, `result jsonb OUT`.

Selects a coherent city/district tuple and a street from the chosen locale. Adds a building number, optional room/apartment, postcode and formatting variant. Chinese variants use `号`, `室` and an optional `中国` prefix. Korean variants use `호`, spaces and an optional `대한민국` prefix. Chinese postcodes have six digits, Korean postcodes five. They follow a format rather than a delivery-area lookup.

### coordinates

```sql
CALL sqlfaker.coordinates(12345, NULL);
```

Arguments: `state bigint INOUT`, `result jsonb OUT`.

For independent uniform draws u and v:

```text
latitude  = degrees(asin(2 × u − 1))
longitude = 360 × v − 180
```

The surface-area element is proportional to `cos(latitude) d(latitude) d(longitude)`. Uniform `sin(latitude)` and longitude therefore produce equal probability per unit area. Sampling latitude uniformly would put too many points near the poles. The procedure rounds the result to six decimal places.

### attributes

```sql
CALL sqlfaker.attributes(12345, 'F', NULL);
```

Arguments: `state bigint INOUT`, `gender_code text`, `result jsonb OUT`.

| Measurement | Group F  | Group M  | Standard deviation |
| ----------- | -------- | -------- | ------------------ |
| Height, cm  | Mean 163 | Mean 175 | 7                  |
| Weight, kg  | Mean 60  | Mean 75  | 9                  |

These are illustrative generation parameters, not demographic estimates. Normal samples are independent. Eye colors use a discrete distribution: brown 55%, dark brown 35%, hazel 8%, gray 2%. Blood groups A, B, AB and O have equal selection probability. The choices demonstrate continuous and discrete generation, not population prevalence.

### phone

```sql
CALL sqlfaker.phone(12345, 'ko-KR', NULL);
```

Arguments: `state bigint INOUT`, `locale_code text`, `result jsonb OUT`.

China: a mobile-style three-digit prefix plus eight digits; international prefix `+86`. South Korea: domestic prefix `010`, eight subscriber digits, international form `+82 10`. The display can be international, hyphenated domestic or compact domestic. The normalized value is returned separately as `e164`.

### email

```sql
CALL sqlfaker.email(12345, 'zhang.wei', 42, 0, NULL);
```

Arguments: `state bigint INOUT`, `stem text`, `seed_value bigint`, `position_value bigint`, `email_address text OUT`.

Builds `stem.seed.record_number@example-domain`, limiting the stem to 35 characters. Unique record numbers prevent duplicate email addresses within one locale/seed dataset. Uses only the three example domains listed above.

### generate_user

Arguments: `locale_code text`, `seed_value bigint`, `position_value bigint`, `catalog jsonb`, `result jsonb OUT`.

Initializes the local RNG, calls the field procedures in a fixed order and combines their results. Used internally by `generate_batch`. Direct calls require a matching catalog:

```sql
DO $$
DECLARE c jsonb; person jsonb;
BEGIN
    CALL sqlfaker.load_catalog('ko-KR', c);
    CALL sqlfaker.generate_user('ko-KR', 42, 0, c, person);
    RAISE NOTICE '%', person;
END;
$$;
```

### generate_batch

The main public entry point, documented at the start of this page. Generates full records and returns a JSONB array. It does not insert generated people into a table. Memory usage depends on the requested batch size, not on the overall dataset capacity.

### catalog_info

```sql
CALL sqlfaker.catalog_info(NULL);
```

Returns the library version, supported locales and counts of names, places and streets. Used by the site's locale selector and health endpoint.

### benchmark

```sql
CALL sqlfaker.benchmark('zh-CN', 42, 10000, 100, NULL);
```

Arguments: `locale_code text`, `seed_value bigint`, `user_count integer`, `batch_size integer`, `result jsonb OUT`.

Accepts 1–1000000 users and batch sizes 1–1000. Warms the same batch procedure once, starts `clock_timestamp()`, generates complete batches and the final partial batch, serializes their JSON and computes a rolling checksum. All timing happens inside PostgreSQL. Full contact generation is performed; only the resulting contact arrays are discarded after measurement.

Returns `users`, `seconds`, `users_per_second`, `batch_size`, `json_bytes`, `checksum`, `locale`, `seed`, `postgres_version` and a timing-scope description. The result includes catalog loading, field generation, JSON construction, serialization and checksumming. It excludes network transfer of the contacts and Python/HTML rendering. The web endpoint limits a benchmark to 10000 contacts. Use the CLI for a larger run:

```bash
python benchmark.py --count 100000 --batch-size 100 --runs 3
```

The CLI saves all timings and their median to `benchmark_results.json`. Run against the same database you plan to demonstrate; timings depend on its CPU, load, runtime and batch size. The bundled test-environment measurement is described in the repository README.

## Lookup design and capacity

The shared tables are `locales`, `names`, `places`, `streets` and `dataset`. The `locale` key distinguishes countries inside each lookup table. Names are distinguished by kind and group, not by separate English/Chinese/Korean tables.

The catalog includes 399 Chinese family names, 131 Chinese given names, 40 Chinese place tuples and 91 Chinese streets. The Korean catalog includes 112 family names, 540 given names, 65 place tuples and 22 streets. Just multiplying family names × given names × places × streets gives over one million combinations for either locale, before building numbers, apartments, phone numbers and physical measurements are considered. Full contacts can be generated for one million stable positions. Name collisions are expected; a million people do not imply a million unique names.

Lookup lists are versioned snapshots. Chinese names and Korean road stems originate from the static data lists of Python Faker. Korean names come from the larger Faker JS lists. Both are used under their MIT licenses. No Faker library is installed or called at runtime. See `data/SOURCES.md` and `data/FAKER_LICENSE.txt` and `data/FAKER_JS_LICENSE.txt` for provenance. Selection weights have been simplified and outputs are synthetic rather than representative samples of a national population.

To add a locale, add metadata and locale-keyed lookup rows, then extend the locale-specific name, address and phone formatting branches. Preserve existing v1 catalogs if their existing outputs need to remain unchanged; introduce a new library/data version for a changed mapping.

## Errors and limits

Unsupported locales, negative/out-of-range seeds, invalid batch sizes and requests beyond the last position raise SQLSTATE `22023`. The web app returns those as HTTP 400. A missing database connection or uninitialized schema returns HTTP 503 with a setup message. The application never substitutes Python-generated fake data when the database is unavailable.

The optional Markov-chain text generator is not included.

## References

- [PostgreSQL CREATE PROCEDURE](https://www.postgresql.org/docs/current/sql-createprocedure.html)
- [PostgreSQL CALL](https://www.postgresql.org/docs/current/sql-call.html)
- [PostgreSQL mathematical functions](https://www.postgresql.org/docs/current/functions-math.html)
- [Faker lookup-data repository](https://github.com/joke2k/faker)

-- Local state only: no random(), setseed(), sequences or shared mutable RNG.
CREATE OR REPLACE PROCEDURE sqlfaker.uniform(
    INOUT state bigint, IN lower_bound double precision,
    IN upper_bound double precision, OUT value double precision
)
LANGUAGE plpgsql AS $$
BEGIN
    IF state IS NULL OR state < 1 OR state > 2147483646 THEN
        RAISE EXCEPTION 'RNG state must be between 1 and 2147483646' USING ERRCODE = '22023';
    END IF;
    IF lower_bound IS NULL OR upper_bound IS NULL OR lower_bound > upper_bound THEN
        RAISE EXCEPTION 'Invalid uniform bounds' USING ERRCODE = '22023';
    END IF;
    state := (state * 48271) % 2147483647;
    value := lower_bound + (upper_bound - lower_bound) * state::double precision / 2147483647.0;
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.normal(
    INOUT state bigint, IN mean_value double precision,
    IN deviation double precision, OUT value double precision
)
LANGUAGE plpgsql AS $$
DECLARE u double precision; v double precision;
BEGIN
    IF deviation IS NULL OR deviation < 0 OR mean_value IS NULL THEN
        RAISE EXCEPTION 'Normal deviation must be nonnegative' USING ERRCODE = '22023';
    END IF;
    CALL sqlfaker.uniform(state, 0.0, 1.0, u);
    CALL sqlfaker.uniform(state, 0.0, 1.0, v);
    value := mean_value + deviation * sqrt(-2.0 * ln(u)) * cos(2.0 * pi() * v);
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.load_catalog(IN locale_code text, OUT catalog jsonb)
LANGUAGE plpgsql AS $$
DECLARE result jsonb; n jsonb;
BEGIN
    SELECT to_jsonb(l) INTO result FROM sqlfaker.locales l WHERE code = locale_code;
    IF result IS NULL THEN
        RAISE EXCEPTION 'Unsupported locale: %', locale_code USING ERRCODE = '22023';
    END IF;
    SELECT jsonb_object_agg(key, entries) INTO n FROM (
        SELECT kind || '_' || gender AS key,
               jsonb_agg(jsonb_build_object('value', value, 'latin', latin) ORDER BY slot) AS entries
        FROM sqlfaker.names WHERE locale = locale_code GROUP BY kind, gender
    ) entries;
    result := result || jsonb_build_object('names', n);
    SELECT result || jsonb_build_object('places', jsonb_agg(to_jsonb(p) ORDER BY slot))
        INTO result FROM sqlfaker.places p WHERE locale = locale_code;
    SELECT result || jsonb_build_object('streets', jsonb_agg(value ORDER BY slot))
        INTO result FROM sqlfaker.streets WHERE locale = locale_code;
    IF coalesce(jsonb_array_length(result->'names'->'family_X'), 0) = 0
       OR coalesce(jsonb_array_length(result->'names'->'given_F'), 0) = 0
       OR coalesce(jsonb_array_length(result->'names'->'given_M'), 0) = 0
       OR coalesce(jsonb_array_length(result->'places'), 0) = 0
       OR coalesce(jsonb_array_length(result->'streets'), 0) = 0 THEN
        RAISE EXCEPTION 'Lookup data is incomplete for %', locale_code USING ERRCODE = '22023';
    END IF;
    catalog := result;
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.person_name(
    INOUT state bigint, IN catalog jsonb, OUT person jsonb
)
LANGUAGE plpgsql AS $$
DECLARE u double precision; gender_code text; family jsonb; given jsonb;
        full_name text; display_name text; title text := ''; variation integer;
BEGIN
    CALL sqlfaker.uniform(state, 0.0, 2.0, u);
    gender_code := CASE WHEN u < 1 THEN 'F' ELSE 'M' END;
    CALL sqlfaker.uniform(state, 0.0, jsonb_array_length(catalog->'names'->'family_X')::float8, u);
    family := catalog->'names'->'family_X'->floor(u)::integer;
    CALL sqlfaker.uniform(state, 0.0, jsonb_array_length(catalog->'names'->('given_' || gender_code))::float8, u);
    given := catalog->'names'->('given_' || gender_code)->floor(u)::integer;
    full_name := (family->>'value') || (given->>'value');
    CALL sqlfaker.uniform(state, 0.0, 4.0, u); variation := floor(u)::integer;
    IF catalog->>'code' = 'zh-CN' THEN
        IF variation = 3 THEN title := CASE gender_code WHEN 'F' THEN '女士' ELSE '先生' END; END IF;
        display_name := full_name || title;
    ELSE
        IF variation = 1 THEN title := '님'; ELSIF variation = 3 THEN title := '씨'; END IF;
        display_name := CASE WHEN variation = 2 THEN (family->>'value') || ' ' || (given->>'value') ELSE full_name END;
        IF title <> '' THEN display_name := display_name || ' ' || title; END IF;
    END IF;
    person := jsonb_build_object('full_name', full_name, 'display_name', display_name,
        'family_name', family->>'value', 'given_name', given->>'value', 'title', title,
        'gender', gender_code, 'latin_name', (family->>'latin') || ' ' || (given->>'latin'),
        'email_stem', (family->>'latin') || '.' || (given->>'latin'));
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.address(
    INOUT state bigint, IN catalog jsonb, OUT result jsonb
)
LANGUAGE plpgsql AS $$
DECLARE u double precision; place jsonb; street text; building integer;
        apartment integer; postcode text; variation integer; formatted text;
BEGIN
    CALL sqlfaker.uniform(state, 0.0, jsonb_array_length(catalog->'places')::float8, u);
    place := catalog->'places'->floor(u)::integer;
    CALL sqlfaker.uniform(state, 0.0, jsonb_array_length(catalog->'streets')::float8, u);
    street := catalog->'streets'->>floor(u)::integer;
    CALL sqlfaker.uniform(state, 1.0, 500.0, u); building := floor(u)::integer;
    CALL sqlfaker.uniform(state, 1.0, 1501.0, u); apartment := floor(u)::integer;
    CALL sqlfaker.uniform(state, 10000.0, 100000.0, u);
    IF catalog->>'code' = 'zh-CN' THEN
        postcode := lpad((floor(u)::integer * 10)::text, 6, '0');
    ELSE postcode := lpad(floor(u)::integer::text, 5, '0'); END IF;
    CALL sqlfaker.uniform(state, 0.0, 3.0, u); variation := floor(u)::integer;
    IF catalog->>'code' = 'zh-CN' THEN
        formatted := (place->>'region') || (place->>'city') || (place->>'district') || street || building || '号';
        IF variation > 0 THEN formatted := formatted || apartment || '室'; END IF;
        IF variation = 2 THEN formatted := '中国 ' || postcode || ' ' || formatted;
        ELSE formatted := formatted || '，' || postcode; END IF;
    ELSE
        formatted := (place->>'city') || ' ' || (place->>'district') || ' ' || street || ' ' || building;
        IF variation > 0 THEN formatted := formatted || ', ' || apartment || '호'; END IF;
        IF variation = 2 THEN formatted := '대한민국 (' || postcode || ') ' || formatted;
        ELSE formatted := formatted || ' (' || postcode || ')'; END IF;
    END IF;
    result := jsonb_build_object('formatted', formatted, 'country', catalog->>'country',
        'region', place->>'region', 'city', place->>'city', 'district', place->>'district',
        'street', street, 'building', building, 'apartment', CASE WHEN variation > 0 THEN apartment ELSE NULL END,
        'postcode', postcode);
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.coordinates(
    INOUT state bigint, OUT result jsonb
)
LANGUAGE plpgsql AS $$
DECLARE u double precision; v double precision;
BEGIN
    CALL sqlfaker.uniform(state, 0.0, 1.0, u);
    CALL sqlfaker.uniform(state, 0.0, 1.0, v);
    result := jsonb_build_object('latitude', round(degrees(asin(2.0 * u - 1.0))::numeric, 6),
        'longitude', round((360.0 * v - 180.0)::numeric, 6));
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.attributes(
    INOUT state bigint, IN gender_code text, OUT result jsonb
)
LANGUAGE plpgsql AS $$
DECLARE height double precision; weight double precision; u double precision;
        eyes text[] := ARRAY['brown', 'dark brown', 'hazel', 'gray'];
        blood text[] := ARRAY['A', 'B', 'AB', 'O']; eye text;
BEGIN
    CALL sqlfaker.normal(state, CASE WHEN gender_code = 'F' THEN 163.0 ELSE 175.0 END, 7.0, height);
    CALL sqlfaker.normal(state, CASE WHEN gender_code = 'F' THEN 60.0 ELSE 75.0 END, 9.0, weight);
    CALL sqlfaker.uniform(state, 0.0, 1.0, u);
    eye := CASE WHEN u < .55 THEN eyes[1] WHEN u < .90 THEN eyes[2] WHEN u < .98 THEN eyes[3] ELSE eyes[4] END;
    CALL sqlfaker.uniform(state, 0.0, 4.0, u);
    result := jsonb_build_object('height_cm', round(height::numeric, 1),
        'weight_kg', round(weight::numeric, 1), 'eye_color', eye, 'blood_group', blood[1 + floor(u)::integer]);
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.phone(
    INOUT state bigint, IN locale_code text, OUT result jsonb
)
LANGUAGE plpgsql AS $$
DECLARE u double precision; prefix text; rest text; raw text; formatted text;
        prefixes text[] := ARRAY['130','131','132','133','135','136','137','138','139','150','151','152','155','156','157','158','159','186','187','188'];
        variation integer;
BEGIN
    CALL sqlfaker.uniform(state, 10000000.0, 100000000.0, u); rest := floor(u)::bigint::text;
    CALL sqlfaker.uniform(state, 0.0, 3.0, u); variation := floor(u)::integer;
    IF locale_code = 'zh-CN' THEN
        CALL sqlfaker.uniform(state, 0.0, array_length(prefixes, 1)::float8, u); prefix := prefixes[1 + floor(u)::integer];
        raw := '+86' || prefix || rest;
        formatted := CASE variation WHEN 0 THEN '+86 ' || prefix || ' ' || left(rest,4) || ' ' || right(rest,4)
            WHEN 1 THEN prefix || '-' || left(rest,4) || '-' || right(rest,4) ELSE prefix || rest END;
    ELSIF locale_code = 'ko-KR' THEN
        raw := '+8210' || rest;
        formatted := CASE variation WHEN 0 THEN '+82 10-' || left(rest,4) || '-' || right(rest,4)
            WHEN 1 THEN '010-' || left(rest,4) || '-' || right(rest,4) ELSE '010' || rest END;
    ELSE RAISE EXCEPTION 'Unsupported locale' USING ERRCODE = '22023'; END IF;
    result := jsonb_build_object('formatted', formatted, 'e164', raw);
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.email(
    INOUT state bigint, IN stem text, IN seed_value bigint,
    IN position_value bigint, OUT email_address text
)
LANGUAGE plpgsql AS $$
DECLARE u double precision; domains text[] := ARRAY['example.com','example.net','example.org'];
BEGIN
    CALL sqlfaker.uniform(state, 0.0, 3.0, u);
    email_address := lower(left(stem, 35)) || '.' || seed_value || '.' || (position_value + 1) || '@' || domains[1 + floor(u)::integer];
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.generate_user(
    IN locale_code text, IN seed_value bigint, IN position_value bigint,
    IN catalog jsonb, OUT result jsonb
)
LANGUAGE plpgsql AS $$
DECLARE state bigint; person jsonb; location jsonb; geo jsonb; physical jsonb; telephone jsonb; mail text;
BEGIN
    IF seed_value IS NULL OR seed_value < 0 OR seed_value > 2147483647
       OR position_value IS NULL OR position_value < 0 OR position_value >= 1000000 THEN
        RAISE EXCEPTION 'Seed must be 0..2147483647 and position 0..999999' USING ERRCODE = '22023';
    END IF;
    IF catalog->>'code' IS DISTINCT FROM locale_code THEN
        RAISE EXCEPTION 'Catalog locale mismatch' USING ERRCODE = '22023';
    END IF;
    state := (('x' || substr(md5('sqlfaker-v1|' || locale_code || '|' || seed_value || '|' || position_value), 1, 15))::bit(60)::bigint % 2147483646) + 1;
    CALL sqlfaker.person_name(state, catalog, person);
    CALL sqlfaker.address(state, catalog, location);
    CALL sqlfaker.coordinates(state, geo);
    CALL sqlfaker.attributes(state, person->>'gender', physical);
    CALL sqlfaker.phone(state, locale_code, telephone);
    CALL sqlfaker.email(state, person->>'email_stem', seed_value, position_value, mail);
    result := (person - 'email_stem') || jsonb_build_object('locale', locale_code,
        'position', position_value, 'number', position_value + 1,
        'id', locale_code || '-' || seed_value || '-' || (position_value + 1),
        'address', location, 'coordinates', geo, 'physical', physical, 'phone', telephone, 'email', mail);
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.generate_batch(
    IN locale_code text, IN seed_value bigint, IN batch_index bigint,
    IN batch_size integer, OUT users jsonb
)
LANGUAGE plpgsql AS $$
DECLARE catalog jsonb; item jsonb; items jsonb[] := ARRAY[]::jsonb[];
        first_position bigint; i integer;
BEGIN
    IF batch_index IS NULL OR batch_index < 0 OR batch_index > 999999
       OR batch_size IS NULL OR batch_size < 1 OR batch_size > 1000 THEN
        RAISE EXCEPTION 'Batch index must be nonnegative; batch size must be 1..1000' USING ERRCODE = '22023';
    END IF;
    first_position := batch_index * batch_size;
    IF first_position + batch_size > 1000000 THEN
        RAISE EXCEPTION 'Requested batch exceeds 1,000,000 positions' USING ERRCODE = '22023';
    END IF;
    CALL sqlfaker.load_catalog(locale_code, catalog);
    FOR i IN 0..batch_size - 1 LOOP
        CALL sqlfaker.generate_user(locale_code, seed_value, first_position + i, catalog, item);
        items := array_append(items, item);
    END LOOP;
    users := to_jsonb(items);
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.catalog_info(OUT info jsonb)
LANGUAGE plpgsql AS $$
BEGIN
    SELECT jsonb_build_object('version', (SELECT version FROM sqlfaker.dataset WHERE id=1),
        'locales', coalesce(jsonb_agg(x ORDER BY x->>'code'), '[]'::jsonb)) INTO info FROM (
        SELECT to_jsonb(l) || jsonb_build_object(
            'family_names', (SELECT count(*) FROM sqlfaker.names n WHERE n.locale=l.code AND kind='family'),
            'given_names', (SELECT count(DISTINCT value) FROM sqlfaker.names n WHERE n.locale=l.code AND kind='given'),
            'places', (SELECT count(*) FROM sqlfaker.places p WHERE p.locale=l.code),
            'streets', (SELECT count(*) FROM sqlfaker.streets s WHERE s.locale=l.code)) AS x
        FROM sqlfaker.locales l
    ) lists;
END;
$$;

CREATE OR REPLACE PROCEDURE sqlfaker.benchmark(
    IN locale_code text, IN seed_value bigint, IN user_count integer,
    IN batch_size integer, OUT result jsonb
)
LANGUAGE plpgsql AS $$
DECLARE started timestamptz; elapsed double precision; users jsonb; page integer;
        generated integer := 0; chunk integer; checksum text := ''; total_bytes bigint := 0;
BEGIN
    IF user_count IS NULL OR user_count < 1 OR user_count > 1000000 OR batch_size IS NULL OR batch_size < 1 OR batch_size > 1000 THEN
        RAISE EXCEPTION 'Count must be 1..1000000 and batch size 1..1000' USING ERRCODE='22023';
    END IF;
    -- Warm the same procedure path before starting the timer.
    CALL sqlfaker.generate_batch(locale_code, seed_value, 0, batch_size, users);
    started := clock_timestamp();
    FOR page IN 0..(user_count - 1) / batch_size LOOP
        chunk := least(batch_size, user_count - generated);
        IF chunk = batch_size THEN
            CALL sqlfaker.generate_batch(locale_code, seed_value, page, batch_size, users);
        ELSE
            -- Keep absolute positions correct when the final chunk is shorter.
            DECLARE catalog jsonb; item jsonb; tail jsonb[] := ARRAY[]::jsonb[]; j integer;
            BEGIN
                CALL sqlfaker.load_catalog(locale_code, catalog);
                FOR j IN generated..user_count - 1 LOOP
                    CALL sqlfaker.generate_user(locale_code, seed_value, j, catalog, item);
                    tail := array_append(tail, item);
                END LOOP;
                users := to_jsonb(tail);
            END;
        END IF;
        generated := generated + jsonb_array_length(users);
        total_bytes := total_bytes + octet_length(users::text);
        checksum := md5(checksum || users::text);
    END LOOP;
    elapsed := extract(epoch FROM clock_timestamp() - started);
    result := jsonb_build_object('locale', locale_code, 'seed', seed_value, 'users', generated,
        'batch_size', batch_size, 'seconds', elapsed,
        'users_per_second', round((generated / greatest(elapsed, .000001))::numeric, 2),
        'json_bytes', total_bytes, 'checksum', checksum, 'postgres_version', version(),
        'scope', 'SQL batch generation, JSON serialization and checksum; excludes network transfer');
END;
$$;

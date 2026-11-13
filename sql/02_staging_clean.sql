SET search_path = project_staging;

DROP TABLE IF EXISTS cleaning_log;
CREATE TABLE cleaning_log (
    log_id SERIAL PRIMARY KEY,
    table_name TEXT,
    action TEXT,
    rows_affected BIGINT,
    logged_at TIMESTAMP DEFAULT now()
);

WITH d AS (
    DELETE FROM stg_circuits a 
    USING stg_circuits b 
    WHERE a.circuit_id = b.circuit_id AND a.ctid > b.ctid 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_circuits', 'remove duplicates', count(*) FROM d;

WITH d AS (
    DELETE FROM stg_constructors a 
    USING stg_constructors b 
    WHERE a.constructor_id = b.constructor_id AND a.ctid > b.ctid 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_constructors', 'remove duplicates', count(*) FROM d;

WITH d AS (
    DELETE FROM stg_drivers a 
    USING stg_drivers b 
    WHERE a.driver_id = b.driver_id AND a.ctid > b.ctid 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_drivers', 'remove duplicates', count(*) FROM d;

WITH d AS (
    DELETE FROM stg_races a 
    USING stg_races b 
    WHERE a.race_id = b.race_id AND a.ctid > b.ctid 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_races', 'remove duplicates', count(*) FROM d;

WITH d AS (
    DELETE FROM stg_status a 
    USING stg_status b 
    WHERE a.status_id = b.status_id AND a.ctid > b.ctid 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_status', 'remove duplicates', count(*) FROM d;

WITH d AS (
    DELETE FROM stg_results a 
    USING stg_results b 
    WHERE a.result_id = b.result_id AND a.ctid > b.ctid 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_results', 'remove duplicates', count(*) FROM d;

WITH d AS (
    DELETE FROM stg_driver_standings a 
    USING stg_driver_standings b 
    WHERE a.driver_standings_id = b.driver_standings_id AND a.ctid > b.ctid 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_driver_standings', 'remove duplicates', count(*) FROM d;

WITH u AS (
    UPDATE stg_circuits SET 
        circuit_ref = lower(NULLIF(btrim(circuit_ref), '')), 
        name = NULLIF(regexp_replace(btrim(name), '\s+', ' ', 'g'), ''), 
        location = NULLIF(regexp_replace(btrim(location), '\s+', ' ', 'g'), ''), 
        country = NULLIF(btrim(country), '') 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_circuits', 'standardize text', count(*) FROM u;

WITH u AS (
    UPDATE stg_constructors SET 
        constructor_ref = lower(NULLIF(btrim(constructor_ref), '')), 
        name = NULLIF(regexp_replace(btrim(name), '\s+', ' ', 'g'), ''), 
        nationality = initcap(NULLIF(btrim(nationality), '')) 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_constructors', 'standardize text', count(*) FROM u;

WITH u AS (
    UPDATE stg_drivers SET 
        driver_ref = lower(NULLIF(btrim(driver_ref), '')), 
        code = upper(NULLIF(btrim(code), '')), 
        forename = NULLIF(regexp_replace(btrim(forename), '\s+', ' ', 'g'), ''), 
        surname = NULLIF(regexp_replace(btrim(surname), '\s+', ' ', 'g'), ''), 
        nationality = initcap(NULLIF(btrim(nationality), '')) 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_drivers', 'standardize text', count(*) FROM u;

WITH u AS (
    UPDATE stg_races SET 
        name = NULLIF(regexp_replace(btrim(name), '\s+', ' ', 'g'), '') 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_races', 'standardize text', count(*) FROM u;

WITH u AS (
    UPDATE stg_status SET 
        status = NULLIF(regexp_replace(btrim(status), '\s+', ' ', 'g'), '') 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_status', 'standardize text', count(*) FROM u;

WITH u AS (
    UPDATE stg_results SET 
        points = 0 
    WHERE points IS NULL 
    RETURNING 1
)
INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'stg_results', 'NULL points set to 0', count(*) FROM u;

ALTER TABLE stg_circuits
    ALTER COLUMN circuit_id TYPE INT USING circuit_id::int,
    ALTER COLUMN lat TYPE NUMERIC(9,6) USING NULLIF(lat::text, '')::numeric,
    ALTER COLUMN lng TYPE NUMERIC(9,6) USING NULLIF(lng::text, '')::numeric,
    ALTER COLUMN alt TYPE INT USING round(NULLIF(alt::text, '')::numeric)::int;

ALTER TABLE stg_constructors
    ALTER COLUMN constructor_id TYPE INT USING constructor_id::int;

ALTER TABLE stg_drivers
    ALTER COLUMN driver_id TYPE INT USING driver_id::int,
    ALTER COLUMN number TYPE SMALLINT USING round(NULLIF(number::text, '')::numeric)::smallint,
    ALTER COLUMN dob TYPE DATE USING NULLIF(dob::text, '')::date;

ALTER TABLE stg_races
    ALTER COLUMN race_id TYPE INT USING race_id::int,
    ALTER COLUMN year TYPE SMALLINT USING year::smallint,
    ALTER COLUMN round TYPE SMALLINT USING round::smallint,
    ALTER COLUMN circuit_id TYPE INT USING circuit_id::int,
    ALTER COLUMN "date" TYPE DATE USING NULLIF("date"::text, '')::date,
    ALTER COLUMN "time" TYPE TIME USING NULLIF("time"::text, '')::time;

ALTER TABLE stg_status
    ALTER COLUMN status_id TYPE INT USING status_id::int;

ALTER TABLE stg_results
    ALTER COLUMN result_id TYPE INT USING result_id::int,
    ALTER COLUMN race_id TYPE INT USING race_id::int,
    ALTER COLUMN driver_id TYPE INT USING driver_id::int,
    ALTER COLUMN constructor_id TYPE INT USING constructor_id::int,
    ALTER COLUMN number TYPE SMALLINT USING round(NULLIF(number::text, '')::numeric)::smallint,
    ALTER COLUMN grid TYPE SMALLINT USING round(NULLIF(grid::text, '')::numeric)::smallint,
    ALTER COLUMN "position" TYPE SMALLINT USING round(NULLIF("position"::text, '')::numeric)::smallint,
    ALTER COLUMN position_order TYPE SMALLINT USING round(NULLIF(position_order::text, '')::numeric)::smallint,
    ALTER COLUMN points TYPE NUMERIC(5,2) USING NULLIF(points::text, '')::numeric,
    ALTER COLUMN laps TYPE SMALLINT USING round(NULLIF(laps::text, '')::numeric)::smallint,
    ALTER COLUMN milliseconds TYPE BIGINT USING round(NULLIF(milliseconds::text, '')::numeric)::bigint,
    ALTER COLUMN fastest_lap TYPE SMALLINT USING round(NULLIF(fastest_lap::text, '')::numeric)::smallint,
    ALTER COLUMN "rank" TYPE SMALLINT USING round(NULLIF("rank"::text, '')::numeric)::smallint,
    ALTER COLUMN fastest_lap_speed TYPE NUMERIC(6,3) USING NULLIF(fastest_lap_speed::text, '')::numeric,
    ALTER COLUMN status_id TYPE INT USING status_id::int;

ALTER TABLE stg_driver_standings
    ALTER COLUMN driver_standings_id TYPE INT USING driver_standings_id::int,
    ALTER COLUMN race_id TYPE INT USING race_id::int,
    ALTER COLUMN driver_id TYPE INT USING driver_id::int,
    ALTER COLUMN points TYPE NUMERIC(6,2) USING NULLIF(points::text, '')::numeric,
    ALTER COLUMN "position" TYPE SMALLINT USING round(NULLIF("position"::text, '')::numeric)::smallint,
    ALTER COLUMN wins TYPE SMALLINT USING round(NULLIF(wins::text, '')::numeric)::smallint;

INSERT INTO cleaning_log(table_name, action, rows_affected) 
SELECT 'ALL', 'data types converted', 7;

INSERT INTO cleaning_log(table_name, action, rows_affected)
SELECT 'stg_circuits', 'final row count', count(*) FROM stg_circuits UNION ALL
SELECT 'stg_constructors', 'final row count', count(*) FROM stg_constructors UNION ALL
SELECT 'stg_drivers', 'final row count', count(*) FROM stg_drivers UNION ALL
SELECT 'stg_races', 'final row count', count(*) FROM stg_races UNION ALL
SELECT 'stg_status', 'final row count', count(*) FROM stg_status UNION ALL
SELECT 'stg_results', 'final row count', count(*) FROM stg_results UNION ALL
SELECT 'stg_driver_standings', 'final row count', count(*) FROM stg_driver_standings;

SELECT * FROM cleaning_log ORDER BY log_id;
SET search_path = project_dw;

TRUNCATE fact_race_results, fact_driver_standings, fact_driver_season_entry,
         dim_date, dim_race, dim_season, dim_driver, dim_constructor,
         dim_circuit, dim_status RESTART IDENTITY CASCADE;

INSERT INTO dim_date(date_key, full_date) VALUES (-1, DATE '1900-01-01');
INSERT INTO dim_race(race_key, race_id, race_name) VALUES (-1, -1, 'Unknown');
INSERT INTO dim_season(season_key, season_year, era_label) VALUES (-1, 0, 'Unknown');
INSERT INTO dim_driver(driver_key, driver_id, full_name) VALUES (-1, -1, 'Unknown');
INSERT INTO dim_constructor(constructor_key, constructor_id, constructor_name) VALUES (-1, -1, 'Unknown');
INSERT INTO dim_circuit(circuit_key, circuit_id, circuit_name) VALUES (-1, -1, 'Unknown');
INSERT INTO dim_status(status_key, status_id, status_text, status_category) VALUES (-1, -1, 'Unknown', 'Unknown');

INSERT INTO dim_date (date_key, full_date, day, month, month_name, quarter, year, decade, weekday)
SELECT to_char(d, 'YYYYMMDD')::int,
       d,
       EXTRACT(day FROM d)::smallint,
       EXTRACT(month FROM d)::smallint,
       to_char(d, 'FMMonth'),
       EXTRACT(quarter FROM d)::smallint,
       EXTRACT(year FROM d)::smallint,
       (floor(EXTRACT(year FROM d) / 10) * 10)::smallint,
       to_char(d, 'FMDay')
FROM (SELECT DISTINCT "date" AS d FROM project_staging.stg_races WHERE "date" IS NOT NULL) x
ORDER BY d;

INSERT INTO dim_race (race_id, race_name, round, season_year, race_date)
SELECT race_id, name, round, year, "date"
FROM project_staging.stg_races
ORDER BY race_id;

INSERT INTO dim_season (season_year, era_label)
SELECT y,
       CASE
           WHEN y <= 1960 THEN 'Pioneer era'
           WHEN y <= 1976 THEN 'Rear-engine and aerodynamics era'
           WHEN y <= 1988 THEN 'Turbo era'
           WHEN y <= 2005 THEN 'Naturally aspirated era'
           WHEN y <= 2013 THEN 'V8 era'
           ELSE 'Hybrid era'
       END
FROM (SELECT DISTINCT year AS y FROM project_staging.stg_races WHERE year IS NOT NULL) x
ORDER BY y;

INSERT INTO dim_driver (driver_id, driver_ref, full_name, driver_code, date_of_birth, nationality)
SELECT driver_id, driver_ref, forename || ' ' || surname, code, dob, nationality
FROM project_staging.stg_drivers
ORDER BY driver_id;

INSERT INTO dim_constructor (constructor_id, constructor_ref, constructor_name, nationality)
SELECT constructor_id, constructor_ref, name, nationality
FROM project_staging.stg_constructors
ORDER BY constructor_id;

INSERT INTO dim_circuit (circuit_id, circuit_ref, circuit_name, location, country, latitude, longitude, altitude)
SELECT circuit_id, circuit_ref, name, location, country, lat, lng, alt
FROM project_staging.stg_circuits
ORDER BY circuit_id;

INSERT INTO dim_status (status_id, status_text, status_category)
SELECT status_id, status,
       CASE
           WHEN status = 'Finished' THEN 'Finished'
           WHEN status ~ '^\+[0-9]+ Laps?$' THEN 'Lapped'
           WHEN status IN ('Accident', 'Collision', 'Collision damage', 'Spun off') THEN 'Accident/Collision'
           WHEN status ~* '(engine|gearbox|transmission|clutch|hydraulic|electr|brake|suspension|overheat|oil|fuel|water|radiator|exhaust|turbo|throttle|steering|wheel|shaft|differential|power|mechanical|pneumatic|puncture|tyre|handling|vibration|technical|ignition|magneto|battery|cooling|coolant|pump|piston|injection|spark|alternator|supercharger|drivetrain|axle|wing|leak|pressure|fire|crank|conrod|chassis|undertray|cv joint)' THEN 'Mechanical Failure'
           ELSE 'Other'
       END
FROM project_staging.stg_status
ORDER BY status_id;
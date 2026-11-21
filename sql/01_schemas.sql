CREATE SCHEMA IF NOT EXISTS project_staging;
CREATE SCHEMA IF NOT EXISTS project_dw;
CREATE SCHEMA IF NOT EXISTS project_reporting;

SET search_path = project_staging;

DROP TABLE IF EXISTS stg_circuits, stg_constructors, stg_drivers, stg_races,
                     stg_status, stg_results, stg_driver_standings;

CREATE TABLE stg_circuits (
    circuit_id      TEXT,
    circuit_ref     TEXT,
    name            TEXT,
    location        TEXT,
    country         TEXT,
    lat             TEXT,
    lng             TEXT,
    alt             TEXT,
    url             TEXT
);

CREATE TABLE stg_constructors (
    constructor_id  TEXT,
    constructor_ref TEXT,
    name            TEXT,
    nationality     TEXT,
    url             TEXT
);

CREATE TABLE stg_drivers (
    driver_id       TEXT,
    driver_ref      TEXT,
    number          TEXT,
    code            TEXT,
    forename        TEXT,
    surname         TEXT,
    dob             TEXT,
    nationality     TEXT,
    url             TEXT
);

CREATE TABLE stg_races (
    race_id         TEXT,
    year            TEXT,
    round           TEXT,
    circuit_id      TEXT,
    name            TEXT,
    "date"          TEXT,
    "time"          TEXT,
    url             TEXT
);

CREATE TABLE stg_status (
    status_id       TEXT,
    status          TEXT
);

CREATE TABLE stg_results (
    result_id           TEXT,
    race_id             TEXT,
    driver_id           TEXT,
    constructor_id      TEXT,
    number              TEXT,
    grid                TEXT,
    "position"          TEXT,
    position_text       TEXT,
    position_order      TEXT,
    points              TEXT,
    laps                TEXT,
    "time"              TEXT,
    milliseconds        TEXT,
    fastest_lap         TEXT,
    "rank"              TEXT,
    fastest_lap_time    TEXT,
    fastest_lap_speed   TEXT,
    status_id           TEXT
);

CREATE TABLE stg_driver_standings (
    driver_standings_id TEXT,
    race_id             TEXT,
    driver_id           TEXT,
    points              TEXT,
    "position"          TEXT,
    position_text       TEXT,
    wins                TEXT
);

RESET search_path;

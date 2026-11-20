SET search_path = project_dw;

DROP TABLE IF EXISTS dq_log;
CREATE TABLE dq_log (
    check_id SERIAL PRIMARY KEY,
    category TEXT,
    check_name TEXT,
    expected TEXT,
    actual NUMERIC,
    status TEXT,
    checked_at TIMESTAMP DEFAULT now()
);

CREATE OR REPLACE FUNCTION log_check(p_cat TEXT, p_name TEXT, p_expected TEXT, p_actual NUMERIC, p_ok BOOLEAN)
RETURNS VOID AS $$
    INSERT INTO dq_log(category, check_name, expected, actual, status)
    VALUES (p_cat, p_name, p_expected, p_actual, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END);
$$ LANGUAGE sql;

SELECT log_check('Completeness', 'dim_driver rows with NULL full_name', '0', (SELECT count(*) FROM dim_driver WHERE full_name IS NULL), (SELECT count(*) FROM dim_driver WHERE full_name IS NULL) = 0);
SELECT log_check('Completeness', 'dim_constructor rows with NULL constructor_name', '0', (SELECT count(*) FROM dim_constructor WHERE constructor_name IS NULL), (SELECT count(*) FROM dim_constructor WHERE constructor_name IS NULL) = 0);
SELECT log_check('Completeness', 'dim_circuit rows with NULL circuit_name', '0', (SELECT count(*) FROM dim_circuit WHERE circuit_name IS NULL), (SELECT count(*) FROM dim_circuit WHERE circuit_name IS NULL) = 0);
SELECT log_check('Completeness', 'dim_race rows with NULL race_name', '0', (SELECT count(*) FROM dim_race WHERE race_name IS NULL), (SELECT count(*) FROM dim_race WHERE race_name IS NULL) = 0);
SELECT log_check('Completeness', 'dim_status rows with NULL status_category', '0', (SELECT count(*) FROM dim_status WHERE status_category IS NULL), (SELECT count(*) FROM dim_status WHERE status_category IS NULL) = 0);
SELECT log_check('Completeness', 'dim_season rows with NULL era_label', '0', (SELECT count(*) FROM dim_season WHERE era_label IS NULL), (SELECT count(*) FROM dim_season WHERE era_label IS NULL) = 0);
SELECT log_check('Completeness', 'fact_race_results rows with NULL points', '0', (SELECT count(*) FROM fact_race_results WHERE points IS NULL), (SELECT count(*) FROM fact_race_results WHERE points IS NULL) = 0);
SELECT log_check('Completeness', 'fact_race_results rows with NULL is_dnf', '0', (SELECT count(*) FROM fact_race_results WHERE is_dnf IS NULL), (SELECT count(*) FROM fact_race_results WHERE is_dnf IS NULL) = 0);

SELECT log_check('Completeness', 'INFO: NULL race_time_ms', 'expected NULLs', (SELECT count(*) FROM fact_race_results WHERE race_time_ms IS NULL), true);
SELECT log_check('Completeness', 'INFO: NULL fastest_lap_speed', 'expected NULLs', (SELECT count(*) FROM fact_race_results WHERE fastest_lap_speed IS NULL), true);
SELECT log_check('Completeness', 'INFO: NULL finish_position', 'expected NULLs', (SELECT count(*) FROM fact_race_results WHERE finish_position IS NULL), true);

SELECT log_check('Accuracy', 'fact_race_results rows = stg_results rows', (SELECT count(*) FROM project_staging.stg_results)::text, (SELECT count(*) FROM fact_race_results), (SELECT count(*) FROM fact_race_results) = (SELECT count(*) FROM project_staging.stg_results));
SELECT log_check('Accuracy', 'SUM(points) fact = SUM(points) staging', (SELECT sum(points) FROM project_staging.stg_results)::text, (SELECT sum(points) FROM fact_race_results), (SELECT sum(points) FROM fact_race_results) = (SELECT sum(points) FROM project_staging.stg_results));
SELECT log_check('Accuracy', 'SUM(is_win) = staging rows with position = 1', (SELECT count(*) FROM project_staging.stg_results WHERE "position" = 1)::text, (SELECT sum(is_win) FROM fact_race_results), (SELECT sum(is_win) FROM fact_race_results) = (SELECT count(*) FROM project_staging.stg_results WHERE "position" = 1));
SELECT log_check('Accuracy', 'SUM(is_podium) = staging rows with position <= 3', (SELECT count(*) FROM project_staging.stg_results WHERE "position" <= 3)::text, (SELECT sum(is_podium) FROM fact_race_results), (SELECT sum(is_podium) FROM fact_race_results) = (SELECT count(*) FROM project_staging.stg_results WHERE "position" <= 3));
SELECT log_check('Accuracy', 'is_dnf consistency', '0', (SELECT count(*) FROM fact_race_results f JOIN dim_status s USING (status_key) WHERE (f.is_dnf = 1 AND s.status_category IN ('Finished', 'Lapped')) OR (f.is_dnf = 0 AND s.status_category NOT IN ('Finished', 'Lapped'))), (SELECT count(*) FROM fact_race_results f JOIN dim_status s USING (status_key) WHERE (f.is_dnf = 1 AND s.status_category IN ('Finished', 'Lapped')) OR (f.is_dnf = 0 AND s.status_category NOT IN ('Finished', 'Lapped'))) = 0);
SELECT log_check('Accuracy', 'fact_driver_standings rows = stg_driver_standings rows', (SELECT count(*) FROM project_staging.stg_driver_standings)::text, (SELECT count(*) FROM fact_driver_standings), (SELECT count(*) FROM fact_driver_standings) = (SELECT count(*) FROM project_staging.stg_driver_standings));
SELECT log_check('Accuracy', 'fact_driver_season_entry rows match staging distinct', (SELECT count(*) FROM (SELECT DISTINCT ra.year, r.driver_id, r.constructor_id FROM project_staging.stg_results r JOIN project_staging.stg_races ra USING (race_id)) x)::text, (SELECT count(*) FROM fact_driver_season_entry), (SELECT count(*) FROM fact_driver_season_entry) = (SELECT count(*) FROM (SELECT DISTINCT ra.year, r.driver_id, r.constructor_id FROM project_staging.stg_results r JOIN project_staging.stg_races ra USING (race_id)) x));
SELECT log_check('Accuracy', 'Races with more than one winner', '0', (SELECT count(*) FROM (SELECT race_key FROM fact_race_results GROUP BY race_key HAVING sum(is_win) > 1) x), (SELECT count(*) FROM (SELECT race_key FROM fact_race_results GROUP BY race_key HAVING sum(is_win) > 1) x) = 0);

DO $$
DECLARE
    r RECORD;
    n BIGINT;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('fact_race_results', 'race_key', 'dim_race'),
            ('fact_race_results', 'driver_key', 'dim_driver'),
            ('fact_race_results', 'date_key', 'dim_date'),
            ('fact_race_results', 'constructor_key', 'dim_constructor'),
            ('fact_race_results', 'circuit_key', 'dim_circuit'),
            ('fact_race_results', 'status_key', 'dim_status'),
            ('fact_driver_standings', 'race_key', 'dim_race'),
            ('fact_driver_standings', 'driver_key', 'dim_driver'),
            ('fact_driver_standings', 'date_key', 'dim_date'),
            ('fact_driver_season_entry', 'season_key', 'dim_season'),
            ('fact_driver_season_entry', 'driver_key', 'dim_driver'),
            ('fact_driver_season_entry', 'constructor_key', 'dim_constructor')
        ) v(f, c, d)
    LOOP
        EXECUTE format('SELECT count(*) FROM %I f LEFT JOIN %I d ON d.%I = f.%I WHERE d.%I IS NULL', r.f, r.d, r.c, r.c, r.c) INTO n;
        PERFORM log_check('Integrity', format('%s.%s rows with no matching %s', r.f, r.c, r.d), '0', n, n = 0);

        EXECUTE format('SELECT count(*) FROM %I WHERE %I = -1', r.f, r.c) INTO n;
        PERFORM log_check('Integrity', format('%s.%s mapped to Unknown (-1)', r.f, r.c), '0', n, n = 0);
    END LOOP;
END $$;

SELECT log_check('Integrity', 'fact_race_results duplicate (race_key, driver_key)', '0', (SELECT count(*) - count(DISTINCT (race_key, driver_key)) FROM fact_race_results), (SELECT count(*) - count(DISTINCT (race_key, driver_key)) FROM fact_race_results) = 0);
SELECT log_check('Integrity', 'fact_driver_standings duplicate (race_key, driver_key)', '0', (SELECT count(*) - count(DISTINCT (race_key, driver_key)) FROM fact_driver_standings), (SELECT count(*) - count(DISTINCT (race_key, driver_key)) FROM fact_driver_standings) = 0);
SELECT log_check('Integrity', 'dim_driver duplicate natural keys', '0', (SELECT count(*) - count(DISTINCT driver_id) FROM dim_driver), (SELECT count(*) - count(DISTINCT driver_id) FROM dim_driver) = 0);

SELECT log_check('Volume', 'fact_race_results rows >= 10000', '>= 10000', (SELECT count(*) FROM fact_race_results), (SELECT count(*) FROM fact_race_results) >= 10000);
SELECT log_check('Volume', 'fact_driver_standings rows >= 10000', '>= 10000', (SELECT count(*) FROM fact_driver_standings), (SELECT count(*) FROM fact_driver_standings) >= 10000);
SELECT log_check('Volume', 'total dimension records >= 100', '>= 100', (SELECT (SELECT count(*) FROM dim_date) + (SELECT count(*) FROM dim_race) + (SELECT count(*) FROM dim_season) + (SELECT count(*) FROM dim_driver) + (SELECT count(*) FROM dim_constructor) + (SELECT count(*) FROM dim_circuit) + (SELECT count(*) FROM dim_status)), (SELECT (SELECT count(*) FROM dim_date) + (SELECT count(*) FROM dim_race) + (SELECT count(*) FROM dim_season) + (SELECT count(*) FROM dim_driver) + (SELECT count(*) FROM dim_constructor) + (SELECT count(*) FROM dim_circuit) + (SELECT count(*) FROM dim_status)) >= 100);

SELECT category, status, count(*) FROM dq_log GROUP BY category, status ORDER BY category, status;
SELECT * FROM dq_log ORDER BY check_id;
SET search_path = project_dw;

TRUNCATE fact_race_results, fact_driver_standings, fact_driver_season_entry;

INSERT INTO fact_race_results (
    race_key, driver_key, date_key, constructor_key, circuit_key, status_key, result_id,
    points, laps_completed, is_win, is_podium, is_points_finish, is_dnf,
    grid_position, finish_position, race_time_ms, fastest_lap_speed)
SELECT
    COALESCE(dr.race_key, -1),
    COALESCE(dd.driver_key, -1),
    COALESCE(dt.date_key, -1),
    COALESCE(dc.constructor_key, -1),
    COALESCE(dci.circuit_key, -1),
    COALESCE(ds.status_key, -1),
    s.result_id,
    s.points,
    s.laps,
    CASE WHEN s."position" = 1 THEN 1 ELSE 0 END,
    CASE WHEN s."position" <= 3 THEN 1 ELSE 0 END,
    CASE WHEN s.points > 0 THEN 1 ELSE 0 END,
    CASE WHEN COALESCE(ds.status_category, 'Other') IN ('Finished', 'Lapped') THEN 0 ELSE 1 END,
    s.grid,
    s."position",
    s.milliseconds,
    s.fastest_lap_speed
FROM (SELECT DISTINCT ON (race_id, driver_id) *
      FROM project_staging.stg_results
      ORDER BY race_id, driver_id, position_order, result_id) s
LEFT JOIN project_staging.stg_races sr ON sr.race_id = s.race_id
LEFT JOIN dim_race dr ON dr.race_id = s.race_id
LEFT JOIN dim_driver dd ON dd.driver_id = s.driver_id
LEFT JOIN dim_date dt ON dt.full_date = sr."date"
LEFT JOIN dim_constructor dc ON dc.constructor_id = s.constructor_id
LEFT JOIN dim_circuit dci ON dci.circuit_id = sr.circuit_id
LEFT JOIN dim_status ds ON ds.status_id = s.status_id;

INSERT INTO fact_driver_standings (
    race_key, driver_key, date_key, cumulative_points, cumulative_wins, standing_position)
SELECT
    COALESCE(dr.race_key, -1),
    COALESCE(dd.driver_key, -1),
    COALESCE(dt.date_key, -1),
    s.points,
    s.wins,
    s."position"
FROM (SELECT DISTINCT ON (race_id, driver_id) *
      FROM project_staging.stg_driver_standings
      ORDER BY race_id, driver_id, driver_standings_id) s
LEFT JOIN project_staging.stg_races sr ON sr.race_id = s.race_id
LEFT JOIN dim_race dr ON dr.race_id = s.race_id
LEFT JOIN dim_driver dd ON dd.driver_id = s.driver_id
LEFT JOIN dim_date dt ON dt.full_date = sr."date";

INSERT INTO fact_driver_season_entry (season_key, driver_key, constructor_key)
SELECT DISTINCT
    COALESCE(se.season_key, -1),
    COALESCE(dd.driver_key, -1),
    COALESCE(dc.constructor_key, -1)
FROM project_staging.stg_results r
LEFT JOIN project_staging.stg_races sr ON sr.race_id = r.race_id
LEFT JOIN dim_season se ON se.season_year = sr.year
LEFT JOIN dim_driver dd ON dd.driver_id = r.driver_id
LEFT JOIN dim_constructor dc ON dc.constructor_id = r.constructor_id;
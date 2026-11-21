# Formula 1 Analytics Data Warehouse

**DL3004 Final Project: Phase 1 (Dimensional Design) and Phase 2 (Physical Data Warehouse & ETL Pipeline)**

A Kimball-style data warehouse for Formula 1 race and championship data from 1950 onward. A Python + SQL pipeline loads the Ergast Formula 1 World Championship CSV files into PostgreSQL, cleans them in a staging layer and builds a star schema (3 fact tables, 7 dimensions) that answers 10 business questions about drivers, constructors, circuits and seasons.

| Roll No | Team member |
|---|---|
| 24L-2580 | Sanan Zahid |
| 24L-2525 | Munam Ansari |
| 24L-2593 | Noyan Siddiqui |
| 24L-2542 | Salman Ali |

**Contents:** [Phase 1: Design](#phase-1--business-analysis-and-dimensional-design) · [Phase 2: Implementation](#phase-2--physical-data-warehouse-and-etl-pipeline) · [Setup and run](#29-setup-and-run) · [Documents](#212-documents)

---

# Phase 1 – Business Analysis and Dimensional Design

Phase 1 designed the model around business questions rather than copying the source tables. All Phase 1 documents are in [`docs/phase1/`](docs/phase1).

## 1.1 Problem, Objectives and Scope

The Ergast data is spread over many linked CSV files. Even a simple question such as "which circuits have the highest retirement rate?" needs several joins, missing-value handling and a definition of "retirement", repeated for every new question. The goal is one consistent structure for fast, repeatable analysis.

- **Objectives:** measure driver and constructor performance (BO1), explain the effect of grid position, circuit and reliability (BO2), follow a championship round by round (BO3), and understand driver-team lineups and field size (BO4).
- **Stakeholders:** team strategists and analysts, journalists and commentators, fans and statisticians.
- **In scope:** race results, driver standings and driver-constructor lineups for all seasons. **Out of scope:** constructor standings, lap times, pit stops, qualifying, real-time data.

| ID | Business requirement | Questions |
|---|---|---|
| BR1 | Count and compare wins, podiums and points by driver and constructor, by season, decade and nationality | BQ1, BQ2, BQ6 |
| BR2 | Compare starting grid position with finishing position | BQ3 |
| BR3 | Measure the DNF rate by circuit and show causes of retirement over time | BQ4, BQ5 |
| BR4 | Show how driver points and positions change after each race | BQ7, BQ8 |
| BR5 | Show how many constructors each driver raced for and how many drivers took part each season | BQ9, BQ10 |
| BR6 | Allow every result to be analysed by driver, constructor, circuit, race, date and finishing status | All |

## 1.2 The 10 Business Questions

| ID | Question | Fact table |
|---|---|---|
| BQ1 | Which drivers have won the most races, and how does this change by decade? | `fact_race_results` |
| BQ2 | How many points does each constructor score each season? | `fact_race_results` |
| BQ3 | How does grid position relate to finishing position? How often does pole become a win? | `fact_race_results` |
| BQ4 | Which circuits have the highest DNF rate? | `fact_race_results` |
| BQ5 | What are the most common causes of retirement, and how do they change by decade? | `fact_race_results` |
| BQ6 | Which countries have produced the most winners? | `fact_race_results` |
| BQ7 | How does the championship battle develop round by round? | `fact_driver_standings` |
| BQ8 | At which round do eventual champions first take the lead? | `fact_driver_standings` |
| BQ9 | For how many different constructors has each driver raced? | `fact_driver_season_entry` |
| BQ10 | How many drivers took part in each season? | `fact_driver_season_entry` |

## 1.3 Dimensional Model

The conceptual, logical and physical star schema diagrams are in [`docs/phase1/Star_Schema_F1_Analytics_Data_Warehouse.pdf`](docs/phase1/Star_Schema_F1_Analytics_Data_Warehouse.pdf); the column-level definitions are in the [Data Dictionary](docs/phase1/Data_Dictionary_F1_Analytics_Data_Warehouse.xlsx). Facts and dimensions in short:

| Fact table | Type | Grain: one row = … | Key |
|---|---|---|---|
| `fact_race_results` | Transaction | one driver's result in one race, for the constructor they drove for | `race_key, driver_key` |
| `fact_driver_standings` | Periodic snapshot | one driver's championship position and cumulative points after one race | `race_key, driver_key` |
| `fact_driver_season_entry` | Factless | one driver driving for one constructor in one season | `season_key, driver_key, constructor_key` |

| Dimension | Natural key | Hierarchy | SCD | Used by |
|---|---|---|:-:|---|
| `dim_date` | race date (`date_key` = yyyymmdd) | Day → Month → Quarter → Year → Decade | 0 | results, standings |
| `dim_race` | `raceId` | Race → Round → Season | 0 | results, standings |
| `dim_season` | `year` | Season → Era | 0 | lineup |
| `dim_driver` ★ | `driverId` | Driver → Nationality | 1 | all three |
| `dim_constructor` ★ | `constructorId` | Constructor → Nationality | 1 | results, lineup |
| `dim_circuit` | `circuitId` | Circuit → Location → Country | 1 | results |
| `dim_status` | `statusId` | Status → Category | 0 | results |

★ conformed dimension shared across fact tables (`dim_date` is shared by results and standings).

| Fact table | date | race | season | driver | constructor | circuit | status |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `fact_race_results` | ✓ | ✓ |  | ✓ | ✓ | ✓ | ✓ |
| `fact_driver_standings` | ✓ | ✓ |  | ✓ |  |  |  |
| `fact_driver_season_entry` |  |  | ✓ | ✓ | ✓ |  |  |

## 1.4 Measures and Business Rules

| Fact | Measures | Additivity |
|---|---|---|
| `fact_race_results` | `points`, `laps_completed`, `is_win`, `is_podium`, `is_points_finish`, `is_dnf` | Additive |
| | `grid_position`, `finish_position`, `race_time_ms`, `fastest_lap_speed` | Non-additive |
| | `result_id` (source id kept for traceability) | Degenerate dimension |
| `fact_driver_standings` | `cumulative_points`, `cumulative_wins` | Semi-additive (sum across drivers at one race, never across races) |
| | `standing_position` | Non-additive |
| `fact_driver_season_entry` | none: the row itself is the fact | Count rows |

- **Win** = finishing position 1; **podium** = position 1–3; **points finish** = points > 0.
- **DNF** = status category is not `Finished` and not `Lapped`.
- **Missing data** (for example race time and fastest lap in older seasons) stays `NULL` and is never estimated.
- **Unknown members:** every dimension has a row with key `-1`, so a missing foreign key never drops a fact row.
- **SCD:** driver, constructor and circuit changes are overwritten (Type 1); race, season, date and status are fixed (Type 0).

**Key design decisions:** the lineup fact includes constructor in its grain because a driver can race for two teams in one season; standings values are semi-additive (never summed across races); every dimension has an Unknown row (`-1`) so no fact row is lost; missing historical values stay `NULL`; Ergast is the single source of truth.

---

# Phase 2 – Physical Data Warehouse and ETL Pipeline

Phase 2 implements the Phase 1 design in PostgreSQL: source files → staging → warehouse → data quality validation, all started by one command.

## 2.1 Requirements Checklist

| Phase 2 requirement | Where it is implemented | Status |
|---|---|:-:|
| **Data source** (Kaggle; 100+ dimension rows, 10,000+ fact rows) | Ergast F1 dataset; 3,728 dimension rows, 27,587 + 35,813 fact rows | ✓ |
| **Architecture:** `project_staging` → `project_dw` → `project_reporting` | `sql/01_schemas.sql` | ✓ (reporting schema created, views are Phase 3) |
| **Staging layer:** remove duplicates, handle NULLs, standardise text, convert types | `etl/01_extract_load_staging.py`, `sql/02_staging_clean.sql`, `cleaning_log` | ✓ |
| **Dimensions with surrogate keys** (business key → surrogate key) | `sql/03_dw_ddl.sql`, `sql/04_load_dimensions.sql` | ✓ |
| **Fact loading** via business key → surrogate key lookup | `sql/05_load_facts.sql` | ✓ |
| **Data quality:** completeness, accuracy, integrity | `sql/06_data_quality.sql` → `project_dw.dq_log` (49 checks) | ✓ |
| **ETL orchestration** | `etl/run_pipeline.py` | ✓ |
| **Reports** (Data Cleaning, Data Quality) | [`docs/phase2/`](docs/phase2) | ✓ |

## 2.2 Architecture and Technology

```
 Kaggle CSVs        project_staging            project_dw              project_reporting
 (7 files)   ──►   stg_* tables (clean)  ──►  7 dimensions + 3 facts ──►  (Phase 3 views)
  data/            pandas load + SQL clean    surrogate keys, FKs        
                                                      │
                                                      ▼
                                              project_dw.dq_log (49 checks)
```

- **Database:** PostgreSQL 14+ · **ETL:** Python 3.9+ (pandas, SQLAlchemy, psycopg2, python-dotenv) and plain SQL
- **Load style:** batch, idempotent full reload (every step drops or truncates and rebuilds, so the pipeline can be re-run safely)
- **Credentials:** read from a `.env` file that is git-ignored

## 2.3 Pipeline Steps

`python etl/run_pipeline.py` runs these in order and stops on the first error (each SQL file runs in one transaction and is rolled back on failure).

| Step | File | Purpose |
|---|---|---|
| 1 | `sql/01_schemas.sql` | Create `project_staging`, `project_dw`, `project_reporting` |
| 2 | `etl/01_extract_load_staging.py` | Read the 7 CSVs and load them into `project_staging` |
| 3 | `sql/02_staging_clean.sql` | Deduplicate, standardise text, handle NULLs, cast types, write `cleaning_log` |
| 4 | `sql/03_dw_ddl.sql` | Create the 7 dimensions and 3 fact tables with keys and foreign keys |
| 5 | `sql/04_load_dimensions.sql` | Load dimensions with surrogate keys, Unknown members, derived attributes |
| 6 | `sql/05_load_facts.sql` | Load facts by looking up surrogate keys |
| 7 | `sql/06_data_quality.sql` | Run 49 validation checks and log them |

## 2.4 Staging Layer

**Extract and load** (`01_extract_load_staging.py`): the Ergast null marker `\N` becomes a real SQL `NULL`; columns are renamed to `snake_case` (`raceId` → `race_id`); only the needed columns of `races.csv` are kept; tables are replaced on every run.

| Staging table | Source file | Rows |
|---|---|--:|
| `stg_circuits` | `circuits.csv` | 78 |
| `stg_constructors` | `constructors.csv` | 214 |
| `stg_drivers` | `drivers.csv` | 867 |
| `stg_races` | `races.csv` | 1,172 |
| `stg_status` | `status.csv` | 141 |
| `stg_results` | `results.csv` | 27,678 |
| `stg_driver_standings` | `driver_standings.csv` | 35,813 |

**Cleaning** (`02_staging_clean.sql`), every action logged in `project_staging.cleaning_log` (table, action, rows affected, timestamp, final row counts):

| Rule | Detail |
|---|---|
| Remove duplicates | One row kept per natural key (`circuit_id`, `constructor_id`, `driver_id`, `race_id`, `status_id`, `result_id`, `driver_standings_id`), using `ctid` to pick the survivor |
| Standardise text | Trim, collapse repeated spaces, empty string → `NULL`; `*_ref` lower-case, driver `code` upper-case, `nationality` in title case |
| Handle NULLs | `NULL` points in results → `0`; values not recorded in early seasons (race time, fastest-lap speed, unclassified positions) stay `NULL` and are never estimated |
| Convert data types | Text → `INT`, `SMALLINT`, `NUMERIC(p,s)`, `BIGINT`, `DATE`, `TIME` on all 7 tables (for example `points` → `NUMERIC(5,2)`, `dob` → `DATE`) |

Text standardisation example: `"  british  "` and `"BRITISH"` both become `British` in `nationality`.

## 2.5 Dimensions and Surrogate Keys

Each dimension has an integer surrogate key generated by the database (`GENERATED BY DEFAULT AS IDENTITY`); the source id is kept as a unique natural key.

| Before (source) | After (warehouse) |
|---|---|
| `driver_id = 1` (Lewis Hamilton) | `driver_key = 1`, `driver_id = 1` |
| `constructor_id = 1` (McLaren) | `constructor_key = 1`, `constructor_id = 1` |
| race date `2008-03-16` | `date_key = 20080316` |

Load rules (`04_load_dimensions.sql`):
- **Unknown members:** every dimension gets a row with key `-1` and text `Unknown` before the real data, so a failed lookup never drops a fact row.
- **`dim_date`:** generated from the distinct race dates with day, month, month name, quarter, year, decade and weekday.
- **`dim_driver.full_name`:** forename + space + surname.
- **`dim_season.era_label`:** ≤1960 Pioneer · 1961–1976 Rear-engine and aerodynamics · 1977–1988 Turbo · 1989–2005 Naturally aspirated · 2006–2013 V8 · 2014+ Hybrid.
- **`dim_status.status_category`:** the 141 raw statuses are grouped by text rules:

| Category | Rule |
|---|---|
| Finished | `Finished` |
| Lapped | matches `+N Lap(s)` |
| Accident/Collision | Accident, Collision, Collision damage, Spun off |
| Mechanical Failure | text contains a mechanical term (engine, gearbox, brakes, hydraulics, electrical, suspension, overheating, …) |
| Other | everything else |

## 2.6 Fact Loading

Facts are loaded by mapping each business key to the surrogate key of its dimension with a `LEFT JOIN`; a missing match falls back to `-1`:

```sql
SELECT COALESCE(dr.race_key, -1),   COALESCE(dd.driver_key, -1),
       COALESCE(dc.constructor_key, -1), COALESCE(ds.status_key, -1), ...
FROM  (SELECT DISTINCT ON (race_id, driver_id) * FROM project_staging.stg_results
       ORDER BY race_id, driver_id, position_order, result_id) s
LEFT JOIN dim_race dr        ON dr.race_id        = s.race_id
LEFT JOIN dim_driver dd      ON dd.driver_id      = s.driver_id
LEFT JOIN dim_constructor dc ON dc.constructor_id = s.constructor_id
LEFT JOIN dim_status ds      ON ds.status_id      = s.status_id;
```

Derived measures in `fact_race_results`: `is_win` (position = 1), `is_podium` (position 1–3), `is_points_finish` (points > 0), `is_dnf` (status category is not Finished or Lapped). A `NULL` position gives 0 for win and podium.

| Warehouse table | Rows | Source rows | Note |
|---|--:|--:|---|
| `fact_race_results` | 27,587 | 27,678 | 91 duplicate driver-race records not loaded (one row per driver per race) |
| `fact_driver_standings` | 35,813 | 35,813 | all rows loaded |
| `fact_driver_season_entry` | 3,602 | n/a | distinct (season, driver, constructor) |
| All 7 dimensions | 3,728 | n/a | includes the 7 Unknown rows |

## 2.7 Data Quality Validation (`sql/06_data_quality.sql`)

Each check writes one row to `project_dw.dq_log` (`category`, `check_name`, `expected`, `actual`, `status`, `checked_at`). `INFO` checks record an expected count and always pass.

| Pillar | What it verifies | Checks | Passed |
|---|---|:-:|:-:|
| Completeness | Mandatory attributes are not NULL; historical NULLs counted (race time 70.1%, fastest lap 70.1%, finish position 39.4% of results) | 11 | 11 |
| Accuracy | Row counts, total points, wins and podiums reconcile to staging; `is_dnf` matches status category; one winner per race | 8 | 4 |
| Integrity | All 12 fact-to-dimension keys resolve and none map to Unknown; no duplicate keys | 27 | 27 |
| Volume | ≥10,000 rows in each large fact, ≥100 dimension rows | 3 | 3 |
| **Total** | | **49** | **45** |

All four flagged checks are explained in the [Data Quality Report](docs/phase2/Data_Quality_Report_F1_Analytics_Data_Warehouse.pdf):

| Check | Expected | Actual | Cause |
|---|--:|--:|---|
| Fact rows = staging rows | 27,678 | 27,587 | 91 duplicate driver-race records dropped by the one-row-per-driver-per-race grain |
| `SUM(points)` fact = staging | 57,631.05 | 57,624.89 | same cause (-6.16 points, 0.01%) |
| `SUM(is_podium)` = staging position ≤ 3 | 3,528 | 3,526 | same cause (-2 podiums) |
| Races with more than one winner | 0 | 3 | source data: three historical races have two drivers at position 1 |

Wins reconcile exactly (1,172). Read the log with `SELECT * FROM project_dw.dq_log ORDER BY check_id;`.

## 2.8 Repository Structure

```
.
├── etl/
│   ├── 01_extract_load_staging.py   # CSV → staging tables
│   └── run_pipeline.py              # runs all 7 steps, prints the DQ results
├── sql/
│   ├── 01_schemas.sql
│   ├── 02_staging_clean.sql
│   ├── 03_dw_ddl.sql
│   ├── 04_load_dimensions.sql
│   ├── 05_load_facts.sql
│   └── 06_data_quality.sql
├── docs/
│   ├── phase1/   # proposal, requirements, questions, fact/dimension, grain, star schema, data dictionary
│   └── phase2/   # data cleaning report, data quality report
├── data/         # NOT in the repo: you add the CSVs (git-ignored)
├── .env          # NOT in the repo: your DB credentials (git-ignored)
└── README.md
```

## 2.9 Setup and Run

Run everything on your own machine; you need a local PostgreSQL server.

1. **Install** Python 3.9+ and PostgreSQL 14+ (with pgAdmin or `psql`).
2. **Clone and install packages**
   ```bash
   git clone https://github.com/Salmanali005/F1-Analytics-Data-Warehouse.git
   cd F1-Analytics-Data-Warehouse
   python -m venv venv
   venv\Scripts\activate          # Windows  (macOS/Linux: source venv/bin/activate)
   pip install pandas sqlalchemy psycopg2-binary python-dotenv
   ```
3. **Create an empty database**
   ```sql
   CREATE DATABASE f1_warehouse;
   ```
4. **Get the dataset** (not stored in the repo). On Kaggle download *Formula 1 World Championship* by Rohan Rao (`rohanrao/formula-1-world-championship-1950-2020`) and copy these 7 files into a `data/` folder in the repo root: `circuits.csv`, `constructors.csv`, `drivers.csv`, `races.csv`, `results.csv`, `status.csv`, `driver_standings.csv`. Or with the Kaggle CLI:
   ```bash
   pip install kaggle
   kaggle datasets download -d rohanrao/formula-1-world-championship-1950-2020 -p data --unzip
   ```
   The other files in the download (lap times, pit stops, qualifying, constructor standings) are out of scope and ignored. Row counts in this README match the version of the dataset used for the reports (1,172 races); a newer version may give slightly different totals.
5. **Create `.env` in the repo root**
   ```
   DB_USER=postgres
   DB_PASSWORD=your_password
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=f1_warehouse
   ```
6. **Run from the repo root** (paths are relative)
   ```bash
   python etl/run_pipeline.py
   ```
   Expected: seven `[OK]` lines, the data quality table and `FAILED checks: 4`.
7. **Verify**
   ```sql
   SELECT COUNT(*) FROM project_dw.fact_race_results;                 -- 27587
   SELECT status, COUNT(*) FROM project_dw.dq_log GROUP BY status;    -- 45 PASS, 4 FAIL
   SELECT * FROM project_staging.cleaning_log ORDER BY log_id;
   ```

**Troubleshooting:** `FileNotFoundError: data/...csv` means you did not run from the repo root or a CSV is missing; `password authentication failed` or `connection refused` means check `.env` and that PostgreSQL is running; `database "f1_warehouse" does not exist` means create it first (step 3).

## 2.10 Example Queries

```sql
-- BQ1: drivers with the most wins
SELECT d.full_name, SUM(f.is_win) AS wins
FROM project_dw.fact_race_results f
JOIN project_dw.dim_driver d ON d.driver_key = f.driver_key
WHERE f.driver_key <> -1
GROUP BY d.full_name ORDER BY wins DESC LIMIT 10;

-- BQ4: circuits with the highest DNF rate (at least 100 entries)
SELECT c.circuit_name, COUNT(*) AS entries,
       ROUND(100.0 * SUM(f.is_dnf) / COUNT(*), 1) AS dnf_rate_pct
FROM project_dw.fact_race_results f
JOIN project_dw.dim_circuit c ON c.circuit_key = f.circuit_key
WHERE f.circuit_key <> -1
GROUP BY c.circuit_name HAVING COUNT(*) >= 100
ORDER BY dnf_rate_pct DESC LIMIT 10;
```

## 2.11 Limitations and Next Steps

- **Row reconciliation:** 91 of 27,678 result rows (0.33%) are not loaded because the grain is one row per driver per race. For an exact match, add `result_id` (already stored as a degenerate dimension) to the primary key and remove the `DISTINCT ON` filter.
- **Multi-winner races:** three historical races have two drivers at position 1 in the source; they are kept as recorded.
- **Status categories** come from text matching; new status values fall into `Other` until the rules are extended.
- There is no `requirements.txt` (install the packages in step 2) and the `project_reporting` schema has no objects yet.
- **Phase 3 (next):** analytical views in `project_reporting`, OLAP queries and Power BI reporting.

## 2.12 Documents

| Phase | Document |
|---|---|
| 1 | [Project Proposal](docs/phase1/Project_Proposal_F1_Analytics_Data_Warehouse.pdf) · [Business Requirements](docs/phase1/Business_Requirements_Document_F1_Analytics_Data_Warehouse.pdf) · [10 Business Questions](docs/phase1/10_Business_Questions_F1_Analytics_Data_Warehouse.pdf) · [Fact & Dimension Identification](docs/phase1/Fact_Dimension_Identification_F1_Analytics_Data_Warehouse.pdf) · [Grain Definition](docs/phase1/Grain_Definition_Document_F1_Analytics_Data_Warehouse.pdf) · [Star Schema](docs/phase1/Star_Schema_F1_Analytics_Data_Warehouse.pdf) · [Data Dictionary](docs/phase1/Data_Dictionary_F1_Analytics_Data_Warehouse.xlsx) |
| 2 | [Data Cleaning Report](docs/phase2/Data_Cleaning_Report_F1_Analytics_Data_Warehouse.pdf) · [Data Quality Report](docs/phase2/Data_Quality_Report_F1_Analytics_Data_Warehouse.pdf) |

**Data source:** Ergast Formula 1 World Championship dataset via Kaggle, accepted as the single source of truth; no outside data is added.

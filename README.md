# Formula 1 Analytics Data Warehouse

**DL3004 – Data Warehousing project: Phase 1 (Dimensional Design) and Phase 2 (Implementation & ETL)**

A Kimball-style dimensional data warehouse for Formula 1 race and championship data from 1950 onward. It turns the Ergast Formula 1 World Championship CSV files into a star schema in PostgreSQL, loaded by a Python + SQL pipeline, so questions about drivers, constructors, circuits and seasons become simple queries instead of multi-file joins.

| Roll No | Team member |
|---|---|
| 24L-2580 | Sanan Zahid |
| 24L-2525 | Munam Ansari |
| 24L-2593 | Noyan Siddiqui |
| 24L-2542 | Salman Ali |

**Contents**
- [Phase 1 – Business Analysis and Dimensional Design](#phase-1--business-analysis-and-dimensional-design)
- [Phase 2 – Implementation and ETL Pipeline](#phase-2--implementation-and-etl-pipeline)

---

# Phase 1 – Business Analysis and Dimensional Design

Phase 1 designed the warehouse around business processes and analytical questions, not around copying the source tables. It produced the Project Proposal, Business Requirements Document, 10 Business Questions, Fact & Dimension Identification, Grain Definition Document, Star Schema Diagram (conceptual, logical, physical) and the Data Dictionary.

## 1.1 Problem and Objectives

The Ergast data is spread across many linked CSV files. To answer even a simple question, such as "which circuits have the highest retirement rate", an analyst must join several files, clean missing values and decide what counts as a retirement, and repeat that for every new question. There is no single, consistent structure for fast, repeatable analysis.

**Project objectives**
- Design a dimensional model for F1 race and championship data using the Kimball approach.
- Identify business processes, declare the grain of each fact table and choose suitable fact types.
- Define dimensions, hierarchies, natural keys and surrogate keys.
- Answer at least 10 analytical questions on drivers, constructors, circuits and seasons.
- Document the model with a conceptual, logical and physical schema and a data dictionary.

## 1.2 Business Requirements

| ID | Business objective |
|---|---|
| BO1 | Measure driver and constructor performance (wins, podiums, points) across seasons and eras |
| BO2 | Understand how grid position, circuit and reliability affect race outcomes |
| BO3 | Track how a championship develops over a season |
| BO4 | Understand the driver-team structure: who drove for whom, and how large the field was |

**Stakeholders:** team strategists and performance analysts, sports journalists and commentators, fans and statisticians, and the data warehouse team.

| ID | Requirement | Questions |
|---|---|---|
| BR1 | Count and compare wins, podiums and points by driver and constructor, by season, decade and nationality | BQ1, BQ2, BQ6 |
| BR2 | Compare starting grid position with finishing position | BQ3 |
| BR3 | Measure the DNF rate by circuit and show causes of retirement over time | BQ4, BQ5 |
| BR4 | Show how driver points and positions change after each race | BQ7, BQ8 |
| BR5 | Show how many constructors each driver raced for and how many drivers took part each season | BQ9, BQ10 |
| BR6 | Allow every result to be analysed by driver, constructor, circuit, race, date and finishing status | All |

**Scope.** In scope: driver race results, driver championship standings and driver-constructor lineups for all seasons. Out of scope (future work): constructor standings, lap times, pit stops, qualifying, live or real-time data.

## 1.3 The 10 Business Questions

| ID | Question | Fact table | Measures / dimensions used |
|---|---|---|---|
| BQ1 | Which drivers have won the most races, and how does this change by decade? | `fact_race_results` | `is_win`, `dim_driver`, `dim_date` |
| BQ2 | How many points does each constructor score each season, and who is most successful? | `fact_race_results` | `points`, `dim_constructor`, `dim_race`, `dim_date` |
| BQ3 | How does grid position relate to finishing position? How often does pole become a win? | `fact_race_results` | `grid_position`, `finish_position`, `is_win` |
| BQ4 | Which circuits have the highest DNF rate? | `fact_race_results` | `is_dnf`, `dim_circuit`, `dim_date` |
| BQ5 | What are the most common causes of retirement, and how do they change by decade? | `fact_race_results` | `is_dnf`, `dim_status`, `dim_date` |
| BQ6 | Which countries (driver and constructor nationality) have produced the most winners? | `fact_race_results` | `is_win`, `dim_driver`, `dim_constructor` |
| BQ7 | How does the championship battle develop round by round? | `fact_driver_standings` | `cumulative_points`, `standing_position` |
| BQ8 | At which round do eventual champions first take the lead? | `fact_driver_standings` | `standing_position`, `cumulative_wins` |
| BQ9 | For how many different constructors has each driver raced? | `fact_driver_season_entry` | row count, `dim_driver`, `dim_constructor` |
| BQ10 | How many drivers took part in each season, and how has it changed? | `fact_driver_season_entry` | row count, `dim_season` |

## 1.4 Business Processes, Facts and Grain

Three business processes, each modelled as one fact table of a different type, each at the lowest level available so any summary can be built by aggregation.

| Business process | Fact table | Type | Grain: one row = … | Unique key |
|---|---|---|---|---|
| Race Results | `fact_race_results` | Transaction | one driver's result in one race, for the constructor they drove for | `race_key, driver_key` |
| Championship Standings | `fact_driver_standings` | Periodic snapshot | one driver's championship position and cumulative points after one race | `race_key, driver_key` |
| Driver-Team Lineup | `fact_driver_season_entry` | Factless | one driver driving for one constructor in one season | `season_key, driver_key, constructor_key` |

Constructor is part of the lineup grain because a driver can race for two teams in one season.

### Measures

| Fact | Measure | Meaning | Additivity |
|---|---|---|---|
| `fact_race_results` | `points`, `laps_completed` | Points earned, laps completed | Additive |
| | `is_win`, `is_podium`, `is_points_finish`, `is_dnf` | 0/1 flags | Additive |
| | `grid_position`, `finish_position`, `race_time_ms`, `fastest_lap_speed` | Start, finish, time, speed | Non-additive |
| | `result_id` | Source identifier | Degenerate dimension |
| `fact_driver_standings` | `cumulative_points`, `cumulative_wins` | Totals after the race | Semi-additive (sum across drivers at one race, never across races) |
| | `standing_position` | Championship position | Non-additive |
| `fact_driver_season_entry` | none | The row itself is the fact | Count rows |

## 1.5 Dimensions, Bus Matrix and SCD Decisions

| Dimension | Natural key (source) | Surrogate key | Hierarchy | SCD type |
|---|---|---|---|---|
| `dim_date` | race date | `date_key` (yyyymmdd) | Day → Month → Quarter → Year → Decade | 0 (fixed) |
| `dim_race` | `raceId` | `race_key` | Race → Round → Season | 0 (fixed) |
| `dim_season` | `year` | `season_key` | Season → Era | 0 (fixed) |
| `dim_driver` | `driverId` | `driver_key` | Driver → Nationality | 1 (overwrite) |
| `dim_constructor` | `constructorId` | `constructor_key` | Constructor → Nationality | 1 (overwrite) |
| `dim_circuit` | `circuitId` | `circuit_key` | Circuit → Location → Country | 1 (overwrite) |
| `dim_status` | `statusId` | `status_key` | Status → Category | 0 (fixed) |

| Fact table | date | race | season | driver | constructor | circuit | status |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `fact_race_results` | ✓ | ✓ |  | ✓ | ✓ | ✓ | ✓ |
| `fact_driver_standings` | ✓ | ✓ |  | ✓ |  |  |  |
| `fact_driver_season_entry` |  |  | ✓ | ✓ | ✓ |  |  |

`dim_driver`, `dim_constructor` and `dim_date` are **conformed dimensions** shared across facts, so results from different processes can be combined (for example, a driver's wins alongside their championship position). Which team a driver raced for each season is already held in the two facts, so `dim_constructor` needs no history.

## 1.6 Business Rules

- **Win** = finishing position 1. **Podium** = position 1–3. **Points finish** = points > 0.
- **DNF** = status category is not `Finished` and not `Lapped`.
- **`status_category`** groups raw statuses into `Finished`, `Lapped`, `Accident/Collision`, `Mechanical Failure` and `Other`.
- **`era_label`**: ≤1960 Pioneer era · 1961–1976 Rear-engine and aerodynamics era · 1977–1988 Turbo era · 1989–2005 Naturally aspirated era · 2006–2013 V8 era · 2014+ Hybrid era.
- **Missing data** (for example race time and fastest lap in older seasons) stays `NULL` and is never estimated.
- **Unknown members:** every dimension has a row with key `-1`, so a missing foreign key never drops a fact row.
- Standings values are cumulative and must not be added across races.
- Ergast is accepted as the single source of truth; no outside data is added. Changes to driver, constructor and circuit details are overwritten (Type 1).

## 1.7 Phase 1 Deliverables

| Deliverable | Format |
|---|---|
| Project Proposal | PDF |
| Business Requirements Document | PDF |
| 10 Business Questions | PDF |
| Fact & Dimension Identification | PDF |
| Grain Definition Document | PDF |
| Star Schema Diagram (conceptual, logical, physical) | PNG / PDF |
| Data Dictionary | Excel |

**Tools:** Draw.io and dbdiagram.io (schema diagrams), Excel (data dictionary), Kaggle (data source).

---

# Phase 2 – Implementation and ETL Pipeline

Phase 2 implements the Phase 1 design: it loads the Ergast CSVs into PostgreSQL, cleans them, builds the star schema and verifies the result with automated data quality checks.

## 2.1 Technology and Source Data

- **Database:** PostgreSQL 14+ (schemas `project_staging`, `project_dw`, `project_reporting`)
- **ETL:** Python (pandas, SQLAlchemy, psycopg2) for loading; plain SQL for cleaning, modelling and checks
- **Load style:** batch, full reload (the data is static)
- **Source:** Ergast F1 World Championship dataset (Kaggle), 7 CSV files: `circuits`, `constructors`, `drivers`, `races`, `results`, `status`, `driver_standings`

## 2.2 Pipeline

```
Kaggle CSVs ──► project_staging ──► clean ──► project_dw (star schema) ──► data quality checks
   data/        (pandas load)      (SQL)      dimensions → facts            project_dw.dq_log
```

| Step | File | What it does |
|---|---|---|
| 1 | `sql/01_schemas.sql` | Creates the three schemas |
| 2 | `etl/01_extract_load_staging.py` | Reads the 7 CSVs (`\N` → NULL), renames columns, loads `stg_*` tables |
| 3 | `sql/02_staging_clean.sql` | Removes duplicates, standardises text, sets NULL points to 0, converts data types; logs to `cleaning_log` |
| 4 | `sql/03_dw_ddl.sql` | Drops and recreates the 7 dimensions and 3 facts with keys and constraints |
| 5 | `sql/04_load_dimensions.sql` | Inserts the Unknown (`-1`) rows, then loads the dimensions with derived attributes |
| 6 | `sql/05_load_facts.sql` | Loads the 3 facts, looking up surrogate keys and computing the flags |
| 7 | `sql/06_data_quality.sql` | Runs 49 checks and logs each result to `project_dw.dq_log` |

`etl/run_pipeline.py` runs all seven steps in order and prints the data quality results.

## 2.3 Data Cleaning (`sql/02_staging_clean.sql`)

Every action is recorded in `project_staging.cleaning_log` (`table_name`, `action`, `rows_affected`), plus a final row count per table.

| Action | Applies to | Rule |
|---|---|---|
| Remove duplicates | all 7 staging tables | Keep one row per source key |
| Standardise text | circuits, constructors, drivers, races, status | Trim, collapse repeated spaces, empty string → `NULL` |
| Standardise case | refs, driver code, nationality | `*_ref` lower-case, `code` upper-case, `nationality` Initcap |
| Fix missing points | `stg_results` | `NULL` points set to `0` so the measure is never `NULL` |
| Convert data types | all 7 staging tables | Text → `INT`, `SMALLINT`, `NUMERIC`, `BIGINT`, `DATE`, `TIME` |

Other missing values (race time, fastest-lap data, finishing position of non-classified drivers) are deliberately left `NULL`.

## 2.4 Loading the Warehouse

- **Dimensions:** an Unknown member (`-1`) is inserted first; `dim_date` is generated from distinct race dates (key `yyyymmdd`); `era_label` and `status_category` are derived with `CASE` rules; `full_name` is forename + surname.
- **`fact_race_results`:** one row per driver per race (`DISTINCT ON (race_id, driver_id)`); surrogate keys looked up with `LEFT JOIN` and `COALESCE(…, -1)`; flags computed from position, points and status category.
- **`fact_driver_standings`:** one row per driver per race from `driver_standings`.
- **`fact_driver_season_entry`:** distinct (season, driver, constructor) combinations from `results`.

| Table | Rows loaded |
|---|--:|
| `fact_race_results` | 27,587 |
| `fact_driver_standings` | 35,813 |
| `fact_driver_season_entry` | 3,602 |
| All 7 dimensions combined | 3,728 |

In `fact_race_results`, 70.1% of rows have no `race_time_ms` or `fastest_lap_speed` (not recorded in older seasons, or not applicable to non-finishers) and 39.4% have no `finish_position` (non-classified results). These are expected NULLs.

## 2.5 Data Quality Checks (`sql/06_data_quality.sql`)

Each check writes one row to `project_dw.dq_log` (`category`, `check_name`, `expected`, `actual`, `status`, `checked_at`). Checks labelled `INFO` record an expected count and are always `PASS`.

| Pillar | What it verifies | Checks | Passed |
|---|---|:-:|:-:|
| Completeness | Mandatory attributes are not NULL; historical NULLs are counted | 11 | 11 |
| Accuracy | Totals reconcile to staging; derived flags are correct | 8 | 4 |
| Integrity | All 12 fact-to-dimension keys resolve, none map to Unknown, keys are unique | 27 | 27 |
| Volume | Minimum expected row counts | 3 | 3 |
| **Total** | | **49** | **45** |

**The 4 flagged Accuracy checks** are all explained:

| Check | Expected | Actual | Cause |
|---|--:|--:|---|
| `fact_race_results` rows = staging rows | 27,678 | 27,587 | Load rule keeps one row per driver per race, so 91 duplicate result records are not loaded |
| `SUM(points)` fact = staging | 57,631.05 | 57,624.89 | Same cause (-6.16 points, 0.01%) |
| `SUM(is_podium)` = staging position ≤ 3 | 3,528 | 3,526 | Same cause (-2 podiums) |
| Races with more than one winner | 0 | 3 | Source characteristic: three historical races in Ergast have two drivers at position 1 |

Wins reconcile exactly (1,172). Query the log any time with `SELECT * FROM project_dw.dq_log ORDER BY check_id;`.

## 2.6 Repository Structure

```
.
├── etl/
│   ├── 01_extract_load_staging.py   # CSV → staging tables
│   └── run_pipeline.py              # runs the whole pipeline
├── sql/
│   ├── 01_schemas.sql
│   ├── 02_staging_clean.sql
│   ├── 03_dw_ddl.sql
│   ├── 04_load_dimensions.sql
│   ├── 05_load_facts.sql
│   └── 06_data_quality.sql
├── data/                            # NOT in the repo: add the CSVs (git-ignored)
├── .env                             # NOT in the repo: your DB credentials (git-ignored)
└── README.md
```

## 2.7 Setup and Run

Run everything **on your own machine**; you need a local PostgreSQL server.

1. **Prerequisites:** Python 3.9+ and PostgreSQL 14+ (with pgAdmin or `psql`).
2. **Clone and install**
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
4. **Download the dataset** (it is not in the repo). Kaggle → *Formula 1 World Championship (1950-2020)* (`rohanrao/formula-1-world-championship-1950-2020`). Put these 7 files in a `data/` folder in the repo root: `circuits.csv`, `constructors.csv`, `drivers.csv`, `races.csv`, `results.csv`, `status.csv`, `driver_standings.csv`.
   ```bash
   pip install kaggle
   kaggle datasets download -d rohanrao/formula-1-world-championship-1950-2020 -p data --unzip
   ```
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
7. **Check the result**
   ```sql
   SELECT COUNT(*) FROM project_dw.fact_race_results;               -- 27,587
   SELECT status, COUNT(*) FROM project_dw.dq_log GROUP BY status;  -- 45 PASS, 4 FAIL
   ```

## 2.8 Example Query (BQ4: circuits with the highest DNF rate)

```sql
SELECT c.circuit_name,
       COUNT(*)                                    AS entries,
       ROUND(100.0 * SUM(f.is_dnf) / COUNT(*), 1)  AS dnf_rate_pct
FROM project_dw.fact_race_results f
JOIN project_dw.dim_circuit c ON c.circuit_key = f.circuit_key
WHERE f.circuit_key <> -1
GROUP BY c.circuit_name
HAVING COUNT(*) >= 100
ORDER BY dnf_rate_pct DESC
LIMIT 10;
```

## 2.9 Known Limitations and Next Steps

- **Row reconciliation:** 91 of 27,678 staging result rows (0.33%) are not loaded because the fact table keeps the one-row-per-driver-per-race grain. For an exact match, extend the primary key of `fact_race_results` with `result_id` (already stored as a degenerate dimension) and remove the `DISTINCT ON` filter.
- **Multi-winner races:** three historical races have two drivers at position 1 in the source; they are kept as recorded.
- There is no `requirements.txt`; install the packages in step 2.
- Each run is a full reload: staging tables are replaced and warehouse tables are dropped and rebuilt.
- **Phase 3 (next):** analytical views, OLAP queries and Power BI reporting on top of `project_dw`.

## 2.10 Phase 2 Deliverables

Data Cleaning Report · Data Quality Report (results of `sql/06_data_quality.sql`) · this repository (ETL code and SQL).

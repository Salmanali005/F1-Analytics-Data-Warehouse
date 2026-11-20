# Formula 1 Analytics Data Warehouse

**DL3004 – Phase 2: Implementation & ETL Pipeline (PostgreSQL + Python)**

A Kimball-style dimensional data warehouse for Formula 1 race and championship data (1950 onward). It turns the Ergast Formula 1 World Championship CSV files into a star schema, so questions about drivers, constructors, circuits and seasons become simple queries instead of multi-file joins.

**Team**

| Roll No | Name |
|---|---|
| 24L-2580 | Sanan Zahid |
| 24L-2525 | Munam Ansari |
| 24L-2593 | Noyan Siddiqui |
| 24L-2542 | Salman Ali |

---

## 1. Project Overview

Phase 1 (business analysis and dimensional design) produced the proposal, business requirements, 10 business questions, fact/dimension identification, grain definitions, star schema diagrams and data dictionary. This repository is the Phase 2 implementation of that design.

- **Source:** Ergast F1 World Championship dataset (Kaggle), 7 CSV files
- **Database:** PostgreSQL
- **ETL:** Python (pandas, SQLAlchemy) for loading, plain SQL for cleaning and modelling
- **Load style:** batch, full reload (the data is static, so no real-time updates)

## 2. Data Model

Three business processes, each modelled as one fact table of a different type, sharing seven dimensions.

| Business Process | Fact Table | Type | Grain (one row = …) | Unique Key |
|---|---|---|---|---|
| Race Results | `fact_race_results` | Transaction | one driver's result in one race, for the constructor they drove for | `race_key, driver_key` |
| Championship Standings | `fact_driver_standings` | Periodic snapshot | one driver's championship position and cumulative points after one race | `race_key, driver_key` |
| Driver-Team Lineup | `fact_driver_season_entry` | Factless | one driver driving for one constructor in one season | `season_key, driver_key, constructor_key` |

### Bus matrix

| Fact Table | date | race | season | driver | constructor | circuit | status |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `fact_race_results` | ✓ | ✓ |  | ✓ | ✓ | ✓ | ✓ |
| `fact_driver_standings` | ✓ | ✓ |  | ✓ |  |  |  |
| `fact_driver_season_entry` |  |  | ✓ | ✓ | ✓ |  |  |

`dim_driver`, `dim_constructor` and `dim_date` are conformed dimensions shared across facts.

### Dimensions

| Dimension | Natural key (source) | Surrogate key | Hierarchy | SCD |
|---|---|---|---|---|
| `dim_date` | race date | `date_key` (yyyymmdd) | Day → Month → Quarter → Year → Decade | Type 0 |
| `dim_race` | `raceId` | `race_key` | Race → Round → Season | Type 0 |
| `dim_season` | `year` | `season_key` | Season → Era | Type 0 |
| `dim_driver` | `driverId` | `driver_key` | Driver → Nationality | Type 1 |
| `dim_constructor` | `constructorId` | `constructor_key` | Constructor → Nationality | Type 1 |
| `dim_circuit` | `circuitId` | `circuit_key` | Circuit → Location → Country | Type 1 |
| `dim_status` | `statusId` | `status_key` | Status → Category | Type 0 |

### Measures (`fact_race_results`)

| Measure | Meaning | Additivity |
|---|---|---|
| `points` | Championship points earned in the race | Additive |
| `laps_completed` | Laps completed | Additive |
| `is_win` / `is_podium` / `is_points_finish` / `is_dnf` | 0/1 flags | Additive |
| `grid_position`, `finish_position` | Start / classified position | Non-additive |
| `race_time_ms`, `fastest_lap_speed` | Race time and fastest-lap speed | Non-additive |
| `result_id` | Source identifier (degenerate dimension) | – |

`fact_driver_standings` holds `cumulative_points` and `cumulative_wins` (semi-additive: sum across drivers at one race, never across races) and `standing_position` (non-additive). `fact_driver_season_entry` has no measures; analysis is done by counting rows.

### Business rules implemented

- **Win** = finishing position 1. **Podium** = position 1–3. **Points finish** = points > 0.
- **DNF** = status category is not `Finished` and not `Lapped`.
- **`status_category`** groups raw statuses into: `Finished`, `Lapped`, `Accident/Collision`, `Mechanical Failure`, `Other`.
- **`era_label`** by season year: ≤1960 Pioneer era · 1961–1976 Rear-engine and aerodynamics era · 1977–1988 Turbo era · 1989–2005 Naturally aspirated era · 2006–2013 V8 era · 2014+ Hybrid era.
- **Missing data** (e.g. race time and fastest lap in older seasons) is kept as `NULL`, never estimated.
- **Unknown members:** every dimension has a row with key `-1` ("Unknown"). Missing foreign keys map to it so no fact row is dropped.
- A driver can race for more than one constructor in a season, so the constructor is stored per race and in the lineup grain.

## 3. Business Questions Answered

| ID | Question | Fact table | Key columns |
|---|---|---|---|
| BQ1 | Which drivers have won the most races, and how does this change by decade? | `fact_race_results` | `is_win`, `dim_driver`, `dim_date.decade` |
| BQ2 | How many points does each constructor score per season? | `fact_race_results` | `points`, `dim_constructor`, `dim_race.season_year` |
| BQ3 | How does grid position relate to finishing position? How often does pole become a win? | `fact_race_results` | `grid_position`, `finish_position`, `is_win` |
| BQ4 | Which circuits have the highest DNF rate? | `fact_race_results` | `is_dnf`, `dim_circuit` |
| BQ5 | What are the most common retirement causes, and how do they change by decade? | `fact_race_results` | `is_dnf`, `dim_status.status_category`, `dim_date.decade` |
| BQ6 | Which countries have produced the most race winners? | `fact_race_results` | `is_win`, `dim_driver.nationality`, `dim_constructor.nationality` |
| BQ7 | How does the championship develop round by round? | `fact_driver_standings` | `cumulative_points`, `standing_position` |
| BQ8 | At which round do eventual champions first take the lead? | `fact_driver_standings` | `standing_position`, `cumulative_wins` |
| BQ9 | For how many different constructors has each driver raced? | `fact_driver_season_entry` | row count by driver |
| BQ10 | How many drivers took part in each season (field size)? | `fact_driver_season_entry` | row count by season |

Example (BQ4, circuits with the highest DNF rate):

```sql
SELECT c.circuit_name,
       COUNT(*)                                  AS entries,
       ROUND(100.0 * SUM(f.is_dnf) / COUNT(*), 1) AS dnf_rate_pct
FROM project_dw.fact_race_results f
JOIN project_dw.dim_circuit c ON c.circuit_key = f.circuit_key
WHERE f.circuit_key <> -1
GROUP BY c.circuit_name
HAVING COUNT(*) >= 100
ORDER BY dnf_rate_pct DESC
LIMIT 10;
```

## 4. Pipeline

```
Kaggle CSVs ──► project_staging ──► clean ──► project_dw (star schema)
   data/        (pandas load)      (SQL)      dimensions → facts
```

| Step | File | What it does |
|---|---|---|
| 1 | `sql/01_schemas.sql` | Creates schemas `project_staging`, `project_dw`, `project_reporting` |
| 2 | `etl/01_extract_load_staging.py` | Reads the 7 CSVs (`\N` → NULL), renames columns, loads `stg_*` tables |
| 3 | `sql/02_staging_clean.sql` | Cleans and standardises the staging tables |
| 4 | `sql/03_dw_ddl.sql` | Drops and recreates the dimension and fact tables with keys and constraints |
| 5 | `sql/04_load_dimensions.sql` | Inserts the Unknown rows, then loads the 7 dimensions with derived attributes (era, status category, calendar fields) |
| 6 | `sql/05_load_facts.sql` | Loads the 3 fact tables, looking up surrogate keys and computing the flags |
| 7 | `sql/06_data_quality.sql` | Data quality checks written to `project_dw.dq_log` (see Known limitations) |

`etl/run_pipeline.py` runs all steps in order and prints the data quality results.

## 5. Repository Structure

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
│   └── 05_load_facts.sql
├── data/                            # NOT in the repo – you add the CSVs (git-ignored)
├── .env                             # NOT in the repo – your DB credentials (git-ignored)
└── README.md
```

## 6. Setup and Run

Run everything **on your own machine**; you need a local PostgreSQL server.

### Prerequisites
- Python 3.9+
- PostgreSQL 14+ (with pgAdmin or `psql`)

### Steps

1. **Clone the repo**
   ```bash
   git clone https://github.com/Salmanali005/F1-Analytics-Data-Warehouse.git
   cd F1-Analytics-Data-Warehouse
   ```

2. **Create a virtual environment and install packages**
   ```bash
   python -m venv venv
   venv\Scripts\activate          # Windows
   # source venv/bin/activate     # macOS / Linux
   pip install pandas sqlalchemy psycopg2-binary python-dotenv
   ```

3. **Create an empty database**
   ```sql
   CREATE DATABASE f1_dw;
   ```

4. **Download the dataset (not included in the repo)**
   Kaggle → *Formula 1 World Championship (1950-2020)* (`rohanrao/formula-1-world-championship-1950-2020`). Copy these 7 files into a `data/` folder in the repo root:

   `circuits.csv`, `constructors.csv`, `drivers.csv`, `races.csv`, `results.csv`, `status.csv`, `driver_standings.csv`

   Or with the Kaggle CLI:
   ```bash
   pip install kaggle
   kaggle datasets download -d rohanrao/formula-1-world-championship-1950-2020 -p data --unzip
   ```
   Other files (lap times, pit stops, qualifying, constructor standings) are out of scope and ignored.

5. **Create a `.env` file in the repo root**
   ```
   DB_USER=postgres
   DB_PASSWORD=your_password
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=f1_dw
   ```

6. **Run the pipeline from the repo root** (paths are relative)
   ```bash
   python etl/run_pipeline.py
   ```

7. **Check the result**
   ```sql
   SELECT COUNT(*) FROM project_dw.fact_race_results;
   SELECT COUNT(*) FROM project_dw.fact_driver_standings;
   SELECT COUNT(*) FROM project_dw.fact_driver_season_entry;
   ```

## 7. Scope

**In scope:** race results, driver championship standings and driver-constructor lineups for all seasons in the dataset.

**Out of scope (future work):** constructor standings, lap times, pit stops, qualifying, live or real-time data. The model can be extended with new fact tables without changing existing ones.

## 8. Known Limitations

- `etl/run_pipeline.py` expects `sql/06_data_quality.sql` (which creates and fills `project_dw.dq_log`), but that file is not yet in the repository. Until it is added, the pipeline stops at the last step after the warehouse tables are already built.
- There is no `requirements.txt`; install the packages listed in step 2.
- Each run is a full reload: staging tables are replaced and the warehouse tables are dropped and rebuilt.

## 9. Documentation (Phase 1 deliverables)

Project Proposal · Business Requirements Document · 10 Business Questions · Fact & Dimension Identification · Grain Definition Document · Star Schema Diagram (conceptual, logical, physical) · Data Dictionary (Excel).

## 10. Data Source

Ergast Formula 1 World Championship dataset, via Kaggle. Accepted as the single source of truth and loaded as provided; no outside data is added.

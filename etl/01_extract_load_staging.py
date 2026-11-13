import os
import pandas as pd
from sqlalchemy import create_engine
from dotenv import load_dotenv

load_dotenv()

engine = create_engine(
    f"postgresql+psycopg2://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@"
    f"{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
)

files_to_tables = {
    "circuits.csv": "stg_circuits",
    "constructors.csv": "stg_constructors",
    "drivers.csv": "stg_drivers",
    "races.csv": "stg_races",
    "status.csv": "stg_status",
    "results.csv": "stg_results",
    "driver_standings.csv": "stg_driver_standings",
}

for filename, table_name in files_to_tables.items():
    df = pd.read_csv(f"data/{filename}", na_values=["\\N"])
    df.columns = [c.lower() for c in df.columns]
    
    if filename == "races.csv":
        df = df[["raceid", "year", "round", "circuitid", "name", "date", "time", "url"]]
        df.columns = ["race_id", "year", "round", "circuit_id", "name", "date", "time", "url"]
    elif filename == "circuits.csv":
        df.columns = ["circuit_id", "circuit_ref", "name", "location", "country", "lat", "lng", "alt", "url"]
    elif filename == "constructors.csv":
        df.columns = ["constructor_id", "constructor_ref", "name", "nationality", "url"]
    elif filename == "drivers.csv":
        df.columns = ["driver_id", "driver_ref", "number", "code", "forename", "surname", "dob", "nationality", "url"]
    elif filename == "status.csv":
        df.columns = ["status_id", "status"]
    elif filename == "results.csv":
        df.columns = [
            "result_id", "race_id", "driver_id", "constructor_id", "number", "grid",
            "position", "position_text", "position_order", "points", "laps", "time",
            "milliseconds", "fastest_lap", "rank", "fastest_lap_time", "fastest_lap_speed", "status_id"
        ]
    elif filename == "driver_standings.csv":
        df.columns = ["driver_standings_id", "race_id", "driver_id", "points", "position", "position_text", "wins"]

    df.to_sql(table_name, engine, schema="project_staging", if_exists="replace", index=False)
    print(f"Loaded {len(df)} rows into project_staging.{table_name}")
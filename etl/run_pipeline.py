import os
import subprocess
import sys
import time

from dotenv import load_dotenv
from sqlalchemy import create_engine

load_dotenv()

engine = create_engine(
    f"postgresql+psycopg2://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@"
    f"{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
)

def run_sql(path):
    start = time.time()
    with open(path, encoding="utf-8") as f:
        sql = f.read()
    raw = engine.raw_connection()
    try:
        cur = raw.cursor()
        cur.execute(sql)
        raw.commit()
    except Exception:
        raw.rollback()
        raise
    finally:
        raw.close()
    print(f"[OK] {path} ({time.time() - start:.1f}s)")

def run_py(path):
    start = time.time()
    subprocess.run([sys.executable, path], check=True)
    print(f"[OK] {path} ({time.time() - start:.1f}s)")

steps = [
    ("sql", "sql/01_schemas.sql"),
    ("py", "etl/01_extract_load_staging.py"),
    ("sql", "sql/02_staging_clean.sql"),
    ("sql", "sql/03_dw_ddl.sql"),
    ("sql", "sql/04_load_dimensions.sql"),
    ("sql", "sql/05_load_facts.sql"),
    ("sql", "sql/06_data_quality.sql"),
]

for kind, path in steps:
    run_sql(path) if kind == "sql" else run_py(path)

with engine.connect() as conn:
    rows = conn.exec_driver_sql(
        "SELECT category, check_name, expected, actual, status FROM project_dw.dq_log ORDER BY check_id"
    ).fetchall()

print("\nDATA QUALITY RESULTS")
for r in rows:
    print(f"{r[4]:5} | {r[0]:12} | {r[1]} | expected={r[2]} actual={r[3]}")

print(f"\nFAILED checks: {sum(1 for r in rows if r[4] == 'FAIL')}")

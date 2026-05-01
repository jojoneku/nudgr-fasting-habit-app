"""
import_usda_fdc.py — Download USDA FoodData Central SR Legacy and rebuild food_db.sqlite.

Downloads ~30 MB ZIP, parses nutrient CSVs, merges with curated data from
build_food_db.py, then writes assets/food_db.sqlite with ~9,400+ entries.

Usage:
    python scripts/import_usda_fdc.py

All values are per 100g. Curated foods take precedence over USDA entries
(inserted first; USDA duplicates skipped via INSERT OR IGNORE).
"""

import csv
import io
import os
import re
import sqlite3
import sys
import urllib.request
import zipfile

# USDA FDC SR Legacy — public domain, last updated Oct 2021 (data unchanged since)
FDC_URL = (
    "https://fdc.nal.usda.gov/fdc-datasets/"
    "FoodData_Central_sr_legacy_food_csv_2018-04.zip"
)

# ---------------------------------------------------------------------------
# Import curated foods from build_food_db.py
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_food_db import FOODS as CURATED_FOODS  # noqa: E402


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def download(url: str) -> bytes:
    print(f"Downloading {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        total = int(r.headers.get("Content-Length", 0))
        chunks: list[bytes] = []
        done = 0
        while True:
            chunk = r.read(65536)
            if not chunk:
                break
            chunks.append(chunk)
            done += len(chunk)
            if total:
                print(
                    f"\r  {done/1e6:.1f}/{total/1e6:.1f} MB "
                    f"({done/total*100:.0f}%)",
                    end="",
                    flush=True,
                )
        print()
    return b"".join(chunks)


# ---------------------------------------------------------------------------
# Parse USDA FDC SR Legacy ZIP
# ---------------------------------------------------------------------------

def parse_fdc_sr(zip_bytes: bytes) -> list[tuple]:
    print("Parsing USDA FDC SR Legacy ...")
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
        # Map basename -> zip path
        files = {os.path.basename(n): n for n in z.namelist() if n.endswith(".csv")}

        # ── nutrient.csv: map by nutrient_nbr (stable across releases) ──────────
        # 208 = Energy (kcal), 203 = Protein, 204 = Total fat, 205 = Carbs
        NBR_MAP = {"208": "energy", "203": "protein", "204": "fat", "205": "carbs"}
        macro_ids: dict[str, str] = {}  # key -> nutrient id string
        with z.open(files["nutrient.csv"]) as f:
            for row in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")):
                key = NBR_MAP.get(row.get("nutrient_nbr", "").strip())
                if key:
                    macro_ids[key] = row["id"]

        print(f"  Nutrient IDs resolved: {macro_ids}")
        want   = set(macro_ids.values())
        rev_id = {v: k for k, v in macro_ids.items()}  # id -> key name

        # ── food_category.csv ─────────────────────────────────────────────────
        categories: dict[str, str] = {}
        if "food_category.csv" in files:
            with z.open(files["food_category.csv"]) as f:
                for row in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")):
                    categories[row["id"]] = row["description"]

        # ── food.csv: SR Legacy rows only ─────────────────────────────────────
        foods: dict[str, dict] = {}
        with z.open(files["food.csv"]) as f:
            for row in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")):
                if row.get("data_type") != "sr_legacy_food":
                    continue
                fid = row["fdc_id"]
                foods[fid] = {
                    "name":     row["description"],
                    "category": categories.get(row.get("food_category_id", ""), "Other"),
                }

        print(f"  SR Legacy foods found: {len(foods)}")

        # ── food_nutrient.csv ─────────────────────────────────────────────────
        nutrients: dict[str, dict] = {}
        with z.open(files["food_nutrient.csv"]) as f:
            for row in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")):
                fid = row["fdc_id"]
                if fid not in foods:
                    continue
                nid = row["nutrient_id"]
                if nid not in want:
                    continue
                key = rev_id[nid]
                val = float(row["amount"]) if row["amount"] else 0.0
                nutrients.setdefault(fid, {})[key] = val

    # ── Build output rows ─────────────────────────────────────────────────────
    rows: list[tuple] = []
    for fid, food in foods.items():
        n   = nutrients.get(fid, {})
        cal = n.get("energy", 0.0)
        if cal <= 0:
            continue  # skip entries with no calorie data
        rows.append((
            f"usda_{fid}",
            _title(food["name"]),
            food["category"],
            round(cal,                  1),
            round(n.get("protein", 0), 1),
            round(n.get("carbs",   0), 1),
            round(n.get("fat",     0), 1),
        ))

    print(f"  Parsed {len(rows)} USDA foods with calorie data")
    return rows


def _title(s: str) -> str:
    """Title-case a food name but preserve all-caps acronyms (e.g. NFS, UHT)."""
    return re.sub(r"[A-Z]{2,}", lambda m: m.group(), s.title())


# ---------------------------------------------------------------------------
# Build SQLite
# ---------------------------------------------------------------------------

def build_db(curated: list[tuple], usda: list[tuple], db_path: str) -> None:
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cur  = conn.cursor()

    cur.execute("""
        CREATE TABLE foods (
            id       TEXT PRIMARY KEY,
            name     TEXT NOT NULL,
            category TEXT,
            cal      REAL NOT NULL,
            protein  REAL,
            carbs    REAL,
            fat      REAL
        )
    """)
    cur.execute("""
        CREATE VIRTUAL TABLE foods_fts USING fts5(
            name,
            content='foods',
            content_rowid='rowid'
        )
    """)
    cur.execute("""
        CREATE INDEX idx_foods_name_lower ON foods(lower(name))
    """)
    cur.execute("""
        CREATE TRIGGER foods_ai AFTER INSERT ON foods BEGIN
            INSERT INTO foods_fts(rowid, name) VALUES (new.rowid, new.name);
        END
    """)

    # Curated first so INSERT OR IGNORE keeps them over USDA duplicates
    cur.executemany(
        "INSERT OR IGNORE INTO foods (id, name, category, cal, protein, carbs, fat) "
        "VALUES (?,?,?,?,?,?,?)",
        list(curated) + list(usda),
    )
    conn.commit()
    cur.execute("VACUUM")
    conn.close()

    kb = os.path.getsize(db_path) / 1024
    print(f"\nOK: {db_path}")
    print(f"  {len(curated) + len(usda):,} total entries")
    print(f"  {len(curated):,} curated  |  {len(usda):,} USDA SR Legacy")
    print(f"  {kb:.0f} KB on disk")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root  = os.path.dirname(script_dir)
    db_path    = os.path.join(repo_root, "assets", "food_db.sqlite")

    zip_bytes = download(FDC_URL)
    usda_rows = parse_fdc_sr(zip_bytes)
    build_db(CURATED_FOODS, usda_rows, db_path)


if __name__ == "__main__":
    main()

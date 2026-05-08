"""
import_usda_fdc.py — Download USDA FoodData Central and rebuild food_db.sqlite.

Pulls two USDA datasets:
  - SR Legacy (~6 MB ZIP): lab-tested raw foods (~7,800 entries)
  - FNDDS Survey Foods (~3 MB ZIP): foods as actually eaten (~7,000 entries)

Merges with curated data from build_food_db.py, then writes
assets/food_db.sqlite with ~16,000 entries total.

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

# USDA FDC dataset URLs — public domain.
# SR Legacy is frozen at 2018-04; FNDDS is updated periodically (latest 2024-10-31).
SR_LEGACY_URL = (
    "https://fdc.nal.usda.gov/fdc-datasets/"
    "FoodData_Central_sr_legacy_food_csv_2018-04.zip"
)
FNDDS_URL = (
    "https://fdc.nal.usda.gov/fdc-datasets/"
    "FoodData_Central_survey_food_csv_2024-10-31.zip"
)
FOUNDATION_URL = (
    "https://fdc.nal.usda.gov/fdc-datasets/"
    "FoodData_Central_foundation_food_csv_2025-04-24.zip"
)

# FDC data_type values we want to keep, per dataset.
SR_LEGACY_TYPES = {"sr_legacy_food"}
FNDDS_TYPES = {"survey_fndds_food"}
FOUNDATION_TYPES = {"foundation_food"}

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

def parse_fdc_zip(
    zip_bytes: bytes,
    allowed_types: set[str],
    label: str,
) -> list[tuple]:
    print(f"Parsing USDA FDC {label} ...")
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

        # ── food.csv: filter to the data_types we care about ─────────────────
        foods: dict[str, dict] = {}
        with z.open(files["food.csv"]) as f:
            for row in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")):
                if row.get("data_type") not in allowed_types:
                    continue
                fid = row["fdc_id"]
                foods[fid] = {
                    "name":     row["description"],
                    "category": categories.get(row.get("food_category_id", ""), "Other"),
                }

        print(f"  {label} foods found: {len(foods)}")

        # ── food_nutrient.csv ─────────────────────────────────────────────────
        # FNDDS stores nutrient_id as the legacy nutrient_nbr (e.g. "208" for
        # energy), while SR Legacy uses the new numeric ids ("1008"). Accept
        # either by merging both mappings into a single id->key dictionary.
        id_to_key: dict[str, str] = {**rev_id, **NBR_MAP}
        nutrients: dict[str, dict] = {}
        with z.open(files["food_nutrient.csv"]) as f:
            for row in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")):
                fid = row["fdc_id"]
                if fid not in foods:
                    continue
                nid = row["nutrient_id"]
                key = id_to_key.get(nid)
                if key is None:
                    continue
                val = float(row["amount"]) if row["amount"] else 0.0
                # Don't overwrite a non-zero value with zero (some FDC entries
                # have multiple rows for the same nutrient — keep the first
                # meaningful one).
                existing = nutrients.setdefault(fid, {})
                if key not in existing or existing[key] == 0.0:
                    existing[key] = val

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

    print(f"  Parsed {len(rows)} {label} foods with calorie data")
    return rows


def _title(s: str) -> str:
    """Title-case a food name but preserve all-caps acronyms (e.g. NFS, UHT)."""
    return re.sub(r"[A-Z]{2,}", lambda m: m.group(), s.title())


# ---------------------------------------------------------------------------
# Build SQLite
# ---------------------------------------------------------------------------

def build_db(
    curated: list[tuple],
    foundation: list[tuple],
    sr_legacy: list[tuple],
    fndds: list[tuple],
    db_path: str,
) -> None:
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

    # Source priority for dedup: lower wins on collision. Curated represents
    # the user's overrides and PH-specific data, so it ranks highest.
    sources = [
        ("curated",    curated,    0),
        ("foundation", foundation, 1),
        ("sr_legacy",  sr_legacy,  2),
        ("fndds",      fndds,      3),
    ]
    final_rows, kept_by_source, dropped_by_source = _dedupe(sources)

    cur.executemany(
        "INSERT OR IGNORE INTO foods (id, name, category, cal, protein, carbs, fat) "
        "VALUES (?,?,?,?,?,?,?)",
        final_rows,
    )
    conn.commit()
    cur.execute("VACUUM")
    conn.close()

    total = len(final_rows)
    kb = os.path.getsize(db_path) / 1024
    print(f"\nOK: {db_path}")
    print(f"  {total:,} total entries after dedup")
    parts = []
    for name, rows, _ in sources:
        kept = kept_by_source.get(name, 0)
        dropped = dropped_by_source.get(name, 0)
        parts.append(f"{kept:,} {name} ({dropped:,} dropped)")
    print("  " + "  |  ".join(parts))
    print(f"  {kb:.0f} KB on disk")


def _dedupe(sources):
    """Drop near-duplicate entries across sources, preferring lower-priority
    indices. Two entries collide when their normalized names are identical.

    Returns (final_rows, kept_by_source, dropped_by_source).
    """
    seen: dict[str, str] = {}  # norm_name -> winning source name
    final: list[tuple] = []
    kept: dict[str, int] = {}
    dropped: dict[str, int] = {}

    for source_name, rows, _priority in sources:
        for row in rows:
            # row = (id, name, category, cal, protein, carbs, fat)
            norm = _normalize_name(row[1])
            if norm in seen:
                dropped[source_name] = dropped.get(source_name, 0) + 1
                continue
            seen[norm] = source_name
            final.append(row)
            kept[source_name] = kept.get(source_name, 0) + 1
    return final, kept, dropped


_NORM_RE = re.compile(r"[^a-z0-9 ]+")
_WS_RE = re.compile(r"\s+")


def _normalize_name(name: str) -> str:
    """Lowercase + strip non-alphanumeric + collapse whitespace.
    "Oats, Rolled, Dry" → "oats rolled dry"; "Bear Brand (Powdered)" → "bear brand powdered".
    """
    s = _NORM_RE.sub(" ", name.lower())
    s = _WS_RE.sub(" ", s).strip()
    return s


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root  = os.path.dirname(script_dir)
    db_path    = os.path.join(repo_root, "assets", "food_db.sqlite")

    foundation_zip = download(FOUNDATION_URL)
    foundation_rows = parse_fdc_zip(
        foundation_zip, FOUNDATION_TYPES, "Foundation"
    )

    sr_zip = download(SR_LEGACY_URL)
    sr_rows = parse_fdc_zip(sr_zip, SR_LEGACY_TYPES, "SR Legacy")

    fndds_zip = download(FNDDS_URL)
    fndds_rows = parse_fdc_zip(fndds_zip, FNDDS_TYPES, "FNDDS")

    build_db(CURATED_FOODS, foundation_rows, sr_rows, fndds_rows, db_path)


if __name__ == "__main__":
    main()

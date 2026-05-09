"""
load_philfct.py — Loader for the DOST-FNRI Philippine Food Composition Table.

Reads scripts/data/philfct.csv (1,542 official entries with Tagalog common
names) and yields rows shaped like the rest of the food DB pipeline so it can
be merged with curated PH brands + USDA datasets in import_usda_fdc.py.

Output tuple: (id, name, name_norm, category, cal, protein, carbs, fat).

The Tagalog/Filipino common name from the "Alternate/Common Name(s)" column is
folded INTO `name_norm` (not the display name) so trigram FTS5 finds rows when
users search "kamoteng kahoy", "manok", "talong", etc., while the displayed
name stays the canonical English description.

Source: i-plan.fnri.dost.gov.ph (PhilFCT). Public reference data; attribute
DOST-FNRI in any user-facing surface.
"""

import csv
import os
import re

# Mirrors lib/services/food_db_service.dart::SearchNormalize.dense and
# scripts/migrate_food_db_v8.py::normalize_for_search. Anything that touches
# name_norm MUST go through this — keep all three in sync.
_PANCIT_RE = re.compile(r"\bpancit\b")
_NON_ALPHANUM_RE = re.compile(r"[^a-z0-9]+")


def _search_norm(text: str) -> str:
    s = text.lower().replace("ñ", "n")
    s = _PANCIT_RE.sub("pansit", s)
    return _NON_ALPHANUM_RE.sub("", s)


# Standard FNRI food group letter prefixes. Categories shape only metadata; the
# matcher doesn't filter on them today, but they're useful in any future
# curation UI and worth preserving.
_CATEGORY = {
    "A": "Grains",
    "B": "Starchy Roots & Tubers",
    "C": "Nuts & Seeds",
    "D": "Vegetables",
    "E": "Fruits",
    "F": "Meat",
    "G": "Fish & Shellfish",
    "H": "Eggs",
    "J": "Milk & Dairy",
    "K": "Fats & Oils",
    "M": "Sugars & Sweets",
    "N": "Beverages",
    "P": "Alcoholic Beverages",
    "Q": "Miscellaneous",
    "R": "Composite Dishes",
    "S": "Baby Foods",
    "T": "Other",
}


def _parse_float(value: str) -> float:
    """Tolerate missing/dash/N-A values. Returns 0.0 for anything non-numeric
    so we still record a row when only some macros are unknown."""
    if value is None:
        return 0.0
    s = value.strip().replace(",", "")
    if not s or s in ("-", "N/A", "n/a"):
        return 0.0
    try:
        return float(s)
    except ValueError:
        return 0.0


def load_philfct(csv_path: str | None = None) -> list[tuple]:
    """Returns rows shaped (id, name, name_norm, category, cal, protein, carbs, fat).

    Skips rows with no calorie data (currently 1 such row in the dataset).
    """
    if csv_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        csv_path = os.path.join(here, "data", "philfct.csv")

    out: list[tuple] = []
    with open(csv_path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            food_id = row.get("Food_ID", "").strip()
            name = row.get("Food Name and Description", "").strip()
            cal_raw = row.get("Energy (kcal)", "").strip()
            if not food_id or not name or not cal_raw:
                continue
            cal = _parse_float(cal_raw)
            if cal <= 0:
                continue

            tagalog = row.get("Alternate/Common Name(s)", "").strip()
            # "N/A" is the dataset's null sentinel; drop it so it doesn't
            # contaminate the search index.
            if tagalog.lower() in ("", "n/a"):
                tagalog = ""

            # Tagalog goes into name_norm so the trigram FTS5 finds it, but the
            # displayed name stays the canonical English description.
            search_text = f"{name} {tagalog}" if tagalog else name

            category = _CATEGORY.get(food_id[:1], "Other")
            out.append((
                f"fnri_{food_id}",
                name,
                _search_norm(search_text),
                category,
                round(cal, 1),
                round(_parse_float(row.get("Protein (g)", "")), 1),
                round(_parse_float(row.get("Carbs (g)", "")), 1),
                round(_parse_float(row.get("Fat (g)", "")), 1),
            ))
    return out


if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    rows = load_philfct()
    print(f"Loaded {len(rows)} PhilFCT rows")
    print("Sample:")
    for r in rows[:5]:
        print(f"  {r}")

"""
migrate_food_db_v10.py — Merge food_aliases.json into a new bundled DB
that has an `aliases` column + FTS5 index covering it.

Reads:
    assets/food_db.sqlite           (v9, source of truth)
    assets/data/food_aliases.json   (output of build_food_aliases.py)

Writes:
    assets/food_db.sqlite           (v10 — overwrites v9 in place)

After running, bump the version constant in food_db_service.dart so the
app discards its cached copy and re-extracts the asset.

Note: v9 and v10 use the same asset filename (food_db.sqlite). Versioning
is tracked by the `_dbFilename` constant in FoodDbService, which controls
the path under app documents — bumping that triggers a fresh copy.
"""

from __future__ import annotations

import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "assets" / "food_db.sqlite"
ALIASES_PATH = ROOT / "assets" / "data" / "food_aliases.json"

# Mirror of SearchNormalize.dense() in food_db_service.dart. Keep in sync.
_PANCIT_RE = re.compile(r"\bpancit\b")
_NON_ALNUM_RE = re.compile(r"[^a-z0-9]+")


def dense(s: str) -> str:
    """Lowercase, fold Pinoy variants, strip ALL non-alphanumeric."""
    s = s.lower().replace("ñ", "n")
    s = _PANCIT_RE.sub("pansit", s)
    return _NON_ALNUM_RE.sub("", s)


def normalize_aliases(aliases: list[str]) -> tuple[str, str]:
    """Returns (raw, normalized) — raw is comma-joined originals,
    normalized is per-alias densified, space-separated so FTS5 trigrams
    don't span across distinct aliases."""
    cleaned = [a.strip() for a in aliases if a and a.strip()]
    raw = ",".join(cleaned)
    norm = " ".join(dense(a) for a in cleaned if dense(a))
    return raw, norm


def main() -> int:
    if not DB_PATH.exists():
        sys.exit(f"food DB not found at {DB_PATH}")
    if not ALIASES_PATH.exists():
        sys.exit(
            f"aliases file not found at {ALIASES_PATH}\n"
            "Run `python scripts/build_food_aliases.py` first."
        )

    print(f"Loading aliases from {ALIASES_PATH.relative_to(ROOT)}...")
    with ALIASES_PATH.open("r", encoding="utf-8") as f:
        aliases_by_id: dict[str, list[str]] = json.load(f)
    print(f"  {len(aliases_by_id)} entries")

    print(f"Opening DB {DB_PATH.relative_to(ROOT)}...")
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()

        # Add columns if not already present (idempotent — safe to re-run).
        existing_cols = {row[1] for row in cur.execute("PRAGMA table_info(foods)")}
        if "aliases" not in existing_cols:
            print("Adding `aliases` column...")
            cur.execute("ALTER TABLE foods ADD COLUMN aliases TEXT DEFAULT ''")
        if "aliases_norm" not in existing_cols:
            print("Adding `aliases_norm` column...")
            cur.execute("ALTER TABLE foods ADD COLUMN aliases_norm TEXT DEFAULT ''")

        # Populate alias columns.
        all_ids = [row[0] for row in cur.execute("SELECT id FROM foods")]
        print(f"Updating {len(all_ids)} rows...")
        missing = 0
        updated = 0
        for fid in all_ids:
            aliases = aliases_by_id.get(fid, [])
            if not aliases:
                missing += 1
                continue
            raw, norm = normalize_aliases(aliases)
            cur.execute(
                "UPDATE foods SET aliases = ?, aliases_norm = ? WHERE id = ?",
                (raw, norm, fid),
            )
            updated += 1
        print(f"  updated {updated} rows; {missing} rows had no aliases")

        # Rebuild FTS5 to cover both name_norm and aliases_norm.
        print("Rebuilding FTS5 index...")
        cur.execute("DROP TABLE IF EXISTS foods_fts")
        cur.execute(
            """
            CREATE VIRTUAL TABLE foods_fts USING fts5(
                name_norm,
                aliases_norm,
                content='foods',
                content_rowid='rowid',
                tokenize='trigram case_sensitive 0'
            )
            """
        )
        cur.execute(
            "INSERT INTO foods_fts(rowid, name_norm, aliases_norm) "
            "SELECT rowid, name_norm, aliases_norm FROM foods"
        )

        conn.commit()

        # Sanity check.
        print("\nSanity checks:")
        for probe in [
            ("fried pork", "Pork Belly"),
            ("kanin", "Rice"),
            ("lechon kawali", "Pork"),
            ("alfredo", "Fettuccine"),
        ]:
            query, expected_substring = probe
            dense_q = dense(query)
            rows = cur.execute(
                "SELECT f.name FROM foods f JOIN foods_fts ON foods_fts.rowid = f.rowid "
                "WHERE foods_fts MATCH ? ORDER BY bm25(foods_fts, 2.0, 1.0) LIMIT 3",
                (f'"{dense_q}"',),
            ).fetchall()
            names = [r[0] for r in rows]
            ok = any(expected_substring.lower() in n.lower() for n in names)
            mark = "OK" if ok else "??"
            print(f"  [{mark}] '{query}' -> {names}")

        # Vacuum to shrink the file.
        print("\nVacuuming...")
        conn.commit()
        conn.execute("VACUUM")

    finally:
        conn.close()

    size_kb = DB_PATH.stat().st_size // 1024
    print(f"\nDone. {DB_PATH.relative_to(ROOT)} is now {size_kb} KB.")
    print("Next: bump `_dbFilename` in lib/services/food_db_service.dart to v10.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

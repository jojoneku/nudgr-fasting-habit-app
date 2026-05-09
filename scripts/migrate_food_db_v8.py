"""
migrate_food_db_v8.py — In-place schema bump for assets/food_db.sqlite (v7 -> v8).

Adds a `name_norm` column with all-lowercase, alphanumeric-only,
Pinoy-variant-folded forms ("Bear Brand Sterilized Milk" -> "bearbrandsterilizedmilk",
"Pancit Canton" -> "pansitcanton"), then rebuilds foods_fts using the trigram
tokenizer over name_norm. Trigram FTS5 supports substring matching, which
collapses brand-token spacing differences ("bearbrand" vs "bear brand") and
mid-word retrieval ("milk" inside "Kefir, Plain" — n/a, but "rolled" inside
"Oats, Rolled, Dry" — yes).

This is a pure in-place migration: it does NOT re-download USDA data. Run after
modifying scripts/import_usda_fdc.py for fresh full rebuilds, but for repointing
an existing v7 asset it's the fast path.

Usage:
    python scripts/migrate_food_db_v8.py
"""

import os
import re
import sqlite3

# Mirrors lib/services/food_db_service.dart::_normalizeForSearch.
# Keep in sync with the Dart side or queries won't match the index.
_PANCIT_RE = re.compile(r"\bpancit\b")
_NON_ALPHANUM_RE = re.compile(r"[^a-z0-9]+")


def normalize_for_search(name: str) -> str:
    s = name.lower().replace("ñ", "n")
    s = _PANCIT_RE.sub("pansit", s)
    s = _NON_ALPHANUM_RE.sub("", s)
    return s


def main() -> None:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    db_path = os.path.join(repo_root, "assets", "food_db.sqlite")

    if not os.path.exists(db_path):
        raise SystemExit(f"food_db.sqlite not found at {db_path}")

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Drop old FTS5 + triggers — name column based, default tokenizer.
    cur.execute("DROP TRIGGER IF EXISTS foods_ai")
    cur.execute("DROP TABLE IF EXISTS foods_fts")

    # Add name_norm if missing; populate from name.
    cols = {row[1] for row in cur.execute("PRAGMA table_info(foods)").fetchall()}
    if "name_norm" not in cols:
        cur.execute("ALTER TABLE foods ADD COLUMN name_norm TEXT")

    rows = cur.execute("SELECT rowid, name FROM foods").fetchall()
    cur.executemany(
        "UPDATE foods SET name_norm = ? WHERE rowid = ?",
        [(normalize_for_search(name), rowid) for rowid, name in rows],
    )

    # Trigram-tokenized FTS5 over name_norm. case_sensitive 0 lets us pass
    # already-lowered queries without further conversion.
    cur.execute(
        """
        CREATE VIRTUAL TABLE foods_fts USING fts5(
            name_norm,
            content='foods',
            content_rowid='rowid',
            tokenize='trigram case_sensitive 0'
        )
        """
    )
    cur.execute(
        """
        CREATE TRIGGER foods_ai AFTER INSERT ON foods BEGIN
            INSERT INTO foods_fts(rowid, name_norm) VALUES (new.rowid, new.name_norm);
        END
        """
    )

    # Backfill the FTS index from the existing rows.
    cur.execute(
        "INSERT INTO foods_fts(rowid, name_norm) "
        "SELECT rowid, name_norm FROM foods"
    )

    conn.commit()
    cur.execute("VACUUM")
    conn.close()

    size_kb = os.path.getsize(db_path) / 1024
    print(f"OK: {db_path} migrated to v8 ({size_kb:.0f} KB on disk, {len(rows):,} rows)")


if __name__ == "__main__":
    main()

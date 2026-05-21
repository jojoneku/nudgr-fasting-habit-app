# scripts/

Build-time tooling for the food database. All scripts are one-shot — run
once when source data or DB schema changes, commit the regenerated
artifacts.

## Food DB pipeline

```
USDA + PH brand data  ──►  build_food_db.py        ──►  assets/food_db.sqlite (v9)
                                                          │
                                                          ▼
                            build_food_aliases.py   ──►  assets/data/food_aliases.json
                                  (claude -p)             │
                                                          ▼
                            migrate_food_db_v10.py  ──►  assets/food_db_v10.sqlite
                                                          (bundled with app)
```

### `build_food_aliases.py` — Plan 026 Phase 1

Generates 8–12 colloquial aliases + descriptive phrases per food row by
batching through the local `claude -p` CLI. **No API key required** —
uses your Claude Code subscription.

**First-time setup:** ensure `claude --version` works in your shell.

**Run:**

```bash
# Dry-run on first 100 entries — sanity-check quality
python scripts/build_food_aliases.py --dry-run

# Full run (~30–60 min for ~16k entries, resumable)
python scripts/build_food_aliases.py

# Resume after interruption (default behavior — re-run the full command)
python scripts/build_food_aliases.py

# Skip generation, just merge existing shards into the output file
python scripts/build_food_aliases.py --merge-only
```

**Outputs:**

- `scripts/data/aliases_shards/batch_NNNNN.json` — per-batch cache (gitignored)
- `assets/data/food_aliases.json` — merged output (committed)

**If a batch fails:** the script prints the error and continues. Re-run
the command to retry failed batches; successful shards are skipped.

**Quality QA:** after the first full run, spot-check `food_aliases.json`
for ~30 random entries. Look for:
- Aliases that contradict the food (e.g., chicken-named alias on a pork dish)
- Generic phrases used by many foods ("good food", "meal")
- Missing PH-specific names on dishes that should have them

Delete bad shards from `scripts/data/aliases_shards/` and re-run to regenerate.

### `migrate_food_db_v10.py` — Plan 026 Phase 2

Merges `food_aliases.json` into a new `food_db_v10.sqlite` with FTS5
indexing both `name_norm` and `aliases`. Run once after Phase 1 is done.

```bash
python scripts/migrate_food_db_v10.py
```

### `build_food_db.py`, `import_usda_fdc.py`, `load_philfct.py`

Source-of-truth data ingestion. Re-run when adding new foods.

### `migrate_food_db_v8.py`

Legacy migration. Kept for history; not part of the current pipeline.

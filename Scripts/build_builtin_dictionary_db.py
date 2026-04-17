#!/usr/bin/env python3
"""
Build bundled SQLite dictionary from ECDICT CSV.

Output:
  Sources/Lumina/Resources/builtin_dictionary.sqlite3
"""

from __future__ import annotations

import csv
import sqlite3
import tempfile
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "Lumina" / "Resources"
OUT_DB = RESOURCES / "builtin_dictionary.sqlite3"
ECDICT_URL = "https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv"


def normalize_definition(row: dict[str, str]) -> str:
    parts = []
    for key in ("translation", "definition", "pos"):
        value = (row.get(key) or "").strip()
        if value:
            parts.append(value)
    return " | ".join(parts)[:4000]


def main() -> None:
    RESOURCES.mkdir(parents=True, exist_ok=True)

    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
        tmp_path = Path(tmp.name)

    print(f"Downloading ECDICT from {ECDICT_URL}")
    urllib.request.urlretrieve(ECDICT_URL, tmp_path)

    if OUT_DB.exists():
        OUT_DB.unlink()

    conn = sqlite3.connect(OUT_DB)
    cur = conn.cursor()
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS entries(
            word TEXT PRIMARY KEY,
            phonetic_us TEXT NOT NULL DEFAULT '',
            phonetic_uk TEXT NOT NULL DEFAULT '',
            definition TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_entries_word ON entries(word);
        """
    )

    inserted = 0
    cur.execute("BEGIN TRANSACTION")
    with tmp_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = (row.get("word") or "").strip()
            if not word:
                continue
            phonetic = (row.get("phonetic") or "").strip()
            definition = normalize_definition(row)
            if not definition:
                continue
            cur.execute(
                """
                INSERT OR REPLACE INTO entries(word, phonetic_us, phonetic_uk, definition)
                VALUES (?, ?, ?, ?)
                """,
                (word, phonetic, phonetic, definition),
            )
            inserted += 1
    conn.commit()

    count = cur.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
    conn.close()
    tmp_path.unlink(missing_ok=True)

    print(f"Inserted rows: {inserted}")
    print(f"Unique entries: {count}")
    print(f"Output DB: {OUT_DB}")


if __name__ == "__main__":
    main()

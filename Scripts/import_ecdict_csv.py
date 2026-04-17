#!/usr/bin/env python3
"""
Import ECDICT CSV into Lumina SQLite dictionary.

Usage:
  python Scripts/import_ecdict_csv.py /path/to/ecdict.csv
"""

from __future__ import annotations

import csv
import sqlite3
import sys
from pathlib import Path


def normalize_definition(row: dict[str, str]) -> str:
    candidates = [
        row.get("translation", ""),
        row.get("definition", ""),
        row.get("pos", ""),
    ]
    parts = [p.strip() for p in candidates if p and p.strip()]
    return " | ".join(parts)[:2000]


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python Scripts/import_ecdict_csv.py /path/to/ecdict.csv")
        return 1

    csv_path = Path(sys.argv[1]).expanduser().resolve()
    if not csv_path.exists():
        print(f"CSV not found: {csv_path}")
        return 1

    db_path = Path.home() / "Library" / "Application Support" / "Lumina" / "dictionaries" / "ecdict.sqlite3"
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
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

    with csv_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = []
        for row in reader:
            word = (row.get("word") or row.get("headword") or "").strip()
            if not word:
                continue

            phonetic = (row.get("phonetic") or "").strip()
            phonetic_us = (row.get("phonetic_us") or phonetic).strip()
            phonetic_uk = (row.get("phonetic_uk") or phonetic).strip()
            definition = normalize_definition(row)
            if not definition:
                continue

            rows.append((word, phonetic_us, phonetic_uk, definition))

    cur.execute("BEGIN TRANSACTION")
    cur.executemany(
        """
        INSERT OR REPLACE INTO entries(word, phonetic_us, phonetic_uk, definition)
        VALUES (?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()

    print(f"Imported {len(rows)} rows into {db_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

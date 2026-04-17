# Lumina Dictionary Data

Lumina now uses SQLite as the local dictionary backend.

## Built-in Dictionary (Default)

- The app ships with a bundled large SQLite dictionary:
  `Sources/Lumina/Resources/builtin_dictionary.sqlite3`
- It is generated from **ECDICT** and contains hundreds of thousands of entries.
- On launch, if local DB is missing or too small, the app auto-installs/replaces it.
- Users can query common words immediately without manual import.

## Chosen Large Dictionary

- **ECDICT** (English-Chinese Dictionary Database)
- Reason: widely used, open-source, large vocabulary, suitable for offline lookup and candidate search.

## Import ECDICT CSV

1. Download `ecdict.csv` from an ECDICT source.
2. Run:

```bash
cd /Users/pinli/Workshop/Lumina
python Scripts/import_ecdict_csv.py /path/to/ecdict.csv
```

3. The data will be imported to:

`~/Library/Application Support/Lumina/dictionaries/ecdict.sqlite3`

After import, restart the app to use the new data.

## In-app Custom Dictionary Import

- Open `Settings` in the sidebar.
- Click `导入自定义 TSV/CSV 词典`.
- The app imports your file into the same SQLite database.

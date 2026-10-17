"""Regenerates ResourceEfficiencyTooltips/SpellCoefficients.lua from the spell database.

Runs SELECT_RET_SPELL_DATA_AS_LUA.sql against spelldb.db (both in the same data/<date>/ folder,
newest by default) and writes the rows into the Lua file under a header with the generation time.
The database is opened read-only, so it's safe to run while a database browser has it open.

Usage (from anywhere):
    python scripts/generate_spell_coefficients.py
    python scripts/generate_spell_coefficients.py --data data/2026_10_17
"""

import argparse
import datetime
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUTPUT = REPO / "ResourceEfficiencyTooltips" / "SpellCoefficients.lua"
DB_NAME = "spelldb.db"
SQL_NAME = "SELECT_RET_SPELL_DATA_AS_LUA.sql"
LUAC_FALLBACK = Path(r"C:\tools\lua51\luac5.1.exe")

# Kept to the generation time only, since the file ships; the format is documented in the query.
HEADER = """\
-- Generated {timestamp} from {source} by scripts/generate_spell_coefficients.py
local _, ns = ...
ns.SPELL_COEFFICIENTS = {{
"""


def newest_data_folder():
    """The newest data/<date>/ folder that has a database, by folder name (they're named by date)."""
    folders = sorted(p.parent for p in (REPO / "data").glob("*/" + DB_NAME))
    if not folders:
        sys.exit("No data/*/%s found." % DB_NAME)
    return folders[-1]


def find_luac():
    found = shutil.which("luac5.1")
    if found:
        return found
    return str(LUAC_FALLBACK) if LUAC_FALLBACK.exists() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", type=Path, help="data folder holding %s and %s (default: newest)" % (DB_NAME, SQL_NAME))
    args = parser.parse_args()

    folder = (args.data if args.data.is_absolute() else Path.cwd() / args.data).resolve() if args.data else newest_data_folder()
    db_path, sql_path = folder / DB_NAME, folder / SQL_NAME
    for path in (db_path, sql_path):
        if not path.exists():
            sys.exit("Not found: %s" % path)

    db = sqlite3.connect("file:%s?mode=ro" % db_path.as_posix(), uri=True)
    try:
        rows = [row[0] for row in db.execute(sql_path.read_text(encoding="utf-8"))]
    finally:
        db.close()
    if not rows:
        sys.exit("The query returned no rows; %s left unchanged." % OUTPUT.name)
    if any(row is None or "\n" in row or "\r" in row for row in rows):
        sys.exit("The query returned an empty or multi-line row; %s left unchanged." % OUTPUT.name)

    timestamp = datetime.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    source = db_path.relative_to(REPO).as_posix() if db_path.is_relative_to(REPO) else db_path.as_posix()
    text = HEADER.format(timestamp=timestamp, source=source) + "\n".join(rows) + "\n}\n"

    # Write to a temporary file and check it compiles before replacing the real one.
    temp = OUTPUT.with_suffix(".lua.tmp")
    temp.write_text(text, encoding="utf-8", newline="\n")
    luac = find_luac()
    if luac:
        result = subprocess.run([luac, "-p", str(temp)], capture_output=True, text=True)
        if result.returncode != 0:
            temp.unlink()
            sys.exit("Generated Lua doesn't compile; %s left unchanged:\n%s" % (OUTPUT.name, result.stderr or result.stdout))
    else:
        print("luac5.1 not found; skipped the syntax check.")
    temp.replace(OUTPUT)

    print("Wrote %d spells to %s (from %s, %s)." % (len(rows), OUTPUT.relative_to(REPO).as_posix(), source, timestamp))


if __name__ == "__main__":
    main()

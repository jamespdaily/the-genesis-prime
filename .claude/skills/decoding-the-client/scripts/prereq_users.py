"""Print which game table columns name a Prerequisite row with a clause of each
given type, and how many rows of each column do, to find what a clause type gates.

It reads every `prerequisiteId...` column of every table but Prerequisite.tbl,
and skips a table wstbl cannot lay out.

Usage: python3 -I prereq_users.py <clause type> [<clause type> ...]
"""
import sys
from collections import Counter
from pathlib import Path

WILDSTAR = Path.home() / "Coding/wildstar"
sys.path.insert(0, str(WILDSTAR / "scripts"))
import wstbl  # noqa: E402

TABLES = WILDSTAR / "client-data/ClientData/DB"


def main():
    wanted = {int(arg) for arg in sys.argv[1:]}
    clause_types = {}
    for row in wstbl.rows(TABLES / "Prerequisite.tbl"):
        clause_types[row["ID"]] = {row[f"prerequisiteTypeId{clause}"] for clause in range(3)}
    rows_with = {wanted_type: {prerequisite_id for prerequisite_id, types in clause_types.items()
                               if wanted_type in types}
                 for wanted_type in wanted}
    for path in sorted(TABLES.glob("*.tbl")):
        if path.name == "Prerequisite.tbl":
            continue
        try:
            _, columns, _, _ = wstbl.layout(path)
        except Exception:  # a table wstbl cannot lay out names no prerequisite this script can read
            continue
        prerequisite_columns = [column[0] for column in columns if column[0].lower().startswith("prerequisiteid")]
        if not prerequisite_columns:
            continue
        counts = Counter()
        for row in wstbl.rows(path):
            for column in prerequisite_columns:
                for wanted_type in wanted:
                    if row[column] in rows_with[wanted_type]:
                        counts[(wanted_type, column)] += 1
        if counts:
            print(path.name, dict(counts))


if __name__ == "__main__":
    main()

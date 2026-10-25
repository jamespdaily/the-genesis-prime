"""Print how Prerequisite.tbl uses each clause type: how many clauses have it, their
comparisons, their most common objectId and value, and how many of those are
Spell4 or Spell4Base ids, which tells whether the type names a spell.

Usage: python3 -I prereq_stats.py <clause type> [<clause type> ...]
"""
import sys
from collections import Counter
from pathlib import Path

WILDSTAR = Path.home() / "Coding/wildstar"
sys.path.insert(0, str(WILDSTAR / "scripts"))
import wstbl  # noqa: E402

TABLES = WILDSTAR / "client-data/ClientData/DB"


def ids(name):
    return {row["ID"] for row in wstbl.rows(TABLES / f"{name}.tbl")}


def main():
    spells = ids("Spell4")
    spell_bases = ids("Spell4Base")
    rows = list(wstbl.rows(TABLES / "Prerequisite.tbl"))
    for clause_type in sorted({int(arg) for arg in sys.argv[1:]}):
        object_ids = Counter()
        values = Counter()
        comparisons = Counter()
        spell_matches = Counter()
        uses = 0
        for row in rows:
            for clause in range(3):
                if row[f"prerequisiteTypeId{clause}"] != clause_type:
                    continue
                uses += 1
                object_id = row[f"objectId{clause}"]
                value = row[f"value{clause}"]
                object_ids[object_id] += 1
                values[value] += 1
                comparisons[row[f"prerequisiteComparisonId{clause}"]] += 1
                spell_matches["obj in Spell4" if object_id in spells else "obj not Spell4"] += 1
                spell_matches["obj in Spell4Base" if object_id in spell_bases else "obj not Spell4Base"] += 1
                spell_matches["val in Spell4" if value in spells else "val not Spell4"] += 1
                spell_matches["val in Spell4Base" if value in spell_bases else "val not Spell4Base"] += 1
        print("TYPE", clause_type, "uses", uses)
        print(" cmp", dict(comparisons))
        print(" obj top", object_ids.most_common(8))
        print(" val top", values.most_common(8))
        print(" ", dict(spell_matches))


if __name__ == "__main__":
    main()

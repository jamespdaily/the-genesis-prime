"""Sample the QuestObjective rows of one type, with their quests' titles, the
objectives' own text and the clauses of each quest's prerequisite, to learn what
the type's `data` column names.

It prints the row count, the distinct `data` values, the most common counts and
flags, the clause types of the quests' prerequisites, then one line per sampled
objective: its data, count and flags, the first quest's title and id, the
objective's text, and that quest's prerequisite as (type, comparison, objectId,
value) clauses.

Usage: python3 -I quest_objectives.py <objective type> [<sample size, default 12>]
"""
import struct
import sys
from collections import Counter
from pathlib import Path

WILDSTAR = Path.home() / "Coding/wildstar"
sys.path.insert(0, str(WILDSTAR / "scripts"))
import wstbl  # noqa: E402

TABLES = WILDSTAR / "client-data/ClientData/DB"
TEXTS = WILDSTAR / "client-data/ClientDataEN/en-US.bin"
OBJECTIVE_COLUMNS = ("objective0", "objective01", "objective02", "objective03", "objective04", "objective05")


def text_reader():
    """A function from a text id to its English text, or "" for an id the file lacks."""
    data = TEXTS.read_bytes()
    count, record_offset, _, string_offset = struct.unpack_from("<QQQQ", data, 64)
    offsets = {}
    for index in range(count):
        text_id, offset = struct.unpack_from("<II", data, 96 + record_offset + index * 8)
        offsets[text_id] = offset

    def text(text_id):
        if text_id not in offsets:
            return ""
        start = 96 + string_offset + offsets[text_id] * 2
        end = start
        while data[end:end + 2] != b"\0\0":
            end += 2
        return data[start:end].decode("utf-16le")

    return text


def main():
    objective_type = int(sys.argv[1])
    sample_size = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    text = text_reader()
    objectives = {row["ID"]: row for row in wstbl.rows(TABLES / "QuestObjective.tbl")}
    clauses_of = {
        row["ID"]: [(row[f"prerequisiteTypeId{clause}"], row[f"prerequisiteComparisonId{clause}"],
                     row[f"objectId{clause}"], row[f"value{clause}"])
                    for clause in range(3) if row[f"prerequisiteTypeId{clause}"]]
        for row in wstbl.rows(TABLES / "Prerequisite.tbl")}
    quests_of = {}
    for quest in wstbl.rows(TABLES / "Quest2.tbl"):
        for column in OBJECTIVE_COLUMNS:
            objective_id = quest[column]
            if objective_id in objectives and objectives[objective_id]["type"] == objective_type:
                quests_of.setdefault(objective_id, []).append(quest)
    data_values = Counter()
    counts = Counter()
    flags = Counter()
    for objective in objectives.values():
        if objective["type"] == objective_type:
            data_values[objective["data"]] += 1
            counts[objective["count"]] += 1
            flags[objective["flags"]] += 1
    print("rows", sum(data_values.values()), "distinct data", len(data_values),
          "count top", counts.most_common(6), "flags top", flags.most_common(5))
    prerequisite_types = Counter()
    for quests in quests_of.values():
        for quest in quests:
            for clause in clauses_of.get(quest["prerequisiteId"], []):
                prerequisite_types[clause[0]] += 1
    print("quests", sum(len(quests) for quests in quests_of.values()),
          "quest prereq types", prerequisite_types.most_common(8))
    for objective_id, quests in list(quests_of.items())[:sample_size]:
        objective = objectives[objective_id]
        quest = quests[0]
        print(objective_id, "data", objective["data"], "count", objective["count"], "flags", objective["flags"],
              "|", text(quest["localizedTextIdTitle"]), "| quest", quest["ID"],
              "| objtext:", text(objective["localizedTextIdFull"])[:70],
              "| prereq", clauses_of.get(quest["prerequisiteId"]))


if __name__ == "__main__":
    main()

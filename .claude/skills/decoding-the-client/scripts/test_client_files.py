"""client_files tokens: the list of tooltip tokens, written from the client's texts and checked against them.

Expected values come from the client's own data and the layouts in the fact file, never from the code under
test. Every file here is planted, so no test touches the real client:
- en-US.bin is built in the layout of the fact file's language_file.layout ('XETL'; entries of a text id and a
  character offset, each text zero-terminated UTF-16LE).
- Spell4.tbl is built in the layout of game_table.file (a 0x60-byte header, the column table, the column names,
  the records) with the field placement of game_table.schema (a 4-byte field at the next multiple of 4, an 8-byte
  field at the next multiple of 8, in column order).
- The texts are the client's: 376222 (Pulse Blast), 445006 (Spell Surge) and 360105 (Electrocute), read with
  `client_files.py text <id>`. Text 376222 holds `$(eff=95337.data02rawint)` and 445006 holds
  `$(spell=72652)`, a token with no field. The token's form, `$(kind=id.field)`, is the design on issue 326
  (section 1); the client reads the id up to `.` and the field up to `)` (FormatSpellTooltipToken).
- A text id a Spell4 column names that the language file lacks has no tokens: GetLocalizedText answers an empty
  text for it (fact 0x14034bdd0's record).
Run: python3.13 -I -m unittest discover -s .claude/skills/decoding-the-client/scripts -p 'test_client_files.py'
"""

import contextlib
import io
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import client_files  # noqa: E402

TEXT_COLUMNS = [
    "localizedTextIdActionBarTooltip",
    "localizedTextIdCasterIconSpellText",
    "localizedTextIdPrimaryTargetIconSpellText",
    "localizedTextIdSecondaryTargetIconSpellText",
    "localizedTextIdTooltipCastInfo",
    "localizedTextIdTooltipCostInfo",
    "localizedTextIdLASTier",
]
# The column type numbers of game_table.column_type: 3 a 32-bit integer, 4 a float, 11 a boolean, 20 a 64-bit
# integer, 130 a string.
TYPE = {"i32": 3, "f32": 4, "bool": 11, "i64": 20, "string": 130}
SIZE = {"i32": 4, "f32": 4, "bool": 4, "i64": 8, "string": 8}
PACK = {"i32": "<i", "f32": "<f", "bool": "<I", "i64": "<q"}

PULSE_BLAST = "Deal $(eff=79090.input0pct) physical damage and generate $(eff=95337.data02rawint) Volatility."
SPELL_SURGE = "Requires $(spell=47273.lasData00) Spell Power. While active, $(spell=72652) drains Focus."
ELECTROCUTE = "Deal $(eff=92587.input0pct) technology damage to $(spell=41276.aoeTc) foes every $(spell=41276.channelPulseMS)s."


def language_file(texts: dict[int, str]) -> bytes:
    """en-US.bin: the header, the entries sorted by id, the zero-terminated UTF-16LE texts."""
    body, entries = b"", []
    for text_id in sorted(texts):
        entries.append(struct.pack("<II", text_id, len(body) // 2))
        body += texts[text_id].encode("utf-16-le") + b"\0\0"
    header = bytearray(0x60)
    header[:4] = b"XETL"
    struct.pack_into("<I", header, 0x40, len(entries))
    struct.pack_into("<QQQ", header, 0x48, 0, len(body) // 2, 8 * len(entries))
    return bytes(header) + b"".join(entries) + body


def game_table(name: str, columns: list[tuple[str, str]], rows: list[dict]) -> bytes:
    """A game table file with these columns (name, kind) and rows (column name to value, 0 or "" for the rest)."""
    offsets, at = [], 0
    for _, kind in columns:
        at = (at + SIZE[kind] - 1) // SIZE[kind] * SIZE[kind]
        offsets.append(at)
        at += SIZE[kind]
    record_size = at
    strings, string_at = b"", len(rows) * record_size
    records = b""
    for row in rows:
        record = bytearray(record_size)
        for (column, kind), offset in zip(columns, offsets):
            value = row.get(column, "" if kind == "string" else 0)
            if kind == "string":
                struct.pack_into("<Q", record, offset, string_at + len(strings))
                strings += value.encode("utf-16-le") + b"\0\0"
            else:
                struct.pack_into(PACK[kind], record, offset, value)
        records += bytes(record)
    table_name = name.encode("utf-16-le") + b"\0\0"
    column_table_at = (len(table_name) + 15) // 16 * 16
    names_at = column_table_at + (24 * len(columns) + 15) // 16 * 16
    names, entries = b"", b""
    for column, kind in columns:
        entries += struct.pack("<IIQH", len(column) + 1, 0, len(names), TYPE[kind]) + bytes(6)
        names += column.encode("utf-16-le") + b"\0\0"
    block_at = (names_at + len(names) + 15) // 16 * 16
    body = (table_name.ljust(column_table_at, b"\0") + entries.ljust(names_at - column_table_at, b"\0") + names).ljust(block_at, b"\0")
    body += records + strings
    header = struct.pack(
        "<IIQQQQQQQQQQQ",
        0x4454424C, 0, len(name) + 1, 0, record_size, len(columns), column_table_at, len(rows),
        len(records) + len(strings), block_at, 0, 0, 0,
    )
    return header + body


def spell4_table(rows: list[dict]) -> bytes:
    """Spell4.tbl with columns before, between and after the seven text columns, so a wrong placement misreads."""
    columns = [("ID", "i32"), ("description", "string"), ("spellDuration", "i32"), ("targetMaxRange", "f32")]
    columns += [(TEXT_COLUMNS[0], "i32"), ("ravelInstanceId", "i64")] + [(name, "i32") for name in TEXT_COLUMNS[1:]]
    columns += [("flags", "bool")]
    return game_table("Spell4", columns, rows)


class Planted(unittest.TestCase):
    """A client files folder and a tables folder under a temporary folder, and the list's place."""

    def setUp(self):
        self._root = tempfile.TemporaryDirectory()
        self.addCleanup(self._root.cleanup)
        root = Path(self._root.name)
        self.files, self.tables, self.list = root / "client-files", root / "tables", root / "tokens" / "tokens.tsv"
        self.files.mkdir()
        self.tables.mkdir()
        self.env = {"GENESIS_CLIENT_FILES_DIR": str(self.files), "GENESIS_TABLE_DIR": str(self.tables)}

    def plant(self, texts: dict[int, str], spells: list[dict]) -> None:
        (self.files / client_files.LANGUAGE_FILE).write_bytes(language_file(texts))
        (self.tables / "Spell4.tbl").write_bytes(spell4_table(spells))

    def run_tokens(self, *flags: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stderr(err):
            status = client_files.main(["tokens", *flags, "--list", str(self.list)], self.env, out)
        return status, out.getvalue(), err.getvalue()

    def written(self) -> list[list[str]]:
        """The list's rows after its header, split on tabs."""
        lines = self.list.read_text().splitlines()
        self.assertEqual(lines[0], "text_id\tkind\tid\tfield")
        return [line.split("\t") for line in lines[1:]]


class WriteTest(Planted):
    def test_each_token_of_a_text_a_column_names_is_a_row_with_kind_and_field_in_lower_case(self):
        self.plant({376222: PULSE_BLAST}, [{"ID": 42276, localized: 376222} for localized in TEXT_COLUMNS[:1]])
        status, _, _ = self.run_tokens("--write")
        self.assertEqual(status, 0)
        self.assertEqual(self.written(), [["376222", "eff", "79090", "input0pct"], ["376222", "eff", "95337", "data02rawint"]])

    def test_the_kind_and_the_field_are_written_in_lower_case_whatever_the_text_holds(self):
        self.plant({360105: ELECTROCUTE}, [{"ID": 41276, "localizedTextIdActionBarTooltip": 360105}])
        self.run_tokens("--write")
        self.assertEqual(
            self.written(),
            [["360105", "eff", "92587", "input0pct"], ["360105", "spell", "41276", "aoetc"], ["360105", "spell", "41276", "channelpulsems"]],
        )

    def test_a_token_with_no_field_is_a_row_with_an_empty_field(self):
        self.plant({445006: SPELL_SURGE}, [{"ID": 47273, "localizedTextIdTooltipCastInfo": 445006}])
        self.run_tokens("--write")
        self.assertEqual(self.written(), [["445006", "spell", "47273", "lasdata00"], ["445006", "spell", "72652", ""]])

    def test_every_one_of_the_seven_text_columns_is_read(self):
        texts = {1000 + i: "$(eff=%d.input0)" % (500 + i) for i in range(len(TEXT_COLUMNS))}
        spell = {"ID": 1, **{column: 1000 + i for i, column in enumerate(TEXT_COLUMNS)}}
        self.plant(texts, [spell])
        self.run_tokens("--write")
        self.assertEqual(
            self.written(), [[str(1000 + i), "eff", str(500 + i), "input0"] for i in range(len(TEXT_COLUMNS))]
        )

    def test_a_text_named_by_several_spells_is_listed_once_and_a_repeated_token_in_a_text_once(self):
        self.plant({7: "$(eff=1.input0) and again $(eff=1.input0)"}, [
            {"ID": 1, "localizedTextIdActionBarTooltip": 7},
            {"ID": 2, "localizedTextIdLASTier": 7},
        ])
        self.run_tokens("--write")
        self.assertEqual(self.written(), [["7", "eff", "1", "input0"]])

    def test_the_rows_are_in_text_id_order_and_a_text_without_tokens_or_missing_from_the_file_has_none(self):
        self.plant({50: "$(eff=2.input0)", 20: "plain words", 30: "$(spell=3)"}, [
            {"ID": 1, "localizedTextIdActionBarTooltip": 50, "localizedTextIdLASTier": 30},
            {"ID": 2, "localizedTextIdActionBarTooltip": 20, "localizedTextIdTooltipCastInfo": 99999},
            {"ID": 3},
        ])
        self.run_tokens("--write")
        self.assertEqual(self.written(), [["30", "spell", "3", ""], ["50", "eff", "2", "input0"]])

    def test_the_list_holds_no_english_text(self):
        self.plant({376222: PULSE_BLAST}, [{"ID": 42276, "localizedTextIdActionBarTooltip": 376222}])
        self.run_tokens("--write")
        for word in ("Deal", "physical", "Volatility", "damage"):
            self.assertNotIn(word, self.list.read_text())

    def test_a_text_column_missing_from_spell4_is_refused_naming_it_and_nothing_is_written(self):
        columns = [("ID", "i32")] + [(name, "i32") for name in TEXT_COLUMNS if name != "localizedTextIdLASTier"]
        (self.files / client_files.LANGUAGE_FILE).write_bytes(language_file({1: "x"}))
        (self.tables / "Spell4.tbl").write_bytes(game_table("Spell4", columns, [{"ID": 1}]))
        status, _, err = self.run_tokens("--write")
        self.assertEqual(status, 1)
        self.assertIn("localizedTextIdLASTier", err)
        self.assertFalse(self.list.exists())

    def test_no_language_file_says_to_run_extract(self):
        (self.tables / "Spell4.tbl").write_bytes(spell4_table([]))
        status, _, err = self.run_tokens("--write")
        self.assertEqual(status, 1)
        self.assertIn("run extract", err)

    def test_no_spell4_table_says_to_run_extract_tables(self):
        (self.files / client_files.LANGUAGE_FILE).write_bytes(language_file({1: "x"}))
        status, _, err = self.run_tokens("--write")
        self.assertEqual(status, 1)
        self.assertIn("extract_tables.py", err)


class IrregularTokenTest(Planted):
    """A `$(` is read as the client reads it (FormatTextTokens 0x1400c12b0): a form it prints nothing for is no row, is
    named with its text id and why, and does not stop the write or touch the text's other tokens."""

    def write_text(self, text: str) -> tuple[list[list[str]], str]:
        self.plant({424242: text}, [{"ID": 1, "localizedTextIdActionBarTooltip": 424242}])
        status, out, _ = self.run_tokens("--write")
        self.assertEqual(status, 0, text)
        return self.written(), out

    def test_each_form_the_client_prints_nothing_for_is_no_row_and_is_named_with_its_text_id(self):
        for text in (
            "Deal $(eff=.input0pct) damage.",  # no id: wcstol gives 0 and every evaluator refuses 0
            "Deal $(eff=id.input0) damage.",  # the id is not a number
            "Deal $(eff=0.input0) damage.",  # id 0
            "Deal $(eff=61017.tickTimeMS seconds.",  # no closing parenthesis: the rest of the text is the token
            "Deal $(eff=216424.) percent.",  # a dot and no field
            "Deal $(eff = 73075.input0) percent.",  # a space between the kind and the equals sign: no kind matches
            "Deal $(#####.data02int) percent.",
            "Deal $(no equals sign) percent.",
        ):
            with self.subTest(text=text):
                rows, out = self.write_text(text)
                self.assertEqual(rows, [])
                self.assertIn("424242", out)

    def test_an_eff_token_with_no_dot_is_the_spell_row_the_client_falls_through_to(self):
        # ReadKindToken 0x1400b8010 tries spell= with the id eff= matched when eff= gives nothing, and
        # FormatSpellTooltipToken 0x1404df2c0 finds no '.' and prints the spell's name: texts 735915, 749242, 235966,
        # 700085 and 712161 of the client's file hold these forms.
        for body, spell_id in (
            ("eff=83598", "83598"),
            ("eff=60984data03raw", "60984"),
            ("eff=216424input0", "216424"),
            ("eff=217650input0actual", "217650"),
        ):
            with self.subTest(body=body):
                rows, out = self.write_text("Deal $(%s) damage." % body)
                self.assertEqual(rows, [["424242", "spell", spell_id, ""]])
                self.assertNotIn("left out", out)

    def test_an_eff_token_with_a_dot_and_no_field_stays_unread(self):
        rows, out = self.write_text("Deal $(eff=216424.) percent.")
        self.assertEqual(rows, [])
        self.assertIn("424242", out)

    def test_a_field_that_runs_over_other_text_is_no_row_and_the_scan_goes_on_after_its_parenthesis(self):
        rows, out = self.write_text("Every $(eff=61017.tickTimeMS seconds. Deal $(eff=5.input0) and $(eff=6.input1) more")
        self.assertEqual(rows, [["424242", "eff", "6", "input1"]])  # the client's field for 61017 ends at the first ")"
        self.assertIn("424242", out)

    def test_the_other_tokens_of_a_text_with_an_irregular_one_stay(self):
        rows, _ = self.write_text("$(eff=1.input0) $(eff=.input0) $(eff=2.input1)")
        self.assertEqual(rows, [["424242", "eff", "1", "input0"], ["424242", "eff", "2", "input1"]])

    def test_the_kind_is_matched_without_case_and_written_in_lower_case(self):
        rows, _ = self.write_text("$(Eff=3.Input0) $(SPELL=4.AbTooltip)")
        self.assertEqual(rows, [["424242", "eff", "3", "input0"], ["424242", "spell", "4", "abtooltip"]])

    def test_spaces_before_the_id_are_read_as_the_client_reads_them(self):
        rows, _ = self.write_text("$(eff= 206216.tickTimeMS)")  # wcstol skips them, so the client prints a value
        self.assertEqual(rows, [["424242", "eff", "206216", "ticktimems"]])

    def test_a_token_that_names_a_spell_or_a_creature_with_no_field_is_a_link_row(self):
        rows, _ = self.write_text("$(spell=72652) $(creature=73075) $(item=9) $(achievement=10)")
        self.assertEqual(
            rows,
            [["424242", "spell", "72652", ""], ["424242", "creature", "73075", ""], ["424242", "item", "9", ""], ["424242", "achievement", "10", ""]],
        )

    def test_a_second_dot_stays_in_the_field(self):
        rows, _ = self.write_text("$(eff=65912.data02.pctAdd)")
        self.assertEqual(rows, [["424242", "eff", "65912", "data02.pctadd"]])

    def test_a_text_with_only_regular_tokens_names_no_irregular_form(self):
        _, out = self.write_text("$(eff=1.input0)")
        self.assertNotIn("left out", out)


class CheckTest(Planted):
    def written_list(self) -> str:
        self.plant({376222: PULSE_BLAST, 445006: SPELL_SURGE}, [
            {"ID": 42276, "localizedTextIdActionBarTooltip": 376222},
            {"ID": 47273, "localizedTextIdTooltipCastInfo": 445006},
        ])
        self.run_tokens("--write")
        return self.list.read_text()

    def test_a_list_equal_to_a_fresh_write_is_current_and_exits_0(self):
        self.written_list()
        status, out, _ = self.run_tokens("--check")
        self.assertEqual((status, out.strip()), (0, "current"))

    def test_a_list_whose_tokens_differ_names_each_differing_text_id_and_exits_1(self):
        written = self.written_list()
        # 376222's field changed, 445006's token removed, and 999 is a text the file does not name.
        stale = written.replace("data02rawint", "data03rawint").replace("445006\tspell\t72652\t\n", "") + "999\teff\t5\tinput0\n"
        self.list.write_text(stale)
        status, out, _ = self.run_tokens("--check")
        self.assertEqual(status, 1)
        for text_id in ("376222", "445006", "999"):
            self.assertIn(text_id, out)
        self.assertNotIn("360105", out)

    def test_a_text_that_changed_in_the_client_file_is_named(self):
        self.written_list()
        self.plant({376222: PULSE_BLAST.replace("95337", "95338"), 445006: SPELL_SURGE}, [
            {"ID": 42276, "localizedTextIdActionBarTooltip": 376222},
            {"ID": 47273, "localizedTextIdTooltipCastInfo": 445006},
        ])
        status, out, _ = self.run_tokens("--check")
        self.assertEqual(status, 1)
        self.assertIn("376222", out)
        self.assertNotIn("445006", out)

    def test_no_list_says_to_run_write_and_exits_1(self):
        self.plant({1: "x"}, [{"ID": 1}])
        status, out, err = self.run_tokens("--check")
        self.assertEqual(status, 1)
        self.assertIn("tokens --write", out + err)

    def test_check_changes_nothing(self):
        written = self.written_list()
        self.list.write_text(written + "999\teff\t5\tinput0\n")
        before = self.list.read_bytes()
        self.run_tokens("--check")
        self.assertEqual(self.list.read_bytes(), before)

    def test_write_and_check_are_alternatives_and_one_is_required(self):
        for flags in ((), ("--write", "--check")):
            with self.subTest(flags=flags), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    client_files.main(["tokens", *flags], self.env, io.StringIO())


if __name__ == "__main__":
    unittest.main()

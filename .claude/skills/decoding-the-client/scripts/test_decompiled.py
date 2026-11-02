"""decompiled.py: the saved copy of every function's decompiled C, and when it is stale.

Most tests run a planted client that answers the query process's requests (`functions`,
`function_at`, `decompile`) from a small function table, so they need neither Ghidra nor the
client. Its decompiled text names each callee as Ghidra does: by its current name, or by its
address while the callee is no function. The tests under GENESIS_INTEGRATION=1 run the real
query process on a scoped function set of a project built from the client, in a temporary
folder; a rename in them is made in a copy of that project by name_functions.apply_names, the
rename the skill's own tool makes.

Expected values: the file layout is decompiled.py's own contract (one file per function, named by
its address, whose first line names the function, its address and the hash it was made under);
the hash of a table is its sha256 over the sorted lines "<address> <name>", first 16 hex digits,
computed here with shasum -a 256 on those lines, not by the code under test.
Run: python3 -I test_decompiled.py   (GENESIS_INTEGRATION=1 adds the real-process tests)
"""

import io
import json
import os
import subprocess
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_facts  # noqa: E402
import check_support as cs  # noqa: E402
import decompiled  # noqa: E402
import query  # noqa: E402
from query_client import QueryClient, QueryFailed, QueryProcessEnded, QueryTimeout, open_query_client  # noqa: E402
PLANTED_CALLER = 0x140000100
PLANTED_CALLEE = 0x140000200
PLANTED_BYSTANDER = 0x140000300
PLANTED_ADDED = 0x140000400
PLANTED_FAILING = 0x140000500

# shasum -a 256 over base_names()'s lines "<address> <name>", one per line in address order,
# first 16 hex digits
BASE_HASH = "7e1fb996056cd649"
# the same for the lines of {PLANTED_CALLER: "A", PLANTED_CALLEE: "B"} and, swapped, of
# {PLANTED_CALLER: "B", PLANTED_CALLEE: "A"}
HASH_OF_A_AND_B = "ec4d51854cccc764"
HASH_OF_B_AND_A = "9dba1b40584d5159"


def base_names() -> dict[int, str]:
    return {
        PLANTED_CALLER: "HandleCaller",
        PLANTED_CALLEE: "FUN_%x" % PLANTED_CALLEE,
        PLANTED_BYSTANDER: "Bystander",
        PLANTED_FAILING: "FailsToDecompile",
    }


PLANTED_POINTER_USER = 0x140000600
PLANTED_POINTER = 0x140000700
PLANTED_POINTER_TO_ADDED = 0x140000800
# pointer address -> the address it points to
POINTERS = {PLANTED_POINTER: PLANTED_CALLEE, PLANTED_POINTER_TO_ADDED: PLANTED_ADDED}


class PlantedClient:
    """Answers the query process's requests from a function table, and notes each decompile asked.

    PLANTED_CALLER calls PLANTED_CALLEE and PLANTED_ADDED. Its text writes a callee that is a function
    by its current name, and one that is no function by its address, as Ghidra's C does.
    PLANTED_POINTER_USER, where the table has it, calls through each pointer in POINTERS by the label
    Ghidra gives the pointer: PTR_FUN_<pointer address> for a default-named target, PTR_<name>_<pointer
    address> for a named one, PTR_DAT_<pointer address> where the target is no function; the label holds
    neither the target's name nor its address.

    ends_after: the decompile that raises QueryProcessEnded; refuses: a request kind answered with an
    error reply; close_raises: what close() raises."""

    def __init__(
        self,
        names: dict[int, str],
        failing=(),
        ends_after: int | None = None,
        refuses: str | None = None,
        close_raises: Exception | None = None,
    ):
        self.names = dict(names)
        self.failing = set(failing)
        self.ends_after = ends_after
        self.refuses = refuses
        self.close_raises = close_raises
        self.decompiled: list[int] = []

    def pointer_label(self, pointer: int) -> str:
        name = self.names.get(POINTERS[pointer])
        stem = "DAT" if name is None else "FUN" if name.startswith("FUN_") else name
        return "PTR_%s_%x" % (stem, pointer)

    def text(self, address: int) -> str:
        calls = [PLANTED_CALLEE, PLANTED_ADDED] if address == PLANTED_CALLER else []
        body = "".join(
            "  %s();\n" % self.names[c] if c in self.names else "  (*(code *)0x%x)();\n" % c for c in calls
        )
        if address == PLANTED_POINTER_USER:
            body = "".join("  (*%s)();\n" % self.pointer_label(p) for p in sorted(POINTERS))
        return "\nvoid %s(void)\n\n{\n%s}\n" % (self.names[address], body)

    def answer(self, kind: str, timeout=None, **arguments):
        if kind == self.refuses:
            raise QueryFailed("planted refusal of " + kind)
        if kind == "functions":
            return ["0x%x" % a for a in sorted(self.names)]
        if kind == "refs_to":
            target = int(arguments["address"], 16)
            return [
                {"from": "0x%x" % pointer, "type": "DATA", "function": None}
                for pointer in sorted(POINTERS)
                if POINTERS[pointer] == target
            ]
        address = int(arguments["address" if kind == "function_at" else "function"], 16)
        if kind == "function_at":
            return {"start": "0x%x" % address, "name": self.names[address]}
        assert kind == "decompile", kind
        if self.ends_after is not None and len(self.decompiled) >= self.ends_after:
            raise QueryProcessEnded("planted: the query process ended")
        self.decompiled.append(address)
        if address in self.failing:
            raise QueryFailed("the decompile of 0x%x failed: planted" % address)
        return {"signature": "void f(void)", "c": self.text(address)}

    def close(self):
        if self.close_raises is not None:
            raise self.close_raises

    def kill(self):
        pass


def read_state(directory: Path) -> dict:
    return json.loads((directory / "state.json").read_text())


def file_of(directory: Path, address: int) -> Path:
    return directory / ("0x%x.c" % address)


def first_line(directory: Path, address: int) -> str:
    return file_of(directory, address).read_text().split("\n", 1)[0]


def functions_saved(directory: Path) -> set[int]:
    return {int(p.stem, 16) for p in directory.glob("0x*.c")}


class TemporaryDirectoryTest(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.directory = Path(self._temporary.name) / "copy"


class RefreshWithNoCopyTest(TemporaryDirectoryTest):
    """Item 1."""

    def setUp(self):
        super().setUp()
        self.client = PlantedClient(base_names())
        self.report = decompiled.refresh(self.client, self.directory)

    def test_it_writes_one_file_per_function_named_by_its_address(self):
        self.assertEqual(functions_saved(self.directory), set(base_names()))
        self.assertEqual(self.report.decompiled, 4)

    def test_each_files_first_line_names_its_function_its_address_and_the_hash_it_was_made_under(self):
        for address, name in base_names().items():
            with self.subTest(address=hex(address)):
                self.assertEqual(first_line(self.directory, address), "// 0x%x %s made under %s" % (address, name, BASE_HASH))

    def test_each_file_holds_the_decompiled_text_after_its_first_line(self):
        text = file_of(self.directory, PLANTED_CALLER).read_text().split("\n", 1)[1]
        self.assertEqual(text, "\nvoid HandleCaller(void)\n\n{\n  FUN_%x();\n  (*(code *)0x%x)();\n}\n" % (PLANTED_CALLEE, PLANTED_ADDED))

    def test_state_json_holds_the_hash_and_every_functions_name(self):
        state = read_state(self.directory)
        self.assertEqual(state["hash"], BASE_HASH)
        self.assertEqual(state["names"], {"0x%x" % a: n for a, n in base_names().items()})

    def test_the_hash_is_the_sha256_of_the_sorted_address_and_name_lines_first_16_digits(self):
        self.assertEqual(decompiled.names_hash({PLANTED_CALLER: "A", PLANTED_CALLEE: "B"}), HASH_OF_A_AND_B)
        self.assertEqual(decompiled.names_hash({PLANTED_CALLEE: "B", PLANTED_CALLER: "A"}), HASH_OF_A_AND_B)

    def test_swapping_two_names_changes_the_hash(self):
        self.assertEqual(decompiled.names_hash({PLANTED_CALLER: "B", PLANTED_CALLEE: "A"}), HASH_OF_B_AND_A)


class CheckTest(TemporaryDirectoryTest):
    """Item 2."""

    def test_a_directory_with_no_copy_has_no_copy(self):
        report = decompiled.check(PlantedClient(base_names()), self.directory)
        self.assertEqual(report.status, decompiled.Status.NO_COPY)

    def test_a_copy_made_from_the_same_names_is_current(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        report = decompiled.check(PlantedClient(base_names()), self.directory)
        self.assertEqual(report.status, decompiled.Status.CURRENT)
        self.assertEqual(report.hash, BASE_HASH)

    def test_after_a_rename_the_copy_is_stale_and_names_the_function_with_its_old_and_new_name(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        renamed = PlantedClient({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"})
        report = decompiled.check(renamed, self.directory)
        self.assertEqual(report.status, decompiled.Status.STALE)
        self.assertEqual(report.renamed, [(PLANTED_CALLEE, "FUN_%x" % PLANTED_CALLEE, "ReadFileToMemory")])
        self.assertEqual((report.added, report.removed), ([], []))

    def test_a_new_function_makes_the_copy_stale_and_is_named(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        report = decompiled.check(PlantedClient({**base_names(), PLANTED_ADDED: "FindMapZoneAt"}), self.directory)
        self.assertEqual(report.status, decompiled.Status.STALE)
        self.assertEqual(report.added, [(PLANTED_ADDED, "FindMapZoneAt")])

    def test_a_function_that_is_gone_makes_the_copy_stale_and_is_named(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        names = base_names()
        del names[PLANTED_BYSTANDER]
        report = decompiled.check(PlantedClient(names), self.directory)
        self.assertEqual(report.status, decompiled.Status.STALE)
        self.assertEqual(report.removed, [(PLANTED_BYSTANDER, "Bystander")])

    def test_a_missing_file_makes_the_copy_stale_and_is_named_and_refresh_makes_it_again(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        file_of(self.directory, PLANTED_CALLEE).unlink()
        report = decompiled.check(PlantedClient(base_names()), self.directory)
        self.assertEqual(report.status, decompiled.Status.STALE)
        self.assertEqual(report.missing, [PLANTED_CALLEE])
        again = PlantedClient(base_names())
        decompiled.refresh(again, self.directory)
        self.assertEqual(again.decompiled, [PLANTED_CALLEE])
        self.assertEqual(decompiled.check(PlantedClient(base_names()), self.directory).status, decompiled.Status.CURRENT)

    def test_check_changes_nothing_in_the_copy(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.directory.iterdir()}
        decompiled.check(PlantedClient({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}), self.directory)
        after = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.directory.iterdir()}
        self.assertEqual(after, before)


class RefreshAfterAChangeTest(TemporaryDirectoryTest):
    """Item 3."""

    def refresh_after(self, changed_names: dict[int, str]) -> PlantedClient:
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        client = PlantedClient(changed_names)
        decompiled.refresh(client, self.directory)
        return client

    def test_a_rename_redoes_the_renamed_function_and_the_file_that_names_its_old_name_and_no_other(self):
        client = self.refresh_after({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"})
        # PLANTED_CALLER's text names the callee, so it is redone; the bystander's text does not
        self.assertEqual(sorted(client.decompiled), sorted([PLANTED_CALLEE, PLANTED_CALLER]))

    def test_the_redone_files_carry_the_new_hash_and_the_others_keep_the_hash_they_were_made_under(self):
        self.refresh_after({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"})
        new_hash = read_state(self.directory)["hash"]
        self.assertNotEqual(new_hash, BASE_HASH)
        self.assertEqual(first_line(self.directory, PLANTED_CALLEE), "// 0x%x ReadFileToMemory made under %s" % (PLANTED_CALLEE, new_hash))
        self.assertTrue(first_line(self.directory, PLANTED_CALLER).endswith("made under " + new_hash))
        self.assertTrue(first_line(self.directory, PLANTED_BYSTANDER).endswith("made under " + BASE_HASH))
        self.assertTrue(first_line(self.directory, PLANTED_FAILING).endswith("made under " + BASE_HASH))

    def test_the_callers_file_now_names_the_new_name_and_the_copy_is_current_again(self):
        renamed = {**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}
        self.refresh_after(renamed)
        self.assertIn("  ReadFileToMemory();\n", file_of(self.directory, PLANTED_CALLER).read_text())
        self.assertEqual(decompiled.check(PlantedClient(renamed), self.directory).status, decompiled.Status.CURRENT)

    def test_a_new_function_redoes_itself_and_the_file_that_calls_its_address(self):
        # before the function exists, PLANTED_CALLER's text holds its address
        names = {**base_names(), PLANTED_ADDED: "FindMapZoneAt"}
        client = self.refresh_after(names)
        self.assertEqual(sorted(client.decompiled), sorted([PLANTED_ADDED, PLANTED_CALLER]))
        self.assertIn("  FindMapZoneAt();\n", file_of(self.directory, PLANTED_CALLER).read_text())
        self.assertEqual(decompiled.check(PlantedClient(names), self.directory).status, decompiled.Status.CURRENT)

    def test_a_function_that_is_gone_loses_its_file_and_the_files_that_name_it_are_redone(self):
        names = base_names()
        del names[PLANTED_CALLEE]
        client = self.refresh_after(names)
        self.assertEqual(client.decompiled, [PLANTED_CALLER])
        self.assertEqual(functions_saved(self.directory), set(names))
        self.assertIn("  (*(code *)0x%x)();\n" % PLANTED_CALLEE, file_of(self.directory, PLANTED_CALLER).read_text())

    def test_a_refresh_of_a_current_copy_decompiles_nothing(self):
        client = self.refresh_after(base_names())
        self.assertEqual(client.decompiled, [])

    def test_a_refresh_removes_the_temporary_files_a_stopped_refresh_left(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        (self.directory / ("0x%x.c.tmp" % PLANTED_CALLER)).write_text("half")
        (self.directory / "state.json.tmp").write_text("{")
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        self.assertEqual(sorted(p.name for p in self.directory.glob("*.tmp")), [])


class PointerLabelTest(TemporaryDirectoryTest):
    """A file that reaches a function through a pointer label holds neither its name nor its address."""

    def pointer_names(self, names: dict[int, str]) -> dict[int, str]:
        return {**names, PLANTED_POINTER_USER: "UsesPointers"}

    def refresh_after(self, changed_names: dict[int, str]) -> PlantedClient:
        decompiled.refresh(PlantedClient(self.pointer_names(base_names())), self.directory)
        client = PlantedClient(self.pointer_names(changed_names))
        decompiled.refresh(client, self.directory)
        return client

    def test_the_planted_label_holds_neither_the_functions_name_nor_its_address(self):
        decompiled.refresh(PlantedClient(self.pointer_names(base_names())), self.directory)
        text = file_of(self.directory, PLANTED_POINTER_USER).read_text()
        self.assertIn("PTR_FUN_%x" % PLANTED_POINTER, text)
        self.assertNotIn("%x" % PLANTED_CALLEE, text)

    def test_a_rename_redoes_the_file_that_reaches_the_function_through_a_pointer_label(self):
        client = self.refresh_after({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"})
        self.assertIn(PLANTED_POINTER_USER, client.decompiled)
        self.assertIn("(*PTR_ReadFileToMemory_%x)();" % PLANTED_POINTER, file_of(self.directory, PLANTED_POINTER_USER).read_text())

    def test_a_new_function_redoes_the_file_that_reaches_its_address_through_a_pointer_label(self):
        client = self.refresh_after({**base_names(), PLANTED_ADDED: "FindMapZoneAt"})
        self.assertIn(PLANTED_POINTER_USER, client.decompiled)
        self.assertIn("(*PTR_FindMapZoneAt_%x)();" % PLANTED_POINTER_TO_ADDED, file_of(self.directory, PLANTED_POINTER_USER).read_text())

    def test_a_function_that_is_gone_redoes_the_file_that_reaches_its_address_through_a_pointer_label(self):
        names = base_names()
        del names[PLANTED_CALLEE]
        client = self.refresh_after(names)
        self.assertIn(PLANTED_POINTER_USER, client.decompiled)
        self.assertIn("(*PTR_DAT_%x)();" % PLANTED_POINTER, file_of(self.directory, PLANTED_POINTER_USER).read_text())

    def test_the_bystander_is_not_redone_by_a_pointer_needle(self):
        client = self.refresh_after({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"})
        self.assertNotIn(PLANTED_BYSTANDER, client.decompiled)


class FailedDecompileTest(TemporaryDirectoryTest):
    """Item 4."""

    def setUp(self):
        super().setUp()
        self.client = PlantedClient(base_names(), failing={PLANTED_FAILING})
        self.report = decompiled.refresh(self.client, self.directory)

    def test_the_failed_function_gets_a_file_holding_the_error_line_after_its_first_line(self):
        lines = file_of(self.directory, PLANTED_FAILING).read_text().splitlines()
        self.assertEqual(lines[0], "// 0x%x FailsToDecompile made under %s" % (PLANTED_FAILING, BASE_HASH))
        self.assertEqual(lines[1], "// decompile failed: the decompile of 0x%x failed: planted" % PLANTED_FAILING)

    def test_refresh_finishes_every_other_function_and_lists_the_failure(self):
        self.assertEqual(functions_saved(self.directory), set(base_names()))
        self.assertEqual(self.report.failed, {PLANTED_FAILING: "the decompile of 0x%x failed: planted" % PLANTED_FAILING})
        self.assertEqual(self.report.decompiled, 3)

    def test_state_json_is_written_and_names_the_failure(self):
        state = read_state(self.directory)
        self.assertEqual(state["hash"], BASE_HASH)
        self.assertEqual(list(state["failed"]), ["0x%x" % PLANTED_FAILING])

    def test_the_next_refresh_tries_the_failed_function_again_and_no_other(self):
        again = PlantedClient(base_names())
        report = decompiled.refresh(again, self.directory)
        self.assertEqual(again.decompiled, [PLANTED_FAILING])
        self.assertEqual(report.failed, {})
        self.assertEqual(read_state(self.directory)["failed"], {})
        self.assertNotIn("decompile failed", file_of(self.directory, PLANTED_FAILING).read_text())

    def test_the_main_function_prints_the_failure_and_exits_0(self):
        out = io.StringIO()
        status = decompiled.main(["refresh"], self.env(), lambda: PlantedClient(base_names(), failing={PLANTED_FAILING}), out)
        self.assertEqual(status, 0)
        self.assertIn("failed 0x%x" % PLANTED_FAILING, out.getvalue())

    def env(self) -> dict:
        return {"GENESIS_DECOMPILED_DIR": str(self.directory)}


class KilledRefreshTest(TemporaryDirectoryTest):
    """Item 5."""

    def test_a_refresh_with_no_copy_that_ends_midway_leaves_no_state_and_the_next_run_does_everything(self):
        with self.assertRaises(QueryProcessEnded):
            decompiled.refresh(PlantedClient(base_names(), ends_after=2), self.directory)
        self.assertFalse((self.directory / "state.json").exists())
        self.assertEqual(decompiled.check(PlantedClient(base_names()), self.directory).status, decompiled.Status.NO_COPY)
        again = PlantedClient(base_names())
        decompiled.refresh(again, self.directory)
        self.assertEqual(sorted(again.decompiled), sorted(base_names()))
        self.assertEqual(read_state(self.directory)["hash"], BASE_HASH)

    def test_a_refresh_after_a_rename_that_ends_midway_leaves_the_old_state_byte_for_byte(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        old = (self.directory / "state.json").read_bytes()
        renamed = {**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}
        with self.assertRaises(QueryProcessEnded):
            decompiled.refresh(PlantedClient(renamed, ends_after=1), self.directory)
        self.assertEqual((self.directory / "state.json").read_bytes(), old)
        self.assertEqual(decompiled.check(PlantedClient(renamed), self.directory).status, decompiled.Status.STALE)

    def test_the_next_run_after_that_finishes_the_rename_and_the_copy_is_current(self):
        # the ended run redid one of the two files the rename touches; the next run redoes the renamed
        # function whichever it was, and every file ends under the new hash except the bystander's
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        renamed = {**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}
        with self.assertRaises(QueryProcessEnded):
            decompiled.refresh(PlantedClient(renamed, ends_after=1), self.directory)
        again = PlantedClient(renamed)
        decompiled.refresh(again, self.directory)
        self.assertIn(PLANTED_CALLEE, again.decompiled)
        new_hash = read_state(self.directory)["hash"]
        self.assertEqual(first_line(self.directory, PLANTED_CALLEE), "// 0x%x ReadFileToMemory made under %s" % (PLANTED_CALLEE, new_hash))
        self.assertTrue(first_line(self.directory, PLANTED_CALLER).endswith("made under " + new_hash))
        self.assertTrue(first_line(self.directory, PLANTED_BYSTANDER).endswith("made under " + BASE_HASH))
        self.assertIn("  ReadFileToMemory();\n", file_of(self.directory, PLANTED_CALLER).read_text())
        self.assertEqual(decompiled.check(PlantedClient(renamed), self.directory).status, decompiled.Status.CURRENT)

    def test_a_file_is_written_beside_its_place_and_moved_so_a_stop_before_the_move_leaves_every_old_file(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        before = {p.name: p.read_bytes() for p in self.directory.glob("0x*.c")}
        renamed = {**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}
        real_replace = os.replace

        def stop_before_moving_a_c_file(source, target):
            if str(target).endswith(".c"):
                raise OSError("planted: stopped before the move")
            real_replace(source, target)

        with mock.patch("decompiled.os.replace", side_effect=stop_before_moving_a_c_file):
            with self.assertRaises(OSError):
                decompiled.refresh(PlantedClient(renamed), self.directory)
        self.assertEqual({p.name: p.read_bytes() for p in self.directory.glob("0x*.c")}, before)

    def test_a_refresh_that_ends_leaves_a_pending_file_and_a_finished_one_removes_it(self):
        with self.assertRaises(QueryProcessEnded):
            decompiled.refresh(PlantedClient(base_names(), ends_after=1), self.directory)
        self.assertTrue((self.directory / "pending.json").exists())
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        self.assertFalse((self.directory / "pending.json").exists())

    def test_a_rename_after_an_ended_refresh_redoes_the_file_that_names_the_ended_refreshs_name(self):
        # the ended refresh redid PLANTED_CALLER under the name ReadFileToMemory and ended before the
        # callee, so the saved state still says the old name; the rename that follows is to a third name
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        with self.assertRaises(QueryProcessEnded):
            decompiled.refresh(PlantedClient({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}, ends_after=1), self.directory)
        self.assertIn("ReadFileToMemory", file_of(self.directory, PLANTED_CALLER).read_text())  # the premise
        decompiled.refresh(PlantedClient({**base_names(), PLANTED_CALLEE: "LoadFile"}), self.directory)
        text = file_of(self.directory, PLANTED_CALLER).read_text()
        self.assertIn("  LoadFile();\n", text)
        self.assertNotIn("ReadFileToMemory", text)

    def test_a_rename_back_to_the_saved_name_after_an_ended_refresh_redoes_the_file_the_ended_refresh_made(self):
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        with self.assertRaises(QueryProcessEnded):
            decompiled.refresh(PlantedClient({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}, ends_after=1), self.directory)
        report = decompiled.check(PlantedClient(base_names()), self.directory)
        self.assertEqual(report.status, decompiled.Status.STALE)
        self.assertTrue(report.unfinished)
        decompiled.refresh(PlantedClient(base_names()), self.directory)
        self.assertIn("  FUN_%x();\n" % PLANTED_CALLEE, file_of(self.directory, PLANTED_CALLER).read_text())
        self.assertEqual(decompiled.check(PlantedClient(base_names()), self.directory).status, decompiled.Status.CURRENT)


class DirectoryTest(unittest.TestCase):
    def test_the_copy_lives_under_the_genesis_home_by_default(self):
        self.assertEqual(
            decompiled.copy_directory({"GENESIS_HOME": "/somewhere/home"}), Path("/somewhere/home/decompiled")
        )

    def test_the_default_home_is_dot_genesis_prime_in_the_users_home(self):
        self.assertEqual(
            decompiled.copy_directory({"HOME": "/users/someone"}), Path("/users/someone/.genesis-prime/decompiled")
        )

    def test_genesis_decompiled_dir_names_the_folder(self):
        self.assertEqual(
            decompiled.copy_directory({"GENESIS_DECOMPILED_DIR": "/elsewhere/copy", "GENESIS_HOME": "/h"}),
            Path("/elsewhere/copy"),
        )

    def test_a_folder_inside_the_repository_is_refused(self):
        # the client's code does not go into the public repository
        for inside in (check_facts.REPOSITORY / "decompiled", check_facts.REPOSITORY):
            with self.subTest(folder=str(inside)):
                with self.assertRaisesRegex(decompiled.Refused, "inside the repository"):
                    decompiled.copy_directory({"GENESIS_DECOMPILED_DIR": str(inside)})

    def test_a_folder_inside_any_git_working_tree_is_refused(self):
        with tempfile.TemporaryDirectory() as other:
            subprocess.run(["git", "init", "-q", other], check=True)
            for inside in (Path(other) / "decompiled", Path(other) / "a" / "b" / "decompiled"):
                with self.subTest(folder=str(inside)):
                    with self.assertRaisesRegex(decompiled.Refused, "inside a git working tree"):
                        decompiled.copy_directory({"GENESIS_DECOMPILED_DIR": str(inside)})

    def test_a_folder_outside_every_git_working_tree_is_accepted_though_it_does_not_exist_yet(self):
        with tempfile.TemporaryDirectory() as outside:
            folder = Path(outside) / "not" / "yet" / "decompiled"
            self.assertEqual(decompiled.copy_directory({"GENESIS_DECOMPILED_DIR": str(folder)}), folder)

    def test_the_main_function_refuses_a_folder_inside_the_repository_and_runs_nothing(self):
        asked = []
        out, err = io.StringIO(), io.StringIO()
        status = decompiled.main(
            ["refresh"],
            {"GENESIS_DECOMPILED_DIR": str(check_facts.REPOSITORY / "decompiled")},
            lambda: asked.append("started") or PlantedClient(base_names()),
            out,
            err,
        )
        self.assertEqual(status, 1)
        self.assertEqual(asked, [])
        self.assertIn("inside the repository", err.getvalue())


class MainTest(TemporaryDirectoryTest):
    def run_main(self, command: str, client: PlantedClient) -> tuple[int, str]:
        out = io.StringIO()
        env = {"GENESIS_DECOMPILED_DIR": str(self.directory)}
        return decompiled.main([command], env, lambda: client, out), out.getvalue()

    def test_check_with_no_copy_says_so_and_exits_1(self):
        status, text = self.run_main("check", PlantedClient(base_names()))
        self.assertEqual(status, 1)
        self.assertIn("no copy", text)

    def test_check_of_a_current_copy_says_current_and_exits_0(self):
        self.run_main("refresh", PlantedClient(base_names()))
        status, text = self.run_main("check", PlantedClient(base_names()))
        self.assertEqual(status, 0)
        self.assertIn("current", text)

    def test_check_of_a_stale_copy_names_the_renamed_function_and_exits_1(self):
        self.run_main("refresh", PlantedClient(base_names()))
        status, text = self.run_main("check", PlantedClient({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}))
        self.assertEqual(status, 1)
        self.assertIn("stale", text)
        self.assertIn("0x%x renamed FUN_%x -> ReadFileToMemory" % (PLANTED_CALLEE, PLANTED_CALLEE), text)

    def test_refresh_says_how_many_functions_it_decompiled(self):
        status, text = self.run_main("refresh", PlantedClient(base_names()))
        self.assertEqual(status, 0)
        self.assertIn("decompiled 4 functions", text)

    def test_a_query_process_that_ends_makes_refresh_exit_1_and_name_the_cause(self):
        out, err = io.StringIO(), io.StringIO()
        env = {"GENESIS_DECOMPILED_DIR": str(self.directory)}
        status = decompiled.main(["refresh"], env, lambda: PlantedClient(base_names(), ends_after=1), out, err)
        self.assertEqual(status, 1)
        self.assertIn("planted: the query process ended", err.getvalue())
        self.assertFalse((self.directory / "state.json").exists())

    def test_a_holder_that_cannot_be_reached_makes_refresh_exit_1_and_say_why(self):
        def unreachable():
            raise query.HolderUnavailable("no query process is running")

        out, err = io.StringIO(), io.StringIO()
        env = {"GENESIS_DECOMPILED_DIR": str(self.directory)}
        self.assertEqual(decompiled.main(["refresh"], env, unreachable, out, err), 1)
        self.assertIn("no query process is running", err.getvalue())

    def run_main_with_errors(self, command: str, client: PlantedClient) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        env = {"GENESIS_DECOMPILED_DIR": str(self.directory)}
        return decompiled.main([command], env, lambda: client, out, err), err.getvalue()

    def test_a_refusal_of_functions_or_function_at_gives_a_message_and_exit_1_not_a_traceback(self):
        for command in ("check", "refresh"):
            for kind in ("functions", "function_at"):
                with self.subTest(command=command, request=kind):
                    status, text = self.run_main_with_errors(command, PlantedClient(base_names(), refuses=kind))
                    self.assertEqual(status, 1)
                    self.assertIn("planted refusal of " + kind, text)

    def test_a_close_that_times_out_gives_a_message_and_exit_1(self):
        client = PlantedClient(base_names(), close_raises=QueryTimeout("planted: did not stop"))
        status, text = self.run_main_with_errors("refresh", client)
        self.assertEqual(status, 1)
        self.assertIn("planted: did not stop", text)

    def test_check_names_a_missing_file_and_an_unfinished_refresh(self):
        self.run_main("refresh", PlantedClient(base_names()))
        file_of(self.directory, PLANTED_CALLEE).unlink()
        status, text = self.run_main("check", PlantedClient(base_names()))
        self.assertEqual(status, 1)
        self.assertIn("0x%x missing" % PLANTED_CALLEE, text)
        self.run_main("refresh", PlantedClient(base_names()))
        ended = PlantedClient({**base_names(), PLANTED_CALLEE: "ReadFileToMemory"}, ends_after=1)
        self.assertEqual(self.run_main_with_errors("refresh", ended)[0], 1)
        status, text = self.run_main("check", PlantedClient(base_names()))
        self.assertEqual(status, 1)
        self.assertIn("an earlier refresh did not finish", text)


# Addresses measured on WildStar64.exe (SHA-256 565c2fa1...fe0b10), each a record of the fact file:
# 0x140283670 InitSpriteRendererAndFonts calls 0x1401b6d00 by its project name, and 0x14077ed70 is a small
# function that does not call it.
CALLER_BY_NAME = 0x140283670
CALLEE_BY_NAME = 0x1401B6D00
UNRELATED = cs.POINTER_ONLY_A
BIG_SWITCH = cs.FN_BIG_SWITCH
SCOPE = {CALLER_BY_NAME, CALLEE_BY_NAME, UNRELATED}
PLANTED_NAME = "PlantedReadFileToMemory"


def real_client(project_dir: Path) -> QueryClient:
    return open_query_client(cs.query_environment(project_dir))


def project_name(client: QueryClient, address: int) -> str:
    return client.answer("function_at", address=cs.hx(address))["name"]


@cs.integration_only
class RealQueryProcessTest(TemporaryDirectoryTest):
    """Items 1, 2 and 4 with the real query process, on the shared project, three functions at a time."""

    @classmethod
    def setUpClass(cls):
        cls.client = real_client(cs.seeded_project().project_dir)

    @classmethod
    def tearDownClass(cls):
        cls.client.close()

    def test_refresh_writes_each_functions_files_as_the_query_process_decompiles_it(self):
        report = decompiled.refresh(self.client, self.directory, scope=SCOPE)
        state = read_state(self.directory)
        self.assertEqual(report.decompiled, 3)
        self.assertEqual(functions_saved(self.directory), SCOPE)
        for address in SCOPE:
            with self.subTest(address=hex(address)):
                direct = self.client.answer("decompile", function=cs.hx(address))["c"]
                name = project_name(self.client, address)
                self.assertEqual(first_line(self.directory, address), "// %s %s made under %s" % (cs.hx(address), name, state["hash"]))
                self.assertEqual(file_of(self.directory, address).read_text().split("\n", 1)[1], direct)

    def test_the_callers_file_holds_the_callees_project_name(self):
        decompiled.refresh(self.client, self.directory, scope=SCOPE)
        name = project_name(self.client, CALLEE_BY_NAME)
        self.assertIn(name + "(", file_of(self.directory, CALLER_BY_NAME).read_text())

    def test_check_of_the_copy_just_made_is_current(self):
        decompiled.refresh(self.client, self.directory, scope=SCOPE)
        self.assertEqual(decompiled.check(self.client, self.directory, scope=SCOPE).status, decompiled.Status.CURRENT)

    def test_a_decompile_that_passes_its_timeout_gets_an_error_file_and_the_refresh_goes_on(self):
        # the 2,322-case switch function cannot be decompiled in a millisecond: the process answers an
        # error reply. Whether the small function beside it does is not asserted, as it is a matter of time.
        scope = {BIG_SWITCH, UNRELATED}
        report = decompiled.refresh(self.client, self.directory, scope=scope, timeout_s=0.001)
        self.assertIn(BIG_SWITCH, report.failed)
        self.assertIn("timeout", report.failed[BIG_SWITCH])
        self.assertEqual(file_of(self.directory, BIG_SWITCH).read_text().splitlines()[1], "// decompile failed: " + report.failed[BIG_SWITCH])
        self.assertEqual(functions_saved(self.directory), scope)
        self.assertEqual(sorted(read_state(self.directory)["failed"]), sorted("0x%x" % a for a in report.failed))
        self.assertEqual(self.client.answer("seed_report"), None)  # the process goes on answering


RENAME_SCRIPT = r"""
import os, sys
sys.path.insert(0, %(scripts)r)
import ghidra_env, name_functions
outcomes = name_functions.name_and_save(ghidra_env.settings_from_env(os.environ), [(%(address)d, %(name)r)], True)
assert not [o for o in outcomes if o.failed], outcomes
"""


def rename_in_project(project_dir: Path, address: int, name: str) -> None:
    code = RENAME_SCRIPT % {"scripts": str(cs.SCRIPTS), "address": address, "name": name}
    done = subprocess.run(
        [cs.require_env("GENESIS_PYGHIDRA_PYTHON"), "-I", "-c", code],
        env=cs.query_environment(project_dir),
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert done.returncode == 0, done.stderr


@cs.integration_only
class RealRenameTest(unittest.TestCase):
    """Items 2 and 3 with a rename made in a copy of the shared project."""

    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="genesis-decompiled-test-"))
        cls.addClassCleanup(shutil.rmtree, cls.root, True)
        project_dir = cls.root / "project"
        shutil.copytree(cs.seeded_project().project_dir, project_dir)
        cls.directory = cls.root / "copy"
        scope = SCOPE
        client = real_client(project_dir)
        try:
            decompiled.refresh(client, cls.directory, scope=scope)
            cls.old_name = project_name(client, CALLEE_BY_NAME)
            cls.old_hash = read_state(cls.directory)["hash"]
            cls.old_first_lines = {a: first_line(cls.directory, a) for a in scope}
            cls.callers_old_text = file_of(cls.directory, CALLER_BY_NAME).read_text()
            cls.unrelated_old_text = file_of(cls.directory, UNRELATED).read_text()
        finally:
            client.close()
        rename_in_project(project_dir, CALLEE_BY_NAME, PLANTED_NAME)
        client = real_client(project_dir)
        try:
            cls.stale = decompiled.check(client, cls.directory, scope=scope)
            cls.refreshed = decompiled.refresh(client, cls.directory, scope=scope)
            cls.after = decompiled.check(client, cls.directory, scope=scope)
        finally:
            client.close()

    def test_the_planted_rename_is_the_only_difference_between_the_two_states(self):
        # the precondition of the tests below: the caller names the callee, the unrelated function does not
        self.assertIn(self.old_name + "(", self.callers_old_text)
        self.assertNotIn(self.old_name, self.unrelated_old_text)
        self.assertNotIn("%x" % CALLEE_BY_NAME, self.unrelated_old_text)

    def test_check_after_the_rename_is_stale_and_names_the_function(self):
        self.assertEqual(self.stale.status, decompiled.Status.STALE)
        self.assertEqual(self.stale.renamed, [(CALLEE_BY_NAME, self.old_name, PLANTED_NAME)])

    def test_refresh_after_the_rename_redoes_the_renamed_function_and_its_caller_only(self):
        self.assertEqual(self.refreshed.decompiled, 2)
        new_hash = read_state(self.directory)["hash"]
        self.assertNotEqual(new_hash, self.old_hash)
        self.assertEqual(first_line(self.directory, CALLEE_BY_NAME), "// %s %s made under %s" % (cs.hx(CALLEE_BY_NAME), PLANTED_NAME, new_hash))
        self.assertTrue(first_line(self.directory, CALLER_BY_NAME).endswith("made under " + new_hash))
        self.assertEqual(first_line(self.directory, UNRELATED), self.old_first_lines[UNRELATED])
        self.assertEqual(file_of(self.directory, UNRELATED).read_text(), self.unrelated_old_text)

    def test_the_callers_file_names_the_new_name_after_the_refresh(self):
        text = file_of(self.directory, CALLER_BY_NAME).read_text()
        self.assertIn(PLANTED_NAME + "(", text)
        self.assertNotIn(self.old_name + "(", text)

    def test_the_copy_is_current_after_the_refresh(self):
        self.assertEqual(self.after.status, decompiled.Status.CURRENT)


if __name__ == "__main__":
    unittest.main(verbosity=2)

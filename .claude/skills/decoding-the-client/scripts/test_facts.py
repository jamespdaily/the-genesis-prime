"""facts: the lookup over the fact file.

Expected values come from the usage in the docstring of facts.py. Every record
here is planted in one temporary fact file; the real one is never read. An
address is assigned once to a PLANTED_ name, as the fact checker's coverage
rule asks, so these tests cite no client address a record must hold.
Run: python3 -I test_facts.py
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import facts  # noqa: E402

PLANTED_ADDRESS = "0x140006060"

ALPHA = "opcode.0x7f4"
BETA = "movement_command.kind_8"
GAMMA = PLANTED_ADDRESS
PLAIN = "planted.plain_citer"
DELTA = "opcode.0x638"
NOT_A_KEY = "planted.not_a_key"
UNKNOWN = "opcode.0xfff"

ALPHA_STATEMENT = (
    "The movement batch the client sends each send interval; the commands are laid out "
    f"as `{BETA}` gives, then `{BETA}` again, and `{NOT_A_KEY}` names nothing."
)
ALPHA_PROOF = "the alpha proof"
ALPHA_GAP = f"Whether the queue can hold two batches is unread; `{PLANTED_ADDRESS}` would settle it."
BETA_STATEMENT = f"The velocity as three half-precision floats and a bit; the queue side is `{DELTA}`."
BETA_PROOF = "the beta proof"
GAMMA_STATEMENT = (
    "Collapses the queued movement commands before a send, dropping each command that has not "
    "changed since the last send and keeping only the newest of each kind, so only changes go out."
)
GAMMA_PROOF = "the gamma proof"
# The fact file's records cite keys as plain words far more than in backticks
# (272 to 1, measured 2026-11-06), so a plain word that is a key is a citation.
PLAIN_STATEMENT = f"Read as {GAMMA} reads it, then {ALPHA}."
GAMMA_NAME = "PlantedGamma"
DELTA_STATEMENT = "The platform-relative rotation command: a yaw relative to the platform unit's facing."
DELTA_PROOF = "the delta proof"


def toml_text(key: str, **fields) -> str:
    lines = [f"[{json.dumps(key)}]"]
    lines += [f"{name} = {json.dumps(value)}" for name, value in fields.items()]
    return "\n".join(lines) + "\n"


PLANTED_TOML = (
    toml_text(ALPHA, statement=ALPHA_STATEMENT, proof=ALPHA_PROOF, grade="fairly sure", gap=ALPHA_GAP)
    + toml_text(BETA, statement=BETA_STATEMENT, proof=BETA_PROOF, grade="sure")
    + toml_text(GAMMA, statement=GAMMA_STATEMENT, proof=GAMMA_PROOF, grade="sure", name=GAMMA_NAME)
    + toml_text(DELTA, statement=DELTA_STATEMENT, proof=DELTA_PROOF, grade="sure")
    + toml_text(PLAIN, statement=PLAIN_STATEMENT, proof="the plain proof", grade="sure")
)


def block(key: str, **fields) -> str:
    """What get prints for one record: the key, then each field in the fact file's order."""
    lines = [key]
    for field in ("statement", "proof", "grade", "gap", "name"):
        if field in fields:
            lines.append(f"{field}: {fields[field]}")
    return "\n".join(lines)


ALPHA_BLOCK = block(ALPHA, statement=ALPHA_STATEMENT, proof=ALPHA_PROOF, grade="fairly sure", gap=ALPHA_GAP)
BETA_BLOCK = block(BETA, statement=BETA_STATEMENT, proof=BETA_PROOF, grade="sure")
GAMMA_BLOCK = block(GAMMA, statement=GAMMA_STATEMENT, proof=GAMMA_PROOF, grade="sure", name=GAMMA_NAME)
DELTA_BLOCK = block(DELTA, statement=DELTA_STATEMENT, proof=DELTA_PROOF, grade="sure")


class FactsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._dir = tempfile.TemporaryDirectory()
        cls.fact_file = Path(cls._dir.name) / "client-facts.toml"
        cls.fact_file.write_text(PLANTED_TOML)

    @classmethod
    def tearDownClass(cls):
        cls._dir.cleanup()

    def run_facts(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with (
            mock.patch.object(facts, "FACT_FILE", self.fact_file),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
        ):
            code = facts.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def keys_printed(self, out: str) -> list[str]:
        """The key line of each printed record, in print order."""
        return [b.splitlines()[0] for b in out.strip().split("\n\n")] if out.strip() else []


class GetTest(FactsTest):
    def test_get_prints_each_asked_record_whole(self):
        # the docstring of facts.py: the key, then statement, proof, grade, gap, name
        code, out, err = self.run_facts("get", ALPHA, DELTA)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, ALPHA_BLOCK + "\n\n" + DELTA_BLOCK + "\n")

    def test_get_prints_only_the_fields_a_record_holds(self):
        # the docstring of facts.py: only the fields present
        code, out, err = self.run_facts("get", BETA)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, BETA_BLOCK + "\n")
        self.assertNotIn("gap:", out)
        self.assertNotIn("name:", out)
        code, out, err = self.run_facts("get", GAMMA)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, GAMMA_BLOCK + "\n")
        self.assertIn("name: " + GAMMA_NAME, out)

    def test_an_unknown_key_exits_1_after_printing_the_found_ones(self):
        code, out, err = self.run_facts("get", UNKNOWN, ALPHA)
        self.assertEqual(code, 1)
        self.assertEqual(out, ALPHA_BLOCK + "\n")
        self.assertEqual(err, "no record %s\n" % UNKNOWN)

    def test_every_key_unknown_prints_no_record(self):
        code, out, err = self.run_facts("get", UNKNOWN)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertEqual(err, "no record %s\n" % UNKNOWN)


class CitesTest(FactsTest):
    def test_get_cites_prints_each_record_cited_in_backticks(self):
        # ALPHA's statement cites BETA and its gap cites GAMMA
        code, out, err = self.run_facts("get", "--cites", ALPHA)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(self.keys_printed(out), [ALPHA, BETA, GAMMA])
        self.assertEqual(out, ALPHA_BLOCK + "\n\n" + BETA_BLOCK + "\n\n" + GAMMA_BLOCK + "\n")

    def test_a_key_named_as_a_plain_word_is_cited(self):
        code, out, err = self.run_facts("get", "--cites", PLAIN)
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(self.keys_printed(out), [PLAIN, GAMMA, ALPHA])

    def test_cites_follow_one_level_only(self):
        # BETA cites DELTA; asking for ALPHA must not pull DELTA in
        _code, out, _err = self.run_facts("get", "--cites", ALPHA)
        self.assertNotIn(DELTA, self.keys_printed(out))

    def test_cites_have_no_repeats(self):
        # ALPHA's statement cites BETA twice, and GAMMA is both asked for and cited
        # by ALPHA's gap; each prints once
        _code, out, _err = self.run_facts("get", "--cites", ALPHA, GAMMA)
        self.assertEqual(self.keys_printed(out), [ALPHA, GAMMA, BETA])

    def test_a_backticked_span_that_is_no_key_is_ignored(self):
        # ALPHA's statement holds `planted.not_a_key`
        _code, out, _err = self.run_facts("get", "--cites", ALPHA)
        self.assertNotIn(NOT_A_KEY, self.keys_printed(out))

    def test_get_without_cites_prints_no_cited_record(self):
        _code, out, _err = self.run_facts("get", ALPHA)
        self.assertEqual(self.keys_printed(out), [ALPHA])


class FindTest(FactsTest):
    def test_find_lists_each_key_holding_every_word_with_the_statements_first_100_characters(self):
        self.assertGreater(len(GAMMA_STATEMENT), 100)  # the line really is cut
        code, out, err = self.run_facts("find", "collapses", "newest")
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, "%s: %.100s\n" % (GAMMA, GAMMA_STATEMENT))

    def test_find_matches_case_insensitively(self):
        code, out, err = self.run_facts("find", "HALF-PRECISION")
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, "%s: %.100s\n" % (BETA, BETA_STATEMENT))

    def test_find_searches_the_key_as_well_as_the_statement(self):
        # BETA's statement holds no "movement"; its key does
        self.assertNotIn("movement", BETA_STATEMENT.lower())
        code, out, err = self.run_facts("find", "movement")
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(
            [line.split(": ", 1)[0] for line in out.splitlines()],
            [ALPHA, BETA, GAMMA],  # the fact file's order
        )

    def test_every_word_must_be_held(self):
        # BETA holds "velocity", DELTA holds "rotation", no record holds both
        code, out, err = self.run_facts("find", "velocity", "rotation")
        self.assertEqual((code, out, err), (0, "", ""))

    def test_find_does_not_search_the_name(self):
        # GAMMA's name is PlantedGamma; the docstring of facts.py names key and statement only
        code, out, err = self.run_facts("find", GAMMA_NAME.lower())
        self.assertEqual((code, out, err), (0, "", ""))


class UsageTest(FactsTest):
    def test_an_unknown_command_prints_usage_and_exits_2(self):
        code, out, err = self.run_facts("show", ALPHA)
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("usage:", err)

    def test_get_without_a_key_prints_usage_and_exits_2(self):
        code, out, err = self.run_facts("get")
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("usage:", err)


if __name__ == "__main__":
    unittest.main(verbosity=2)

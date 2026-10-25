"""Tests for check_facts.py, each writing its fact file and cited code to a temporary folder.

Usage: python3 -I check_facts_test.py
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest

# Loading the script would otherwise leave a __pycache__ folder beside it.
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check_facts.py")
SPEC = importlib.util.spec_from_file_location("check_facts", SCRIPT)
check_facts = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_facts)

ADDRESS_RECORD = """
["0x1403ec6a0"]
name = "InGameScreenHandler"
statement = "Handles the in-game screen messages."
proof = "Its jump table's cases."
grade = "sure"
"""

LUA_RECORD = """
["MailSystemLib.AtMailbox"]
statement = "True within 20 m of any mailbox."
proof = "Seen in a live login."
grade = "guess"
"""


def record(key, **fields):
    lines = [f"[{json.dumps(key)}]"] + [f"{field} = {json.dumps(value)}" for field, value in fields.items()]
    return "\n".join(lines) + "\n"


def valid(key="MailSystemLib.AtMailbox", **fields):
    values = {"statement": "Says one thing.", "proof": "Seen once.", "grade": "sure"}
    values.update(fields)
    return record(key, **{field: value for field, value in values.items() if value is not None})


class CheckFactsTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.facts = self.write("client-facts.toml", "")

    def write(self, relative, text):
        path = os.path.join(self.folder.name, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as file:
            file.write(textwrap.dedent(text))
        return path

    def check(self, facts_text, cover=None):
        self.write("client-facts.toml", facts_text)
        return check_facts.check(self.facts, cover or [])

    def assert_one_finding(self, findings, *parts):
        self.assertEqual(len(findings), 1, findings)
        for part in parts:
            self.assertIn(part, findings[0])

    def test_a_valid_file_with_an_address_record_and_a_lua_record_passes(self):
        self.write("client-facts.toml", "# Message plumbing\n" + ADDRESS_RECORD + LUA_RECORD)
        self.assertEqual(check_facts.check(self.facts, []), [])
        result = subprocess.run(
            [sys.executable, "-I", SCRIPT, self.facts], capture_output=True, text=True
        )
        self.assertEqual((result.returncode, result.stdout), (0, "ok: 2 records\n"), result.stderr)

    def test_a_duplicate_key_is_refused(self):
        findings = self.check(LUA_RECORD + LUA_RECORD)
        self.assert_one_finding(findings, "parse error")

    def test_two_keys_equal_when_lowercased_are_refused(self):
        findings = self.check(valid("MailSystemLib.AtMailbox") + valid("MailSystemLib.atMailbox"))
        self.assert_one_finding(findings, "MailSystemLib.atMailbox", "lowercased")

    def test_an_uppercase_address_key_is_refused(self):
        findings = self.check(valid("0x1403EC6A0"))
        self.assert_one_finding(findings, "0x1403EC6A0", "lowercase")

    def test_a_missing_proof_is_refused(self):
        findings = self.check(valid(proof=None))
        self.assert_one_finding(findings, "missing 'proof'")

    def test_an_empty_statement_is_refused(self):
        findings = self.check(valid(statement=""))
        self.assert_one_finding(findings, "'statement' must be a non-empty string")

    def test_an_unknown_grade_is_refused(self):
        findings = self.check(valid(grade="likely"))
        self.assert_one_finding(findings, "grade 'likely'")

    def test_an_unknown_field_is_refused(self):
        findings = self.check(valid(source="Ghidra"))
        self.assert_one_finding(findings, "unknown field 'source'")

    def test_a_name_on_a_lua_key_is_refused(self):
        findings = self.check(valid("MailSystemLib.AtMailbox", name="AtMailbox"))
        self.assert_one_finding(findings, "only on an address key")

    def test_two_records_with_one_name_are_refused(self):
        findings = self.check(
            valid("0x14006c290", name="RegisterMessage") + valid("0x1403ec6a0", name="RegisterMessage")
        )
        self.assert_one_finding(findings, "0x1403ec6a0", "'RegisterMessage' is also on")

    def test_a_lowercase_first_name_is_refused(self):
        findings = self.check(valid("0x14006c290", name="registerMessage"))
        self.assert_one_finding(findings, "name 'registerMessage'")

    def assert_refused_in_a_value_and_a_comment(self, text):
        with self.subTest(where="value"):
            findings = self.check(valid(statement=f"Matches {text} exactly."))
            self.assert_one_finding(findings, ":2:", "forbidden text")
        with self.subTest(where="comment"):
            findings = self.check(f"# Seen in {text}\n" + valid())
            self.assert_one_finding(findings, ":1:", "forbidden text")

    def test_nexusforever_is_refused_in_a_value_and_a_comment(self):
        self.assert_refused_in_a_value_and_a_comment("NexusForever")

    def test_nexus_forever_is_refused_in_a_value_and_a_comment(self):
        self.assert_refused_in_a_value_and_a_comment("Nexus Forever")

    def test_an_issue_number_is_refused_in_a_value_and_a_comment(self):
        self.assert_refused_in_a_value_and_a_comment("#123")

    def test_decision_record_is_refused_in_a_value_and_a_comment(self):
        self.assert_refused_in_a_value_and_a_comment("decision record")

    def test_nexus_alone_passes(self):
        findings = self.check("# Nexus chat\n" + valid(statement="Sends to the Nexus channel."))
        self.assertEqual(findings, [])

    def test_an_address_cited_and_missing_from_the_file_is_reported_with_its_file_and_line(self):
        cited = self.write("code/src/mail.gleam", "import x\n\n/// Handler at 0x14006c290.\n")
        findings = self.check(LUA_RECORD, [os.path.join(self.folder.name, "code")])
        self.assert_one_finding(findings, f"{cited}:3:", "0x14006c290")

    def test_an_address_only_inside_another_records_statement_counts_as_covered(self):
        self.write("code/mail.gleam", "/// Handler at 0x14006c290.\n")
        facts = valid(statement="Called from 0x14006c290 once.")
        findings = self.check(facts, [os.path.join(self.folder.name, "code")])
        self.assertEqual(findings, [])

    def test_a_lua_function_cited_but_not_a_key_is_reported(self):
        cited = self.write("code/mail.gleam", "\n/// As MailSystemLib.GetInbox returns.\n")
        findings = self.check(LUA_RECORD, [os.path.join(self.folder.name, "code")])
        self.assert_one_finding(findings, f"{cited}:2:", "MailSystemLib.GetInbox")

    def test_a_cited_uppercase_address_matches_a_lowercase_mention(self):
        self.write("code/screen.gleam", "/// The screen handler 0x1403EC6A0.\n")
        findings = self.check(ADDRESS_RECORD, [os.path.join(self.folder.name, "code")])
        self.assertEqual(findings, [])

    def test_a_file_under_a_build_folder_is_not_read(self):
        self.write("code/build/dev/mail.erl", "%% Handler at 0x14006c290.\n")
        findings = self.check(LUA_RECORD, [os.path.join(self.folder.name, "code")])
        self.assertEqual(findings, [])


if __name__ == "__main__":
    unittest.main()

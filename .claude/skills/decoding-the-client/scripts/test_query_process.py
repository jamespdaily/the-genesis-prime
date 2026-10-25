"""The client query process (ghidra_query.py), started as a subprocess.

Integration tests: they run only when GENESIS_INTEGRATION=1, and need
GENESIS_GHIDRA_DIR, JAVA_HOME and GENESIS_PYGHIDRA_PYTHON (see check_support).
Each class that needs the saved project opens the one built by
check_support.seeded_project() (import, seed, analysis: about 3 minutes, once
per run); the unseeded project is built by UnseededProjectTest.

The interface, as ghidra_query.py documents it:
- `--seed PATH` on the command line; used only when the project does not exist yet.
- `seed_report` answers null exactly when the open ran no analysis ("analysed_now"
  is false); on the first start it answers
  {"lines", "created", "already_present", "failed": [hex], "unmapped": [hex]}.

Expected values come from check_support's independent readings of WildStar64.exe
(RawPE, the reference index, the jump table reader) and the fact file's records,
measured on WildStar64.exe, SHA-256 565c2fa1...fe0b10.
Run: GENESIS_INTEGRATION=1 python3 -I test_query_process.py
"""

import json
import os
import signal
import statistics
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
import seed  # noqa: E402
from check_support import hx  # noqa: E402
from jump_tables import read_function  # noqa: E402


@cs.integration_only
class PinnedPartsTest(unittest.TestCase):
    """Item 1."""

    def test_check_parts_passes_on_the_real_install(self):
        # run under the pinned Python 3.13 of the PyGhidra venv: check_parts checks the interpreter it runs in
        with tempfile.TemporaryDirectory() as d:
            code = (
                "import os, sys; sys.path.insert(0, %r); import ghidra_env; "
                "ghidra_env.check_parts(ghidra_env.settings_from_env(os.environ))" % str(cs.SCRIPTS)
            )
            r = subprocess.run(
                [cs.require_env("GENESIS_PYGHIDRA_PYTHON"), "-I", "-c", code],
                env=cs.query_environment(Path(d)),
                capture_output=True,
                text=True,
                timeout=300,
            )
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_the_process_refuses_to_start_on_another_ghidra_version_and_names_it(self):
        # planted: a copy of the install's layout whose application.properties says 12.1.4
        with tempfile.TemporaryDirectory() as d:
            planted = cs.planted_ghidra_dir(Path(d), "12.1.4")
            project = Path(d) / "project"
            project.mkdir()
            r = subprocess.run(
                cs.query_command(),
                env=cs.query_environment(project, planted),
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=300,
            )
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("12.1.4", r.stderr)
        self.assertEqual(r.stdout, "")


@cs.integration_only
class FirstStartTest(unittest.TestCase):
    """Items 2 and 3: the first start imports, seeds, analyses and saves."""

    @classmethod
    def setUpClass(cls):
        cls.project = cs.seeded_project()
        cls.report = cls.project.first_report

    def test_the_first_start_reports_a_seed_outcome(self):
        self.assertIsNotNone(self.report)

    def test_every_seed_line_has_one_outcome_and_the_counts_add_up(self):
        # created + already present + failed + unmapped == the number of lines
        r = self.report
        self.assertEqual(r["lines"], len(self.project.seed_lines))
        self.assertEqual(r["created"] + r["already_present"] + len(r["failed"]) + len(r["unmapped"]), r["lines"])
        print("seed report:", {k: (v if isinstance(v, int) else len(v)) for k, v in r.items()})

    def test_the_planted_line_outside_every_section_is_reported_unmapped(self):
        # planted: seed.PLANTED_UNMAPPED lies outside every section; every other line is in .text
        self.assertEqual(self.report["unmapped"], [hx(seed.PLANTED_UNMAPPED)])
        self.assertNotIn(hx(seed.PLANTED_UNMAPPED), self.report["failed"])


@cs.integration_only
class ReopenTest(unittest.TestCase):
    """Item 4."""

    def test_a_reopened_project_runs_no_analysis_and_answers_within_30_seconds(self):
        project = cs.seeded_project()
        qp = cs.QueryProcess(project.project_dir)
        try:
            reply = qp.ask("seed_report")
            seconds = qp.first_reply_seconds
        finally:
            qp.close()
        # "analysed_now" is false exactly when the seed report is null
        self.assertIsNone(reply.answer)
        print("reopened project: first answer after %.1f s" % seconds)
        self.assertLess(seconds, 30)


@cs.integration_only
class QueriesTest(unittest.TestCase):
    """Items 6 to 9 on the reopened project."""

    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()
        cls.idx = cs.ref_index()
        cls.project = cs.seeded_project()
        cls.qp = cs.QueryProcess(cls.project.project_dir)
        cls.qp.ask("seed_report")  # the first answer: the project is open

    @classmethod
    def tearDownClass(cls):
        cls.qp.close()

    def test_each_of_the_ten_questions_is_answered_as_the_index_says_in_at_most_15_ms(self):
        medians = {}
        for q in cs.QUESTIONS_16:
            with self.subTest(question=q["id"], kind=q["kind"]):
                kind, arguments = cs.request_for(q, self.pe)
                want = cs.expected_value(q, self.pe, self.idx)
                times = []
                for _ in range(3):
                    reply = self.qp.ask(kind, **arguments)
                    times.append(reply.ms)
                    got = cs.normalise_answer(q, reply.answer)
                    if q["kind"] == "callers":
                        # the call sites must be exactly the index's; the calling
                        # function is compared only where .pdata names it. The seed makes functions the
                        # index cannot name, such as 0x140420230, which tail-jumps to 0x140663030 at 0x14042023e
                        sites = cs.caller_sites(reply.answer)
                        index_sites = cs.expected_caller_sites(q, self.pe, self.idx)
                        self.assertEqual(set(sites), set(index_sites))
                        for site, function in index_sites.items():
                            if function is not None:
                                self.assertEqual(sites[site], function, hex(site))
                    elif q["kind"] == "import":
                        # a site outside every .pdata function (0x1402801f3 for ShowCursor) may sit in a
                        # function Ghidra made from the seed; the sites themselves must be exactly the index's
                        self.assertEqual(set(got), set(want))
                        for site, function in want.items():
                            if function is not None:
                                self.assertEqual(got[site], function, hex(site))
                    else:
                        self.assertEqual(got, want)
                medians[q["id"]] = statistics.median(times)
                self.assertLessEqual(medians[q["id"]], 15.0, "question %d" % q["id"])
        print("median ms per question:", {k: round(v, 2) for k, v in medians.items()})

    def test_the_callees_of_0x140283670_name_the_five_imports_as_dll_bang_name_in_one_request(self):
        # fact file record 0x140283670
        answer = self.qp.ask("callees", function="0x140283670").answer
        self.assertEqual(
            sorted(answer["imports"]),
            [
                "gdi32.dll!AddFontMemResourceEx",
                "kernel32.dll!DebugBreak",
                "kernel32.dll!GetLastError",
                "kernel32.dll!TlsGetValue",
                "kernel32.dll!TlsSetValue",
            ],
        )
        self.assertEqual(
            sorted(int(a, 16) for a in answer["internal"]),
            [0x1401971E0, 0x1401A3130, 0x1401B54E0, 0x1401B6D00, 0x140288100],
        )

    def test_the_27_case_switch_targets_are_the_jump_table_readers_27_targets(self):
        want = [t for t in read_function(self.pe, cs.FN_CONTROL_SWITCH) if t.jmp == cs.JMP_CONTROL_SWITCH][0].targets
        self.assertEqual(len(want), 27)
        got = self.qp.ask("switch_targets", jmp=hx(cs.JMP_CONTROL_SWITCH)).answer
        self.assertEqual({int(a, 16) for a in got}, set(want))

    def test_the_pointer_only_function_0x14077ed70_is_a_function(self):
        # pointer-only, one relocated pointer (fact file record 0x14077ed70); the seed names it seed_<address>
        answer = self.qp.ask("function_at", address=hx(cs.POINTER_ONLY_A)).answer
        self.assertIsNotNone(answer)
        self.assertEqual(int(answer["start"], 16), cs.POINTER_ONLY_A)
        self.assertEqual(answer["name"], "seed_14077ed70")

    def test_the_pointer_only_function_0x14077ed70_lists_its_one_pointer_from_0x140b6d240(self):
        refs = self.qp.ask("refs_to", address=hx(cs.POINTER_ONLY_A)).answer
        self.assertIn(0x140B6D240, [int(r["from"], 16) for r in refs])

    def test_function_at_an_address_inside_a_function_names_its_start(self):
        # the jmp of the 27-case switch lies in function 0x140003fb0 (fact file record 0x140003fb0)
        answer = self.qp.ask("function_at", address=hx(cs.JMP_CONTROL_SWITCH)).answer
        self.assertEqual(int(answer["start"], 16), cs.FN_CONTROL_SWITCH)

    def test_function_at_a_data_address_is_null(self):
        self.assertIsNone(self.qp.ask("function_at", address="0x140b47ec8").answer)  # the string "Lighting"

    def test_the_seed_made_every_pdata_start_and_pointer_only_function_a_function(self):
        # the planted unmapped address is not a function
        functions = {int(a, 16) for a in self.qp.ask("functions").answer}
        seeded = {a for a, _k, _n in self.project.seed_lines} - {seed.PLANTED_UNMAPPED}
        self.assertLessEqual(seeded, functions)
        self.assertNotIn(seed.PLANTED_UNMAPPED, functions)

    def test_bytes_returns_the_files_bytes_as_hex(self):
        # 16 bytes at 0x1404a4e30 (fact file record 0x1404a4e30)
        self.assertEqual(
            self.qp.ask("bytes", address="0x1404a4e30", length=16).answer, "48895c24084889742410574883ec4041"
        )


@cs.integration_only
class BadRequestTest(unittest.TestCase):
    """Item 9."""

    @classmethod
    def setUpClass(cls):
        cls.qp = cs.QueryProcess(cs.seeded_project().project_dir)
        cls.qp.ask("seed_report")

    @classmethod
    def tearDownClass(cls):
        cls.qp.close()

    def assert_still_answering(self):
        self.assertEqual(
            self.qp.ask("bytes", address="0x1404a4e30", length=16).answer, "48895c24084889742410574883ec4041"
        )

    def test_a_malformed_json_line_gets_an_error_reply_and_the_next_request_is_answered(self):
        reply = self.qp.send_line(b"{this is not json")
        self.assertIs(reply.body["ok"], False)
        self.assertIsInstance(reply.body["error"], str)
        self.assert_still_answering()

    def test_an_unknown_kind_gets_an_error_reply_with_its_id_and_the_next_request_is_answered(self):
        reply = self.qp.send_line(json.dumps({"id": 77, "kind": "no_such_kind"}).encode())
        self.assertIs(reply.body["ok"], False)
        self.assertEqual(reply.body["id"], 77)
        self.assertIn("no_such_kind", reply.body["error"])  # the documented error names the kind
        self.assert_still_answering()

    def test_a_request_with_an_address_that_is_not_hex_gets_an_error_reply(self):
        reply = self.qp.send_line(json.dumps({"id": 78, "kind": "bytes", "address": "zzz", "length": 4}).encode())
        self.assertIs(reply.body["ok"], False)
        self.assertEqual(reply.body["id"], 78)
        self.assert_still_answering()

    def test_a_json_line_that_is_not_an_object_gets_an_error_reply(self):
        reply = self.qp.send_line(b"[1, 2, 3]")
        self.assertIs(reply.body["ok"], False)
        self.assert_still_answering()


PARENT_SCRIPT = r"""
import json, subprocess, sys, time
cmd, env, cwd = json.loads(sys.argv[1]), json.loads(sys.argv[2]), sys.argv[3]
child = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env, cwd=cwd)
child.stdin.write(b'{"id": 1, "kind": "seed_report"}\n')
child.stdin.flush()
child.stdout.readline()
print(child.pid, flush=True)
time.sleep(600)
"""


@cs.integration_only
class CleanStopTest(unittest.TestCase):
    """Item 10: no java or decompile process is left 5 s after the end."""

    def setUp(self):
        self.project = cs.seeded_project()
        self.baseline = cs.java_or_decompile_pids()  # other sessions' processes are not ours

    def assert_gone_within_5_seconds(self, tree):
        gone = cs.wait_until(
            lambda: not any(cs.pid_alive(p) for p in tree) and not (cs.java_or_decompile_pids() - self.baseline),
            5.0,
        )
        left = [p for p in tree if cs.pid_alive(p)] + sorted(cs.java_or_decompile_pids() - self.baseline)
        self.assertTrue(gone, "still running 5 s after the end: %s" % left)

    def test_closing_stdin_stops_the_process_and_everything_it_started(self):
        qp = cs.QueryProcess(self.project.project_dir)
        try:
            qp.ask("seed_report")
            tree = cs.process_tree(qp.proc.pid)
            self.assertIn(qp.proc.pid, tree)
            qp.proc.stdin.close()
            self.assert_gone_within_5_seconds(tree)
            self.assertEqual(qp.proc.wait(timeout=5), 0)
        finally:
            qp.kill()

    def test_killing_the_parent_stops_the_process_and_everything_it_started(self):
        # a parent Python in its own process group starts the query process; it is killed, alone
        # (not its group), so the query process finds its stdin closed and its parent gone
        with tempfile.TemporaryDirectory() as d:
            parent = subprocess.Popen(
                [
                    sys.executable,
                    "-I",
                    "-c",
                    PARENT_SCRIPT,
                    json.dumps(cs.query_command()),
                    json.dumps(cs.query_environment(self.project.project_dir)),
                    str(self.project.project_dir),
                ],
                stdout=subprocess.PIPE,
                start_new_session=True,
            )
            tree = []
            try:
                child_pid = int(parent.stdout.readline())  # printed after the first answer
                tree = cs.process_tree(child_pid)
                self.assertIn(child_pid, tree)
                os.kill(parent.pid, signal.SIGKILL)
                parent.wait()
                self.assert_gone_within_5_seconds(tree)
            finally:
                if parent.poll() is None:
                    os.kill(parent.pid, signal.SIGKILL)
                for pid in tree:
                    if cs.pid_alive(pid):
                        os.kill(pid, signal.SIGKILL)


@cs.integration_only
class StaysLocalTest(unittest.TestCase):
    """Item 11."""

    def test_the_first_session_that_imported_and_analysed_made_no_connection_off_this_machine(self):
        w = cs.seeded_project().watcher
        self.assertGreater(w.samples, 1)
        self.assertGreaterEqual(w.max_tree, 1)
        self.assertEqual(w.outside, [])

    def test_a_reopened_session_with_every_kind_of_request_made_no_connection_off_this_machine(self):
        project = cs.seeded_project()
        qp = cs.QueryProcess(project.project_dir)
        watcher = cs.Watcher(qp.proc.pid)
        try:
            qp.ask("seed_report")
            for kind, arguments in (
                ("bytes", {"address": "0x1404a4e30", "length": 16}),
                ("function_at", {"address": "0x14077ed70"}),
                ("callers", {"function": "0x140663030"}),
                ("callees", {"function": "0x140283670"}),
                ("refs_to", {"address": "0x14077ed70"}),
                ("string_refs", {"text": "Lighting"}),
                ("switch_targets", {"jmp": "0x140003fe8"}),
            ):
                self.assertTrue(qp.ask(kind, **arguments).body["ok"], kind)
            qp.close()
        finally:
            qp.kill()
            watcher.finish()
        self.assertGreaterEqual(watcher.samples, 1)
        self.assertEqual(watcher.outside, [])

    def test_the_watcher_flags_a_connection_to_this_machines_lan_address(self):
        # planted: a child connects to the LAN address, not loopback; the watcher must catch it
        lan = cs.lan_address()
        if lan is None:
            self.skipTest("this machine has no LAN address to plant a connection to")
        watcher = cs.watch_a_connection(lan)
        self.assertGreater(len(watcher.outside), 0)

    def test_the_watcher_does_not_flag_a_loopback_connection(self):
        watcher = cs.watch_a_connection("127.0.0.1")
        self.assertGreater(len(watcher.socket_lines), 0)  # it saw the socket
        self.assertEqual(watcher.outside, [])


@cs.integration_only
class UnseededProjectTest(unittest.TestCase):
    """Item 5: the same analysis as 12.1.4. Builds its own project, without a seed."""

    @classmethod
    def setUpClass(cls):
        cls.pe = cs.client_pe()
        _root, project_dir = cs.fresh_unseeded_project()
        cls.qp = cs.QueryProcess(project_dir)
        cls.report = cls.qp.ask("seed_report", timeout=1800).answer
        cls.functions = {int(a, 16) for a in cls.qp.ask("functions").answer}

    @classmethod
    def tearDownClass(cls):
        cls.qp.close()

    def test_an_unseeded_import_finds_24970_functions(self):
        self.assertEqual(len(self.functions), 24970)  # plain Ghidra, 12.1.4 and 12.2

    def test_ghidra_agrees_with_the_jump_table_reader_on_299_of_302_switches(self):
        # the three that differ are the jmps at 0x1400bc619, 0x1403ec719 and 0x140612b08 (fact file records)
        switches = cs.all_found_switches()
        self.assertEqual(len(switches), 302)
        differ = []
        for t in switches:
            got = {int(a, 16) for a in self.qp.ask("switch_targets", jmp=hx(t.jmp)).answer}
            if got != set(t.targets):
                differ.append(t.jmp)
        self.assertEqual(len(switches) - len(differ), 299)
        self.assertEqual(sorted(differ), sorted(cs.SWITCH_JMP_DIFFERENCES))


if __name__ == "__main__":
    unittest.main(verbosity=2)

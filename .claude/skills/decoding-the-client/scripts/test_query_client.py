"""query_client.QueryClient, against a planted server that speaks the query process's line protocol.

The server is a few lines of Python, so these tests need neither Ghidra nor the client. The
protocol is ghidra_query.py's own: one JSON request per line in, one JSON reply per line out,
{"id", "ok": true, "answer"} or {"id", "ok": false, "error"}. Run: python3 -I test_query_client.py
"""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from query_client import (  # noqa: E402
    NotConfigured,
    QueryClient,
    QueryFailed,
    QueryProcessEnded,
    QueryTimeout,
    answer_of,
    check_reply_id,
    open_query_client,
    query_command,
)

# Answers {"echo": the request's arguments}; kind "refuse" gets an error reply; kind "die" writes to
# stderr and exits; kind "hang" reads the request and never answers.
PLANTED_SERVER = r"""
import json, sys, time
for line in sys.stdin:
    request = json.loads(line)
    kind = request["kind"]
    if kind == "die":
        sys.stderr.write("planted: the server stopped")
        sys.exit(3)
    if kind == "hang":
        time.sleep(600)
    if kind == "garbage":
        print("this is not json", flush=True)
        continue
    if kind == "list":
        print("[1, 2]", flush=True)
        continue
    if kind == "refuse":
        reply = {"id": request["id"], "ok": False, "error": "planted refusal"}
    else:
        reply = {"id": request["id"], "ok": True, "answer": {"echo": request["text"]}}
    print(json.dumps(reply), flush=True)
"""


def planted_client() -> QueryClient:
    return QueryClient([sys.executable, "-I", "-c", PLANTED_SERVER], dict(os.environ))


class QueryClientTest(unittest.TestCase):
    def setUp(self):
        self.client = planted_client()
        self.addCleanup(self.client.kill)

    def test_an_answer_is_the_replys_answer(self):
        self.assertEqual(self.client.answer("say", text="hello"), {"echo": "hello"})
        self.assertEqual(self.client.answer("say", text="again"), {"echo": "again"})

    def test_an_error_reply_raises_with_the_servers_message_and_the_process_goes_on(self):
        with self.assertRaisesRegex(QueryFailed, "planted refusal"):
            self.client.answer("refuse")
        self.assertEqual(self.client.answer("say", text="still here"), {"echo": "still here"})

    def test_a_process_that_ends_raises_with_what_it_wrote_to_stderr(self):
        with self.assertRaisesRegex(QueryProcessEnded, "planted: the server stopped"):
            self.client.answer("die")

    def test_a_reply_that_does_not_come_in_time_raises(self):
        with self.assertRaises(QueryTimeout):
            self.client.answer("hang", timeout=0.5)

    def test_closing_ends_the_process_with_exit_status_0(self):
        self.assertEqual(self.client.close(), 0)

    def test_a_reply_that_is_not_json_raises_process_ended_as_a_protocol_break(self):
        with self.assertRaisesRegex(QueryProcessEnded, "protocol"):
            self.client.answer("garbage", text="")

    def test_a_reply_that_is_json_but_not_an_object_raises_process_ended(self):
        with self.assertRaisesRegex(QueryProcessEnded, "protocol"):
            self.client.answer("list", text="")


class ReplyTest(unittest.TestCase):
    def test_the_answer_of_an_ok_reply_is_its_answer(self):
        self.assertEqual(answer_of({"id": 1, "ok": True, "answer": [1, 2]}), [1, 2])
        self.assertIsNone(answer_of({"id": 1, "ok": True, "answer": None}))

    def test_an_error_reply_raises_query_failed_with_its_error_text(self):
        with self.assertRaisesRegex(QueryFailed, "planted refusal"):
            answer_of({"id": 1, "ok": False, "error": "planted refusal"})

    def test_a_reply_that_is_neither_ok_nor_has_error_text_raises_query_failed_showing_it(self):
        with self.assertRaisesRegex(QueryFailed, "no error text in .*'surprise'"):
            answer_of({"id": 1, "surprise": True})

    def test_a_reply_with_the_requests_id_passes_and_one_with_another_id_raises_process_ended(self):
        check_reply_id({"id": 4, "kind": "x"}, {"id": 4, "ok": True})
        with self.assertRaisesRegex(QueryProcessEnded, "not for"):
            check_reply_id({"id": 4, "kind": "x"}, {"id": 3, "ok": True})

    def test_a_request_with_no_id_has_no_id_to_check(self):
        check_reply_id({"kind": "x"}, {"id": None, "ok": False})

    def test_a_request_that_is_not_an_object_has_no_id_to_check(self):
        check_reply_id([1, 2], {"id": None, "ok": False})


class CloseTest(unittest.TestCase):
    def test_a_process_that_ends_with_a_non_zero_status_after_stdin_closes_makes_close_raise_with_it(self):
        client = QueryClient([sys.executable, "-I", "-c", "import sys\nfor line in sys.stdin: pass\nsys.exit(3)"], dict(os.environ))
        self.addCleanup(client.kill)
        with self.assertRaisesRegex(QueryProcessEnded, "exit status 3"):
            client.close()

    def test_close_of_a_process_that_already_ended_does_not_raise_a_broken_pipe(self):
        client = QueryClient([sys.executable, "-I", "-c", "pass"], dict(os.environ))
        self.addCleanup(client.kill)
        client.proc.wait()
        client.proc.stdin.write(b"unread")  # buffered; closing flushes it into the closed pipe
        self.assertEqual(client.close(), 0)


class CommandTest(unittest.TestCase):
    def test_the_command_runs_the_python_the_given_environment_names(self):
        command = query_command(env={"GENESIS_PYGHIDRA_PYTHON": "/planted/python"})
        self.assertEqual(command[0], "/planted/python")
        self.assertTrue(command[1].endswith("ghidra_query.py"))

    def test_the_command_ignores_the_processs_own_environment(self):
        with mock.patch.dict(os.environ, {"GENESIS_PYGHIDRA_PYTHON": "/from/os/environ"}):
            with self.assertRaises(NotConfigured):
                query_command(env={})

    def test_open_query_client_uses_the_environment_it_is_given(self):
        # the four paths ghidra_env reads are set; the python is missing, though os.environ holds one
        env = {"GENESIS_GHIDRA_DIR": "/g", "GENESIS_GHIDRA_PROJECT_DIR": "/p", "WILDSTAR_CLIENT_EXE": "/w", "JAVA_HOME": "/j"}
        with mock.patch.dict(os.environ, {"GENESIS_PYGHIDRA_PYTHON": "/from/os/environ"}):
            with self.assertRaises(NotConfigured):
                open_query_client(env)


if __name__ == "__main__":
    unittest.main(verbosity=2)

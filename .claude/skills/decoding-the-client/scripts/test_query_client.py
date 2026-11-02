"""query_client.QueryClient, against a planted server that speaks the query process's line protocol.

The server is a few lines of Python, so these tests need neither Ghidra nor the client. The
protocol is ghidra_query.py's own: one JSON request per line in, one JSON reply per line out,
{"id", "ok": true, "answer"} or {"id", "ok": false, "error"}. Run: python3 -I test_query_client.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from query_client import QueryClient, QueryFailed, QueryProcessEnded, QueryTimeout  # noqa: E402

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


if __name__ == "__main__":
    unittest.main(verbosity=2)

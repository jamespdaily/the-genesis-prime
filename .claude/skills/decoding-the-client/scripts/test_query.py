"""query.py: the one command that sends the query process a request from any shell.

The CI tests run the holder (the process that keeps the query process open and listens on a
Unix socket) as a thread of the test, over a planted query process that speaks ghidra_query.py's
line protocol: one JSON request per line in, {"id", "ok": true, "answer"} or {"id", "ok": false,
"error"} out, an error reply for a line that is not JSON, and the process goes on. They need
neither Ghidra nor the client. The one test of the real process runs under GENESIS_INTEGRATION=1.
Run: python3 -I test_query.py   (GENESIS_INTEGRATION=1 adds the real-process test)
"""

import fcntl
import io
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
import ghidra_project  # noqa: E402
import name_functions  # noqa: E402
import query  # noqa: E402
import recover_switches  # noqa: E402
from query_client import QueryClient, QueryFailed, QueryProcessEnded, QueryTimeout  # noqa: E402

# kind "who" answers the process's pid and how many requests it has answered; "echo" answers the
# request's text; "refuse" and a line that is not JSON get an error reply; "sleep" answers after
# `seconds`; "later" answers from a thread, after `seconds` for the first such request and at once for
# any after it, so a second request that arrives while the first waits is answered first;
# "wrongid" answers with another request's id; "slow_exit" sets how long the process takes to end
# once its input closes; "big" answers a string of `size` characters; "die" writes to stderr and
# exits; "hang" never answers.
PLANTED_QUERY_PROCESS = r"""
import json, os, sys, threading, time
answered = 0
exit_delay = 0
delayed = False
printing = threading.Lock()

def send(reply):
    with printing:
        print(json.dumps(reply), flush=True)

for line in sys.stdin:
    try:
        request = json.loads(line)
    except ValueError:
        send({"id": None, "ok": False, "error": "planted: not JSON"})
        continue
    kind = request["kind"]
    if kind == "die":
        sys.stderr.write("planted: the process stopped")
        sys.exit(3)
    if kind == "hang":
        time.sleep(600)
    answered += 1
    if kind == "refuse":
        reply = {"id": request.get("id"), "ok": False, "error": "planted refusal"}
    elif kind == "who":
        reply = {"id": request.get("id"), "ok": True, "answer": {"pid": os.getpid(), "answered": answered}}
    elif kind == "big":
        reply = {"id": request.get("id"), "ok": True, "answer": "x" * request["size"]}
    elif kind == "wrongid":
        reply = {"id": request.get("id") + 100, "ok": True, "answer": {"echo": request.get("text")}}
    elif kind == "slow_exit":
        exit_delay = request["seconds"]
        reply = {"id": request.get("id"), "ok": True, "answer": None}
    else:
        reply = {"id": request.get("id"), "ok": True, "answer": {"echo": request.get("text")}}
        if kind == "later":
            threading.Timer(0 if delayed else request["seconds"], send, [reply]).start()
            delayed = True
            continue
        if kind == "sleep":
            time.sleep(request["seconds"])
    send(reply)
time.sleep(exit_delay)
"""

PLANTED_START_S = 0  # the planted process answers at once, so its first request gets no extra time


def planted_query_process() -> QueryClient:
    return QueryClient([sys.executable, "-I", "-c", PLANTED_QUERY_PROCESS], dict(os.environ))


def planted_environment(home: Path, project: str = "project") -> dict:
    """The four settings ghidra_env reads, naming nothing real, and a home of the test's own."""
    return {
        "GENESIS_HOME": str(home),
        "GENESIS_GHIDRA_DIR": str(home / "ghidra"),
        "GENESIS_GHIDRA_PROJECT_DIR": str(home / project),
        "WILDSTAR_CLIENT_EXE": str(home / "WildStar64.exe"),
        "JAVA_HOME": str(home / "jdk"),
        "GENESIS_PYGHIDRA_PYTHON": sys.executable,
    }


class HolderTest(unittest.TestCase):
    """Each test starts holders as threads over planted query processes, through the command's own
    start hook, and ends them before it finishes."""

    idle_s = 600.0
    timeout_s = 30.0

    def setUp(self):
        # a short folder: a Unix socket's path is at most 104 bytes on macOS
        self.home = Path(tempfile.mkdtemp(prefix="gq-", dir="/tmp"))
        self.addCleanup(shutil.rmtree, self.home)
        self.env = planted_environment(self.home)
        self.paths = query.paths_for(self.env)
        self.holders: list[threading.Thread] = []
        self.query_processes: list[QueryClient] = []
        self.holder_errors: list[BaseException] = []
        self.addCleanup(self.end_holders)

    def open_planted(self) -> QueryClient:
        client = planted_query_process()
        self.query_processes.append(client)
        return client

    def start_holder(self, paths: "query.Paths", idle_s: float | None = None, timeout_s: float | None = None):
        def run():
            try:
                query.run_holder(
                    paths, self.open_planted, idle_s or self.idle_s, timeout_s or self.timeout_s, PLANTED_START_S
                )
            except BaseException as error:  # the test that expects one reads it from the list
                self.holder_errors.append(error)

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        self.holders.append(thread)

    def end_holders(self):
        if self.paths.lock.exists():
            query.main(["stop"], self.env, io.StringIO(), io.StringIO())
        for thread in self.holders:
            thread.join(timeout=30)
        for client in self.query_processes:
            client.kill()

    def run_command(self, *argv: str, env: dict | None = None, start=None):
        out, err = io.StringIO(), io.StringIO()
        status = query.main(list(argv), env or self.env, out, err, start or self.start_holder)
        return status, out.getvalue(), err.getvalue()

    def ask(self, request: dict) -> dict:
        status, out, err = self.run_command("ask", json.dumps(request))
        self.assertEqual((status, err), (0, ""))
        return json.loads(out)

    def holder_running(self) -> bool:
        return self.paths.lock.exists()

    def wait_for(self, condition, what: str, seconds: float = 30.0):
        """Polls an observable condition until it holds; fails naming what never happened."""
        deadline = time.monotonic() + seconds
        while not condition():
            self.assertLess(time.monotonic(), deadline, "never happened: " + what)
            time.sleep(0.01)

    def connect(self) -> socket.socket:
        """A connection to the holder once it listens."""
        found = []

        def listening() -> bool:
            connection = query._connect(self.paths)
            if connection is not None:
                found.append(connection)
            return connection is not None

        self.wait_for(listening, "the holder listens")
        self.addCleanup(found[0].close)
        return found[0]

    def stop_without_waiting(self) -> None:
        """Asks the holder to stop on a connection of its own and returns at its reply, before it has ended."""
        connection = self.connect()
        with connection.makefile("rb") as reader:
            connection.sendall(b'{"holder": "stop"}\n')
            self.assertEqual(json.loads(reader.readline()), {"holder": "stopped"})


class FirstRequestTest(HolderTest):
    """Item 1."""

    def test_a_first_request_starts_the_process_and_returns_its_reply_and_a_second_reuses_it(self):
        first = self.ask({"id": 1, "kind": "who"})
        second = self.ask({"id": 2, "kind": "who"})
        self.assertEqual(len(self.holders), 1)  # the second request found the holder
        self.assertEqual(len(self.query_processes), 1)
        self.assertEqual((first["id"], second["id"]), (1, 2))
        self.assertEqual(first["answer"]["pid"], second["answer"]["pid"])  # one query process answered both
        self.assertEqual((first["answer"]["answered"], second["answer"]["answered"]), (1, 2))

    def test_a_request_from_another_shell_reaches_the_same_process(self):
        # a shell is a fresh run of the command: a second thread asks while the first holder runs
        first = self.ask({"id": 1, "kind": "who"})
        replies = []
        shell = threading.Thread(target=lambda: replies.append(self.ask({"id": 2, "kind": "who"})))
        shell.start()
        shell.join(timeout=30)
        self.assertEqual(replies[0]["answer"]["pid"], first["answer"]["pid"])

    def test_two_commands_asking_at_once_each_get_the_reply_to_their_own_request(self):
        # the request that reaches the query process first is answered last: a holder that let both wait
        # on the query process at once would give each the other's reply
        self.start_holder(self.paths)
        self.connect()  # the holder listens before the commands race
        barrier = threading.Barrier(2)
        results = {}

        def shell(request: dict) -> None:
            barrier.wait()
            results[request["id"]] = self.run_command("ask", json.dumps(request))

        requests = [{"id": 1, "kind": "later", "seconds": 0.6, "text": "a"}, {"id": 2, "kind": "later", "seconds": 0.6, "text": "b"}]
        threads = [threading.Thread(target=shell, args=(request,)) for request in requests]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)
        for request in requests:
            status, out, err = results[request["id"]]
            self.assertEqual((status, err), (0, ""))
            self.assertEqual(json.loads(out)["answer"], {"echo": request["text"]})
            self.assertEqual(json.loads(out)["id"], request["id"])

    def test_a_reply_larger_than_a_socket_buffer_arrives_whole(self):
        reply = self.ask({"id": 1, "kind": "big", "size": 5_000_000})
        self.assertEqual(reply["answer"], "x" * 5_000_000)


class RequestFileTest(HolderTest):
    """Item 2."""

    def test_a_request_file_returns_one_reply_per_line_in_order(self):
        requests = self.home / "requests.jsonl"
        requests.write_text(
            "\n".join(json.dumps({"id": n, "kind": "echo", "text": text}) for n, text in enumerate("cab", 1)) + "\n"
        )
        status, out, err = self.run_command("ask", "--file", str(requests))
        self.assertEqual((status, err), (0, ""))
        replies = [json.loads(line) for line in out.splitlines()]
        self.assertEqual([(r["id"], r["answer"]["echo"]) for r in replies], [(1, "c"), (2, "a"), (3, "b")])

    def test_a_blank_line_in_the_file_is_not_a_request(self):
        requests = self.home / "requests.jsonl"
        requests.write_text('\n{"id": 1, "kind": "echo", "text": "a"}\n\n   \n{"id": 2, "kind": "echo", "text": "b"}\n')
        _status, out, _err = self.run_command("ask", "--file", str(requests))
        self.assertEqual([json.loads(line)["id"] for line in out.splitlines()], [1, 2])

    def test_an_error_reply_in_the_file_does_not_stop_the_replies_after_it_and_the_status_is_1(self):
        requests = self.home / "requests.jsonl"
        requests.write_text('{"id": 1, "kind": "refuse"}\n{"id": 2, "kind": "echo", "text": "after"}\n')
        status, out, _err = self.run_command("ask", "--file", str(requests))
        replies = [json.loads(line) for line in out.splitlines()]
        self.assertEqual([r["ok"] for r in replies], [False, True])
        self.assertEqual(status, 1)

    def test_a_missing_request_file_is_refused_by_name_before_any_process_starts(self):
        status, out, err = self.run_command("ask", "--file", str(self.home / "absent.jsonl"))
        self.assertEqual((status, out), (1, ""))
        self.assertIn("absent.jsonl", err)
        self.assertEqual(self.holders, [])


class SecondStartTest(HolderTest):
    """Item 3."""

    def test_a_second_holder_on_the_same_project_is_refused_naming_the_running_one(self):
        self.ask({"id": 1, "kind": "who"})
        with self.assertRaises(query.AlreadyRunning) as raised:
            query.run_holder(self.paths, self.open_planted, 600, 30, PLANTED_START_S)
        message = str(raised.exception)
        self.assertEqual(raised.exception.pid, os.getpid())  # the holder here is a thread of this process
        self.assertIn("pid %d" % os.getpid(), message)
        self.assertIn(str(self.paths.project), message)
        self.assertIn(str(self.paths.log), message)
        self.assertEqual(len(self.query_processes), 1)  # the refused holder opened no query process

    def test_a_holder_on_another_project_is_not_refused(self):
        self.ask({"id": 1, "kind": "who"})
        other_env = planted_environment(self.home, project="other-project")
        other = query.paths_for(other_env)
        self.assertNotEqual(other.lock, self.paths.lock)
        self.assertNotEqual(other.socket, self.paths.socket)
        status, out, _err = self.run_command("ask", json.dumps({"id": 1, "kind": "who"}), env=other_env)
        self.assertEqual(status, 0)
        self.assertEqual(len(self.holders), 2)
        self.assertNotEqual(json.loads(out)["answer"]["pid"], self.ask({"id": 2, "kind": "who"})["answer"]["pid"])
        query.main(["stop"], other_env, io.StringIO(), io.StringIO())

    def test_status_names_the_running_process_its_project_and_its_log(self):
        self.ask({"id": 1, "kind": "who"})
        status, out, _err = self.run_command("status")
        self.assertEqual(status, 0)
        self.assertIn("running", out)
        self.assertIn("pid %d" % os.getpid(), out)
        self.assertIn(str(self.paths.project), out)
        self.assertIn(str(self.paths.log), out)

    def test_status_with_no_process_says_so_and_exits_1(self):
        status, out, _err = self.run_command("status")
        self.assertEqual(status, 1)
        self.assertIn("not running", out)


class StopTest(HolderTest):
    """Item 4."""

    def test_stop_ends_the_holder_and_the_query_process_and_removes_the_socket_and_the_lock(self):
        self.ask({"id": 1, "kind": "who"})
        status, out, err = self.run_command("stop")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("stopped", out)
        self.holders[0].join(timeout=30)
        self.assertFalse(self.holders[0].is_alive())
        self.assertIsNotNone(self.query_processes[0].proc.poll())  # the query process is gone
        self.assertFalse(self.paths.socket.exists())
        self.assertFalse(self.paths.lock.exists())

    def test_the_next_request_after_a_stop_starts_a_new_process(self):
        before = self.ask({"id": 1, "kind": "who"})
        self.run_command("stop")
        after = self.ask({"id": 2, "kind": "who"})
        self.assertEqual(len(self.holders), 2)
        self.assertNotEqual(before["answer"]["pid"], after["answer"]["pid"])

    def test_stop_with_no_process_says_so_and_succeeds(self):
        status, out, _err = self.run_command("stop")
        self.assertEqual(status, 0)
        self.assertIn("no query process", out)


class IdleTimeoutTest(HolderTest):
    """Item 4."""

    def test_the_holder_ends_after_the_idle_time_and_removes_its_socket_and_its_lock(self):
        self.start_holder(self.paths, idle_s=0.3)
        self.holders[0].join(timeout=30)  # ends by itself, with no request
        self.assertFalse(self.holders[0].is_alive())
        self.assertFalse(self.paths.socket.exists())
        self.assertFalse(self.paths.lock.exists())
        self.assertIsNotNone(self.query_processes[0].proc.poll())

    def test_a_command_whose_request_is_being_answered_keeps_the_holder_up_for_its_next_request(self):
        # the first request outlasts the idle time; the second, on the same connection, needs the holder still serving
        self.start_holder(self.paths, idle_s=1.0)
        self.connect().close()  # the holder listens, so the command finds it instead of starting a second
        requests = self.home / "requests.jsonl"
        requests.write_text('{"id": 1, "kind": "sleep", "seconds": 2.5}\n{"id": 2, "kind": "who"}\n')
        status, out, err = self.run_command("ask", "--file", str(requests))
        self.assertEqual((status, err), (0, ""))
        self.assertEqual([json.loads(line)["id"] for line in out.splitlines()], [1, 2])
        self.assertEqual(len(self.holders), 1)  # no second holder answered the second request

    def test_the_idle_time_is_read_from_the_environment_and_a_bad_value_is_refused_by_name(self):
        self.assertEqual(query.idle_seconds({"GENESIS_QUERY_IDLE_S": "12.5"}), 12.5)
        self.assertEqual(query.idle_seconds({}), 1800.0)
        for bad in ("soon", "0", "-5", "nan"):
            with self.subTest(value=bad):
                with self.assertRaisesRegex(query.BadSetting, "GENESIS_QUERY_IDLE_S"):
                    query.idle_seconds({"GENESIS_QUERY_IDLE_S": bad})


class IdleRaceTest(unittest.TestCase):
    """The idle stop and a connection that arrives at the same moment."""

    class Server:
        def __init__(self):
            self.shut_down = threading.Event()

        def shutdown(self):
            self.shut_down.set()

    def idle_holder(self) -> "query._Holder":
        holder = query._Holder(None, 1.0, 30.0, 0)
        holder.server = self.Server()
        holder.last_activity -= 100  # idle for far longer than idle_s
        return holder

    def test_a_connection_that_was_admitted_keeps_an_otherwise_idle_holder_up(self):
        holder = self.idle_holder()
        self.assertTrue(holder.admit())
        self.assertFalse(holder.stop_if_idle())
        self.assertFalse(holder.stopping.is_set())

    def test_a_connection_that_arrives_after_the_idle_stop_is_refused(self):
        holder = self.idle_holder()
        self.assertTrue(holder.stop_if_idle())
        self.assertTrue(holder.server.shut_down.wait(timeout=30))
        self.assertFalse(holder.admit())


class BadRequestTest(HolderTest):
    """Item 5."""

    def test_a_request_that_is_not_json_gets_the_query_processs_error_reply_and_the_process_stays_up(self):
        before = self.ask({"id": 1, "kind": "who"})
        status, out, err = self.run_command("ask", "this is not json")
        self.assertEqual(status, 1)
        self.assertEqual(err, "")
        self.assertEqual(json.loads(out), {"id": None, "ok": False, "error": "planted: not JSON"})
        after = self.ask({"id": 2, "kind": "who"})
        self.assertEqual(after["answer"]["pid"], before["answer"]["pid"])
        self.assertEqual(len(self.holders), 1)

    def test_a_refused_request_gets_the_error_reply_and_the_process_stays_up(self):
        before = self.ask({"id": 1, "kind": "who"})
        status, out, _err = self.run_command("ask", json.dumps({"id": 2, "kind": "refuse"}))
        self.assertEqual((status, json.loads(out)["error"]), (1, "planted refusal"))
        self.assertEqual(self.ask({"id": 3, "kind": "who"})["answer"]["pid"], before["answer"]["pid"])

    def test_a_request_written_over_several_lines_is_sent_as_one(self):
        status, out, _err = self.run_command("ask", '{"id": 7,\n "kind": "echo",\n "text": "multi"}')
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(out)["answer"], {"echo": "multi"})


class QueryProcessFailureTest(HolderTest):
    """A query process that ends or does not answer is reported by the command, and the next request
    starts a new one."""

    def test_a_query_process_that_dies_is_reported_with_its_stderr_and_the_next_request_starts_a_new_one(self):
        before = self.ask({"id": 1, "kind": "who"})
        status, out, err = self.run_command("ask", json.dumps({"id": 2, "kind": "die"}))
        self.assertEqual((status, out), (1, ""))
        self.assertIn("planted: the process stopped", err)
        self.holders[0].join(timeout=30)
        self.assertFalse(self.paths.lock.exists())
        after = self.ask({"id": 3, "kind": "who"})
        self.assertNotEqual(after["answer"]["pid"], before["answer"]["pid"])
        self.assertEqual(len(self.holders), 2)

    def test_a_request_with_no_reply_in_time_is_reported_and_the_process_is_ended(self):
        self.start_holder(self.paths, timeout_s=0.5)
        status, out, err = self.run_command("ask", json.dumps({"id": 1, "kind": "hang"}))
        self.assertEqual((status, out), (1, ""))
        self.assertIn("no reply within", err)
        self.holders[0].join(timeout=30)
        self.assertFalse(self.holders[0].is_alive())
        self.assertIsNotNone(self.query_processes[0].proc.poll())  # a late reply would answer the next request
        self.assertFalse(self.paths.lock.exists())

    def test_a_timeout_s_far_beyond_what_the_query_process_accepts_does_not_end_the_holder_or_shift_the_replies(self):
        # the query process refuses a decompile timeout above 3600 s; the holder must not wait 1e10 s for it
        first = self.ask({"id": 1, "kind": "echo", "text": "x", "timeout_s": 1e10})
        self.assertEqual(first["id"], 1)
        self.assertEqual(self.ask({"id": 2, "kind": "who"})["id"], 2)
        self.assertEqual(len(self.holders), 1)

    def test_any_exception_from_the_exchange_ends_the_holder_and_the_next_request_starts_a_new_one(self):
        self.ask({"id": 1, "kind": "who"})
        with unittest.mock.patch.object(QueryClient, "exchange", side_effect=ValueError("planted: closed file")):
            status, out, err = self.run_command("ask", json.dumps({"id": 2, "kind": "who"}))
        self.assertEqual((status, out), (1, ""))
        self.assertIn("planted: closed file", err)
        self.holders[0].join(timeout=30)
        self.assertFalse(self.holders[0].is_alive())
        after = self.ask({"id": 3, "kind": "who"})
        self.assertEqual(after["id"], 3)  # a reply left on the queue would answer this request
        self.assertEqual(len(self.holders), 2)

    def test_a_reply_for_another_request_ends_the_holder_instead_of_being_passed_on(self):
        status, out, err = self.run_command("ask", json.dumps({"id": 5, "kind": "wrongid", "text": "x"}))
        self.assertEqual((status, out), (1, ""))
        self.assertIn("not for", err)
        self.holders[0].join(timeout=30)
        self.assertFalse(self.holders[0].is_alive())

    def test_the_rest_of_a_file_after_a_dead_process_is_not_sent_and_the_status_is_1(self):
        requests = self.home / "requests.jsonl"
        requests.write_text('{"id": 1, "kind": "echo", "text": "a"}\n{"id": 2, "kind": "die"}\n{"id": 3, "kind": "echo", "text": "c"}\n')
        status, out, err = self.run_command("ask", "--file", str(requests))
        self.assertEqual(status, 1)
        self.assertEqual([json.loads(line)["id"] for line in out.splitlines()], [1])
        self.assertIn("planted: the process stopped", err)


class StaleLockTest(HolderTest):
    def dead_pid(self) -> int:
        done = subprocess.Popen([sys.executable, "-I", "-c", "pass"])
        done.wait()
        return done.pid

    def plant_stale_lock(self) -> int:
        pid = self.dead_pid()
        self.home.mkdir(parents=True, exist_ok=True)
        self.paths.lock.write_text(
            json.dumps({"pid": pid, "project": str(self.paths.project), "socket": str(self.paths.socket), "log": str(self.paths.log)})
        )
        self.paths.socket.write_text("left by the holder that died")
        return pid

    def test_a_lock_whose_process_is_gone_is_cleared_and_the_request_starts_a_new_holder(self):
        stale = self.plant_stale_lock()
        reply = self.ask({"id": 1, "kind": "who"})
        self.assertTrue(reply["ok"])
        self.assertEqual(len(self.holders), 1)
        self.assertEqual(json.loads(self.paths.lock.read_text())["pid"], os.getpid())
        self.assertNotEqual(json.loads(self.paths.lock.read_text())["pid"], stale)

    def test_status_calls_a_lock_whose_process_is_gone_not_running_and_names_it(self):
        stale = self.plant_stale_lock()
        status, out, _err = self.run_command("status")
        self.assertEqual(status, 1)
        self.assertIn("not running", out)
        self.assertIn("pid %d" % stale, out)

    def test_stop_clears_a_lock_whose_process_is_gone(self):
        self.plant_stale_lock()
        status, out, _err = self.run_command("stop")
        self.assertEqual(status, 0)
        self.assertIn("no query process", out)
        self.assertFalse(self.paths.lock.exists())
        self.assertFalse(self.paths.socket.exists())

    def test_a_lock_held_by_something_that_is_not_a_holder_is_refused_by_name_and_left_in_place(self):
        with open(self.paths.lock, "w") as held:
            held.write("garbage")
            held.flush()
            fcntl.flock(held, fcntl.LOCK_EX)
            with self.assertRaises(query.BadLock) as raised:
                query.run_holder(self.paths, self.open_planted, 600, 30, PLANTED_START_S)
            self.assertIn(str(self.paths.lock), str(raised.exception))
        self.assertTrue(self.paths.lock.exists())

    def test_a_lock_file_that_names_a_running_process_that_is_not_a_holder_is_cleared_by_the_next_start(self):
        # a pid the system gave to another process after the holder died
        bystander = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(600)"])
        self.addCleanup(bystander.wait)
        self.addCleanup(bystander.kill)
        self.paths.lock.write_text(
            json.dumps({"pid": bystander.pid, "project": str(self.paths.project), "socket": str(self.paths.socket), "log": str(self.paths.log)})
        )
        status, out, _err = self.run_command("status")
        self.assertEqual(status, 1)
        self.assertIn("not running", out)
        with unittest.mock.patch.object(query, "HOLDER_WAIT_S", 10.0):
            reply = self.ask({"id": 1, "kind": "who"})
        self.assertTrue(reply["ok"])
        self.assertEqual(len(self.holders), 1)
        self.assertIsNone(bystander.poll())  # the bystander was left alone


HOLDS_THE_LOCK = r"""
import os, sys, time
sys.path.insert(0, sys.argv[1])
import query
held = query.acquire_lock(query.paths_for(os.environ))
print("held", flush=True)
time.sleep(600)
"""


class KilledHolderTest(HolderTest):
    def hold_the_lock_in_a_process(self) -> subprocess.Popen:
        holder = subprocess.Popen(
            [sys.executable, "-I", "-c", HOLDS_THE_LOCK, str(cs.SCRIPTS)], env=self.env, stdout=subprocess.PIPE, text=True
        )
        self.addCleanup(holder.wait)
        self.addCleanup(holder.kill)
        self.assertEqual(holder.stdout.readline().strip(), "held")
        return holder

    def test_a_holder_killed_without_cleanup_leaves_a_lock_the_next_start_takes_at_once(self):
        holder = self.hold_the_lock_in_a_process()
        record = query.live_holder(self.paths)
        self.assertEqual(record.pid, holder.pid)
        self.assertEqual(self.run_command("status")[0], 0)
        holder.send_signal(signal.SIGKILL)
        holder.wait()
        self.assertIsNone(query.live_holder(self.paths))
        self.assertEqual(self.run_command("status")[0], 1)
        with unittest.mock.patch.object(query, "HOLDER_WAIT_S", 10.0):
            self.assertTrue(self.ask({"id": 1, "kind": "who"})["ok"])

    def test_a_second_holder_is_refused_while_the_first_process_lives_naming_it(self):
        holder = self.hold_the_lock_in_a_process()
        with self.assertRaises(query.AlreadyRunning) as raised:
            query.run_holder(self.paths, self.open_planted, 600, 30, PLANTED_START_S)
        self.assertEqual(raised.exception.pid, holder.pid)


class OrphanedQueryProcessTest(HolderTest):
    """A holder killed while a long request ran leaves its query process holding the project."""

    def orphan(self) -> subprocess.Popen:
        orphan = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(600)"])
        self.addCleanup(orphan.wait)
        self.addCleanup(orphan.kill)
        return orphan

    def plant_lock_of_a_dead_holder_naming(self, orphan: subprocess.Popen, started: str) -> None:
        self.paths.lock.write_text(
            json.dumps(
                {
                    "pid": 2**22 + 1,  # beyond any pid in use
                    "project": str(self.paths.project),
                    "socket": str(self.paths.socket),
                    "log": str(self.paths.log),
                    "query_pid": orphan.pid,
                    "query_started": started,
                }
            )
        )

    def test_the_next_start_ends_the_query_process_a_killed_holder_left_behind(self):
        orphan = self.orphan()
        self.plant_lock_of_a_dead_holder_naming(orphan, query.started_at(orphan.pid))
        self.assertTrue(self.ask({"id": 1, "kind": "who"})["ok"])
        self.assertIsNotNone(orphan.poll())

    def test_a_process_that_only_has_the_recorded_pid_is_not_ended(self):
        bystander = self.orphan()
        self.plant_lock_of_a_dead_holder_naming(bystander, "Thu Jan 1 00:00:00 1970")
        self.assertTrue(self.ask({"id": 1, "kind": "who"})["ok"])
        self.assertIsNone(bystander.poll())

    def test_a_running_holder_records_its_query_process_in_the_lock(self):
        self.ask({"id": 1, "kind": "who"})
        record = json.loads(self.paths.lock.read_text())
        self.assertEqual(record["query_pid"], self.query_processes[0].proc.pid)
        self.assertEqual(record["query_started"], query.started_at(record["query_pid"]))


class EndingHolderTest(HolderTest):
    """A command that arrives while a holder ends: its socket is gone and its lock is still held until the
    query process has ended."""

    def holder_ending(self) -> None:
        self.ask({"id": 1, "kind": "slow_exit", "seconds": 1.5})
        self.stop_without_waiting()
        self.wait_for(lambda: not self.paths.socket.exists(), "the ending holder removes its socket")
        self.assertTrue(self.paths.lock.exists())  # the query process is still ending

    def test_a_request_while_the_holder_ends_starts_a_new_holder_when_the_lock_is_gone(self):
        self.holder_ending()
        with unittest.mock.patch.object(query, "HOLDER_WAIT_S", 10.0):
            after = self.ask({"id": 2, "kind": "who"})
        self.assertEqual(after["id"], 2)
        self.assertEqual(len(self.holders), 2)

    def test_stop_while_the_holder_ends_reports_it_stopped(self):
        self.holder_ending()
        status, out, err = self.run_command("stop")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("stopped", out)

    def test_stop_waits_for_its_own_holder_even_when_a_new_holder_has_taken_the_lock_by_then(self):
        self.ask({"id": 1, "kind": "who"})
        first = self.holders[0]
        real_exchange = query._exchange

        def exchange_then_a_new_holder_starts(connection, reader, line):
            reply = real_exchange(connection, reader, line)
            first.join(timeout=30)  # the first holder has ended; another command starts the next one
            self.start_holder(self.paths)
            self.connect()
            return reply

        with unittest.mock.patch.object(query, "STOP_WAIT_S", 5.0), unittest.mock.patch.object(query, "_exchange", exchange_then_a_new_holder_starts):
            status, out, err = self.run_command("stop")
        self.assertEqual((status, err), (0, ""))
        self.assertIn("stopped", out)
        self.assertEqual(self.run_command("status")[0], 0)  # the new holder runs


class HeldClientTest(HolderTest):
    """decompiled.py and its like make thousands of requests: they use the held process as a QueryClient."""

    def held(self) -> query.HeldClient:
        self.ask({"id": 1, "kind": "who"})  # starts the holder
        client = query.open_client(self.env)
        self.addCleanup(client.close)
        return client

    def test_open_client_gives_the_held_process_when_a_holder_runs(self):
        client = self.held()
        self.assertIsInstance(client, query.HeldClient)
        self.assertEqual(client.answer("echo", text="held"), {"echo": "held"})
        self.assertEqual(client.answer("who")["answered"], 3)  # after the first ask and the echo: one process

    def test_open_client_starts_the_holder_when_none_runs_so_no_query_process_of_its_own_opens(self):
        client = query.open_client(self.env, start=self.start_holder)
        self.addCleanup(client.close)
        self.assertIsInstance(client, query.HeldClient)
        self.assertEqual(client.answer("who")["answered"], 1)
        self.assertEqual(self.ask({"id": 2, "kind": "who"})["answer"]["answered"], 2)  # another shell reaches the same process
        self.assertEqual((len(self.holders), len(self.query_processes)), (1, 1))

    def test_an_error_reply_raises_query_failed_with_its_text_and_the_client_goes_on(self):
        client = self.held()
        with self.assertRaisesRegex(QueryFailed, "planted refusal"):
            client.answer("refuse")
        self.assertEqual(client.answer("echo", text="again"), {"echo": "again"})

    def test_a_query_process_that_ends_raises_process_ended_with_its_stderr(self):
        client = self.held()
        with self.assertRaisesRegex(QueryProcessEnded, "planted: the process stopped"):
            client.answer("die")

    def test_a_request_with_no_reply_in_time_raises_a_timeout_as_the_query_client_does(self):
        self.start_holder(self.paths, timeout_s=0.5)
        client = query.HeldClient(self.connect())
        self.addCleanup(client.close)
        with self.assertRaises(QueryTimeout):
            client.answer("hang")

    def test_a_connection_left_open_across_a_stop_is_told_the_holder_is_stopping(self):
        client = self.held()
        status, _out, err = self.run_command("stop")
        self.assertEqual((status, err), (0, ""))
        with self.assertRaisesRegex(QueryProcessEnded, "stopping"):
            client.answer("who")


class HeldClientAgainstAHolderThatMisbehavesTest(unittest.TestCase):
    """The holder's end of the socket is played by the test."""

    def pair(self) -> "tuple[query.HeldClient, socket.socket]":
        near, far = socket.socketpair()
        client = query.HeldClient(near)
        self.addCleanup(client.close)
        self.addCleanup(far.close)
        return client, far

    def reply_once(self, far: socket.socket, body: dict) -> None:
        def run():
            with far.makefile("rb") as reader:
                reader.readline()
            far.sendall(json.dumps(body).encode() + b"\n")

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 30)

    def test_a_connection_the_holder_closed_raises_process_ended_never_an_os_error(self):
        client, far = self.pair()
        far.close()
        for _ in range(2):  # the first send may be taken by the kernel; the second meets the closed peer
            with self.assertRaises(QueryProcessEnded):
                client.answer("who")

    def test_a_reply_for_another_request_raises_process_ended(self):
        client, far = self.pair()
        self.reply_once(far, {"id": 99, "ok": True, "answer": "not yours"})
        with self.assertRaisesRegex(QueryProcessEnded, "not for"):
            client.answer("who")

    def test_the_holders_timeout_reply_raises_a_timeout(self):
        client, far = self.pair()
        self.reply_once(far, {"holder_timeout": "no reply within 5 s"})
        with self.assertRaisesRegex(QueryTimeout, "no reply within 5 s"):
            client.answer("who")


class NameFunctionsTest(HolderTest):
    """name_functions needs the project, which a held query process has open."""

    def test_it_refuses_while_a_query_process_holds_the_project_and_says_how_to_stop_it(self):
        self.ask({"id": 1, "kind": "who"})
        with self.assertRaises(SystemExit) as raised:
            name_functions.main(self.env)
        message = str(raised.exception)
        self.assertIn("pid %d" % os.getpid(), message)
        self.assertIn("query.py stop", message)

    def test_it_goes_on_when_no_query_process_holds_the_project(self):
        out = io.StringIO()
        with unittest.mock.patch.object(name_functions, "name_and_save", return_value=[]), unittest.mock.patch("sys.stdout", out):
            self.assertEqual(name_functions.main(self.env), 0)
        self.assertIn("would name 0", out.getvalue())


class RecoverSwitchesTest(HolderTest):
    """recover_switches opens the project itself, which a held query process has open."""

    def test_it_refuses_while_a_query_process_holds_the_project_and_says_how_to_stop_it_with_and_without_write(self):
        self.ask({"id": 1, "kind": "who"})
        for write in (False, True):
            with self.subTest(write=write):
                env = dict(self.env, GENESIS_DECOMPILED_DIR=str(self.home / "decompiled"))
                with self.assertRaisesRegex(ghidra_project.ProjectHeld, "pid %d.*query.py stop" % os.getpid()):
                    recover_switches.run(env, write)
        self.assertFalse((self.home / "decompiled").exists())


class SpawnedHolderTest(HolderTest):
    """The command's own start of the holder, as a process of its own: a holder that cannot open the
    query process ends, the command reports why from the log, and no lock is left."""

    def test_a_holder_that_cannot_open_the_query_process_is_reported_from_its_log_and_leaves_no_lock(self):
        (self.home / "project").mkdir()  # the query process runs in the project's folder
        env = dict(self.env, GENESIS_PYGHIDRA_PYTHON=str(self.home / "no-such-python"))
        out, err = io.StringIO(), io.StringIO()
        status = query.main(["ask", '{"id": 1, "kind": "functions"}'], env, out, err)  # the default start
        self.assertEqual((status, out.getvalue()), (1, ""))
        self.assertIn("no-such-python", err.getvalue())
        self.assertIn(str(self.paths.log), err.getvalue())
        self.assertIn("no-such-python", self.paths.log.read_text())
        self.assertFalse(self.paths.lock.exists())
        self.assertFalse(self.paths.socket.exists())


class SettingsTest(HolderTest):
    def test_a_missing_setting_is_named_and_no_process_starts(self):
        env = dict(self.env)
        del env["GENESIS_GHIDRA_DIR"]
        status, out, err = self.run_command("ask", '{"kind": "functions"}', env=env)
        self.assertEqual((status, out), (1, ""))
        self.assertIn("GENESIS_GHIDRA_DIR", err)
        self.assertEqual(self.holders, [])

    def test_a_python_for_the_query_process_that_is_not_set_is_named_and_no_process_starts(self):
        env = dict(self.env)
        del env["GENESIS_PYGHIDRA_PYTHON"]
        status, _out, err = self.run_command("ask", '{"kind": "functions"}', env=env)
        self.assertEqual(status, 1)
        self.assertIn("GENESIS_PYGHIDRA_PYTHON", err)
        self.assertEqual(self.holders, [])

    def test_the_home_is_genesis_home_or_dot_genesis_prime_under_home(self):
        self.assertEqual(query.paths_for({**self.env, "GENESIS_HOME": "/x/y"}).lock.parent, Path("/x/y"))
        without_home = {k: v for k, v in self.env.items() if k != "GENESIS_HOME"}
        self.assertEqual(query.paths_for({**without_home, "HOME": "/h"}).lock.parent, Path("/h/.genesis-prime"))


@cs.integration_only
class RealQueryProcessTest(unittest.TestCase):
    """Items 1, 2, 4 and 5 on the real query process and the real project, with the command run as
    separate shells (processes) would run it."""

    @classmethod
    def setUpClass(cls):
        cls.home = Path(tempfile.mkdtemp(prefix="gq-", dir="/tmp"))
        cls.addClassCleanup(shutil.rmtree, cls.home)
        cls.env = cs.query_environment(cs.seeded_project().project_dir)
        cls.env["GENESIS_HOME"] = str(cls.home)
        cls.addClassCleanup(cls.stop)

    @classmethod
    def stop(cls):
        shell(cls.env, "stop")  # the project is shared: no other class opens it while this one holds it

    def test_two_shells_share_one_real_process_a_file_answers_in_order_and_stop_ends_it(self):
        first = shell(self.env, "ask", '{"id": 1, "kind": "function_at", "address": "0x%x"}' % cs.FN_CONTROL_SWITCH)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(json.loads(first.stdout)["answer"]["start"], "0x%x" % cs.FN_CONTROL_SWITCH)
        running = shell(self.env, "status")
        self.assertEqual(running.returncode, 0, running.stdout)
        # a second shell: the same process answers, at the cost of one request
        requests = self.home / "requests.jsonl"
        requests.write_text(
            '{"id": 7, "kind": "seed_report"}\n'
            'not json\n'
            '{"id": 9, "kind": "bytes", "address": "0x%x", "length": 2}\n' % cs.FN_CONTROL_SWITCH
        )
        second = shell(self.env, "ask", "--file", str(requests))
        replies = [json.loads(line) for line in second.stdout.splitlines()]
        self.assertEqual([r["id"] for r in replies], [7, None, 9])
        self.assertEqual([r["ok"] for r in replies], [True, False, True])  # the bad line did not stop the process
        self.assertEqual(second.returncode, 1)  # one error reply
        self.assertEqual(replies[0]["answer"], None)  # seed_report: null when the open ran no analysis (the first start did)
        # a decompile that fails is the query process's own error reply, the status is 1, and the process goes on
        # (the 2,322-case switch function cannot be decompiled in a millisecond, as test_decompiled relies on)
        failed = shell(self.env, "ask", '{"id": 11, "kind": "decompile", "function": "0x%x", "timeout_s": 0.001}' % cs.FN_BIG_SWITCH)
        self.assertEqual(failed.returncode, 1, failed.stderr)
        reply = json.loads(failed.stdout)
        self.assertEqual((reply["id"], reply["ok"]), (11, False))
        self.assertIn("timeout", reply["error"])
        again = shell(self.env, "ask", '{"id": 12, "kind": "seed_report"}')
        self.assertEqual((again.returncode, json.loads(again.stdout)["id"]), (0, 12))
        stopped = shell(self.env, "stop")
        self.assertEqual(stopped.returncode, 0, stopped.stderr)
        self.assertEqual(shell(self.env, "status").returncode, 1)


def shell(env: dict, *argv: str) -> subprocess.CompletedProcess:
    """One run of the command in a process of its own, as a decoder's shell runs it."""
    return subprocess.run(
        [sys.executable, "-I", str(cs.SCRIPTS / "query.py"), *argv],
        env=env,
        capture_output=True,
        text=True,
        timeout=900,
    )


if __name__ == "__main__":
    unittest.main(verbosity=2)

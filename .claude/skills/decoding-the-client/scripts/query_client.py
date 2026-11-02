"""A client of the query process (ghidra_query.py): starts it, asks it, stops it.

One JSON request per line in, one JSON reply per line out, as ghidra_query.py documents. A
reader thread feeds the replies to a queue, so a reply that does not come in time raises
instead of hanging the caller. check_support.QueryProcess adds the test measurements to it.
"""

import json
import os
import queue
import subprocess
import tempfile
import threading
import time
from pathlib import Path

import ghidra_env

DEFAULT_TIMEOUT_S = 120
SCRIPTS = Path(__file__).resolve().parent


class QueryFailed(Exception):
    """The process answered a request with an error reply; the message is its error text."""


class QueryProcessEnded(Exception):
    """The process closed its output, or its reply broke the protocol; the message says which, and
    what it wrote to stderr."""


class QueryTimeout(Exception):
    """No reply came within the time given."""


class NotConfigured(Exception):
    """GENESIS_PYGHIDRA_PYTHON is not set."""


def query_command(seed: Path | None = None, unseeded: bool = False) -> list[str]:
    """The pinned Python running ghidra_query.py. No -I: the script puts its own directory on
    sys.path to import its siblings. `--seed PATH` is used only when the project does not exist
    yet; `--unseeded` is the explicit first import without a seed, which the process refuses to
    make unasked; with neither it opens the project that exists."""
    python = os.environ.get("GENESIS_PYGHIDRA_PYTHON")
    if not python:
        raise NotConfigured("GENESIS_PYGHIDRA_PYTHON is not set; source ~/.genesis-prime/env.sh")
    command = [python, str(SCRIPTS / "ghidra_query.py")]
    if unseeded:
        command += ["--unseeded"]
    elif seed is not None:
        command += ["--seed", str(seed)]
    return command


def open_query_client(env) -> "QueryClient":
    """The query process on the project the environment names (ghidra_env reads it). Raises
    ghidra_env.WrongVersion for a variable that is not set and NotConfigured without
    GENESIS_PYGHIDRA_PYTHON; the process itself refuses a missing project and says so on stderr."""
    settings = ghidra_env.settings_from_env(env)
    return QueryClient(query_command(), dict(env), cwd=settings.project_dir)


class QueryClient:
    """The query process as a subprocess, one JSON line per request and reply."""

    def __init__(self, command: list[str], env: dict, cwd: Path | None = None):
        self.stderr_file = tempfile.TemporaryFile()
        self.proc = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.stderr_file,
            env=env,
            cwd=cwd,
        )
        self.lines: queue.Queue = queue.Queue()
        self.last_exchange_seconds = 0.0  # write to read, of the latest exchange
        self._next_id = 0
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def stderr_text(self) -> str:
        self.stderr_file.seek(0)
        return self.stderr_file.read().decode(errors="replace")

    def exchange(self, raw: bytes, timeout: float = DEFAULT_TIMEOUT_S) -> dict:
        """One raw line (a newline is added) and the next reply line, parsed."""
        started = time.perf_counter()
        try:
            self.proc.stdin.write(raw + b"\n")
            self.proc.stdin.flush()
        except BrokenPipeError:
            pass  # the process has ended; the closed output below says so
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            raise QueryTimeout("no reply within %s s; stderr:\n%s" % (timeout, self.stderr_text())) from None
        if line is None:
            raise QueryProcessEnded("the query process closed stdout; stderr:\n%s" % self.stderr_text())
        self.last_exchange_seconds = time.perf_counter() - started
        return json.loads(line)

    def request(self, kind: str, timeout: float = DEFAULT_TIMEOUT_S, **arguments) -> dict:
        """The whole reply to a request, an error reply included."""
        self._next_id += 1
        body = self.exchange(json.dumps({"id": self._next_id, "kind": kind, **arguments}).encode(), timeout)
        if body.get("id") != self._next_id:
            raise QueryProcessEnded("reply %s is not for request %d" % (body, self._next_id))
        return body

    def answer(self, kind: str, timeout: float = DEFAULT_TIMEOUT_S, **arguments):
        """A request's answer; an error reply raises QueryFailed with its error text."""
        body = self.request(kind, timeout, **arguments)
        if body.get("ok") is not True:
            raise QueryFailed(body.get("error", "no error text in %s" % body))
        return body["answer"]

    def close(self, timeout: float = 60) -> int:
        """Closes stdin and waits for the process to end; kills it and raises after timeout."""
        if not self.proc.stdin.closed:
            self.proc.stdin.close()
        try:
            status = self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.kill()
            raise QueryTimeout("the process did not stop %s s after stdin closed" % timeout) from None
        self._release()
        return status

    def kill(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        self._release()

    def _release(self):
        """Ends the reader thread, which stops when the process's output closes, and closes the
        pipe and the stderr file. stderr_text is for a process that is still running or just ended."""
        try:
            self.proc.stdin.close()
        except BrokenPipeError:
            pass  # the process ended with input unread
        self.reader.join(timeout=5)
        if not self.reader.is_alive():
            self.proc.stdout.close()
        self.stderr_file.close()

"""The one command that sends the query process (ghidra_query.py) a request from any shell.

    python3 -I query.py ask '<one JSON request>'      the reply, one line
    python3 -I query.py ask --file requests.jsonl     one reply line per request line, in order
    python3 -I query.py status                        whether one runs, on which project, its log
    python3 -I query.py stop                          ends it

The first `ask` starts a holder: a process of its own that keeps one query process open and
listens on a Unix socket in the genesis home (~/.genesis-prime, or GENESIS_HOME), one request line
in and one reply line out, so a later `ask` from any shell costs one request's time. The holder
runs on one project (GENESIS_GHIDRA_PROJECT_DIR); a lock file beside its socket refuses a second
holder on that project, naming the running one, and a lock whose process is gone is cleared by
the next start. It ends on `stop`, or after GENESIS_QUERY_IDLE_S seconds (default 1800) with no
connection and no request, and removes its socket and lock. Its log is the file `status` names.

A reply is printed as the query process wrote it; the status is 1 when any reply is an error
reply, and the replies after one are still printed. A query process that ends or does not answer
ends the holder and the command, which says why on stderr; the next `ask` starts a new one.
The requests are those ghidra_query.py documents. The settings are the ones ghidra_env reads and
GENESIS_PYGHIDRA_PYTHON, from ~/.genesis-prime/env.sh.
"""

import argparse
import fcntl
import hashlib
import json
import logging
import math
import os
import socket
import socketserver
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ghidra_env  # noqa: E402
from query_client import (  # noqa: E402
    DEFAULT_TIMEOUT_S,
    NotConfigured,
    QueryClient,
    QueryFailed,
    QueryProcessEnded,
    QueryTimeout,
    open_query_client,
    query_command,
)

DEFAULT_IDLE_S = 1800.0
DEFAULT_START_S = 900.0  # added to the first request's time: the query process opens the project then
HOLDER_WAIT_S = 60.0  # how long a command waits for a holder it started to listen
STOP_WAIT_S = 120.0  # the holder closes the query process for up to 60 s before it ends
LOG_LINES_SHOWN = 8

logger = logging.getLogger("query")


class BadSetting(Exception):
    """GENESIS_QUERY_IDLE_S is not a number above 0; the message names it."""


class BadLock(Exception):
    """A lock file that is not a record of a holder; the message names the file."""


class HolderUnavailable(Exception):
    """No holder answers on the socket, and none is starting; the message says why."""


class HolderFailure(Exception):
    """The holder reports that the query process ended or did not answer; the message says why."""


@dataclass(frozen=True)
class Paths:
    project: Path  # GENESIS_GHIDRA_PROJECT_DIR: what one holder serves
    socket: Path
    lock: Path
    guard: Path  # held while a lock is read and written, so two starts never both clear a stale one
    log: Path


@dataclass(frozen=True)
class LockRecord:
    pid: int
    project: str
    socket: str
    log: str


class AlreadyRunning(Exception):
    """A holder already runs on the project; the message names its process, project and log."""

    def __init__(self, record: LockRecord):
        super().__init__("a query process already runs on %s: pid %d, log %s" % (record.project, record.pid, record.log))
        self.pid = record.pid


def paths_for(env) -> Paths:
    """The socket, lock and log of the holder for the environment's project, named by a hash of the
    project's folder. Raises ghidra_env.WrongVersion for a setting that is not set."""
    project = ghidra_env.settings_from_env(env).project_dir
    home = ghidra_env.genesis_home(env)
    key = hashlib.sha256(str(project.resolve()).encode()).hexdigest()[:10]
    return Paths(project, home / ("query-%s.sock" % key), home / ("query-%s.lock" % key), home / ("query-%s.guard" % key), home / ("query-%s.log" % key))


def idle_seconds(env) -> float:
    """GENESIS_QUERY_IDLE_S, or the default; raises BadSetting for a value that is not above 0."""
    text = env.get("GENESIS_QUERY_IDLE_S")
    if text is None:
        return DEFAULT_IDLE_S
    try:
        seconds = float(text)
    except ValueError:
        seconds = math.nan
    if not (math.isfinite(seconds) and seconds > 0):
        raise BadSetting("GENESIS_QUERY_IDLE_S must be a number of seconds above 0, not %r" % text)
    return seconds


# ---------------------------------------------------------------- the lock

def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # the process exists, under another user
    return True


def read_lock(paths: Paths) -> LockRecord | None:
    """The record in the lock file, or None when there is no lock. Raises BadLock for a file that is not one."""
    try:
        text = paths.lock.read_text()
    except FileNotFoundError:
        return None
    try:
        body = json.loads(text)
        return LockRecord(int(body["pid"]), str(body["project"]), str(body["socket"]), str(body["log"]))
    except (ValueError, KeyError, TypeError) as error:
        raise BadLock("%s is not a record of a query holder (%s); remove it if no holder runs" % (paths.lock, error)) from error


def live_holder(paths: Paths) -> LockRecord | None:
    """The record of the holder whose process runs, or None when there is no lock or its process is gone."""
    record = read_lock(paths)
    return record if record is not None and _alive(record.pid) else None


@contextmanager
def _guarded(paths: Paths):
    paths.guard.parent.mkdir(parents=True, exist_ok=True)
    with open(paths.guard, "a") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        yield


def _remove(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def clear_stale(paths: Paths) -> LockRecord | None:
    """Removes a lock whose process is gone, with the socket it left, and returns its record; a lock
    whose process runs is left, and None is returned for no lock."""
    with _guarded(paths):
        record = read_lock(paths)
        if record is None or _alive(record.pid):
            return None
        _remove(paths.lock)
        _remove(paths.socket)
        return record


def acquire_lock(paths: Paths) -> None:
    """Writes this process's lock. Raises AlreadyRunning for a holder whose process runs; a lock whose
    process is gone, and the socket it left, are removed first."""
    paths.lock.parent.mkdir(parents=True, exist_ok=True)
    with _guarded(paths):
        record = read_lock(paths)
        if record is not None:
            if _alive(record.pid):
                raise AlreadyRunning(record)
            _remove(paths.lock)
        _remove(paths.socket)
        mine = LockRecord(os.getpid(), str(paths.project), str(paths.socket), str(paths.log))
        pending = paths.lock.with_name("%s.%d" % (paths.lock.name, os.getpid()))
        pending.write_text(json.dumps(asdict(mine)))
        try:
            os.link(pending, paths.lock)  # the lock appears whole, or not at all
        finally:
            pending.unlink()


# ---------------------------------------------------------------- the holder

class _Holder:
    """What the connections share: the query process, one request at a time, and the idle clock."""

    def __init__(self, client: QueryClient, idle_s: float, timeout_s: float, start_s: float):
        self.client = client
        self.idle_s = idle_s
        self.timeout_s = timeout_s
        self.start_s = start_s
        self.asking = threading.Lock()
        self.first_request = True
        self.connections = 0
        self.counting = threading.Lock()
        self.last_activity = time.monotonic()
        self.failure: str | None = None
        self.stopping = threading.Event()
        self.server: socketserver.BaseServer | None = None

    def touch(self, connections: int = 0) -> None:
        with self.counting:
            self.connections += connections
            self.last_activity = time.monotonic()

    def request_stop(self) -> None:
        """Ends the serving loop from any thread; the loop's owner then cleans up."""
        if not self.stopping.is_set():
            self.stopping.set()
            threading.Thread(target=self.server.shutdown, daemon=True).start()

    def time_for(self, line: bytes) -> float:
        """The time a request may take: the default, or a decompile's own timeout_s and a minute more."""
        timeout = self.timeout_s
        try:
            asked = json.loads(line).get("timeout_s")
        except (ValueError, AttributeError):
            asked = None
        if isinstance(asked, (int, float)) and not isinstance(asked, bool) and math.isfinite(asked):
            timeout = max(timeout, asked + 60)
        if self.first_request:
            timeout += self.start_s
        return timeout

    def ask(self, line: bytes) -> str:
        """The query process's reply to one request line. Raises HolderFailure, after ending the holder,
        when the process ends, breaks the protocol or does not answer in time: a reply that came late
        would answer the next request."""
        with self.asking:
            if self.failure is not None:
                raise HolderFailure(self.failure)
            try:
                body = self.client.exchange(line, self.time_for(line))
            except (QueryProcessEnded, QueryTimeout) as error:
                self.failure = str(error)
                logger.error("the query process failed: %s", error)
                self.request_stop()
                raise HolderFailure(self.failure) from error
            self.first_request = False
            return json.dumps(body)


class _Connection(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        holder: _Holder = self.server.holder
        holder.touch(+1)
        try:
            for raw in self.rfile:
                line = raw.strip()
                if not line:
                    continue
                if _is_stop(line):
                    self._reply({"holder": "stopped"})
                    logger.info("stop asked")
                    holder.request_stop()
                    return
                try:
                    reply = holder.ask(line)
                except HolderFailure as failure:
                    self._reply({"holder_error": str(failure)})
                    return
                holder.touch()
                self.wfile.write(reply.encode() + b"\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            logger.warning("a command went away before its reply")
        finally:
            holder.touch(-1)

    def _reply(self, body: dict) -> None:
        self.wfile.write(json.dumps(body).encode() + b"\n")
        self.wfile.flush()


def _is_stop(line: bytes) -> bool:
    try:
        body = json.loads(line)
    except ValueError:
        return False
    return isinstance(body, dict) and body.get("holder") == "stop"


class _Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    block_on_close = False


def _watch_idle(holder: _Holder) -> None:
    interval = min(1.0, holder.idle_s / 4)
    while not holder.stopping.wait(interval):
        if holder.connections == 0 and time.monotonic() - holder.last_activity >= holder.idle_s:
            logger.info("idle for %s s: stopping", holder.idle_s)
            holder.request_stop()


def run_holder(
    paths: Paths,
    open_client: Callable[[], QueryClient],
    idle_s: float,
    timeout_s: float = DEFAULT_TIMEOUT_S,
    start_s: float = DEFAULT_START_S,
) -> None:
    """Holds the project's lock, opens the query process with open_client and serves requests on the
    socket until a stop request or the idle time. Raises AlreadyRunning before it opens anything when
    a holder runs on the project. It removes the socket first and the lock last, so the next holder
    starts only after the query process has ended."""
    acquire_lock(paths)
    try:
        client = open_client()
    except BaseException:
        _remove(paths.lock)
        raise
    holder = _Holder(client, idle_s, timeout_s, start_s)
    server = None
    try:
        previous = os.umask(0o077)  # the socket answers the user alone
        try:
            server = _Server(str(paths.socket), _Connection)
        finally:
            os.umask(previous)
        server.holder = holder
        holder.server = server
        logger.info("serving %s on %s as pid %d", paths.project, paths.socket, os.getpid())
        threading.Thread(target=_watch_idle, args=(holder,), daemon=True).start()
        server.serve_forever(poll_interval=0.1)
    finally:
        holder.stopping.set()
        if server is not None:
            server.server_close()
        _remove(paths.socket)
        _end_query_process(client, holder.failure is not None)
        _remove(paths.lock)
        logger.info("stopped")


def _end_query_process(client: QueryClient, failed: bool) -> None:
    if failed:
        client.kill()
        return
    try:
        client.close()
    except (QueryProcessEnded, QueryTimeout) as error:
        logger.warning("the query process did not stop cleanly: %s", error)
        client.kill()


def holder_main(env) -> int:
    """The holder as its own process, started by `ask`; it logs to stderr, which the command points at the log file."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        paths = paths_for(env)
        run_holder(paths, lambda: open_query_client(env), idle_seconds(env))
    except AlreadyRunning as error:
        logger.info("%s", error)
        return 1
    except (ghidra_env.WrongVersion, NotConfigured, BadSetting, BadLock, OSError) as error:
        logger.error("the holder could not start: %s", error)
        return 1
    return 0


def spawn_holder(env, paths: Paths) -> subprocess.Popen:
    """Starts the holder as a process of its own, in its own session, so it outlives the shell."""
    paths.log.parent.mkdir(parents=True, exist_ok=True)
    with open(paths.log, "ab") as log:
        return subprocess.Popen(
            [sys.executable, "-I", os.path.abspath(__file__), "holder"],
            env=dict(env),
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            start_new_session=True,
            close_fds=True,
        )


# ---------------------------------------------------------------- the commands

def _connect(paths: Paths) -> socket.socket | None:
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        connection.connect(str(paths.socket))
    except OSError:
        connection.close()
        return None
    return connection


def _log_tail(paths: Paths) -> str:
    try:
        lines = paths.log.read_text(errors="replace").splitlines()[-LOG_LINES_SHOWN:]
    except OSError:
        return "(no log)"
    return "\n".join(lines)


def _connect_or_start(paths: Paths, start: Callable[[Paths], object] | None) -> socket.socket:
    """A connection to the holder; with `start`, a holder is started when none runs. Raises
    HolderUnavailable naming the log when none comes up."""
    connection = _connect(paths)
    if connection is not None:
        return connection
    child = None
    if live_holder(paths) is None:
        if start is None:
            raise HolderUnavailable("no query process is running")
        child = start(paths)
    deadline = time.monotonic() + HOLDER_WAIT_S
    while time.monotonic() < deadline:
        connection = _connect(paths)
        if connection is not None:
            return connection
        ended = child is not None and child.poll() is not None
        if live_holder(paths) is None and (ended or child is None and start is None):
            raise HolderUnavailable("the holder did not start; its log %s ends:\n%s" % (paths.log, _log_tail(paths)))
        time.sleep(0.05)
    raise HolderUnavailable("nothing answered at %s within %d s; its log %s ends:\n%s" % (paths.socket, HOLDER_WAIT_S, paths.log, _log_tail(paths)))


def _exchange(connection: socket.socket, reader, line: str) -> dict:
    connection.sendall(line.encode() + b"\n")
    reply = reader.readline()
    if not reply:
        raise HolderFailure("the holder ended without a reply")
    return json.loads(reply)


def ask(paths: Paths, requests: list[str], out, start: Callable[[Paths], object]) -> int:
    """Sends the requests in order and prints each reply as a line; returns 1 when any reply is an
    error reply. Raises HolderUnavailable or HolderFailure; replies already printed stay printed."""
    connection = _connect_or_start(paths, start)
    status = 0
    with connection, connection.makefile("rb") as reader:
        for line in requests:
            body = _exchange(connection, reader, line)
            if "holder_error" in body:
                raise HolderFailure(body["holder_error"])
            print(json.dumps(body), file=out, flush=True)
            if body.get("ok") is not True:
                status = 1
    return status


class HeldClient:
    """The held query process, used as a QueryClient by scripts that make many requests (decompiled.py):
    answer, close and kill, over the holder's socket. The holder decides how long a request may take,
    so the timeout argument of answer is not used."""

    def __init__(self, connection: socket.socket):
        self.connection = connection
        self.reader = connection.makefile("rb")
        self._next_id = 0

    def answer(self, kind: str, timeout: float = DEFAULT_TIMEOUT_S, **arguments):
        """A request's answer. An error reply raises QueryFailed with its text; a holder whose query
        process ended or did not answer raises QueryProcessEnded with the holder's message."""
        self._next_id += 1
        try:
            body = _exchange(self.connection, self.reader, json.dumps({"id": self._next_id, "kind": kind, **arguments}))
        except HolderFailure as failure:
            raise QueryProcessEnded(str(failure)) from failure
        if "holder_error" in body:
            raise QueryProcessEnded(body["holder_error"])
        if body.get("ok") is not True:
            raise QueryFailed(body.get("error", "no error text in %s" % body))
        return body["answer"]

    def close(self) -> None:
        self.reader.close()
        self.connection.close()

    kill = close  # the holder owns the query process; a caller that gives up only leaves it


def open_client(env) -> "HeldClient | QueryClient":
    """The held query process when a holder runs on the project, else a query process of the caller's own."""
    connection = _connect(paths_for(env))
    return HeldClient(connection) if connection is not None else open_query_client(env)


def stop(paths: Paths, out) -> int:
    """Ends the holder and waits until its lock is gone, which is after its query process has ended."""
    record = live_holder(paths)
    if record is None:
        clear_stale(paths)
        print("no query process is running", file=out)
        return 0
    connection = _connect_or_start(paths, None)
    with connection, connection.makefile("rb") as reader:
        _exchange(connection, reader, json.dumps({"holder": "stop"}))
    deadline = time.monotonic() + STOP_WAIT_S
    while paths.lock.exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    if paths.lock.exists():
        raise HolderUnavailable("pid %d was asked to stop and still holds %s" % (record.pid, paths.lock))
    print("stopped: pid %d, project %s" % (record.pid, record.project), file=out)
    return 0


def status(paths: Paths, out) -> int:
    record = read_lock(paths)
    if record is not None and _alive(record.pid):
        print("running: pid %d on project %s; log %s" % (record.pid, record.project, record.log), file=out)
        return 0
    if record is not None:
        print("not running (the lock of pid %d, which is gone, is cleared by the next start)" % record.pid, file=out)
    else:
        print("not running", file=out)
    return 1


def _requests_of(arguments) -> list[str]:
    """The request lines: the given request as one line, or the file's non-blank lines."""
    if arguments.file is None:
        try:
            return [json.dumps(json.loads(arguments.request))]  # a request written over several lines is one
        except ValueError:
            return [" ".join(arguments.request.split())]  # not JSON: the query process answers with its error reply
    return [line.strip() for line in Path(arguments.file).read_text().splitlines() if line.strip()]


def main(argv: list[str], env, out=None, err=None, start: Callable[[Paths], object] | None = None) -> int:
    """Runs a command and returns its exit status. `start(paths)` starts a holder; by default a process
    of its own, and it may return an object with poll() that tells when the holder ended."""
    out, err = out or sys.stdout, err or sys.stderr
    parser = argparse.ArgumentParser(description="Sends the client query process requests from any shell.")
    commands = parser.add_subparsers(dest="command", required=True)
    ask_parser = commands.add_parser("ask", help="send one request, or a file of requests")
    which = ask_parser.add_mutually_exclusive_group(required=True)
    which.add_argument("request", nargs="?", help="one JSON request")
    which.add_argument("--file", help="a file of JSON requests, one per line")
    commands.add_parser("status", help="whether a query process runs, on which project, and its log")
    commands.add_parser("stop", help="end the query process")
    commands.add_parser("holder")  # started by `ask`
    arguments = parser.parse_args(argv)
    if arguments.command == "holder":
        return holder_main(env)
    try:
        paths = paths_for(env)
        if arguments.command == "status":
            return status(paths, out)
        if arguments.command == "stop":
            return stop(paths, out)
        requests = _requests_of(arguments)
        query_command(env=env)  # a missing GENESIS_PYGHIDRA_PYTHON, named before a holder is started
        idle_seconds(env)
        return ask(paths, requests, out, start or (lambda paths: spawn_holder(env, paths)))
    except (ghidra_env.WrongVersion, NotConfigured, BadSetting, BadLock, HolderUnavailable, HolderFailure) as error:
        print("query: %s" % error, file=err)
        return 1
    except OSError as error:
        print("query: %s" % error, file=err)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ))

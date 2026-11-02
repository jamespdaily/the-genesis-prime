"""The one command that sends the query process (ghidra_query.py) a request from any shell.

    python3 -I query.py ask '<one JSON request>'      the reply, one line
    python3 -I query.py ask --file requests.jsonl     one reply line per request line, in order
    python3 -I query.py status                        whether one runs, on which project, its log
    python3 -I query.py stop                          ends it

The first `ask` starts a holder: a process of its own that keeps one query process open and
listens on a Unix socket in the genesis home (~/.genesis-prime, or GENESIS_HOME), one request line
in and one reply line out, so a later `ask` from any shell costs one request's time. The holder
runs on one project (GENESIS_GHIDRA_PROJECT_DIR) and holds an flock on a lock file beside its
socket for its whole life, with a record of itself in the file. A second holder on that project is
refused, naming the running one; the kernel frees the lock when the holder dies however it dies,
and the next start clears what it left, ending a query process the dead holder had not. It ends on
`stop`, or after GENESIS_QUERY_IDLE_S seconds (default 1800) with no connection and no request,
and removes its socket and lock. Scripts that make many requests (decompiled.py) reach the same
holder through open_client, so every opener of the project goes through the one lock. Its log is
the file `status` names.

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
import signal
import socketserver
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import BinaryIO

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ghidra_env  # noqa: E402
import ghidra_query  # noqa: E402
from query_client import (  # noqa: E402
    DEFAULT_TIMEOUT_S,
    NotConfigured,
    QueryClient,
    QueryProcessEnded,
    QueryTimeout,
    answer_of,
    check_reply_id,
    open_query_client,
    query_command,
)

DEFAULT_IDLE_S = 1800.0
DEFAULT_START_S = 900.0  # added to the first request's time: the query process opens the project then
HOLDER_WAIT_S = 60.0  # how long a command waits for a holder it started to listen
STOP_WAIT_S = 120.0  # the holder closes the query process for up to 60 s before it ends
LOCK_TRIES = 5  # a start that finds the lock held tries again briefly: a command probing it holds it for an instant
LOCK_RETRY_S = 0.02
RECORD_WAIT_S = 2.0  # a holder that has taken the lock writes its record a moment later
ORPHAN_WAIT_S = 10.0  # how long a start waits for the query process of a dead holder to end
LOG_LINES_SHOWN = 8

logger = logging.getLogger("query")


class BadSetting(Exception):
    """GENESIS_QUERY_IDLE_S is not a number above 0; the message names it."""


class BadLock(Exception):
    """A lock file that is not a record of a holder; the message names the file."""


class HolderUnavailable(Exception):
    """No holder answers on the socket, and none is starting; the message says why."""


class HolderFailure(Exception):
    """The holder reports that it cannot serve a request: the query process ended, broke the protocol
    or did not answer in time (`timed_out`), or the holder is stopping; the message says why."""

    def __init__(self, message: str, timed_out: bool = False):
        super().__init__(message)
        self.timed_out = timed_out


@dataclass(frozen=True)
class Paths:
    project: Path  # GENESIS_GHIDRA_PROJECT_DIR: what one holder serves
    socket: Path
    lock: Path
    log: Path


@dataclass(frozen=True)
class LockRecord:
    pid: int
    project: str
    socket: str
    log: str
    query_pid: int | None = None  # the holder's query process, so a start can end one a killed holder left
    query_started: str = ""  # when it started, so a pid the system reused is not taken for it


class AlreadyRunning(Exception):
    """A holder already runs on the project; the message names its process, project and log."""

    def __init__(self, record: LockRecord):
        super().__init__("a query process already runs on %s: pid %d, log %s" % (record.project, record.pid, record.log))
        self.pid = record.pid
        self.record = record


def paths_for(env) -> Paths:
    """The socket, lock and log of the holder for the environment's project, named by a hash of the
    project's folder. Raises ghidra_env.WrongVersion for a setting that is not set."""
    project = ghidra_env.settings_from_env(env).project_dir
    home = ghidra_env.genesis_home(env)
    key = hashlib.sha256(str(project.resolve()).encode()).hexdigest()[:10]
    return Paths(project, home / ("query-%s.sock" % key), home / ("query-%s.lock" % key), home / ("query-%s.log" % key))


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

def started_at(pid: int) -> str:
    """When the process started, as ps prints it with its padding squeezed out; empty when no process
    has the pid, or it has ended and is not yet reaped. Two processes that held one pid at different
    times differ here."""
    fields = subprocess.run(["ps", "-o", "stat=,lstart=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
    if not fields or fields[0].startswith("Z"):
        return ""
    return " ".join(fields[1:])


def _parse_record(text: str) -> LockRecord:
    body = json.loads(text)
    query_pid = body.get("query_pid")
    return LockRecord(
        int(body["pid"]),
        str(body["project"]),
        str(body["socket"]),
        str(body["log"]),
        None if query_pid is None else int(query_pid),
        str(body.get("query_started", "")),
    )


def read_lock(paths: Paths) -> LockRecord | None:
    """The record in the lock file, or None when there is no file or it holds nothing yet. Raises
    BadLock for a file that holds something else."""
    try:
        text = paths.lock.read_text()
    except FileNotFoundError:
        return None
    if not text:
        return None
    try:
        return _parse_record(text)
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise BadLock("%s is not a record of a query holder (%s); remove it if no holder runs" % (paths.lock, error)) from error


def _is_held(file: BinaryIO) -> bool:
    """Whether a holder holds the lock file's flock. Takes it for an instant when it is free."""
    try:
        fcntl.flock(file, fcntl.LOCK_SH | fcntl.LOCK_NB)
    except BlockingIOError:
        return True
    fcntl.flock(file, fcntl.LOCK_UN)
    return False


def _record_of_holder(paths: Paths) -> LockRecord | None:
    """The record of the holder that holds the lock, which may not have written it yet; None when the
    file is gone, because the holder ended. Raises BadLock when the file holds no record after a moment."""
    deadline = time.monotonic() + RECORD_WAIT_S
    while True:
        record = read_lock(paths)
        if record is not None or not paths.lock.exists():
            return record
        if time.monotonic() >= deadline:
            raise BadLock("%s is held but holds no record of a query holder" % paths.lock)
        time.sleep(0.02)


def live_holder(paths: Paths) -> LockRecord | None:
    """The record of the holder that holds the project's lock, or None when none does."""
    try:
        file = open(paths.lock, "rb")
    except FileNotFoundError:
        return None
    with file:
        if not _is_held(file):
            return None
    return _record_of_holder(paths)


def _end_orphan(record: LockRecord | None) -> None:
    """Ends the query process a holder left when it was killed, if it still runs. A process that only
    has the recorded pid, started at another time, is left alone."""
    if record is None or record.query_pid is None or not record.query_started:
        return
    if started_at(record.query_pid) != record.query_started:
        return
    logger.warning("ending query process %d, left by the holder pid %d", record.query_pid, record.pid)
    try:
        os.kill(record.query_pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + ORPHAN_WAIT_S
    while started_at(record.query_pid) == record.query_started and time.monotonic() < deadline:
        time.sleep(0.05)


class HeldLock:
    """The project's lock file, held by this process until `release`, with this holder's record in it."""

    def __init__(self, paths: Paths, file: BinaryIO, record: LockRecord):
        self.paths = paths
        self.file = file
        self.record = record

    def _write(self, record: LockRecord) -> None:
        data = json.dumps(asdict(record)).encode()
        os.ftruncate(self.file.fileno(), 0)  # a reader that sees the file empty waits for the record
        os.pwrite(self.file.fileno(), data, 0)
        self.record = record

    def record_query_process(self, pid: int) -> None:
        """Adds the query process to the record, for a later start to end if this holder is killed."""
        self._write(replace(self.record, query_pid=pid, query_started=started_at(pid)))

    def release(self) -> None:
        """Removes the file while the lock is held, so a start that opened it earlier finds it replaced,
        then lets the lock go."""
        self.paths.lock.unlink(missing_ok=True)
        self.file.close()


def _is_the_path(file: BinaryIO, path: Path) -> bool:
    try:
        return os.path.samestat(os.fstat(file.fileno()), os.stat(path))
    except FileNotFoundError:
        return False


def acquire_lock(paths: Paths) -> HeldLock:
    """Takes the project's lock and writes this process's record in it. Raises AlreadyRunning for a
    project a holder holds. What a holder that died left is cleared first: its socket, and its query
    process when that still runs."""
    paths.lock.parent.mkdir(parents=True, exist_ok=True)
    refused = 0
    while True:
        file = os.fdopen(os.open(paths.lock, os.O_RDWR | os.O_CREAT, 0o600), "r+b")
        try:
            fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            file.close()
            refused += 1
            if refused >= LOCK_TRIES:
                record = _record_of_holder(paths)
                if record is not None:
                    raise AlreadyRunning(record) from None
                refused = 0  # the holder ended as this looked
            else:
                time.sleep(LOCK_RETRY_S)
            continue
        except BaseException:
            file.close()
            raise
        if not _is_the_path(file, paths.lock):
            file.close()  # the holder that held it removed it as this opened it
            continue
        try:
            try:
                previous = _parse_record(file.read().decode())
            except (ValueError, KeyError, TypeError, AttributeError):
                previous = None
            held = HeldLock(paths, file, LockRecord(os.getpid(), str(paths.project), str(paths.socket), str(paths.log)))
            held._write(held.record)
            _end_orphan(previous)
            paths.socket.unlink(missing_ok=True)
        except BaseException:
            file.close()
            raise
        return held


# ---------------------------------------------------------------- the holder

def _request_of(line: bytes) -> object:
    """The request line parsed, or None when it is not JSON (the query process answers that with its error reply)."""
    try:
        return json.loads(line)
    except ValueError:
        return None


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
        self.counting = threading.RLock()  # guards connections, last_activity and the decision to stop
        self.last_activity = time.monotonic()
        self.failure: HolderFailure | None = None
        self.stopping = threading.Event()
        self.server: socketserver.BaseServer | None = None

    def admit(self) -> bool:
        """Counts a new connection; False when the holder is stopping, which serves no more."""
        with self.counting:
            if self.stopping.is_set():
                return False
            self.connections += 1
            self.last_activity = time.monotonic()
            return True

    def leave(self) -> None:
        with self.counting:
            self.connections -= 1
            self.last_activity = time.monotonic()

    def touch(self) -> None:
        with self.counting:
            self.last_activity = time.monotonic()

    def request_stop(self) -> None:
        """Ends the serving loop from any thread; the loop's owner then cleans up."""
        with self.counting:
            if self.stopping.is_set():
                return
            self.stopping.set()
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def stop_if_idle(self) -> bool:
        """Stops when no connection is open and none has done anything for the idle time. The check and
        the stop are one step, so a connection admitted a moment before is never served by a holder that
        is already stopping."""
        with self.counting:
            idle = self.connections == 0 and time.monotonic() - self.last_activity >= self.idle_s
            if idle and not self.stopping.is_set():
                self.request_stop()
                return True
            return False

    def time_for(self, request: object) -> float:
        """The time a request may take: the default, or a decompile's own timeout_s up to the most the
        query process accepts, and a minute more."""
        timeout = self.timeout_s
        asked = request.get("timeout_s") if isinstance(request, dict) else None
        if isinstance(asked, (int, float)) and not isinstance(asked, bool) and math.isfinite(asked):
            timeout = max(timeout, min(asked, ghidra_query.MAX_DECOMPILE_TIMEOUT_S) + 60)
        if self.first_request:
            timeout += self.start_s
        return timeout

    def ask(self, line: bytes) -> str:
        """The query process's reply to one request line. Raises HolderFailure when the holder is
        stopping, and, after ending the holder, when anything goes wrong between the write and the read:
        a reply that came late, or that answers another request, would answer the next one."""
        with self.asking:
            if self.stopping.is_set():
                if self.failure is None:
                    raise HolderFailure("the holder is stopping")
                raise HolderFailure(str(self.failure), self.failure.timed_out)
            request = _request_of(line)
            try:
                body = self.client.exchange(line, self.time_for(request))
                check_reply_id(request, body)
            except BaseException as error:
                expected = isinstance(error, (QueryProcessEnded, QueryTimeout))
                text = str(error) if expected else "the holder failed on a request: %r" % (error,)
                self.failure = HolderFailure(text, timed_out=isinstance(error, QueryTimeout))
                logger.error("the query process failed: %s", text, exc_info=not expected)
                self.request_stop()
                raise HolderFailure(text, self.failure.timed_out) from error
            self.first_request = False
            return json.dumps(body)


class _Connection(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        holder: _Holder = self.server.holder
        if not holder.admit():
            self._reply_ignoring_a_closed_peer({"holder_error": "the holder is stopping"})
            return
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
                    self._reply({"holder_timeout" if failure.timed_out else "holder_error": str(failure)})
                    return
                holder.touch()
                self.wfile.write(reply.encode() + b"\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            logger.warning("a command went away before its reply")
        finally:
            holder.leave()

    def _reply(self, body: dict) -> None:
        self.wfile.write(json.dumps(body).encode() + b"\n")
        self.wfile.flush()

    def _reply_ignoring_a_closed_peer(self, body: dict) -> None:
        try:
            self._reply(body)
        except (BrokenPipeError, ConnectionResetError):
            logger.warning("a command went away before its reply")


def _is_stop(line: bytes) -> bool:
    body = _request_of(line)
    return isinstance(body, dict) and body.get("holder") == "stop"


class _Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    block_on_close = False


def _watch_idle(holder: _Holder) -> None:
    interval = min(1.0, holder.idle_s / 4)
    while not holder.stopping.wait(interval):
        if holder.stop_if_idle():
            logger.info("idle for %s s: stopping", holder.idle_s)


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
    lock = acquire_lock(paths)
    try:
        client = open_client()
        lock.record_query_process(client.proc.pid)
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
            paths.socket.unlink(missing_ok=True)
            _end_query_process(client, holder.failure is not None)
            logger.info("stopped")
    finally:
        lock.release()


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
    """A connection to the holder. With `start`, a holder is started once when none holds the lock,
    including one that ends while this waits. Raises HolderUnavailable when no holder runs and none is
    to be started, or when none comes up, naming the log."""
    deadline = time.monotonic() + HOLDER_WAIT_S
    started = False
    child = None
    while True:
        connection = _connect(paths)
        if connection is not None:
            return connection
        if live_holder(paths) is None:
            if child is not None and child.poll() is not None:
                raise HolderUnavailable("the holder did not start; its log %s ends:\n%s" % (paths.log, _log_tail(paths)))
            if not started:
                if start is None:
                    raise HolderUnavailable("no query process is running")
                child = start(paths)
                started = True
        if time.monotonic() >= deadline:
            raise HolderUnavailable("nothing answered at %s within %d s; its log %s ends:\n%s" % (paths.socket, HOLDER_WAIT_S, paths.log, _log_tail(paths)))
        time.sleep(0.05)


def _open_connection(env, paths: Paths, start: Callable[[Paths], object]) -> socket.socket:
    """A connection to the holder, started if need be, after the settings it needs are checked."""
    query_command(env=env)  # a missing GENESIS_PYGHIDRA_PYTHON, named before a holder is started
    idle_seconds(env)
    return _connect_or_start(paths, start)


def _exchange(connection: socket.socket, reader, line: str) -> dict:
    """One request line to the holder and its reply. Raises HolderFailure when the connection fails,
    ends without a reply, or the reply is not an object."""
    try:
        connection.sendall(line.encode() + b"\n")
        reply = reader.readline()
    except OSError as error:
        raise HolderFailure("the connection to the holder failed: %s" % error) from error
    if not reply:
        raise HolderFailure("the holder ended without a reply")
    try:
        body = json.loads(reply)
    except ValueError:
        body = None
    if not isinstance(body, dict):
        raise HolderFailure("the holder's reply %r is not a JSON object" % reply[:200])
    return body


def _raise_if_holder_failed(body: dict) -> None:
    if "holder_timeout" in body:
        raise HolderFailure(body["holder_timeout"], timed_out=True)
    if "holder_error" in body:
        raise HolderFailure(body["holder_error"])


def ask(connection: socket.socket, requests: list[str], out) -> int:
    """Sends the requests in order and prints each reply as a line; returns 1 when any reply is an
    error reply. Raises HolderFailure; replies already printed stay printed."""
    status = 0
    with connection, connection.makefile("rb") as reader:
        for line in requests:
            body = _exchange(connection, reader, line)
            _raise_if_holder_failed(body)
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
        """A request's answer. An error reply raises QueryFailed with its text; a holder that reports
        no reply in time raises QueryTimeout, and any other failure of the holder or its query process
        raises QueryProcessEnded, both with the holder's message."""
        self._next_id += 1
        request = {"id": self._next_id, "kind": kind, **arguments}
        try:
            body = _exchange(self.connection, self.reader, json.dumps(request))
            _raise_if_holder_failed(body)
        except HolderFailure as failure:
            raise (QueryTimeout if failure.timed_out else QueryProcessEnded)(str(failure)) from failure
        check_reply_id(request, body)
        return answer_of(body)

    def close(self) -> None:
        self.reader.close()
        self.connection.close()

    kill = close  # the holder owns the query process; a caller that gives up only leaves it


def open_client(env, start: Callable[[Paths], object] | None = None) -> HeldClient:
    """The held query process on the environment's project, its holder started when none runs, so
    every opener of the project goes through the holder's lock. `start` is how a holder is started;
    by default a process of its own."""
    paths = paths_for(env)
    return HeldClient(_open_connection(env, paths, start or (lambda paths: spawn_holder(env, paths))))


def stop(paths: Paths, out) -> int:
    """Ends the holder and waits until its lock is released, which is after its query process has
    ended. With no holder, clears what a dead one left."""
    try:
        lock = acquire_lock(paths)
    except AlreadyRunning as running:
        record = running.record
    else:
        lock.release()
        print("no query process is running", file=out)
        return 0
    try:
        probe = open(paths.lock, "rb")  # the lock of this holder, whichever holder takes the path after it
    except FileNotFoundError:
        probe = None
    if probe is not None:
        with probe:
            _ask_to_stop(paths, probe)
            deadline = time.monotonic() + STOP_WAIT_S
            while _is_held(probe) and time.monotonic() < deadline:
                time.sleep(0.05)
            if _is_held(probe):
                raise HolderUnavailable("pid %d was asked to stop and still holds %s" % (record.pid, paths.lock))
    print("stopped: pid %d, project %s" % (record.pid, record.project), file=out)
    return 0


def _ask_to_stop(paths: Paths, probe: BinaryIO) -> None:
    """Sends the holder the stop request. A holder that is already ending, or is gone, needs none."""
    try:
        connection = _connect_or_start(paths, None)
    except HolderUnavailable:
        if _is_held(probe):
            raise
        return
    with connection, connection.makefile("rb") as reader:
        try:
            _exchange(connection, reader, json.dumps({"holder": "stop"}))
        except HolderFailure:
            pass  # it went away as it was asked: the wait for its lock says whether it ended


def status(paths: Paths, out) -> int:
    record = live_holder(paths)
    if record is not None:
        print("running: pid %d on project %s; log %s" % (record.pid, record.project, record.log), file=out)
        return 0
    try:
        left = read_lock(paths)
    except BadLock:
        left = None
    if left is not None:
        print("not running (the last holder, pid %d, is gone; the next start clears what it left)" % left.pid, file=out)
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
        connection = _open_connection(env, paths, start or (lambda paths: spawn_holder(env, paths)))
        return ask(connection, requests, out)
    except (ghidra_env.WrongVersion, NotConfigured, BadSetting, BadLock, HolderUnavailable, HolderFailure) as error:
        print("query: %s" % error, file=err)
        return 1
    except OSError as error:
        print("query: %s" % error, file=err)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ))

"""A saved copy of every function's decompiled C, so one text search covers the whole client.

`refresh` writes one file per function, `<address>.c` (the address as 0x and lower-case hex), whose
first line is `// <address> <name> made under <hash>`, then the C the query process's `decompile`
request answers, which carries the project's saved names. A function whose decompile fails gets
`// decompile failed: <error>` as its second line. `state.json` holds the hash, every function's
name and the failures. `check` says whether the copy is current and changes nothing.

The hash is the sha256 of the sorted lines `<address> <name>` of every function the query process
lists (its `functions` and `function_at` requests), first 16 hex digits: a rename and a new or lost
function change it. It cannot see a change that is not a name or an address, such as a type edit.

A refresh with no copy decompiles every function. With a copy it decompiles the functions whose name
changed or that are new, the ones that failed last time, the ones whose file is missing, and every saved
file whose text holds a changed function's old name, its address, or the address of a place that refers
to it (a pointer's label, PTR_FUN_<pointer address>, holds neither). A file that is not redone keeps the
hash it was made under. A refresh writes `pending.json` (the names it sets out to write) before the first
file and removes it after `state.json`, which is written last: one that ends midway leaves the old state,
and the next run does the same work again, and also redoes files that hold the ended run's names.

The copy is the client's code: it lives outside the repository, in $GENESIS_DECOMPILED_DIR or
$GENESIS_HOME/decompiled (GENESIS_HOME defaults to ~/.genesis-prime), and a folder inside the
repository or in any git working tree is refused.

Usage, with ~/.genesis-prime/env.sh read. It reaches the query process through query.py's holder, which
it starts when none runs, and which stays up after it (`query.py stop` ends it):
    python3 -I decompiled.py check      about 10 seconds; exit 0 when current; 1 and the changes when
                                        stale or no copy
    python3 -I decompiled.py refresh    a whole client takes about 7 minutes, a few renames seconds;
                                        failures are listed, exit 0
"""

import argparse
import enum
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_facts  # noqa: E402
import ghidra_env  # noqa: E402
import query  # noqa: E402
from query_client import NotConfigured, QueryFailed, QueryProcessEnded, QueryTimeout  # noqa: E402

STATE_FILE = "state.json"
PENDING_FILE = "pending.json"
HASH_DIGITS = 16
DECOMPILE_TIMEOUT_S = 60
PROGRESS_EVERY = 1000

_IDENTIFIER = re.compile(r"[A-Za-z0-9_]+")
_HEX_RUN = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{6,16}(?![0-9a-fA-F])")


class Refused(Exception):
    """A request the script will not carry out; the message says why."""


class Status(enum.Enum):
    NO_COPY = "no copy"
    CURRENT = "current"
    STALE = "stale"


@dataclass(frozen=True)
class State:
    hash: str
    names: dict[int, str]
    failed: dict[int, str]  # address -> the error line of its file


@dataclass(frozen=True)
class CheckReport:
    status: Status
    hash: str  # of the project now
    functions: int  # in the project now
    renamed: list[tuple[int, str, str]]  # address, name in the copy, name now
    added: list[tuple[int, str]]  # in the project and not in the copy
    removed: list[tuple[int, str]]  # in the copy and not in the project
    failed: dict[int, str]  # functions of the copy with no C
    missing: list[int]  # functions of the project whose file is not in the copy
    unfinished: bool  # an earlier refresh ended before it finished


@dataclass(frozen=True)
class RefreshReport:
    hash: str
    decompiled: int  # functions written with C
    removed: int  # files of functions that are gone
    failed: dict[int, str]  # functions with no C, and why


def copy_directory(env) -> Path:
    """Where the copy lives; raises Refused for a folder inside this repository or any git working tree."""
    if env.get("GENESIS_DECOMPILED_DIR"):
        directory = Path(env["GENESIS_DECOMPILED_DIR"])
    else:
        directory = ghidra_env.genesis_home(env) / "decompiled"
    require_outside_work_trees(directory, "the client's code")
    return directory


def require_outside_work_trees(directory: Path, what: str) -> None:
    """Raises Refused unless directory is outside this repository and every git working tree; what names its
    contents (the client's code, the client's files) for the message."""
    repository = check_facts.REPOSITORY.resolve()
    resolved = directory.resolve()
    if resolved == repository or repository in resolved.parents:
        raise Refused("%s is inside the repository %s; %s must stay outside it" % (directory, repository, what))
    if _inside_work_tree(resolved):
        raise Refused("%s is inside a git working tree; %s must stay outside every repository" % (directory, what))


def _inside_work_tree(directory: Path) -> bool:
    """Whether git says the folder, or the nearest folder above it that exists, is in a working tree."""
    existing = directory
    while not existing.exists():
        existing = existing.parent
    done = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"], cwd=existing, capture_output=True, text=True
    )
    return done.returncode == 0 and done.stdout.strip() == "true"


def names_hash(names: dict[int, str]) -> str:
    """The hash of a table of function names: see the module's description."""
    text = "".join("0x%x %s\n" % (address, names[address]) for address in sorted(names))
    return hashlib.sha256(text.encode()).hexdigest()[:HASH_DIGITS]


def read_names(client, scope: set[int] | None) -> dict[int, str]:
    """Every function's name as the project holds it now, by address; scope limits the functions."""
    addresses = sorted(int(a, 16) for a in client.answer("functions"))
    return {
        address: client.answer("function_at", address="0x%x" % address)["name"]
        for address in addresses
        if scope is None or address in scope
    }


def load_state(directory: Path) -> State | None:
    path = directory / STATE_FILE
    if not path.is_file():
        return None
    raw = json.loads(path.read_text())
    return State(
        raw["hash"],
        {int(a, 16): n for a, n in raw["names"].items()},
        {int(a, 16): e for a, e in raw["failed"].items()},
    )


def load_pending(directory: Path) -> dict[int, str] | None:
    """The names the latest refresh set out to write, when it did not finish; else None."""
    path = directory / PENDING_FILE
    if not path.is_file():
        return None
    return {int(a, 16): n for a, n in json.loads(path.read_text())["names"].items()}


def _write(path: Path, text: str) -> None:
    """Whole or not at all: written beside the file, then moved over it."""
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text)
    os.replace(temporary, path)


def _file(directory: Path, address: int) -> Path:
    return directory / ("0x%x.c" % address)


def _saved_addresses(directory: Path) -> set[int]:
    return {int(p.stem, 16) for p in directory.glob("0x*.c") if re.fullmatch(r"0x[0-9a-f]+", p.stem)}


def _compare(old: dict[int, str], new: dict[int, str]):
    renamed = [(a, old[a], new[a]) for a in sorted(new) if a in old and old[a] != new[a]]
    added = [(a, new[a]) for a in sorted(new) if a not in old]
    removed = [(a, old[a]) for a in sorted(old) if a not in new]
    return renamed, added, removed


def check(client, directory: Path, scope: set[int] | None = None) -> CheckReport:
    """Whether the copy in directory matches the project now; changes nothing.
    Only the tests pass a scope, to keep a real-process run to a few functions."""
    names = read_names(client, scope)
    digest = names_hash(names)
    state = load_state(directory)
    if state is None:
        return CheckReport(Status.NO_COPY, digest, len(names), [], [], [], {}, [], False)
    renamed, added, removed = _compare(state.names, names)
    missing = sorted(set(names) - _saved_addresses(directory))
    unfinished = (directory / PENDING_FILE).exists()
    current = state.hash == digest and not missing and not unfinished
    status = Status.CURRENT if current else Status.STALE
    return CheckReport(status, digest, len(names), renamed, added, removed, state.failed, missing, unfinished)


def _mentioning(directory: Path, candidates: set[int], needles: set[str]) -> set[int]:
    """The candidates whose saved text holds a needle as a whole identifier or hex number, or, for
    a needle that is not an identifier, anywhere."""
    identifiers = {n for n in needles if _IDENTIFIER.fullmatch(n)}
    others = needles - identifiers
    found = set()
    for address in candidates:
        text = _file(directory, address).read_text()
        words = set(_IDENTIFIER.findall(text)) | {h.lower() for h in _HEX_RUN.findall(text)}
        if words & identifiers or any(n in text for n in others):
            found.add(address)
    return found


def _addresses_to_redo(
    client, directory: Path, state: State | None, pending: dict[int, str] | None, names: dict[int, str]
) -> tuple[set[int], set[int]]:
    """(the functions to decompile, the saved files to delete).

    A saved file is redone when it holds a needle of a changed function: its old name, its address, and
    the address of each place the project refers to it from (a pointer's label, PTR_FUN_<pointer
    address>, holds neither the name nor the function's address). A function has changed against the
    saved state and against the names an unfinished refresh set out to write, since that refresh may have
    redone files under those names before it ended."""
    saved = _saved_addresses(directory)
    if state is None:
        return set(names), saved - set(names)
    redo = (set(state.failed) & set(names)) | (set(names) - saved)
    needles: set[str] = set()
    changed: set[int] = set()
    for baseline in [state.names] + ([pending] if pending is not None else []):
        renamed, added, removed = _compare(baseline, names)
        redo |= {a for a, _old, _new in renamed} | {a for a, _name in added}
        needles |= {old for _a, old, _new in renamed} | {name for _a, name in removed}
        changed |= {a for a, _old, _new in renamed} | {a for a, _name in added} | {a for a, _name in removed}
    for address in sorted(changed):
        needles.add("%x" % address)
        needles |= {"%x" % int(ref["from"], 16) for ref in client.answer("refs_to", address="0x%x" % address)}
    if needles:
        redo |= _mentioning(directory, (saved & set(names)) - redo, needles)
    return redo, saved - set(names)


def refresh(client, directory: Path, scope: set[int] | None = None, timeout_s: float = DECOMPILE_TIMEOUT_S, progress=None) -> RefreshReport:
    """Brings the copy in directory up to the project now; see the module's description.
    A QueryProcessEnded or QueryTimeout propagates and leaves the old state and a pending file with the
    names this refresh set out to write; any other leftover *.tmp file is removed at the start.
    progress, when given, is called with (done, total) after every PROGRESS_EVERY functions.
    Only the tests pass a scope, to keep a real-process run to a few functions."""
    names = read_names(client, scope)
    digest = names_hash(names)
    directory.mkdir(parents=True, exist_ok=True)
    for leftover in directory.glob("*.tmp"):
        leftover.unlink()
    redo, gone = _addresses_to_redo(client, directory, load_state(directory), load_pending(directory), names)
    intended = {"hash": digest, "names": {"0x%x" % a: names[a] for a in sorted(names)}}
    _write(directory / PENDING_FILE, json.dumps(intended, indent=0) + "\n")
    failed: dict[int, str] = {}
    for done, address in enumerate(sorted(redo), 1):
        header = "// 0x%x %s made under %s\n" % (address, names[address], digest)
        try:
            answer = client.answer("decompile", function="0x%x" % address, timeout_s=timeout_s, timeout=timeout_s + DECOMPILE_TIMEOUT_S)
            text = answer["c"]
        except QueryFailed as error:
            failed[address] = str(error)
            text = "// decompile failed: %s\n" % error
        _write(_file(directory, address), header + text)
        if progress is not None and done % PROGRESS_EVERY == 0:
            progress(done, len(redo))
    for address in gone:
        _file(directory, address).unlink()
    state = {
        "hash": digest,
        "names": {"0x%x" % a: names[a] for a in sorted(names)},
        "failed": {"0x%x" % a: failed[a] for a in sorted(failed)},
    }
    _write(directory / STATE_FILE, json.dumps(state, indent=0) + "\n")
    (directory / PENDING_FILE).unlink()
    return RefreshReport(digest, len(redo) - len(failed), len(gone), failed)


def _report_check(report: CheckReport, directory: Path, out) -> int:
    if report.status is Status.NO_COPY:
        print("no copy in %s; run refresh" % directory, file=out)
        return 1
    if report.status is Status.CURRENT:
        print("current: %s, %d functions" % (report.hash, report.functions), file=out)
    else:
        print("stale: the project is now %s" % report.hash, file=out)
        for address, old, new in report.renamed:
            print("0x%x renamed %s -> %s" % (address, old, new), file=out)
        for address, name in report.added:
            print("0x%x new %s" % (address, name), file=out)
        for address, name in report.removed:
            print("0x%x gone %s" % (address, name), file=out)
    for address in report.missing:
        print("0x%x missing: no file in the copy" % address, file=out)
    if report.unfinished:
        print("an earlier refresh did not finish; run refresh", file=out)
    for address in sorted(report.failed):
        print("0x%x has no C: %s" % (address, report.failed[address]), file=out)
    return 0 if report.status is Status.CURRENT else 1


def _run(command: str, client, directory: Path, out) -> int:
    if command == "check":
        return _report_check(check(client, directory), directory, out)
    started = time.monotonic()
    report = refresh(client, directory, progress=lambda done, total: print("%d of %d" % (done, total), file=out, flush=True))
    print(
        "decompiled %d functions, removed %d files, %d failed, now %s, %.0f s"
        % (report.decompiled, report.removed, len(report.failed), report.hash, time.monotonic() - started),
        file=out,
    )
    for address in sorted(report.failed):
        print("failed 0x%x: %s" % (address, report.failed[address]), file=out)
    return 0


def main(argv: list[str], env, open_client, out=None, err=None) -> int:
    """Runs a command; open_client() starts the query process. Returns the exit status."""
    out, err = out or sys.stdout, err or sys.stderr
    parser = argparse.ArgumentParser(description="The saved copy of the client's decompiled C.")
    parser.add_argument("command", choices=("check", "refresh"))
    command = parser.parse_args(argv).command
    try:
        directory = copy_directory(env)
    except Refused as error:
        print("decompiled: %s" % error, file=err)
        return 1
    try:
        client = open_client()
    except (ghidra_env.WrongVersion, NotConfigured, query.BadSetting, query.BadLock, query.HolderUnavailable, OSError) as error:
        print("decompiled: %s" % error, file=err)
        return 1
    try:
        status = _run(command, client, directory, out)
    except (QueryProcessEnded, QueryTimeout) as error:
        client.kill()
        print("decompiled: the query process failed: %s" % error, file=err)
        return 1
    except QueryFailed as error:
        client.kill()
        print("decompiled: the query process refused a request: %s" % error, file=err)
        return 1
    except BaseException:
        client.kill()
        raise
    try:
        client.close()
    except (QueryProcessEnded, QueryTimeout) as error:
        print("decompiled: the query process did not stop cleanly: %s" % error, file=err)
        return 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ, lambda: query.open_client(os.environ)))

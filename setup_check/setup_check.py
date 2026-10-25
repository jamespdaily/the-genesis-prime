"""The setup check: names every part this machine is missing, with its fix.

It runs before anything else, and the full check runs it first. It checks
every part, prints each missing one with what was found and how to fix it,
then exits non-zero. It installs nothing.

Settings come from the environment; on a development machine
$GENESIS_HOME/env.sh (default ~/.genesis-prime/env.sh) sets them, and
./setup-check and the full check read it (setup_check/environment.sh).
GENESIS_NO_CLIENT=1 marks a machine without the client, such as CI: the
client, the client query process and the patched OTP are not checked there.

Usage: ./setup-check
"""

import hashlib
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping

REPOSITORY = Path(__file__).resolve().parent.parent
SCRIPTS = Path(".claude") / "skills" / "decoding-the-client" / "scripts"
sys.path.insert(0, str(REPOSITORY / SCRIPTS))

import ghidra_env  # noqa: E402

# The client's own build, client_archive.target_build: GetVersionInfo at
# 0x1406f8360 returns nBuildNumber 16042 (0x3eaa).
TARGET_BUILD = 16042
POSTGRES_MAJOR = 18  # Jim's choice on issue #13
CLOCK_TOLERANCE_SECONDS = 1.0
MARKER = "GENESIS_PATCHES"
BUILD_SCRIPT = "setup_check/build_patched_otp.sh"


@dataclass(frozen=True)
class Missing:
    part: str  # what is missing, as the reader knows it: "Postgres 18", "Gleam 1.19.2"
    found: str  # what is there instead, or "nothing"
    fix: str  # what to do, as a command or a setting where one exists


@dataclass(frozen=True)
class Machine:
    """What a check may look at, so a test can plant a machine missing a part."""

    env: Mapping[str, str]
    repository: Path
    run: Callable[[list[str]], tuple[int, str]]  # a command -> (exit code, stdout and stderr)


def tool_versions(machine: Machine) -> dict[str, str]:
    """The pinned versions in .tool-versions: tool -> version."""
    pins = {}
    for line in (machine.repository / ".tool-versions").read_text().splitlines():
        fields = line.split()
        if len(fields) >= 2 and not line.startswith("#"):
            pins[fields[0]] = fields[1]
    return pins


def _no_client(machine: Machine) -> bool:
    return machine.env.get("GENESIS_NO_CLIENT") == "1"


def _first_line(text: str) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return lines[0] if lines else "no output"


def _tool(machine: Machine, tool: str, name: str, command: list[str], pattern: str) -> list[Missing]:
    """A tool whose version command prints the first match of pattern."""
    pinned = tool_versions(machine)[tool]
    part = "%s %s" % (name, pinned)
    fix = "install %s %s, the version in .tool-versions (asdf install %s %s)" % (name, pinned, tool, pinned)
    code, output = machine.run(command)
    if code != 0:
        return [Missing(part, "nothing" if code == 127 else _first_line(output), fix)]
    found = re.search(pattern, output, re.MULTILINE)
    if not found:
        return [Missing(part, _first_line(output), fix)]
    if found.group(1) != pinned:
        return [Missing(part, "version %s" % found.group(1), fix)]
    return []


def check_gleam(machine: Machine) -> list[Missing]:
    return _tool(machine, "gleam", "Gleam", ["gleam", "--version"], r"^gleam (\S+)")


OTP_VERSION_COMMAND = (
    '{ok, V} = file:read_file(filename:join([code:root_dir(), "releases", '
    'erlang:system_info(otp_release), "OTP_VERSION"])), io:format("~s~n", [string:trim(V)]), halt().'
)


def check_erlang(machine: Machine) -> list[Missing]:
    """OTP as pinned, and on a machine with the client the patched build the
    full check runs on (GENESIS_OTP_DIR, with its patch marker)."""
    missing = _tool(machine, "erlang", "Erlang/OTP", ["erl", "-noshell", "-eval", OTP_VERSION_COMMAND], r"^(\d+(?:\.\d+)*)\s*$")
    if _no_client(machine):
        return missing
    return missing + _patched_otp(machine)


def _otp_dir(machine: Machine) -> Path:
    if machine.env.get("GENESIS_OTP_DIR"):
        return Path(machine.env["GENESIS_OTP_DIR"])
    home = machine.env.get("GENESIS_HOME") or os.path.join(machine.env.get("HOME") or os.path.expanduser("~"), ".genesis-prime")
    return Path(home) / ("otp-%s-gc-marker" % tool_versions(machine)["erlang"])


def _patched_otp(machine: Machine) -> list[Missing]:
    """The build in GENESIS_OTP_DIR, with a line in GENESIS_PATCHES, naming the
    patch and its SHA-256, for every setup_check/*.patch."""
    version = tool_versions(machine)["erlang"]
    directory = _otp_dir(machine)
    patches = sorted((machine.repository / "setup_check").glob("*.patch"))
    names = ", ".join(patch.name for patch in patches) or "no patch"
    fix = "rebuild the patched OTP with %s (builds into GENESIS_OTP_DIR=%s, applying %s)" % (BUILD_SCRIPT, directory, names)
    if not (directory / "bin" / "erl").is_file():
        return [Missing("Patched OTP %s at %s (%s)" % (version, directory, names), "nothing", fix)]
    marker = directory / MARKER
    if not marker.is_file():
        return [Missing("Patched OTP %s with %s" % (version, names), "no %s in %s" % (MARKER, directory), fix)]
    built = dict(line.split()[:2] for line in marker.read_text().splitlines() if len(line.split()) >= 2)
    missing = []
    for patch in patches:
        wanted = hashlib.sha256(patch.read_bytes()).hexdigest()
        if patch.name not in built:
            found = "no line for %s in %s" % (patch.name, marker)
        elif built[patch.name] != wanted:
            found = "built from %s with SHA-256 %s, the file in setup_check/ has %s" % (patch.name, built[patch.name], wanted)
        else:
            continue
        missing.append(Missing("Patched OTP %s with %s" % (version, patch.name), found, fix))
    return missing


def check_rebar(machine: Machine) -> list[Missing]:
    return _tool(machine, "rebar", "rebar3", ["rebar3", "version"], r"^rebar (\S+)")


def check_manifest(machine: Machine) -> list[Missing]:
    code, output = machine.run(["git", "-C", str(machine.repository), "ls-files", "--error-unmatch", "manifest.toml"])
    if code == 0:
        return []
    return [Missing("manifest.toml tracked by git", _first_line(output), "git add manifest.toml, and commit it")]


def check_postgres(machine: Machine) -> list[Missing]:
    """Reachable at PGHOST, PGPORT and PGUSER; major version 18; its clock
    within 1 second of this machine's."""
    host = machine.env.get("PGHOST") or "/tmp"
    port = machine.env.get("PGPORT") or "5433"
    user = machine.env.get("PGUSER") or "postgres"
    part = "Postgres %d" % POSTGRES_MAJOR
    query = "select current_setting('server_version_num'), extract(epoch from clock_timestamp())"
    before = time.time()
    code, output = machine.run(["psql", "-X", "-At", "-h", host, "-p", port, "-U", user, "-d", "postgres", "-c", query])
    after = time.time()
    if code != 0:
        fix = "start Postgres %d at %s:%s as %s, or set PGHOST, PGPORT and PGUSER in env.sh" % (POSTGRES_MAJOR, host, port, user)
        return [Missing(part, "nothing reachable at %s:%s as %s (%s)" % (host, port, user, _first_line(output)), fix)]
    number, _, epoch = output.strip().partition("|")
    major = int(number) // 10000
    if major != POSTGRES_MAJOR:
        fix = "run Postgres %d at %s:%s (found major version %d)" % (POSTGRES_MAJOR, host, port, major)
        return [Missing(part, "major version %d" % major, fix)]
    offset = float(epoch) - (before + after) / 2
    if abs(offset) > CLOCK_TOLERANCE_SECONDS:
        fix = "set this machine's clock, or the server's, from the network time (sudo sntp -sS time.apple.com)"
        return [Missing("%s clock within %g second of this machine's" % (part, CLOCK_TOLERANCE_SECONDS),
                        "its clock is %+.1f seconds from this machine's" % offset, fix)]
    return []


def check_client(machine: Machine) -> list[Missing]:
    """WildStar64.exe with the pinned SHA-256, and every Patch/*.index on the
    target build."""
    pin = ghidra_env.CLIENT_SHA256
    given = machine.env.get("WILDSTAR_CLIENT_EXE")
    if not given:
        return [Missing("WildStar64.exe with SHA-256 %s" % pin, "nothing",
                        "set WILDSTAR_CLIENT_EXE to the client's Client64/WildStar64.exe in env.sh")]
    exe = Path(given)
    missing = []
    if not exe.is_file():
        missing.append(Missing("WildStar64.exe with SHA-256 %s" % pin, "nothing",
                               "point WILDSTAR_CLIENT_EXE at the client's Client64/WildStar64.exe in env.sh"))
    else:
        digest = hashlib.sha256(exe.read_bytes()).hexdigest()
        if digest != pin:
            missing.append(Missing("WildStar64.exe with SHA-256 %s" % pin, "SHA-256 %s at %s" % (digest, exe),
                                   "restore the client's own WildStar64.exe, SHA-256 %s" % pin))
    return missing + _indexes(exe.parent.parent / "Patch")


def _indexes(patch_dir: Path) -> list[Missing]:
    indexes = sorted(patch_dir.glob("*.index"))
    if not indexes:
        return [Missing("the client's Patch/*.index on build %d" % TARGET_BUILD, "nothing in %s" % patch_dir,
                        "restore the client's Patch folder, next to Client64")]
    missing = []
    for index in indexes:
        build, why = _build_of_index(index.read_bytes())
        if build == TARGET_BUILD:
            continue
        if build is None:
            missing.append(Missing("Patch/%s as an archive index" % index.name, "not an archive index: %s" % why,
                                   "restore the client's own %s (a PACK container holding an AIDX block)" % index.name))
        else:
            missing.append(Missing("Patch/%s on build %d" % (index.name, TARGET_BUILD), "build %d" % build,
                                   "update the client to build %d, so every Patch/*.index carries it" % TARGET_BUILD))
    return missing


def _build_of_index(data: bytes) -> tuple[int | None, str]:
    """The build in the AIDX header of an archive index, or (None, why not),
    read as the fact file's "archive_index.header" describes: PACK header
    0x230 bytes (signature 0x5041434B, version 1, block table offset at 0x218,
    block count at 0x220, root block index at 0x228), the root block holding
    the AIDX header (signature 0x41494458, version 1, build at offset 8)."""
    u32 = lambda at: int.from_bytes(data[at : at + 4], "little")  # noqa: E731
    u64 = lambda at: int.from_bytes(data[at : at + 8], "little")  # noqa: E731
    if len(data) < 0x230:
        return None, "shorter than the 0x230-byte PACK header"
    if u32(0) != 0x5041434B or u32(4) != 1:
        return None, "no PACK signature and version 1"
    count, root = u32(0x220), u32(0x228)
    if root >= count:
        return None, "root block %d is not below the block count %d" % (root, count)
    entry = u64(0x218) + 16 * root
    offset, size = u64(entry), u64(entry + 8)
    if size < 16 or offset + 16 > len(data) or entry + 16 > len(data):
        return None, "the root block lies outside the file"
    if u32(offset) != 0x41494458 or u32(offset + 4) != 1:
        return None, "no AIDX signature and version 1"
    return u32(offset + 8), ""


QUERY_PROCESS_VARIABLES = {
    "GENESIS_GHIDRA_DIR": "$HOME/.genesis-prime/ghidra_%s_PUBLIC" % ghidra_env.GHIDRA_VERSION,
    "GENESIS_GHIDRA_PROJECT_DIR": "$HOME/genesis-prime-ghidra",
    "WILDSTAR_CLIENT_EXE": "<the client folder>/Client64/WildStar64.exe",
    "JAVA_HOME": "$(brew --prefix openjdk@%d)/libexec/openjdk.jdk/Contents/Home" % ghidra_env.JDK_MAJOR,
    "GENESIS_PYGHIDRA_PYTHON": "$HOME/.genesis-prime/pyghidra-venv/bin/python",
}

# Run by the query process's interpreter: ghidra_env's checks, except the
# client's hash, which check_client owns (the interpreter's own file stands in
# for the client, with its own hash as the pin). One line per failure; exit 1
# when there is one, exit 2 on anything unexpected.
QUERY_PROCESS_SNIPPET = """
import hashlib, sys
from pathlib import Path
try:
    scripts, ghidra_dir, project_dir, java_home = sys.argv[1:5]
    sys.path.insert(0, scripts)
    import ghidra_env
    stand_in = Path(sys.executable)
    ghidra_env.CLIENT_SHA256 = hashlib.sha256(stand_in.read_bytes()).hexdigest()
    settings = ghidra_env.Settings(Path(ghidra_dir), Path(project_dir), stand_in, Path(java_home))
    try:
        ghidra_env.check_parts(settings)
    except ghidra_env.WrongVersion as failure:
        print(failure)
        sys.exit(1)
except Exception:
    import traceback
    traceback.print_exc()
    sys.exit(2)
"""


def check_query_process(machine: Machine) -> list[Missing]:
    """The client query process's pinned parts (ghidra_env.check_parts) and
    its environment, with a project path Ghidra accepts."""
    missing = []
    for name, value in QUERY_PROCESS_VARIABLES.items():
        if not machine.env.get(name):
            missing.append(Missing("%s for the client query process" % name, "nothing",
                                   "add export %s=%s to env.sh (GENESIS_HOME/env.sh)" % (name, value)))
    if missing:
        return missing
    env = machine.env
    for folder in Path(env["GENESIS_GHIDRA_PROJECT_DIR"]).parts:
        if folder.startswith(".") and folder not in (".", ".."):
            missing.append(Missing("Ghidra project path %s" % env["GENESIS_GHIDRA_PROJECT_DIR"],
                                   "the folder %r starts with '.', which Ghidra refuses" % folder,
                                   "set GENESIS_GHIDRA_PROJECT_DIR to a path with no folder starting with '.' in env.sh"))
            break
    interpreter = env["GENESIS_PYGHIDRA_PYTHON"]
    code, output = machine.run([
        interpreter, "-I", "-c", QUERY_PROCESS_SNIPPET, str(machine.repository / SCRIPTS),
        env["GENESIS_GHIDRA_DIR"], env["GENESIS_GHIDRA_PROJECT_DIR"], env["JAVA_HOME"],
    ])
    if code == 0:
        return missing
    if code != 1:
        return missing + [Missing("GENESIS_PYGHIDRA_PYTHON %s runs the query process's checks" % interpreter,
                                  "exit %d: %s" % (code, _first_line(output)),
                                  "set GENESIS_PYGHIDRA_PYTHON in env.sh to the python of a venv with PyGhidra %s" % ghidra_env.PYGHIDRA_VERSION)]
    return missing + [_query_failure(line.strip()) for line in output.splitlines() if line.strip()]


def _query_failure(message: str) -> Missing:
    """One failure ghidra_env.check_parts raised, as a Missing."""
    if message.startswith("Ghidra"):
        part = "Ghidra %s" % ghidra_env.GHIDRA_VERSION
        fix = "unpack the official Ghidra %s release (%s) and set GENESIS_GHIDRA_DIR to it in env.sh" % (ghidra_env.GHIDRA_VERSION, ghidra_env.GHIDRA_RELEASE_ZIP)
    elif "decompiler" in message:
        part = "Ghidra %s macOS arm64 decompiler" % ghidra_env.GHIDRA_VERSION
        fix = "build the decompiler from the release's Ghidra/Features/Decompiler/src/decompile/cpp and install it as Ghidra/Features/Decompiler/os/mac_arm_64/decompile"
    elif message.startswith("JDK"):
        part = "JDK %d" % ghidra_env.JDK_MAJOR
        fix = "install JDK %d (brew install openjdk@%d) and set JAVA_HOME to it in env.sh" % (ghidra_env.JDK_MAJOR, ghidra_env.JDK_MAJOR)
    elif message.startswith("Python"):
        part = "Python %d.%d for PyGhidra" % ghidra_env.PYTHON_MINOR
        fix = "install Python %d.%d (brew install python@%d.%d) and make GENESIS_PYGHIDRA_PYTHON the python of a venv made with it" % (*ghidra_env.PYTHON_MINOR, *ghidra_env.PYTHON_MINOR)
    elif message.startswith("PyGhidra"):
        part = "PyGhidra %s" % ghidra_env.PYGHIDRA_VERSION
        fix = "install PyGhidra %s in the venv of GENESIS_PYGHIDRA_PYTHON (pip install pyghidra==%s)" % (ghidra_env.PYGHIDRA_VERSION, ghidra_env.PYGHIDRA_VERSION)
    else:
        part = "the client query process's parts"
        fix = "see the message; the pins are in %s/ghidra_env.py" % SCRIPTS
    return Missing(part, message, fix)


def check_all(machine: Machine) -> list[Missing]:
    """Every part's check, in order, skipping the client's parts where
    GENESIS_NO_CLIENT=1."""
    checks = [check_gleam, check_erlang, check_rebar, check_manifest, check_postgres]
    if not _no_client(machine):
        checks += [check_client, check_query_process]
    return [missing for check in checks for missing in check(machine)]


def real_machine() -> Machine:
    """This machine: the process's environment, this repository, and commands
    run as subprocesses with that environment."""
    env = dict(os.environ)

    def run(command: list[str]) -> tuple[int, str]:
        try:
            done = subprocess.run(command, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, timeout=120)
        except FileNotFoundError:
            return 127, "command not found: %s" % command[0]
        except PermissionError:
            return 126, "permission denied: %s" % command[0]
        except subprocess.TimeoutExpired:
            return 124, "timed out: %s" % " ".join(command[:2])
        return done.returncode, done.stdout

    return Machine(env=env, repository=REPOSITORY, run=run)


def main() -> int:
    missing = check_all(real_machine())
    if not missing:
        print("setup check passed")
        return 0
    for each in missing:
        print("missing: %s (found: %s)" % (each.part, each.found))
        print("  fix: %s" % each.fix)
    print("setup check FAILED: %d part%s missing" % (len(missing), "" if len(missing) == 1 else "s"))
    return 1


if __name__ == "__main__":
    sys.exit(main())

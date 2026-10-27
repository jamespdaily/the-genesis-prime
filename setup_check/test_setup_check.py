"""setup_check: every part this machine needs is named, with what was found and its fix.

Every test but two plants a Machine: an `env` mapping, a temporary repository
folder and a `run` function that answers commands from a table, so no test
touches the real install. The two exceptions run on this machine: the
real-machine test (needs ~/.genesis-prime/env.sh's variables, which the full
check sources before the setup check; the test reads them with zsh) and the
full-check test (runs ./check in a subprocess with a planted environment).

Expected values and their sources:
- Gleam 1.19.2, OTP 29.1.2 and rebar3 3.28.0: the repository's .tool-versions
  (read from it here); the Gleam range ">= 1.19.2 and < 2.0.0" is gleam.toml's
  `gleam` field.
- Ghidra 12.2, JDK 25, Python 3.13, PyGhidra 3.2.0 and the client's SHA-256:
  ghidra_env's pins. The planted client is a small file, so its test pins
  ghidra_env.CLIENT_SHA256 to that file's hash for the length of the test; the
  client check must read the pin as `ghidra_env.CLIENT_SHA256` at the time it
  runs. The client's hash belongs to check_client alone: the query-process
  check does not report it.
- The client's archive index layout and build: the fact file's record
  "archive_index.header" (PACK header 0x230 bytes, block table at 0x240, AIDX
  header 16 bytes with the build at its offset 8) and the client's own build
  16042 (client_archive.target_build, GetVersionInfo 0x1406f8360).
- Erlang distribution: a VM turns it on with the `-name` or `-sname` flag (Erlang
  reference manual, "Distributed Erlang"; `erl` flags), which a release reads
  from its vm.args; a vm.args line that starts with `#` is a comment (Erlang
  system principles, "Releases", vm.args). The server runs as one node and uses
  no distribution (issue #30, closing summary). No file of that name is in the
  repository, so the check passes where there is none.
- Postgres 18: Jim's choice on issue #13 ("with Postgres 18 as the version
  checked"); the clock tolerance is 1 second, from the issue's test list.

What a planted command answers (the contract the checks run against):
- a missing tool answers (127, "command not found: NAME");
- `gleam ...` answers "gleam X.Y.Z"; `erl ...` answers the full OTP version
  alone ("29.1.2"); `rebar3 ...` answers "rebar 3.28.0 on Erlang/OTP 29 Erts 17.1.1";
- `git ... ls-files ...` answers the file's name when it is tracked; when it is
  not, `--error-unmatch` fails with exit 1 and without it the output is empty;
- `psql ...` answers each of the words server_version_num, server_version and
  epoch found in the query, in the order they appear, joined by "|"
  (the clock as epoch seconds, plus or minus the planted offset); an
  unreachable server answers exit 2; `pg_isready` answers by the same state;
- the command `$GENESIS_PYGHIDRA_PYTHON -I -c SNIPPET` (the interpreter the
  query process uses; the snippet imports ghidra_env from the skill's scripts
  folder and reports each failure; "ghidra_env" and
  ".claude/skills/decoding-the-client/scripts" must appear in the command)
  answers exit 0 and nothing when every part is right; exit 1 and one line per
  failure, each line the message ghidra_env raises as WrongVersion, when not
  (the client's hash is not among them); any other exit means the interpreter
  could not run;
- any other command stops the test with an AssertionError, so a check that
  runs something the table does not know is seen at once.

The patched OTP is checked unless GENESIS_NO_CLIENT=1 and GENESIS_OTP_DIR is
unset (CI sets GENESIS_OTP_DIR, so it runs on the patched build it caches), and
setup_check/environment.sh puts its bin first on PATH on the same condition.
The patched OTP's marker is the file `GENESIS_PATCHES` in $GENESIS_OTP_DIR: one
line per patch, "NAME SHA-256", the name and the hash of that file in the
repository's setup_check/ folder. The check requires a line, with the matching
hash, for every setup_check/*.patch, so a changed patch asks for a rebuild.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import contextlib
import hashlib
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from dataclasses import dataclass
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent
SCRIPTS = REPOSITORY / ".claude" / "skills" / "decoding-the-client" / "scripts"
for directory in (HERE, SCRIPTS):
    if str(directory) not in sys.path:
        sys.path.insert(0, str(directory))

import check_support  # noqa: E402
import ghidra_env  # noqa: E402
import setup_check  # noqa: E402
import test_extract_tables  # noqa: E402
from setup_check import Machine, Missing  # noqa: E402

# ---------------------------------------------------------------- expected values


def pinned_tool_versions() -> dict[str, str]:
    """.tool-versions read here, apart from the code under test."""
    pins = {}
    for line in (REPOSITORY / ".tool-versions").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            tool, version = line.split()[:2]
            pins[tool] = version
    return pins


PINS = pinned_tool_versions()
GLEAM = PINS["gleam"]  # 1.19.2
OTP = PINS["erlang"]  # 29.1.2
REBAR = PINS["rebar"]  # 3.28.0
TARGET_BUILD = 16042  # client_archive.target_build: GetVersionInfo 0x1406f8360 returns 0x3eaa
OTHER_BUILD = 17000
POSTGRES_MAJOR = "18"  # issue #13, Jim's choice
PATCH_FILE = "otp-erl-gc-live-hf-end.patch"
MARKER = "GENESIS_PATCHES"

PATCH_SHA256 = hashlib.sha256((HERE / PATCH_FILE).read_bytes()).hexdigest()
STALE_SHA256 = hashlib.sha256(b"an older patch").hexdigest()

PLANTED_CLIENT = b"planted WildStar64.exe"
OTHER_CLIENT = b"another WildStar64.exe"
INDEX_NAMES = ("Client64.index", "ClientData.index", "ClientDataEN.index", "Patch.index")
# Tables of the client's DB folder (fact file, game_tables.ClientData: 384 game
# tables); the planted ClientData.index lists these five, standing for the 384.
TABLE_NAMES = ("Creature2", "World", "XpPerLevel", "CharacterCreation", "Spell4")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def archive_index(build: int) -> bytes:
    """An index laid out as the fact file's "archive_index.header" says: PACK
    signature 0x5041434B and version 1, 64 zero offsets, archive end at 0x208,
    block table at 0x240 with 3 blocks and root block 2, the AIDX block
    (signature 0x41494458, version 1, build, root directory 1) at 0x270."""
    block_offset, table_offset, blocks, root = 0x270, 0x240, 3, 2
    archive_end = block_offset + 16
    header = struct.pack("<II", 0x5041434B, 1) + bytes(0x200)  # 0x000..0x208
    header += struct.pack("<QQQ", archive_end, 0, table_offset)  # 0x208, 0x210, 0x218
    header += struct.pack("<IIII", blocks, 0, root, 0)  # 0x220, 0x224, 0x228, 0x22c
    assert len(header) == 0x230
    header += bytes(0x10)
    table = b"".join(
        struct.pack("<QQ", block_offset, 16) if i == root else struct.pack("<QQ", 0, 0) for i in range(blocks)
    )
    aidx = struct.pack("<IIII", 0x41494458, 1, build, 1)
    data = header + table + aidx
    assert len(data) == archive_end
    return data


# ---------------------------------------------------------------- the planted machine


@dataclass
class Plan:
    """The machine as planted; every default is a part that is right."""

    gleam: str | None = GLEAM
    otp: str | None = OTP
    rebar: str | None = REBAR
    manifest_tracked: bool = True
    postgres_reachable: bool = True
    postgres_version: str = "18.6"
    postgres_clock_offset: float = 0.0  # seconds the server's clock is ahead
    with_client: bool = True  # False: nothing of the client, the query process or the patched OTP
    otp_without_client: bool = False  # with_client False, and still GENESIS_OTP_DIR and the build there (CI)
    no_client_flag: bool = False  # GENESIS_NO_CLIENT=1
    client: str = "good"  # good, other (another SHA-256) or missing
    index_builds: tuple = (TARGET_BUILD,) * 4  # per name in INDEX_NAMES: a build, "garbage" or "signature"
    otp_dir: str = "patched"  # patched, unmarked, stale, unlisted_patch or absent
    erl_on_path: str = "patched"  # which erl PATH finds first: patched, elsewhere (a stock OTP) or linked (a link to the patched erl)
    otp_dir_linked: bool = False  # GENESIS_OTP_DIR names a symbolic link to the patched OTP's folder
    ghidra_version: str = "12.2"
    decompiler: bool = True
    jdk: str = "25.0.1"
    python: tuple = (3, 13, 0)
    pyghidra: str | None = ghidra_env.PYGHIDRA_VERSION
    pyghidra_python: str = "ok"  # ok, unset, not_runnable (exit 126) or absent (exit 127)
    without_variables: tuple = ()  # variables left out of env
    project_path: str = "projects/ghidra"  # under the temporary root
    index_tables: tuple = TABLE_NAMES  # the tables ClientData.index lists under DB/
    tables_missing: tuple = ()  # of those, the ones left out of the table folder
    table_folder: str = "present"  # present, or absent (no folder at all)


class PlantedTestCase(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="genesis-setup-check-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()

    # -- the machine

    def plant(self, plan: Plan | None = None, **changes) -> Machine:
        plan = plan or Plan(**changes)
        for leftover in ("repository", "WildStar", "ghidra", "jdk", "otp", "stock"):  # a test may plant twice
            shutil.rmtree(self.root / leftover, ignore_errors=True)
        (self.root / "otp-link").unlink(missing_ok=True)
        repository = self.root / "repository"
        repository.mkdir()
        for name in (".tool-versions", "gleam.toml"):
            shutil.copyfile(REPOSITORY / name, repository / name)
        (repository / "manifest.toml").write_text("# planted\n")
        (repository / "setup_check").mkdir()
        shutil.copyfile(HERE / PATCH_FILE, repository / "setup_check" / PATCH_FILE)
        if plan.otp_dir == "unlisted_patch":
            (repository / "setup_check" / "second.patch").write_text("a second patch\n")
        env = {
            "HOME": str(self.root / "home"),
            "GENESIS_HOME": str(self.root / "home" / ".genesis-prime"),
            "PGHOST": "/tmp",
            "PGPORT": "5433",
            "PGUSER": "postgres",
        }
        if plan.no_client_flag:
            env["GENESIS_NO_CLIENT"] = "1"
        if plan.with_client:
            env.update(self.plant_client(plan))
        elif plan.otp_without_client:
            env.update(self.plant_otp(plan))
        env["PATH"] = self.plant_path(plan, env)
        for name in plan.without_variables:
            env.pop(name, None)
        self.apply_pins(plan)
        return Machine(env=env, repository=repository, run=self.runner(plan, env))

    def plant_client(self, plan: Plan) -> dict[str, str]:
        client_root = self.root / "WildStar"
        (client_root / "Client64").mkdir(parents=True, exist_ok=True)
        (client_root / "Patch").mkdir(exist_ok=True)
        exe = client_root / "Client64" / "WildStar64.exe"
        if plan.client != "missing":
            exe.write_bytes(PLANTED_CLIENT if plan.client == "good" else OTHER_CLIENT)
        for name, build in zip(INDEX_NAMES, plan.index_builds):
            data = archive_index(build if isinstance(build, int) else TARGET_BUILD)
            if name == "ClientData.index" and build == TARGET_BUILD:
                data = self.index_listing_tables(plan)
            if build == "garbage":
                data = b"this is not an archive index"
            elif build == "signature":
                data = b"KCAQ" + data[4:]
            (client_root / "Patch" / name).write_bytes(data)
        ghidra = self.root / "ghidra"
        ghidra.mkdir(exist_ok=True)
        jdk = self.root / "jdk"
        jdk.mkdir(exist_ok=True)
        env = {
            "GENESIS_TABLE_DIR": str(self.plant_table_folder(plan)),
            "WILDSTAR_CLIENT_EXE": str(exe),
            "GENESIS_GHIDRA_DIR": str(ghidra),
            "GENESIS_GHIDRA_PROJECT_DIR": str(self.root / plan.project_path),
            "JAVA_HOME": str(jdk),
        }
        env.update(self.plant_otp(plan))
        if plan.pyghidra_python != "unset":
            interpreter = self.root / "pyghidra-venv" / "bin" / "python"
            interpreter.parent.mkdir(parents=True, exist_ok=True)
            interpreter.write_text("#!/bin/sh\n")
            env["GENESIS_PYGHIDRA_PYTHON"] = str(interpreter)
        return env

    def index_listing_tables(self, plan: Plan) -> bytes:
        """A ClientData.index with a directory tree: the tables of the plan under
        DB/, and two files that are not tables of the DB folder (DB/Notes.txt and
        Other/Gamma.tbl), which the folder never holds."""
        client_data = self.root / "client-data"
        shutil.rmtree(client_data, ignore_errors=True)
        client_data.mkdir()
        files = [("DB/%s.tbl" % name, test_extract_tables.table_content(name), 5) for name in plan.index_tables]
        files += [("DB/Notes.txt", b"not a table", 1), ("Other/Gamma.tbl", test_extract_tables.table_content("gamma"), 5)]
        planted = test_extract_tables.Planted(client_data, files)
        return (planted.patch / "ClientData.index").read_bytes()

    def plant_table_folder(self, plan: Plan) -> Path:
        """The folder GENESIS_TABLE_DIR names: a file for each table the index
        lists, less the plan's missing ones; not there at all when absent."""
        folder = self.root / "tables"
        shutil.rmtree(folder, ignore_errors=True)
        if plan.table_folder != "absent":
            folder.mkdir()
            for name in plan.index_tables:
                if name not in plan.tables_missing:
                    (folder / (name + ".tbl")).write_bytes(test_extract_tables.table_content(name))
        return folder

    def plant_otp(self, plan: Plan) -> dict[str, str]:
        """The patched OTP's folder as plan.otp_dir says, and GENESIS_OTP_DIR for it."""
        otp_dir = self.root / "otp"
        if plan.otp_dir != "absent":
            (otp_dir / "bin").mkdir(parents=True, exist_ok=True)
            (otp_dir / "bin" / "erl").write_text("#!/bin/sh\n")
            (otp_dir / "bin" / "erl").chmod(0o755)
        lines = {
            "patched": ["%s %s" % (PATCH_FILE, PATCH_SHA256)],
            "unlisted_patch": ["%s %s" % (PATCH_FILE, PATCH_SHA256)],
            "stale": ["%s %s" % (PATCH_FILE, STALE_SHA256)],
        }
        if plan.otp_dir in lines:
            (otp_dir / MARKER).write_text("\n".join(lines[plan.otp_dir]) + "\n")
        if plan.otp_dir_linked:
            link = self.root / "otp-link"
            if not link.exists():
                link.symlink_to(otp_dir)
            return {"GENESIS_OTP_DIR": str(link)}
        return {"GENESIS_OTP_DIR": str(otp_dir)}

    def plant_path(self, plan: Plan, env: dict[str, str]) -> str:
        """PATH as the plan says: the patched OTP's bin and, ahead of it or in
        place of its erl, another folder with an erl that is a stock OTP's or a
        link to the patched one."""
        folders = []
        if plan.erl_on_path != "patched":
            stock = self.root / "stock" / "bin"
            stock.mkdir(parents=True, exist_ok=True)
            if plan.erl_on_path == "elsewhere":
                (stock / "erl").write_text("#!/bin/sh\n")
                (stock / "erl").chmod(0o755)
            else:
                (stock / "erl").symlink_to(self.root / "otp" / "bin" / "erl")
            folders.append(str(stock))
        if "GENESIS_OTP_DIR" in env:
            folders.append(str(self.root / "otp" / "bin"))
        return ":".join(folders)

    def apply_pins(self, plan: Plan):
        """The client's pin is the hash of the planted client."""
        patch = mock.patch.object(ghidra_env, "CLIENT_SHA256", sha256(PLANTED_CLIENT))
        patch.start()
        self.addCleanup(patch.stop)

    def runner(self, plan: Plan, env):
        def run(argv: list[str]) -> tuple[int, str]:
            if env.get("GENESIS_PYGHIDRA_PYTHON") and argv[0] == env["GENESIS_PYGHIDRA_PYTHON"]:
                return self.pyghidra_python(plan, env, argv)
            program = os.path.basename(argv[0])
            if program == "gleam":
                return self.answer(plan.gleam, program, "gleam %s\n" % plan.gleam)
            if program == "erl":
                return self.answer(plan.otp, program, "%s\n" % plan.otp)
            if program == "rebar3":
                major = (plan.otp or "0").split(".")[0]
                return self.answer(plan.rebar, program, "rebar %s on Erlang/OTP %s Erts 17.1.1\n" % (plan.rebar, major))
            if program == "git" and "ls-files" in argv:
                if plan.manifest_tracked:
                    return 0, "manifest.toml\n"
                if "--error-unmatch" in argv:
                    return 1, "error: pathspec 'manifest.toml' did not match any file(s) known to git\n"
                return 0, ""
            if program == "pg_isready":
                if plan.postgres_reachable:
                    return 0, "/tmp:5433 - accepting connections\n"
                return 2, "/tmp:5433 - no response\n"
            if program == "psql":
                return self.psql(plan, argv)
            raise AssertionError("the planted machine has no answer for %r" % (argv,))

        return run

    @staticmethod
    def pyghidra_python(plan: Plan, env, argv: list[str]) -> tuple[int, str]:
        """The query process's interpreter running the snippet that imports
        ghidra_env: the first failure check_parts would raise, as its message."""
        command = " ".join(argv)
        if "-I" not in argv or "-c" not in argv:
            raise AssertionError("the snippet must run as `python -I -c`: %r" % (argv,))
        if "ghidra_env" not in command or ".claude/skills/decoding-the-client/scripts" not in command:
            raise AssertionError("the snippet must import ghidra_env from the skill's scripts folder: %r" % (argv,))
        if plan.pyghidra_python == "not_runnable":
            return 126, "permission denied: %s\n" % argv[0]
        if plan.pyghidra_python == "absent":
            return 127, "no such file or directory: %s\n" % argv[0]
        ghidra_dir, java_home = env.get("GENESIS_GHIDRA_DIR", ""), env.get("JAVA_HOME", "")
        jdk_major = plan.jdk.split(".")[0]
        if plan.ghidra_version != ghidra_env.GHIDRA_VERSION:
            failure = "Ghidra %s found at %s, %s required" % (plan.ghidra_version, ghidra_dir, ghidra_env.GHIDRA_VERSION)
        elif not plan.decompiler:
            failure = "no macOS arm64 decompiler at %s/Ghidra/Features/Decompiler/os/mac_arm_64/decompile" % ghidra_dir
        elif jdk_major != str(ghidra_env.JDK_MAJOR):
            failure = "JDK %r found at %s, %d required" % (jdk_major, java_home, ghidra_env.JDK_MAJOR)
        elif plan.python[:2] != ghidra_env.PYTHON_MINOR:
            failure = "Python %d.%d found, %d.%d required" % (*plan.python[:2], *ghidra_env.PYTHON_MINOR)
        elif plan.pyghidra is None:
            failure = "PyGhidra is not installed, %s required" % ghidra_env.PYGHIDRA_VERSION
        elif plan.pyghidra != ghidra_env.PYGHIDRA_VERSION:
            failure = "PyGhidra %s found, %s required" % (plan.pyghidra, ghidra_env.PYGHIDRA_VERSION)
        else:
            return 0, ""
        return 1, failure + "\n"

    @staticmethod
    def answer(version, program, output):
        if version is None:
            return 127, "command not found: %s\n" % program
        return 0, output

    @staticmethod
    def psql(plan: Plan, argv: list[str]) -> tuple[int, str]:
        if not plan.postgres_reachable:
            return 2, 'psql: error: connection to server on socket "/tmp/.s.PGSQL.5433" failed: No such file or directory\n'
        query = " ".join(argv).lower()
        words = {
            "server_version_num": _version_number(plan.postgres_version),
            "server_version": plan.postgres_version,
            "epoch": "%.3f" % (time.time() + plan.postgres_clock_offset),
        }
        found = []
        for match in re.finditer(r"server_version_num|server_version|epoch", query):
            found.append((match.start(), words[match.group()]))
        if not found:
            raise AssertionError("the planted psql has no answer for %r" % (argv,))
        return 0, "|".join(value for _at, value in sorted(found)) + "\n"

    # -- what a test asserts

    @staticmethod
    def text(missing: Missing) -> str:
        return " ".join((missing.part, missing.found, missing.fix)).lower()

    def only(self, result: list[Missing]) -> Missing:
        self.assertEqual(len(result), 1, "expected exactly one Missing, got %r" % (result,))
        return result[0]

    def assert_part(self, missing: Missing, *words: str):
        self.assertTrue(
            any(word.lower() in missing.part.lower() for word in words),
            "part %r names none of %r" % (missing.part, words),
        )

    def assert_fix(self, missing: Missing, *words: str):
        self.assertTrue(missing.fix.strip(), "the fix is empty for %r" % (missing,))
        self.assertTrue(
            any(word.lower() in missing.fix.lower() for word in words),
            "fix %r names none of %r" % (missing.fix, words),
        )

    def assert_found(self, missing: Missing, text: str):
        self.assertIn(text.lower(), missing.found.lower())


def _version_number(version: str) -> str:
    major, _, minor = version.partition(".")
    return str(int(major) * 10000 + int(minor or 0))


INSTALL_WORDS = ("install", "asdf", "mise", "brew")


# ---------------------------------------------------------------- 1. all present


class AllPresentTest(PlantedTestCase):
    def test_a_machine_with_every_part_right_has_nothing_missing(self):
        self.assertEqual(setup_check.check_all(self.plant()), [])

    def test_a_machine_without_the_client_and_marked_so_needs_no_client_part_and_no_patched_otp(self):
        # CI: GENESIS_NO_CLIENT=1, no client, no query process variables, no patched OTP.
        machine = self.plant(with_client=False, no_client_flag=True)
        self.assertEqual(setup_check.check_all(machine), [])

    def test_a_machine_without_the_client_and_not_marked_so_is_missing_the_client(self):
        result = setup_check.check_all(self.plant(with_client=False))
        self.assertTrue(
            any("wildstar64" in self.text(m) or "client" in m.part.lower() for m in result),
            "no Missing names the client: %r" % (result,),
        )


def real_environment() -> dict[str, str] | None:
    """os.environ after the full check's sourcing of env.sh, or None when the
    machine has no env.sh."""
    home = Path(os.environ.get("GENESIS_HOME", "~/.genesis-prime")).expanduser()
    env_sh = home / "env.sh"
    if not env_sh.is_file():
        return None
    out = subprocess.run(
        ["zsh", "-c", 'source "$1" && env -0', "zsh", str(env_sh)], capture_output=True, text=True, check=True
    ).stdout
    env = dict(os.environ)
    env.update(line.split("=", 1) for line in out.split("\0") if "=" in line)
    env.setdefault("GENESIS_HOME", str(home))
    return env


class RealMachineTest(unittest.TestCase):
    @check_support.needs_client
    def test_this_machine_has_every_part_right(self):
        """Needs the variables of ~/.genesis-prime/env.sh (GENESIS_HOME/env.sh), which
        the full check sources before the setup check; they are read here by running
        zsh. The patched OTP's bin goes first on PATH, as the full check puts it."""
        env = real_environment()
        if env is None:
            self.skipTest("no env.sh under GENESIS_HOME (default ~/.genesis-prime): this machine is not set up")
        otp_dir = Path(env.get("GENESIS_OTP_DIR") or Path.home() / ".genesis-prime" / "otp-29.1.2-gc-marker")
        env["GENESIS_OTP_DIR"] = str(otp_dir)
        env["PATH"] = "%s:%s" % (otp_dir / "bin", env.get("PATH", ""))

        def run(argv):
            try:
                done = subprocess.run(
                    argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, timeout=60,
                )
            except FileNotFoundError:
                return 127, "command not found: %s\n" % argv[0]
            return done.returncode, done.stdout

        machine = Machine(env=env, repository=REPOSITORY, run=run)
        self.assertEqual(setup_check.check_all(machine), [])


# ---------------------------------------------------------------- 2. Gleam


class GleamTest(PlantedTestCase):
    def test_a_missing_gleam_is_named_with_the_pinned_version_to_install(self):
        missing = self.only(setup_check.check_gleam(self.plant(gleam=None)))
        self.assert_part(missing, "gleam")
        self.assertIn(GLEAM, missing.part)
        self.assertEqual(missing.found, "nothing")
        self.assert_fix(missing, *INSTALL_WORDS)
        self.assertIn(GLEAM, missing.fix)

    def test_a_gleam_other_than_the_pinned_version_is_named_with_what_was_found(self):
        # 1.18.0 is below gleam.toml's ">= 1.19.2 and < 2.0.0"; 1.20.0 is inside it
        # and still not the .tool-versions pin.
        for found in ("1.18.0", "1.20.0"):
            with self.subTest(found=found):
                missing = self.only(setup_check.check_gleam(self.plant(gleam=found)))
                self.assert_part(missing, "gleam")
                self.assert_found(missing, found)
                self.assertIn(GLEAM, missing.part + missing.fix)
                self.assert_fix(missing, *INSTALL_WORDS)

    def test_the_pinned_gleam_is_not_missing(self):
        self.assertEqual(setup_check.check_gleam(self.plant()), [])


# ---------------------------------------------------------------- 3. Erlang, rebar3, patched OTP


class ErlangTest(PlantedTestCase):
    def test_a_missing_erlang_is_named_with_the_pinned_version_to_install(self):
        missing = self.only(setup_check.check_erlang(self.plant(otp=None)))
        self.assert_part(missing, "erlang", "otp")
        self.assertIn(OTP, missing.part)
        self.assertEqual(missing.found, "nothing")
        self.assert_fix(missing, *INSTALL_WORDS)
        self.assertIn(OTP, missing.fix)

    def test_an_otp_other_than_the_pinned_version_is_named_with_what_was_found(self):
        for found in ("28.3.1", "29.1.1"):
            with self.subTest(found=found):
                missing = self.only(setup_check.check_erlang(self.plant(otp=found)))
                self.assert_part(missing, "erlang", "otp")
                self.assert_found(missing, found)
                self.assertIn(OTP, missing.part + missing.fix)
                self.assert_fix(missing, *INSTALL_WORDS)

    def test_a_patched_otp_missing_at_genesis_otp_dir_is_named_where_the_client_is(self):
        missing = self.only(setup_check.check_erlang(self.plant(otp_dir="absent")))
        self.assert_part(missing, "patch")
        self.assert_fix(missing, "GENESIS_OTP_DIR", PATCH_FILE)

    def test_a_patched_otp_without_its_genesis_patches_file_is_named_where_the_client_is(self):
        missing = self.only(setup_check.check_erlang(self.plant(otp_dir="unmarked")))
        self.assert_part(missing, "patch")
        self.assert_found(missing, MARKER)
        self.assertIn(PATCH_FILE, missing.part + missing.found + missing.fix)
        self.assert_fix(missing, "GENESIS_OTP_DIR", PATCH_FILE, "rebuild")

    def test_a_patched_otp_built_from_an_older_patch_asks_for_a_rebuild(self):
        # the line for the patch holds another SHA-256 than the file in setup_check/
        missing = self.only(setup_check.check_erlang(self.plant(otp_dir="stale")))
        self.assert_part(missing, "patch")
        self.assertIn(PATCH_FILE, missing.part + missing.found)
        self.assert_fix(missing, "rebuild")

    def test_a_patch_in_setup_check_with_no_line_in_genesis_patches_asks_for_a_rebuild(self):
        missing = self.only(setup_check.check_erlang(self.plant(otp_dir="unlisted_patch")))
        self.assert_part(missing, "patch")
        self.assertIn("second.patch", missing.part + missing.found)
        self.assert_fix(missing, "rebuild")

    def test_the_patched_otp_is_not_required_where_genesis_no_client_is_1_and_genesis_otp_dir_is_unset(self):
        machine = self.plant(otp_dir="absent", no_client_flag=True, without_variables=("GENESIS_OTP_DIR",))
        self.assertEqual(setup_check.check_erlang(machine), [])

    def test_the_patched_otp_is_required_where_genesis_no_client_is_1_and_genesis_otp_dir_is_set(self):
        # CI: no client, but GENESIS_OTP_DIR names the build it runs on.
        for otp_dir, expected in (("absent", "nothing"), ("unmarked", MARKER), ("stale", PATCH_FILE)):
            with self.subTest(otp_dir=otp_dir):
                machine = self.plant(otp_dir=otp_dir, no_client_flag=True)
                missing = self.only(setup_check.check_erlang(machine))
                self.assert_part(missing, "patch")
                self.assertIn(expected.lower(), (missing.part + missing.found).lower())
                self.assert_fix(missing, "rebuild")

    def test_a_machine_without_the_client_and_marked_so_but_with_the_patched_otp_has_nothing_missing(self):
        machine = self.plant(with_client=False, otp_without_client=True, no_client_flag=True)
        self.assertEqual(setup_check.check_all(machine), [])

    def test_a_machine_without_the_client_and_marked_so_with_a_stale_patched_otp_is_missing_only_the_rebuild(self):
        machine = self.plant(with_client=False, otp_without_client=True, no_client_flag=True, otp_dir="stale")
        missing = self.only(setup_check.check_all(machine))
        self.assert_part(missing, "patch")
        self.assert_fix(missing, "rebuild")

    def test_the_pinned_otp_with_its_patched_build_is_not_missing(self):
        self.assertEqual(setup_check.check_erlang(self.plant()), [])

    def test_an_erl_on_path_from_outside_the_patched_otp_is_named_with_both_paths(self):
        machine = self.plant(erl_on_path="elsewhere")
        missing = self.only(setup_check.check_erlang(machine))
        self.assert_part(missing, "erl")
        stock_erl = str(self.root / "stock" / "bin" / "erl")
        patched_bin = str(self.root / "otp" / "bin")
        self.assertIn(stock_erl, missing.part + missing.found)
        self.assertIn(patched_bin, missing.part + missing.found + missing.fix)
        self.assert_fix(missing, "PATH", "environment.sh")

    def test_an_erl_on_path_from_outside_the_patched_otp_is_named_where_genesis_no_client_is_1_and_genesis_otp_dir_is_set(self):
        machine = self.plant(erl_on_path="elsewhere", no_client_flag=True)
        missing = self.only(setup_check.check_erlang(machine))
        self.assert_part(missing, "erl")
        self.assert_fix(missing, "PATH")

    def test_an_erl_on_path_that_is_a_link_to_the_patched_erl_is_not_missing(self):
        self.assertEqual(setup_check.check_erlang(self.plant(erl_on_path="linked")), [])

    def test_a_genesis_otp_dir_that_is_a_link_to_the_patched_otp_is_not_missing(self):
        self.assertEqual(setup_check.check_erlang(self.plant(otp_dir_linked=True)), [])

    def test_the_erl_on_path_is_not_checked_where_genesis_no_client_is_1_and_genesis_otp_dir_is_unset(self):
        machine = self.plant(erl_on_path="elsewhere", no_client_flag=True, without_variables=("GENESIS_OTP_DIR",))
        self.assertEqual(setup_check.check_erlang(machine), [])


class RebarTest(PlantedTestCase):
    def test_a_missing_rebar3_is_named_with_the_pinned_version_to_install(self):
        missing = self.only(setup_check.check_rebar(self.plant(rebar=None)))
        self.assert_part(missing, "rebar")
        self.assertIn(REBAR, missing.part)
        self.assertEqual(missing.found, "nothing")
        self.assert_fix(missing, *INSTALL_WORDS)
        self.assertIn(REBAR, missing.fix)

    def test_a_rebar3_other_than_the_pinned_version_is_named_with_what_was_found(self):
        missing = self.only(setup_check.check_rebar(self.plant(rebar="3.25.0")))
        self.assert_part(missing, "rebar")
        self.assert_found(missing, "3.25.0")
        self.assertIn(REBAR, missing.part + missing.fix)
        self.assert_fix(missing, *INSTALL_WORDS)

    def test_the_pinned_rebar3_is_not_missing(self):
        self.assertEqual(setup_check.check_rebar(self.plant()), [])


class EnvironmentTest(PlantedTestCase):
    """setup_check/environment.sh, sourced by ./check and ./setup-check from the
    repository's folder: the patched OTP's bin goes first on PATH, unless
    GENESIS_NO_CLIENT=1 and GENESIS_OTP_DIR is unset."""

    def sourced(self, **env) -> dict[str, str]:
        base = {"PATH": "/usr/bin:/bin", "HOME": str(self.root), "GENESIS_HOME": str(self.root / "genesis-home")}
        base.update(env)
        script = '. setup_check/environment.sh; printf "%s\\n%s\\n" "$PATH" "${GENESIS_OTP_DIR:-unset}"'
        done = subprocess.run(["sh", "-c", script], cwd=REPOSITORY, env=base, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr)
        path, otp_dir = done.stdout.splitlines()
        return {"PATH": path, "GENESIS_OTP_DIR": otp_dir}

    def test_the_patched_otp_is_first_on_path_by_default_in_the_genesis_home(self):
        result = self.sourced()
        default = str(self.root / "genesis-home" / ("otp-%s-gc-marker" % OTP))
        self.assertEqual(result["GENESIS_OTP_DIR"], default)
        self.assertEqual(result["PATH"], "%s/bin:/usr/bin:/bin" % default)

    def test_genesis_otp_dir_names_the_patched_otp_first_on_path(self):
        result = self.sourced(GENESIS_OTP_DIR="/somewhere/otp")
        self.assertEqual(result["GENESIS_OTP_DIR"], "/somewhere/otp")
        self.assertEqual(result["PATH"], "/somewhere/otp/bin:/usr/bin:/bin")

    def test_where_genesis_no_client_is_1_and_genesis_otp_dir_is_unset_path_is_left_as_it_is(self):
        result = self.sourced(GENESIS_NO_CLIENT="1")
        self.assertEqual(result["GENESIS_OTP_DIR"], "unset")
        self.assertEqual(result["PATH"], "/usr/bin:/bin")

    def test_where_genesis_no_client_is_1_and_genesis_otp_dir_is_set_the_patched_otp_is_first_on_path(self):
        # CI: no client, the patched OTP from the cache.
        result = self.sourced(GENESIS_NO_CLIENT="1", GENESIS_OTP_DIR="/cache/otp")
        self.assertEqual(result["GENESIS_OTP_DIR"], "/cache/otp")
        self.assertEqual(result["PATH"], "/cache/otp/bin:/usr/bin:/bin")


# ---------------------------------------------------------------- 4. manifest.toml


class ManifestTest(PlantedTestCase):
    def test_a_manifest_toml_not_tracked_by_git_is_named_with_the_command_to_add_it(self):
        missing = self.only(setup_check.check_manifest(self.plant(manifest_tracked=False)))
        self.assert_part(missing, "manifest.toml")
        self.assert_fix(missing, "git add")
        self.assertIn("manifest.toml", missing.fix)

    def test_a_tracked_manifest_toml_is_not_missing(self):
        self.assertEqual(setup_check.check_manifest(self.plant()), [])


# ---------------------------------------------------------------- distribution


class DistributionTest(PlantedTestCase):
    def settings(self, machine: Machine, path: str, text: str):
        file = machine.repository / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def test_a_repository_with_no_release_settings_has_nothing_missing(self):
        self.assertEqual(setup_check.check_distribution(self.plant()), [])

    def test_a_vm_args_with_a_sname_line_is_named_with_its_file_line_and_text(self):
        machine = self.plant()
        self.settings(machine, "vm.args", "-setcookie planted\n-sname genesis\n+K true\n")
        missing = self.only(setup_check.check_distribution(machine))
        self.assert_part(missing, "distribution")
        self.assert_found(missing, "vm.args line 2")
        self.assert_found(missing, "-sname genesis")
        self.assert_fix(missing, "-sname")

    def test_a_vm_args_src_with_a_name_line_in_a_folder_is_named_with_its_path(self):
        machine = self.plant()
        self.settings(machine, "rel/vm.args.src", "## the node\n-name genesis@${HOST}\n")
        missing = self.only(setup_check.check_distribution(machine))
        self.assert_found(missing, "rel/vm.args.src line 2")
        self.assert_found(missing, "-name genesis@${HOST}")

    def test_an_indented_name_line_turns_distribution_on_too(self):
        machine = self.plant()
        self.settings(machine, "config/vm.args", "  -name genesis@127.0.0.1\n")
        self.assert_found(self.only(setup_check.check_distribution(machine)), "config/vm.args line 1")

    def test_every_file_and_every_line_that_turns_it_on_is_named(self):
        machine = self.plant()
        self.settings(machine, "vm.args", "-sname one\n-name two\n")
        self.settings(machine, "rel/vm.args.src", "-sname three\n")
        result = setup_check.check_distribution(machine)
        self.assertEqual(len(result), 3, result)
        found = " | ".join(missing.found for missing in result)
        for expected in ("vm.args line 1", "vm.args line 2", "rel/vm.args.src line 1"):
            self.assertIn(expected, found)

    def test_settings_that_do_not_turn_distribution_on_have_nothing_missing(self):
        machine = self.plant()
        self.settings(
            machine,
            "vm.args",
            "# -name commented\n## -sname commented\n\n-setcookie planted\n+K true\n-kernel net_ticktime 60\n"
            "-namespace x\n-snames x\n",
        )
        self.assertEqual(setup_check.check_distribution(machine), [])

    def test_a_vm_args_under_build_or_git_is_not_the_releases(self):
        machine = self.plant()
        self.settings(machine, "build/packages/some_package/vm.args", "-sname dependency\n")
        self.settings(machine, ".git/vm.args", "-sname dependency\n")
        self.assertEqual(setup_check.check_distribution(machine), [])

    def test_the_releases_committed_vm_args_holds_no_name_or_sname(self):
        """The release keeps its VM flags in release/vm.args (issue #43), which the
        check above reads; the tests above show a planted -name or -sname is
        found, so an empty result for this repository is the release's flags
        turning distribution off."""
        flags = REPOSITORY / "release" / "vm.args"
        self.assertTrue(flags.is_file(), "the release's VM flags are not committed at release/vm.args")
        machine = Machine(env={}, repository=REPOSITORY, run=lambda argv: (0, ""))
        self.assertEqual(setup_check.check_distribution(machine), [])

    def test_the_check_runs_where_genesis_no_client_is_1_too(self):
        machine = self.plant(with_client=False, no_client_flag=True)
        self.settings(machine, "vm.args", "-sname genesis\n")
        result = setup_check.check_all(machine)
        self.assertEqual(len(result), 1, result)
        self.assert_part(result[0], "distribution")


# ---------------------------------------------------------------- 5. Postgres


class PostgresTest(PlantedTestCase):
    def test_a_postgres_that_is_not_reachable_is_named_with_the_settings_to_check(self):
        missing = self.only(setup_check.check_postgres(self.plant(postgres_reachable=False)))
        self.assert_part(missing, "postgres")
        self.assertIn(POSTGRES_MAJOR, missing.part)
        self.assert_fix(missing, "PGHOST", "PGPORT", "pg_ctl", "brew services")

    def test_a_reachable_postgres_of_major_version_17_is_named_with_what_was_found(self):
        missing = self.only(setup_check.check_postgres(self.plant(postgres_version="17.5")))
        self.assert_part(missing, "postgres")
        self.assertIn(POSTGRES_MAJOR, missing.part)
        self.assert_found(missing, "17")
        self.assert_fix(missing, POSTGRES_MAJOR)

    def test_a_postgres_clock_more_than_1_second_off_is_named_ahead_or_behind(self):
        for offset in (30.0, -30.0):
            with self.subTest(offset=offset):
                missing = self.only(setup_check.check_postgres(self.plant(postgres_clock_offset=offset)))
                self.assert_part(missing, "postgres", "clock")
                self.assertNotEqual(missing.found, "nothing")
                self.assertTrue(missing.found.strip())
                self.assert_fix(missing, "clock", "time", "ntp", "sntp")

    def test_a_postgres_of_major_version_18_with_the_right_time_is_not_missing(self):
        self.assertEqual(setup_check.check_postgres(self.plant()), [])


# ---------------------------------------------------------------- 6. the client


class ClientTest(PlantedTestCase):
    def test_a_missing_wildstar64_exe_is_named_with_the_setting_that_points_at_it(self):
        missing = self.only(setup_check.check_client(self.plant(client="missing")))
        self.assert_part(missing, "wildstar64.exe")
        self.assertEqual(missing.found, "nothing")
        self.assert_fix(missing, "WILDSTAR_CLIENT_EXE", "env.sh")

    def test_a_wildstar64_exe_with_another_sha256_is_named_with_the_hash_found(self):
        missing = self.only(setup_check.check_client(self.plant(client="other")))
        self.assert_part(missing, "wildstar64.exe")
        self.assert_found(missing, sha256(OTHER_CLIENT))
        self.assertIn(sha256(PLANTED_CLIENT), missing.part + missing.fix)  # the pin
        self.assertTrue(missing.fix.strip())

    def test_an_archive_index_whose_build_is_not_16042_is_named_with_its_file_and_build(self):
        # Patch.index is the last of INDEX_NAMES; the other three are on build 16042.
        builds = (TARGET_BUILD, TARGET_BUILD, TARGET_BUILD, OTHER_BUILD)
        missing = self.only(setup_check.check_client(self.plant(index_builds=builds)))
        self.assertIn("Patch.index", missing.part + missing.found)
        self.assert_found(missing, str(OTHER_BUILD))
        self.assertIn(str(TARGET_BUILD), missing.part + missing.fix)
        self.assertTrue(missing.fix.strip())

    def test_every_index_on_another_build_is_named(self):
        builds = (OTHER_BUILD,) * 4
        result = setup_check.check_client(self.plant(index_builds=builds))
        named = "\n".join(m.part + " " + m.found for m in result)
        for name in INDEX_NAMES:
            with self.subTest(index=name):
                self.assertIn(name, named)

    def test_a_file_that_is_not_an_archive_index_is_named_as_such(self):
        # "garbage" is too short for a PACK header; "signature" has a header
        # whose first four bytes are not 0x5041434B (0x1401ba550).
        for kind in ("garbage", "signature"):
            with self.subTest(kind=kind):
                builds = (TARGET_BUILD, kind, TARGET_BUILD, TARGET_BUILD)
                missing = self.only(setup_check.check_client(self.plant(index_builds=builds)))
                self.assertIn("ClientData.index", missing.part + missing.found)
                self.assertIn("not an archive index", self.text(missing))
                self.assertTrue(missing.fix.strip())

    def test_a_client_with_another_sha256_is_one_missing_across_the_whole_check(self):
        # the hash belongs to check_client; the query-process check does not repeat it
        result = setup_check.check_all(self.plant(client="other"))
        missing = self.only(result)
        self.assert_part(missing, "wildstar64.exe")
        self.assert_found(missing, sha256(OTHER_CLIENT))

    def test_a_client_with_the_pinned_hash_and_indexes_on_build_16042_is_not_missing(self):
        self.assertEqual(setup_check.check_client(self.plant()), [])


# ---------------------------------------------------------------- 6b. the table folder


class TableFolderTest(PlantedTestCase):
    """Issue 109, item 4: the setup check checks the table folder holds every
    table of the client's index.

    Expected values: the tables are the files directly in DB/ ending in .tbl of
    the planted ClientData.index (the layout extract_tables documents: 384 for
    the client, fact file game_tables.ClientData); a name is missing when the
    folder holds no file of it."""

    def test_a_folder_holding_every_table_of_the_index_has_nothing_missing(self):
        # The index also lists DB/Notes.txt and Other/Gamma.tbl, which are not tables of DB.
        self.assertEqual(setup_check.check_table_folder(self.plant()), [])

    def test_a_folder_missing_tables_names_each_one_and_no_other(self):
        machine = self.plant(tables_missing=("World", "Spell4"))
        result = setup_check.check_table_folder(machine)
        self.assertTrue(result, "a folder missing two tables passes")
        named = " ".join(self.text(m) for m in result)
        for name in ("World", "Spell4"):
            self.assertIn(name.lower() + ".tbl", named, name + " is named")
        for name in ("Creature2", "XpPerLevel", "CharacterCreation"):
            self.assertNotIn(name.lower(), named, name + " is there and is not named")

    def test_the_setup_check_as_a_whole_fails_on_a_missing_table(self):
        result = setup_check.check_all(self.plant(tables_missing=("XpPerLevel",)))
        self.assertTrue(any("xpperlevel.tbl" in self.text(m) for m in result), "no Missing names it: %r" % (result,))

    def test_a_missing_folder_names_every_table(self):
        result = setup_check.check_table_folder(self.plant(table_folder="absent"))
        named = " ".join(self.text(m) for m in result)
        for name in TABLE_NAMES:
            self.assertIn(name.lower() + ".tbl", named, name + " is named")

    def test_the_expected_tables_are_the_indexs_not_a_fixed_list(self):
        machine = self.plant(index_tables=("Alpha", "Beta", "Gamma"), tables_missing=("Beta",))
        named = " ".join(self.text(m) for m in setup_check.check_table_folder(machine))
        self.assertIn("beta.tbl", named)
        self.assertNotIn("alpha", named)
        self.assertNotIn("creature2", named, "a table the planted index does not list is not expected")

    def test_a_folder_of_384_tables_passes_and_one_short_names_the_one(self):
        names = tuple("Table%03d" % number for number in range(384))
        self.assertEqual(setup_check.check_table_folder(self.plant(index_tables=names)), [])
        result = setup_check.check_table_folder(self.plant(index_tables=names, tables_missing=("Table200",)))
        named = " ".join(self.text(m) for m in result)
        self.assertIn("table200.tbl", named)
        for neighbour in ("table199.tbl", "table201.tbl"):
            self.assertNotIn(neighbour, named, "only the missing table is named")

    def test_the_folder_is_not_checked_where_genesis_no_client_is_1(self):
        machine = self.plant(with_client=False, no_client_flag=True)
        machine.env["GENESIS_TABLE_DIR"] = str(self.root / "no-tables-here")
        self.assertEqual(setup_check.check_all(machine), [])

    def test_an_index_that_cannot_be_read_is_left_to_the_client_check_and_does_not_crash(self):
        builds = (TARGET_BUILD, "garbage", TARGET_BUILD, TARGET_BUILD)
        machine = self.plant(index_builds=builds, table_folder="absent")
        self.assertIsInstance(setup_check.check_table_folder(machine), list)
        named = " ".join(self.text(m) for m in setup_check.check_all(machine))
        self.assertIn("clientdata.index", named, "the client check still names the index")


# ---------------------------------------------------------------- 7. the query process


class QueryProcessTest(PlantedTestCase):
    def test_a_ghidra_other_than_12_2_is_named_with_its_version_and_the_pin(self):
        missing = self.only(setup_check.check_query_process(self.plant(ghidra_version="12.1.4")))
        self.assert_part(missing, "ghidra")
        self.assert_found(missing, "12.1.4")
        self.assert_fix(missing, ghidra_env.GHIDRA_VERSION)

    def test_a_ghidra_without_the_macos_arm64_decompiler_is_named(self):
        missing = self.only(setup_check.check_query_process(self.plant(decompiler=False)))
        self.assertIn("decompiler", self.text(missing))
        self.assertTrue(missing.fix.strip())

    def test_a_jdk_other_than_25_is_named_with_its_version_and_the_pin(self):
        missing = self.only(setup_check.check_query_process(self.plant(jdk="21.0.4")))
        self.assert_part(missing, "jdk", "java")
        self.assert_found(missing, "21")
        self.assert_fix(missing, str(ghidra_env.JDK_MAJOR), "JAVA_HOME")

    def test_a_python_other_than_3_13_is_named_with_its_version_and_the_pin(self):
        missing = self.only(setup_check.check_query_process(self.plant(python=(3, 12, 4))))
        self.assert_part(missing, "python")
        self.assert_found(missing, "3.12")
        self.assert_fix(missing, "3.13")

    def test_a_pyghidra_other_than_3_2_0_or_not_installed_is_named_with_the_pin(self):
        for installed in ("3.1.0", None):
            with self.subTest(installed=installed):
                missing = self.only(setup_check.check_query_process(self.plant(pyghidra=installed)))
                self.assert_part(missing, "pyghidra")
                self.assert_fix(missing, ghidra_env.PYGHIDRA_VERSION)

    def test_a_missing_environment_variable_is_named_with_the_value_to_set(self):
        for name in ("GENESIS_GHIDRA_DIR", "GENESIS_GHIDRA_PROJECT_DIR", "WILDSTAR_CLIENT_EXE", "JAVA_HOME"):
            with self.subTest(variable=name):
                machine = self.plant(without_variables=(name,))
                missing = self.only(setup_check.check_query_process(machine))
                self.assertIn(name.lower(), self.text(missing))
                self.assertIn(name + "=", missing.fix)

    def test_an_unset_genesis_pyghidra_python_is_named_with_the_value_to_set(self):
        missing = self.only(setup_check.check_query_process(self.plant(pyghidra_python="unset")))
        self.assertIn("genesis_pyghidra_python", self.text(missing))
        self.assertIn("GENESIS_PYGHIDRA_PYTHON=", missing.fix)

    def test_a_genesis_pyghidra_python_that_cannot_run_is_named_with_its_variable(self):
        for kind in ("not_runnable", "absent"):
            with self.subTest(kind=kind):
                machine = self.plant(pyghidra_python=kind)
                missing = self.only(setup_check.check_query_process(machine))
                self.assertIn("genesis_pyghidra_python", self.text(missing))
                self.assertIn(machine.env["GENESIS_PYGHIDRA_PYTHON"], missing.part + missing.found)
                self.assertIn("GENESIS_PYGHIDRA_PYTHON", missing.fix)

    def test_a_project_path_with_a_folder_starting_with_a_dot_is_refused(self):
        # Ghidra refuses a path element starting with '.' (issue #13, found on #7).
        machine = self.plant(project_path=".genesis-prime/ghidra-project")
        missing = self.only(setup_check.check_query_process(machine))
        self.assertIn(machine.env["GENESIS_GHIDRA_PROJECT_DIR"], missing.part + missing.found)
        self.assert_fix(missing, "GENESIS_GHIDRA_PROJECT_DIR")

    def test_a_project_path_without_a_dot_folder_is_accepted(self):
        self.assertEqual(setup_check.check_query_process(self.plant()), [])

    def test_the_query_process_is_not_checked_where_genesis_no_client_is_1(self):
        machine = self.plant(
            no_client_flag=True, ghidra_version="12.1.4", pyghidra=None, pyghidra_python="unset"
        )
        self.assertEqual(setup_check.check_all(machine), [])


# ---------------------------------------------------------------- 8. several at once


class SeveralMissingTest(PlantedTestCase):
    def test_every_part_missing_at_once_is_named_not_only_the_first(self):
        machine = self.plant(
            gleam=None,
            otp="28.3.1",
            rebar=None,
            manifest_tracked=False,
            postgres_reachable=False,
            client="missing",
        )
        result = setup_check.check_all(machine)
        parts = [m.part.lower() for m in result]
        for words in (
            ("gleam",),
            ("erlang", "otp"),
            ("rebar",),
            ("manifest.toml",),
            ("postgres",),
            ("wildstar64.exe",),
        ):
            with self.subTest(part=words[0]):
                self.assertTrue(
                    any(any(w in p for w in words) for p in parts), "no Missing names %r in %r" % (words, parts)
                )
        for missing in result:
            with self.subTest(fix_of=missing.part):
                self.assertTrue(missing.fix.strip())


# ---------------------------------------------------------------- the entry point


class MainTest(unittest.TestCase):
    def run_main(self, result: list[Missing]) -> tuple[int, str]:
        output = io.StringIO()
        with mock.patch.object(setup_check, "check_all", lambda machine: result):
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                code = setup_check.main()
        return code, output.getvalue()

    def test_main_prints_one_pass_line_and_exits_0_when_nothing_is_missing(self):
        code, output = self.run_main([])
        self.assertEqual(code, 0)
        lines = [line for line in output.splitlines() if line.strip()]
        self.assertEqual(len(lines), 1, output)
        self.assertIn("setup check", lines[0].lower())
        self.assertIn("pass", lines[0].lower())

    def test_main_prints_every_missing_part_with_what_was_found_and_its_fix_and_exits_1(self):
        missing = [
            Missing("Gleam 1.19.2", "1.18.0", "mise install gleam@1.19.2"),
            Missing("Postgres 18", "nothing", "brew services start postgresql@18"),
        ]
        code, output = self.run_main(missing)
        self.assertEqual(code, 1)
        for each in missing:
            with self.subTest(part=each.part):
                for field in (each.part, each.found, each.fix):
                    self.assertIn(field, output)
        self.assertNotIn("pass", output.lower())


# ---------------------------------------------------------------- 9. the full check stops


CHECK = REPOSITORY / "check"
FULL_CHECK_RUNNABLE = bool(shutil.which("bash")) and bool(shutil.which("python3.13")) and os.access(CHECK, os.X_OK)


@unittest.skipUnless(FULL_CHECK_RUNNABLE, "the full check needs bash, python3.13 and an executable ./check here")
class FullCheckStopsTest(PlantedTestCase):
    PART_LINE = re.compile(
        r"^\s*(format|gleam-build|glinter|gleam-test|migrations|squirrel|client-suite|client-integration|fact-checker)\s+(ok|FAILED)\b",
        re.MULTILINE,
    )

    def test_the_full_check_stops_when_the_setup_check_fails_before_any_other_part_runs(self):
        # PATH holds python3.13 and bash and the system's tools, but no gleam, erl,
        # rebar3 or psql: the setup check fails, as on a machine missing them.
        tools = self.root / "tools"
        tools.mkdir()
        for name in ("python3.13", "bash"):
            (tools / name).symlink_to(shutil.which(name))
        home = self.root / "home"
        home.mkdir()
        env = {
            "PATH": "%s:/usr/bin:/bin:/usr/sbin:/sbin" % tools,
            "HOME": str(home),
            "GENESIS_HOME": str(home / ".genesis-prime"),
            "GENESIS_NO_CLIENT": "1",
        }
        done = subprocess.run(
            [str(CHECK)], cwd=REPOSITORY, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180
        )
        output = done.stdout + done.stderr
        self.assertNotEqual(done.returncode, 0, output)
        self.assertIn("setup check", output.lower(), output)
        self.assertIn("gleam", output.lower(), output)  # the missing part is named
        self.assertNotIn("check passed", output)
        self.assertEqual(self.PART_LINE.findall(output), [], "a part ran after the setup check failed:\n" + output)


if __name__ == "__main__":
    unittest.main()

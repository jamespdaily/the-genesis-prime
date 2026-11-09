"""setup_check: every part this machine needs is named, with what was found and its fix.

Every test plants a Machine: an `env` mapping, a temporary repository folder
and a `run` function that answers commands from a table, so no test touches the
real install.

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
- Postgres 18: Jim's choice ("with Postgres 18 as the version checked"); the
  clock tolerance is 1 second, the approved test list's.
- ICU: the character name index folds case under the collation "und-x-icu"
  (priv/migrations/0005_character_name_unique_in_icu.sql), which exists only in
  a Postgres built with ICU; the setup check refuses one without it (Jim's
  approved design for the name index).

What a planted command answers (the contract the checks run against):
- a missing tool answers (127, "command not found: NAME");
- `gleam ...` answers "gleam X.Y.Z"; `erl ...` answers the full OTP version
  alone ("29.1.2"); `rebar3 ...` answers "rebar 3.28.0 on Erlang/OTP 29 Erts 17.1.1";
- `git ... ls-files ...` answers the file's name when it is tracked; when it is
  not, `--error-unmatch` fails with exit 1 and without it the output is empty;
- `psql ...` answers each of the words server_version_num, server_version,
  epoch and und-x-icu found in the query, in the order they appear, joined by
  "|" (the clock as epoch seconds, plus or minus the planted offset; und-x-icu
  as "t" for a Postgres built with ICU and "f" for one without); an
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

import hashlib
import os
import re
import shutil
import struct
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
POSTGRES_MAJOR = "18"  # Jim's choice
PATCH_FILE = "otp-1b4ac11-clear-live-hf-end.patch"
MARKER = "GENESIS_PATCHES"

PATCH_SHA256 = hashlib.sha256((HERE / PATCH_FILE).read_bytes()).hexdigest()

SPAWN_TSV = b"id\tentity_type\n1\t0\n"
PATH_TSV = b"id\tspawn_id\n1\t1\n"
IMPORT_COMMAND = "gleam run -m genesis_prime/import_world_data"
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
    postgres_icu: bool = True
    postgres_clock_offset: float = 0.0  # seconds the server's clock is ahead
    with_client: bool = True  # False: nothing of the client, the query process or the patched OTP
    otp_without_client: bool = False  # with_client False, and still GENESIS_OTP_DIR and the build there (CI)
    no_client_flag: bool = False  # GENESIS_NO_CLIENT=1
    no_query_process_flag: bool = False  # GENESIS_NO_QUERY_PROCESS=1
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
    index_damage: str = "none"  # none, or directory: a good header and a damaged directory node
    # GENESIS_WORLD_DATA and the play database's content_import: absent (the variable unset), matching,
    # one_changed (spawn.tsv differs from the recorded hash), two_changed, missing_file (spawn_path.tsv
    # is listed and not in the folder) or no_record (the play database has no content_import table)
    world_data: str = "absent"


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
        if plan.no_query_process_flag:
            env["GENESIS_NO_QUERY_PROCESS"] = "1"
        if plan.with_client:
            env.update(self.plant_client(plan))
        elif plan.otp_without_client:
            env.update(self.plant_otp(plan))
        if plan.world_data != "absent":
            folder = self.root / "world-data"
            folder.mkdir(exist_ok=True)
            (folder / "spawn.tsv").write_bytes(SPAWN_TSV)
            if plan.world_data != "missing_file":
                (folder / "spawn_path.tsv").write_bytes(PATH_TSV)
            env["GENESIS_WORLD_DATA"] = str(folder)
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
        index = bytearray((planted.patch / "ClientData.index").read_bytes())
        if plan.index_damage == "directory":
            # Block 1 is the root directory node; its first u32 is the directory count.
            (offset, _size) = struct.unpack_from("<QQ", index, 0x240 + 16)
            index[offset : offset + 4] = struct.pack("<I", 0x00FFFFFF)
        return bytes(index)

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
        if "content_import" in query:
            if plan.world_data == "no_record":
                return 1, 'ERROR:  relation "content_import" does not exist\n'
            old = sha256(b"an older file")
            recorded = {
                "spawn.tsv": old if plan.world_data in ("one_changed", "two_changed") else sha256(SPAWN_TSV),
                "spawn_path.tsv": old if plan.world_data == "two_changed" else sha256(PATH_TSV),
            }
            return 0, "".join("%s|%s\n" % (file, recorded[file]) for file in sorted(recorded))
        words = {
            "server_version_num": _version_number(plan.postgres_version),
            "server_version": plan.postgres_version,
            "epoch": "%.3f" % (time.time() + plan.postgres_clock_offset),
            "und-x-icu": "t" if plan.postgres_icu else "f",
        }
        found = []
        for match in re.finditer(r"server_version_num|server_version|epoch|und-x-icu", query):
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
# The query process's variables other than the client's, which the client's own part needs too.
GHIDRA_VARIABLES = tuple(name for name in setup_check.QUERY_PROCESS_VARIABLES if name != "WILDSTAR_CLIENT_EXE")


class AllPresentTest(PlantedTestCase):
    def test_a_machine_with_every_part_right_has_nothing_missing(self):
        self.assertEqual(setup_check.check_all(self.plant()), [])

    def test_a_machine_without_the_client_and_not_marked_so_is_missing_the_client(self):
        result = setup_check.check_all(self.plant(with_client=False))
        self.assertTrue(
            any("wildstar64" in self.text(m) or "client" in m.part.lower() for m in result),
            "no Missing names the client: %r" % (result,),
        )

    def test_a_machine_marked_as_having_no_query_process_needs_no_ghidra_variable(self):
        self.assertEqual(setup_check.check_all(self.plant(no_query_process_flag=True, without_variables=GHIDRA_VARIABLES)), [])

    def test_a_machine_without_the_query_process_and_not_marked_so_is_missing_its_variables(self):
        result = setup_check.check_all(self.plant(without_variables=GHIDRA_VARIABLES))
        self.assertEqual(len(result), len(GHIDRA_VARIABLES), result)

    def test_a_machine_marked_as_having_no_query_process_still_needs_the_client(self):
        result = setup_check.check_all(self.plant(no_query_process_flag=True, client="missing"))
        self.assertTrue(any("wildstar64" in self.text(m) for m in result), "no Missing names the client: %r" % (result,))


class GleamTest(PlantedTestCase):
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


class ErlangTest(PlantedTestCase):
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

    def test_a_patched_otp_built_from_an_older_patch_asks_for_a_rebuild(self):
        # the line for the patch holds another SHA-256 than the file in setup_check/
        missing = self.only(setup_check.check_erlang(self.plant(otp_dir="stale")))
        self.assert_part(missing, "patch")
        self.assertIn(PATCH_FILE, missing.part + missing.found)
        self.assert_fix(missing, "rebuild")


class PostgresTest(PlantedTestCase):
    def test_a_reachable_postgres_of_major_version_17_is_named_with_what_was_found(self):
        missing = self.only(setup_check.check_postgres(self.plant(postgres_version="17.5")))
        self.assert_part(missing, "postgres")
        self.assertIn(POSTGRES_MAJOR, missing.part)
        self.assert_found(missing, "17")
        self.assert_fix(missing, POSTGRES_MAJOR)

    def test_a_postgres_built_without_icu_is_named_with_what_to_run_instead(self):
        missing = self.only(setup_check.check_postgres(self.plant(postgres_icu=False)))
        self.assert_part(missing, "icu")
        self.assert_found(missing, "und-x-icu")
        self.assert_fix(missing, "ICU")


class WorldDataTest(PlantedTestCase):
    """The setup check compares the world database's files with what the play
    database imported.

    Expected values: the design of the world spawns (the Design artifact of issue
    375, section 1): for each file listed in the play database's content_import, the
    file in GENESIS_WORLD_DATA has the SHA-256 recorded; a file that differs is named
    on a line of its own with the import command as the fix; the check runs only
    where GENESIS_WORLD_DATA is set. The planted files are spawn.tsv and
    spawn_path.tsv, each with its hash in the planted content_import."""

    def test_matching_hashes_and_an_unset_variable_pass(self):
        self.assertEqual(setup_check.check_world_data(self.plant(world_data="matching")), [])
        self.assertEqual(setup_check.check_world_data(self.plant(world_data="absent")), [])

    def test_a_file_that_differs_from_the_recorded_hash_is_named_with_the_import_command(self):
        missing = self.only(setup_check.check_world_data(self.plant(world_data="one_changed")))
        self.assert_part(missing, "spawn.tsv")
        self.assertNotIn("spawn_path", self.text(missing))
        self.assert_found(missing, sha256(SPAWN_TSV)[:12])
        self.assert_found(missing, sha256(b"an older file")[:12])
        self.assert_fix(missing, IMPORT_COMMAND)

    def test_each_file_that_differs_is_named_on_a_line_of_its_own(self):
        result = setup_check.check_world_data(self.plant(world_data="two_changed"))
        self.assertEqual(len(result), 2, "one Missing for each differing file")
        self.assert_part(result[0], "spawn.tsv")
        self.assert_part(result[1], "spawn_path.tsv")
        for missing in result:
            self.assert_fix(missing, IMPORT_COMMAND)

    def test_a_listed_file_that_is_not_in_the_folder_is_named(self):
        missing = self.only(setup_check.check_world_data(self.plant(world_data="missing_file")))
        self.assert_part(missing, "spawn_path.tsv")
        self.assert_found(missing, "no file")

    def test_a_play_database_with_no_content_import_lists_nothing(self):
        self.assertEqual(setup_check.check_world_data(self.plant(world_data="no_record")), [])

    def test_the_whole_check_runs_it(self):
        result = setup_check.check_all(self.plant(world_data="one_changed"))
        self.assertEqual(len([m for m in result if "spawn.tsv" in m.part]), 1)


class TableFolderTest(PlantedTestCase):
    """The setup check checks the table folder holds every
    table of the client's index.

    Expected values: the tables are the files directly in DB/ ending in .tbl of
    the planted ClientData.index (the layout extract_tables documents: 384 for
    the client, fact file game_tables.ClientData); a name is missing when the
    folder holds no file of it."""

    def test_a_folder_missing_tables_names_each_one_and_no_other(self):
        machine = self.plant(tables_missing=("World", "Spell4"))
        result = setup_check.check_table_folder(machine)
        self.assertTrue(result, "a folder missing two tables passes")
        named = " ".join(self.text(m) for m in result)
        for name in ("World", "Spell4"):
            self.assertIn(name.lower() + ".tbl", named, name + " is named")
        for name in ("Creature2", "XpPerLevel", "CharacterCreation"):
            self.assertNotIn(name.lower(), named, name + " is there and is not named")

    def test_a_missing_folder_names_every_table(self):
        result = setup_check.check_table_folder(self.plant(table_folder="absent"))
        named = " ".join(self.text(m) for m in result)
        for name in TABLE_NAMES:
            self.assertIn(name.lower() + ".tbl", named, name + " is named")


if __name__ == "__main__":
    unittest.main()

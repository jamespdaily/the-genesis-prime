"""Tests of the play service (dev/play_service): the updater, the stop and start scripts, the image
check, and session.sh's stop and start of the play server's container.

Each case runs the real script with a planted `podman`, `git`, `gh`, `lsof` and `psql` first on PATH.
A planted program appends each call to one log (plant/calls.log) and answers from files in plant/, so
a case plants what GitHub, Podman and the folders say, runs the script, and reads what it called and
in what order. Expected values come from these places.
- The design's rules for the updater: a new commit whose server check run (the `check` job of
  .github/workflows/check.yml) finished well is built, migrated and deployed, whatever became of
  the docs workflow's jobs (`build` and `publish` of .github/workflows/docs.yml); a red,
  unfinished, missing or unknown server check does nothing; the same commit does
  nothing; an address change replaces the container without a build; a held live lock skips
  everything; the server's container is not started until Postgres answers.
- GitHub's check-runs answer: a run has a status and a conclusion, and a conclusion is null until
  the run has completed (docs.github.com, "List check runs for a Git reference").
- SHA-256 of a file's bytes, which the tests compute with Python's hashlib, never with the scripts'
  own tools.
"""

import atexit
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
REPOSITORY = os.path.abspath(os.path.join(SCRIPTS, "..", "..", "..", ".."))
PLAY_SERVICE = os.path.join(REPOSITORY, "dev", "play_service")
SESSION = os.path.join(SCRIPTS, "session.sh")
RUNNABLE = shutil.which("jq") is not None and os.path.exists("/bin/bash")

NEW_COMMIT = "a" * 40
OLD_COMMIT = "b" * 40

PODMAN = r"""#!/bin/bash
# A planted podman: logs each call and answers from the files in $PLANT.
echo "podman $*" >> "$PLANT/calls.log"
case "$1 $2" in
  "info "*) exit "$(cat "$PLANT/info_status" 2>/dev/null || echo 0)" ;;
  "network exists") exit 0 ;;
  "container exists") [ -e "$PLANT/exists_$3" ]; exit $? ;;
  "container inspect")
    name=${@: -1}
    case "$*" in
      *RestartCount*) cat "$PLANT/server_status" 2>/dev/null || echo "running 0 0" ;;
      *genesis.revision*) cat "$PLANT/server_state" 2>/dev/null ;;
      *) if [ -e "$PLANT/running_$name" ]; then echo true; else echo false; fi ;;
    esac
    exit 0 ;;
  "image exists") [ -e "$PLANT/image_$3" ]; exit $? ;;
  "image prune") exit 0 ;;
  "images "*) cat "$PLANT/images_list" 2>/dev/null; exit 0 ;;
  "rmi "*) exit 0 ;;
  "logs "*) cat "$PLANT/server_log" 2>/dev/null; exit 0 ;;
  "exec "*)
    refused=$(cat "$PLANT/pg_isready_refusals" 2>/dev/null || echo 0)
    if [ "$refused" -gt 0 ]; then
      echo $((refused - 1)) > "$PLANT/pg_isready_refusals"
      echo "pg_isready refused" >> "$PLANT/calls.log"
      exit 2
    fi
    echo "pg_isready answered" >> "$PLANT/calls.log"
    exit 0 ;;
  "stop "*) rm -f "$PLANT/running_${@: -1}"; exit 0 ;;
  "start "*) : > "$PLANT/running_$2"; exit 0 ;;
  "build "*) exit "$(cat "$PLANT/build_status" 2>/dev/null || echo 0)" ;;
esac
case "$*" in
  *"run -d --replace --name genesis-play "*)
    if [ -e "$PLANT/crash_${@: -1}" ]; then
      echo "exited 1 5" > "$PLANT/server_status"
      echo "panic: planted crash" > "$PLANT/server_log"
    else
      rm -f "$PLANT/server_status"
      echo "the server loaded 46 game tables and serves the STS login on port 6600" > "$PLANT/server_log"
    fi
    exit 0 ;;
  *"--entrypoint /bin/sh"*) cat "$PLANT/image_files" 2>/dev/null; exit 0 ;;
  *"--entrypoint /migrate/dev/apply_migrations.sh"*) exit "$(cat "$PLANT/migrate_status" 2>/dev/null || echo 0)" ;;
esac
exit 0
"""

GIT = r"""#!/bin/bash
# A planted git for the updater's calls; any other call is the real git's.
case "$1" in
  ls-remote)
    echo "git $*" >> "$PLANT/calls.log"
    [ ! -e "$PLANT/ls_remote_fails" ] || exit 128
    printf '%s\trefs/heads/main\n' "$(cat "$PLANT/main_commit")"
    exit 0 ;;
  clone) echo "git $*" >> "$PLANT/calls.log"; mkdir -p "${@: -1}"; exit 0 ;;
  -C)
    echo "git $*" >> "$PLANT/calls.log"
    case "$3" in
      archive) tar -cf - -C "$PLANT/archive" . ;;
    esac
    exit 0 ;;
esac
exec /usr/bin/git "$@"
"""

GH = r"""#!/bin/bash
# A planted gh: a token, and a commit's check runs from plant/checks_<commit>.json.
echo "gh $*" >> "$PLANT/calls.log"
case "$1 $2" in
  "auth token") echo planted-token; exit 0 ;;
  "api repos/"*)
    commit=$(echo "$2" | sed -E 's#^repos/[^/]+/[^/]+/commits/([^/]+)/check-runs$#\1#')
    [ -e "$PLANT/checks_$commit.json" ] || exit 1
    jq -r "$4" < "$PLANT/checks_$commit.json"
    exit 0 ;;
esac
exit 1
"""

LSOF = r"""#!/bin/bash
echo "lsof $*" >> "$PLANT/calls.log"
[ -e "$PLANT/ports_held" ] && { echo "beam.smp 1 jimd TCP *:24000 (LISTEN)"; exit 0; }
exit 1
"""

PSQL = r"""#!/bin/bash
echo "psql [$PGHOST:$PGPORT as $PGPASSWORD] $*" >> "$PLANT/calls.log"
case "$*" in
  *"count(*)"*) echo 0; exit 0 ;;
  *"CREATE DATABASE"*) echo "ERROR: planted failure" >&2; exit 1 ;;
esac
exit 0
"""


def checks(*runs: tuple) -> str:
    """A check-runs answer of GitHub's for runs given as (status, conclusion) or (status, conclusion,
    name); a run with no name is the server's own, the `check` job of .github/workflows/check.yml."""
    return json.dumps(
        {
            "total_count": len(runs),
            "check_runs": [
                {"name": run[2] if len(run) > 2 else "check", "status": run[0], "conclusion": run[1]}
                for run in runs
            ],
        }
    )


def planted_programs(podman: str = PODMAN) -> str:
    """A new folder holding the planted programs, which a case may put first on PATH."""
    folder = tempfile.mkdtemp(prefix="play-service-bin-")
    atexit.register(shutil.rmtree, folder, ignore_errors=True)
    for name, text in (("podman", podman), ("git", GIT), ("gh", GH), ("lsof", LSOF), ("psql", PSQL)):
        path = os.path.join(folder, name)
        with open(path, "w") as file:
            file.write(text)
        os.chmod(path, 0o755)
    return folder


_SHARED_PROGRAMS: list[str] = []


def shared_programs() -> str:
    """The planted programs, written once for the module: a program written a moment ago is slow to
    run the first time on a Mac, so each case does not write its own."""
    if not _SHARED_PROGRAMS:
        _SHARED_PROGRAMS.append(planted_programs())
    return _SHARED_PROGRAMS[0]


class Planted:
    """One case's world: the planted programs, the answers, the machine's home folder."""

    def __init__(self, test: unittest.TestCase):
        self.root = tempfile.mkdtemp(prefix="play-service-test-")
        test.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.plant = os.path.join(self.root, "plant")
        self.home = os.path.join(self.root, "home")
        self.state = os.path.join(self.home, "play-service")
        self.bin = shared_programs()
        for folder in (self.plant, self.state, os.path.join(self.plant, "archive"),
                       os.path.join(self.home, "tables")):
            os.makedirs(folder)
        self.write(
            os.path.join(self.home, "env.sh"),
            "export GENESIS_PLAY_ADDRESS=10.0.0.5 GENESIS_PLAY_ACCOUNT=genesis GENESIS_PLAY_PGPASSWORD=secret\n",
        )
        self.write(
            os.path.join(self.state, "config.sh"),
            "remote='https://example.invalid/owner/name.git'\nrepository='owner/name'\n",
        )
        self.write(os.path.join(self.home, "tables", "Spell4.tbl"), "table bytes of the client")
        os.makedirs(os.path.join(self.plant, "archive", "release"))
        self.write(os.path.join(self.plant, "archive", "release", "Containerfile"), "FROM scratch\n")
        self.touch("exists_genesis-play-postgres")
        self.touch("running_genesis-play-postgres")
        self.set("main_commit", NEW_COMMIT)
        self.set("image_files", "0" * 64 + "  /usr/bin/bash\n")

    @staticmethod
    def write(path: str, text: str, executable: bool = False) -> None:
        with open(path, "w") as file:
            file.write(text)
        if executable:
            os.chmod(path, 0o755)

    def set(self, name: str, text: str) -> None:
        self.write(os.path.join(self.plant, name), text)

    def touch(self, name: str) -> None:
        self.set(name, "")

    def environment(self) -> dict:
        return {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": self.root,
            "GENESIS_HOME": self.home,
            "PLANT": self.plant,
            "GENESIS_PLAY_POLL_SECONDS": "0",
            "GENESIS_NO_CLIENT": "1",
        }

    def run(self, *command: str, timeout: int = 60) -> subprocess.CompletedProcess:
        return subprocess.run(
            list(command), env=self.environment(), capture_output=True, text=True, timeout=timeout
        )

    def update(self, script: str | None = None) -> subprocess.CompletedProcess:
        return self.run("/bin/bash", script or os.path.join(PLAY_SERVICE, "update.sh"))

    def log_text(self) -> str:
        try:
            with open(os.path.join(self.home, "play-service.log")) as file:
                return file.read()
        except FileNotFoundError:
            return ""

    def calls(self) -> list[str]:
        try:
            with open(os.path.join(self.plant, "calls.log")) as file:
                return file.read().splitlines()
        except FileNotFoundError:
            return []

    def index_of(self, prefix: str, start: int = 0) -> int:
        """The index of the first call that starts with `prefix`, from `start`; -1 when none."""
        for index, line in enumerate(self.calls()):
            if index >= start and line.startswith(prefix):
                return index
        return -1

    def server_runs(self) -> list[str]:
        return [line for line in self.calls() if line.startswith("podman run -d --replace --name genesis-play ")]


def deployed(planted: Planted, commit: str, address: str = "10.0.0.5", running: str = "true") -> None:
    planted.set("server_state", f"{commit} {address} {running}\n")
    planted.touch("exists_genesis-play")


@unittest.skipUnless(RUNNABLE, "the updater's test needs bash and jq")
class UpdaterTest(unittest.TestCase):
    def setUp(self):
        self.planted = Planted(self)

    def green(self, commit: str = NEW_COMMIT) -> None:
        self.planted.set(f"checks_{commit}.json", checks(("completed", "success")))

    def assert_nothing_built_migrated_or_replaced(self):
        calls = self.planted.calls()
        self.assertEqual([c for c in calls if c.startswith("podman build")], [], calls)
        self.assertEqual([c for c in calls if "apply_migrations" in c], [], calls)
        self.assertEqual(self.planted.server_runs(), [], calls)

    def test_a_new_commit_whose_check_passed_is_built_migrated_and_the_server_replaced_in_that_order(self):
        self.green()
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        calls = self.planted.calls()
        build = self.planted.index_of("podman build")
        listing = self.planted.index_of("podman run --rm --entrypoint /bin/sh genesis-play:" + NEW_COMMIT)
        migrate = self.planted.index_of("podman run --rm --network genesis-play")
        replace = self.planted.index_of("podman run -d --replace --name genesis-play ")
        self.assertTrue(0 <= build < listing < migrate < replace, calls)
        self.assertIn(f"-t genesis-play:{NEW_COMMIT}", calls[build])
        self.assertIn(f"--build-arg REVISION={NEW_COMMIT}", calls[build])
        self.assertNotIn("--secret", calls[build], "the build holds no GitHub login")
        self.assertEqual([c for c in calls if c.startswith("gh auth")], [], "no token is asked for")
        self.assertIn(f"genesis-play:{NEW_COMMIT} genesis_play", calls[migrate])
        self.assertIn("--entrypoint /migrate/dev/apply_migrations.sh", calls[migrate])
        server = calls[replace]
        for expected in (
            "--restart=on-failure:5", "--memory 3g", "-p 6600:6600", "-p 23115:23115", "-p 24000:24000",
            "-v " + os.path.join(self.planted.home, "tables") + ":/tables:ro",
            f"--label genesis.revision={NEW_COMMIT}", "--label genesis.address=10.0.0.5",
            "-e GENESIS_GAME_ADDRESS=10.0.0.5", "-e PGHOST=genesis-play-postgres", "-e PGPASSWORD ",
            "--network genesis-play",
        ):
            self.assertIn(expected, server)
        self.assertTrue(server.endswith(f"genesis-play:{NEW_COMMIT}"), server)
        self.assertNotIn("secret", server, "the password reaches the container by the environment, not the command line")

    def test_a_commit_whose_check_failed_does_nothing(self):
        self.planted.set(f"checks_{NEW_COMMIT}.json", checks(("completed", "failure")))
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_commit_whose_check_has_not_finished_does_nothing(self):
        self.planted.set(f"checks_{NEW_COMMIT}.json", checks(("in_progress", None)))
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_commit_with_one_red_check_among_green_ones_does_nothing(self):
        self.planted.set(f"checks_{NEW_COMMIT}.json", checks(("completed", "success"), ("completed", "failure")))
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_commit_whose_server_check_passed_is_deployed_though_the_docs_publish_was_cancelled(self):
        self.planted.set(
            f"checks_{NEW_COMMIT}.json",
            checks(("completed", "success"), ("completed", "success", "build"), ("completed", "cancelled", "publish")),
        )
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(self.planted.server_runs()), 1, self.planted.calls())

    def test_a_commit_whose_server_check_failed_does_nothing_though_the_docs_jobs_passed(self):
        self.planted.set(
            f"checks_{NEW_COMMIT}.json",
            checks(("completed", "failure"), ("completed", "success", "build"), ("completed", "success", "publish")),
        )
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_commit_whose_server_check_has_not_finished_does_nothing_though_the_docs_jobs_passed(self):
        self.planted.set(
            f"checks_{NEW_COMMIT}.json",
            checks(("in_progress", None), ("completed", "success", "build"), ("completed", "success", "publish")),
        )
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_commit_with_docs_check_runs_but_no_server_check_run_does_nothing(self):
        self.planted.set(
            f"checks_{NEW_COMMIT}.json",
            checks(("completed", "success", "build"), ("completed", "success", "publish")),
        )
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_commit_with_no_check_run_yet_does_nothing(self):
        self.planted.set(f"checks_{NEW_COMMIT}.json", checks())
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_commit_whose_checks_cannot_be_asked_for_does_nothing(self):
        # No planted answer: the planted gh fails, as it does with GitHub unreachable.
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_the_branch_the_config_names_is_the_one_followed_and_main_when_it_names_none(self):
        self.planted.update()
        self.assertGreaterEqual(self.planted.index_of("git ls-remote https://example.invalid/owner/name.git refs/heads/main"), 0)
        Planted.write(
            os.path.join(self.planted.state, "config.sh"),
            "remote='https://example.invalid/owner/name.git'\nrepository='owner/name'\nbranch='feature'\n",
        )
        os.makedirs(os.path.join(self.planted.state, "repository.git"))
        self.green()
        self.planted.update()
        self.assertGreaterEqual(self.planted.index_of("git ls-remote https://example.invalid/owner/name.git refs/heads/feature"), 0)
        fetch = self.planted.index_of("git -C ")
        self.assertIn("+refs/heads/feature:refs/heads/feature", self.planted.calls()[fetch])

    def test_a_commit_with_no_containerfile_is_left_alone_and_not_asked_about_again(self):
        self.green()
        os.remove(os.path.join(self.planted.plant, "archive", "release", "Containerfile"))
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()
        asked = len([c for c in self.planted.calls() if c.startswith("gh api")])
        self.assertEqual(self.planted.update().returncode, 0)
        self.assertEqual(len([c for c in self.planted.calls() if c.startswith("gh api")]), asked, "no second question to GitHub")
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_new_image_that_exits_is_replaced_by_the_last_good_one_and_the_log_says_why(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        self.planted.touch(f"image_genesis-play:{OLD_COMMIT}")
        self.planted.touch(f"crash_genesis-play:{NEW_COMMIT}")
        done = self.planted.update()
        self.assertEqual(done.returncode, 1, done.stderr)
        runs = self.planted.server_runs()
        self.assertEqual(len(runs), 2, self.planted.calls())
        self.assertTrue(runs[0].endswith(f"genesis-play:{NEW_COMMIT}"), runs[0])
        self.assertTrue(runs[1].endswith(f"genesis-play:{OLD_COMMIT}"), runs[1])
        self.assertIn(f"--label genesis.revision={OLD_COMMIT}", runs[1])
        log = self.planted.log_text()
        self.assertIn(f"{NEW_COMMIT} did not come up", log)
        self.assertIn("exit code 1", log)
        self.assertIn("panic: planted crash", log, "the container's last lines are in the log")
        self.assertIn(f"putting back {OLD_COMMIT}", log)
        self.assertIn(f"{OLD_COMMIT} is back up", log)

    def test_a_commit_that_did_not_come_up_is_not_tried_again(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        self.planted.touch(f"image_genesis-play:{OLD_COMMIT}")
        self.planted.touch(f"crash_genesis-play:{NEW_COMMIT}")
        self.planted.update()
        runs_before = len(self.planted.server_runs())
        deployed(self.planted, OLD_COMMIT)
        again = self.planted.update()
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(len(self.planted.server_runs()), runs_before, "no second deploy of the failed commit")

    def test_a_new_image_that_exits_with_no_earlier_revision_to_put_back_is_logged_and_left(self):
        self.green()
        self.planted.touch(f"crash_genesis-play:{NEW_COMMIT}")
        done = self.planted.update()
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertEqual(len(self.planted.server_runs()), 1, self.planted.calls())
        self.assertIn("no earlier revision came up to put back", self.planted.log_text())

    def test_a_container_that_restarts_itself_after_a_crash_does_not_count_as_up(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        self.planted.touch(f"image_genesis-play:{OLD_COMMIT}")
        # The restart policy brought it back: it runs, but has restarted and says no ready line.
        self.planted.bin = planted_programs(
            PODMAN.replace('echo "exited 1 5"', 'echo "running 1 2"')
        )
        self.planted.touch(f"crash_genesis-play:{NEW_COMMIT}")
        done = self.planted.update()
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("restarted 2 times", self.planted.log_text())

    def test_a_server_that_says_no_ready_line_in_time_is_not_up(self):
        self.green()
        env = self.planted.environment()
        env["GENESIS_PLAY_UP_ATTEMPTS"] = "3"
        self.planted.bin = planted_programs(
            PODMAN.replace('echo "the server loaded 46 game tables and serves the STS login on port 6600"', 'echo "loading"')
        )
        env["PATH"] = f"{self.planted.bin}:/usr/bin:/bin"
        done = subprocess.run(
            ["/bin/bash", os.path.join(PLAY_SERVICE, "update.sh")], env=env, capture_output=True, text=True, timeout=60
        )
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("said no ready line in 3 asks", self.planted.log_text())

    def test_a_deploy_that_came_up_removes_dangling_images_and_every_image_but_the_running_and_the_last_good(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        self.planted.touch(f"image_genesis-play:{OLD_COMMIT}")
        self.planted.set(
            "images_list",
            "\n".join(f"localhost/genesis-play:{tag}" for tag in (NEW_COMMIT, OLD_COMMIT, "c" * 40, "trial-1")) + "\n",
        )
        self.assertEqual(self.planted.update().returncode, 0)
        calls = self.planted.calls()
        self.assertGreaterEqual(self.planted.index_of("podman image prune --force"), 0, calls)
        removed = [c for c in calls if c.startswith("podman rmi ")]
        self.assertCountEqual(
            removed,
            [f"podman rmi localhost/genesis-play:{tag}" for tag in (OLD_COMMIT, "c" * 40, "trial-1")],
            "the commit running and the last good one (the same, once it came up) stay",
        )
        self.assertGreater(self.planted.index_of("podman rmi"), self.planted.index_of("podman run -d --replace"))

    def test_nothing_is_pruned_when_the_new_image_did_not_come_up_until_the_old_one_is_back(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        self.planted.touch(f"image_genesis-play:{OLD_COMMIT}")
        self.planted.touch(f"crash_genesis-play:{NEW_COMMIT}")
        self.planted.set(
            "images_list",
            "\n".join(f"localhost/genesis-play:{tag}" for tag in (NEW_COMMIT, OLD_COMMIT)) + "\n",
        )
        self.planted.update()
        removed = [c for c in self.planted.calls() if c.startswith("podman rmi ")]
        self.assertEqual(removed, [f"podman rmi localhost/genesis-play:{NEW_COMMIT}"], "only the failed image goes, after the old one is back")

    def test_a_changed_address_whose_container_does_not_come_up_fails_the_update_and_says_so(self):
        deployed(self.planted, OLD_COMMIT, address="10.0.0.4")
        self.planted.set("main_commit", OLD_COMMIT)
        self.planted.touch(f"crash_genesis-play:{OLD_COMMIT}")
        done = self.planted.update()
        self.assertEqual(done.returncode, 1, done.stderr)
        self.assertIn("did not come up", self.planted.log_text())

    def test_the_same_decision_is_written_to_the_log_once_however_many_runs_make_it(self):
        self.planted.set(f"checks_{NEW_COMMIT}.json", checks(("in_progress", None)))
        for _ in range(3):
            self.assertEqual(self.planted.update().returncode, 0)
        waiting = [line for line in self.planted.log_text().splitlines() if "has not passed or has not finished" in line]
        self.assertEqual(len(waiting), 1, self.planted.log_text())
        self.green()
        self.assertEqual(self.planted.update().returncode, 0)
        self.assertIn("building", self.planted.log_text(), "a new decision is written")

    def test_a_held_live_lock_is_written_to_the_log_once_across_runs(self):
        os.makedirs(os.path.join(self.planted.home, "live.lock"))
        for _ in range(3):
            self.planted.update()
        self.assertEqual(self.planted.log_text().count("a live session holds"), 1, self.planted.log_text())

    def test_a_main_that_cannot_be_read_does_nothing(self):
        self.green()
        self.planted.touch("ls_remote_fails")
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()

    def test_the_commit_already_deployed_does_nothing(self):
        self.green()
        deployed(self.planted, NEW_COMMIT)
        self.assertEqual(self.planted.update().returncode, 0)
        self.assert_nothing_built_migrated_or_replaced()
        self.assertEqual([c for c in self.planted.calls() if c.startswith("gh ")], [], "no GitHub question for a commit already running")

    def test_a_changed_address_replaces_the_server_with_the_image_it_runs_and_no_build(self):
        deployed(self.planted, OLD_COMMIT, address="10.0.0.4")
        self.planted.set("main_commit", OLD_COMMIT)
        self.assertEqual(self.planted.update().returncode, 0)
        calls = self.planted.calls()
        self.assertEqual([c for c in calls if c.startswith("podman build")], [], calls)
        self.assertEqual([c for c in calls if "apply_migrations" in c], [], calls)
        runs = self.planted.server_runs()
        self.assertEqual(len(runs), 1, calls)
        self.assertIn("--label genesis.address=10.0.0.5", runs[0])
        self.assertIn("-e GENESIS_GAME_ADDRESS=10.0.0.5", runs[0])
        self.assertTrue(runs[0].endswith(f"genesis-play:{OLD_COMMIT}"), runs[0])

    def test_a_server_container_that_is_not_running_is_started_again_on_the_image_it_has(self):
        deployed(self.planted, OLD_COMMIT, running="false")
        self.planted.set("main_commit", OLD_COMMIT)
        self.assertEqual(self.planted.update().returncode, 0)
        runs = self.planted.server_runs()
        self.assertEqual(len(runs), 1, self.planted.calls())
        self.assertTrue(runs[0].endswith(f"genesis-play:{OLD_COMMIT}"), runs[0])

    def test_a_new_green_commit_and_a_changed_address_replace_the_server_once_with_both(self):
        self.green()
        deployed(self.planted, OLD_COMMIT, address="10.0.0.4")
        self.assertEqual(self.planted.update().returncode, 0)
        runs = self.planted.server_runs()
        self.assertEqual(len(runs), 1, self.planted.calls())
        self.assertIn("--label genesis.address=10.0.0.5", runs[0])
        self.assertTrue(runs[0].endswith(f"genesis-play:{NEW_COMMIT}"), runs[0])

    def test_a_held_live_lock_skips_everything(self):
        self.green()
        os.makedirs(os.path.join(self.planted.home, "live.lock"))
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.planted.calls(), [], "no call to Podman, git or GitHub while a live session holds the lock")
        self.assertIn("live.lock", self.planted.log_text())
        self.assertEqual(done.stdout, "", "a line is written to the log only, which is not standard output off a terminal")

    def test_a_live_lock_taken_during_the_build_leaves_the_server_unreplaced(self):
        self.green()
        # The planted build takes the lock, as a session that starts meanwhile does.
        self.planted.bin = planted_programs(
            PODMAN.replace('"build "*) exit', '"build "*) mkdir -p "$GENESIS_HOME/live.lock"; exit')
        )
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.planted.server_runs(), [], self.planted.calls())
        self.assertEqual([c for c in self.planted.calls() if "apply_migrations" in c], [], "nothing is migrated while a session holds the lock")

    def test_a_live_lock_taken_during_the_migration_leaves_the_server_unreplaced(self):
        self.green()
        self.planted.bin = planted_programs(
            PODMAN.replace(
                '*"--entrypoint /migrate/dev/apply_migrations.sh"*) exit',
                '*"--entrypoint /migrate/dev/apply_migrations.sh"*) mkdir -p "$GENESIS_HOME/live.lock"; exit',
            )
        )
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertGreaterEqual(self.planted.index_of("podman run --rm --network genesis-play"), 0, "the migration ran")
        self.assertEqual(self.planted.server_runs(), [], self.planted.calls())

    def test_a_held_service_skips_everything(self):
        self.green()
        Planted.write(os.path.join(self.planted.state, "held"), "")
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.planted.calls(), [])

    def test_a_second_update_at_the_same_time_does_nothing(self):
        self.green()
        lock = os.path.join(self.planted.state, "update.lock")
        os.makedirs(lock)
        Planted.write(os.path.join(lock, "owner"), str(os.getpid()))
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.planted.calls(), [])

    def test_an_update_lock_with_no_owner_yet_is_held_for_a_minute_and_then_taken_over(self):
        self.green()
        lock = os.path.join(self.planted.state, "update.lock")
        os.makedirs(lock)
        young = self.planted.update()
        self.assertEqual(young.returncode, 0, young.stderr)
        self.assertEqual(self.planted.calls(), [], "its taker may still be writing the owner")
        old = __import__("time").time() - 120
        os.utime(lock, (old, old))
        self.assertEqual(self.planted.update().returncode, 0)
        self.assertEqual(len(self.planted.server_runs()), 1, self.planted.calls())

    def test_a_second_run_cannot_take_over_while_a_takeover_is_going(self):
        self.green()
        lock = os.path.join(self.planted.state, "update.lock")
        os.makedirs(lock)
        Planted.write(os.path.join(lock, "owner"), "999999")
        os.makedirs(lock + ".takeover")
        done = self.planted.update()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.planted.calls(), [], "another run is taking the stale lock over")

    def test_an_update_lock_whose_owner_is_gone_is_taken_over(self):
        self.green()
        lock = os.path.join(self.planted.state, "update.lock")
        os.makedirs(lock)
        gone = subprocess.Popen(["/bin/sh", "-c", "exit 0"])
        gone.wait()
        Planted.write(os.path.join(lock, "owner"), str(gone.pid))
        self.assertEqual(self.planted.update().returncode, 0)
        self.assertEqual(len(self.planted.server_runs()), 1, self.planted.calls())

    def test_the_server_container_is_not_started_until_postgres_answers(self):
        self.green()
        self.planted.set("pg_isready_refusals", "3")
        self.assertEqual(self.planted.update().returncode, 0)
        calls = self.planted.calls()
        refused = self.planted.index_of("pg_isready refused")
        answered = self.planted.index_of("pg_isready answered")
        replace = self.planted.index_of("podman run -d --replace --name genesis-play ")
        migrate = self.planted.index_of("podman run --rm --network genesis-play")
        self.assertTrue(0 <= refused < answered < migrate < replace, calls)

    def test_postgres_that_never_answers_ends_the_update_with_nothing_started(self):
        self.green()
        self.planted.set("pg_isready_refusals", "100000")
        env = self.planted.environment()
        env["GENESIS_PLAY_POSTGRES_ATTEMPTS"] = "3"
        # The wait gives up after 3 refusals, which the planted pg_isready gives at once.
        done = subprocess.run(
            ["/bin/bash", os.path.join(PLAY_SERVICE, "update.sh")], env=env, capture_output=True, text=True, timeout=60
        )
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assert_nothing_built_migrated_or_replaced()

    def test_a_postgres_container_that_does_not_exist_is_made_with_its_volume_and_loopback_port(self):
        self.green()
        os.remove(os.path.join(self.planted.plant, "exists_genesis-play-postgres"))
        self.assertEqual(self.planted.update().returncode, 0)
        made = self.planted.index_of("podman run -d --name genesis-play-postgres ")
        self.assertGreaterEqual(made, 0, self.planted.calls())
        line = self.planted.calls()[made]
        for expected in (
            "--network genesis-play", "-v genesis-play-data:/var/lib/postgresql", "-p 127.0.0.1:5434:5432",
            "-e POSTGRES_PASSWORD", "-e POSTGRES_DB=genesis_play",
        ):
            self.assertIn(expected, line)
        self.assertTrue(line.endswith("docker.io/library/postgres:18"), "the major version is pinned: " + line)
        self.assertLess(made, self.planted.index_of("podman run -d --replace --name genesis-play "))

    def test_a_stopped_postgres_container_is_started_before_anything_else(self):
        self.green()
        os.remove(os.path.join(self.planted.plant, "running_genesis-play-postgres"))
        self.assertEqual(self.planted.update().returncode, 0)
        started = self.planted.index_of("podman start genesis-play-postgres")
        self.assertGreaterEqual(started, 0, self.planted.calls())
        self.assertLess(started, self.planted.index_of("podman build"))

    def test_a_build_that_fails_leaves_the_server_as_it_was_and_fails_the_update(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        self.planted.set("build_status", "1")
        done = self.planted.update()
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertEqual([c for c in self.planted.calls() if "apply_migrations" in c], [])
        self.assertEqual(self.planted.server_runs(), [])

    def test_a_migration_that_fails_leaves_the_server_as_it_was_and_fails_the_update(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        self.planted.set("migrate_status", "1")
        done = self.planted.update()
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertEqual(self.planted.server_runs(), [])
        self.assertIn("migrations", self.planted.log_text())

    def test_a_commit_whose_image_is_already_built_is_not_built_again(self):
        self.green()
        self.planted.touch(f"image_genesis-play:{NEW_COMMIT}")
        self.assertEqual(self.planted.update().returncode, 0)
        self.assertEqual(self.planted.index_of("podman build"), -1, self.planted.calls())
        self.assertEqual(len(self.planted.server_runs()), 1)

    def test_an_image_holding_a_file_of_the_clients_is_refused_before_anything_is_migrated_or_started(self):
        self.green()
        deployed(self.planted, OLD_COMMIT)
        client_bytes = b"table bytes of the client"
        digest = hashlib.sha256(client_bytes).hexdigest()
        self.planted.set("image_files", f"{digest}  /app/Spell4.tbl\n")
        done = self.planted.update()
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn("/app/Spell4.tbl", done.stderr + done.stdout)
        self.assertEqual([c for c in self.planted.calls() if "apply_migrations" in c], [])
        self.assertEqual(self.planted.server_runs(), [])

    def test_the_installed_scripts_are_replaced_with_the_deployed_commits(self):
        self.green()
        installed = os.path.join(self.planted.state, "bin")
        shutil.copytree(PLAY_SERVICE, installed)
        os.makedirs(os.path.join(self.planted.plant, "archive", "dev", "play_service"))
        Planted.write(os.path.join(self.planted.plant, "archive", "dev", "play_service", "update.sh"), "# the new commit's\n")
        done = self.planted.update(os.path.join(installed, "update.sh"))
        self.assertEqual(done.returncode, 0, done.stderr)
        with open(os.path.join(installed, "update.sh")) as file:
            self.assertEqual(file.read(), "# the new commit's\n")

    def test_a_checkout_that_runs_the_updater_is_never_overwritten(self):
        self.green()
        os.makedirs(os.path.join(self.planted.plant, "archive", "dev", "play_service"))
        Planted.write(os.path.join(self.planted.plant, "archive", "dev", "play_service", "update.sh"), "# the new commit's\n")
        self.assertEqual(self.planted.update().returncode, 0)
        with open(os.path.join(PLAY_SERVICE, "update.sh")) as file:
            self.assertNotEqual(file.read(), "# the new commit's\n")


@unittest.skipUnless(RUNNABLE, "the image check's test needs bash and jq")
class ImageCheckTest(unittest.TestCase):
    """check_image.sh against a planted image listing."""

    def setUp(self):
        self.planted = Planted(self)
        self.client = os.path.join(self.planted.root, "client")
        os.makedirs(self.client)
        Planted.write(os.path.join(self.client, "Item.tbl"), "item table bytes")
        Planted.write(os.path.join(self.client, "Empty.tbl"), "")

    def check(self, listing: str) -> subprocess.CompletedProcess:
        self.planted.set("image_files", listing)
        return self.planted.run(os.path.join(PLAY_SERVICE, "check_image.sh"), "genesis-play:x", self.client)

    def test_an_image_that_holds_a_client_file_is_refused_and_the_file_named(self):
        digest = hashlib.sha256(b"item table bytes").hexdigest()
        done = self.check(f"{'1' * 64}  /usr/bin/bash\n{digest}  /app/renamed.bin\n")
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn("/app/renamed.bin", done.stderr)

    def test_an_image_that_holds_none_is_accepted(self):
        done = self.check(f"{'1' * 64}  /usr/bin/bash\n{'2' * 64}  /app/start\n")
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_an_empty_file_in_the_image_matches_nothing(self):
        empty = hashlib.sha256(b"").hexdigest()
        done = self.check(f"{empty}  /etc/empty\n")
        self.assertEqual(done.returncode, 0, done.stderr)


@unittest.skipUnless(RUNNABLE, "the stop and start scripts' test needs bash and jq")
class StopAndStartTest(unittest.TestCase):
    def setUp(self):
        self.planted = Planted(self)
        deployed(self.planted, OLD_COMMIT)
        self.planted.touch("running_genesis-play")

    def script(self, name: str, *arguments: str) -> subprocess.CompletedProcess:
        return self.planted.run("/bin/bash", os.path.join(PLAY_SERVICE, name), *arguments)

    def test_stopping_a_running_server_container_stops_it_and_says_so(self):
        done = self.script("stop.sh")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.splitlines()[-1], "stopped")
        self.assertGreaterEqual(self.planted.index_of("podman stop --time 60 genesis-play"), 0)
        self.assertEqual(self.planted.index_of("podman stop --time 60 genesis-play-postgres"), -1, "Postgres keeps running")

    def test_stopping_a_container_that_is_not_running_says_so_and_stops_nothing(self):
        os.remove(os.path.join(self.planted.plant, "running_genesis-play"))
        done = self.script("stop.sh")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "not running")
        self.assertEqual(self.planted.index_of("podman stop"), -1)

    def test_a_stop_by_hand_holds_the_updater_until_start_releases_it(self):
        self.planted.set(f"checks_{NEW_COMMIT}.json", checks(("completed", "success")))
        self.assertEqual(self.script("stop.sh", "--hold").returncode, 0)
        update = self.planted.update()
        self.assertEqual(update.returncode, 0, update.stderr)
        self.assertEqual(self.planted.index_of("podman build"), -1)
        started = self.script("start.sh")
        self.assertEqual(started.returncode, 0, started.stderr)
        self.assertEqual(started.stdout.splitlines()[-1], "started")
        self.assertFalse(os.path.exists(os.path.join(self.planted.state, "held")))

    def test_starting_waits_for_postgres_and_starts_the_container(self):
        self.planted.set("pg_isready_refusals", "2")
        done = self.script("start.sh")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertLess(self.planted.index_of("pg_isready answered"), self.planted.index_of("podman start genesis-play"))

    def test_starting_with_no_server_container_says_so(self):
        os.remove(os.path.join(self.planted.plant, "exists_genesis-play"))
        done = self.script("start.sh")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "not installed")
        self.assertEqual(self.planted.index_of("podman start"), -1)


@unittest.skipUnless(RUNNABLE, "session.sh's test needs bash and jq")
class SessionTest(unittest.TestCase):
    """session.sh with the planted programs: the run is cut short at its first database step, which
    comes before the server starts, so what is shown is where the container's stop and start fall."""

    def setUp(self):
        self.planted = Planted(self)
        deployed(self.planted, OLD_COMMIT)
        self.planted.touch("running_genesis-play")
        self.folder = os.path.join(self.planted.root, "sitting")

    def session(self) -> subprocess.CompletedProcess:
        return self.planted.run(SESSION, self.folder)

    def test_a_run_stops_the_play_container_before_its_server_and_starts_it_again_when_it_fails_part_way(self):
        done = self.session()
        self.assertNotEqual(done.returncode, 0, "the planted psql fails the run database's creation")
        stop = self.planted.index_of("podman stop --time 60 genesis-play")
        create = next((i for i, c in enumerate(self.planted.calls()) if " -c CREATE DATABASE " in c), -1)
        start = self.planted.index_of("podman start genesis-play")
        self.assertTrue(0 <= stop < create < start, (self.planted.calls(), done.stdout, done.stderr))
        self.assertTrue(os.path.exists(os.path.join(self.planted.plant, "running_genesis-play")), "the container is running again")
        self.assertFalse(os.path.exists(os.path.join(self.planted.home, "live.lock")), "the lock is released")

    def test_a_run_makes_its_database_in_the_play_postgres_on_the_loopback_port_with_the_password(self):
        done = self.session()
        creates = [c for c in self.planted.calls() if " -c CREATE DATABASE " in c]
        self.assertEqual(len(creates), 1, (self.planted.calls(), done.stdout, done.stderr))
        self.assertTrue(creates[0].startswith("psql [127.0.0.1:5434 as secret] "), creates[0])
        self.assertTrue(creates[0].endswith(" TEMPLATE genesis_play"), creates[0])

    def test_a_container_that_was_not_running_is_not_started_by_a_run(self):
        os.remove(os.path.join(self.planted.plant, "running_genesis-play"))
        self.session()
        self.assertEqual(self.planted.index_of("podman stop"), -1)
        self.assertEqual(self.planted.index_of("podman start genesis-play"), -1, self.planted.calls())

    def test_a_process_holding_the_ports_keeps_the_container_from_starting_and_fails_the_run(self):
        self.planted.touch("ports_held")
        done = self.session()
        self.assertNotEqual(done.returncode, 0)
        self.assertEqual(self.planted.index_of("podman start genesis-play"), -1, self.planted.calls())


if __name__ == "__main__":
    unittest.main()

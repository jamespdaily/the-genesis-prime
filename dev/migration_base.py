"""CI's guard that a pull request changes no migration already on its base.

    python3 -I dev/migration_base.py BASE

BASE is a commit of the base branch (CI's pull request checkout is the merge of the head
into the base, so `HEAD^1`, as `./check scope HEAD^1` takes it). The script compares BASE
with HEAD and fails on every file under `priv/migrations/` that is modified, deleted or
renamed away; a file that is added passes, and so does a change that touches no
migration. A database that ran a migration records its hash and the server refuses a
database whose recorded hash differs (genesis_prime/migration), so the fix of a migration
is a new migration, and a row of test/code_rule/migration_hashes.txt is never the thing
to edit: the list is the local guard (the code rule in test/code_rule/migration_hash.gleam
compares the files with the list in the same tree), this script is the guard against the
base, which still fails when a pull request changes a file together with its row.

Exit status: 0 no migration of BASE was changed, 1 one or more were (each line on stdout
is what happened and the path, naming the file, then a line saying what to do), 2 the arguments
are wrong or git could not compare the commits (the reason is on stderr).
"""

import subprocess
import sys

MIGRATIONS = "priv/migrations/"

WORDS = {"M": "modified", "D": "deleted or renamed away", "T": "changed in type"}


def changed(base: str) -> list[tuple[str, str]]:
    """The (status, path) of each file of the migrations folder that BASE has and HEAD
    changed or lacks. Renames are not detected, so a renamed file is its old path
    deleted and its new path added."""
    done = subprocess.run(
        ["git", "diff", "--name-status", "--no-renames", "-z", base, "HEAD", "--", MIGRATIONS],
        capture_output=True,
        text=True,
    )
    if done.returncode != 0:
        raise RuntimeError(done.stderr.strip() or f"git diff exited {done.returncode}")
    fields = done.stdout.split("\0")
    pairs = zip(fields[0::2], fields[1::2])
    return [(status, path) for status, path in pairs if status != "A"]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: python3 -I dev/migration_base.py BASE", file=sys.stderr)
        return 2
    try:
        found = changed(sys.argv[1])
    except (RuntimeError, OSError) as error:
        print(f"cannot compare {sys.argv[1]} with HEAD: {error}", file=sys.stderr)
        return 2
    for status, path in found:
        print(f"{WORDS.get(status, status)} {path}")
    if found:
        print(
            "a migration on the base is never changed: restore each file above to the "
            "base's bytes and write the change as a new migration"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

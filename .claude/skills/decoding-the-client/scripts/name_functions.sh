#!/bin/bash
# Usage: name_functions.sh <out-file>
# Names in the Ghidra project every function the fact file names, in one Ghidra run, and writes
# one line per name to <out-file>, ending with "named N, failed M". Read-only unless GHIDRA_WRITE=1,
# which saves the names. Run nothing else on the project while it writes.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
pairs="${TMPDIR:-/tmp}/client-fact-names.txt"
python3 -I -c '
import sys, tomllib
for key, fact in tomllib.load(open(sys.argv[1], "rb")).items():
    if "name" in fact:
        print(key, fact["name"])
' "$here/../references/client-facts.toml" >"$pairs"
echo "$(wc -l <"$pairs" | tr -d " ") names"
"$here/ghidra.sh" RenameFunction.java "$1" "@$pairs"
tail -1 "$1"

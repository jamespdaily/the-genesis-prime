#!/bin/bash
# Usage: ghidra.sh <Script.java> [script args...]
# Runs one Ghidra script headless against the WildStar client project, read-only
# unless GHIDRA_WRITE=1, which saves what the script changes, such as function names.
# Extra script folders can be added with GHIDRA_EXTRA_SCRIPTS=/path/one;/path/two.
set -u
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
script=$1; shift
scripts="$(cd "$(dirname "$0")/../ghidra/scripts" && pwd)"
paths="$scripts${GHIDRA_EXTRA_SCRIPTS:+;$GHIDRA_EXTRA_SCRIPTS}"
log="${TMPDIR:-/tmp}/ghidra_last.log"
mode=-readOnly
[ "${GHIDRA_WRITE:-}" = 1 ] && mode=
/opt/homebrew/Cellar/ghidra/12.1.4/libexec/support/analyzeHeadless \
  "$HOME/Coding/wildstar/ghidra" WildStar -process WildStar64.exe -noanalysis $mode \
  -scriptPath "$paths" -postScript "$script" "$@" >"$log" 2>&1
status=$?
if grep -q 'SCRIPT ERROR\|Exception' "$log"; then
  echo "script failed, see $log:"
  grep -m3 'SCRIPT ERROR\|Exception' "$log"
  exit 1
fi
echo "ok (exit $status, log $log)"

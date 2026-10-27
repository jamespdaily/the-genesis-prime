#!/usr/bin/env bash
# Brings back what the client logged during a live session, and lists each message it failed to
# handle, with the message id.
#
#   client-log.sh start <folder>       notes the PC's time as the session's start, in <folder>/since.txt
#   client-log.sh collect <folder>     copies the client's log files and error reports written since
#                                      then into <folder>, and prints the failures (also saved in
#                                      <folder>/failures.txt)
#   client-log.sh failures <file>...   prints the failures in log files already here
#
# The client writes a log file only when started with -logFile -logFlush on its command line
# (fact 0x1401a1530): <install>\Logs\WildStar64_16042_<PC>_<date>_<time>.txt. An error report
# (.txt, .dmp and .log, the .log a copy of its in-memory log) goes to <install>\Errors whatever
# the flags (facts 0x140192440, 0x1401971e0). Each failure line names the message by its decimal
# id (fact 0x140335f10); a frame whose length or id cannot be read logs only the disconnect.
#
# Needs GENESIS_PLAY_PC (user@host) and GENESIS_PLAY_CLIENT_DIR (the client's install folder, the
# one holding Client64), read from ~/.genesis-prime/env.sh when it is there.
set -euo pipefail

usage() { sed -n '5,10p' "$0" >&2; exit 2; }

# Each failure line as: kind, message id (decimal, or - when the line has none), the line. A line
# found in more than one file (an error report holds a copy of the log) is listed once. The texts
# are the client's own (facts 0x140331990, 0x140331620, 0x1403321a0, 0x1403374e0, 0x140015a90).
failures() {
  awk '
    seen[$0]++ { next }
    function id(line,   m) {
      if (match(line, /Message Id #[0-9]+/)) return substr(line, RSTART + 12, RLENGTH - 12)
      if (match(line, /<[0-9]+,/)) return substr(line, RSTART + 1, RLENGTH - 2)
      if (match(line, /\[[0-9]+, /)) return substr(line, RSTART + 1, RLENGTH - 3)
      return "-"
    }
    function show(kind) { printf "%-16s %6s  %s\n", kind, id($0), $0; count++ }
    /Malformed Packet: Unknown Message/           { show("unknown id"); next }
    /Malformed Packet: bad Message size/          { show("too long"); next }
    /failed to GetMsgBuffer/                      { show("no record space"); next }
    /failed to find unPackFromStreamFn/           { show("no reader"); next }
    /unpacked data too big|unPackFromStreamFn failure/ { show("reader failed"); next }
    /\) Invalid Message /                         { show("handler failed"); next }
    /Unhandled network message/                   { show("unhandled"); next }
    /Message offset invalid!|Message size exceeds (remaining|limit)!|\(Network\) Overflow/ { show("record space"); next }
    /Disconnecting connectionId/                  { show("disconnected"); next }
    /Invalid TConnectionId/                       { show("bad connection"); next }
    / without wrapper/                            { show("no wrapper"); next }
    END { printf "%d failure line(s)\n", count }
  ' "$@"
}

command=${1:-}
case "$command" in
  failures) shift; [ $# -gt 0 ] || usage; failures "$@"; exit ;;
  start | collect) [ $# -eq 2 ] || usage; folder=$2 ;;
  *) usage ;;
esac

[ -f "${GENESIS_HOME:-$HOME/.genesis-prime}/env.sh" ] && . "${GENESIS_HOME:-$HOME/.genesis-prime}/env.sh"
: "${GENESIS_PLAY_PC:?set GENESIS_PLAY_PC (user@host) in ~/.genesis-prime/env.sh}"
: "${GENESIS_PLAY_CLIENT_DIR:?set GENESIS_PLAY_CLIENT_DIR (the client install folder, for example C:\\WildStar-HD) in ~/.genesis-prime/env.sh}"
options=(-o BatchMode=yes -o ConnectTimeout=10)

# Runs a PowerShell script on the PC. It is passed encoded, so no quoting reaches the PC's shell.
on_pc() {
  local encoded
  encoded=$(printf '%s' "\$ProgressPreference = 'SilentlyContinue'
\$ErrorActionPreference = 'Stop'
$1" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')
  ssh "${options[@]}" "$GENESIS_PLAY_PC" "powershell -NoProfile -NonInteractive -EncodedCommand $encoded" | tr -d '\r'
}

mkdir -p "$folder"
if [ "$command" = start ]; then
  on_pc '(Get-Date).ToString("o")' > "$folder/since.txt"
  echo "session start on the PC: $(cat "$folder/since.txt")"
  exit
fi

[ -s "$folder/since.txt" ] || { echo "client-log: no $folder/since.txt; run 'client-log.sh start $folder' before the session" >&2; exit 1; }
since=$(cat "$folder/since.txt")
# Both go into single-quoted PowerShell text, where an apostrophe is written twice.
quoted_since=${since//\'/\'\'}
quoted_dir=${GENESIS_PLAY_CLIENT_DIR//\'/\'\'}
names=$(on_pc "\$since = [datetime]::Parse('$quoted_since')
foreach (\$part in 'Logs', 'Errors') {
  \$path = Join-Path '$quoted_dir' \$part
  if (Test-Path \$path) {
    Get-ChildItem \$path -File | Where-Object { \$_.LastWriteTime -gt \$since } | ForEach-Object { \$part + '/' + \$_.Name }
  }
}")
if [ -z "$names" ]; then
  echo "client-log: nothing in $GENESIS_PLAY_CLIENT_DIR\\Logs or \\Errors since $since" >&2
  exit 1
fi
# The client names its files without spaces, so the list passes as words.
# shellcheck disable=SC2086
ssh "${options[@]}" "$GENESIS_PLAY_PC" "tar -cf - -C \"$GENESIS_PLAY_CLIENT_DIR\" $(echo $names)" | tar -xf - -C "$folder"
echo "copied to $folder:"
sed 's/^/  /' <<< "$names"

# Only this collection's files: a folder used before holds earlier sessions' files too. The error
# reports' logs are read as well, since a run without -logFile leaves only those.
sources=()
while read -r name; do
  case "$name" in
    Logs/*.txt | Errors/*.log) sources+=("$folder/$name") ;;
  esac
done <<< "$names"
grep -q '^Logs/' <<< "$names" || echo "client-log: no log file; was the client started with -logFile -logFlush? Reading the error reports' logs only." >&2
[ ${#sources[@]} -gt 0 ] || { echo "client-log: no log file and no error report log" >&2; exit 1; }
failures "${sources[@]}" | tee "$folder/failures.txt"

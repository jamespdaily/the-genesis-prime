#!/usr/bin/env bash
# One command for a whole live session to world entry, with background keys only: no click, no
# focus, no person. It records the session and checks what the client saw against the database.
#
#   session.sh <folder>            runs the session; <folder> must be empty or new
#   session.sh --verdict <folder>  only the verdict, on a folder a session left; needs no PC
#
# In order: the server starts in record mode into <folder> (dev_start) and its ready line is awaited;
# report.sh install, client-log.sh start, client.sh start (logged in from the command line); on the
# select screen Enter plays the first character in the list; report.sh collect is retried until the
# report is in; client-log.sh collect, client.sh stop, report.sh remove, and SIGTERM to the server's
# VM, so every recording gets its End. Then the verdict (session_verdict.py): the report against the
# saved row of the character it names, and the client's failure log. Any miss fails the run.
#
# A step that fails part-way still runs, best effort, client.sh stop, report.sh remove and the
# server's stop, and names each that failed. A failed verdict keeps <folder>/Logs and /Errors, which
# name the PC's machine: delete them before the folder is committed.
#
# <folder> keeps the recordings, client-start.txt (the client.sh start line), failures.txt,
# report.json and verdict.txt. Needs what the scripts it runs need (GENESIS_PLAY_PC,
# GENESIS_PLAY_ADDRESS, GENESIS_PLAY_CLIENT_DIR, GENESIS_PLAY_ACCOUNT, GENESIS_PLAY_PASSWORD), read
# from ~/.genesis-prime/env.sh. The server runs against the genesis_play database on ::1; its port is
# GENESIS_PLAY_PGPORT (default 5433). SELECT_SETTLE_SECONDS (default 5) is how long the select
# screen is left to show its list after the client's first request on it.
set -euo pipefail

usage() { sed -n '2,6p' "$0" >&2; exit 2; }

case ${1:-} in
  --verdict) [ $# -eq 2 ] || usage; mode=verdict; folder=$2 ;;
  -* | "") usage ;;
  *) [ $# -eq 1 ] || usage; mode=session; folder=$1 ;;
esac

scripts=$(cd "$(dirname "$0")" && pwd)
cd "$scripts/../../../.."
. setup_check/environment.sh
: "${GENESIS_PLAY_ACCOUNT:?set GENESIS_PLAY_ACCOUNT (the account the client logs in with) in ~/.genesis-prime/env.sh}"
export PGHOST=::1 PGPORT=${GENESIS_PLAY_PGPORT:-5433} PGUSER=postgres PGDATABASE=genesis_play

if [ "$mode" = verdict ]; then
  [ -d "$folder" ] || { echo "session: $folder is not a folder" >&2; exit 2; }
  python3 -I "$scripts/session_verdict.py" "$folder" | tee "$folder/verdict.txt"
  exit
fi

: "${GENESIS_PLAY_ADDRESS:?set GENESIS_PLAY_ADDRESS (this machine's address on the PC's network) in ~/.genesis-prime/env.sh}"
export GENESIS_GAME_ADDRESS=$GENESIS_PLAY_ADDRESS GENESIS_REALM_NAME=Genesis

mkdir -p "$folder"
folder=$(cd "$folder" && pwd)
[ -z "$(ls -A "$folder")" ] || { echo "session: $folder holds files; a session needs an empty folder, so no old recording mixes in" >&2; exit 2; }
if lsof -nP -iTCP:6600,23115,24000,25000 -sTCP:LISTEN; then
  echo "session: a process holds one of the server's ports (above); stop it first" >&2
  exit 2
fi

client_state=${GENESIS_HOME:-$HOME/.genesis-prime}/client.pid
work=$(mktemp -d)
server_log=$work/server.log
server_pid=
addon_touched=0
client_touched=0
cleaned=0

step() { echo "session: $*"; }

fail() {
  echo "session: $*" >&2
  if [ -n "$server_pid" ] && [ -s "$server_log" ]; then
    echo "session: the server's log, last lines:" >&2
    tail -n 15 "$server_log" | sed 's/^/  /' >&2
  fi
  exit 1
}

# Waits until the command succeeds, or fails with $2 after $1 seconds or when the server has ended.
wait_until() {
  local seconds=$1 what=$2
  shift 2
  local deadline=$((SECONDS + seconds))
  until "$@"; do
    kill -0 "$server_pid" 2>/dev/null || fail "the server ended before $what"
    [ "$SECONDS" -lt "$deadline" ] || fail "no $what within $seconds s"
    sleep 0.5
  done
}

server_said() { grep -qF -- "$1" "$server_log"; }

# SIGTERM to the server's VM, the one child of the process that `gleam run` started, so the supervision
# tree stops and every recording gets its End; without a VM yet, to that process. Waits until both end.
stop_server() {
  [ -n "$server_pid" ] || return 0
  if kill -0 "$server_pid" 2>/dev/null; then
    local children target
    children=$(pgrep -P "$server_pid" || true)
    if [ -z "$children" ]; then
      target=$server_pid
    elif [ "$(wc -l <<< "$children")" -eq 1 ] && [ "$(basename "$(ps -o comm= -p "$children")")" = beam.smp ]; then
      target=$children
    else
      echo "session: the server's process $server_pid has children that are not one VM ($(echo $children)); nothing was stopped" >&2
      return 1
    fi
    kill -TERM "$target"
    local deadline=$((SECONDS + 75))
    while kill -0 "$target" 2>/dev/null || kill -0 "$server_pid" 2>/dev/null; do
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "session: the server (process $target) did not end within 75 s of SIGTERM" >&2
        return 1
      fi
      sleep 0.5
    done
  fi
  wait "$server_pid" 2>/dev/null || true
}

# Each of these ends the session's use of the PC, best effort, and names those that failed.
cleanup() {
  [ "$cleaned" -eq 0 ] || return 0
  cleaned=1
  local failed=()
  if [ "$client_touched" -eq 1 ] && [ -s "$client_state" ]; then
    "$scripts/client.sh" stop || failed+=("client.sh stop")
  fi
  if [ "$addon_touched" -eq 1 ]; then
    "$scripts/report.sh" remove || failed+=("report.sh remove")
  fi
  stop_server || failed+=("the server's stop")
  rm -f "$folder/since.txt" "$folder"/GenesisReport_0_*.xml
  rm -rf "$work"
  if [ ${#failed[@]} -gt 0 ]; then
    echo "session: cleanup failed: ${failed[*]}" >&2
    return 1
  fi
}

on_exit() {
  local status=$?
  cleanup || { [ "$status" -ne 0 ] || status=1; }
  exit "$status"
}
trap on_exit EXIT

step "starting the server in record mode into $folder"
gleam run -m genesis_prime/dev_start -- "$folder" > "$server_log" 2>&1 &
server_pid=$!
wait_until 180 "the server's ready line" server_said "serves the STS login on port"

step "installing the report addon, starting the client log and the client"
addon_touched=1
"$scripts/report.sh" install
"$scripts/client-log.sh" start "$folder"
client_touched=1
"$scripts/client.sh" start | tee "$folder/client-start.txt"

# The client sends 0x082D on the select screen, right after the list is asked for.
wait_until 90 "the client on the select screen (unhandled game message 0x082D)" server_said "unhandled game message 0x082D"
sleep "${SELECT_SETTLE_SECONDS:-5}"
step "playing the first character"
"$scripts/client.sh" key enter

step "waiting for the report"
report_log=$work/report.err
deadline=$((SECONDS + 90))
until "$scripts/report.sh" collect "$folder" > /dev/null 2> "$report_log"; do
  [ "$SECONDS" -lt "$deadline" ] || { sed 's/^/  /' "$report_log" >&2; fail "no report within 90 s"; }
  sleep 3
done

step "collecting the client's log and ending the session"
"$scripts/client-log.sh" collect "$folder"
cleanup || fail "the session's cleanup failed"

step "the verdict"
verdict=0
python3 -I "$scripts/session_verdict.py" "$folder" | tee "$folder/verdict.txt" || verdict=$?
if [ "$verdict" -eq 0 ]; then
  rm -rf "$folder/Logs" "$folder/Errors"
else
  echo "session: the verdict failed; $folder/Logs and $folder/Errors are kept (they name the PC's machine)" >&2
fi
exit "$verdict"

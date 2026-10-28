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
# saved row of the character it names, the client's failure log, any client error report, and that
# the client was still running when the session ended. Any miss fails the run.
#
# A step that fails part-way still runs, best effort, client.sh stop, report.sh remove and the
# server's stop, and names each that failed. The server is stopped by the VM's pid, recorded with its
# start time once the ready line is seen and checked again before it is signalled; before the ready
# line the launcher's whole process tree is stopped instead. A client.sh start that failed before it
# recorded a client leaves any WildStar64 alone and is named as a cleanup failure: it may be the
# person's own. A failed verdict keeps <folder>/Logs and /Errors, which name the PC's machine:
# delete them before the folder is committed.
#
# <folder> keeps the recordings, client-start.txt (the client.sh start line), client-end.txt (what
# client.sh stop found: closed or gone), failures.txt, report.json and verdict.txt. Needs what the
# scripts it runs need (GENESIS_PLAY_PC, GENESIS_PLAY_ADDRESS, GENESIS_PLAY_CLIENT_DIR,
# GENESIS_PLAY_ACCOUNT, GENESIS_PLAY_PASSWORD), read from ~/.genesis-prime/env.sh. The server runs
# against the genesis_play database on ::1; its port is GENESIS_PLAY_PGPORT (default 5433).
# SELECT_SETTLE_SECONDS (default 5) is how long the select screen is left to show its list after the
# client's first request on it.
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
export GENESIS_PLAY_ACCOUNT
export PGHOST=::1 PGPORT=${GENESIS_PLAY_PGPORT:-5433} PGUSER=postgres PGDATABASE=genesis_play

# The verdict on <folder>, printed and saved in it; fails when any check does.
verdict() { python3 -I "$scripts/session_verdict.py" "$folder" | tee "$folder/verdict.txt"; }

if [ "$mode" = verdict ]; then
  [ -d "$folder" ] || { echo "session: $folder is not a folder" >&2; exit 2; }
  verdict
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
client_state_before=$(cat "$client_state" 2>/dev/null || true)
work=$(mktemp -d)
server_log=$work/server.log
launcher_pid=
launcher_started=
vm_pid=
vm_started=
addon_touched=0
client_touched=0
cleaned=0

step() { echo "session: $*"; }

fail() {
  echo "session: $*" >&2
  if [ -n "$launcher_pid" ] && [ -s "$server_log" ]; then
    echo "session: the server's log, last lines:" >&2
    tail -n 15 "$server_log" | sed 's/^/  /' >&2
  fi
  exit 1
}

# When process $1 started, as ps prints it with its padding squeezed out: empty when there is no
# such process. Together with the pid it names one process, so a pid the system has reused is not
# taken for the one recorded.
started_at() { { ps -o lstart= -p "$1" 2>/dev/null || true; } | awk '{ $1 = $1; print }'; }

# Whether process $1 is the one that started at $2.
is_process() { [ -n "$2" ] && [ "$(started_at "$1")" = "$2" ]; }

launcher_alive() { is_process "$launcher_pid" "$launcher_started"; }

# The VM once it is known, else the launcher.
server_alive() {
  if [ -n "$vm_pid" ]; then is_process "$vm_pid" "$vm_started"; else launcher_alive; fi
}

# Polls the command every $1 seconds until it succeeds; gives up with the command's last error
# after $2 seconds, or when the server has ended. $3 names what is waited for.
wait_until() {
  local interval=$1 seconds=$2 what=$3
  shift 3
  local deadline=$((SECONDS + seconds)) last_error=$work/wait.err
  until "$@" 2> "$last_error"; do
    if ! server_alive || [ "$SECONDS" -ge "$deadline" ]; then
      if [ -s "$last_error" ]; then sed 's/^/  /' "$last_error" >&2; fi
      if server_alive; then fail "gave up waiting for $what: it did not come within $seconds s"; fi
      fail "the server ended while waiting for $what"
    fi
    sleep "$interval"
  done
}

server_said() { grep -qF -- "$1" "$server_log"; }

report_in() { "$scripts/report.sh" collect "$folder" > /dev/null; }

# Records the server's VM, the one beam.smp child of the launcher, with its start time.
record_vm() {
  local child found=()
  for child in $(pgrep -P "$launcher_pid" || true); do
    if [ "$(basename "$(ps -o comm= -p "$child" 2>/dev/null || true)")" = beam.smp ]; then found+=("$child"); fi
  done
  [ ${#found[@]} -eq 1 ] || fail "the server's ready line is out, but its process $launcher_pid has ${#found[@]} beam.smp children, not one VM"
  vm_pid=${found[0]}
  vm_started=$(started_at "$vm_pid")
  [ -n "$vm_started" ] || fail "the server's VM $vm_pid ended as it was recorded"
}

# The pids below process $1, each with the start time it had when listed, children before their own
# children, as "pid|started" lines.
descendants() {
  local child
  for child in $(pgrep -P "$1" || true); do
    echo "$child|$(started_at "$child")"
    descendants "$child"
  done
}

# Signals $2 to each of the "pid|started" entries after $1 that is still the process it was.
signal_entries() {
  local signal=$1 entry
  shift
  for entry in "$@"; do
    if is_process "${entry%%|*}" "${entry#*|}"; then kill "-$signal" "${entry%%|*}" 2>/dev/null || true; fi
  done
}

entries_alive() {
  local entry
  for entry in "$@"; do
    if is_process "${entry%%|*}" "${entry#*|}"; then return 0; fi
  done
  return 1
}

# Stops the launcher and everything below it (a build or a fetch it still runs, or a VM it started),
# from the top so it starts nothing more: SIGTERM, then SIGKILL after 20 s, each only to a process
# that is still the one listed.
stop_tree() {
  local entries=("$launcher_pid|$launcher_started") entry deadline
  while read -r entry; do
    if [ -n "$entry" ]; then entries+=("$entry"); fi
  done < <(descendants "$launcher_pid")
  signal_entries TERM "${entries[@]}"
  deadline=$((SECONDS + 20))
  while entries_alive "${entries[@]}" && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; done
  if entries_alive "${entries[@]}"; then
    signal_entries KILL "${entries[@]}"
    sleep 1
  fi
  if entries_alive "${entries[@]}"; then
    echo "session: the server's processes (${entries[*]%%|*}) did not end" >&2
    return 1
  fi
}

# Stops the server. With its VM recorded, SIGTERM goes to that VM alone (so the supervision tree
# stops and every recording gets its End), and the launcher is left to end by itself; without one,
# the launcher's whole process tree is stopped.
stop_server() {
  [ -n "$launcher_pid" ] || return 0
  local deadline
  if [ -n "$vm_pid" ]; then
    if is_process "$vm_pid" "$vm_started"; then
      kill -TERM "$vm_pid"
      deadline=$((SECONDS + 75))
      while is_process "$vm_pid" "$vm_started"; do
        if [ "$SECONDS" -ge "$deadline" ]; then
          echo "session: the server's VM (process $vm_pid) did not end within 75 s of SIGTERM" >&2
          return 1
        fi
        sleep 0.5
      done
    fi
    deadline=$((SECONDS + 15))
    while launcher_alive && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.5; done
  fi
  if launcher_alive; then stop_tree || return 1; fi
}

# Closes the client that client.sh start recorded and notes in the folder how it was found: closed,
# or gone when it was no longer running (client.sh stop says "was not running").
stop_client() {
  local out
  out=$("$scripts/client.sh" stop 2>&1) || { echo "$out" >&2; return 1; }
  echo "$out"
  case $out in
    *"was not running"*) echo gone > "$folder/client-end.txt" ;;
    *) echo closed > "$folder/client-end.txt" ;;
  esac
}

# Each of these ends the session's use of the PC, best effort, and names those that failed.
cleanup() {
  [ "$cleaned" -eq 0 ] || return 0
  cleaned=1
  local failed=() recorded
  if [ "$client_touched" -eq 1 ]; then
    recorded=$(cat "$client_state" 2>/dev/null || true)
    if [ -n "$recorded" ] && [ "$recorded" != "$client_state_before" ]; then
      stop_client || failed+=("client.sh stop")
    else
      failed+=("the client may be running: client.sh start failed before it recorded a client; check the PC")
    fi
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
launcher_pid=$!
launcher_started=$(started_at "$launcher_pid")
wait_until 0.5 180 "the server's ready line" server_said "serves the STS login on port"
record_vm

step "installing the report addon, starting the client log and the client"
addon_touched=1
"$scripts/report.sh" install
"$scripts/client-log.sh" start "$folder"
client_touched=1
"$scripts/client.sh" start | tee "$folder/client-start.txt"

# The client sends message 0x082D, the store-catalog request, once on the select screen (facts
# opcode.0x82d, 0x14044db80). The server logs it as unhandled, so this wait relies on that: a step
# that handles the store request changes this wait.
wait_until 0.5 90 "the client on the select screen (unhandled game message 0x082D)" server_said "unhandled game message 0x082D"
sleep "${SELECT_SETTLE_SECONDS:-5}"
# Enter on the select screen plays the selected character; with no character logged out last the
# client selects the first in the list (fact lua.CharacterSelection.OnLoadFromCharacter.preselect).
step "playing the first character"
"$scripts/client.sh" key enter

# The report addon writes the report 10 s after the character is in (knReadySeconds in
# GenesisReport.lua), so polling starts after 12 s.
step "waiting for the report"
sleep 12
wait_until 3 90 "the report" report_in

step "collecting the client's log and ending the session"
"$scripts/client-log.sh" collect "$folder"
cleanup || fail "the session's cleanup failed"

step "the verdict"
status=0
verdict || status=$?
if [ "$status" -eq 0 ]; then
  rm -rf "$folder/Logs" "$folder/Errors"
else
  echo "session: the verdict failed; $folder/Logs and $folder/Errors are kept (they name the PC's machine)" >&2
fi
exit "$status"

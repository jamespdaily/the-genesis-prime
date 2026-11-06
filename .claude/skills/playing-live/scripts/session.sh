#!/usr/bin/env bash
# One command for a whole live session to world entry, with background keys only: no click, no
# focus, no person. It records the session and checks what the client saw against the database.
#
#   session.sh <folder>            runs the session; <folder> must be empty or new
#   session.sh --verdict <folder>  only the verdict, on a folder a session left; needs no PC
#   session.sh --recover           ends a run that was cut off and releases its lock
#
# The run holds the live lock (live_lock.sh) from before it starts anything until it has ended
# everything it started: the PC's client, the server's ports and the dev database belong to one run
# at a time. The play server's container (dev/play_service) holds those ports, so the run stops it
# first (the updater skips while the lock is held) and starts it again once its own server has
# ended, also when the run fails part-way; the lock's owner record holds that it did, so --recover
# starts it too. A container that was not running is left alone. A second session.sh, or a client.sh start outside the run, refuses and names the owner;
# a lock whose owner is gone is never taken over, and the refusal points at --recover. The lock's
# owner record also holds what the run has started, so --recover can end it. The run works on its own
# database, a copy of genesis_play made with that as its template (genesis_play is never written, and
# the copy fails while another session is connected to genesis_play). The server and the verdict read
# the copy, and it is dropped after the verdict, a failed one too: the recordings and the report keep
# the evidence, and the verdict's lines name the values it compared. --verdict reads genesis_play.
# genesis_play is the play Postgres container's database (dev/play_service), reached on 127.0.0.1
# at GENESIS_PLAY_PGPORT (default 5434) with GENESIS_PLAY_PGPASSWORD.
#
# --recover ends what a lock's owner started, a run or a client.sh start outside one. It refuses
# while the owner's process still runs, and while the lock has no owner record and is under a minute
# old (a taker is still writing it). It claims the lock first (live.lock/recovering), so one recovery
# runs at a time, and holds the claim until the lock is released. From the owner record, each step
# safe to repeat with its outcome printed: it stops the client (only when client.pid names a client
# the owner started, by pid and start time), removes the report addon, stops the run's server (by
# its VM's pid and start time), checks that no process holds the server's ports, drops the run's
# database (after waiting for a CREATE DATABASE of it that is still running) and releases the lock.
# A step that fails is named, the exit is non-zero and the lock stays, with the claim given up;
# recover again once it is dealt with.
#
# In order: the server starts in record mode into <folder> (dev_start) and its ready line is awaited;
# report.sh install, client-log.sh start, client.sh start (logged in from the command line); on the
# select screen Enter plays the first character in the list; report.sh collect is retried until the
# report is in; client-log.sh collect, client.sh stop, report.sh remove, and SIGTERM to the server's
# VM, so every recording gets its closing line. Then the verdict (session_verdict.py): the report against the
# saved row of the character it names, the client's failure log, any client error report, and that
# the client was still running when the session ended. Any miss fails the run.
#
# A step that fails part-way still runs, best effort, client.sh stop, report.sh remove and the
# server's stop, and names each that failed. The launcher waits for a go file until its pid and start
# time are recorded, so a run cut off before the record has started no server. The server is stopped
# by the VM's pid, recorded with its start time once the ready line is seen and checked again before
# it is signalled; before the ready line the launcher's whole process tree is stopped instead. A
# client.sh start that failed before it recorded a client leaves any WildStar64 alone and is named as
# a cleanup failure that does not keep the lock: it may be the person's own, and client.sh start
# refuses while any WildStar64 runs. A failed verdict keeps <folder>/Logs and /Errors, which name the
# PC's machine: delete them before the folder is committed.
#
# <folder> keeps the recordings, client-start.txt (the client.sh start line), client-end.txt (what
# client.sh stop found: closed or gone), failures.txt, report.json and verdict.txt. Needs what the
# scripts it runs need (GENESIS_PLAY_PC, GENESIS_PLAY_ADDRESS, GENESIS_PLAY_CLIENT_DIR,
# GENESIS_PLAY_ACCOUNT, GENESIS_PLAY_PASSWORD, GENESIS_PLAY_PGPASSWORD), read from
# ~/.genesis-prime/env.sh. The server runs against the run's database in the play Postgres.
# SELECT_SETTLE_SECONDS (default 5) is how long the select screen is left to show its list after the
# client's first request on it.
set -euo pipefail

usage() { sed -n '2,7p' "$0" >&2; exit 2; }

case ${1:-} in
  --verdict) [ $# -eq 2 ] || usage; mode=verdict; folder=$2 ;;
  --recover) [ $# -eq 1 ] || usage; mode=recover; folder= ;;
  -* | "") usage ;;
  *) [ $# -eq 1 ] || usage; mode=session; folder=$1 ;;
esac

scripts=$(cd "$(dirname "$0")" && pwd)
cd "$scripts/../../../.."
. setup_check/environment.sh
: "${GENESIS_PLAY_ACCOUNT:?set GENESIS_PLAY_ACCOUNT (the account the client logs in with) in ~/.genesis-prime/env.sh}"
export GENESIS_PLAY_ACCOUNT
dev_database=genesis_play
: "${GENESIS_PLAY_PGPASSWORD:?set GENESIS_PLAY_PGPASSWORD (the password of the play Postgres container) in ~/.genesis-prime/env.sh; dev/play_service/install.sh makes it}"
export PGHOST=127.0.0.1 PGPORT=${GENESIS_PLAY_PGPORT:-5434} PGUSER=postgres PGPASSWORD=$GENESIS_PLAY_PGPASSWORD PGDATABASE=$dev_database
tool=session
. "$scripts/live_lock.sh"

# The verdict on <folder>, printed and saved in it; fails when any check does.
verdict() { python3 -I "$scripts/session_verdict.py" "$folder" | tee "$folder/verdict.txt"; }

if [ "$mode" = verdict ]; then
  [ -d "$folder" ] || { echo "session: $folder is not a folder" >&2; exit 2; }
  verdict
  exit
fi

client_state=$home/client.pid
work=
server_log=
folder_ready=0
stop_status=
hold_lock=0
server_ok=1

# What the run has started, which --recover reads back from the lock's owner record (load_record).
record_keys=(client_before run_database launcher_pid launcher_started vm_pid vm_started client_touched addon_touched play_service_stopped)
for key in "${record_keys[@]}"; do printf -v "$key" '%s' ''; done

step() { echo "session: $*"; }

fail() {
  echo "session: $*" >&2
  if [ -n "$launcher_pid" ] && [ -s "$server_log" ]; then
    echo "session: the server's log, last lines:" >&2
    tail -n 15 "$server_log" | sed 's/^/  /' >&2
  fi
  exit 1
}

# Sets each variable named in the arguments to the value after it, and records them all in the
# lock's owner record in one write.
mark() {
  local pairs=("$@")
  while [ $# -gt 0 ]; do
    printf -v "$1" '%s' "$2"
    shift 2
  done
  lock_set "${pairs[@]}"
}

# Reads the lock's owner record: the run's folder and token, and what it recorded.
load_record() {
  local key
  for key in folder token "${record_keys[@]}"; do
    printf -v "$key" '%s' "$(lock_get "$key")"
  done
  lock_token=$token
}

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
  local child found=() started
  for child in $(pgrep -P "$launcher_pid" || true); do
    if [ "$(basename "$(ps -o comm= -p "$child" 2>/dev/null || true)")" = beam.smp ]; then found+=("$child"); fi
  done
  [ ${#found[@]} -eq 1 ] || fail "the server's ready line is out, but its process $launcher_pid has ${#found[@]} beam.smp children, not one VM"
  started=$(started_at "${found[0]}")
  [ -n "$started" ] || fail "the server's VM ${found[0]} ended as it was recorded"
  mark vm_pid "${found[0]}" vm_started "$started"
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
# stops and every recording gets its closing line), and the launcher is left to end by itself; without one,
# the launcher's whole process tree is stopped.
stop_server() {
  local deadline ended="server: was not running"
  if [ -z "$launcher_pid" ] && [ -z "$vm_pid" ]; then
    step "server: none was started"
    return 0
  fi
  if [ -n "$vm_pid" ]; then
    if is_process "$vm_pid" "$vm_started"; then
      ended="server: stopped"
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
  if launcher_alive; then
    ended="server: stopped"
    stop_tree || return 1
  fi
  step "$ended"
}

# The listeners on the server's ports, printed; fails when there are none.
ports_held() { lsof -nP -iTCP:6600,23115,24000 -sTCP:LISTEN; }

# Closes the client that client.sh start recorded and notes in the folder how it was found: closed,
# or gone when it was no longer running (client.sh stop says "was not running"). A recovery leaves
# the folder alone, since the folder's verdict reads what the run itself wrote.
stop_client() {
  local out
  out=$("$scripts/client.sh" stop 2>&1) || { echo "$out" >&2; return 1; }
  echo "$out"
  [ "$mode" = session ] || return 0
  case $out in
    *"was not running"*) echo gone > "$folder/client-end.txt" ;;
    *) echo closed > "$folder/client-end.txt" ;;
  esac
}

# Stops the play server's container, which holds the server's ports, and records that this run did.
# A container that was not running (or none) is left alone and started by no one.
stop_play_service() {
  local out
  out=$(dev/play_service/stop.sh) || fail "the play server's container could not be stopped: $out"
  case $out in
    *stopped*) mark play_service_stopped 1; step "play server container: stopped" ;;
    *) step "play server container: $out" ;;
  esac
}

# Starts the play server's container again when this run stopped it, once nothing holds the server's
# ports. Fails when the container did not start; update.sh starts it within 2 minutes anyway.
start_play_service() {
  if [ "$play_service_stopped" != 1 ]; then
    step "play server container: this run stopped none"
    return 0
  fi
  if ports_held; then
    echo "session: the play server's container is not started: a process holds the server's ports (above)" >&2
    return 1
  fi
  if dev/play_service/start.sh > /dev/null; then
    mark play_service_stopped 0
    step "play server container: started"
  else
    echo "session: the play server's container did not start: dev/play_service/start.sh failed" >&2
    return 1
  fi
}

# Ends the run's use of the PC and the server, each step best effort, safe to repeat, and named by
# its outcome. Returns 1 when a step failed or the client could not be confirmed; hold_lock is set
# when a step failed that leaves something of the run behind. The first call's status is every later
# call's.
stop_run() {
  [ -z "$stop_status" ] || return "$stop_status"
  local failed=() unconfirmed=() recorded
  if [ "$client_touched" = 1 ]; then
    recorded=$(cat "$client_state" 2>/dev/null || true)
    if [ -n "$recorded" ] && [ "$recorded" != "$client_before" ]; then
      if stop_client; then mark client_touched 0; else failed+=("client.sh stop"); fi
    else
      unconfirmed+=("the client may be running: client.sh start failed before it recorded a client; check the PC")
      mark client_touched 0
    fi
  else
    step "client: this run started none"
  fi
  if [ "$addon_touched" = 1 ]; then
    if "$scripts/report.sh" remove; then mark addon_touched 0; else failed+=("report.sh remove"); fi
  else
    step "addon: this run installed none"
  fi
  if ! stop_server; then
    failed+=("the server's stop")
    server_ok=0
  elif { [ -n "$launcher_pid" ] || [ -n "$vm_pid" ]; } && ports_held; then
    echo "session: a process still holds one of the server's ports (above); stop it, then run --recover" >&2
    failed+=("a process holds the server's ports")
  fi
  if [ "$folder_ready" = 1 ]; then rm -f "$folder/since.txt" "$folder"/GenesisReport_0_*.xml; fi
  if [ -n "$work" ]; then rm -rf "$work"; fi
  stop_status=0
  if [ ${#unconfirmed[@]} -gt 0 ]; then
    echo "session: ${unconfirmed[*]}" >&2
    stop_status=1
  fi
  if [ ${#failed[@]} -gt 0 ]; then
    echo "session: cleanup failed: ${failed[*]}" >&2
    hold_lock=1
    stop_status=1
  fi
  return "$stop_status"
}

# psql on the server's Postgres, connected to its postgres database: the run's database is made and
# dropped from there, never from genesis_play or the run's own.
admin_psql() { psql -X -q -A -t -v ON_ERROR_STOP=1 -d postgres "$@"; }

# Makes the run's database from genesis_play as the template, and records its name first, so a run
# cut off while it is made is recovered the same way.
make_run_database() {
  local name err
  name=genesis_run_$(date +%s)_$$
  mark run_database "$name"
  if ! err=$(admin_psql -c "CREATE DATABASE $name TEMPLATE $dev_database" 2>&1); then
    case $err in
      *"being accessed by other users"*)
        fail "$dev_database has another session connected (a server or a psql, perhaps a person's own); the run copies it as a template, which needs none: stop it first" ;;
      *) fail "could not make the run database $name from $dev_database: $err" ;;
    esac
  fi
  step "run database: $name made from $dev_database"
  # The committed recording replays with no spawns (the replay's settings stand none), so the run
  # stands none either: every spawn row goes, its stats with it (on delete cascade). A recording
  # made with the world database's spawns holds creatures' news the replay can never take.
  if ! err=$(psql -X -q -A -t -v ON_ERROR_STOP=1 -d "$name" -c "DELETE FROM spawn" 2>&1); then
    fail "could not empty the spawns of the run database $name: $err"
  fi
  step "run database: $name holds no spawns, as the replay stands none"
}

# Drops the run's database, forcing off the connections still open to it, once no CREATE DATABASE
# of it is still running (a run cut off in the copy leaves its psql finishing it: the wait is up to
# 60 s). It drops only a name of the form the run makes, so a damaged record never reaches
# genesis_play.
drop_database() {
  [ -n "$run_database" ] || { step "run database: none was made"; return 0; }
  if [[ ! $run_database =~ ^genesis_run_[0-9]+_[0-9]+$ ]]; then
    echo "session: run database: the recorded name '$run_database' is not one a run makes; left alone" >&2
    return 1
  fi
  local deadline=$((SECONDS + 60)) creating=0 out
  while :; do
    out=$(admin_psql -c "select count(*) from pg_stat_activity where state = 'active' and pid <> pg_backend_pid() and strpos(query, 'CREATE DATABASE $run_database ') > 0") \
      || { echo "session: run database: could not ask Postgres whether $run_database is being made" >&2; return 1; }
    [ "$out" != 0 ] || break
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "session: run database: a CREATE DATABASE of $run_database still runs after 60 s" >&2
      return 1
    fi
    if [ "$creating" = 0 ]; then step "run database: waiting for the CREATE DATABASE of $run_database to end"; creating=1; fi
    sleep 1
  done
  out=$(admin_psql -c "DROP DATABASE IF EXISTS $run_database WITH (FORCE)" 2>&1) \
    || { echo "session: run database: could not drop $run_database: $out" >&2; return 1; }
  case $out in
    *"does not exist"*) step "run database: $run_database is not there" ;;
    *) step "run database: $run_database dropped" ;;
  esac
}

# Drops the run's database once the server has stopped, then releases the lock unless a step left
# something of the run behind.
drop_run() {
  local failed=0
  if [ "$server_ok" = 1 ]; then
    drop_database || failed=1
  else
    echo "session: run database: $run_database is kept; the server did not stop and may hold it" >&2
    failed=1
  fi
  if [ "$hold_lock" = 1 ] || [ "$failed" = 1 ]; then
    echo "session: the lock is kept; session.sh --recover ends what is left and releases it" >&2
    return 1
  fi
  lock_release "$lock_token"
  step "the lock is released"
}

# Ends everything the run started, then releases the lock; returns 1 when any of it failed.
end_run() {
  local status=0
  stop_run || status=1
  start_play_service || status=1
  drop_run || status=1
  return "$status"
}

# Finishes what a lock's owner started, from the lock's owner record, holding the recovery claim
# from before it reads the record until the lock is released (or, on a failure, until this script
# ends).
recover() {
  [ -d "$lock_dir" ] || { step "no lock at $lock_dir; nothing to recover"; return 0; }
  local seen
  if [ -s "$lock_owner" ]; then
    if lock_owner_alive; then lock_refuse; return 1; fi
  elif ! lock_ownerless_for_a_minute; then
    lock_refuse
    return 1
  fi
  seen=$(lock_get token)
  if ! mkdir "$lock_claim" 2> /dev/null; then
    if [ -d "$lock_claim" ]; then
      echo "session: another --recover holds $lock_claim; when none runs (one was cut off), remove it and recover again" >&2
      return 1
    fi
    step "the lock was released meanwhile; nothing to recover"
    return 0
  fi
  trap 'rmdir "$lock_claim" 2> /dev/null || true' EXIT
  if [ "$(lock_get token)" != "$seen" ]; then
    echo "session: the lock changed hands as it was claimed; run --recover again" >&2
    return 1
  fi
  if [ -z "$seen" ]; then
    rm -rf "$lock_dir"
    step "the lock had no owner record and was over a minute old, so nothing had been started; it is released"
    return 0
  fi
  load_record
  export GENESIS_LIVE_LOCK_TOKEN=$lock_token
  step "ending what the lock's owner started: $(lock_get kind) in '$folder', process $(lock_get pid), commit $(lock_get commit)"
  end_run
}

if [ "$mode" = recover ]; then
  recover || exit 1
  exit
fi

: "${GENESIS_PLAY_ADDRESS:?set GENESIS_PLAY_ADDRESS (this machine's address on the PC's network) in ~/.genesis-prime/env.sh}"
export GENESIS_GAME_ADDRESS=$GENESIS_PLAY_ADDRESS GENESIS_REALM_NAME=Genesis

mkdir -p "$folder"
folder=$(cd "$folder" && pwd)
lock_take run "$folder" || exit 2
export GENESIS_LIVE_LOCK_TOKEN=$lock_token
work=$(mktemp -d)
server_log=$work/server.log

on_exit() {
  local status=$?
  end_run || { [ "$status" -ne 0 ] || status=1; }
  exit "$status"
}
trap on_exit EXIT

mark client_before "$(cat "$client_state" 2>/dev/null || true)" client_touched 0 addon_touched 0
if [ -n "$(ls -A "$folder")" ]; then
  echo "session: $folder holds files; a session needs an empty folder, so no old recording mixes in" >&2
  exit 2
fi
folder_ready=1
stop_play_service
if ports_held; then
  echo "session: a process holds one of the server's ports (above); stop it first" >&2
  exit 2
fi

step "making the run database"
make_run_database
export PGDATABASE=$run_database

step "starting the server in record mode into $folder"
# The launcher waits for the go file, so its pid and start time are recorded before the server runs
# anything; it gives up when this script is gone.
{
  until [ -e "$work/go" ]; do
    kill -0 "$$" 2> /dev/null || exit 1
    sleep 0.1
  done
  exec gleam run -m genesis_prime/dev_start -- "$folder"
} > "$server_log" 2>&1 &
mark launcher_pid "$!" launcher_started "$(started_at "$!")"
touch "$work/go"
wait_until 0.5 180 "the server's ready line" server_said "serves the STS login on port"
record_vm

step "installing the report addon, starting the client log and the client"
mark addon_touched 1
"$scripts/report.sh" install
"$scripts/client-log.sh" start "$folder"
mark client_touched 1
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
stop_run || fail "the session's cleanup failed"

step "the verdict"
status=0
verdict || status=$?
if [ "$status" -eq 0 ]; then
  rm -rf "$folder/Logs" "$folder/Errors"
else
  echo "session: the verdict failed; $folder/Logs and $folder/Errors are kept (they name the PC's machine)" >&2
fi
exit "$status"

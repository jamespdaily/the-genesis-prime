#!/usr/bin/env bash
# Reports the play service, the play database, the updater and the live lock as one
# read: one `key=value` line for each fact, on standard output. It only reads: it
# starts, stops and makes nothing, never calls machine_up, never reads env.sh (so it
# needs no password and prints none), and writes no file of the service's.
#
#   machine=up|down|unreadable            `podman info` answered, failed (a closed machine
#                                          exits 125 or 1), or could not be read; with the
#                                          machine down or unreadable the lines for the
#                                          containers and the connections are left out
#   server=running|stopping|exited|created|missing|unreadable
#                                          the server container's State.Status as Podman
#                                          words it (any other word is passed on as it is),
#                                          or missing when there is none
#   server_revision=, server_address=      the container's genesis.revision and
#                                          genesis.address labels, when it exists
#   database=...                           the same for the Postgres container
#   database_ready=yes|no|unreadable       pg_isready's answer; no without asking when the
#                                          container is not running
#   game_connections=N|unreadable          the established connections on the game port
#   held=yes|no                            stop.sh --hold's file
#   update_lock=free|run|ownerless|gone    update.sh's lock: free (no folder), run (its owner
#                                          runs), ownerless (no owner file, under a minute
#                                          old: its taker is still writing it), gone (its
#                                          owner is gone, or no owner file over a minute: the
#                                          next update takes it over)
#   update_lock_pid=                       the owner's process id, when the lock names one
#   live_lock=free|client|run|ownerless|gone
#                                          the live lock: client or run is a live owner of
#                                          that kind (anything but client counts as run, as
#                                          live_lock.sh's lock_refuse does); ownerless and
#                                          gone as for the update lock, and gone also for an
#                                          owner that is not the process the record names
#   live_lock_kind=, live_lock_pid=, live_lock_folder=
#                                          the owner record's fields, each when it holds one
#   updater_last_line=                     the last line of the updater's log, empty when
#                                          there is no log
#
# A fact that could not be read prints `KEY=unreadable` and `KEY_reason=WHY` (one line
# of words); the other facts are still printed. The script ends 0 whenever it printed.
#
# Every call that can hang (podman, lsof: a Podman machine that is stopping holds a
# call open) runs under its own bound and is ended at it, so a hung call leaves no
# process behind, also when this script is ended meanwhile. The bound is in tenths of a
# second so a test can set it small. The calls that read local files and the process
# table (ps, sed, find, cat, tail) are not bounded.
#
# bash 3.2 (the /bin/bash launchd runs) and later; the lib.sh note on `${x:?word}` holds.
#
# Usage: state.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

# The longest a podman or lsof call may run: 3 s, a guess (one call took 0.09 to 0.17 s
# at a load average of 3.9).
bound_tenths=${GENESIS_PLAY_COMMAND_BOUND_TENTHS:-30}

# The port run_server publishes for the game.
game_port=24000

scratch=$(mktemp -d "${TMPDIR:-/tmp}/play-service-state.XXXXXX") || exit 1
trap 'rm -rf "$scratch"' EXIT
trap 'exit 143' HUP INT TERM

# bounded COMMAND ARGUMENT...: runs the command, prints its standard output and returns
# its status; its standard error is kept in $scratch/error. A command still running after
# bound_tenths tenths of a second is ended and the status is 124. The waiting is done by
# a shell of its own that looks twenty times a second, so it goes on and ends the command
# even when this script is ended.
bounded() {
  (
    waited=0
    command "$@" >"$scratch/output" 2>"$scratch/error" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$((bound_tenths * 2))" ]; then
        kill -9 "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        exit 124
      fi
      sleep 0.05
      waited=$((waited + 1))
    done
    wait "$pid"
    status=$?
    cat "$scratch/output"
    exit "$status"
  )
}

# The calls of lib.sh's functions go through bounded.
podman() { bounded podman "$@"; }
lsof() { bounded lsof "$@"; }

# failure_reason COMMAND STATUS: why a call failed, in one line.
failure_reason() {
  local detail
  if [ "$2" -eq 124 ]; then
    printf 'timed out after %s.%s s' "$((bound_tenths / 10))" "$((bound_tenths % 10))"
    return 0
  fi
  detail=$(head -n 1 "$scratch/error" 2>/dev/null | tr -d '\r')
  printf '%s exited with status %s' "$1" "$2"
  if [ -n "$detail" ]; then printf ': %s' "$detail"; fi
}

# unreadable KEY WHY: the lines of a fact that could not be read.
unreadable() { printf '%s=unreadable\n%s_reason=%s\n' "$1" "$1" "$2"; }

# older_than_a_minute PATH: whether the file or folder was last changed over a minute ago.
older_than_a_minute() {
  [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}

# container_report PREFIX NAME: prints the container's status line; sets container_word
# to the status, or to missing or unreadable.
container_word=
container_report() {
  local word code=0
  word=$(container_status "$2") || code=$?
  case "$code" in
    0) container_word=$word ;;
    1) container_word=missing ;;
    *)
      container_word=unreadable
      unreadable "$1" "$(failure_reason podman "$code")"
      return 0
      ;;
  esac
  printf '%s=%s\n' "$1" "$container_word"
}

machine_report() {
  local code=0
  machine_running || code=$?
  case "$code" in
    0) echo machine=up ;;
    1 | 125) echo machine=down ;;
    *)
      unreadable machine "$(failure_reason podman "$code")"
      return 1
      ;;
  esac
  [ "$code" -eq 0 ]
}

server_report() {
  local revision address
  container_report server "$server_container"
  case "$container_word" in
    missing | unreadable) ;;
    *)
      read -r revision address _ <<<"$(server_state)"
      printf 'server_revision=%s\nserver_address=%s\n' "${revision:-}" "${address:-}"
      ;;
  esac
}

database_report() {
  local code=0
  container_report database "$postgres_container"
  case "$container_word" in
    running)
      postgres_ready || code=$?
      case "$code" in
        0) echo database_ready=yes ;;
        1 | 2 | 3) echo database_ready=no ;;
        *) unreadable database_ready "$(failure_reason podman "$code")" ;;
      esac
      ;;
    unreadable) unreadable database_ready "the database container could not be read" ;;
    *) echo database_ready=no ;;
  esac
}

connections_report() {
  local code=0 lines
  lines=$(lsof -nP "-iTCP:$game_port" -sTCP:ESTABLISHED) || code=$?
  case "$code" in
    0 | 1)
      if [ "$code" -eq 1 ] && [ -s "$scratch/error" ]; then
        unreadable game_connections "$(failure_reason lsof "$code")"
      else
        printf 'game_connections=%s\n' "$(printf '%s\n' "$lines" | awk '$1 != "COMMAND" && NF { count++ } END { print count + 0 }')"
      fi
      ;;
    *) unreadable game_connections "$(failure_reason lsof "$code")" ;;
  esac
}

update_lock_report() {
  local owner
  if [ ! -d "$update_lock" ]; then
    echo update_lock=free
    return 0
  fi
  owner=$(update_lock_owner)
  if update_lock_is_stale; then
    echo update_lock=gone
  elif [ -n "$owner" ]; then
    echo update_lock=run
  else
    echo update_lock=ownerless
  fi
  if [ -n "$owner" ]; then printf 'update_lock_pid=%s\n' "$owner"; fi
}

live_lock_report() {
  local pid kind folder
  if ! live_lock_held; then
    echo live_lock=free
    return 0
  fi
  pid=$(lock_field pid)
  kind=$(lock_field kind)
  folder=$(lock_field folder)
  if [ -z "$pid" ]; then
    if ! live_lock_held; then
      echo live_lock=free
      return 0
    fi
    if older_than_a_minute "$home/live.lock"; then echo live_lock=gone; else echo live_lock=ownerless; fi
  elif lock_owner_running; then
    if [ "$kind" = client ]; then echo live_lock=client; else echo live_lock=run; fi
  else
    echo live_lock=gone
  fi
  if [ -n "$kind" ]; then printf 'live_lock_kind=%s\n' "$kind"; fi
  if [ -n "$pid" ]; then printf 'live_lock_pid=%s\n' "$pid"; fi
  if [ -n "$folder" ]; then printf 'live_lock_folder=%s\n' "$folder"; fi
}

if machine_report; then
  server_report
  database_report
  connections_report
fi
if [ -e "$state/held" ]; then echo held=yes; else echo held=no; fi
update_lock_report
live_lock_report
printf 'updater_last_line=%s\n' "$(tail -n 1 "$log_file" 2>/dev/null | tr -d '\r')"
exit 0

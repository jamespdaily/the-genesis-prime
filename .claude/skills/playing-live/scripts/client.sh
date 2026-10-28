#!/usr/bin/env bash
# Starts the WildStar client on the PC in the person's session, types into it and closes it, without
# moving focus: Jim may be using the PC.
#
#   client.sh start [--type-login]   starts the client hidden and logged in from its command line;
#                                    with --type-login, without an account or password
#   client.sh type <text>            posts each character of <text> as WM_CHAR to the client's window
#   client.sh key tab|enter          posts WM_CHAR 0x09 or 0x0D
#   client.sh stop                   closes the client this script started
#
# Needs GENESIS_PLAY_PC (user@host), GENESIS_PLAY_ADDRESS (the server host the client is pointed
# at) and GENESIS_PLAY_CLIENT_DIR (the client's install folder, for example C:\WildStar-HD; the
# program is <dir>\Client64\WildStar64.exe) for start, and GENESIS_PLAY_ACCOUNT and
# GENESIS_PLAY_PASSWORD for start without --type-login, read from ~/.genesis-prime/env.sh when it
# is there. Each command runs a script on the PC (genesis-start.ps1, genesis-input.ps1) through a
# hidden scheduled task (GenesisClient, GenesisInput) that is always deleted. start refuses when
# any WildStar64 process runs, and saves the pid it started in client.pid beside env.sh; stop
# closes only that pid.
set -euo pipefail

usage() { sed -n '5,9p' "$0" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
command=${1:-}
case "$command" in
  start) [ $# -eq 1 ] || { [ $# -eq 2 ] && [ "$2" = --type-login ]; } || usage ;;
  type) [ $# -eq 2 ] || usage ;;
  key)
    [ $# -eq 2 ] || usage
    case "$2" in
      tab) text=$'\t' ;;
      enter) text=$'\r' ;;
      *) usage ;;
    esac ;;
  stop) [ $# -eq 1 ] || usage ;;
  *) usage ;;
esac

home=${GENESIS_HOME:-$HOME/.genesis-prime}
state=$home/client.pid
[ -f "$home/env.sh" ] && . "$home/env.sh"
: "${GENESIS_PLAY_PC:?set GENESIS_PLAY_PC (user@host) in ~/.genesis-prime/env.sh}"
if [ "$command" = start ]; then
  : "${GENESIS_PLAY_ADDRESS:?set GENESIS_PLAY_ADDRESS (the server host the client is pointed at, an address on the PC network) in ~/.genesis-prime/env.sh}"
  : "${GENESIS_PLAY_CLIENT_DIR:?set GENESIS_PLAY_CLIENT_DIR (the client install folder, for example C:\\WildStar-HD) in ~/.genesis-prime/env.sh}"
  if [ $# -eq 1 ]; then
    : "${GENESIS_PLAY_ACCOUNT:?set GENESIS_PLAY_ACCOUNT (the account to log in) in ~/.genesis-prime/env.sh}"
    : "${GENESIS_PLAY_PASSWORD:?set GENESIS_PLAY_PASSWORD (the account password) in ~/.genesis-prime/env.sh}"
  fi
fi
user=${GENESIS_PLAY_PC%@*}
options=(-o BatchMode=yes -o ConnectTimeout=10)
local_file=

on_pc() { ssh "${options[@]}" "$GENESIS_PLAY_PC" "$1"; }
delete_task() { on_pc "schtasks /Delete /F /TN $1 >NUL 2>&1" || true; }
# A task is gone when the PC no longer finds it; anything else fails the run. The files that hold
# the password or the typed text go too, and the local copy.
finish() {
  local status=$? query task
  [ -z "$local_file" ] || rm -f "$local_file"
  on_pc 'del /Q %USERPROFILE%\genesis-start-args.txt %USERPROFILE%\genesis-input.txt 2>NUL' || true
  for task in GenesisClient GenesisInput; do
    query=0
    delete_task "$task"
    on_pc "schtasks /Query /TN $task >NUL 2>&1" || query=$?
    case $query in
      0) echo "client: the $task task is still on the PC; delete it there" >&2; exit 1 ;;
      255) echo "client: could not reach the PC to check the $task task is gone" >&2; exit 1 ;;
    esac
  done
  exit $status
}
trap finish EXIT

# Runs <script> on the PC as the hidden task <task>, and leaves the text it wrote to <result file>
# in $result: run_task <task> <script> <result file> <seconds to wait>. The script writes its
# result file last, so the work is done once it is there.
result=
run_task() {
  local task=$1 script=$2 file=$3 seconds=$4
  scp -q "${options[@]}" "$here/$script" "$GENESIS_PLAY_PC:C:/Users/$user/$script"
  delete_task "$task"
  on_pc "del /Q %USERPROFILE%\\$file 2>NUL & schtasks /Create /F /TN $task /SC ONCE /ST 23:59 /IT /RU $user /TR \"conhost.exe --headless powershell -NoProfile -NonInteractive -WindowStyle Hidden -File C:\\Users\\$user\\$script\" >NUL && schtasks /Run /TN $task >NUL"
  result=
  for _ in $(seq 1 "$seconds"); do
    result=$(on_pc "type %USERPROFILE%\\$file 2>NUL" | tr -d '\r' || true)
    [ -n "$result" ] && break
    sleep 1
  done
  [ -n "$result" ] || { echo "client: $script wrote no result after $seconds s" >&2; exit 1; }
}

# Succeeds when a WildStar64 process runs (the one with the pid given, when there is one), fails
# when none does.
client_running() {
  local filter='' status=0
  if [ -n "${1:-}" ]; then filter=" /FI \"PID eq $1\""; fi
  on_pc "tasklist /NH /FI \"IMAGENAME eq WildStar64.exe\"$filter | findstr /B /I WildStar64.exe >NUL" || status=$?
  [ "$status" -ne 255 ] || { echo "client: could not reach the PC" >&2; exit 1; }
  return "$status"
}

# Closes the client with that pid and no other: taskkill asks first, then forces after a few seconds.
stop_client() {
  local pid=$1
  if client_running "$pid"; then
    on_pc "taskkill /PID $pid /FI \"IMAGENAME eq WildStar64.exe\" >NUL 2>&1" || true
    for _ in 1 2 3 4 5; do
      client_running "$pid" || break
      sleep 1
    done
    if client_running "$pid"; then
      on_pc "taskkill /F /PID $pid /FI \"IMAGENAME eq WildStar64.exe\" >NUL 2>&1" || true
      sleep 1
    fi
    ! client_running "$pid" || { echo "client: WildStar64 $pid is still running on the PC" >&2; exit 1; }
  fi
  rm -f "$state"
}

# Posts the text in $1 to the client's window, and fails when the person's focus moved.
send_input() {
  local pid=0
  [ ! -s "$state" ] || pid=$(cat "$state")
  local_file=$(mktemp)
  printf '%s\n%s' "$pid" "$1" > "$local_file"
  scp -q "${options[@]}" "$local_file" "$GENESIS_PLAY_PC:C:/Users/$user/genesis-input.txt"
  run_task GenesisInput genesis-input.ps1 genesis-input-result.txt 30
  case "$result" in
    typed=*) ;;
    *) echo "client: $result" >&2; exit 1 ;;
  esac
  echo "$result"
  case "$result" in
    *foreground_kept=False*) echo "client: typing took the focus from the person" >&2; exit 1 ;;
  esac
}

case "$command" in
  start)
    status=0
    client_running || status=$?
    [ "$status" -ne 0 ] || { echo "client: a WildStar64 process already runs on the PC; the person may be playing, so nothing was changed" >&2; exit 1; }
    local_file=$(mktemp)
    { printf '%s\n%s\n' "$GENESIS_PLAY_CLIENT_DIR" "$GENESIS_PLAY_ADDRESS"
      [ $# -eq 2 ] || printf '%s\n%s\n' "$GENESIS_PLAY_ACCOUNT" "$GENESIS_PLAY_PASSWORD"
    } > "$local_file"
    scp -q "${options[@]}" "$local_file" "$GENESIS_PLAY_PC:C:/Users/$user/genesis-start-args.txt"
    run_task GenesisClient genesis-start.ps1 genesis-start.txt 90
    case "$result" in
      pid=*) ;;
      *) echo "client: $result" >&2; exit 1 ;;
    esac
    echo "$result"
    pid=${result#pid=}
    pid=${pid%% *}
    mkdir -p "$home"
    echo "$pid" > "$state"
    case "$result" in
      *foreground_kept=False*) echo "client: the start took the focus from the person; the client (pid $pid) still runs, close it with client.sh stop" >&2; exit 1 ;;
    esac ;;
  type) send_input "$2" ;;
  key) send_input "$text" ;;
  stop)
    [ -s "$state" ] || { echo "client: no $state; this script closes only a client it started, and none is recorded" >&2; exit 1; }
    pid=$(cat "$state")
    [[ $pid =~ ^[0-9]+$ ]] || { echo "client: $state does not hold a pid" >&2; exit 1; }
    stop_client "$pid"
    echo "client $pid is closed" ;;
esac

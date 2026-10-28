#!/usr/bin/env bash
# Starts the WildStar client on the PC in the person's session, types into it and closes it, without
# moving focus: Jim may be using the PC. Only click, in takeover mode, takes the focus and the mouse.
#
#   client.sh start [--type-login]   starts the client hidden and logged in from its command line;
#                                    with --type-login, without an account or password
#   client.sh type <text>            posts each character of <text> as WM_CHAR to the client's window;
#                                    a Tab (\t) or Enter (\r) in the text is posted as that key, so a
#                                    whole login is one call: client.sh type $'<account>\t<password>\r'
#   client.sh key tab|enter          posts WM_CHAR 0x09 or 0x0D
#   client.sh click <x> <y> --pc-free  takeover mode: brings the client's window forward, moves the real
#                                    mouse to the client point (x, y) and clicks the left button there;
#                                    refuses without --pc-free (or GENESIS_PC_FREE=1 in the environment)
#   client.sh click <target> --pc-free  the same at a named point of the 3840x2160 client: enter-game,
#                                    create-none and create-one (the create row with no or one
#                                    character), next, novice, veteran, human, warrior, soldier,
#                                    randomize, first-name, last-name
#   client.sh stop                   closes the client this script started
#
# Needs GENESIS_PLAY_PC (user@host), GENESIS_PLAY_ADDRESS (the server host the client is pointed
# at) and GENESIS_PLAY_CLIENT_DIR (the client's install folder, for example C:\WildStar-HD; the
# program is <dir>\Client64\WildStar64.exe) for start, and GENESIS_PLAY_ACCOUNT and
# GENESIS_PLAY_PASSWORD for start without --type-login, read from ~/.genesis-prime/env.sh when it
# is there. start and type run a script on the PC (genesis-start.ps1, genesis-input.ps1) through a
# hidden scheduled task (GenesisClient, GenesisInput), by pc.sh; the task and the files it copied
# are always deleted. start refuses, in the script and before it launches anything, when any
# WildStar64 process runs, and saves the client's pid and start time in client.pid beside env.sh.
# type, key, click and stop act only on the process with that pid, that name and that start time, so
# a reused pid never reaches another client; with no client recorded, type, key and click refuse.
# click runs genesis-click.ps1 (task GenesisClick) and is the one command that moves focus: the
# client reads the real cursor for its pointer (fact 0x1403f3790), so a posted click never reaches
# it. It checks --pc-free or GENESIS_PC_FREE=1 before it touches the PC.
set -euo pipefail

usage() { sed -n '5,19p' "$0" >&2; exit 2; }

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
  click)
    # Points read from screenshots of the client at 3840x2160 (a 1280 screenshot's point times 3).
    case "${2:-}" in
      enter-game) point='1920 2076' ;;
      create-none) point='315 897' ;;
      create-one) point='315 1011' ;;
      next) point='3720 2046' ;;
      novice) point='1554 1095' ;;
      veteran) point='2292 1095' ;;
      human) point='810 1350' ;;
      warrior) point='1245 1425' ;;
      soldier) point='1248 1275' ;;
      randomize) point='180 795' ;;
      first-name) point='1755 1986' ;;
      last-name) point='2115 1986' ;;
      *) point= ;;
    esac
    if [ -n "$point" ]; then
      set -- click $point "${@:3}"
    fi
    [ $# -eq 3 ] || { [ $# -eq 4 ] && [ "$4" = --pc-free ]; } || usage
    [[ $2 =~ ^[0-9]+$ && $3 =~ ^[0-9]+$ ]] || usage
    if [ $# -eq 3 ] && [ "${GENESIS_PC_FREE:-}" != 1 ]; then
      echo "client: click takes the PC's focus and mouse; it runs only with --pc-free or GENESIS_PC_FREE=1, when the PC is free" >&2
      exit 1
    fi ;;
  stop) [ $# -eq 1 ] || usage ;;
  *) usage ;;
esac

tool=client
. "$(dirname "$0")/pc.sh"
if [ "$command" = start ]; then
  : "${GENESIS_PLAY_ADDRESS:?set GENESIS_PLAY_ADDRESS (the server host the client is pointed at, an address on the PC network) in ~/.genesis-prime/env.sh}"
  : "${GENESIS_PLAY_CLIENT_DIR:?set GENESIS_PLAY_CLIENT_DIR (the client install folder, for example C:\\WildStar-HD) in ~/.genesis-prime/env.sh}"
  if [ $# -eq 1 ]; then
    : "${GENESIS_PLAY_ACCOUNT:?set GENESIS_PLAY_ACCOUNT (the account to log in) in ~/.genesis-prime/env.sh}"
    : "${GENESIS_PLAY_PASSWORD:?set GENESIS_PLAY_PASSWORD (the account password) in ~/.genesis-prime/env.sh}"
  fi
fi

# Saves the pid and start time that genesis-start.ps1 reported in $result.
save_state() {
  pid=${result#pid=}; pid=${pid%% *}
  started=${result#*start=}; started=${started%% *}
  [[ $pid =~ ^[0-9]+$ && $started =~ ^[0-9]+$ ]] || { echo "client: the start result has no pid and start time: $result" >&2; exit 1; }
  mkdir -p "$home"
  echo "$pid $started" > "$state"
}

# Posts the text in $1 to the client's window.
send_input() {
  read_state
  printf '%s\n%s\n%s' "$pid" "$started" "$1" > "$pc_tmp/input"
  run_task GenesisInput genesis-input.ps1 genesis-input-result.txt 30 "$pc_tmp/input"
  case "$result" in
    typed=*) echo "$result" ;;
    *) echo "client: $result" >&2; exit 1 ;;
  esac
}

# Clicks the client point $1, $2 with the real mouse (takeover mode, checked above).
send_click() {
  read_state
  printf '%s\n%s\n%s\n%s' "$pid" "$started" "$1" "$2" > "$pc_tmp/click"
  run_task GenesisClick genesis-click.ps1 genesis-click-result.txt 30 "$pc_tmp/click"
  case "$result" in
    clicked=*) echo "$result" ;;
    *) echo "client: $result" >&2; exit 1 ;;
  esac
}

case "$command" in
  start)
    # run_task calls this when the start moved the person's focus: the client runs, so it is recorded.
    on_focus_lost() {
      save_state
      echo "client: the client (pid $pid) still runs, close it with client.sh stop" >&2
    }
    { printf '%s\n%s\n' "$GENESIS_PLAY_CLIENT_DIR" "$GENESIS_PLAY_ADDRESS"
      [ $# -eq 2 ] || printf '%s\n%s\n' "$GENESIS_PLAY_ACCOUNT" "$GENESIS_PLAY_PASSWORD"
    } > "$pc_tmp/args"
    run_task GenesisClient genesis-start.ps1 genesis-start.txt 90 "$pc_tmp/args"
    case "$result" in
      pid=*) ;;
      *) echo "client: $result" >&2; exit 1 ;;
    esac
    echo "$result"
    save_state ;;
  type) send_input "$2" ;;
  key) send_input "$text" ;;
  click) send_click "$2" "$3" ;;
  stop)
    read_state
    # On the PC in one call: the process must be WildStar64 with the recorded start time, or it is
    # not our client (the pid was reused) and nothing is touched. The process is ended outright: a
    # close asked from the ssh session cannot reach a window in the person's session (taskkill
    # without /F answers that the process can only be terminated forcefully).
    out=$(on_pc_ps_try "\$p = Get-Process -Id $pid -ErrorAction SilentlyContinue
if (-not \$p -or \$p.ProcessName -ne 'WildStar64' -or \$p.StartTime.ToFileTimeUtc() -ne $started) { 'gone' }
else {
  \$p.Kill()
  if (-not \$p.WaitForExit(5000)) { throw 'it is still running after the kill' }
  'closed'
}")
    case "$out" in
      closed) rm -f "$state"; echo "client $pid is closed" ;;
      gone) rm -f "$state"; echo "client $pid was not running; nothing was changed" ;;
      *) echo "client: the PC answered $out; WildStar64 $pid was not confirmed closed" >&2; exit 1 ;;
    esac ;;
esac

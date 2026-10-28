# How the playing-live scripts reach the play PC. Sourced by client.sh, screenshot.sh, client-log.sh
# and report.sh, never run; the script that sources it has set -euo pipefail, and may set `tool`
# (its name, the prefix of every message here) first.
#
# It reads ~/.genesis-prime/env.sh (or $GENESIS_HOME/env.sh) and needs GENESIS_PLAY_PC (user@host),
# then provides:
#   on_pc <cmd text>             runs a command in the PC's cmd.exe
#   on_pc_ps <powershell text>   runs PowerShell text on the PC, passed encoded so no quoting
#                                reaches the PC's shell; stops on the first error
#   run_task <task> <script> <result file> <seconds> [input file]
#                                copies <script> (and the input, as <script>.in) to the PC's profile,
#                                runs it as the hidden task <task> in the person's session, waits on
#                                the PC for <result file> and leaves its one line in $result. The
#                                script must write that file last and all at once (write a .tmp,
#                                then move it). Fails on a result starting "error:", on a timeout
#                                (after ending the task) and on "foreground_kept=False" (after
#                                calling on_focus_lost, when the caller defined it).
#   pc_track <file>              a file the script leaves in the PC's profile, deleted at the end
#   read_state                   reads the pid and start time (a file time in UTC) of the client that
#                                client.sh start recorded in $state (client.pid beside env.sh) into
#                                $pid and $started; ends the script when none is recorded
# A trap on EXIT deletes only the tasks and files this run used, in one ssh, and fails when any is
# still on the PC or the PC cannot be reached. A run that used none (stop) does not call the PC.
# PowerShell runs without -ExecutionPolicy Bypass: the PC's CurrentUser policy is RemoteSigned.

home=${GENESIS_HOME:-$HOME/.genesis-prime}
if [ -f "$home/env.sh" ]; then . "$home/env.sh"; fi
: "${GENESIS_PLAY_PC:?set GENESIS_PLAY_PC (user@host) in ~/.genesis-prime/env.sh}"
user=${GENESIS_PLAY_PC%@*}
options=(-o BatchMode=yes -o ConnectTimeout=10)
pc_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# A private folder for what is copied to the PC (it may hold the password); removed on exit.
pc_tmp=$(mktemp -d)
pc_tasks=()
pc_files=()
result=
state=$home/client.pid

on_pc() { ssh "${options[@]}" "$GENESIS_PLAY_PC" "$1"; }

ps_encode() {
  printf '%s' "\$ProgressPreference = 'SilentlyContinue'
\$ErrorActionPreference = 'Stop'
$1" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n'
}

on_pc_ps() {
  ssh "${options[@]}" "$GENESIS_PLAY_PC" "powershell -NoProfile -NonInteractive -EncodedCommand $(ps_encode "$1")" | tr -d '\r'
}

pc_track() { pc_files+=("$1"); }

read_state() {
  [ -s "$state" ] || { echo "${tool:-pc}: no $state; client.sh start records the client it starts there, and none is recorded" >&2; exit 1; }
  read -r pid started < "$state"
  [[ $pid =~ ^[0-9]+$ && ${started:-} =~ ^[0-9]+$ ]] || { echo "${tool:-pc}: $state does not hold a pid and a start time" >&2; exit 1; }
}

run_task() {
  local task=$1 script=$2 file=$3 seconds=$4 input=${5:-}
  local stage=$pc_tmp/stage staged out status=0 cmd waiter
  pc_tasks+=("$task")
  pc_files+=("$script" "$script.in" "$file" "$file.tmp")

  mkdir -p "$stage"
  cp "$pc_dir/$script" "$stage/$script"
  staged=("$stage/$script")
  cmd="del /Q \"%USERPROFILE%\\$file\" \"%USERPROFILE%\\$file.tmp\" 2>NUL"
  if [ -n "$input" ]; then
    cp "$input" "$stage/$script.in"
    staged+=("$stage/$script.in")
  else
    cmd="del /Q \"%USERPROFILE%\\$script.in\" 2>NUL & $cmd"
  fi
  scp -q "${options[@]}" "${staged[@]}" "$GENESIS_PLAY_PC:C:/Users/$user/" || { echo "${tool:-pc}: could not copy $script to the PC" >&2; exit 1; }

  # On the PC: wait for the result file; at the deadline end the task and wait for it to stop,
  # since deleting a running task leaves it running.
  waiter=$(cat <<EOF
\$file = Join-Path \$env:USERPROFILE '$file'
\$deadline = (Get-Date).AddSeconds($seconds)
while (-not (Test-Path \$file)) {
  if ((Get-Date) -gt \$deadline) {
    try {
      schtasks /End /TN '$task' | Out-Null
      \$stop = (Get-Date).AddSeconds(15)
      while ((Get-ScheduledTask -TaskName '$task').State -eq 'Running' -and (Get-Date) -lt \$stop) { Start-Sleep -Milliseconds 200 }
    } catch {}
    exit 124
  }
  Start-Sleep -Milliseconds 200
}
Get-Content -Raw \$file
EOF
)
  cmd="$cmd & schtasks /Create /F /TN $task /SC ONCE /ST 23:59 /IT /RU \"$user\" /TR \"conhost.exe --headless powershell -NoProfile -NonInteractive -WindowStyle Hidden -File \\\"%USERPROFILE%\\$script\\\"\" >NUL && schtasks /Run /TN $task >NUL && powershell -NoProfile -NonInteractive -EncodedCommand $(ps_encode "$waiter")"
  out=$(ssh "${options[@]}" "$GENESIS_PLAY_PC" "$cmd") || status=$?
  case $status in
    0) ;;
    124) echo "${tool:-pc}: $script wrote no result after $seconds s; its task was ended" >&2; exit 1 ;;
    255) echo "${tool:-pc}: could not reach the PC" >&2; exit 1 ;;
    *) echo "${tool:-pc}: could not create or run the $task task on the PC (status $status)" >&2; exit 1 ;;
  esac

  result=$(printf '%s' "$out" | tr -d '\r')
  case "$result" in
    "") echo "${tool:-pc}: $script wrote an empty result" >&2; exit 1 ;;
    error:*) echo "${tool:-pc}: ${result#error: }" >&2; exit 1 ;;
    *foreground_kept=False*)
      echo "${tool:-pc}: $script took the focus from the person ($result)" >&2
      if declare -F on_focus_lost >/dev/null; then on_focus_lost; fi
      exit 1 ;;
  esac
}

# Deletes this run's tasks and files, and checks they are gone: 255 means the PC cannot be reached.
finish() {
  local status=$? cmd='' name task out query=0
  rm -rf "$pc_tmp"
  if [ ${#pc_tasks[@]} -gt 0 ] || [ ${#pc_files[@]} -gt 0 ]; then
    if [ ${#pc_tasks[@]} -gt 0 ]; then
      for task in "${pc_tasks[@]}"; do cmd+="schtasks /Delete /F /TN $task >NUL 2>&1 & "; done
    fi
    if [ ${#pc_files[@]} -gt 0 ]; then
      for name in "${pc_files[@]}"; do cmd+="del /F /Q \"%USERPROFILE%\\$name\" >NUL 2>&1 & "; done
    fi
    if [ ${#pc_tasks[@]} -gt 0 ]; then
      for task in "${pc_tasks[@]}"; do cmd+="(schtasks /Query /TN $task >NUL 2>&1 && echo task $task) & "; done
    fi
    if [ ${#pc_files[@]} -gt 0 ]; then
      for name in "${pc_files[@]}"; do cmd+="(if exist \"%USERPROFILE%\\$name\" echo file $name) & "; done
    fi
    out=$(ssh "${options[@]}" "$GENESIS_PLAY_PC" "${cmd% & }" | tr -d '\r') || query=$?
    if [ "$query" -eq 255 ]; then
      echo "${tool:-pc}: could not reach the PC to check its task and files are gone" >&2
      exit 1
    elif [ -n "$out" ]; then
      echo "${tool:-pc}: still on the PC, delete it there: $(echo $out)" >&2
      exit 1
    fi
  fi
  exit $status
}
trap finish EXIT

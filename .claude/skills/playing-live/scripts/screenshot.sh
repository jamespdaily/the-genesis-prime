#!/usr/bin/env bash
# Takes a picture of the client's window on the PC without moving focus, and copies it here.
#
#   screenshot.sh [destination.png]
#
# Needs GENESIS_PLAY_PC (user@host), read from ~/.genesis-prime/env.sh when it is there.
# A hidden scheduled task runs genesis-shot.ps1 on the PC; the task is always deleted.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
destination=${1:-genesis-shot.png}
[ -f "${GENESIS_HOME:-$HOME/.genesis-prime}/env.sh" ] && . "${GENESIS_HOME:-$HOME/.genesis-prime}/env.sh"
: "${GENESIS_PLAY_PC:?set GENESIS_PLAY_PC (user@host) in ~/.genesis-prime/env.sh}"
user=${GENESIS_PLAY_PC%@*}
options=(-o BatchMode=yes -o ConnectTimeout=10)

on_pc() { ssh "${options[@]}" "$GENESIS_PLAY_PC" "$1"; }
delete_task() { on_pc 'schtasks /Delete /F /TN GenesisShot >NUL 2>&1' || true; }
trap delete_task EXIT

rm -f "$destination"
scp -q "${options[@]}" "$here/genesis-shot.ps1" "$GENESIS_PLAY_PC:C:/Users/$user/genesis-shot.ps1"
delete_task
on_pc "del /Q %USERPROFILE%\\genesis-shot.png %USERPROFILE%\\genesis-shot.txt 2>NUL & schtasks /Create /F /TN GenesisShot /SC ONCE /ST 23:59 /IT /RU $user /TR \"conhost.exe --headless powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\\Users\\$user\\genesis-shot.ps1\" >NUL && schtasks /Run /TN GenesisShot >NUL"

# The script writes genesis-shot.txt last, so the picture is ready once it is there.
for _ in $(seq 1 "${SCREENSHOT_SECONDS:-30}"); do
  result=$(on_pc 'type %USERPROFILE%\genesis-shot.txt 2>NUL' || true)
  [ -n "$result" ] && break
  sleep 1
done
case "$result" in
  printwindow=*) ;;
  "") echo "screenshot: no picture after ${SCREENSHOT_SECONDS:-30} s" >&2; exit 1 ;;
  *) echo "screenshot: $result" >&2; exit 1 ;;
esac
scp -q "${options[@]}" "$GENESIS_PLAY_PC:C:/Users/$user/genesis-shot.png" "$destination"
echo "$destination ($result)"

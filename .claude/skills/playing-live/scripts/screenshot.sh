#!/usr/bin/env bash
# Takes a picture of the client's window on the PC without moving focus, and copies it here.
#
#   screenshot.sh [destination.png]
#
# Needs GENESIS_PLAY_PC (user@host), read from ~/.genesis-prime/env.sh when it is there.
# A hidden scheduled task runs genesis-shot.ps1 on the PC, by pc.sh; the task and the files it
# copied are always deleted. When client.sh has recorded a client (client.pid beside env.sh), the
# picture is of that process, checked by pid, name and start time; otherwise of the first WildStar64
# window. SCREENSHOT_SECONDS (default 30) is how long to wait for the picture.
set -euo pipefail

destination=${1:-genesis-shot.png}
tool=screenshot
. "$(dirname "$0")/pc.sh"
seconds=${SCREENSHOT_SECONDS:-30}

input=
if [ -s "$home/client.pid" ]; then input=$home/client.pid; fi
pc_track genesis-shot.png
rm -f "$destination"
run_task GenesisShot genesis-shot.ps1 genesis-shot.txt "$seconds" "$input"
case "$result" in
  printwindow=True*) ;;
  *) echo "screenshot: $result" >&2; exit 1 ;;
esac
scp -q "${options[@]}" "$GENESIS_PLAY_PC:C:/Users/$user/genesis-shot.png" "$destination"
echo "$destination ($result)"

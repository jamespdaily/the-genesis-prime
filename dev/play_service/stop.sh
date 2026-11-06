#!/usr/bin/env bash
# Stops the play server container, so the game ports are free: SIGTERM, which
# stops the server's supervision tree in order and closes every recording, and
# SIGKILL after 60 s. Postgres keeps running. Prints one line: "stopped" when it
# stopped a running server, "not running" when the container was stopped or
# there is none. session.sh uses the word to know whether to start it again.
#
# Usage: stop.sh [--hold]
#
# --hold also makes update.sh leave the service alone until start.sh releases
# it, for a stop by hand; session.sh holds the live lock instead.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

case "${1:-}" in
  "") ;;
  --hold) mkdir -p "$state" && : >"$state/held" ;;
  *) echo "usage: stop.sh [--hold]" >&2; exit 2 ;;
esac

if container_running "$server_container"; then
  podman stop --time 60 "$server_container" >/dev/null
  log "$server_container stopped"
  echo stopped
else
  echo "not running"
fi

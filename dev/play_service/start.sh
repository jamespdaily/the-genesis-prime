#!/usr/bin/env bash
# Starts the play server container again after stop.sh, once Postgres accepts
# connections, and releases a `stop.sh --hold`. It starts the container as it
# was made (the address update.sh gave it); the next update.sh run replaces it
# when the address has changed. Prints "started", or "not installed" when there
# is no server container (update.sh makes it).
#
# Usage: start.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

rm -f "$state/held"
if ! podman container exists "$server_container"; then
  echo "not installed"
  exit 0
fi
load_environment
ensure_postgres
podman start "$server_container" >/dev/null
log "$server_container started"
echo started

# Sourced by update.sh, start.sh, stop.sh and install.sh, never run: the play
# service's names, and what two or more of them do. The play server runs as two
# containers on one Podman network (a pod would keep the game ports bound while
# the server container is stopped, and a recording run needs them free):
#
#   genesis-play-postgres   postgres:18, data in the volume genesis-play-data,
#                           published on 127.0.0.1:5434 for the tools on the Mac
#   genesis-play            the server's image (release/Containerfile), reaches
#                           Postgres by its name on the network; publishes 6600,
#                           23115 and 24000 for the PC
#
# The machine's values come from $home/env.sh (default ~/.genesis-prime), never
# from this repository: GENESIS_PLAY_ADDRESS (this Mac's address on the PC's
# network, worked out at each read), GENESIS_PLAY_ACCOUNT and
# GENESIS_PLAY_PGPASSWORD (the play Postgres's password, which install.sh makes).
# provides:
#   home, state, log_file          where the service keeps its files
#   log MESSAGE                    appends a time-stamped line to log_file, and prints it when
#                                  standard output is a terminal (launchd keeps the output in a
#                                  file of its own, so a printed line would be there twice)
#   log_once MESSAGE               the same, unless the last line the service wrote was this
#                                  one, so a decision that stays is written once
#   skip_commit COMMIT, is_skipped COMMIT   the commits not to try again (a file in state)
#   load_environment               reads env.sh and checks the values above are set
#   live_lock_held                 whether a live session holds ~/.genesis-prime/live.lock
#   machine_up                     starts the Podman machine when it is not running
#   container_running NAME         whether the container exists and is running
#   ensure_postgres                makes the network and the Postgres container, starts it,
#                                  and returns once it accepts connections
#   server_state                   prints "REVISION ADDRESS RUNNING" of the server container,
#                                  nothing when there is none
#   run_server IMAGE REVISION ADDRESS   replaces the server container with a new one
#   wait_up                        waits for the server container's ready line; on a container
#                                  that exited or restarted, or no line in time, logs its state,
#                                  exit code and last lines and fails

home=${GENESIS_HOME:-$HOME/.genesis-prime}
state=$home/play-service
log_file=$home/play-service.log

network=genesis-play
postgres_container=genesis-play-postgres
postgres_volume=genesis-play-data
postgres_image=docker.io/library/postgres:18
postgres_port=5434
server_container=genesis-play
play_database=genesis_play

log() {
  local line
  mkdir -p "$(dirname "$log_file")" "$state"
  line=$(printf '%s play-service: %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$*")
  printf '%s\n' "$line" >>"$log_file"
  printf '%s' "$*" >"$state/last_line"
  if [ -t 1 ]; then printf '%s\n' "$line"; fi
}

log_once() {
  if [ "$(cat "$state/last_line" 2>/dev/null || true)" = "$*" ]; then
    return 0
  fi
  log "$*"
}

skip_commit() { mkdir -p "$state" && echo "$1" >>"$state/skipped"; }

is_skipped() { grep -qx "$1" "$state/skipped" 2>/dev/null; }

load_environment() {
  if [ -f "$home/env.sh" ]; then
    # shellcheck disable=SC1091
    . "$home/env.sh"
  fi
  : "${GENESIS_PLAY_ADDRESS:?set GENESIS_PLAY_ADDRESS (the address of this machine on the PC network) in $home/env.sh}"
  : "${GENESIS_PLAY_ACCOUNT:?set GENESIS_PLAY_ACCOUNT in $home/env.sh}"
  : "${GENESIS_PLAY_PGPASSWORD:?set GENESIS_PLAY_PGPASSWORD (the password of the play Postgres) in $home/env.sh; dev/play_service/install.sh makes it}"
  tables=${GENESIS_TABLE_DIR:-$home/tables}
  PGPASSWORD=$GENESIS_PLAY_PGPASSWORD
  POSTGRES_PASSWORD=$GENESIS_PLAY_PGPASSWORD
  export PGPASSWORD POSTGRES_PASSWORD GENESIS_PLAY_ACCOUNT
}

live_lock_held() { [ -d "$home/live.lock" ]; }

machine_up() {
  podman info >/dev/null 2>&1 && return 0
  log "the Podman machine is not running; starting it"
  podman machine start >/dev/null 2>&1 || true
  podman info >/dev/null 2>&1
}

# container_running NAME: whether the container exists and is running. The
# answer is read into a variable first, and no apostrophe stands in a ${x:?word}:
# bash 3.2, the /bin/bash launchd runs, misparses both.
container_running() {
  local running
  running=$(podman container inspect --format '{{.State.Running}}' "$1" 2>/dev/null) || return 1
  [ "$running" = true ]
}

# Waits until Postgres in its container accepts a connection to the play database:
# GENESIS_PLAY_POSTGRES_ATTEMPTS asks (default 120) GENESIS_PLAY_POLL_SECONDS
# apart (default 1).
wait_for_postgres() {
  local waited=0
  until podman exec "$postgres_container" pg_isready -q -U postgres -d "$play_database"; do
    waited=$((waited + 1))
    if [ "$waited" -ge "${GENESIS_PLAY_POSTGRES_ATTEMPTS:-120}" ]; then
      log "Postgres did not accept a connection in ${GENESIS_PLAY_POSTGRES_ATTEMPTS:-120} asks"
      return 1
    fi
    sleep "${GENESIS_PLAY_POLL_SECONDS:-1}"
  done
}

ensure_postgres() {
  podman network exists "$network" || podman network create "$network" >/dev/null
  if podman container exists "$postgres_container"; then
    if ! container_running "$postgres_container"; then
      log "starting $postgres_container"
      podman start "$postgres_container" >/dev/null
    fi
  else
    log "making $postgres_container (postgres 18, volume $postgres_volume)"
    mkdir -p "$state"
    podman run -d --name "$postgres_container" --network "$network" \
      --restart=on-failure \
      -v "$postgres_volume:/var/lib/postgresql" \
      -p "127.0.0.1:$postgres_port:5432" \
      -e POSTGRES_PASSWORD -e POSTGRES_DB="$play_database" \
      "$postgres_image" >/dev/null
  fi
  wait_for_postgres
}

server_state() {
  podman container inspect \
    --format '{{index .Config.Labels "genesis.revision"}} {{index .Config.Labels "genesis.address"}} {{.State.Running}}' \
    "$server_container" 2>/dev/null || true
}

run_server() {
  local image=$1 revision=$2 address=$3
  mkdir -p "$home/sittings"
  podman run -d --replace --name "$server_container" --network "$network" \
    --restart=on-failure:5 --memory 3g --stop-timeout 60 \
    -p 6600:6600 -p 23115:23115 -p 24000:24000 \
    -v "$tables:/tables:ro" -v "$home/sittings:/sittings" \
    --label "genesis.revision=$revision" --label "genesis.address=$address" \
    -e PGHOST="$postgres_container" -e PGPORT=5432 -e PGUSER=postgres \
    -e PGDATABASE="$play_database" -e PGPASSWORD \
    -e GENESIS_GAME_ADDRESS="$address" -e GENESIS_REALM_NAME=Genesis \
    -e GENESIS_PLAY_ACCOUNT -e GENESIS_SITTINGS_DIR=/sittings \
    "$image" >/dev/null
}

# server_ready: whether the server container has said its ready line.
server_ready() {
  podman logs "$server_container" 2>&1 | grep -q 'serves the STS login'
}

# server_failure: prints why the server container is not well and succeeds when it
# is not well: not running, or restarted since it was made (a crash). The format
# is read into a variable first, for bash 3.2.
server_failure() {
  local info status code restarts
  info=$(podman container inspect --format '{{.State.Status}} {{.State.ExitCode}} {{.RestartCount}}' "$server_container" 2>/dev/null) || {
    echo "the container is gone"
    return 0
  }
  read -r status code restarts <<<"$info"
  if [ "$status" != running ] || [ "${restarts:-0}" -gt 0 ]; then
    echo "state $status, exit code $code, restarted $restarts times; its last lines: $(podman logs --tail 5 "$server_container" 2>&1 | tr '\n' '|')"
    return 0
  fi
  return 1
}

wait_up() {
  local waited=0 failure
  until server_ready; do
    if failure=$(server_failure); then
      log "$server_container did not come up: $failure"
      return 1
    fi
    waited=$((waited + 1))
    if [ "$waited" -ge "${GENESIS_PLAY_UP_ATTEMPTS:-300}" ]; then
      log "$server_container said no ready line in ${GENESIS_PLAY_UP_ATTEMPTS:-300} asks"
      return 1
    fi
    sleep "${GENESIS_PLAY_POLL_SECONDS:-1}"
  done
}

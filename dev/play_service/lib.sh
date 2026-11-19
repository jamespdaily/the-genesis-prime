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
# GENESIS_PLAY_PGPASSWORD (the play Postgres's password, which install.sh makes). Two more
# are optional: GENESIS_PLAY_ALERT_CHANNEL (the Discord channel a failed deploy is posted
# to) and GENESIS_PLAY_ALERT_TOKEN_FILE (the file holding the bot's DISCORD_BOT_TOKEN=
# line, the Discord plugin's; the token itself is never in env.sh).
# provides:
#   home, state, log_file          where the service keeps its files
#   log MESSAGE                    appends a time-stamped line to log_file, and prints it when
#                                  standard output is a terminal (launchd keeps the output in a
#                                  file of its own, so a printed line would be there twice)
#   log_once MESSAGE               the same, unless the last line the service wrote was this
#                                  one, so a decision that stays is written once
#   skip_commit COMMIT, is_skipped COMMIT   the commits not to try again (a file in state)
#   read_environment_file          reads env.sh when there is one, setting nothing else
#   load_environment               reads env.sh and checks the values above are set
#   load_config                    reads $state/config.sh and checks it sets remote and repository;
#                                  branch defaults to main
#   remote_head                    prints the commit the remote's branch is at; fails when it
#                                  cannot be read
#   live_lock_held                 whether a live session holds ~/.genesis-prime/live.lock
#   alert_stale_stands             posts one alert line, once per lock or hold, when the live lock
#                                  or the hold has stood over an hour while the remote's branch is
#                                  at a commit the server container does not run; never takes the
#                                  lock or the hold over
#   machine_up                     starts the Podman machine when it is not running
#   container_running NAME         whether the container exists and is running
#   ensure_postgres                makes the network and the Postgres container, starts it,
#                                  and returns once it accepts connections
#   server_state                   prints "REVISION ADDRESS RUNNING" of the server container,
#                                  nothing when there is none
#   run_server IMAGE REVISION ADDRESS   replaces the server container with a new one
#   wait_up                        waits for the server container's ready line; on a container
#                                  that exited or restarted, or no line in time, logs its state,
#                                  exit code and last lines and fails; sets up_failure to the
#                                  state, exit code and restarts, without the last lines
#   alert MESSAGE                  posts one line to the Discord channel; a missing setting or a
#                                  refused post is logged and never fails the caller

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

read_environment_file() {
  if [ -f "$home/env.sh" ]; then
    # shellcheck disable=SC1091
    . "$home/env.sh"
  fi
}

load_environment() {
  read_environment_file
  : "${GENESIS_PLAY_ADDRESS:?set GENESIS_PLAY_ADDRESS (the address of this machine on the PC network) in $home/env.sh}"
  : "${GENESIS_PLAY_ACCOUNT:?set GENESIS_PLAY_ACCOUNT in $home/env.sh}"
  : "${GENESIS_PLAY_PGPASSWORD:?set GENESIS_PLAY_PGPASSWORD (the password of the play Postgres) in $home/env.sh; dev/play_service/install.sh makes it}"
  tables=${GENESIS_TABLE_DIR:-$home/tables}
  terrain=${GENESIS_TERRAIN_DIR:-$home/terrain}
  PGPASSWORD=$GENESIS_PLAY_PGPASSWORD
  POSTGRES_PASSWORD=$GENESIS_PLAY_PGPASSWORD
  export PGPASSWORD POSTGRES_PASSWORD GENESIS_PLAY_ACCOUNT
}

# load_config: reads config.sh, which install.sh wrote: the remote, the repository and,
# to follow a branch other than main before it merges, a `branch=` line.
load_config() {
  # shellcheck source=/dev/null
  . "$state/config.sh"
  : "${remote:?config.sh sets no remote}" "${repository:?config.sh sets no repository}"
  branch=${branch:-main}
}

# remote_head: prints the commit the remote's branch is at. Fails when the remote cannot
# be asked or has no such branch.
remote_head() {
  local head
  head=$(git ls-remote "$remote" "refs/heads/$branch" | cut -f1) || return 1
  [ -n "$head" ] || return 1
  printf '%s\n' "$head"
}

live_lock_held() { [ -d "$home/live.lock" ]; }

# The time a live lock or a hold may stand, with the remote's branch ahead of the server,
# before alert_stale_stands posts it.
stale_stand_seconds=3600

# lock_field KEY: a field of the live lock's owner record (live_lock.sh writes one key=value
# line per field), empty when there is none. The lock's script is not sourced here: the
# installed copies of this service's scripts stand alone.
lock_field() { sed -n "/^$1=/{s///p;q;}" "$home/live.lock/owner" 2>/dev/null || true; }

# lock_owner_running: whether the process that took the live lock is still the one that
# started at the recorded time (a pid the system has reused is not it).
lock_owner_running() {
  local pid started
  pid=$(lock_field pid)
  started=$(lock_field started)
  [ -n "$pid" ] || return 1
  [ -n "$started" ] || return 1
  [ "$(ps -o lstart= -p "$pid" 2>/dev/null | awk '{ $1 = $1; print }')" = "$started" ]
}

# stale_stand_description KIND: who holds the live lock, or the hold, and the command that
# releases it, as one phrase for the alert.
stale_stand_description() {
  local scripts=.claude/skills/playing-live/scripts running=gone
  if [ "$1" = hold ]; then
    echo "the service is held by stop.sh --hold; dev/play_service/start.sh releases it"
    return 0
  fi
  if [ -z "$(lock_field pid)" ]; then
    echo "live.lock has no owner record; $scripts/session.sh --recover releases it once it is over a minute old"
    return 0
  fi
  if lock_owner_running; then running=running; fi
  if [ "$(lock_field kind)" = client ]; then
    echo "live.lock is held by a client.sh start (process $(lock_field pid), $running); $scripts/client.sh stop releases it"
  elif [ "$running" = running ]; then
    echo "live.lock is held by the run in $(lock_field folder) (session.sh process $(lock_field pid), running); it is released when the run ends"
  else
    echo "live.lock is held by the run in $(lock_field folder) (session.sh process $(lock_field pid), gone); $scripts/session.sh --recover releases it"
  fi
}

# alert_stale_stands: for the live lock and for the hold, once it has stood over
# stale_stand_seconds (by the mtime of the lock's owner record, or of the lock folder when
# it has none, and of the held file) while the remote's branch is at a commit that is not
# skipped and not the one the server container runs, posts one alert line naming the
# holder, whether its process runs and the command that releases it. The marker
# $state/stale_<lock|hold>_alerted holds the lock's token (or the stand file's mtime), so
# a stand is announced once; it is removed when the stand is gone. Nothing is taken over,
# and a stand with no config, no answer from the remote or no server container is left
# unannounced. The line it logs does not replace the last line log_once compares.
alert_stale_stands() {
  local kind file key age branch_commit deployed previous_line
  for kind in lock hold; do
    if [ "$kind" = lock ]; then
      file=$home/live.lock/owner
      [ -e "$file" ] || file=$home/live.lock
    else
      file=$state/held
    fi
    if [ ! -e "$file" ]; then
      rm -f "$state/stale_${kind}_alerted"
      continue
    fi
    key=
    [ "$kind" != lock ] || key=$(lock_field token)
    [ -n "$key" ] || key=$(stat -f %m "$file")
    [ "$(cat "$state/stale_${kind}_alerted" 2>/dev/null || true)" != "$key" ] || continue
    age=$(($(date +%s) - $(stat -f %m "$file")))
    [ "$age" -gt "$stale_stand_seconds" ] || continue
    [ -f "$state/config.sh" ] || continue
    branch_commit=$(load_config && remote_head) || continue
    ! is_skipped "$branch_commit" || continue
    read -r deployed _ <<<"$(server_state)"
    deployed=${deployed:-}
    [ -n "$deployed" ] || continue
    [ "$deployed" != "$branch_commit" ] || continue
    read_environment_file
    previous_line=$(cat "$state/last_line" 2>/dev/null || true)
    alert "genesis play: ${branch_commit:0:8} is the remote branch's head but the server runs ${deployed:0:8}, and the updater has done nothing for $((age / 3600)) h: $(stale_stand_description "$kind")"
    printf '%s' "$previous_line" >"$state/last_line"
    printf '%s' "$key" >"$state/stale_${kind}_alerted"
  done
}

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
    -v "$tables:/tables:ro" -v "$terrain:/terrain:ro" -v "$home/sittings:/sittings" \
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

# wait_up: waits for the ready line. When it fails, up_failure holds why in a few words
# (the state, exit code and restarts, or the asks that passed), safe to post: it holds
# no line of the container's log.
wait_up() {
  local waited=0 failure
  up_failure=
  until server_ready; do
    if failure=$(server_failure); then
      up_failure=${failure%%; its last lines:*}
      log "$server_container did not come up: $failure"
      return 1
    fi
    waited=$((waited + 1))
    if [ "$waited" -ge "${GENESIS_PLAY_UP_ATTEMPTS:-300}" ]; then
      up_failure="no ready line in ${GENESIS_PLAY_UP_ATTEMPTS:-300} asks"
      log "$server_container said no ready line in ${GENESIS_PLAY_UP_ATTEMPTS:-300} asks"
      return 1
    fi
    sleep "${GENESIS_PLAY_POLL_SECONDS:-1}"
  done
}

# alert MESSAGE: posts one line to the Discord channel GENESIS_PLAY_ALERT_CHANNEL with the
# bot token in the file GENESIS_PLAY_ALERT_TOKEN_FILE (a DISCORD_BOT_TOKEN= line; env.sh
# holds the two names, never the token). The token goes to curl on its standard input
# as a config line, so it is in no argument list, no environment and no log; the log
# gets the HTTP status alone. A missing setting or a failed post is logged and never
# fails the caller.
alert() {
  local token status
  if [ -z "${GENESIS_PLAY_ALERT_CHANNEL:-}" ] || [ -z "${GENESIS_PLAY_ALERT_TOKEN_FILE:-}" ]; then
    log "no alert sent: GENESIS_PLAY_ALERT_CHANNEL or GENESIS_PLAY_ALERT_TOKEN_FILE is not set in $home/env.sh"
    return 0
  fi
  token=$(sed -n 's/^DISCORD_BOT_TOKEN=//p' "$GENESIS_PLAY_ALERT_TOKEN_FILE" 2>/dev/null) || true
  if [ -z "$token" ]; then
    log "no alert sent: $GENESIS_PLAY_ALERT_TOKEN_FILE holds no DISCORD_BOT_TOKEN"
    return 0
  fi
  status=$(printf 'header = "Authorization: Bot %s"\nheader = "Content-Type: application/json"\n' "$token" |
    curl -sS --max-time 15 --config - -o /dev/null -w '%{http_code}' \
      --data "$(printf '{"content":"%s"}' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')")" \
      "https://discord.com/api/v10/channels/$GENESIS_PLAY_ALERT_CHANNEL/messages" 2>/dev/null) || status=failed
  case "$status" in
    200) log "alert sent to the channel" ;;
    *) log "alert not sent: Discord answered $status" ;;
  esac
  return 0
}

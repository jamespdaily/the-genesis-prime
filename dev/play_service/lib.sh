# Sourced by update.sh, start.sh, stop.sh, state.sh and install.sh, never run: the play
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
#   refuse MESSAGE                 log_once MESSAGE, then ends the script with status 1
#   load_environment               reads env.sh and checks the values above are set; refuses when
#                                  one is not
#   read_config                    reads $state/config.sh and checks it sets remote and repository;
#                                  branch defaults to main; returns 1 with config_problem set, and
#                                  logs nothing, when it is missing or lacks one
#   load_config                    read_config, refusing with config_problem when it returns 1
#   remote_head                    prints the commit the remote's branch is at; fails when it
#                                  cannot be read
#   live_lock_held                 whether a live session holds ~/.genesis-prime/live.lock
#   alert_stale_stands             posts one alert line, once per lock or hold, when the live lock
#                                  or the hold has stood over an hour while the remote's branch is
#                                  at a commit the server container does not run; never takes the
#                                  lock or the hold over
#   update_lock                    the folder update.sh's lock is
#   older_than_a_minute PATH       whether the file or folder was last changed over a minute ago;
#                                  false when it is missing
#   update_lock_owner              the process id the lock's owner file holds, empty when none
#   update_lock_is_stale           whether the lock's owner is gone, or it has no owner file and
#                                  is over a minute old
#   machine_running                whether the Podman machine answers
#   machine_up                     starts the Podman machine when it is not running
#   container_running NAME         whether the container exists and is running
#   container_status NAME          prints the container's status; 1 when there is none
#   postgres_ready                 whether Postgres accepts a connection to the play database now
#   ensure_postgres                makes the network and the Postgres container, starts it,
#                                  and returns once it accepts connections
#   server_labels                  prints "REVISION ADDRESS RUNNING" of the server container;
#                                  podman's status when it could not
#   server_state                   server_labels with its failure and its error text dropped:
#                                  nothing when there is none
#   run_server IMAGE REVISION ADDRESS   replaces the server container with a new one
#   wait_up                        waits for the server container's ready line; on a container
#                                  that exited or restarted, or no line in time, logs its state,
#                                  exit code and last lines and fails; sets up_failure to the
#                                  state, exit code and restarts, without the last lines
#   alert MESSAGE                  posts one line to the Discord channel; a missing setting is
#                                  logged and returns 0, a post that was tried and refused is
#                                  logged and returns 1

home=${GENESIS_HOME:-$HOME/.genesis-prime}
state=$home/play-service
log_file=$home/play-service.log

network=genesis-play
postgres_container=genesis-play-postgres
postgres_volume=genesis-play-data
postgres_image=docker.io/library/postgres:18
postgres_port=5434
game_port=24000
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

# refuse MESSAGE: logs MESSAGE as log_once does, prints it to standard error (which
# launchd's log holds) when it was written, and ends the script with status 1, so a refusal
# the next run repeats is written once. A script that needs a value uses this, not
# `${x:?word}` nor a bare `.` of a file that may be missing: bash 3.2 (the /bin/bash launchd
# runs) ends a script that sets an EXIT trap with status 0 on those, because the trap
# already sees `$?` as 0.
refuse() {
  local before
  before=$(cat "$state/last_line" 2>/dev/null || true)
  log_once "$1"
  if [ "$before" != "$1" ] && [ ! -t 1 ]; then printf '%s\n' "$1" >&2; fi
  exit 1
}

# require_value NAME MESSAGE: refuses with MESSAGE when the variable NAME is empty or unset.
require_value() { [ -n "${!1:-}" ] || refuse "$2"; }

load_environment() {
  read_environment_file
  require_value GENESIS_PLAY_ADDRESS "set GENESIS_PLAY_ADDRESS (the address of this machine on the PC network) in $home/env.sh"
  require_value GENESIS_PLAY_ACCOUNT "set GENESIS_PLAY_ACCOUNT in $home/env.sh"
  require_value GENESIS_PLAY_PGPASSWORD "set GENESIS_PLAY_PGPASSWORD (the password of the play Postgres) in $home/env.sh; dev/play_service/install.sh makes it"
  tables=${GENESIS_TABLE_DIR:-$home/tables}
  terrain=${GENESIS_TERRAIN_DIR:-$home/terrain}
  PGPASSWORD=$GENESIS_PLAY_PGPASSWORD
  POSTGRES_PASSWORD=$GENESIS_PLAY_PGPASSWORD
  export PGPASSWORD POSTGRES_PASSWORD GENESIS_PLAY_ACCOUNT
}

# read_config: reads config.sh, which install.sh wrote: the remote, the repository and,
# to follow a branch other than main before it merges, a `branch=` line. Writes nothing to
# the log; when it returns 1, `config_problem` says why.
read_config() {
  config_problem=
  if [ ! -f "$state/config.sh" ]; then
    config_problem="config.sh is missing in $state; dev/play_service/install.sh writes it"
    return 1
  fi
  # shellcheck source=/dev/null
  . "$state/config.sh"
  if [ -z "${remote:-}" ]; then
    config_problem="config.sh sets no remote"
    return 1
  fi
  if [ -z "${repository:-}" ]; then
    config_problem="config.sh sets no repository"
    return 1
  fi
  branch=${branch:-main}
}

# load_config: read_config, refusing with its problem.
load_config() { read_config || refuse "$config_problem"; }

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

# older_than_a_minute PATH: whether the file or folder was last changed over a minute ago.
# A missing path, or a path find cannot read, is not old.
older_than_a_minute() {
  [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}

# The updater's lock: a folder whose owner file holds the process id of the run that
# took it (update.sh takes and releases it).
update_lock=$state/update.lock

# update_lock_owner: the process id in the lock's owner file, empty when it has none.
update_lock_owner() { cat "$update_lock/owner" 2>/dev/null || true; }

# update_lock_is_stale: the lock's owner is gone, or the lock has no owner file and is over
# a minute old.
update_lock_is_stale() {
  local owner
  owner=$(update_lock_owner)
  if [ -n "$owner" ]; then
    ! kill -0 "$owner" 2>/dev/null
  else
    older_than_a_minute "$update_lock"
  fi
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
# unannounced. The marker is written when the alert was posted or its settings are not set;
# a post that failed leaves it unwritten, so the next run tries again. A lock or hold that
# disappears while it is read is skipped. The line it logs does not replace the last line
# log_once compares.
alert_stale_stands() {
  local kind file key mtime age branch_commit deployed previous_line
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
    mtime=$(stat -f %m "$file") || continue
    key=
    [ "$kind" != lock ] || key=$(lock_field token)
    [ -n "$key" ] || key=$mtime
    [ "$(cat "$state/stale_${kind}_alerted" 2>/dev/null || true)" != "$key" ] || continue
    age=$(($(date +%s) - mtime))
    [ "$age" -gt "$stale_stand_seconds" ] || continue
    [ -f "$state/config.sh" ] || continue
    branch_commit=$(read_config && remote_head) || continue
    ! is_skipped "$branch_commit" || continue
    read -r deployed _ <<<"$(server_state)"
    deployed=${deployed:-}
    [ -n "$deployed" ] || continue
    [ "$deployed" != "$branch_commit" ] || continue
    read_environment_file
    previous_line=$(cat "$state/last_line" 2>/dev/null || true)
    if alert "genesis play: ${branch_commit:0:8} is the remote branch's head but the server runs ${deployed:0:8}, and the updater has done nothing for $((age / 3600)) h: $(stale_stand_description "$kind")"; then
      printf '%s' "$key" >"$state/stale_${kind}_alerted"
    fi
    printf '%s' "$previous_line" >"$state/last_line"
  done
}

# machine_running: whether the Podman machine answers; podman's own status when it does not.
machine_running() { podman info >/dev/null 2>&1; }

machine_up() {
  machine_running && return 0
  log "the Podman machine is not running; starting it"
  podman machine start >/dev/null 2>&1 || true
  machine_running
}

# container_running NAME: whether the container exists and is running. The
# answer is read into a variable first, and no apostrophe stands in a ${x:?word}:
# bash 3.2, the /bin/bash launchd runs, misparses both.
container_running() {
  local running
  running=$(podman container inspect --format '{{.State.Running}}' "$1" 2>/dev/null) || return 1
  [ "$running" = true ]
}

# container_status NAME: prints the container's State.Status as Podman words it (running,
# stopping, exited, created ...). Returns 1 when there is no such container, and podman's
# own status when it could not say.
container_status() {
  local exists=0 status
  podman container exists "$1" >/dev/null 2>&1 || exists=$?
  [ "$exists" -eq 0 ] || return "$exists"
  status=$(podman container inspect --format '{{.State.Status}}' "$1" 2>/dev/null) || return $?
  printf '%s\n' "$status"
}

# postgres_ready: whether Postgres in its container accepts a connection to the play
# database now; pg_isready's status when it does not.
postgres_ready() {
  podman exec "$postgres_container" pg_isready -q -U postgres -d "$play_database"
}

# Waits until Postgres in its container accepts a connection to the play database:
# GENESIS_PLAY_POSTGRES_ATTEMPTS asks (default 120) GENESIS_PLAY_POLL_SECONDS
# apart (default 1).
wait_for_postgres() {
  local waited=0
  until postgres_ready; do
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

# server_labels: prints "REVISION ADDRESS RUNNING" of the server container, and returns
# podman's own status when it could not say.
server_labels() {
  podman container inspect \
    --format '{{index .Config.Labels "genesis.revision"}} {{index .Config.Labels "genesis.address"}} {{.State.Running}}' \
    "$server_container"
}

server_state() { server_labels 2>/dev/null || true; }

run_server() {
  local image=$1 revision=$2 address=$3
  mkdir -p "$home/sittings"
  podman run -d --replace --name "$server_container" --network "$network" \
    --restart=on-failure:5 --memory 3g --stop-timeout 60 \
    -p 6600:6600 -p 23115:23115 -p "$game_port:$game_port" \
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
# gets the HTTP status alone. A missing setting is logged and returns 0 (nothing to
# retry); a post that was tried and not answered 200 is logged and returns 1, so a caller
# under set -e guards it with || true.
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
    *)
      log "alert not sent: Discord answered $status"
      return 1
      ;;
  esac
}

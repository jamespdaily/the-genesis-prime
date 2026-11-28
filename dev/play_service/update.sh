#!/usr/bin/env bash
# Keeps the play server on main. launchd runs it every 2 minutes (install.sh);
# each run does what the state asks and logs to ~/.genesis-prime/play-service.log
# one line for each action, and one line for a decision that is new (the same
# decision at the next run is not written again):
#
#   live lock held, or the service held (stop.sh --hold)   does nothing at all, and once the lock or
#                                                            hold has stood over an hour while main's
#                                                            commit is not the one the server runs,
#                                                            posts one alert line (alert_stale_stands
#                                                            in lib.sh), once per lock or hold
#   Podman machine down                                    starts it
#   Postgres container missing or stopped                  makes or starts it, and waits for it
#   main's commit new, its check run passed, and no image  builds genesis-play:<commit> from a
#     of it yet                                              clean `git archive` of it, and refuses
#                                                            an image that holds a file of the client's
#   main's commit new, its check run passed, and its image   records it as deployed ($state/recorded) and
#     inputs (what release/Containerfile copies, and           logs one line; no build, no migration, no
#     priv/migrations, compared by git blob hashes) those      restart, so a merge of tools, tests or
#     of the commit the server runs                            guidance never touches the running server;
#                                                            its dev/play_service scripts are installed
#                                                            (the launcher takes effect at the next start)
#   main's commit new and its check run passed, the server   waits (one log line): no migration, no restart,
#     runs and a game connection is open (the newest           asked again at the next run; the wait is
#     sitting folder of the running commit holds a game        at most 3 hours from the first run that
#     connection recording written in the last 5 minutes       waited, and its clock starts again at any
#     whose last line is not a closed line)                    run that finds no connection open
#   main's commit new and its check run passed, the server   applies the new migrations to the play
#     stopped, or no game connection open, or the 3 hours      database, then replaces the server container
#     passed
#                                                            and waits for its ready line; after 3 hours
#                                                            with a connection open it logs one line and
#                                                            posts one alert line (alert in lib.sh)
#   the new container does not come up                     logs its state and exit code, puts back the
#                                                            last revision that came up, and does not try
#                                                            the failed commit again
#   a deploy came up                                       removes dangling images and every
#                                                            genesis-play image but the running one and
#                                                            the last good one
#   main's commit new and its tree the one that passed     deploys it as above, without waiting for its own
#     runs of check and tools tested (tested_tree.sh)         run (a pull request merged by a merge commit)
#   main's commit new, server check red, missing or not    nothing for that commit; it is asked again
#     finished                                               at the next run (a docs job's result is not looked at)
#   main's commit holds no release/Containerfile           nothing, and it is not asked about again
#                                                            (the commits before the service existed)
#   this Mac's address changed, or the server stopped      replaces the server container with the same
#                                                            image, no build (also at the end of a run
#                                                            that recorded a commit)
#   none of these                                          nothing
#
# The server container is not started before Postgres answers, and restarts at
# most 5 times by itself. The address is GENESIS_PLAY_ADDRESS of
# ~/.genesis-prime/env.sh, worked out at each run, and the server container is
# labelled with the commit and the address it was given, which is how the next
# run knows what is deployed (a running container's labels cannot change, so a commit
# recorded without a restart is a line "COMMIT DEPLOYED" in $state/recorded, valid while the
# container still runs DEPLOYED; $state/waiting_since holds "DEPLOYED SINCE", the commit the
# server runs and the epoch second of the first run that waited for a connection of it, kept
# while newer commits arrive and removed by any run that finds no connection open);
# $state/good names the last commit that came up and
# $state/skipped the commits not to try again. Before a deploy, and when a commit is
# recorded, the installed copies of these scripts (in $state/bin) are replaced with the
# commit's and read again, so the new commit's launcher starts the next container.
#
# Only one run goes at a time: the lock is the folder $state/update.lock, whose
# owner file (the process id) is written whole by a move. A lock whose owner is
# gone is taken over, and one with no owner file stays held for a minute (its
# taker is still writing it). Needs git, gh (logged in: it reads the commit's
# check runs; the build holds no login), podman, and ~/.genesis-prime/play-service/
# config.sh from install.sh: the remote, the repository and, to follow a branch
# other than main before it merges, a `branch=` line. Exits 0 when it did nothing
# or deployed, 1 when a step failed (the log says which; a server that did not
# come up is replaced by the last good one). A deploy whose server does not come up
# posts one line to the Discord channel (alert in lib.sh): the commit, how it failed and
# whether the last good revision is back up. The restart of an unchanged commit posts none.
# A lock or hold that has stood over an hour posts one line naming its holder, whether the
# holder's process runs and the command that releases it; the updater never takes a lock
# or a hold over. The age is the mtime of the lock's owner record (of the lock folder when
# it has none) or of $state/held; the once-marker is $state/stale_lock_alerted or
# stale_hold_alerted, removed when the lock or hold is gone.
#
# GENESIS_PLAY_UP_ATTEMPTS (default 300) and GENESIS_PLAY_POLL_SECONDS (default 1)
# set how long a new container has to say its ready line; GENESIS_PLAY_WAIT_SECONDS
# (default 10800) sets how long a deploy waits for game connections to close.
#
# Usage: update.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

forget_closed_wait
alert_stale_stands
if live_lock_held; then
  log_once "a live session holds $home/live.lock; nothing done"
  exit 0
fi
if [ -e "$state/held" ]; then
  log_once "the service is held (stop.sh --hold; start.sh releases it); nothing done"
  exit 0
fi

mkdir -p "$state"

# write_owner: records this process as the lock's owner, whole, by a move.
write_owner() {
  echo $$ >"$update_lock/owner.next"
  mv -f "$update_lock/owner.next" "$update_lock/owner"
}

# take_lock: makes the lock or, when it is stale, takes it over under a second
# folder only one run can make, so two runs never both remove a lock and make one.
take_lock() {
  if mkdir "$update_lock" 2>/dev/null; then
    write_owner
    return 0
  fi
  if older_than_a_minute "$update_lock.takeover"; then
    rmdir "$update_lock.takeover" 2>/dev/null || true
  fi
  mkdir "$update_lock.takeover" 2>/dev/null || return 1
  if update_lock_is_stale; then
    rm -rf "$update_lock"
    if mkdir "$update_lock" 2>/dev/null; then
      write_owner
      rmdir "$update_lock.takeover"
      return 0
    fi
  fi
  rmdir "$update_lock.takeover"
  return 1
}

if ! take_lock; then
  log_once "another update runs (process $(update_lock_owner)); nothing done"
  exit 0
fi
context=
scripts_folder=
cleanup() {
  rm -rf "$update_lock"
  [ -z "$context" ] || rm -rf "$context"
  [ -z "$scripts_folder" ] || rm -rf "$scripts_folder"
}
trap cleanup EXIT

load_environment
load_config

machine_up || { log "the Podman machine could not be started"; exit 1; }
ensure_postgres || exit 1

# ci_passed COMMIT: 0 when the commit's server check run (the `check` job of
# .github/workflows/check.yml) finished well, 1 when it has none or it is red or not
# finished, 2 when GitHub could not be asked. The docs workflow's jobs do not count:
# a newer commit cancels a publish that is still waiting.
ci_passed() {
  local runs
  runs=$(gh api "repos/$repository/commits/$1/check-runs" \
    --jq '.check_runs[] | select(.name == "check") | "\(.status):\(.conclusion)"') || return 2
  [ -n "$runs" ] || return 1
  if printf '%s\n' "$runs" | grep -qv '^completed:\(success\|skipped\|neutral\)$'; then
    return 1
  fi
}

# fetch_repository: brings the bare copy of the remote in $state up to date, making it
# when there is none.
fetch_repository() {
  if [ -d "$state/repository.git" ]; then
    git -C "$state/repository.git" fetch --quiet origin "+refs/heads/$branch:refs/heads/$branch"
  else
    git clone --quiet --bare "$remote" "$state/repository.git"
  fi
}

# build_image COMMIT: builds the image of the commit from a clean archive of it
# and refuses it when it holds a file of the client's. Gives 2 for a commit with
# no release/Containerfile.
build_image() {
  local commit=$1
  # The caller tests this function's status, which turns set -e off inside it:
  # each step that can fail ends it with return.
  context=$(mktemp -d "$state/context.XXXXXX") || return 1
  fetch_repository || return 1
  git -C "$state/repository.git" archive "$commit" | tar -x -C "$context" || return 1
  if [ ! -f "$context/release/Containerfile" ]; then
    skip_commit "$commit"
    log "$commit holds no release/Containerfile, so it is not deployed and not asked about again"
    return 2
  fi
  log "building genesis-play:$commit"
  podman build --quiet --build-arg "REVISION=$commit" \
    -t "genesis-play:$commit" -f "$context/release/Containerfile" "$context" >/dev/null || return 1
  local client_folders=("$tables" "$terrain")
  [ ! -d "$home/client-files" ] || client_folders+=("$home/client-files")
  "$here/check_image.sh" "genesis-play:$commit" "${client_folders[@]}"
}

# migrate IMAGE: applies the migrations the image holds to the play database.
migrate() {
  podman run --rm --network "$network" \
    -e PGHOST="$postgres_container" -e PGPORT=5432 -e PGUSER=postgres -e PGPASSWORD \
    --entrypoint /migrate/dev/apply_migrations.sh "$1" "$play_database"
}

# install_scripts COMMIT: replaces the installed copies of the scripts with the ones of
# the commit, so the next run is the new commit's updater. They are taken from the
# commit itself, not from the build's archive: a retry finds the image already built
# and extracts nothing. Fails, installing nothing, when the commit holds no script.
install_scripts() {
  local commit=$1 script found=0
  [ "$here" = "$state/bin" ] || return 0
  if ! git -C "$state/repository.git" cat-file -e "$commit^{commit}" 2>/dev/null; then
    fetch_repository || return 1
  fi
  scripts_folder=$(mktemp -d "$state/scripts.XXXXXX") || return 1
  git -C "$state/repository.git" archive "$commit" dev/play_service | tar -x -C "$scripts_folder" || return 1
  for script in "$scripts_folder"/dev/play_service/*.sh; do
    [ -e "$script" ] && found=1
  done
  [ "$found" = 1 ] || return 1
  for script in "$scripts_folder"/dev/play_service/*.sh; do
    cp "$script" "$here/$(basename "$script").next"
    mv -f "$here/$(basename "$script").next" "$here/$(basename "$script")"
  done
}

# prune_images KEEP...: removes the dangling images and every genesis-play image
# whose tag is not one of the commits named.
prune_images() {
  local reference tag keep kept
  podman image prune --force >/dev/null || true
  for reference in $(podman images --filter 'reference=genesis-play:*' --format '{{.Repository}}:{{.Tag}}'); do
    tag=${reference##*:}
    kept=no
    for keep in "$@"; do
      [ "$tag" != "$keep" ] || kept=yes
    done
    if [ "$kept" = no ]; then
      if podman rmi "$reference" >/dev/null 2>&1; then
        log "removed the image $reference"
      fi
    fi
  done
}

# deploy COMMIT: replaces the server container with the commit's image and waits
# for it to come up. A container that does not is replaced by the last good
# revision's, and the commit is not tried again; one alert line says how it failed
# and whether the last good revision is back up (a commit that came up posts none).
# Gives 0 when the commit came up.
deploy() {
  local commit=$1 previous reason outcome
  previous=$(cat "$state/good" 2>/dev/null || true)
  log "replacing $server_container: $commit at $address (was ${deployed_commit:-none})"
  run_server "genesis-play:$commit" "$commit" "$address"
  if wait_up; then
    echo "$commit" >"$state/good"
    log "$commit came up"
    prune_images "$commit" "$commit"
    return 0
  fi
  reason=$up_failure
  skip_commit "$commit"
  if [ -n "$previous" ] && [ "$previous" != "$commit" ] && podman image exists "genesis-play:$previous"; then
    log "$commit did not come up; putting back $previous, and $commit is not tried again"
    run_server "genesis-play:$previous" "$previous" "$address"
    if wait_up; then
      log "$previous is back up"
      prune_images "$previous" "$previous"
      outcome="${previous:0:8} is back up"
    else
      log "$previous did not come up either"
      outcome="${previous:0:8} did not come up either"
    fi
  else
    log "$commit did not come up, and no earlier revision came up to put back; $commit is not tried again"
    outcome="no earlier revision to put back"
  fi
  alert "genesis play: ${commit:0:8} did not come up ($reason); $outcome" || true
  return 1
}

# restart_when_needed: replaces the server container with the same image when this Mac's
# address changed or the server is not running, unless a live session holds the lock.
restart_when_needed() {
  if [ -n "$deployed_commit" ] && { [ "$deployed_address" != "$address" ] || [ "$running" != true ]; }; then
    if live_lock_held; then
      log_once "a live session holds $home/live.lock; the server is not replaced"
      return 0
    fi
    log "replacing $server_container: $deployed_commit, address $deployed_address -> $address, running $running"
    run_server "genesis-play:$deployed_commit" "$deployed_commit" "$address"
    wait_up || exit 1
  fi
}

address=$GENESIS_PLAY_ADDRESS
read -r deployed_commit deployed_address running <<<"$(server_state)"
deployed_commit=${deployed_commit:-}
deployed_address=${deployed_address:-}
running=${running:-}
if [ ! -s "$state/good" ] && [ -n "$deployed_commit" ] && [ "$running" = true ]; then
  echo "$deployed_commit" >"$state/good"
fi

main_commit=
if ! main_commit=$(remote_head); then
  log_once "could not read $branch from $remote; nothing built"
  main_commit=
fi
if [ -n "$main_commit" ] && is_skipped "$main_commit"; then
  main_commit=
fi
{ read -r recorded_commit recorded_over <"$state/recorded"; } 2>/dev/null || true
if [ -n "$main_commit" ] && [ "${recorded_commit:-}" = "$main_commit" ] && [ "${recorded_over:-}" = "$deployed_commit" ]; then
  main_commit=
fi

if [ -n "$main_commit" ] && [ "$main_commit" != "$deployed_commit" ]; then
  status=0
  ci_passed "$main_commit" || status=$?
  # Reason: a merge commit whose files are the tree its pull request's passed run tested (a
  # head that was current with main) holds nothing that run did not test, so it is deployed
  # without waiting for, or whatever the result of, its own run.
  if [ "$status" = 1 ] && tested=$("$here/tested_tree.sh" "$repository" "$main_commit" check tools); then
    log "$main_commit has the files of $tested, whose check passed; not waiting for its own run"
    status=0
  fi
  case $status in
    0)
      fetch_repository || { log "could not fetch $branch to compare $main_commit with $deployed_commit; nothing done for it"; exit 1; }
      if [ -n "$deployed_commit" ] &&
        wanted=$(image_inputs "$main_commit") && held=$(image_inputs "$deployed_commit") &&
        [ "$wanted" = "$held" ]; then
        # The scripts are installed first: a commit that changed only them is recorded too.
        install_scripts "$main_commit" || { log "the scripts of $main_commit could not be installed; it is not recorded"; exit 1; }
        echo "$main_commit $deployed_commit" >"$state/recorded"
        rm -f "$state/waiting_since"
        log "$main_commit has the image inputs of $deployed_commit; recorded as deployed, scripts installed, no rebuild and no restart"
        # shellcheck source=lib.sh
        . "$here/lib.sh"
        load_environment
        restart_when_needed
        exit 0
      fi
      if ! podman image exists "genesis-play:$main_commit"; then
        built=0
        build_image "$main_commit" || built=$?
        case $built in
          0) ;;
          2) exit 0 ;;
          *) log "building $main_commit failed; the running server is left as it was"; exit 1 ;;
        esac
      fi
      if live_lock_held; then
        log_once "a live session took the lock during the build; $main_commit is not migrated or deployed"
        exit 0
      fi
      if deploy_waits "$main_commit"; then
        exit 0
      fi
      log "applying the migrations of $main_commit to $play_database"
      migrate "genesis-play:$main_commit" || { log "the migrations of $main_commit failed; the running server is left as it was"; exit 1; }
      if live_lock_held; then
        log_once "a live session took the lock during the migration; the server is not replaced"
        exit 0
      fi
      # The new commit's launcher (its mounts and variables) starts the new container, so the
      # installed scripts are replaced and read again before the deploy, not after it.
      install_scripts "$main_commit" || { log "the scripts of $main_commit could not be installed; the running server is left as it was"; exit 1; }
      # shellcheck source=lib.sh
      . "$here/lib.sh"
      load_environment
      deploy "$main_commit" || exit 1
      exit 0
      ;;
    1) log_once "the check of $main_commit has not passed or has not finished; nothing done for it" ;;
    *) log_once "could not ask GitHub for the check of $main_commit; nothing done for it" ;;
  esac
fi

restart_when_needed

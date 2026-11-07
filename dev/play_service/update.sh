#!/usr/bin/env bash
# Keeps the play server on main. launchd runs it every 2 minutes (install.sh);
# each run does what the state asks and logs to ~/.genesis-prime/play-service.log
# one line for each action, and one line for a decision that is new (the same
# decision at the next run is not written again):
#
#   live lock held, or the service held (stop.sh --hold)   does nothing at all
#   Podman machine down                                    starts it
#   Postgres container missing or stopped                  makes or starts it, and waits for it
#   main's commit new, its check run passed, and no image  builds genesis-play:<commit> from a
#     of it yet                                              clean `git archive` of it, and refuses
#                                                            an image that holds a file of the client's
#   main's commit new and its check run passed             applies the new migrations to the play
#                                                            database, then replaces the server container
#                                                            at once, players connected or not, and waits
#                                                            for its ready line
#   the new container does not come up                     logs its state and exit code, puts back the
#                                                            last revision that came up, and does not try
#                                                            the failed commit again
#   a deploy came up                                       removes dangling images and every
#                                                            genesis-play image but the running one and
#                                                            the last good one
#   main's commit new and its tree equal to the tree of a   deploys it as above, without waiting for its own
#     commit whose check and tools jobs passed (tested_tree.sh)  run (a pull request merged by a merge commit)
#   main's commit new, server check red, missing or not    nothing for that commit; it is asked again
#     finished                                               at the next run (a docs job's result is not looked at)
#   main's commit holds no release/Containerfile           nothing, and it is not asked about again
#                                                            (the commits before the service existed)
#   this Mac's address changed, or the server stopped      replaces the server container with the same
#                                                            image, no build
#   none of these                                          nothing
#
# The server container is not started before Postgres answers, and restarts at
# most 5 times by itself. The address is GENESIS_PLAY_ADDRESS of
# ~/.genesis-prime/env.sh, worked out at each run, and the server container is
# labelled with the commit and the address it was given, which is how the next
# run knows what is deployed; $state/good names the last commit that came up and
# $state/skipped the commits not to try again. After a deploy the installed copies
# of these scripts (in $state/bin) are replaced with the new commit's.
#
# Only one run goes at a time: the lock is the folder $state/update.lock, whose
# owner file (the process id) is written whole by a move. A lock whose owner is
# gone is taken over, and one with no owner file stays held for a minute (its
# taker is still writing it). Needs git, gh (logged in: it reads the commit's
# check runs; the build holds no login), podman, and ~/.genesis-prime/play-service/
# config.sh from install.sh: the remote, the repository and, to follow a branch
# other than main before it merges, a `branch=` line. Exits 0 when it did nothing
# or deployed, 1 when a step failed (the log says which; a server that did not
# come up is replaced by the last good one).
#
# GENESIS_PLAY_UP_ATTEMPTS (default 300) and GENESIS_PLAY_POLL_SECONDS (default 1)
# set how long a new container has to say its ready line.
#
# Usage: update.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

if live_lock_held; then
  log_once "a live session holds $home/live.lock; nothing done"
  exit 0
fi
if [ -e "$state/held" ]; then
  log_once "the service is held (stop.sh --hold; start.sh releases it); nothing done"
  exit 0
fi

mkdir -p "$state"
lock=$state/update.lock

# lock_owner: the process id in the lock's owner file, empty when it has none.
lock_owner() { cat "$lock/owner" 2>/dev/null || true; }

# lock_is_stale: the lock's owner is gone, or the lock has no owner file and is over
# a minute old.
lock_is_stale() {
  local owner
  owner=$(lock_owner)
  if [ -n "$owner" ]; then
    ! kill -0 "$owner" 2>/dev/null
  else
    [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]
  fi
}

# write_owner: records this process as the lock's owner, whole, by a move.
write_owner() {
  echo $$ >"$lock/owner.next"
  mv -f "$lock/owner.next" "$lock/owner"
}

# take_lock: makes the lock or, when it is stale, takes it over under a second
# folder only one run can make, so two runs never both remove a lock and make one.
take_lock() {
  if mkdir "$lock" 2>/dev/null; then
    write_owner
    return 0
  fi
  if [ -d "$lock.takeover" ] && [ -n "$(find "$lock.takeover" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    rmdir "$lock.takeover" 2>/dev/null || true
  fi
  mkdir "$lock.takeover" 2>/dev/null || return 1
  if lock_is_stale; then
    rm -rf "$lock"
    if mkdir "$lock" 2>/dev/null; then
      write_owner
      rmdir "$lock.takeover"
      return 0
    fi
  fi
  rmdir "$lock.takeover"
  return 1
}

if ! take_lock; then
  log_once "another update runs (process $(lock_owner)); nothing done"
  exit 0
fi
context=
cleanup() {
  rm -rf "$lock"
  [ -z "$context" ] || rm -rf "$context"
}
trap cleanup EXIT

load_environment
# shellcheck source=/dev/null
. "$state/config.sh"
: "${remote:?config.sh sets no remote}" "${repository:?config.sh sets no repository}"
branch=${branch:-main}

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

# build_image COMMIT: builds the image of the commit from a clean archive of it
# and refuses it when it holds a file of the client's. Gives 2 for a commit with
# no release/Containerfile.
build_image() {
  local commit=$1
  # The caller tests this function's status, which turns set -e off inside it:
  # each step that can fail ends it with return.
  context=$(mktemp -d "$state/context.XXXXXX") || return 1
  if [ -d "$state/repository.git" ]; then
    git -C "$state/repository.git" fetch --quiet origin "+refs/heads/$branch:refs/heads/$branch" || return 1
  else
    git clone --quiet --bare "$remote" "$state/repository.git" || return 1
  fi
  git -C "$state/repository.git" archive "$commit" | tar -x -C "$context" || return 1
  if [ ! -f "$context/release/Containerfile" ]; then
    skip_commit "$commit"
    log "$commit holds no release/Containerfile, so it is not deployed and not asked about again"
    return 2
  fi
  log "building genesis-play:$commit"
  podman build --quiet --build-arg "REVISION=$commit" \
    -t "genesis-play:$commit" -f "$context/release/Containerfile" "$context" >/dev/null || return 1
  local client_folders=("$tables")
  [ ! -d "$home/client-files" ] || client_folders+=("$home/client-files")
  "$here/check_image.sh" "genesis-play:$commit" "${client_folders[@]}"
}

# migrate IMAGE: applies the migrations the image holds to the play database.
migrate() {
  podman run --rm --network "$network" \
    -e PGHOST="$postgres_container" -e PGPORT=5432 -e PGUSER=postgres -e PGPASSWORD \
    --entrypoint /migrate/dev/apply_migrations.sh "$1" "$play_database"
}

# install_scripts: replaces the installed copies of the scripts with the ones of
# the archive just built, so the next run is the new commit's updater.
install_scripts() {
  local script
  [ "$here" = "$state/bin" ] || return 0
  for script in "$context"/dev/play_service/*.sh; do
    [ -e "$script" ] || continue
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
# revision's, and the commit is not tried again. Gives 0 when the commit came up.
deploy() {
  local commit=$1 previous
  previous=$(cat "$state/good" 2>/dev/null || true)
  log "replacing $server_container: $commit at $address (was ${deployed_commit:-none})"
  run_server "genesis-play:$commit" "$commit" "$address"
  if wait_up; then
    echo "$commit" >"$state/good"
    log "$commit came up"
    prune_images "$commit" "$commit"
    return 0
  fi
  skip_commit "$commit"
  if [ -n "$previous" ] && [ "$previous" != "$commit" ] && podman image exists "genesis-play:$previous"; then
    log "$commit did not come up; putting back $previous, and $commit is not tried again"
    run_server "genesis-play:$previous" "$previous" "$address"
    if wait_up; then
      log "$previous is back up"
      prune_images "$previous" "$previous"
    else
      log "$previous did not come up either"
    fi
  else
    log "$commit did not come up, and no earlier revision came up to put back; $commit is not tried again"
  fi
  return 1
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
if ! main_commit=$(git ls-remote "$remote" "refs/heads/$branch" | cut -f1) || [ -z "$main_commit" ]; then
  log_once "could not read $branch from $remote; nothing built"
  main_commit=
fi
if [ -n "$main_commit" ] && is_skipped "$main_commit"; then
  main_commit=
fi

if [ -n "$main_commit" ] && [ "$main_commit" != "$deployed_commit" ]; then
  status=0
  ci_passed "$main_commit" || status=$?
  # Reason: a merge commit whose files are those of its pull request's head (one that was
  # current with main) holds nothing the head's passed check did not test, so it is
  # deployed without waiting for, or whatever the result of, its own run.
  if [ "$status" = 1 ] && tested=$("$here/tested_tree.sh" "$repository" "$main_commit" check tools); then
    log "$main_commit has the files of $tested, whose check passed; not waiting for its own run"
    status=0
  fi
  case $status in
    0)
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
      log "applying the migrations of $main_commit to $play_database"
      migrate "genesis-play:$main_commit" || { log "the migrations of $main_commit failed; the running server is left as it was"; exit 1; }
      if live_lock_held; then
        log_once "a live session took the lock during the migration; the server is not replaced"
        exit 0
      fi
      deploy "$main_commit" || exit 1
      install_scripts
      exit 0
      ;;
    1) log_once "the check of $main_commit has not passed or has not finished; nothing done for it" ;;
    *) log_once "could not ask GitHub for the check of $main_commit; nothing done for it" ;;
  esac
fi

if [ -n "$deployed_commit" ] && { [ "$deployed_address" != "$address" ] || [ "$running" != true ]; }; then
  if live_lock_held; then
    log_once "a live session holds $home/live.lock; the server is not replaced"
    exit 0
  fi
  log "replacing $server_container: $deployed_commit, address $deployed_address -> $address, running $running"
  run_server "genesis-play:$deployed_commit" "$deployed_commit" "$address"
  wait_up || exit 1
fi

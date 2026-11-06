#!/usr/bin/env bash
# Keeps the play server on main. launchd runs it every 2 minutes (install.sh);
# each run does what the state asks and logs one line per action to
# ~/.genesis-prime/play-service.log:
#
#   live lock held, or the service held (stop.sh --hold)   does nothing at all
#   Podman machine down                                    starts it
#   Postgres container missing or stopped                  makes or starts it, and waits for it
#   main's commit new, its check run passed, and no image  builds genesis-play:<commit> from a
#     of it yet                                              clean `git archive` of it, and refuses
#                                                            an image that holds a file of the client's
#   main's commit new and its check run passed             applies the new migrations to the play
#                                                            database, then replaces the server container
#                                                            at once, players connected or not
#   main's commit new, check red or not finished           nothing for that commit; it is asked again
#                                                            at the next run
#   this Mac's address changed, or the server stopped      replaces the server container with the same
#                                                            image, no build
#   none of these                                          nothing
#
# The server container is not started before Postgres answers. The address is
# GENESIS_PLAY_ADDRESS of ~/.genesis-prime/env.sh, worked out at each run, and
# the server container is labelled with the commit and the address it was given,
# which is how the next run knows what is deployed. After a deploy the installed
# copies of these scripts are replaced with the new commit's. A second run at the
# same time exits at once. Needs git, gh (logged in: it reads the commit's check
# runs and gives the build its token), podman, and ~/.genesis-prime/play-service/
# config.sh from install.sh (remote and repository). Exits 0 when it did nothing
# or deployed, 1 when a step failed (the log says which; the running server is
# left as it was).
#
# Usage: update.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

if live_lock_held; then
  log "a live session holds $home/live.lock; nothing done"
  exit 0
fi
if [ -e "$state/held" ]; then
  log "the service is held (stop.sh --hold; start.sh releases it); nothing done"
  exit 0
fi

mkdir -p "$state"
if ! mkdir "$state/update.lock" 2>/dev/null; then
  other=$(cat "$state/update.lock/pid" 2>/dev/null || true)
  if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
    log "another update runs (process $other); nothing done"
    exit 0
  fi
  rm -rf "$state/update.lock"
  mkdir "$state/update.lock"
fi
echo $$ >"$state/update.lock/pid"
context=
cleanup() {
  rm -rf "$state/update.lock"
  [ -z "$context" ] || rm -rf "$context"
}
trap cleanup EXIT

load_environment
# shellcheck source=/dev/null
. "$state/config.sh"
: "${remote:?config.sh sets no remote}" "${repository:?config.sh sets no repository}"

machine_up || { log "the Podman machine could not be started"; exit 1; }
ensure_postgres || exit 1

# ci_passed COMMIT: 0 when the commit has check runs and every one finished well,
# 1 when it has none or one is red or not finished, 2 when GitHub could not be asked.
ci_passed() {
  local runs
  runs=$(gh api "repos/$repository/commits/$1/check-runs" \
    --jq '.check_runs[] | "\(.status):\(.conclusion)"') || return 2
  [ -n "$runs" ] || return 1
  if printf '%s\n' "$runs" | grep -qv '^completed:\(success\|skipped\|neutral\)$'; then
    return 1
  fi
}

# build_image COMMIT: builds the image of the commit from a clean archive of it
# and refuses it when it holds a file of the client's.
build_image() {
  local commit=$1 token
  # The caller tests this function's status, which turns set -e off inside it:
  # each step that can fail ends it with return.
  context=$(mktemp -d "$state/context.XXXXXX") || return 1
  if [ -d "$state/repository.git" ]; then
    git -C "$state/repository.git" fetch --quiet origin "+refs/heads/main:refs/heads/main" || return 1
  else
    git clone --quiet --bare "$remote" "$state/repository.git" || return 1
  fi
  git -C "$state/repository.git" archive "$commit" | tar -x -C "$context" || return 1
  token=$(gh auth token) || return 1
  log "building genesis-play:$commit"
  GH_TOKEN=$token podman build --quiet \
    --secret id=github_token,env=GH_TOKEN --build-arg "REVISION=$commit" \
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

address=$GENESIS_PLAY_ADDRESS
read -r deployed_commit deployed_address running <<<"$(server_state)"
deployed_commit=${deployed_commit:-}
deployed_address=${deployed_address:-}
running=${running:-}

main_commit=
if ! main_commit=$(git ls-remote "$remote" refs/heads/main | cut -f1) || [ -z "$main_commit" ]; then
  log "could not read main from $remote; nothing built"
  main_commit=
fi

if [ -n "$main_commit" ] && [ "$main_commit" != "$deployed_commit" ]; then
  status=0
  ci_passed "$main_commit" || status=$?
  case $status in
    0)
      if ! podman image exists "genesis-play:$main_commit"; then
        build_image "$main_commit" || { log "building $main_commit failed; the running server is left as it was"; exit 1; }
      fi
      log "applying the migrations of $main_commit to $play_database"
      migrate "genesis-play:$main_commit" || { log "the migrations of $main_commit failed; the running server is left as it was"; exit 1; }
      if live_lock_held; then
        log "a live session took the lock during the build; the server is not replaced"
        exit 0
      fi
      log "replacing $server_container: $main_commit at $address (was ${deployed_commit:-none})"
      run_server "genesis-play:$main_commit" "$main_commit" "$address"
      install_scripts
      exit 0
      ;;
    1) log "the check of $main_commit has not passed or has not finished; nothing done for it" ;;
    *) log "could not ask GitHub for the check of $main_commit; nothing done for it" ;;
  esac
fi

if [ -n "$deployed_commit" ] && { [ "$deployed_address" != "$address" ] || [ "$running" != true ]; }; then
  if live_lock_held; then
    log "a live session holds $home/live.lock; the server is not replaced"
    exit 0
  fi
  log "replacing $server_container: $deployed_commit, address $deployed_address -> $address, running $running"
  run_server "genesis-play:$deployed_commit" "$deployed_commit" "$address"
fi

# The lock on the live resources: the play PC's client, the server's ports and the dev database.
# Sourced by session.sh and client.sh, never run; the script that sources it has set -euo pipefail,
# and may set `tool` (its name, the prefix of every refusal here) first.
#
# The lock is the folder live.lock beside env.sh ($home, default ~/.genesis-prime). mkdir makes it
# or fails in one step, so only one holder has it: a run (session.sh) for its whole length, or a
# client.sh start outside a run until client.sh stop. Its file `owner` holds one key=value line per
# field and is replaced whole (lock_write: a temporary file, then a move), never edited in place:
#   token, kind, folder, pid, started, commit   written when the lock is taken: a random token (the
#                                           proof of being the owner), run or client (a run, or a
#                                           client.sh start outside one), the run's folder (empty for
#                                           a client), the taker's pid and start time, and the commit
#                                           checked out
#   client_before, client_touched, and for a run run_database, launcher_pid, launcher_started, vm_pid,
#   vm_started, addon_touched               written as the holder learns or does each (lock_set), so
#                                           session.sh --recover can end what it began
# A recovery claims the lock first with the folder $lock_claim (live.lock/recovering), so only one
# runs.
# provides:
#   home                         the folder that holds env.sh, client.pid and the lock
#   started_at <pid>             when the process started, as ps prints it with its padding squeezed
#                                out: empty when there is no such process
#   is_process <pid> <started>   whether the process with that pid is the one that started then, so a
#                                pid the system has reused is not taken for the recorded one
#   lock_take <kind> <folder>    makes the lock and writes its owner; on success sets $lock_token. When
#                                the lock is held it prints the owner, and returns 1
#   lock_get <key>               a field of the owner record, empty when it has none
#   lock_set <key> <value>...    sets one or more fields in one write
#   lock_owner_alive             whether the process that took the lock is still running
#   lock_ownerless_for_a_minute  whether the lock folder has no owner record and is over a minute old,
#                                so no taker is still writing it
#   lock_refuse                  prints why the lock is not free: who holds it, or that its owner is
#                                gone and session.sh --recover must clean up
#   lock_for_client_start        for client.sh start: succeeds when the caller is the run that holds
#                                the lock (it carries the token in GENESIS_LIVE_LOCK_TOKEN, which
#                                session.sh exports to what it runs) or when it takes the lock itself
#                                (then $lock_token is set); otherwise refuses
#   lock_release_client          for client.sh stop: removes a client's lock, unless its owner is the
#                                caller or a recovery holds it
#   lock_release <token>         removes the lock when its owner record holds that token

home=${GENESIS_HOME:-$HOME/.genesis-prime}
lock_dir=$home/live.lock
lock_owner=$lock_dir/owner
lock_claim=$lock_dir/recovering
lock_token=

started_at() { { ps -o lstart= -p "$1" 2>/dev/null || true; } | awk '{ $1 = $1; print }'; }

is_process() { [ -n "$2" ] && [ "$(started_at "$1")" = "$2" ]; }

lock_get() { sed -n "/^$1=/{s///p;q;}" "$lock_owner" 2>/dev/null || true; }

# Replaces the owner record with the text on standard input.
lock_write() {
  cat > "$lock_owner.next"
  mv -f "$lock_owner.next" "$lock_owner"
}

lock_set() {
  local drop=() i
  for ((i = 1; i < $#; i += 2)); do drop+=(-e "^${!i}="); done
  {
    grep -v "${drop[@]}" "$lock_owner" 2>/dev/null || true
    while [ $# -gt 0 ]; do printf '%s=%s\n' "$1" "$2"; shift 2; done
  } | lock_write
}

lock_owner_alive() { is_process "$(lock_get pid)" "$(lock_get started)"; }

lock_ownerless_for_a_minute() {
  [ ! -s "$lock_owner" ] && [ -n "$(find "$lock_dir" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}

lock_refuse() {
  local who
  if [ ! -s "$lock_owner" ]; then
    echo "${tool:-live}: $lock_dir has no owner record: a run is taking the lock, or was cut off as it did; session.sh --recover releases it once it is over a minute old" >&2
    return 0
  fi
  if [ "$(lock_get kind)" = client ]; then
    who="a client.sh start (process $(lock_get pid), started $(lock_get started))"
    if lock_owner_alive; then
      echo "${tool:-live}: the PC's client, the server's ports and the dev database are in use by $who, which is still starting the client" >&2
    else
      echo "${tool:-live}: the lock is held by $who, which has ended: the client it started may still run; client.sh stop closes it and releases the lock, or session.sh --recover does" >&2
    fi
    return 0
  fi
  who="the run in $(lock_get folder) (session.sh process $(lock_get pid), started $(lock_get started), commit $(lock_get commit))"
  if lock_owner_alive; then
    echo "${tool:-live}: the PC's client, the server's ports and the dev database are in use by $who" >&2
  else
    echo "${tool:-live}: the lock is held by $who, which is gone: it was cut off and may have left a client, the report addon, a server or a run database; session.sh --recover ends them and releases the lock" >&2
  fi
}

lock_take() {
  local err commit
  mkdir -p "$home"
  if ! err=$(mkdir "$lock_dir" 2>&1); then
    if [ -d "$lock_dir" ]; then lock_refuse; else echo "${tool:-live}: could not make $lock_dir: $err" >&2; fi
    return 1
  fi
  lock_token=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
  commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)
  printf 'token=%s\nkind=%s\nfolder=%s\npid=%s\nstarted=%s\ncommit=%s\n' \
    "$lock_token" "$1" "$2" "$$" "$(started_at "$$")" "$commit" | lock_write
}

lock_for_client_start() {
  if [ -n "${GENESIS_LIVE_LOCK_TOKEN:-}" ] && [ "$(lock_get token)" = "$GENESIS_LIVE_LOCK_TOKEN" ]; then return 0; fi
  lock_take client ""
}

# Whether this caller may type into, click on or stop the PC's client: yes with no lock, with the
# lock's own token, or under a standalone client start's lock (it holds the lock for that client);
# no while a session or a recovery holds it, so no agent touches another run's client.
lock_allows_client_use() {
  [ -d "$lock_dir" ] || return 0
  if [ -n "${GENESIS_LIVE_LOCK_TOKEN:-}" ] && [ "$(lock_get token)" = "$GENESIS_LIVE_LOCK_TOKEN" ]; then return 0; fi
  if [ -e "$lock_claim" ]; then
    echo "${tool:-live}: a session.sh --recover holds the lock; the client is left to it" >&2
    return 1
  fi
  [ "$(lock_get kind)" != client ] || return 0
  lock_refuse
  return 1
}

lock_release_client() {
  [ "$(lock_get kind)" = client ] || return 0
  [ ! -e "$lock_claim" ] || return 0
  if [ -n "${GENESIS_LIVE_LOCK_TOKEN:-}" ] && [ "$(lock_get token)" = "$GENESIS_LIVE_LOCK_TOKEN" ]; then return 0; fi
  rm -rf "$lock_dir"
}

lock_release() {
  [ -n "$1" ] && [ "$(lock_get token)" = "$1" ] || return 0
  rm -rf "$lock_dir"
}

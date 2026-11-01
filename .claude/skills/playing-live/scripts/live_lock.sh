# The lock on the live resources: the play PC's client, the server's ports and the dev database.
# Sourced by session.sh and client.sh, never run; the script that sources it has set -euo pipefail,
# and may set `tool` (its name, the prefix of every refusal here) first.
#
# The lock is the folder live.lock beside env.sh ($GENESIS_HOME, default ~/.genesis-prime). mkdir
# makes it or fails in one step, so only one run holds it. Its file `owner` holds one key=value line
# per field and is replaced whole (a temporary file, then a move), never edited in place:
#   token, folder, pid, started, commit     written when the lock is taken: a random token (the proof
#                                           of being the owner), the run's folder, session.sh's pid and
#                                           start time, and the commit checked out
#   client_before, run_database, launcher_pid, launcher_started, vm_pid, vm_started, client_touched,
#   addon_touched                           written by session.sh as the run learns or does each
#                                           (lock_set), so --recover can end what the run began
# provides:
#   started_at <pid>             when the process started, as ps prints it with its padding squeezed
#                                out: empty when there is no such process
#   is_process <pid> <started>   whether the process with that pid is the one that started then, so a
#                                pid the system has reused is not taken for the recorded one
#   lock_take <folder>           makes the lock and writes its owner; on success sets $lock_token. When
#                                the lock is held it prints the owner, and returns 1
#   lock_get <key>               a field of the owner record, empty when it has none
#   lock_set <key> <value>       sets a field
#   lock_owner_alive             whether the process that took the lock is still running
#   lock_refuse                  prints why the lock is not free: who holds it, or that its owner is
#                                gone and session.sh --recover must clean up
#   lock_allows_client_start     for client.sh start: succeeds when no lock is held, or when the caller
#                                is the owner (it carries the token in GENESIS_LIVE_LOCK_TOKEN, which
#                                session.sh exports to what it runs); otherwise refuses
#   lock_release <token>         removes the lock when its owner record holds that token

lock_dir=${GENESIS_HOME:-$HOME/.genesis-prime}/live.lock
lock_owner=$lock_dir/owner
lock_token=

started_at() { { ps -o lstart= -p "$1" 2>/dev/null || true; } | awk '{ $1 = $1; print }'; }

is_process() { [ -n "$2" ] && [ "$(started_at "$1")" = "$2" ]; }

lock_get() { sed -n "/^$1=/{s///p;q;}" "$lock_owner" 2>/dev/null || true; }

lock_set() {
  local next=$lock_owner.next
  { grep -v "^$1=" "$lock_owner" || true; printf '%s=%s\n' "$1" "$2"; } > "$next"
  mv -f "$next" "$lock_owner"
}

lock_owner_alive() { is_process "$(lock_get pid)" "$(lock_get started)"; }

lock_refuse() {
  local who
  if [ ! -s "$lock_owner" ]; then
    echo "${tool:-live}: $lock_dir exists with no owner record: a run is taking the lock, or was cut off as it did; when no session.sh runs, session.sh --recover releases it" >&2
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
  mkdir -p "$(dirname "$lock_dir")"
  if ! err=$(mkdir "$lock_dir" 2>&1); then
    if [ -d "$lock_dir" ]; then lock_refuse; else echo "${tool:-live}: could not make $lock_dir: $err" >&2; fi
    return 1
  fi
  lock_token=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
  commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)
  printf 'token=%s\nfolder=%s\npid=%s\nstarted=%s\ncommit=%s\n' \
    "$lock_token" "$1" "$$" "$(started_at "$$")" "$commit" > "$lock_owner.next"
  mv -f "$lock_owner.next" "$lock_owner"
}

lock_allows_client_start() {
  [ -d "$lock_dir" ] || return 0
  if [ -n "${GENESIS_LIVE_LOCK_TOKEN:-}" ] && [ "$(lock_get token)" = "$GENESIS_LIVE_LOCK_TOKEN" ]; then return 0; fi
  lock_refuse
  return 1
}

lock_release() {
  [ -n "$1" ] && [ "$(lock_get token)" = "$1" ] || return 0
  rm -rf "$lock_dir"
}

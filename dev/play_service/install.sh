#!/usr/bin/env bash
# Installs the play service on this Mac, and is safe to run again:
#
#   1. the play Postgres's password: GENESIS_PLAY_PGPASSWORD in
#      ~/.genesis-prime/env.sh, made (random) and appended when it is missing
#   2. the scripts of this folder copied to ~/.genesis-prime/play-service/bin, and
#      config.sh there with this checkout's origin (the remote and the repository
#      update.sh reads main and its check runs from)
#   3. the Postgres container, started, and, when its play database holds no
#      table, the local play database (PGHOST=::1 PGPORT=5433 PGUSER=postgres,
#      database genesis_play) dumped and restored into it; the row counts of
#      account, character, spawn, spawn_stat, game_number and schema_migration
#      are printed for both before and after. The local database is left as it is.
#   4. the launchd agent com.genesis-prime.play-service, which runs
#      bin/update.sh at load and every 2 minutes, and starts the Podman machine
#      when it is not running
#
# The first update.sh run builds the image, applies the migrations and starts the
# server container, so the server's ports (6600, 23115, 24000) must be free by
# then: stop any server of another kind first. Needs podman, gh (logged in), git,
# psql and pg_dump.
#
# Usage: install.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

for tool in podman gh git psql pg_dump openssl; do
  command -v "$tool" >/dev/null || { echo "install: $tool is not installed" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "install: gh is not logged in (update.sh reads check runs and gives the build its token)" >&2; exit 1; }

mkdir -p "$home"
touch "$home/env.sh"
if ! grep -q '^export GENESIS_PLAY_PGPASSWORD=' "$home/env.sh"; then
  {
    echo ""
    echo "# The play Postgres container's password (dev/play_service), read by the play service and the playing-live scripts."
    echo "export GENESIS_PLAY_PGPASSWORD=$(openssl rand -hex 16)"
  } >>"$home/env.sh"
  log "made GENESIS_PLAY_PGPASSWORD in $home/env.sh"
fi
load_environment

mkdir -p "$state/bin"
for script in "$here"/*.sh; do
  cp "$script" "$state/bin/$(basename "$script")"
done
remote=$(git -C "$here" remote get-url origin)
repository=$(printf '%s\n' "$remote" | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')
printf 'remote=%s\nrepository=%s\n' "'$remote'" "'$repository'" >"$state/config.sh"
log "scripts installed in $state/bin; main is read from $remote"

machine_up || { echo "install: the Podman machine could not be started" >&2; exit 1; }
ensure_postgres

# The pod's Postgres is reached from this Mac on its published port; the local one as the tests use it.
pod_psql() { psql -X -q -At -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$postgres_port" -U postgres -d "$play_database" "$@"; }
local_psql() { PGPASSWORD= psql -X -q -At -v ON_ERROR_STOP=1 -h "${GENESIS_SEED_PGHOST:-::1}" -p "${GENESIS_SEED_PGPORT:-5433}" -U postgres -d "$play_database" "$@"; }

counts() {
  local table
  for table in account character spawn spawn_stat game_number schema_migration; do
    printf '%s=%s ' "$table" "$("$1" -c "select count(*) from $table" 2>/dev/null || echo none)"
  done
  echo
}

tables_in_pod=$(pod_psql -c "select count(*) from information_schema.tables where table_schema = 'public'")
if [ "$tables_in_pod" = 0 ]; then
  log "the pod's $play_database is empty; seeding it from the local $play_database"
  log "local before:  $(counts local_psql)"
  log "pod before:    $(counts pod_psql)"
  PGPASSWORD= pg_dump -h "${GENESIS_SEED_PGHOST:-::1}" -p "${GENESIS_SEED_PGPORT:-5433}" -U postgres -d "$play_database" --no-owner --no-privileges |
    pod_psql --single-transaction -f - >/dev/null
  log "local after:   $(counts local_psql)"
  log "pod after:     $(counts pod_psql)"
else
  log "the pod's $play_database holds $tables_in_pod tables; not seeded"
fi

plist=$HOME/Library/LaunchAgents/com.genesis-prime.play-service.plist
mkdir -p "$(dirname "$plist")"
cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.genesis-prime.play-service</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$state/bin/update.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>120</integer>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StandardOutPath</key><string>$home/play-service.launchd.log</string>
  <key>StandardErrorPath</key><string>$home/play-service.launchd.log</string>
</dict>
</plist>
EOF
domain=gui/$(id -u)
launchctl bootout "$domain/com.genesis-prime.play-service" 2>/dev/null || true
launchctl bootstrap "$domain" "$plist"
log "launchd agent loaded: $plist"

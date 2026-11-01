#!/usr/bin/env bash
# Applies the migration files of priv/migrations to a database and records each
# one in its schema_migration table, the one place that does either: ./check,
# the tests' template database and the play database all use it.
#
# Usage: dev/apply_migrations.sh DATABASE
#        dev/apply_migrations.sh --adopt DATABASE
#
# DATABASE is on the Postgres PGHOST, PGPORT and PGUSER name (psql's own
# environment). The first form applies each file, in name order, that the
# database has not recorded: the file and the insert of its name and the
# SHA-256 of its bytes (lower-case hex, the form genesis_prime/migration reads)
# run in one transaction, so a file is applied and recorded, or neither. It
# stops at the first file that fails. A recorded file is skipped by name, even
# when its bytes have changed since: the server at start catches that
# (genesis_prime/readiness). It refuses a database that has tables and no
# schema_migration table, and says to adopt it.
#
# The files are the *.sql files directly in priv/migrations, the set the server
# reads at start (genesis_prime.load_migrations). Before any file runs, the
# script refuses the whole folder when a file's name is not letters, digits and
# underscores, or when a file holds a statement that would break the one
# transaction: BEGIN, COMMIT, ROLLBACK or START TRANSACTION alone in a
# statement, or CONCURRENTLY (CREATE INDEX CONCURRENTLY cannot run in a
# transaction). It reads a file's lines, not its SQL, so a BEGIN, COMMIT or
# ROLLBACK that is the whole of a line, ended by a semicolon, is refused even
# in a function body.
#
# The second form is for a database made before the record existed (the play
# database): it applies and records 0000_schema_migration.sql, and records the
# four migrations that database already ran (0001 to 0004) by name and hash
# without running them. It refuses a database that already has the record, and
# one where 0004's column is missing, which means those four did not all run.
# Run the first form after it for any newer file. Run it once per such database.

set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

. setup_check/sha256.sh

folder=priv/migrations
first=0000_schema_migration
adopted="0001_account_and_character 0002_character_list_columns 0003_character_look 0004_character_needs_rename"

adopting=no
if [ "${1:-}" = --adopt ]; then
  adopting=yes
  shift
fi
if [ $# -ne 1 ]; then
  echo "usage: dev/apply_migrations.sh [--adopt] DATABASE" >&2
  exit 2
fi
database=$1

sql() {
  psql -X -q -At -v ON_ERROR_STOP=1 -d "$database" "$@"
}

# insert_of NAME: the statement that records the file of that name.
insert_of() {
  echo "insert into schema_migration (name, sha256) values ('$1', '$(sha256 "$folder/$1.sql")')"
}

# The names of the files, in the byte order of the name, as the server sorts
# them: the *.sql files one level deep, read NUL-separated so no name is split
# or expanded.
names=()
while IFS= read -r -d '' file; do
  names+=("$(basename "$file" .sql)")
done < <(find "$folder" -maxdepth 1 -type f -name '*.sql' -print0 | LC_ALL=C sort -z)

# A shell that expands an empty array under set -u fails (bash 3.2, macOS), so
# each loop over the names guards its expansion with the same form.
for name in ${names[@]+"${names[@]}"}; do
  case "$name" in
    *[!0-9A-Za-z_]*)
      echo "apply_migrations: $name.sql is not a name of letters, digits and underscores" >&2
      exit 1
      ;;
  esac
  # Comment lines are dropped first, so a word in a comment is no statement.
  body=$(grep -v '^[[:space:]]*--' "$folder/$name.sql")
  if printf '%s\n' "$body" | grep -Eiq '^[[:space:]]*(begin|commit|rollback|start[[:space:]]+transaction)([[:space:]]+(work|transaction))?[[:space:]]*;'; then
    echo "apply_migrations: $name.sql holds BEGIN, COMMIT, ROLLBACK or START TRANSACTION; the script runs each file and its record in one transaction, which that would end" >&2
    exit 1
  fi
  if printf '%s\n' "$body" | grep -Eiq '(^|[^[:alnum:]_])concurrently([^[:alnum:]_]|$)'; then
    echo "apply_migrations: $name.sql uses CONCURRENTLY, which cannot run inside the one transaction the script runs each file and its record in" >&2
    exit 1
  fi
done

has_record=$(sql -c "select to_regclass('schema_migration') is not null") || exit 1

if [ "$adopting" = yes ]; then
  if [ "$has_record" = t ]; then
    echo "apply_migrations: $database already has schema_migration; nothing to adopt" >&2
    exit 1
  fi
  has_last=$(sql -c "select exists (select from information_schema.columns where table_name = 'character' and column_name = 'needs_rename')") || exit 1
  if [ "$has_last" != t ]; then
    echo "apply_migrations: $database lacks character.needs_rename, so it did not run 0001 to 0004" >&2
    exit 1
  fi
  statements=(-c "$(insert_of "$first")")
  for name in $adopted; do
    statements+=(-c "$(insert_of "$name")")
  done
  echo "adopting $database: applying $first, recording $adopted"
  sql --single-transaction -f "$folder/$first.sql" "${statements[@]}" || exit 1
  exit 0
fi

if [ "$has_record" != t ]; then
  tables=$(sql -c "select count(*) from information_schema.tables where table_schema = 'public'") || exit 1
  if [ "$tables" != 0 ]; then
    echo "apply_migrations: $database has tables and no schema_migration; run dev/apply_migrations.sh --adopt $database once" >&2
    exit 1
  fi
fi

for name in ${names[@]+"${names[@]}"}; do
  recorded=f
  if [ "$has_record" = t ]; then
    recorded=$(sql -c "select exists (select from schema_migration where name = '$name')") || exit 1
  fi
  if [ "$recorded" = t ]; then
    continue
  fi
  echo "applying $name"
  sql --single-transaction -f "$folder/$name.sql" -c "$(insert_of "$name")" || exit 1
  has_record=$(sql -c "select to_regclass('schema_migration') is not null") || exit 1
done

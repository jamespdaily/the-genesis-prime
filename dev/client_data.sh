#!/usr/bin/env bash
# The client's data for CI's full check, kept in the private repository
# <owner>/genesis-client-data and read by CI with a read-only deploy key.
#
#   dev/client_data.sh publish          Jim's command, run once at his terminal, and again
#                                       whenever the extractor or the client's data changes
#   dev/client_data.sh pack DIR         writes the files CI needs into the empty folder DIR
#   dev/client_data.sh unpack DIR [HOME]  checks DIR's stamp, then unpacks it under HOME
#                                       (default $HOME) in the layout ./check reads
#
# What is packed, from this machine's settings (setup_check/environment.sh, so env.sh):
#   tables        every file of $GENESIS_TABLE_DIR (setup_check/extract_tables.py fills it)
#   client-files  en-US.bin of the client-files folder (client_files.py extract fills it)
#   client        Client64/WildStar64.exe and Patch/*.index of the client $WILDSTAR_CLIENT_EXE names
#   world-data    every file of $GENESIS_WORLD_DATA
# Each is a gzip tar split into files of 45 MiB (GitHub warns at 50 MB), named
# <part>.tgz.aa, .ab and so on. STAMP holds the SHA-256 of each input whose change makes
# the packed data stale: the table extractor and client_files.py. pack refuses a client-files
# folder that client_files.py check does not call current.
#
# unpack puts the parts at $HOME/.genesis-prime/{tables,client-files,client,world-data}, where
# ./check finds the tables and the client files by default; CI names the client's exe
# ($HOME/.genesis-prime/client/Client64/WildStar64.exe) and the world data. It refuses, naming
# `dev/client_data.sh publish`, when STAMP differs from this commit's inputs.
#
# publish packs, creates the private repository when it is missing, pushes the pack as the
# repository's only commit (history is replaced, so old copies do not pile up), adds a new
# read-only deploy key, stores its private half as the secret CLIENT_DATA_KEY of this
# repository, then removes the deploy keys it replaced. A second run replaces the first's key.
# It needs gh logged in with rights to create repositories, deploy keys and secrets.
set -euo pipefail

cd "$(dirname "$0")/.."
. setup_check/sha256.sh

part_size=47185920
key_title="CI read-only"
inputs=(
  setup_check/extract_tables.py
  .claude/skills/decoding-the-client/scripts/client_files.py
)

fail() {
  echo "client_data: $*" >&2
  exit 1
}

# archive OUT NAME FOLDER FILE...: the files of FOLDER as OUT/NAME.tgz.aa, .ab and so on.
archive() {
  local out=$1 name=$2 folder=$3
  shift 3
  [ -d "$folder" ] || fail "$name: no folder $folder"
  COPYFILE_DISABLE=1 tar -czf - --no-xattrs -C "$folder" "$@" | split -b "$part_size" - "$out/$name.tgz."
}

pack() {
  local out=${1:-}
  [ -n "$out" ] || fail "pack needs a folder: dev/client_data.sh pack DIR"
  mkdir -p "$out"
  [ -z "$(ls -A "$out")" ] || fail "$out is not empty"
  # shellcheck source=/dev/null
  . setup_check/environment.sh
  [ -n "${GENESIS_TABLE_DIR:-}" ] || fail "GENESIS_TABLE_DIR is not set (GENESIS_NO_CLIENT=1 is)"
  [ -f "${WILDSTAR_CLIENT_EXE:-}" ] || fail "WILDSTAR_CLIENT_EXE names no file"
  [ -d "${GENESIS_WORLD_DATA:-}" ] || fail "GENESIS_WORLD_DATA names no folder"
  local files=${GENESIS_CLIENT_FILES_DIR:-${GENESIS_HOME:-$HOME/.genesis-prime}/client-files}
  python3.13 -I .claude/skills/decoding-the-client/scripts/client_files.py check ||
    fail "the client-files folder is not current: run client_files.py extract"
  local root indexes=() index
  root=$(dirname "$(dirname "$WILDSTAR_CLIENT_EXE")")
  for index in "$root"/Patch/*.index; do
    indexes+=("Patch/$(basename "$index")")
  done
  archive "$out" tables "$GENESIS_TABLE_DIR" .
  archive "$out" client-files "$files" en-US.bin
  archive "$out" client "$root" Client64/WildStar64.exe "${indexes[@]}"
  archive "$out" world-data "$GENESIS_WORLD_DATA" .
  local input
  for input in "${inputs[@]}"; do
    echo "$(sha256 "$input")  $input"
  done >"$out/STAMP"
  echo "packed into $out:"
  ls -l "$out"
}

# check_stamp DIR: fails, naming the publishing command, when DIR's STAMP differs from this
# commit's inputs.
check_stamp() {
  local hash input stale=()
  [ -f "$1/STAMP" ] || fail "$1 holds no STAMP"
  while read -r hash input; do
    [ "$(sha256 "$input")" = "$hash" ] || stale+=("$input")
  done <"$1/STAMP"
  [ "${#stale[@]}" -eq 0 ] ||
    fail "the client data was packed from other versions of ${stale[*]}: Jim runs 'dev/client_data.sh publish' at his terminal to pack it again"
}

unpack() {
  local from=${1:-} dest=${2:-$HOME}/.genesis-prime part
  [ -n "$from" ] || fail "unpack needs the packed folder: dev/client_data.sh unpack DIR [HOME]"
  check_stamp "$from"
  for part in tables client-files client world-data; do
    rm -rf "${dest:?}/$part"
    mkdir -p "$dest/$part"
    cat "$from/$part".tgz.* | tar -xzf - -C "$dest/$part"
  done
  echo "unpacked into $dest"
}

publish() {
  local work code_repo data_repo old_keys id
  work=$(mktemp -d)
  trap "rm -rf '$work'" EXIT
  umask 077
  code_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  data_repo=${code_repo%%/*}/genesis-client-data
  pack "$work/pack"
  if ! gh repo view "$data_repo" >/dev/null 2>&1; then
    gh repo create "$data_repo" --private --description "The client's data for CI's full check; written by dev/client_data.sh publish"
  fi
  git -C "$work/pack" init -q -b main
  git -C "$work/pack" add .
  git -C "$work/pack" commit -q -m "The client's data"
  git -C "$work/pack" -c "credential.helper=!gh auth git-credential" push --force \
    "https://github.com/$data_repo.git" main
  old_keys=$(gh api "repos/$data_repo/keys" --jq ".[] | select(.title == \"$key_title\") | .id")
  ssh-keygen -q -t ed25519 -N "" -C "$key_title" -f "$work/key"
  gh repo deploy-key add "$work/key.pub" --repo "$data_repo" --title "$key_title"
  gh secret set CLIENT_DATA_KEY --repo "$code_repo" <"$work/key"
  for id in $old_keys; do
    gh api -X DELETE "repos/$data_repo/keys/$id"
  done
  echo "published $data_repo; CI's secret CLIENT_DATA_KEY on $code_repo holds its read-only key"
}

case "${1:-}" in
  pack) pack "${2:-}" ;;
  unpack) unpack "${2:-}" "${3:-}" ;;
  publish) publish ;;
  *) fail "usage: dev/client_data.sh pack DIR | unpack DIR [HOME] | publish" ;;
esac

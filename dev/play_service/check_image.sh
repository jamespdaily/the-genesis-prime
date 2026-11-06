#!/usr/bin/env bash
# Refuses an image that holds a file of the client's: lists every file in the
# image with its SHA-256 and compares each with the SHA-256 of every file in the
# folders named, which are the client's own (the extracted tables, the client's
# files). An empty file is left out of both sides, since every empty file is
# alike. A match prints the image's path and exits 1. update.sh runs it on each
# image it builds, before the image is used.
#
# Usage: dev/play_service/check_image.sh IMAGE FOLDER...
#
# Needs podman, and shasum or sha256sum on this machine.
set -euo pipefail
export LC_ALL=C

[ $# -ge 2 ] || { echo "usage: dev/play_service/check_image.sh IMAGE FOLDER..." >&2; exit 2; }
image=$1
shift

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for folder in "$@"; do
  [ -d "$folder" ] || { echo "check_image: $folder is not a folder" >&2; exit 2; }
  find "$folder" -type f -size +0c -print0 | xargs -0 shasum -a 256 | cut -d' ' -f1
done | sort -u >"$work/client_hashes"

podman run --rm --entrypoint /bin/sh "$image" -c \
  'find / -xdev -type f -size +0c -not -path "/proc/*" -exec sha256sum {} +' |
  sort -k1,1 >"$work/image_files"

join "$work/client_hashes" "$work/image_files" >"$work/found" || true
if [ -s "$work/found" ]; then
  echo "check_image: $image holds files of the client's:" >&2
  cut -d' ' -f2- "$work/found" >&2
  exit 1
fi
echo "check_image: $image holds none of the $(wc -l <"$work/client_hashes" | tr -d ' ') files in $*"

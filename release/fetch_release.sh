#!/usr/bin/env bash
# Downloads one asset of a GitHub release and refuses it unless its SHA-256 is
# the digest GitHub publishes for that asset, as setup_check/build_patched_otp.sh
# does for the OTP source. Used by release/Containerfile for the gleam and rebar3
# programs it builds with.
#
# Usage: release/fetch_release.sh REPOSITORY TAG ASSET DIRECTORY
#
# REPOSITORY is owner/name. The asset is saved as DIRECTORY/ASSET. Needs gh,
# which reads GH_TOKEN, and shasum or sha256sum.
set -euo pipefail

[ $# -eq 4 ] || { echo "usage: release/fetch_release.sh REPOSITORY TAG ASSET DIRECTORY" >&2; exit 2; }
repository=$1
tag=$2
asset=$3
directory=$4

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. setup_check/sha256.sh

gh release download "$tag" --repo "$repository" --pattern "$asset" --dir "$directory"
published=$(gh api "repos/$repository/releases/tags/$tag" \
  --jq ".assets[] | select(.name == \"$asset\") | .digest")
published=${published#sha256:}
[ -n "$published" ] || { echo "the release $tag of $repository publishes no digest for $asset" >&2; exit 1; }
actual=$(sha256 "$directory/$asset")
if [ "$actual" != "$published" ]; then
  echo "SHA-256 of $asset is $actual, the release publishes $published" >&2
  exit 1
fi
echo "fetched $asset of $repository $tag, SHA-256 $actual"

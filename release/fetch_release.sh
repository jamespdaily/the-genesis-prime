#!/usr/bin/env bash
# Downloads one asset of a public GitHub release and refuses it unless its
# SHA-256 is the digest GitHub publishes for that asset. Used by
# setup_check/build_patched_otp.sh for the OTP source and by release/Containerfile
# for the gleam and rebar3 programs, so the build holds no GitHub login: the
# download is plain HTTPS and the digest comes from the unauthenticated API. A
# GH_TOKEN in the environment (CI sets one, for the runners' shared rate limit)
# is sent as a bearer token to api.github.com only.
#
# Usage: release/fetch_release.sh REPOSITORY TAG ASSET DIRECTORY
#
# REPOSITORY is owner/name. The asset is saved as DIRECTORY/ASSET. Needs curl, jq,
# and shasum or sha256sum.
set -euo pipefail

[ $# -eq 4 ] || { echo "usage: release/fetch_release.sh REPOSITORY TAG ASSET DIRECTORY" >&2; exit 2; }
repository=$1
tag=$2
asset=$3
directory=$4

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. setup_check/sha256.sh

curl --fail --silent --show-error --location --retry 3 \
  --output "$directory/$asset" \
  "https://github.com/$repository/releases/download/$tag/$asset"

authorization=()
[ -z "${GH_TOKEN:-}" ] || authorization=(--header "Authorization: Bearer $GH_TOKEN")
published=$(curl --fail --silent --show-error --location --retry 3 \
  ${authorization[@]+"${authorization[@]}"} \
  --header "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$repository/releases/tags/$tag" |
  jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .digest')
published=${published#sha256:}
[ -n "$published" ] && [ "$published" != null ] || {
  echo "the release $tag of $repository publishes no digest for $asset" >&2
  exit 1
}
actual=$(sha256 "$directory/$asset")
if [ "$actual" != "$published" ]; then
  echo "SHA-256 of $asset is $actual, the release publishes $published" >&2
  exit 1
fi
echo "fetched $asset of $repository $tag, SHA-256 $actual"

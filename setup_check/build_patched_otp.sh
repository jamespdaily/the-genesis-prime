#!/usr/bin/env bash
# Builds the patched Erlang/OTP the full check runs on, from the official
# source release named by the erlang version in .tool-versions, and installs it
# into $GENESIS_OTP_DIR (default $GENESIS_HOME/otp-<version>-gc-marker, with
# GENESIS_HOME defaulting to ~/.genesis-prime).
#
# It downloads otp_src_<version>.tar.gz from the erlang/otp GitHub release,
# refuses it unless its SHA-256 is the digest GitHub publishes for that release
# asset, applies every setup_check/*.patch, configures, builds, installs, and
# writes $GENESIS_OTP_DIR/GENESIS_PATCHES: one line per patch, "NAME SHA-256",
# the hash being that of the patch file in setup_check/. The setup check
# requires a line with the matching hash for every setup_check/*.patch, so a
# changed patch asks for a rebuild. Takes minutes, and prints its wall time at
# the end. Runs on macOS and on Linux (CI, the ubuntu runner). Needs gh and a C
# toolchain, and OpenSSL 3: on macOS from brew (openssl@3), on Linux from the
# system (libssl-dev, with libncurses-dev, autoconf and m4 for configure; this
# script installs nothing).
#
# Usage: setup_check/build_patched_otp.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
repository=$PWD

version=$(awk '$1 == "erlang" { print $2 }' .tool-versions)
[ -n "$version" ] || { echo "no erlang version in .tool-versions" >&2; exit 1; }
home=${GENESIS_HOME:-$HOME/.genesis-prime}
target=${GENESIS_OTP_DIR:-$home/otp-$version-gc-marker}
tag=OTP-$version
tarball=otp_src_$version.tar.gz

case "$(uname -s)" in
  Darwin)
    cpus=$(sysctl -n hw.ncpu)
    ssl_option=(--with-ssl="$(brew --prefix openssl@3)")
    ;;
  *)
    cpus=$(nproc)
    ssl_option=(--with-ssl)
    ;;
esac

# sha256 FILE: the file's SHA-256, from whichever tool this machine has.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# marker_lines DIRECTORY: one line per DIRECTORY/*.patch, "NAME SHA-256".
marker_lines() {
  local patch
  for patch in "$1"/*.patch; do
    [ -e "$patch" ] || continue
    printf '%s %s\n' "$(basename "$patch")" "$(sha256 "$patch")"
  done
}

work=$(mktemp -d "${TMPDIR:-/tmp}/genesis-otp-build.XXXXXX")
trap 'rm -rf "$work"' EXIT

echo "downloading $tarball from the erlang/otp release $tag"
gh release download "$tag" --repo erlang/otp --pattern "$tarball" --dir "$work"

published=$(gh api "repos/erlang/otp/releases/tags/$tag" \
  --jq ".assets[] | select(.name == \"$tarball\") | .digest")
published=${published#sha256:}
[ -n "$published" ] || { echo "the release $tag publishes no digest for $tarball" >&2; exit 1; }
actual=$(sha256 "$work/$tarball")
if [ "$actual" != "$published" ]; then
  echo "SHA-256 of $tarball is $actual, the release publishes $published" >&2
  exit 1
fi

tar -xzf "$work/$tarball" -C "$work"
source_dir=$work/otp_src_$version
for patch in "$repository"/setup_check/*.patch; do
  [ -e "$patch" ] || continue
  echo "applying $(basename "$patch")"
  patch -p1 --directory="$source_dir" <"$patch"
done

cd "$source_dir"
./configure --prefix="$target" --without-wx --without-javac --without-odbc "${ssl_option[@]}"
make -j"$cpus"
make install

marker_lines "$repository/setup_check" >"$target/GENESIS_PATCHES"
echo "installed OTP $version with $(wc -l <"$target/GENESIS_PATCHES" | tr -d ' ') patch(es) into $target"
echo "patched OTP build wall time ${SECONDS}s"

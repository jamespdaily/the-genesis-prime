# Sourced by ./check and ./setup-check (POSIX sh), from the repository's folder.
# Reads the machine's settings, $GENESIS_HOME/env.sh (GENESIS_HOME defaults to
# ~/.genesis-prime) if it exists, then puts the patched OTP's bin
# ($GENESIS_OTP_DIR, default $GENESIS_HOME/otp-<erlang version in
# .tool-versions>-gc-marker) first on PATH, so the shell's own Erlang, used by
# other projects, stays as it is. Not where GENESIS_NO_CLIENT=1 (no client) and
# GENESIS_OTP_DIR is unset; CI sets both, so it runs on the patched build it
# caches.
# Where the client is installed it also names GENESIS_TABLE_DIR, the folder
# setup_check/extract_tables.py fills with the client's game tables (default
# $GENESIS_HOME/tables); env.sh may set it first.
genesis_home=${GENESIS_HOME:-$HOME/.genesis-prime}
if [ -f "$genesis_home/env.sh" ]; then
  . "$genesis_home/env.sh"
fi
if [ "${GENESIS_NO_CLIENT:-}" != 1 ] || [ -n "${GENESIS_OTP_DIR:-}" ]; then
  if [ -z "${GENESIS_OTP_DIR:-}" ]; then
    GENESIS_OTP_DIR=$genesis_home/otp-$(awk '$1 == "erlang" { print $2 }' .tool-versions)-gc-marker
  fi
  export GENESIS_OTP_DIR
  PATH=$GENESIS_OTP_DIR/bin:$PATH
fi
if [ "${GENESIS_NO_CLIENT:-}" != 1 ]; then
  GENESIS_TABLE_DIR=${GENESIS_TABLE_DIR:-$genesis_home/tables}
  export GENESIS_TABLE_DIR
fi
unset genesis_home

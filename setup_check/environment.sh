# Sourced by ./check and ./setup-check (POSIX sh), from the repository's folder.
# Reads the machine's settings, $GENESIS_HOME/env.sh (GENESIS_HOME defaults to
# ~/.genesis-prime) if it exists, then, unless GENESIS_NO_CLIENT=1 (CI), puts
# the patched OTP's bin ($GENESIS_OTP_DIR, default
# $GENESIS_HOME/otp-<erlang version in .tool-versions>-gc-marker) first on PATH,
# so the shell's own Erlang, used by other projects, stays as it is.
genesis_home=${GENESIS_HOME:-$HOME/.genesis-prime}
if [ -f "$genesis_home/env.sh" ]; then
  . "$genesis_home/env.sh"
fi
if [ "${GENESIS_NO_CLIENT:-}" != 1 ]; then
  if [ -z "${GENESIS_OTP_DIR:-}" ]; then
    GENESIS_OTP_DIR=$genesis_home/otp-$(awk '$1 == "erlang" { print $2 }' .tool-versions)-gc-marker
  fi
  export GENESIS_OTP_DIR
  PATH=$GENESIS_OTP_DIR/bin:$PATH
fi
unset genesis_home

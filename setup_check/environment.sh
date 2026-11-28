# Sourced by ./check and ./setup-check (POSIX sh), from the repository's folder. Load it in
# any shell that runs the tests outside them (`gleam test`, dev/repeat_tests.py):
# `. setup_check/environment.sh`; a shell that cannot source it runs `dev/with_env <command>`.
# Reads the machine's settings, $GENESIS_HOME/env.sh (GENESIS_HOME defaults to
# ~/.genesis-prime) if it exists. The erl on PATH is the OTP: the setup check refuses
# any version but .tool-versions' (Homebrew's erlang on a Mac, setup-beam in CI).
# Where the client is installed it also names GENESIS_TABLE_DIR, the folder
# setup_check/extract_tables.py fills with the client's game tables (default
# $GENESIS_HOME/tables), and GENESIS_TERRAIN_DIR, the folder dev/terrain_extract.py fills
# with the ground files (default $GENESIS_HOME/terrain); env.sh may set either first.
genesis_home=${GENESIS_HOME:-$HOME/.genesis-prime}
if [ -f "$genesis_home/env.sh" ]; then
  . "$genesis_home/env.sh"
fi
if [ "${GENESIS_NO_CLIENT:-}" != 1 ]; then
  GENESIS_TABLE_DIR=${GENESIS_TABLE_DIR:-$genesis_home/tables}
  export GENESIS_TABLE_DIR
  GENESIS_TERRAIN_DIR=${GENESIS_TERRAIN_DIR:-$genesis_home/terrain}
  export GENESIS_TERRAIN_DIR
fi
# Every VM started from a shell that loaded this file (the test VMs and the development
# servers) keeps each process's message queue off its heap (+hmqd off_heap): the VM's abort
# in major_collection after move_msgs_to_heap is a step only a process with an on-heap
# queue takes. ERL_AFLAGS goes before a command line's own flags, so a VM that names +hmqd
# itself keeps its own: the release (release/vm.args) and the load-run server name
# off_heap too. A child VM (a peer, a port) inherits it.
ERL_AFLAGS="+hmqd off_heap${ERL_AFLAGS:+ $ERL_AFLAGS}"
export ERL_AFLAGS
unset genesis_home

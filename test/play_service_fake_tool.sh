#!/bin/bash
# A stand-in for `podman` and `lsof`, copied under each name into a test's folder
# of fakes (test/play_service_support.gleam). It records every call as one line
# in $FAKE_DIR/calls and answers from the files planted in $FAKE_DIR/answers:
#
#   KEY.exit    one exit status per line; the nth call gets the nth line, the
#               last line stands for every later call; no file means 0
#   KEY.out     what the call prints on standard output
#   KEY.err     what it prints on standard error
#   KEY.block   the call writes its process id to KEY.pid and waits, so it ends
#               only when its caller ends it
#
# The key is worked out from the call: info, exists.NAME, status.NAME (inspect of
# the status), labels.NAME (inspect of the labels), ready (exec of pg_isready),
# machine.start and connections (lsof). A call that no key names answers 99
# without a file, so a call a test did not plan fails closed.

fakes=${FAKE_DIR:?FAKE_DIR names the folder of fakes}
answers=$fakes/answers
tool=${0##*/}
printf '%s %s\n' "$tool" "$*" >>"$fakes/calls"

key=unplanned
if [ "$tool" = lsof ]; then
  key=connections
else
  case "$1" in
    info) key=info ;;
    exec) key=ready ;;
    machine) key=machine.$2 ;;
    container)
      case "$2" in
        exists) key=exists.$3 ;;
        inspect)
          case "$*" in
            *State.Status*) key=status.${*: -1} ;;
            *genesis.revision*) key=labels.${*: -1} ;;
          esac
          ;;
      esac
      ;;
  esac
fi

if [ ! -e "$answers/$key.exit" ] && [ ! -e "$answers/$key.out" ] && [ ! -e "$answers/$key.err" ] && [ ! -e "$answers/$key.block" ]; then
  echo "fake $tool: no answer planted for $key" >&2
  exit 99
fi

if [ -e "$answers/$key.block" ]; then
  echo $$ >>"$answers/$key.pid"
  exec sleep 600
fi

count=$(($(cat "$answers/$key.count" 2>/dev/null || echo 0) + 1))
echo "$count" >"$answers/$key.count"
if [ -e "$answers/$key.out" ]; then cat "$answers/$key.out"; fi
if [ -e "$answers/$key.err" ]; then cat "$answers/$key.err" >&2; fi
status=$(sed -n "${count}p" "$answers/$key.exit" 2>/dev/null || true)
[ -n "$status" ] || status=$(tail -n 1 "$answers/$key.exit" 2>/dev/null || true)
exit "${status:-0}"

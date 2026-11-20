#!/bin/bash
# A stand-in for the look of state.sh's `bounded` (GENESIS_PLAY_LOOK_COMMAND),
# copied into a test's folder of fakes (test/play_service_support.gleam). The
# script calls it as `look PID` once for each look it takes at the call PID, in
# place of waiting 0.05 s, so what a bound or the budget decides does not depend
# on how fast the machine runs:
#
#   - a call that ends by itself (a fake that answers) ends the look at once, so
#     it costs one look and can never run out of its bound;
#   - a call the fake tool recorded as blocked (KEY.pid in $FAKE_DIR/answers) ends
#     the look at once too, so the bound counts out its looks without waiting.
#
# While the file $FAKE_DIR/look.hold exists the look first records the process id
# of its caller (the shell that waits for the call) in $FAKE_DIR/look.waiter and
# waits for the hold to be removed, so a test can end the script while a look
# is pending and then let the waiter go on.

fakes=${FAKE_DIR:?FAKE_DIR names the folder of fakes}
pid=${1:?look names the call}

if [ -e "$fakes/look.hold" ]; then
  echo "$PPID" >"$fakes/look.waiter"
  while [ -e "$fakes/look.hold" ]; do sleep 0.01; done
fi

while kill -0 "$pid" 2>/dev/null; do
  if grep -qx "$pid" "$fakes"/answers/*.pid 2>/dev/null; then
    exit 0
  fi
  sleep 0.01
done

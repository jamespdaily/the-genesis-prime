#!/usr/bin/env bash
# SessionStart hook: holds `caffeinate -ims -w <pid>` on the session's claude process, so the
# Mac does not idle-sleep while builders run and the lock ends with the session. It walks up
# from its own parent to the first process named claude, starts one caffeinate in the
# background unless one already waits on that pid, and prints nothing. Where there is no
# caffeinate or no claude process it does nothing. It always exits 0.
command -v caffeinate >/dev/null || exit 0
pid=$PPID
while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
  comm=$(ps -o comm= -p "$pid")
  [ "${comm##*/}" = claude ] && break
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done
{ [ -n "$pid" ] && [ "$pid" -gt 1 ]; } || exit 0
pgrep -f "caffeinate -ims -w $pid\$" >/dev/null && exit 0
nohup caffeinate -ims -w "$pid" </dev/null >/dev/null 2>&1 &
exit 0

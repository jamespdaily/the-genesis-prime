"""Watches the play server's herdr pane and prints each new line that names a crash.

    python3 -I watch_server.py PANE_ID [--once]

PANE_ID is the herdr pane of the tab labelled `server` (`herdr tab list`, `herdr pane list`).
Every 5 s it reads the pane's last 400 lines and prints each line it has not seen that
matches PATTERN (a crash, supervisor or error report, a panic, a refusal), with the three
lines after it. Lines already in the pane when it starts are not printed, and
IGNORE lines (the client's Auth/PageVerifiedIps request, unhandled game messages) never are.
With --once it exits after the first line it prints, so a background Bash job reports it and
ends; start it again after that. A failed pane read is printed and retried after 15 s.
"""
import re
import subprocess
import sys
import time

PANE = sys.argv[1]
PATTERN = re.compile(r"CRASH REPORT|ERROR REPORT|SUPERVISOR REPORT|unhandled game message|panic|exception|refused|terminating|crasher|reason:")
IGNORE = re.compile(r"/Auth/PageVerifiedIps|unhandled game message")

seen = set()
first = True
while True:
    try:
        out = subprocess.run(
            ["herdr", "pane", "read", PANE, "--source", "recent-unwrapped", "--lines", "400"],
            capture_output=True, text=True, timeout=20,
        ).stdout
    except Exception as error:  # a failed read must not end the watch
        print(f"watch: pane read failed: {error}", flush=True)
        time.sleep(15)
        continue
    lines = out.splitlines()
    for index, line in enumerate(lines):
        key = line.strip()
        if not key or key in seen:
            continue
        seen.add(key)
        if first or IGNORE.search(line) or not PATTERN.search(line):
            continue
        context = " | ".join(l.strip() for l in lines[index + 1:index + 4] if l.strip())
        print(f"{key[:300]}  >>  {context[:400]}", flush=True)
        if "--once" in sys.argv:
            sys.exit(0)
    first = False
    time.sleep(5)

"""Every 30 s, decode the newest play sitting and print one line per new anomaly.

Flags:
- a refused press (0x7fc) with its spell and result;
- a cast whose goes, from its first strike on, struck nobody at some go, unless the go's
  unit dodged (0x7fb) or a unit died during the cast (a wind-up go before the first strike
  is normal);
- a cast that ended before any go;
- a player death (0x88c on unit 1).
Finished casts are judged after the whole pass, since a death is told just after the finish.
Run during a live sitting, from the repository: python3 -I dev/live_watch.py .
"""

import re
import subprocess
import sys
import time
from pathlib import Path

repo = sys.argv[1]
sittings = Path.home() / ".genesis-prime" / "sittings"
seen: set[str] = set()
first_pass = True  # the events before the watch starts are only remembered

started = re.compile(r"spell_started SpellStarted\(cast_id: ([\d_]+), spell4_id: (\d+), root_spell4_id: (\d+), parent_spell4_id: (\d+), caster_unit_id: (\d+)")
go = re.compile(r"spell_go SpellGo\(cast_id: ([\d_]+),.*?targets: \[(.?)")
fin = re.compile(r"spell_finished SpellFinished\(cast_id: ([\d_]+)\)")
missed = re.compile(r"spell_missed SpellMissed\(cast_id: ([\d_]+)")
killed = re.compile(r"UnitHealth\(unit_id: \d+, health: \d+, dead: 1")
refused = re.compile(r"spell_cast_refused SpellCastRefused\(client_cast_id: \d+, spell4_id: (\d+), result: (\w+)")
death = re.compile(r"unit_death_state UnitDeathState\(unit_id: (\d+)")
stamp = re.compile(r"^\d+ \+(\d+)ms")
conn = re.compile(r"game\.connection-(\d+)")


def emit(key: str, text: str) -> None:
    if key not in seen:
        seen.add(key)
        if not first_pass:
            print(text, flush=True)


while True:
    folders = sorted(p for p in sittings.iterdir() if p.is_dir())
    if folders:
        out = subprocess.run(
            ["gleam", "run", "-m", "genesis_prime/recording_dump", "--", str(folders[-1])],
            cwd=repo, capture_output=True, text=True, timeout=120,
        ).stdout
        casts: dict[str, dict] = {}
        open_casts: set[str] = set()
        finished: list[dict] = []
        for line in out.splitlines():
            t = stamp.match(line)
            ms = t.group(1) if t else "?"
            k = conn.search(line)
            # cast ids restart on each connection, so a cast is keyed by its connection too
            line = re.sub(r"cast_id: (\d+)", lambda x: f"cast_id: {k.group(1) if k else 0}_{x.group(1)}", line)
            if m := started.search(line):
                cast_id, spell, root, _parent, _caster = m.groups()
                # 5649: the creatures' auto attack. 58832 Discharge: damage at its first pulse only.
                if spell not in ("5649", "58832"):
                    casts[cast_id] = {"spell": spell, "root": root, "goes": [], "ms": ms, "kill": False}
                    open_casts.add(cast_id)
            elif m := go.search(line):
                if m.group(1) in casts:
                    casts[m.group(1)]["goes"].append(m.group(2) != "]")
            elif m := missed.search(line):
                c = casts.get(m.group(1))
                if c and c["goes"]:
                    c["goes"][-1] = True  # a dodge or deflect: the go selected the unit
            elif killed.search(line):
                # a death during a cast, or told right after its finish
                for cast_id in open_casts:
                    casts[cast_id]["kill"] = True
                for c in finished[-3:]:
                    c["kill"] = True
            elif m := fin.search(line):
                if m.group(1) in casts:
                    open_casts.discard(m.group(1))
                    c = casts.pop(m.group(1))
                    c["id"] = m.group(1)
                    finished.append(c)
            elif m := refused.search(line):
                emit(f"ref{ms}{m.group(1)}", f"+{ms}ms press refused: spell {m.group(1)} {m.group(2)}")
            elif m := death.search(line):
                if m.group(1) == "1":
                    emit(f"die{ms}", f"+{ms}ms the player's death state changed")
        for c in finished:
            cast_id = c["id"] + "@" + c["ms"]
            hit = c["goes"]
            if not hit:
                emit(f"nogo{cast_id}", f"+{c['ms']}ms spell {c['spell']} (root {c['root']}) ended with no go")
                continue
            after_first = hit[hit.index(True):] if True in hit else []
            if after_first and not all(after_first) and not c["kill"]:
                emit(f"mix{cast_id}", f"+{c['ms']}ms spell {c['spell']} (root {c['root']}): {sum(hit)} of {len(hit)} goes struck someone")
    first_pass = False
    time.sleep(30)

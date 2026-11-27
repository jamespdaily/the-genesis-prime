#!/usr/bin/env bash
# SubagentStop hook: refuses a subagent's stop while a process it left still runs from its
# worktree, because three builders on 2026-11-26 handed back with a test run still going (one
# for about two hours) although their briefs said to leave no background job.
#
# Reads the hook's JSON on stdin: `agent_id`, and `stop_hook_active` (true when this stop
# follows a refusal). The worktree is `$CLAUDE_PROJECT_DIR/.claude/worktrees/agent-<agent_id>`,
# the folder `isolation: worktree` gives an agent. A process is left when its command line
# names that folder (a `gleam test` beam's `-pa` paths do) or its working directory is in it.
#
# Exit 2 with the processes on stderr refuses the stop: the agent goes on and must wait for or
# end them. On a stop that already followed a refusal, it lets the agent stop and prints a
# warning naming them instead, so a process the agent cannot end never traps it. An agent with
# no such worktree (a reviewer, an investigator) passes. Anything it cannot read passes.
input=$(cat)
read -r agent_id active < <(printf '%s' "$input" |
  python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d.get("agent_id") or "-", str(d.get("stop_hook_active", False)).lower())' 2>/dev/null) || exit 0
[ -n "$agent_id" ] && [ "$agent_id" != - ] || exit 0
tree="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/worktrees/agent-$agent_id"
[ -d "$tree" ] || exit 0
real=$(cd "$tree" && pwd -P)  # lsof names a working directory by its resolved path

# The hook and the shells that started it may stand in the worktree too: leave out its own
# chain of parents.
own=$$
pid=$$
while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
  own="$own $pid"
done

pids=$( { pgrep -f -- "$tree/"
          [ "$real" = "$tree" ] || pgrep -f -- "$real/"
          lsof -a -d cwd -Fpn 2>/dev/null | awk -v t="$real" '/^p/ {p = substr($0, 2)} /^n/ && (substr($0, 2) == t || index(substr($0, 2), t "/") == 1) {print p}'
        } | sort -un | grep -vxF -f <(printf '%s\n' $own) )
[ -n "$pids" ] || exit 0
listing=$(ps -o pid=,etime=,command= -p "$(echo $pids | tr ' ' ,)" 2>/dev/null | cut -c1-160)
[ -n "$listing" ] || exit 0

if [ "$active" = true ]; then
  printf '{"systemMessage": %s}\n' "$(printf 'Subagent %s stopped with processes still running from %s:\n%s' "$agent_id" "$tree" "$listing" |
    python3 -I -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  exit 0
fi
printf 'Processes you started still run from your worktree %s. Wait for each to end, or end it if it is yours and no longer needed, then hand back:\n%s\n' "$tree" "$listing" >&2
exit 2

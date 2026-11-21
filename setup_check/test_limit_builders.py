"""dev/hooks/limit_builders.py: refuses a spawn of an `implementer` agent while as many builders run
as the machine has test slots (dev/hooks/machine_slots.py).

Each test plants a project folder the way Claude Code writes it, `PROJECT/SESSION/subagents/agent-ID.meta.json`
(`agentType`, `description`, `toolUseId`, `finished` once the agent ends) beside `agent-ID.jsonl` (the
transcript, whose modification time is the agent's last write), and a ledger file in a temporary folder.
The hook's `refusal(event, ledger_path, now)` is called with an event shaped like the hook's input
(`tool_input.subagent_type`, `tool_use_id`, `transcript_path`). The layout was read in
~/.claude/projects/-Users-jimd-Projects-the-genesis-prime/*/subagents/ on 2026-11-20.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_limit_builders.py'
"""

import fcntl
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "dev" / "hooks"))

import limit_builders  # noqa: E402
import machine_slots  # noqa: E402

NOW = 1_800_000_000.0


class Plant:
    """A project folder with one session, and a ledger path beside it."""

    def __init__(self, folder: str):
        self.project = Path(folder) / "project"
        self.subagents = self.project / "session-1" / "subagents"
        self.subagents.mkdir(parents=True)
        self.transcript = self.project / "session-1.jsonl"
        self.ledger = Path(folder) / "builder-starts"

    def agent(self, agent_id: str, agent_type: str = "implementer", description: str = "a build",
              finished: bool = False, quiet_seconds: float = 60, tool_use_id: str | None = None) -> None:
        meta = {"agentType": agent_type, "description": description,
                "toolUseId": tool_use_id or f"toolu_{agent_id}"}
        if finished:
            meta["finished"] = True
        (self.subagents / f"agent-{agent_id}.meta.json").write_text(json.dumps(meta))
        transcript = self.subagents / f"agent-{agent_id}.jsonl"
        transcript.write_text("{}\n")
        os.utime(transcript, (NOW - quiet_seconds, NOW - quiet_seconds))

    def spawn(self, subagent_type: str = "implementer", tool_use_id: str | None = "toolu_new") -> dict:
        event = {"tool_input": {"subagent_type": subagent_type, "description": "the new one"},
                 "transcript_path": str(self.transcript)}
        if tool_use_id is not None:
            event["tool_use_id"] = tool_use_id
        return event

    def ask(self, event: dict, lock_tries: int = 1) -> str | None:
        return limit_builders.refusal(event, self.ledger, NOW, lock_tries=lock_tries)

    def ledger_ids(self) -> list[str]:
        return [line.split()[1] for line in self.ledger.read_text().splitlines()]


class LimitBuildersTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.plant = Plant(temporary.name)

    def test_a_third_builder_is_refused_naming_the_two_that_run(self):
        self.plant.agent("a1", description="Build the sight part 1")
        self.plant.agent("a2", description="Fix the socket")
        refused = self.plant.ask(self.plant.spawn())
        self.assertIsNotNone(refused)
        self.assertIn("Build the sight part 1", refused)
        self.assertIn("Fix the socket", refused)
        self.assertIn("agent a1", refused)
        self.assertIn("1 min ago", refused)

    def test_one_builder_running_leaves_room_for_a_second(self):
        self.plant.agent("a1")
        self.assertIsNone(self.plant.ask(self.plant.spawn()))

    def test_a_finished_or_quiet_builder_is_not_counted(self):
        self.plant.agent("done", finished=True)
        self.plant.agent("dead", quiet_seconds=16 * 60)
        self.plant.agent("live")
        self.assertIsNone(self.plant.ask(self.plant.spawn()))

    def test_reviewers_investigators_and_other_agents_neither_count_nor_are_refused(self):
        self.plant.agent("r1", agent_type="reviewer")
        self.plant.agent("r2", agent_type="reviewer")
        self.plant.agent("i1", agent_type="investigator")
        self.assertIsNone(self.plant.ask(self.plant.spawn()), "live reviewers and investigators are no builders")
        self.plant.agent("a1")
        self.plant.agent("a2")
        for other in ("reviewer", "investigator", "general-purpose"):
            with self.subTest(other=other):
                self.assertIsNone(self.plant.ask(self.plant.spawn(other)))

    def test_two_spawns_in_one_message_count_each_other_through_the_ledger(self):
        self.assertIsNone(self.plant.ask(self.plant.spawn(tool_use_id="toolu_A")))
        self.assertIsNone(self.plant.ask(self.plant.spawn(tool_use_id="toolu_B")))
        self.assertIsNotNone(self.plant.ask(self.plant.spawn(tool_use_id="toolu_C")))
        self.assertEqual(self.plant.ledger_ids(), ["toolu_A", "toolu_B"])

    def test_a_start_stops_counting_when_its_agent_shows_or_after_sixty_seconds(self):
        self.plant.ledger.write_text(f"{NOW - 5} toolu_shown\n")
        self.plant.agent("a1", tool_use_id="toolu_shown")
        self.assertIsNone(self.plant.ask(self.plant.spawn()), "the entry and its agent are one builder")
        self.plant.ledger.write_text(f"{NOW - 61} toolu_old1\n{NOW - 61} toolu_old2\n")
        self.assertIsNone(self.plant.ask(self.plant.spawn()), "an entry of 61 seconds counts for nothing")
        self.plant.ledger.write_text(f"{NOW - 59} toolu_young\n")
        self.assertIsNotNone(self.plant.ask(self.plant.spawn()), "an entry of 59 seconds is a builder starting")

    def test_a_malformed_ledger_line_is_dropped_and_the_cap_still_holds(self):
        self.plant.ledger.write_text(f"{NOW - 5} toolu_x\n{NOW - 5}\nnot a number toolu_y\n\n")
        self.assertIsNone(self.plant.ask(self.plant.spawn(tool_use_id="toolu_A")))
        self.assertEqual(self.plant.ledger_ids(), ["toolu_x", "toolu_A"], "the bad lines are rewritten away")
        self.assertIsNotNone(self.plant.ask(self.plant.spawn(tool_use_id="toolu_B")))

    def test_a_meta_whose_transcript_does_not_exist_yet_is_a_builder_starting(self):
        self.plant.agent("a1")
        self.plant.agent("a2")
        (self.plant.subagents / "agent-a2.jsonl").unlink()
        meta = self.plant.subagents / "agent-a2.meta.json"
        os.utime(meta, (NOW - 5, NOW - 5))
        self.plant.ledger.write_text(f"{NOW - 5} toolu_a2\n")
        self.assertIsNotNone(self.plant.ask(self.plant.spawn()), "the entry and the bare meta are one builder, beside a1")
        self.plant.ledger.write_text("")
        self.assertIsNotNone(self.plant.ask(self.plant.spawn(tool_use_id=None)), "a bare meta counts without a ledger entry")
        os.utime(meta, (NOW - 61, NOW - 61))
        self.assertIsNone(self.plant.ask(self.plant.spawn(tool_use_id=None)), "a bare meta of 61 seconds counts for nothing")

    def test_a_spawn_without_a_tool_use_id_is_counted_but_not_recorded(self):
        self.assertIsNone(self.plant.ask(self.plant.spawn(tool_use_id=None)))
        self.assertEqual(self.plant.ledger.read_text(), "")

    def test_unreadable_input_a_missing_project_folder_and_a_locked_ledger_all_pass(self):
        self.plant.agent("a1")
        self.plant.agent("a2")
        self.assertIsNone(limit_builders.refusal("not a dict", self.plant.ledger, NOW))
        gone = self.plant.spawn()
        gone["transcript_path"] = str(self.plant.project / "missing" / "session.jsonl")
        self.assertIsNone(self.plant.ask(gone))
        self.plant.ledger.write_text("")
        with open(self.plant.ledger) as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            self.assertIsNone(self.plant.ask(self.plant.spawn(), lock_tries=1))

    def test_the_cap_is_the_number_of_test_slots(self):
        self.plant.agent("a1")
        self.plant.agent("a2")
        with mock.patch.object(machine_slots, "TEST_SLOTS", 3):
            self.assertIsNone(self.plant.ask(self.plant.spawn(tool_use_id="toolu_C")))
            self.plant.agent("a3")
            refused = self.plant.ask(self.plant.spawn(tool_use_id="toolu_D"))
        self.assertIsNotNone(refused)
        self.assertIn("3 builders already run", refused)
        with mock.patch.object(machine_slots, "TEST_SLOTS", 1):
            self.assertIsNotNone(self.plant.ask(self.plant.spawn(tool_use_id="toolu_E")))


if __name__ == "__main__":
    unittest.main()

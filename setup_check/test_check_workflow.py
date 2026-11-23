"""The shape of .github/workflows/check.yml: one job per part of ./check, and the gate.

The standard library has no YAML reader, so the tests read the file by its layout: a job is
a key at two spaces, a step a dash at six, a matrix leg one flow-style line
`- {name: PART}` (`fast: true` for a part of ./check fast). What the legs and the gate do
with a result is tested where it is decided: dev/ci_gate.py (test_ci_gate.py), `./check part`
and `./check scope` (test_check_script.py), dev/pr_wait.sh (test_pr_wait.py).

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_check_workflow.py'
"""

import re
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
WORKFLOW = REPOSITORY / ".github" / "workflows" / "check.yml"
TOOLCHAIN = REPOSITORY / ".github" / "actions" / "toolchain" / "action.yml"
CHECK = REPOSITORY / "check"

# What every step of a leg that a light change skips carries (see LIGHT below).
LIGHT = "matrix.fast || needs.scope.outputs.light != 'true'"


def without_comments(text: str) -> str:
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


def job(name: str) -> str:
    """The text of the job `name`, comments left out."""
    text = without_comments(WORKFLOW.read_text())
    found = re.search(r"(?ms)^  %s:\n(.*?)(?=^  [A-Za-z][A-Za-z-]*:\n|\Z)" % re.escape(name), text)
    assert found, "check.yml has no job %s" % name
    return found.group(1)


def steps(text: str, indent: int = 6) -> list[str]:
    """The steps of a job or a composite action: the text of each `- ` entry at `indent` spaces."""
    parts = re.split(r"(?m)^ {%d}- " % indent, text)
    return [part for part in parts[1:]]


def field(step: str, key: str) -> str:
    found = re.search(r"(?m)^\s*(?:- )?%s: ?(.*)$" % re.escape(key), step)
    return found.group(1).strip() if found else ""


def command(step: str) -> str:
    """What the step does, without its name, id, condition or retry setting."""
    return "\n".join(
        line for line in step.splitlines()
        if not re.match(r"\s*(name|id|if|continue-on-error):", line)).strip()


def step_named(step_list: list[str], name: str) -> str:
    found = [step for step in step_list if field(step, "name") == name]
    assert len(found) == 1, "one step is named %r: %s" % (name, found)
    return found[0]


def script_variable(name: str) -> list[str]:
    found = re.findall(r'(?m)^%s="([^"]*)"$' % name, CHECK.read_text())
    assert len(found) == 1, found
    return found[0].split()


def legs() -> list[tuple[str, bool]]:
    """The (name, fast) of each matrix leg of the job `part`."""
    return [
        (name.strip(), bool(fast))
        for name, fast in re.findall(r"(?m)^\s+- \{name: ([^,}]+?)(, fast: true)?\}$", job("part"))]


class CheckWorkflowTest(unittest.TestCase):
    def test_every_part_of_the_full_check_has_a_leg_and_the_gleam_test_legs_are_every_shard_of_one_count(self):
        parts = [part for part in script_variable("full_parts") if part != "literal-area"]
        names = [name for name, _ in legs()]
        self.assertEqual(sorted(name for name in names if not name.startswith("gleam-test ")),
                         sorted(part for part in parts if part != "gleam-test"),
                         "a leg for each part of ./check, none for literal-area (it is reported inside the legs that record a peak)")
        shards = [re.fullmatch(r"gleam-test (\d+)/(\d+)", name) for name in names if name.startswith("gleam-test ")]
        self.assertTrue(shards and all(shards), names)
        counts = {int(shard.group(2)) for shard in shards}
        self.assertEqual(len(counts), 1, "one count of shards")
        self.assertEqual(sorted(int(shard.group(1)) for shard in shards), list(range(1, counts.pop() + 1)))

    def test_a_failed_leg_does_not_cancel_the_other_legs(self):
        self.assertRegex(job("part"), r"(?m)^    strategy:\n      fail-fast: false$")

    def test_the_gate_job_is_named_check_needs_the_part_job_and_runs_when_a_part_fails(self):
        gate = job("check")
        self.assertEqual(field(gate, "name"), "check")
        self.assertEqual(field(gate, "needs"), "[tested, scope, tools, part]")
        self.assertIn("!cancelled()", field(gate, "if"))
        self.assertEqual(field(gate, "if"), field(job("part"), "if"), "the gate is skipped only when the part job is")
        self.assertIn("python3 -I dev/ci_gate.py", gate)
        self.assertIn("NEEDS: ${{ toJSON(needs) }}", gate, "the needs reach the script through the environment, not its text")
        leg_names = [name for name, _ in legs()]
        for reserved in ("check", "repeat", "tools"):
            self.assertNotIn(reserved, leg_names, "a leg named like a required check would stand in for it")
        self.assertEqual(field(job("part"), "name"), "${{ matrix.name }}")

    def test_only_the_gleam_build_leg_saves_the_build_cache(self):
        saves = [step for step in steps(job("part")) if "actions/cache/save" in step]
        self.assertEqual(len(saves), 1, saves)
        self.assertIn("matrix.name == 'gleam-build'", field(saves[0], "if"))

    def test_a_light_change_runs_only_the_fast_legs_and_the_gate_passes(self):
        self.assertEqual([name for name, fast in legs() if fast], script_variable("fast_parts"),
                         "the legs a light change runs are the parts of ./check fast")
        scope = job("scope")
        self.assertIn("pull_request", field(scope, "if"), "a push to main has no changed files to read, so every leg runs")
        self.assertIn("./check scope HEAD^1", scope)
        self.assertEqual(field(job("part"), "needs"), "[tested, scope]")
        self.assertIn("scope", field(job("check"), "needs"), "the gate reads the light verdict, to record no tree for a light run")
        every_step = steps(job("part"))
        for step in every_step:
            label = field(step, "name") or field(step, "uses") or field(step, "run")
            retry = re.search(r"steps\.(\w+)\.outcome == 'failure'", field(step, "if"))
            if retry:
                # A retry follows a step that was skipped (outcome skipped) or ran.
                self.assertTrue(
                    any(field(first, "id") == retry.group(1) and LIGHT in field(first, "if") for first in every_step), label)
            elif "actions/cache/save" in step:
                # Guarded by the gleam-build leg, which every light change runs.
                self.assertIn(("gleam-build", True), legs())
            else:
                self.assertIn(LIGHT, field(step, "if"), label)
        self.assertEqual(field(step_named(every_step, "Check the part"), "run"), "./check part ${{ matrix.name }}")

    def test_each_network_setup_step_is_retried_once(self):
        # (the steps, the step) whose network call can fail once and succeed on the next try; a second
        # failure fails the job: the retry has no continue-on-error.
        leg_steps = steps(job("part"))
        toolchain = steps(without_comments(TOOLCHAIN.read_text()), indent=4)
        rows = [
            (leg_steps, step_named(leg_steps, "Start Postgres"), "the Postgres image pull"),
            (leg_steps, step_named(leg_steps, "Fetch the client's data"), "the client data fetch over ssh"),
            (leg_steps, step_named(leg_steps, "Install llvm-objdump"), "apt for llvm-objdump"),
            (toolchain, next(step for step in toolchain if field(step, "id") == "beam"), "the toolchain's release downloads"),
        ]
        for step_list, first, why in rows:
            with self.subTest(why):
                self.assertEqual(field(first, "continue-on-error"), "true")
                identifier = field(first, "id")
                self.assertTrue(identifier)
                retries = [
                    step for step in step_list
                    if "steps.%s.outcome == 'failure'" % identifier in field(step, "if") and command(step) == command(first)]
                self.assertEqual(len(retries), 1, "one retry that does the same")
                self.assertEqual(field(retries[0], "continue-on-error"), "", "a second failure fails the job")
                self.assertGreater(step_list.index(retries[0]), step_list.index(first))


if __name__ == "__main__":
    unittest.main()

# The brief's headings

Each heading is left out when it has nothing.

- **Goal:** what a player or the client sees when it is done; the branch and its base.
- **Read:** each artifact's `gh issue artifact view N <number>`, and the test list comment.
- **Changed since the Design:** each later decision, who made it and why.
- **Ask back if:** what returns to the coordinator or Jim instead of being chosen.
- **Change / Leave alone:** the modules it may change; what is left out and who owns it.
- **Reuse:** the investigator's map, on the base commit.
- **Failure table** (for a shape, locks, timers or remote steps): each step of the flow, killed there, run twice at once, or timed out. A new mechanism gets its own test; a repeat names the test that covers it.
- **Tests:** the test list.
- **Done when:** `dev/test_list_check.py N origin/main HEAD` exits 0, the touched test files and `./check fast` pass, and the last commit is pushed.
- **Live check:** the scenario a sitting runs.
- **Scratch:** its subfolder, `<step>-<role>`.

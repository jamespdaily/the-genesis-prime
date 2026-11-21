"""The number of test slots the machine has, read by the hooks that share it.

`limit_test_runs.py` allows this many test runs at once and `limit_builders.py` this many
`implementer` agents at once, so raising the value raises both. A hook puts this file's folder on
`sys.path` before importing it, because `python3 -I` does not.
"""

TEST_SLOTS = 2

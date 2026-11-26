"""Lists the test files a step's change can affect.

    python3 -I dev/affected_tests.py BASE HEAD
    python3 -I dev/affected_tests.py BASE HEAD --run
"""

import sys


def main(arguments: list[str]) -> int:
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

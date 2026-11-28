"""Report the existing Gleam functions that each function added by a diff resembles.

Run: python3 -I dev/similar_functions.py BASE HEAD   (for example origin/main HEAD)

For each function that HEAD has in src, test or dev and BASE does not (same file and name), it
prints up to five functions of BASE, in any file: file:line, score and longest run. A new
function with no such match is not listed. It reads only git objects, writes nothing, and exits 0
when the refs resolve: it gates no merge, and a listed pair is a question for the author (say in
the hand-back why the pair stays, or call the existing function).

Comparison: bodies are lexed to tokens; string and number literals and the names of locals become
one token each, while constructors, keywords, called names and module paths stay. Functions of 25
to 600 tokens, not named `*_test`, not in generated modules, are candidates when they share at
least 8 six-token runs. Score is the share of tokens inside matching runs of 4 or more tokens
(2 * matched / (length a + length b)), rounded to two places as the measure printed it; run is
the longest matching run.

Thresholds, from the measure on issue #1499: score >= 0.50 and run >= 17 flagged all five known
copies of the last review rounds, and flagged 29% of 1,091 new functions in the last 60 merges, at
about 10 to 30 percent precision. The measure counted cross-file matches only, because
families of sibling functions among existing functions are its largest noise; for a function the
diff adds, a near-copy in its own file is a copy too, so same-file matches are listed. That noise
is why this reports and does not gate. The function itself is never its own match.

Run time: about 3 s on main (it reads and tokenises about 11.5k functions at each ref).
"""

import collections
import difflib
import io
import re
import subprocess
import sys
import tarfile

DIRS = ("src", "test", "dev")
MIN_TOKENS, MAX_TOKENS = 25, 600
SHARED_RUNS, RUN_LENGTH, BLOCK = 8, 6, 4
MIN_SCORE, MIN_LONGEST, SHOWN = 0.50, 17, 5
COMMON_RUN = 300

TOKEN = re.compile(
    r'"(?:\\.|[^"\\])*"|//[^\n]*|0x[0-9a-fA-F_]+|\d[\d_]*(?:\.\d*)?|[A-Za-z_][A-Za-z0-9_]*'
    r"|<>|\|>|->|<-|==|!=|<=|>=|\.\.|[^\s]"
)
KEYWORDS = {
    "fn", "let", "assert", "case", "if", "else", "use", "try", "pub", "as", "import", "type",
    "const", "todo", "panic", "opaque", "True", "False", "Nil",
}
FUNCTION = re.compile(r"^(pub )?fn ([a-z_0-9]+)", re.M)
GENERATED = ("//// Generated", "//// This module contains the code to run the sql")


def tokens(text):
    lexed = [t for t in TOKEN.findall(text) if not t.startswith("//")]
    out = []
    for i, t in enumerate(lexed):
        before = lexed[i - 1] if i else None
        after = lexed[i + 1] if i + 1 < len(lexed) else None
        if t[0] == '"':
            out.append("S")
        elif t[0].isdigit():
            out.append("N")
        elif t[0].isalpha() or t[0] == "_":
            kept = t in KEYWORDS or t[0].isupper() or before == "." or after in ("(", ".")
            out.append(t if kept else "I")
        else:
            out.append(t)
    return out


def functions_at(ref):
    """Candidate functions of a ref: (path, name, line, tokens)."""
    archive = subprocess.run(
        ["git", "archive", ref, *DIRS], capture_output=True, check=True
    ).stdout
    found = []
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar:
            if not (member.isfile() and member.name.endswith(".gleam")):
                continue
            text = tar.extractfile(member).read().decode()
            if any(marker in text[:200] for marker in GENERATED):
                continue
            for m in FUNCTION.finditer(text):
                before = text[: m.start()].rstrip("\n").rsplit("\n", 1)[-1]
                if before.startswith("@external") or m.group(2).endswith("_test"):
                    continue
                end = text.find("\n}\n", m.start())
                body = tokens(text[m.end() : (len(text) if end < 0 else end + 2)])
                if MIN_TOKENS <= len(body) <= MAX_TOKENS:
                    line = text.count("\n", 0, m.start()) + 1
                    found.append((member.name, m.group(2), line, body))
    return found


def runs(body):
    return {hash(tuple(body[j : j + RUN_LENGTH])) for j in range(len(body) - RUN_LENGTH + 1)}


def score(a, b):
    sizes = [m.size for m in difflib.SequenceMatcher(None, a, b, autojunk=False).get_matching_blocks()]
    matched = sum(size for size in sizes if size >= BLOCK)
    return 2 * matched / (len(a) + len(b)), max(sizes)


def main(base, head):
    old = functions_at(base)
    old_keys = {(path, name) for path, name, _, _ in old}
    added = [f for f in functions_at(head) if (f[0], f[1]) not in old_keys]
    index = collections.defaultdict(list)
    for i, (_, _, _, body) in enumerate(old):
        for h in runs(body):
            index[h].append(i)
    listed = 0
    for path, name, line, body in added:
        shared = collections.Counter()
        for h in runs(body):
            if len(index[h]) <= COMMON_RUN:
                shared.update(index[h])
        matches = []
        for i, count in shared.items():
            if count < SHARED_RUNS or (old[i][0], old[i][1]) == (path, name):
                continue
            ratio, longest = score(body, old[i][3])
            if round(ratio, 2) >= MIN_SCORE and longest >= MIN_LONGEST:
                matches.append((ratio, longest, old[i]))
        if not matches:
            continue
        listed += 1
        print(f"{path}:{line} {name}")
        for ratio, longest, (p, n, l, _) in sorted(matches, key=lambda m: -m[0])[:SHOWN]:
            print(f"    {ratio:.2f} run {longest:3d}  {p}:{l} {n}")
    print(f"# {len(added)} new functions, {listed} with a similar existing function", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: python3 -I dev/similar_functions.py BASE HEAD")
    main(sys.argv[1], sys.argv[2])

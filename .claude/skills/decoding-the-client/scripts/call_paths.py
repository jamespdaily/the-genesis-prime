"""The call chains from one client function to others, and the hops the walk cannot take.

    python3.13 -I call_paths.py <function> --to <target>... [--depth N] [--up]

Run with ~/.genesis-prime/env.sh read (WILDSTAR_CLIENT_EXE, and llvm-objdump as client_refs.py finds it).
Addresses are 0x hex. N is 1 to 8, default 4. The walk is over client_refs.py's reference index (llvm-objdump
over the whole executable, built per run in a few seconds), not Ghidra's references: Ghidra disassembled none
of the case blocks of HandleWorldMessage 0x1403ec6a0, so its references miss every flow through a world
message. A function is a .pdata function start, or a leaf function: an address in an executable section that
no .pdata function holds and that the index records a call or jmp to (a leaf has no .pdata entry; GetLocalizedText
0x14034bdd0 is one). A call from any of a function's .pdata ranges, chained chunks included, is a call from it.

Down (the default): every chain of at most N calls from <function> that ends at a target, each function at
most once in a chain; a chain ends at the first target it reaches. A call is a `call`, or a `jmp` to another
function's start or a leaf (a tail call). Chains are listed shortest first, then by address, each hop with
its call sites and, for a site in a chained chunk of the caller, that chunk. At most 50 chains are listed; a
longer list says so and stops. A leaf's own calls are not walked: nothing says where its code ends.
    unfollowed:  each `call [rip+x]` and `jmp [rip+x]` site (not an import's, which the index names) in a
                 walked function, nearest the start first, with its function and the pointer it goes
                 through; at most 50 lines. Its target is known only when it runs, so no chain goes through it.

--up: the same walk over callers, from <function> up to a target (which functions reach this one).
    reached only as data:  each walked function with no caller that is another function, with every other
                 reference the index holds to it: a pointer in a table, a `lea` of its address, a call from
                 itself, and a call or jmp from code outside .pdata ("called from code outside .pdata at
                 X"; such code is a leaf whose start the index does not give, so the walk stops there). At
                 most 50 lines.

Not in the index, so never listed and never followed: a call through a register (`call rax`), a virtual call
through a register's table (`call qword ptr [rcx+0x28]`) and a jump through a register or a table
(`jmp rax`, a switch). A conditional jump to a function start is not followed either (under --up it shows as
`jcc` among the references). A `no path` therefore says no chain of direct calls and tail calls exists
within N, not that the client has none; `unfollowed:` is not the whole list of calls the walk cannot see.

A function or target that is neither a .pdata function start nor a leaf is refused, naming it and why (inside
the function at X, in no executable section, or nothing calls or jumps to it).
Exit 0 when a chain is listed; 1 for `no path` or a refusal. Function names come from the fact file's records.
"""

import argparse
import os
import sys
from dataclasses import dataclass
from typing import Callable

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_facts  # noqa: E402
import check_support  # noqa: E402
import name_functions  # noqa: E402
from client_refs import RefIndex  # noqa: E402

DEFAULT_DEPTH = 4
MAX_DEPTH = 8
MAX_PATHS = 50
MAX_LINES = 50
MAX_SITES = 3


class Refused(Exception):
    """A request the script will not carry out; the message says why."""


@dataclass(frozen=True)
class Walk:
    """What a bounded walk found: the chains (each a list of function starts, the function first), whether
    more chains were left unlisted, and each function the walk expanded with its distance from the start."""

    paths: list[list[int]]
    truncated: bool
    expanded: dict[int, int]


def reach(neighbors: Callable[[int], list[int]], start: int, targets: set[int], depth: int) -> Walk:
    """Every chain of at most depth steps from start to a target through neighbors, a function a chain holds
    at most once, shortest first, then by address; a chain stops at the first target; at most MAX_PATHS."""
    distance = {start: 0}
    edges: dict[int, list[int]] = {}
    queue = [start]
    for at in queue:
        if distance[at] == depth or at in targets:
            continue
        edges[at] = sorted(set(neighbors(at)))
        for next_function in edges[at]:
            if next_function not in distance:
                distance[next_function] = distance[at] + 1
                queue.append(next_function)
    remaining = {target: 0 for target in targets if target in distance}
    backward: dict[int, list[int]] = {}
    for at, going in edges.items():
        for next_function in going:
            backward.setdefault(next_function, []).append(at)
    queue = list(remaining)
    for at in queue:
        for before in backward.get(at, []):
            if before not in remaining:
                remaining[before] = remaining[at] + 1
                queue.append(before)

    paths: list[list[int]] = []
    truncated = False

    def extend(chain: list[int], length: int) -> bool:
        """Adds the chains of exactly `length` steps that continue chain; False once MAX_PATHS is passed."""
        nonlocal truncated
        for next_function in edges.get(chain[-1], []):
            if next_function in chain:
                continue
            steps = len(chain)
            if next_function in targets:
                if steps == length:
                    if len(paths) == MAX_PATHS:
                        truncated = True
                        return False
                    paths.append(chain + [next_function])
            elif steps < length and steps + remaining.get(next_function, depth + 1) <= length:
                if not extend(chain + [next_function], length):
                    return False
        return True

    for length in range(1, depth + 1):
        if not extend([start], length):
            break
    return Walk(paths, truncated, {at: distance[at] for at in edges})


class Names:
    """Function names from the fact file's records, for the lines that print an address."""

    def __init__(self):
        self._names = dict(name_functions.name_pairs(check_facts.load(check_facts.FACT_FILE)))

    def label(self, address: int) -> str:
        name = self._names.get(address)
        return "0x%x %s" % (address, name) if name else "0x%x" % address


def is_leaf_address(index: RefIndex, address: int) -> bool:
    """Whether address is in an executable section and no .pdata function holds it."""
    section = index.pe.section_of(address)
    return section is not None and section.executable and index.pe.root_of(address) is None


def require_node(index: RefIndex, starts: set[int], address: int, role: str) -> None:
    """Raises Refused unless address is in starts (the .pdata function starts) or is a leaf: held by no .pdata
    function, in an executable section, and the target of a call or jmp the index records."""
    if address in starts:
        return
    inside = index.pe.root_of(address)
    if inside is not None:
        why = "it lies inside the function at 0x%x" % inside
    elif not is_leaf_address(index, address):
        why = "it is in no executable section"
    elif not any(r.kind in ("call", "jmp") for r in index.refs_to(address)):
        why = "no .pdata function holds it and the index records no call or jmp to it"
    else:
        return
    raise Refused("%s 0x%x is neither a function start nor a called leaf function: %s" % (role, address, why))


def direct_callers(index: RefIndex, at: int) -> list[int]:
    """The .pdata functions that call or tail-jump to at, itself left out."""
    return [caller for caller in index.callers(at) if caller != at]


def _sites(index: RefIndex, caller: int, callee: int) -> list:
    return [r for r in index.refs_to(callee) if r.kind in ("call", "jmp") and index.pe.root_of(r.source) == caller]


def hop_description(index: RefIndex, caller: int, callee: int) -> str:
    """The call sites of one hop, each with the chained chunk of the caller it lies in, when it is not
    the caller's first range."""
    ranges = index.pe.root_ranges(caller)
    shown = []
    for ref in _sites(index, caller, callee)[:MAX_SITES]:
        low, high = next(r for r in ranges if r[0] <= ref.source < r[1])
        in_chunk = "" if low == caller else ", in the chunk 0x%x-0x%x" % (low, high)
        shown.append("%s at 0x%x%s" % (ref.kind, ref.source, in_chunk))
    extra = len(_sites(index, caller, callee)) - MAX_SITES
    return "; ".join(shown) + ("; and %d more" % extra if extra > 0 else "")


def _print_paths(index: RefIndex, names: Names, walk: Walk, up: bool, out) -> None:
    for number, chain in enumerate(walk.paths, 1):
        print("path %d, %d %s:" % (number, len(chain) - 1, "step" if len(chain) == 2 else "steps"), file=out)
        print("  " + names.label(chain[0]), file=out)
        for before, after in zip(chain, chain[1:]):
            shown = hop_description(index, after, before) if up else hop_description(index, before, after)
            print("  %s %s  (%s)" % ("<-" if up else "->", names.label(after), shown), file=out)
    if walk.truncated:
        print("%d paths listed; more exist: narrow the targets or lower --depth" % MAX_PATHS, file=out)


def _print_unfollowed(index: RefIndex, names: Names, walk: Walk, on_paths: set[int], out) -> None:
    imports = index.pe.imports()
    found = []
    for function, distance in walk.expanded.items():
        for ref in index.sites_from(function, {"call-mem", "jmp-mem"}):
            if ref.target not in imports:
                found.append((function not in on_paths, distance, ref.source, function, ref))
    print(
        "unfollowed (%d sites through [rip+x]; not in the index, so not listed: `call qword ptr [rcx+0x28]`, `call rax`, `jmp reg`):"
        % len(found),
        file=out,
    )
    for _off_path, _distance, _site, function, ref in sorted(found, key=lambda f: f[:3])[:MAX_LINES]:
        print("  %s at 0x%x in %s, through 0x%x" % (ref.kind, ref.source, names.label(function), ref.target), file=out)
    if len(found) > MAX_LINES:
        print("  and %d more" % (len(found) - MAX_LINES), file=out)


def _other_references(index: RefIndex, function: int) -> list[str]:
    """What else refers to function, when no function calls it: each reference as a phrase."""
    phrases = []
    for ref in index.refs_to(function):
        if ref.kind in ("call", "jmp"):
            root = index.pe.root_of(ref.source)
            if root is None:
                phrases.append("called from code outside .pdata at 0x%x" % ref.source)
            else:
                phrases.append("%s from itself at 0x%x" % (ref.kind, ref.source))
        else:
            phrases.append("%s at 0x%x" % (ref.kind, ref.source))
    return phrases


def _print_data_only(index: RefIndex, names: Names, walk: Walk, out) -> None:
    found = []
    for function, distance in walk.expanded.items():
        if not direct_callers(index, function):
            found.append((distance, function, _other_references(index, function)))
    print("reached only as data or from code outside .pdata (walked functions with no calling function: %d):" % len(found), file=out)
    for _distance, function, phrases in sorted(found, key=lambda f: f[:2])[:MAX_LINES]:
        held = ", ".join(phrases[:MAX_SITES]) or "no reference at all"
        print("  %s: %s%s" % (names.label(function), held, "; and %d more" % (len(phrases) - MAX_SITES) if len(phrases) > MAX_SITES else ""), file=out)
    if len(found) > MAX_LINES:
        print("  and %d more" % (len(found) - MAX_LINES), file=out)


def run(index: RefIndex, function: int, targets: list[int], depth: int, up: bool, out) -> int:
    """Prints the walk's report; returns the exit status."""
    starts = set(index.pe.function_starts())
    for address, role in [(function, "function")] + [(t, "target") for t in targets]:
        require_node(index, starts, address, role)
    if function in targets:
        raise Refused("function 0x%x is also a target" % function)
    names = Names()
    if function not in starts and not up:
        print("0x%x has no .pdata entry: its own calls are not walked" % function, file=out)

    def callees(at: int) -> list[int]:
        return [
            r.target
            for r in index.sites_from(at, {"call", "jmp"})
            if r.target != at and (r.target in starts or is_leaf_address(index, r.target))
        ]

    walk = reach(lambda at: direct_callers(index, at) if up else callees(at), function, set(targets), depth)
    if walk.paths:
        _print_paths(index, names, walk, up, out)
    else:
        print("no path", file=out)
    if up:
        _print_data_only(index, names, walk, out)
    else:
        _print_unfollowed(index, names, walk, {f for chain in walk.paths for f in chain}, out)
    print("walked functions: %d, depth %d" % (len(walk.expanded), depth), file=out)
    return 0 if walk.paths else 1


def _address(word: str) -> int:
    try:
        return int(word, 16)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a 0x hex address" % word) from None


def _depth(word: str) -> int:
    try:
        depth = int(word)
    except ValueError:
        depth = 0
    if not 1 <= depth <= MAX_DEPTH:
        raise argparse.ArgumentTypeError("the depth is 1 to %d" % MAX_DEPTH)
    return depth


def main(argv: list[str], out=None) -> int:
    """Runs the command and returns the exit status."""
    out = out or sys.stdout
    parser = argparse.ArgumentParser(description="Call chains from one client function to others.")
    parser.add_argument("function", type=_address)
    parser.add_argument("--to", nargs="+", required=True, type=_address, metavar="target")
    parser.add_argument("--depth", type=_depth, default=DEFAULT_DEPTH)
    parser.add_argument("--up", action="store_true")
    arguments = parser.parse_args(argv)
    try:
        index = check_support.ref_index()
        return run(index, arguments.function, arguments.to, arguments.depth, arguments.up, out)
    except Refused as refused:
        print("call_paths: refused: %s" % refused, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

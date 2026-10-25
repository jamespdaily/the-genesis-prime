"""Reads MSVC x64 switch tables from the client's bytes, with no analyser.

Pattern: cmp IDX, N / ja DEFAULT, lea BASE, [image base], an optional byte
index table, mov R32, [BASE + IDX*4 + table], add R, BASE, jmp R. Anything
else is reported as not found, with the reason; nothing is guessed.
"""

import re
import subprocess
from dataclasses import dataclass

from client_pe import ClientPE
from client_refs import COMMENT_RE, LINE_RE, PREFIXES, objdump_path

WINDOW = 250  # instructions searched backwards from a jmp for each part of the pattern
MAX_CASES = 100_000
# FF /4 with a register operand (jmp r64), with or without a REX.B prefix: a
# function with no such bytes has no indirect jmp, so objdump is not run on it.
INDIRECT_JMP_BYTES = re.compile(rb"\xff[\xe0-\xe7]")


@dataclass(frozen=True)
class JumpTable:
    jmp: int
    found: bool
    reason: str | None
    case_count: int
    default: int | None
    targets: list[int]  # one per switch value, in order


_LEGACY = ["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"]
FAMILY: dict[str, str] = {}
for _r in _LEGACY:
    FAMILY[_r] = _r
    FAMILY["e" + _r[1:]] = _r
    FAMILY[_r[1:]] = _r
for _r, _l in (("rax", "a"), ("rcx", "c"), ("rdx", "d"), ("rbx", "b")):
    FAMILY[_l + "l"] = _r
    FAMILY[_l + "h"] = _r
for _r, _s in (("rsp", "sp"), ("rbp", "bp"), ("rsi", "si"), ("rdi", "di")):
    FAMILY[_s + "l"] = _r
for _n in range(8, 16):
    for _suffix in ("", "d", "w", "b"):
        FAMILY["r%d%s" % (_n, _suffix)] = "r%d" % _n
NO_WRITE = {"cmp", "test", "bt", "push", "jmp", "call", "ucomiss", "ucomisd", "comiss", "comisd", "nop"}
VOLATILE = {"rax", "rcx", "rdx", "r8", "r9", "r10", "r11"}


@dataclass(frozen=True)
class Instruction:
    address: int
    mnemonic: str
    operands: list[str]
    target: int | None  # the `# 0x...` comment objdump adds to rip-relative operands


class _NotFound(Exception):
    pass


def _parse_instruction(line: str) -> Instruction | None:
    m = LINE_RE.match(line)
    if not m:
        return None
    rest = m.group(2)
    comment = COMMENT_RE.search(rest)
    tokens = (rest[: comment.start()] if comment else rest).split(None, 1)
    while tokens and tokens[0] in PREFIXES and len(tokens) > 1:
        tokens = tokens[1].split(None, 1)
    if not tokens:
        return None
    operands = [o.strip() for o in tokens[1].split(",")] if len(tokens) > 1 else []
    operands = [re.sub(r"\s*<[^>]*>$", "", o) for o in operands]  # the <sym+0x..> after a branch target
    return Instruction(int(m.group(1), 16), tokens[0], operands, int(comment.group(1), 16) if comment else None)


def _disassemble(pe: ClientPE, low: int, high: int) -> list[Instruction]:
    command = [
        str(objdump_path()), "-d", "--no-show-raw-insn", "--x86-asm-syntax=intel",
        "--start-address=0x%x" % low, "--stop-address=0x%x" % high, str(pe.path),
    ]
    done = subprocess.run(command, capture_output=True, text=True, errors="replace", check=True)
    return [i for i in map(_parse_instruction, done.stdout.splitlines()) if i]


def _memory(operand: str):
    """'dword ptr [r8 + 4*rax + 0x4400]' -> (plain registers, (index, scale) or None, displacement)."""
    m = re.search(r"\[(.*)\]", operand)
    if not m:
        return None
    registers, scaled, displacement = [], None, 0
    for term in m.group(1).replace(" - ", " + -").split(" + "):
        term = term.strip()
        scale = re.match(r"^(\d+)\*(\w+)$", term)
        if scale:
            scaled = (scale.group(2), int(scale.group(1)))
        elif re.match(r"^-?0x[0-9a-f]+$", term):
            displacement += int(term, 16)
        elif re.match(r"^-?\d+$", term):
            displacement += int(term)
        elif term in FAMILY or term == "rip":
            registers.append(term)
        else:
            return None
    return registers, scaled, displacement


def _writes(instruction: Instruction, family: str) -> bool:
    ops = instruction.operands
    if ops and instruction.mnemonic not in NO_WRITE and FAMILY.get(ops[0]) == family:
        return True
    return instruction.mnemonic == "xchg" and len(ops) == 2 and FAMILY.get(ops[1]) == family


def _last_writer(code: list[Instruction], position: int, family: str) -> int | None:
    """The nearest instruction before position that writes the register family;
    None when a call that clobbers it, or the window's end, comes first."""
    for i in range(position - 1, max(0, position - WINDOW) - 1, -1):
        if _writes(code[i], family):
            return i
        if code[i].mnemonic == "call" and family in VOLATILE:
            return None
    return None


def _integer(text: str) -> int | None:
    try:
        return int(text, 0)
    except ValueError:
        return None


def _analyse(pe: ClientPE, code: list[Instruction], position: int) -> JumpTable:
    jmp = code[position]
    try:
        case_count, default, targets = _read_table(pe, code, position)
    except _NotFound as reason:
        return JumpTable(jmp.address, False, str(reason), 0, None, [])
    return JumpTable(jmp.address, True, None, case_count, default, targets)


def _read_table(pe: ClientPE, code: list[Instruction], position: int) -> tuple[int, int, list[int]]:
    register = FAMILY[code[position].operands[0]]
    add_at = _last_writer(code, position, register)
    if add_at is None:
        raise _NotFound("no write to jump register found")
    add = code[add_at]
    if add.mnemonic != "add" or len(add.operands) != 2 or add.operands[0] not in FAMILY or add.operands[1] not in FAMILY:
        raise _NotFound("jump register not produced by add reg,reg (%s %s)" % (add.mnemonic, ", ".join(add.operands)))
    first, second = FAMILY[add.operands[0]], FAMILY[add.operands[1]]
    load = None
    for loaded, base in ((first, second), (second, first)):
        load_at = _last_writer(code, add_at, loaded)
        if load_at is None:
            continue
        ins = code[load_at]
        if ins.mnemonic == "mov" and len(ins.operands) == 2 and ins.operands[0] in FAMILY and "dword ptr" in ins.operands[1]:
            memory = _memory(ins.operands[1])
            if memory and memory[1] and memory[1][1] == 4 and len(memory[0]) == 1 and FAMILY[memory[0][0]] == base:
                load = (load_at, base, FAMILY[memory[1][0]], memory[2])
                break
    if load is None:
        raise _NotFound("no `mov r32, dword ptr [BASE + IDX*4 + disp]` feeding the add")
    load_at, base, index, displacement = load
    base_at = _last_writer(code, load_at, base)
    if base_at is None:
        raise _NotFound("base register write not found")
    lea = code[base_at]
    if not (lea.mnemonic == "lea" and "[rip" in lea.operands[1] and lea.target == pe.image_base):
        raise _NotFound("base register is not loaded with the image base")
    table_rva = displacement & 0xFFFFFFFF

    bound_register, index_rva, stop = index, None, load_at
    byte_at = _last_writer(code, load_at, index)
    if byte_at is not None:
        ins = code[byte_at]
        if ins.mnemonic == "movzx" and len(ins.operands) == 2 and "byte ptr" in ins.operands[1]:
            memory = _memory(ins.operands[1])
            if memory and not memory[1] and len(memory[0]) == 2:
                families = [FAMILY[r] for r in memory[0]]
                if base in families and families.count(base) == 1 and _last_writer(code, byte_at, base) == base_at:
                    bound_register = families[1 - families.index(base)]
                    index_rva = memory[2] & 0xFFFFFFFF
                    stop = byte_at

    compare_at = None
    for i in range(stop - 1, max(0, stop - WINDOW) - 1, -1):
        ins = code[i]
        if ins.mnemonic == "cmp" and len(ins.operands) == 2 and FAMILY.get(ins.operands[0]) == bound_register \
                and _integer(ins.operands[1]) is not None:
            compare_at = i
            break
        if _writes(ins, bound_register):
            break
    if compare_at is None:
        raise _NotFound("no `cmp IDX, imm` found for the index register")
    bound = _integer(code[compare_at].operands[1])
    default = case_count = None
    for k in range(compare_at + 1, min(compare_at + 4, len(code))):
        ins = code[k]
        if ins.mnemonic in ("ja", "jae") and ins.operands:
            default = _integer(ins.operands[0])
            case_count = bound + 1 if ins.mnemonic == "ja" else bound
            break
        if ins.mnemonic.startswith("j"):
            break
    if default is None:
        raise _NotFound("cmp is not followed by ja/jae")
    if case_count <= 0 or case_count > MAX_CASES:
        raise _NotFound("implausible case count %d" % case_count)
    base_va = pe.image_base
    try:
        if index_rva is not None:
            indexes = pe.read(base_va + index_rva, case_count)
            entries = [base_va + _u32(pe, base_va + table_rva + 4 * k) for k in range(max(indexes) + 1)]
            targets = [entries[v] for v in indexes]
        else:
            targets = [base_va + _u32(pe, base_va + table_rva + 4 * k) for k in range(case_count)]
    except ValueError as error:
        raise _NotFound("table not readable: %s" % error) from error
    return case_count, default, targets


def _u32(pe: ClientPE, va: int) -> int:
    return int.from_bytes(pe.read(va, 4), "little")


def _merged(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for low, high in sorted(ranges):
        if out and out[-1][1] == low:
            out[-1] = (out[-1][0], high)
        else:
            out.append((low, high))
    return out


def read_function(pe: ClientPE, function_start: int) -> list[JumpTable]:
    """Every indirect `jmp REG64` in the function's .pdata ranges, read."""
    tables = []
    for low, high in _merged(pe.root_ranges(function_start)):
        if not INDIRECT_JMP_BYTES.search(pe.read(low, high - low)):
            continue
        code = _disassemble(pe, low, high)
        for position, ins in enumerate(code):
            if ins.mnemonic == "jmp" and len(ins.operands) == 1 and FAMILY.get(ins.operands[0]) == ins.operands[0]:
                tables.append(_analyse(pe, code, position))
    return sorted(tables, key=lambda t: t.jmp)

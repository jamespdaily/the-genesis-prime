"""Runs client code on Ghidra's p-code emulator.

The Windows x64 calling convention: the first four arguments go in RCX, RDX,
R8 and R9 when integers, or XMM0 to XMM3 when floats, by position. The result
is in RAX, or in XMM0 for a float. The emulator reads the client's own bytes
from the program, so code may read its constant tables.

Every run starts from a clean machine: the program's initialised sections and
a 64 KiB stack, with zeroed registers and nothing left by an earlier run.
Building one for the whole client costs about 20 ms, so nothing is restored or
cached between runs.

A run covers one function (it ends when the function returns) or an instruction
range (it ends when the counter reaches the stop address, or at a return from
the stack's start). Memory a request plants, and the blocks a heap_alloc
stand-in hands out, are mapped where nothing else is; a load or store outside
the mapped ranges fails the run as unmapped memory. Ghidra's own access
breakpoints are not used for this: its lookup finds a range only from the first
and last 4 KiB page of the range, so a gap of any size traps only at its ends
and the run goes on reading zeros. Instead each instruction's memory accesses
are checked before they run. An access at an address fixed in the instruction
(a memory varnode in its p-code) is checked before the instruction starts. An
instruction that loads or stores at a computed address is run one p-code op at
a time, and each of those addresses is checked before its op runs; the other
instructions run whole.
"""

import bisect
import struct
from dataclasses import dataclass, field

STACK_BASE = 0x7FFF_0000_0000
STACK_SIZE = 1 << 16
SENTINEL = 0x7FFF_FFFF_0000  # the return address pushed for the function; never mapped
HEAP_BASE = 0x6000_0000_0000  # the first block heap_alloc returns
HEAP_SIZE = 1 << 28
HEAP_ALIGNMENT = 16
DEFAULT_MAX_STEPS = 100_000
INTEGER_REGISTERS = ("RCX", "RDX", "R8", "R9")
FLOAT_REGISTERS = ("XMM0", "XMM1", "XMM2", "XMM3")
GENERAL_REGISTERS = (
    "RAX", "RBX", "RCX", "RDX", "RSI", "RDI", "RBP", "RSP",
    "R8", "R9", "R10", "R11", "R12", "R13", "R14", "R15",
)
VECTOR_REGISTERS = tuple("XMM%d" % i for i in range(16))
REGISTER_NAMES = tuple(name.lower() for name in (*GENERAL_REGISTERS, *VECTOR_REGISTERS))
STAND_IN_KINDS = ("heap_alloc", "heap_free", "return")
TOP_OF_ADDRESS_SPACE = (1 << 64) - 1


@dataclass(frozen=True)
class StandIn:
    """A Python answer for a call: heap_alloc (RCX bytes from the heap, pointer in RAX),
    heap_free (nothing) or return (RAX = value)."""

    kind: str
    value: int = 0


@dataclass(frozen=True)
class Plan:
    """What to run. `stop` is None to run a function until it returns. Register names are lower-case."""

    start: int
    stop: int | None = None
    args: tuple = ()
    registers: dict[str, int] = field(default_factory=dict)
    memory: tuple[tuple[int, bytes], ...] = ()  # (address, bytes) planted before the run
    read: tuple[tuple[int, int], ...] = ()  # (address, length) read after it
    stand_ins: dict[int, StandIn] = field(default_factory=dict)  # call target (function start or import slot) -> answer
    follow_calls: bool = False
    max_steps: int = DEFAULT_MAX_STEPS


@dataclass(frozen=True)
class Run:
    rax: int  # RAX after the run, unsigned 64-bit
    xmm0_low: int  # the low 64 bits of XMM0 after it; a float32 result is the low 32
    registers: dict[str, int]  # every general register and XMM0..15, lower-case names, unsigned
    read: list[bytes]  # one per entry of Plan.read
    steps: int
    stopped_at: int  # the counter when the run ended: the stop address, or SENTINEL after a return


class EmulationFailed(Exception):
    """The run called out, ran past max_steps, touched unmapped memory or could not be set up."""


def _signed(offset: int) -> int:
    return offset - (1 << 64) if offset >= 1 << 63 else offset


def import_name(function) -> str:
    """'dll!name' of an imported function, with the dll lower-case, as the PE import table names it."""
    dll, _, name = function.getName(True).partition("::")
    if name.startswith("Ordinal_"):
        name = "#" + name[len("Ordinal_"):]
    return "%s!%s" % (dll.lower(), name)


def _merged(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Inclusive (first, last) ranges sorted, with overlapping and touching ones joined."""
    joined: list[tuple[int, int]] = []
    for first, last in sorted(ranges):
        if joined and first <= joined[-1][1] + 1:
            joined[-1] = (joined[-1][0], max(joined[-1][1], last))
        else:
            joined.append((first, last))
    return joined


class _Machine:
    """One emulator for one run: the program's initialised memory is copied in, a
    stack is mapped, then the plan's memory is planted and mapped."""

    def __init__(self, program, plan: Plan):
        from jpype import JArray, JByte
        from ghidra.pcode.emu import PcodeEmulator

        self.program = program
        self.plan = plan
        self.listing = program.getListing()
        self.functions = program.getFunctionManager()
        language = program.getLanguage()
        self.space = program.getAddressFactory().getDefaultAddressSpace()
        self.emulator = PcodeEmulator(language)
        # instruction address -> (index -> LOAD/STORE op, has branches, fixed-address accesses (what, address, size))
        self._memory_ops: dict[int, tuple[dict, bool, list]] = {}
        self.state = self.emulator.getSharedState()
        mapped = [(STACK_BASE, STACK_BASE + STACK_SIZE - 1)]
        for block in program.getMemory().getBlocks():
            if block.isInitialized() and not block.isOverlay():
                data = JArray(JByte)(int(block.getSize()))
                block.getBytes(block.getStart(), data)
                self.state.setVar(block.getStart(), len(data), False, data)
                mapped.append((block.getStart().getOffset(), block.getEnd().getOffset()))
        self.state.setVar(self._address(STACK_BASE), STACK_SIZE, False, JArray(JByte)(STACK_SIZE))
        for address, data in plan.memory:
            if not data:
                continue
            if address + len(data) > TOP_OF_ADDRESS_SPACE + 1:
                raise EmulationFailed("memory planted at 0x%x runs past the end of the address space" % address)
            if address < HEAP_BASE + HEAP_SIZE and HEAP_BASE < address + len(data):
                raise EmulationFailed(
                    "memory planted at 0x%x overlaps the heap_alloc region 0x%x-0x%x"
                    % (address, HEAP_BASE, HEAP_BASE + HEAP_SIZE - 1)
                )
            self.state.setVar(self._address(address), len(data), False, JArray(JByte)(data))
            mapped.append((address, address + len(data) - 1))
        self.heap_next = HEAP_BASE
        self._set_mapped(mapped)
        self.thread = self.emulator.newThread("client")
        self.registers = {name.lower(): language.getRegister(name) for name in (*GENERAL_REGISTERS, *VECTOR_REGISTERS)}

    def _address(self, offset: int):
        return self.space.getAddress(_signed(offset))

    def _set_mapped(self, ranges: list[tuple[int, int]]) -> None:
        self.mapped = _merged(ranges)
        self._firsts = [first for first, _last in self.mapped]

    def _map(self, first: int, last: int) -> None:
        self._set_mapped([*self.mapped, (first, last)])

    def is_mapped(self, address: int, length: int) -> bool:
        at = bisect.bisect_right(self._firsts, address) - 1
        return at >= 0 and address + length - 1 <= self.mapped[at][1]

    def _check_access(self, op, pc: int) -> None:
        from ghidra.pcode.exec import PcodeExecutorStatePiece
        from ghidra.program.model.pcode import PcodeOp

        if op.getOpcode() == PcodeOp.LOAD:
            what, size = "load", op.getOutput().getSize()
        else:
            what, size = "store", op.getInput(2).getSize()
        raw = self.thread.getState().getVar(op.getInput(1), PcodeExecutorStatePiece.Reason.INSPECT)
        address = int.from_bytes(bytes(raw), "little")
        if not self.is_mapped(address, size):
            raise EmulationFailed(
                "the instruction at 0x%x made a %s of %d bytes at 0x%x, which is unmapped memory" % (pc, what, size, address)
            )

    def _check_fixed(self, accesses: list, pc: int) -> None:
        for what, address, size in accesses:
            if not self.is_mapped(address, size):
                raise EmulationFailed(
                    "the instruction at 0x%x made a %s of %d bytes at 0x%x, which is unmapped memory"
                    % (pc, what, size, address)
                )

    @staticmethod
    def _fixed_accesses(code) -> list:
        """(what, address, size) of each memory varnode the p-code reads or writes. A branch's or
        call's target is where control goes, not an access, so it is left out."""
        from ghidra.program.model.pcode import PcodeOp

        targets = (PcodeOp.BRANCH, PcodeOp.CBRANCH, PcodeOp.CALL)
        accesses = []
        for i in range(code.size()):
            op = code.get(i)
            for position in range(op.getNumInputs()):
                varnode = op.getInput(position)
                if varnode.isAddress() and not (position == 0 and op.getOpcode() in targets):
                    accesses.append(("load", varnode.getOffset() & TOP_OF_ADDRESS_SPACE, varnode.getSize()))
            output = op.getOutput()
            if output is not None and output.isAddress():
                accesses.append(("store", output.getOffset() & TOP_OF_ADDRESS_SPACE, output.getSize()))
        return accesses

    def _step(self, pc: int) -> None:
        """Runs the instruction at the counter. Its fixed-address accesses are checked first; one
        with a load or store at a computed address is run an op at a time, so that each address is
        checked before the op uses it."""
        from ghidra.program.model.pcode import PcodeOp

        known = self._memory_ops.get(pc)
        if known is not None:
            self._check_fixed(known[2], pc)
            if not known[0]:
                self.thread.stepInstruction()
                return
        self.thread.stepPcodeOp()  # begins the instruction: decodes it into a frame, runs no op
        frame = self.thread.getFrame()
        if known is None:
            code = frame.getCode()
            ops = {i: code.get(i) for i in range(code.size()) if code.get(i).getOpcode() in (PcodeOp.LOAD, PcodeOp.STORE)}
            branches = any(code.get(i).getOpcode() in (PcodeOp.BRANCH, PcodeOp.CBRANCH) for i in range(code.size()))
            known = self._memory_ops[pc] = (ops, branches, self._fixed_accesses(code))
            self._check_fixed(known[2], pc)
        ops, branches, _fixed = known
        last = max(ops, default=-1)
        while not frame.isFinished():
            index = frame.index()
            if index > last and not branches:
                break
            if index in ops:
                self._check_access(ops[index], pc)
            self.thread.stepPcodeOp()
        self.thread.finishInstruction()

    def set_register(self, name: str, value: int) -> None:
        from jpype import JArray, JByte

        register = self.registers[name.lower()]
        size = register.getNumBytes()
        self.thread.getState().setVar(register, JArray(JByte)((value & ((1 << 8 * size) - 1)).to_bytes(size, "little")))

    def register(self, name: str) -> int:
        from ghidra.pcode.exec import PcodeExecutorStatePiece

        raw = self.thread.getState().getVar(self.registers[name.lower()], PcodeExecutorStatePiece.Reason.INSPECT)
        return int.from_bytes(bytes(raw), "little")

    def _read(self, address: int, length: int) -> bytes:
        from ghidra.pcode.exec import PcodeExecutorStatePiece

        if length == 0:
            return b""
        if not self.is_mapped(address, length):
            raise EmulationFailed("cannot read %d bytes at 0x%x: the range is not all mapped memory" % (length, address))
        return bytes(self.state.getVar(self._address(address), length, False, PcodeExecutorStatePiece.Reason.INSPECT))

    def _write(self, address: int, data: bytes) -> None:
        from jpype import JArray, JByte

        self.state.setVar(self._address(address), len(data), False, JArray(JByte)(data))

    def _set_arguments(self) -> None:
        args = self.plan.args
        if len(args) > 4:
            raise EmulationFailed("only the four register arguments are supported, not %d" % len(args))
        for position, argument in enumerate(args):
            if isinstance(argument, float):
                self.set_register(FLOAT_REGISTERS[position], struct.unpack("<I", struct.pack("<f", argument))[0])
            else:
                self.set_register(INTEGER_REGISTERS[position], argument)

    def _call_target(self, instruction):
        """(target, import name or None) of a call, as far as the listing says: a direct call's
        function start, or the import slot of a call through the import table; (None, None) when
        the target is only known when the call runs."""
        flows = list(instruction.getFlows())
        if len(flows) != 1:
            return None, None
        flow = flows[0]
        if not flow.isExternalAddress():
            return flow.getOffset(), None
        function = self.functions.getFunctionAt(flow)
        name = import_name(function) if function is not None else "an import at %s" % flow
        for reference in instruction.getReferencesFrom():
            if not reference.isExternalReference() and reference.getReferenceType().isRead():
                return reference.getToAddress().getOffset(), name
        return None, name

    def _apply_stand_in(self, stand_in: StandIn) -> None:
        if stand_in.kind == "heap_alloc":
            size = self.register("rcx")
            pointer = self.heap_next
            end = pointer + max(size, 1)
            if end > HEAP_BASE + HEAP_SIZE:
                raise EmulationFailed("heap_alloc of %d bytes: the heap's %d bytes are used up" % (size, HEAP_SIZE))
            self._write(pointer, bytes(size))
            self._map(pointer, end - 1)
            self.heap_next = (end + HEAP_ALIGNMENT - 1) // HEAP_ALIGNMENT * HEAP_ALIGNMENT
            self.set_register("rax", pointer)
        elif stand_in.kind == "return":
            self.set_register("rax", stand_in.value)

    def _call(self, instruction, pc: int) -> bool:
        """True when a stand-in answered the call; False when the call is to be stepped into."""
        target, imported = self._call_target(instruction)
        stand_in = self.plan.stand_ins.get(target) if target is not None else None
        if stand_in is not None:
            self._apply_stand_in(stand_in)
            self.thread.overrideCounter(self._address(pc + instruction.getLength()))
            return True
        if imported is not None:
            raise EmulationFailed("calls the import %s at 0x%x, which has no stand-in" % (imported, pc))
        if not self.plan.follow_calls:
            raise EmulationFailed("calls out at 0x%x" % pc)
        return False

    def run(self) -> Run:
        from ghidra.pcode.exec import PcodeExecutionException

        plan = self.plan
        for name in REGISTER_NAMES:
            self.set_register(name, 0)
        self._set_arguments()
        for name, value in plan.registers.items():
            self.set_register(name, value)
        if "rsp" not in plan.registers:
            stack_pointer = STACK_BASE + STACK_SIZE - 0x108  # 16-byte aligned before the return address is pushed
            self._write(stack_pointer, SENTINEL.to_bytes(8, "little"))
            self.set_register("rsp", stack_pointer)
        self.thread.overrideContextWithDefault()
        self.thread.overrideCounter(self._address(plan.start))
        steps = 0
        while (pc := self.thread.getCounter().getOffset() & TOP_OF_ADDRESS_SPACE) not in (SENTINEL, plan.stop):
            if steps >= plan.max_steps:
                raise EmulationFailed("still running after %d steps at 0x%x" % (steps, pc))
            instruction = self.listing.getInstructionAt(self._address(pc))
            if instruction is None:
                raise EmulationFailed("no instruction of the program at 0x%x" % pc)
            if instruction.getFlowType().isCall() and self._call(instruction, pc):
                steps += 1
                continue
            try:
                self._step(pc)
            except PcodeExecutionException as error:
                raise EmulationFailed("stopped at 0x%x: %s" % (pc, error)) from error
            steps += 1
        registers = {name: self.register(name) for name in REGISTER_NAMES}
        read = [self._read(address, length) for address, length in plan.read]
        return Run(registers["rax"], registers["xmm0"] & ((1 << 64) - 1), registers, read, steps, pc)


def emulate(program, plan: Plan) -> Run:
    """Runs the plan on a machine built for it alone."""
    return _Machine(program, plan).run()

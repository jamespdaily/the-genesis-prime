"""Runs one client function on Ghidra's p-code emulator.

The Windows x64 calling convention: the first four arguments go in RCX, RDX,
R8 and R9 when integers, or XMM0 to XMM3 when floats, by position. The result
is in RAX, or in XMM0 for a float. The emulator reads the client's own bytes
from the program, so a function may read its constant tables.
"""

import struct
from dataclasses import dataclass

STACK_BASE = 0x7FFF_0000_0000
STACK_SIZE = 1 << 16
SENTINEL = 0x7FFF_FFFF_0000  # the return address pushed for the function; never mapped
INTEGER_REGISTERS = ("RCX", "RDX", "R8", "R9")
FLOAT_REGISTERS = ("XMM0", "XMM1", "XMM2", "XMM3")
TOP_OF_ADDRESS_SPACE = (1 << 64) - 1


@dataclass(frozen=True)
class Run:
    rax: int  # RAX after the function returns, unsigned 64-bit
    xmm0_low: int  # the low 64 bits of XMM0 after it returns; a float32 result is the low 32
    steps: int


class EmulationFailed(Exception):
    """The function called out, ran past max_steps or touched unmapped memory."""


def _signed(offset: int) -> int:
    return offset - (1 << 64) if offset >= 1 << 63 else offset


class _Machine:
    """One emulator per open program: the program's initialised memory is
    copied in once and a stack is mapped. Any load or store outside those
    ranges is trapped by an access breakpoint and fails the run."""

    def __init__(self, program):
        from jpype import JArray, JByte
        from ghidra.pcode.emu import PcodeEmulator, PcodeMachine
        from ghidra.program.model.address import AddressRangeImpl

        self.program = program
        self.listing = program.getListing()
        language = program.getLanguage()
        self.space = program.getAddressFactory().getDefaultAddressSpace()
        self.emulator = PcodeEmulator(language)
        self.state = self.emulator.getSharedState()
        mapped = [(STACK_BASE, STACK_BASE + STACK_SIZE - 1)]
        for block in program.getMemory().getBlocks():
            if block.isInitialized() and not block.isOverlay():
                data = JArray(JByte)(int(block.getSize()))
                block.getBytes(block.getStart(), data)
                self.state.setVar(block.getStart(), len(data), False, data)
                mapped.append((block.getStart().getOffset(), block.getEnd().getOffset()))
        self.state.setVar(self._address(STACK_BASE), STACK_SIZE, False, JArray(JByte)(STACK_SIZE))
        next_free = 0
        for first, last in sorted(mapped):
            if first > next_free:
                self.emulator.addAccessBreakpoint(
                    AddressRangeImpl(self._address(next_free), self._address(first - 1)), PcodeMachine.AccessKind.RW
                )
            next_free = max(next_free, last + 1)
        if next_free <= TOP_OF_ADDRESS_SPACE:
            self.emulator.addAccessBreakpoint(
                AddressRangeImpl(self._address(next_free), self._address(TOP_OF_ADDRESS_SPACE)), PcodeMachine.AccessKind.RW
            )
        self.thread = self.emulator.newThread("client")
        self.registers = {
            name: language.getRegister(name) for name in (*INTEGER_REGISTERS, *FLOAT_REGISTERS, "RAX", "RSP")
        }

    def _address(self, offset: int):
        return self.space.getAddress(_signed(offset))

    def set_register(self, name: str, value: int) -> None:
        from jpype import JArray, JByte

        register = self.registers[name]
        size = register.getNumBytes()
        self.thread.getState().setVar(register, JArray(JByte)((value & ((1 << 8 * size) - 1)).to_bytes(size, "little")))

    def register(self, name: str) -> int:
        from ghidra.pcode.exec import PcodeExecutorStatePiece

        raw = self.thread.getState().getVar(self.registers[name], PcodeExecutorStatePiece.Reason.INSPECT)
        return int.from_bytes(bytes(raw), "little")

    def run(self, function_start: int, args: list[int | float], max_steps: int) -> Run:
        from jpype import JArray, JByte
        from ghidra.pcode.exec import PcodeExecutionException

        if len(args) > 4:
            raise EmulationFailed("only the four register arguments are supported, not %d" % len(args))
        self.set_register("RAX", 0)
        for name in FLOAT_REGISTERS:
            self.set_register(name, 0)
        for position, argument in enumerate(args):
            if isinstance(argument, float):
                self.set_register(FLOAT_REGISTERS[position], struct.unpack("<I", struct.pack("<f", argument))[0])
            else:
                self.set_register(INTEGER_REGISTERS[position], argument)
        stack_pointer = STACK_BASE + STACK_SIZE - 0x108  # 16-byte aligned before the return address is pushed
        self.state.setVar(
            self._address(stack_pointer), 8, False, JArray(JByte)(SENTINEL.to_bytes(8, "little"))
        )
        self.set_register("RSP", stack_pointer)
        self.thread.overrideContextWithDefault()
        self.thread.overrideCounter(self._address(function_start))
        steps = 0
        while (pc := self.thread.getCounter().getOffset()) != SENTINEL:
            if steps >= max_steps:
                raise EmulationFailed("still running after %d steps at 0x%x" % (steps, pc))
            instruction = self.listing.getInstructionAt(self._address(pc))
            if instruction is None:
                raise EmulationFailed("no instruction of the program at 0x%x" % pc)
            if instruction.getFlowType().isCall():
                raise EmulationFailed("calls out at 0x%x" % pc)
            try:
                self.thread.stepInstruction()
            except PcodeExecutionException as error:
                raise EmulationFailed("stopped at 0x%x: %s" % (pc, error)) from error
            steps += 1
        return Run(self.register("RAX"), self.register("XMM0") & ((1 << 64) - 1), steps)


_machines: dict[int, tuple[object, _Machine]] = {}


def run_function(program, function_start: int, args: list[int | float], max_steps: int = 100_000) -> Run:
    """Each argument is an int (an integer register) or a float (an XMM
    register, passed as float32), by position."""
    held = _machines.get(id(program))
    if held is None or held[0] is not program:
        held = _machines[id(program)] = (program, _Machine(program))
    return held[1].run(function_start, args, max_steps)

"""Two client functions copied by hand from llvm-objdump's disassembly, one
instruction at a time. They are the expected values for the emulator tests:
written from the bytes, not from Ghidra, so the two readings are independent.
"""

import struct

M32 = 0xFFFF_FFFF
M64 = 0xFFFF_FFFF_FFFF_FFFF


def formula_a(rcx: int) -> int:
    """0x140882470: the index of the highest set bit of a 64-bit value
    (0xffffffff for 0). Returns EAX; RAX's upper half is zero."""
    rcx &= M64
    eax = 0x20  # 140882473 mov eax, 0x20
    edx = (rcx >> 32) & M32  # 140882470 mov rdx, rcx; 140882478 shr rdx, 0x20
    if edx != 0:  # 14088247c test edx, edx; je 0x1408824c4
        if edx & 0xFFFF0000 == 0:  # 140882480
            edx = (edx << 16) & M32
            eax = 0x10
        if edx & 0xFF000000 == 0:  # 140882490
            edx = (edx << 8) & M32
            eax -= 8
        if edx & 0xF0000000 == 0:  # 14088249e
            edx = (edx << 4) & M32
            eax -= 4
        if edx & 0xC0000000 == 0:  # 1408824ac
            edx = (edx << 2) & M32
            eax -= 2
        if not edx & 0x80000000:  # 1408824ba test edx, edx; js
            eax -= 1
        return (eax + 0x1F) & M32  # 1408824c0 add eax, 0x1f; ret
    ecx = rcx & M32
    if ecx == 0:  # 1408824c4 test ecx, ecx; mov edx, 0x1f; cmove eax, edx
        eax = 0x1F
    if ecx & 0xFFFF0000 == 0:  # 1408824ce
        ecx = (ecx << 16) & M32
        eax -= 0x10
    if ecx & 0xFF000000 == 0:  # 1408824dc
        ecx = (ecx << 8) & M32
        eax -= 8
    if ecx & 0xF0000000 == 0:  # 1408824ea
        ecx = (ecx << 4) & M32
        eax -= 4
    if ecx & 0xC0000000 == 0:  # 1408824f8
        ecx = (ecx << 2) & M32
        eax -= 2
    if not ecx & 0x80000000:  # 140882506 test ecx, ecx; js
        eax -= 1
    return (eax - 1) & M32  # 14088250c dec eax; ret


def f32(x: float) -> float:
    """Rounds to the nearest float32, as the SSE scalar instructions do."""
    return struct.unpack("<f", struct.pack("<f", x))[0]


def f32_bits(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", x))[0]


C_1_OVER_360 = f32(struct.unpack("<f", bytes.fromhex("610b363b"))[0])  # .rdata 0x140b79d14
C_PI_OVER_180 = f32(struct.unpack("<f", bytes.fromhex("35fa8e3c"))[0])  # .rdata 0x140b79d50


def cvttss2si(x: float) -> int:
    """Truncates toward zero to a signed 32-bit value; NaN and out-of-range
    give the 'integer indefinite' value 0x80000000."""
    if x != x or x >= 2**31 or x < -(2**31):
        return -(2**31)
    return int(x)


def formula_b(x: float) -> float:
    """0x1408296a0: (x - trunc(x / 360)) * pi / 180 in float32. It subtracts
    the whole turns, not 360 times the whole turns. Returns XMM0's low float."""
    x = f32(x)
    xmm1 = f32(x * C_1_OVER_360)  # 1408296a0 movaps; 1408296a3 mulss xmm1, [0x140b79d14]
    eax = cvttss2si(xmm1)  # 1408296ab cvttss2si eax, xmm1
    xmm2 = f32(float(eax))  # 1408296af movd; 1408296b3 cvtdq2ps
    xmm0 = f32(x - xmm2)  # 1408296b6 subss xmm0, xmm2
    return f32(xmm0 * C_PI_OVER_180)  # 1408296ba mulss xmm0, [0x140b79d50]; ret

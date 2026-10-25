"""Print the case address of jump table entries, read from WildStar64.exe on disk.

The in-game screen handler (0x1403EC6A0) dispatches through a jump table at
0x1403f1344 that Ghidra often cannot follow. Each entry is a 4-byte offset from
the image base 0x140000000, at index opcode - 0x61. By default this prints the
case for each opcode. With `--table`, it reads any such table of 4-byte offsets
instead, such as the prerequisite switch's at 0x1404a4848 (index type - 1), and
prints the case for each index. It reads the entries through the PE section table.

Usage: python3 -I jump_table.py <opcode hex> [<opcode hex> ...]
       python3 -I jump_table.py --table <table address hex> <index> [<index> ...]
Set WILDSTAR_EXE to read a different copy of WildStar64.exe.
"""
import os
import struct
import sys

IMAGE_BASE = 0x140000000
TABLE = 0x1403F1344
FIRST_OPCODE = 0x61
EXE = os.environ.get("WILDSTAR_EXE", os.path.expanduser("~/Coding/wildstar/client/WildStar/Client64/WildStar64.exe"))


def sections(data):
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    start = pe + 24 + optional_size
    for i in range(count):
        _, virtual_size, virtual_address, _, raw_address = struct.unpack_from("<8sIIII", data, start + i * 40)
        yield virtual_address, virtual_size, raw_address


def read_u32(data, address):
    rva = address - IMAGE_BASE
    for virtual_address, virtual_size, raw_address in sections(data):
        if virtual_address <= rva < virtual_address + virtual_size:
            return struct.unpack_from("<I", data, raw_address + rva - virtual_address)[0]
    raise ValueError(f"{address:#x} is not in any section")


def case_address(data, table, index):
    return IMAGE_BASE + read_u32(data, table + 4 * index)


def main():
    data = open(EXE, "rb").read()
    if sys.argv[1:2] == ["--table"]:
        table = int(sys.argv[2], 16)
        for arg in sys.argv[3:]:
            index = int(arg)
            print(f"{index} {case_address(data, table, index):#x}")
        return
    for arg in sys.argv[1:]:
        opcode = int(arg, 16)
        if opcode < FIRST_OPCODE:
            sys.exit(f"{opcode:#06x} is below the table's first opcode {FIRST_OPCODE:#06x}")
        print(f"{opcode:#06x} {case_address(data, TABLE, opcode - FIRST_OPCODE):#x}")


if __name__ == "__main__":
    main()

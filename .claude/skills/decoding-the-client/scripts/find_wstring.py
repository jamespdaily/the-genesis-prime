"""Print the virtual address and section of every UTF-16 and ASCII occurrence of each text in WildStar64.exe.

Usage: python3 -I find_wstring.py <text> [<text> ...]
Pass the addresses to DataRefs.java to find the code that uses them.
"""
import struct
import sys
from pathlib import Path

EXE = Path.home() / "Coding/wildstar/client/WildStar/Client64/WildStar64.exe"


def sections(b):
    pe = struct.unpack_from("<I", b, 0x3C)[0]
    count = struct.unpack_from("<H", b, pe + 6)[0]
    opt_size = struct.unpack_from("<H", b, pe + 20)[0]
    base = struct.unpack_from("<Q", b, pe + 48)[0]
    first = pe + 24 + opt_size
    for i in range(count):
        row = first + i * 40
        name = b[row:row + 8].rstrip(b"\0").decode()
        _, vaddr, raw_size, raw_off = struct.unpack_from("<IIII", b, row + 8)
        yield name, base + vaddr, raw_off, raw_size


def main():
    b = EXE.read_bytes()
    secs = list(sections(b))
    for text in sys.argv[1:]:
        for kind, needle in (("utf16", text.encode("utf-16-le")), ("ascii", text.encode())):
            at = b.find(needle)
            while at != -1:
                for name, va, raw_off, raw_size in secs:
                    if raw_off <= at < raw_off + raw_size:
                        print(f"{va + at - raw_off:x} {name} {kind} {text}")
                at = b.find(needle, at + 1)


if __name__ == "__main__":
    main()

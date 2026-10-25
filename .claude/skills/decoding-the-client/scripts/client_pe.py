"""Reads WildStar64.exe's PE tables straight from its bytes, with no analyser.

It is the independent evidence the query process is checked against:
sections, the .pdata function table, imports and base relocations.
"""

import bisect
import struct
from dataclasses import dataclass
from pathlib import Path

UNW_FLAG_CHAININFO = 0x4
SCN_EXECUTE = 0x20000000
DIR_IMPORT, DIR_EXCEPTION, DIR_BASERELOC, DIR_DELAY_IMPORT = 1, 3, 5, 13
REL_DIR64 = 10


@dataclass(frozen=True)
class Section:
    name: str
    va: int
    virtual_size: int
    raw_offset: int
    raw_size: int
    executable: bool

    @property
    def end(self) -> int:
        return self.va + self.virtual_size


@dataclass(frozen=True)
class RuntimeFunction:
    begin: int
    end: int
    unwind: int
    chained_to: int | None  # the parent entry's begin when UNW_FLAG_CHAININFO is set


class ClientPE:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        d = self.data
        if d[:2] != b"MZ":
            raise ValueError("not an MZ file")
        pe = struct.unpack_from("<I", d, 0x3C)[0]
        if d[pe : pe + 4] != b"PE\0\0":
            raise ValueError("no PE signature")
        count, optional_size = struct.unpack_from("<H", d, pe + 6)[0], struct.unpack_from("<H", d, pe + 20)[0]
        opt = pe + 24
        if struct.unpack_from("<H", d, opt)[0] != 0x20B:
            raise ValueError("not PE32+")
        self.image_base = struct.unpack_from("<Q", d, opt + 24)[0]
        directory_count = struct.unpack_from("<I", d, opt + 108)[0]
        self._directories = [struct.unpack_from("<II", d, opt + 112 + 8 * i) for i in range(directory_count)]
        self.sections = []
        at = opt + optional_size
        for _ in range(count):
            name = d[at : at + 8].rstrip(b"\0").decode("latin-1")
            virtual_size, rva, raw_size, raw_offset = struct.unpack_from("<IIII", d, at + 8)
            characteristics = struct.unpack_from("<I", d, at + 36)[0]
            self.sections.append(
                Section(name, self.image_base + rva, virtual_size, raw_offset, raw_size, bool(characteristics & SCN_EXECUTE))
            )
            at += 40
        self._runtime_functions: list[RuntimeFunction] | None = None
        self._begins: list[int] = []
        self._roots: dict[int, int] = {}
        self._by_begin: dict[int, RuntimeFunction] = {}
        self._root_ranges: dict[int, list[tuple[int, int]]] | None = None

    image_base: int
    sections: list[Section]

    def read(self, va: int, n: int) -> bytes:
        """n bytes at va, from the file; raises ValueError outside initialised data."""
        out = bytearray()
        while n > 0:
            s = next((s for s in self.sections if s.va <= va < s.va + s.raw_size), None)
            if s is None:
                raise ValueError("0x%x is not in initialised data" % va)
            take = min(n, s.va + s.raw_size - va)
            start = s.raw_offset + va - s.va
            out += self.data[start : start + take]
            va += take
            n -= take
        return bytes(out)

    def _u32(self, va: int) -> int:
        return struct.unpack("<I", self.read(va, 4))[0]

    def _u64(self, va: int) -> int:
        return struct.unpack("<Q", self.read(va, 8))[0]

    def _cstr(self, va: int) -> str:
        out = bytearray()
        while True:
            b = self.read(va + len(out), 1)
            if b == b"\0":
                return out.decode("latin-1")
            out += b

    def section_of(self, va: int) -> Section | None:
        for s in self.sections:
            if s.va <= va < s.end:
                return s
        return None

    def runtime_functions(self) -> list[RuntimeFunction]:
        """Every .pdata entry, sorted by begin."""
        if self._runtime_functions is None:
            rva, size = self._directories[DIR_EXCEPTION]
            raw = self.read(self.image_base + rva, size)
            entries = []
            for i in range(size // 12):
                begin, end, unwind = struct.unpack_from("<III", raw, 12 * i)
                if begin == 0 and end == 0 and unwind == 0:
                    continue
                unwind_at = self.image_base + (unwind & ~1)
                header = self.read(unwind_at, 4)
                parent = None
                if header[0] >> 3 & UNW_FLAG_CHAININFO:
                    parent = self.image_base + self._u32(unwind_at + 4 + 2 * ((header[2] + 1) & ~1))
                entries.append(RuntimeFunction(self.image_base + begin, self.image_base + end, unwind, parent))
            entries.sort(key=lambda e: e.begin)
            self._runtime_functions = entries
            self._begins = [e.begin for e in entries]
            self._by_begin = {e.begin: e for e in entries}
        return self._runtime_functions

    def function_starts(self) -> list[int]:
        """The begin of every entry that is not chained."""
        return [e.begin for e in self.runtime_functions() if e.chained_to is None]

    def _root_of_entry(self, entry: RuntimeFunction) -> int:
        self.runtime_functions()
        seen = []
        while entry.chained_to is not None and entry.begin not in self._roots:
            seen.append(entry.begin)
            parent = self._by_begin.get(entry.chained_to)
            if parent is None:
                self._roots[seen[-1]] = entry.chained_to
                break
            entry = parent
        root = self._roots.get(entry.begin, entry.begin)
        for begin in seen:
            self._roots[begin] = root
        return root

    def root_of(self, va: int) -> int | None:
        """The function start whose .pdata ranges, chained ones included, hold va."""
        entries = self.runtime_functions()
        i = bisect.bisect_right(self._begins, va) - 1
        if i < 0 or va >= entries[i].end:
            return None
        return self._root_of_entry(entries[i])

    def root_ranges(self, function_start: int) -> list[tuple[int, int]]:
        if self._root_ranges is None:
            ranges: dict[int, list[tuple[int, int]]] = {}
            for e in self.runtime_functions():
                ranges.setdefault(self._root_of_entry(e), []).append((e.begin, e.end))
            self._root_ranges = ranges
        return self._root_ranges.get(function_start, [])

    def imports(self) -> dict[int, str]:
        """IAT slot address -> 'dll!name' or 'dll!#ordinal', dll lower-case; delay imports included."""
        found: dict[int, str] = {}
        base = self.image_base

        def thunks(dll: str, name_table: int, address_table: int) -> None:
            i = 0
            while True:
                v = self._u64(base + name_table + 8 * i)
                if v == 0:
                    return
                name = "#%d" % (v & 0xFFFF) if v >> 63 else self._cstr(base + (v & 0x7FFFFFFF) + 2)
                found[base + address_table + 8 * i] = "%s!%s" % (dll.lower(), name)
                i += 1

        rva, _size = self._directories[DIR_IMPORT]
        at = base + rva if rva else 0
        while at:
            name_table, _stamp, _forwarder, name_rva, address_table = struct.unpack("<IIIII", self.read(at, 20))
            if name_table == 0 and name_rva == 0 and address_table == 0:
                break
            thunks(self._cstr(base + name_rva), name_table or address_table, address_table)
            at += 20
        rva, _size = self._directories[DIR_DELAY_IMPORT] if len(self._directories) > DIR_DELAY_IMPORT else (0, 0)
        at = base + rva if rva else 0
        while at:
            attributes, name_rva, _module, address_table, name_table, *_rest = struct.unpack("<IIIIIIII", self.read(at, 32))
            if attributes == 0 and name_rva == 0:
                break
            thunks(self._cstr(base + name_rva), name_table, address_table)
            at += 32
        return found

    def relocations(self) -> list[tuple[int, int]]:
        """(address, 8-byte value) for every DIR64 base relocation."""
        rva, size = self._directories[DIR_BASERELOC]
        raw = self.read(self.image_base + rva, size)
        out = []
        at = 0
        while at + 8 <= len(raw):
            page, block = struct.unpack_from("<II", raw, at)
            if block < 8:
                break
            for k in range((block - 8) // 2):
                word = struct.unpack_from("<H", raw, at + 8 + 2 * k)[0]
                if word >> 12 == REL_DIR64:
                    address = self.image_base + page + (word & 0xFFF)
                    out.append((address, self._u64(address)))
            at += block
        return out

    def pointer_only_functions(self) -> list[int]:
        """Targets of relocated pointers into .text that lie outside every .pdata range."""
        text = next(s for s in self.sections if s.name == ".text")
        targets = {v for _a, v in self.relocations() if text.va <= v < text.end and self.root_of(v) is None}
        return sorted(targets)

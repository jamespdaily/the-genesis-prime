"""Extracts the client's game tables (every DB/*.tbl in ClientData) into the
folder $GENESIS_TABLE_DIR, once per machine, as build_patched_otp.sh builds
the patched OTP once. The server reads the plain files; nothing else reads the
client's archive.

Usage: python3.13 -I setup_check/extract_tables.py

Settings (env.sh, GENESIS_HOME/env.sh): WILDSTAR_CLIENT_EXE names the client,
whose Patch folder sits beside Client64 and holds ClientData.index and
ClientData.archive; GENESIS_TABLE_DIR names the folder to fill (default
$GENESIS_HOME/tables, set by setup_check/environment.sh).

Every file is checked against the SHA-1 the index holds for it before it is
written, and a file that fails is refused by name: nothing is left in the
folder from that run.

The archive formats. The fact file's "archive_index.header" gives the PACK
container and the AIDX header; the rest was read from the data, and is checked
by the index's SHA-1 of every stored block, which all 384 tables meet (the
evidence is the data and those hashes; the client's code for it is unread).
All numbers are little-endian.
  - PACK container (ClientData.index and ClientData.archive alike): the header
    0x230 bytes, the block table at the offset in the header (16-byte entries:
    u64 file offset, u64 size), the block count at 0x220, the root block's
    index at 0x228 (fact file, archive_index.header).
  - Index root block 1 of ClientData.index (the AIDX header's fourth u32, fact
    file) is a directory node; a directory node is: u32 directory count, u32
    file count, then the directories (u32 name offset, u32 block index of its
    directory node), then the files, then the names, zero-terminated UTF-8,
    each offset counted from the start of the names. A file is 56 bytes: u32
    name offset, u32 flags, u64 write time (Windows FILETIME), u64 size, u64
    stored size, 20 bytes SHA-1, u32 whose use is unread. Flags: 1 the file is
    stored as is (stored size == size), 5 the file is LZMA-compressed. The DB
    directory (block 0x1df2 in this index) holds 384 files, 26 with flag 1 and
    358 with flag 5.
  - ClientData.archive's root block 1 is the AARC header, 16 bytes: u32
    signature 0x41415243 (the bytes 'CRAA'), u32 version 2, u32 entry count,
    u32 index of the block that holds the entries. The entries are 32 bytes
    each: u32 block index, 20 bytes SHA-1, u64 size of that block. A file is
    found by its SHA-1, and the block's size equals the index's stored size.
  - The SHA-1 in the index is the SHA-1 of the stored block (the bytes as the
    archive holds them: compressed for flag 5), not of the file's content.
  - An LZMA file (flag 5) is an LZMA stream with a 5-byte header (the
    properties byte lc + 9 * (lp + 5 * pb), then the u32 dictionary size) and
    no end marker; the index's size says where it stops.
"""

import hashlib
import lzma
import os
import shutil
import struct
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Callable, Mapping

TABLE_DIRECTORY = "DB"
PACK_SIGNATURE = 0x5041434B  # fact file, archive_index.header
AIDX_SIGNATURE = 0x41494458
AARC_SIGNATURE = 0x41415243
DIRECTORY_ENTRY = 8
FILE_ENTRY = 56
ARCHIVE_ENTRY = 32
FLAG_STORED = 1
FLAG_LZMA = 5
EXPECTED_TABLES = 384  # fact file, game_tables.ClientData


class Corrupt(Exception):
    """A file of the archive that does not match the index; `name` is its
    path in the archive."""

    def __init__(self, name: str, reason: str):
        super().__init__("%s: %s" % (name, reason))
        self.name = name
        self.reason = reason


@dataclass(frozen=True)
class IndexedFile:
    """A file the index lists."""

    path: str  # inside the archive, with '/' between folders: DB/Creature2.tbl
    flags: int
    size: int
    stored_size: int
    sha1: bytes  # of the stored block


def _unpack(fmt: str, data: bytes, at: int, name: str) -> tuple:
    try:
        return struct.unpack_from(fmt, data, at)
    except struct.error:
        raise Corrupt(name, "the bytes end before offset %#x" % at) from None


def _block_table(header: bytes, read: Callable[[int, int], bytes], name: str) -> list[tuple[int, int]]:
    """The (offset, size) of every block of a PACK container, from its header
    and a function that reads bytes at an offset."""
    signature, version = _unpack("<II", header, 0, name)
    if signature != PACK_SIGNATURE or version != 1:
        raise Corrupt(name, "not a PACK container (signature and version 1)")
    (table_offset,) = _unpack("<Q", header, 0x218, name)
    (count,) = _unpack("<I", header, 0x220, name)
    table = read(table_offset, 16 * count)
    if len(table) != 16 * count:
        raise Corrupt(name, "the block table ends early")
    return [struct.unpack_from("<QQ", table, 16 * i) for i in range(count)]


def read_index(index: bytes) -> list[IndexedFile]:
    """Every file in the index's directory tree."""
    name = "ClientData.index"
    blocks = _block_table(index, lambda offset, size: index[offset : offset + size], name)

    def block(number: int) -> bytes:
        if number == 0 or number >= len(blocks):
            raise Corrupt(name, "block %d is not readable" % number)
        offset, size = blocks[number]
        data = index[offset : offset + size]
        if len(data) != size:
            raise Corrupt(name, "block %d ends early" % number)
        return data

    (root,) = _unpack("<I", index, 0x228, name)
    signature, version, _build, directory_block = _unpack("<IIII", block(root), 0, name)
    if signature != AIDX_SIGNATURE or version != 1:
        raise Corrupt(name, "the root block is not an AIDX header")
    files: list[IndexedFile] = []
    pending = [(directory_block, "")]
    while pending:
        number, prefix = pending.pop()
        node = block(number)
        directories, file_count = _unpack("<II", node, 0, name)
        names = 8 + DIRECTORY_ENTRY * directories + FILE_ENTRY * file_count

        def text(offset: int) -> str:
            end = node.index(b"\0", names + offset)
            return node[names + offset : end].decode()

        for k in range(directories):
            text_offset, child = _unpack("<II", node, 8 + DIRECTORY_ENTRY * k, name)
            pending.append((child, prefix + text(text_offset) + "/"))
        for k in range(file_count):
            at = 8 + DIRECTORY_ENTRY * directories + FILE_ENTRY * k
            text_offset, flags, _written, size, stored_size = _unpack("<IIQQQ", node, at, name)
            files.append(IndexedFile(prefix + text(text_offset), flags, size, stored_size, node[at + 32 : at + 52]))
    return files


def tables_of(files: list[IndexedFile]) -> list[IndexedFile]:
    """The files directly in the DB directory, ending in .tbl."""
    return sorted(
        (f for f in files if f.path.startswith(TABLE_DIRECTORY + "/") and f.path.count("/") == 1 and f.path.endswith(".tbl")),
        key=lambda f: f.path,
    )


def _content(file: IndexedFile, stored: bytes) -> bytes:
    """The file's content from its stored block."""
    if file.flags == FLAG_STORED:
        if len(stored) != file.size:
            raise Corrupt(file.path, "stored as is, %d bytes, the index says %d" % (len(stored), file.size))
        return stored
    if file.flags != FLAG_LZMA:
        raise Corrupt(file.path, "flags %d are neither stored (1) nor LZMA (5)" % file.flags)
    if len(stored) < 5 or stored[0] >= 9 * 5 * 5:
        raise Corrupt(file.path, "the LZMA header is not valid")
    properties = stored[0]
    (dictionary,) = struct.unpack_from("<I", stored, 1)
    lc, rest = properties % 9, properties // 9
    lp, pb = rest % 5, rest // 5
    decoder = lzma.LZMADecompressor(
        format=lzma.FORMAT_RAW,
        filters=[{"id": lzma.FILTER_LZMA1, "dict_size": max(dictionary, 4096), "lc": lc, "lp": lp, "pb": pb}],
    )
    try:
        content = decoder.decompress(stored[5:], max_length=file.size)
    except lzma.LZMAError as failure:
        raise Corrupt(file.path, "the LZMA stream is not valid: %s" % failure) from None
    if len(content) != file.size:
        raise Corrupt(file.path, "decodes to %d bytes, the index says %d" % (len(content), file.size))
    return content


def _archive_entries(archive: BinaryIO, name: str) -> tuple[list[tuple[int, int]], dict[bytes, tuple[int, int]]]:
    """The archive's block table and its AARC entries, by SHA-1."""

    def read(offset: int, size: int) -> bytes:
        archive.seek(offset)
        return archive.read(size)

    header = read(0, 0x230)
    blocks = _block_table(header, read, name)

    def block(number: int) -> bytes:
        if number == 0 or number >= len(blocks):
            raise Corrupt(name, "block %d is not readable" % number)
        return read(*blocks[number])

    (root,) = _unpack("<I", header, 0x228, name)
    signature, version, count, entries_block = _unpack("<IIII", block(root), 0, name)
    if signature != AARC_SIGNATURE or version != 2:
        raise Corrupt(name, "the root block is not an AARC header, version 2")
    listing = block(entries_block)
    if len(listing) < ARCHIVE_ENTRY * count:
        raise Corrupt(name, "the entries block ends early")
    entries = {}
    for k in range(count):
        number, sha1, size = struct.unpack_from("<I20sQ", listing, ARCHIVE_ENTRY * k)
        entries[sha1] = (number, size)
    return blocks, entries


def extract(patch_folder: Path, destination: Path) -> list[str]:
    """Writes every DB/*.tbl of patch_folder's ClientData into destination,
    each checked against the index's SHA-1, and returns their file names.
    Raises Corrupt naming the file whose block does not match; the
    destination is then left as it was."""
    tables = tables_of(read_index((patch_folder / "ClientData.index").read_bytes()))
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".extracting-", dir=destination.parent))
    try:
        with open(patch_folder / "ClientData.archive", "rb") as archive:
            blocks, entries = _archive_entries(archive, "ClientData.archive")
            for file in tables:
                if file.sha1 not in entries:
                    raise Corrupt(file.path, "the archive holds no block with the index's SHA-1")
                number, size = entries[file.sha1]
                offset, block_size = blocks[number]
                if size != file.stored_size or block_size != size:
                    raise Corrupt(file.path, "the archive's block is %d bytes, the index says %d" % (block_size, file.stored_size))
                archive.seek(offset)
                stored = archive.read(size)
                if hashlib.sha1(stored).digest() != file.sha1:
                    raise Corrupt(file.path, "the block's SHA-1 is not the index's")
                (staging / file.path.split("/", 1)[1]).write_bytes(_content(file, stored))
        destination.mkdir(exist_ok=True)
        names = sorted(path.name for path in staging.iterdir())
        for name in names:
            os.replace(staging / name, destination / name)
        return names
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def table_folder(env: Mapping[str, str]) -> Path:
    """GENESIS_TABLE_DIR, or $GENESIS_HOME/tables (GENESIS_HOME defaulting to
    ~/.genesis-prime)."""
    if env.get("GENESIS_TABLE_DIR"):
        return Path(env["GENESIS_TABLE_DIR"])
    home = env.get("GENESIS_HOME") or os.path.join(env.get("HOME") or os.path.expanduser("~"), ".genesis-prime")
    return Path(home) / "tables"


def patch_folder(env: Mapping[str, str]) -> Path:
    """The Patch folder beside Client64, from WILDSTAR_CLIENT_EXE."""
    return Path(env["WILDSTAR_CLIENT_EXE"]).parent.parent / "Patch"


def main() -> int:
    if "WILDSTAR_CLIENT_EXE" not in os.environ:
        print("WILDSTAR_CLIENT_EXE is not set: add it to env.sh (GENESIS_HOME/env.sh), as ./setup-check says")
        return 1
    destination = table_folder(os.environ)
    started = time.monotonic()
    try:
        names = extract(patch_folder(os.environ), destination)
    except Corrupt as refused:
        print("refused %s: %s" % (refused.name, refused.reason))
        return 1
    print("extracted %d tables into %s in %.1f seconds" % (len(names), destination, time.monotonic() - started))
    if len(names) != EXPECTED_TABLES:
        print("the client's index lists %d tables, the fact file says %d" % (len(names), EXPECTED_TABLES))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

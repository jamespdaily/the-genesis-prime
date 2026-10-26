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
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

TABLE_DIRECTORY = "DB"
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


def read_index(index: bytes) -> list[IndexedFile]:
    """Every file in the index's directory tree."""
    raise NotImplementedError


def tables_of(files: list[IndexedFile]) -> list[IndexedFile]:
    """The files directly in the DB directory, ending in .tbl."""
    raise NotImplementedError


def extract(patch_folder: Path, destination: Path) -> list[str]:
    """Writes every DB/*.tbl of patch_folder's ClientData into destination,
    each checked against the index's SHA-1, and returns their file names.
    Raises Corrupt naming the file whose block does not match; the
    destination is then left as it was."""
    raise NotImplementedError


def table_folder(env: Mapping[str, str]) -> Path:
    """GENESIS_TABLE_DIR, or $GENESIS_HOME/tables (GENESIS_HOME defaulting to
    ~/.genesis-prime)."""
    raise NotImplementedError


def patch_folder(env: Mapping[str, str]) -> Path:
    """The Patch folder beside Client64, from WILDSTAR_CLIENT_EXE."""
    raise NotImplementedError


def main() -> int:
    raise NotImplementedError


if __name__ == "__main__":
    sys.exit(main())

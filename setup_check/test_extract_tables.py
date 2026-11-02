"""extract_tables: every DB/*.tbl of the client's ClientData is written out, each
checked against the index's SHA-1, and a block that does not match is refused
by name.

The planted tests build a small index and archive in the layouts the script's
docstring gives (the PACK container from the fact file's "archive_index.header",
the directory node, the file entry, the AARC entries and the LZMA stream read
from the client's data), so no test touches the real client.

Expected values and their sources:
- the SHA-1 in the index is the SHA-1 of the stored block (the data checked: all
  384 tables of the client's index meet it), so a planted index holds the
  SHA-1 of the bytes the planted archive stores.
- 384 tables, each starting with the signature 'LBTD' (0x4454424C): the fact
  file's "game_tables.ClientData" and "game_table.file". A file stored as is
  has flag 1, an LZMA-compressed one flag 5, read from the client's index.
- all or nothing: a run that fails leaves the folder exactly
  as it was, and one that succeeds replaces it whole, so a file of an earlier
  run that the index no longer lists is gone. The swap moves the old folder to
  `.old` beside it, then the staged set in; a crash between the two renames
  leaves `.old` and no folder, which the next run moves back (rolls back), and a
  crash after them leaves a folder and `.old`, which it removes (the folder was
  verified before the swap). These rules are this script's own design;
  the 384 is the fact file's.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import hashlib
import lzma
import os
import shutil
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import extract_tables  # noqa: E402

PACK_SIGNATURE = 0x5041434B
AIDX_SIGNATURE = 0x41494458
AARC_SIGNATURE = 0x41415243
FILETIME = 0x01D44ED4E4CFCB54  # a write time read from the client's index


def pack(blocks: list[bytes], root: int) -> bytes:
    """A PACK container: the 0x230-byte header, the block table at 0x240 and
    the blocks after it, each at a multiple of 16. Block 0 is empty."""
    table_offset = 0x240
    position = table_offset + 16 * (len(blocks) + 1)
    entries = [struct.pack("<QQ", 0, 0)]
    body = bytearray()
    for block in blocks:
        padding = -position % 16
        body += b"\0" * padding
        position += padding
        entries.append(struct.pack("<QQ", position, len(block)))
        body += block
        position += len(block)
    header = struct.pack("<II", PACK_SIGNATURE, 1) + b"\0" * 512
    header += struct.pack("<QQQ", position, 0, table_offset)
    header += struct.pack("<IIII", len(blocks) + 1, 0, root, 0)
    assert len(header) == 0x230
    return header + b"\0" * (table_offset - 0x230) + b"".join(entries) + bytes(body)


def directory(directories: list[tuple[str, int]], files: list[tuple[str, int, int, int, bytes]]) -> bytes:
    """A directory node: directories as (name, block index), files as (name,
    flags, size, stored size, SHA-1 of the stored block)."""
    names = b""
    offsets = {}
    for name in [d[0] for d in directories] + [f[0] for f in files]:
        offsets[name] = len(names)
        names += name.encode() + b"\0"
    node = struct.pack("<II", len(directories), len(files))
    for name, block in directories:
        node += struct.pack("<II", offsets[name], block)
    for name, flags, size, stored_size, sha1 in files:
        node += struct.pack("<IIQQQ", offsets[name], flags, FILETIME, size, stored_size) + sha1 + struct.pack("<I", 0)
    return node + names


def lzma_block(content: bytes) -> bytes:
    """The stored form of an LZMA file: the properties byte (lc 3, lp 0, pb 2),
    the u32 dictionary size, then the raw LZMA stream."""
    lc, lp, pb, dictionary = 3, 0, 2, 1 << 20
    compressor = lzma.LZMACompressor(
        format=lzma.FORMAT_RAW,
        filters=[{"id": lzma.FILTER_LZMA1, "dict_size": dictionary, "lc": lc, "lp": lp, "pb": pb}],
    )
    stream = compressor.compress(content) + compressor.flush()
    return bytes([lc + 9 * (lp + 5 * pb)]) + struct.pack("<I", dictionary) + stream


class Planted:
    """A planted client: an index and an archive in a Patch folder, with the
    files given as (path, content, flags), and the build the index's AIDX
    header carries (the client's own, 16042, unless given)."""

    def __init__(self, root: Path, files: list[tuple[str, bytes, int]], build: int = 16042):
        self.patch = root / "Patch"
        self.patch.mkdir()
        self.stored: dict[str, bytes] = {}
        entries: dict[str, list[tuple[str, int, int, int, bytes]]] = {}
        archive_blocks: list[tuple[bytes, bytes]] = []
        for path, content, flags in files:
            block = content if flags == 1 else lzma_block(content)
            self.stored[path] = block
            sha1 = hashlib.sha1(block).digest()
            archive_blocks.append((sha1, block))
            folder, name = path.rsplit("/", 1)
            entries.setdefault(folder, []).append((name, flags, len(content), len(block), sha1))
        folders = sorted(entries)
        nodes = [directory([(folder, 3 + i) for i, folder in enumerate(folders)], [])]
        nodes += [directory([], entries[folder]) for folder in folders]
        aidx = struct.pack("<IIII", AIDX_SIGNATURE, 1, build, 1)
        (self.patch / "ClientData.index").write_bytes(pack([nodes[0], aidx] + nodes[1:], root=2))
        aarc = struct.pack("<IIII", AARC_SIGNATURE, 2, len(archive_blocks), 2)
        listing = b"".join(
            struct.pack("<I", 3 + i) + sha1 + struct.pack("<Q", len(block))
            for i, (sha1, block) in enumerate(archive_blocks)
        )
        (self.patch / "ClientData.archive").write_bytes(pack([aarc, listing] + [b for _, b in archive_blocks], root=1))

    def corrupt(self, path: str) -> None:
        """Flips one byte of the stored block of a file in the archive."""
        archive = bytearray((self.patch / "ClientData.archive").read_bytes())
        block = self.stored[path]
        at = bytes(archive).index(block)
        archive[at + len(block) // 2] ^= 0xFF
        (self.patch / "ClientData.archive").write_bytes(bytes(archive))


def table_content(label: str) -> bytes:
    """Bytes that begin as a game table file does (the signature 'LBTD')."""
    return b"LBTD" + label.encode() * 40


class WorkInFolderCase(unittest.TestCase):
    def setUp(self):
        self._folder = tempfile.TemporaryDirectory()
        self.addCleanup(self._folder.cleanup)
        self.root = Path(self._folder.name)
        self.destination = self.root / "tables"


class ExtractionTest(WorkInFolderCase):
    def test_a_stored_and_an_lzma_table_are_written_with_the_content_the_index_describes(self):
        alpha, beta = table_content("alpha"), table_content("beta")
        planted = Planted(self.root, [("DB/Alpha.tbl", alpha, 1), ("DB/Beta.tbl", beta, 5)])
        names = extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(names, ["Alpha.tbl", "Beta.tbl"])
        self.assertEqual((self.destination / "Alpha.tbl").read_bytes(), alpha)
        self.assertEqual((self.destination / "Beta.tbl").read_bytes(), beta)

    def test_a_block_that_does_not_match_the_index_sha1_is_refused_by_name_and_nothing_is_left(self):
        planted = Planted(
            self.root,
            [("DB/Alpha.tbl", table_content("alpha"), 5), ("DB/Beta.tbl", table_content("beta"), 5)],
        )
        planted.corrupt("DB/Beta.tbl")
        with self.assertRaises(extract_tables.Corrupt) as refused:
            extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(refused.exception.name, "DB/Beta.tbl")
        self.assertIn("DB/Beta.tbl", str(refused.exception))
        leftovers = list(self.destination.iterdir()) if self.destination.exists() else []
        self.assertEqual(leftovers, [], "a refused run leaves nothing in the folder")


def write_folder(folder: Path, files: dict[str, bytes]) -> None:
    folder.mkdir(parents=True)
    for name, content in files.items():
        (folder / name).write_bytes(content)


def snapshot(folder: Path) -> dict[str, bytes] | None:
    """The names and bytes of a folder's files, or None when it is not there."""
    if not folder.exists():
        return None
    return {path.name: path.read_bytes() for path in sorted(folder.iterdir())}


OLD_FILES = {"Alpha.tbl": b"LBTD an earlier alpha", "Stale.tbl": b"LBTD a table the index no longer lists"}


class AllOrNothingTest(WorkInFolderCase):
    """Extraction is all or nothing."""

    def assert_nothing_beside_the_folder(self):
        """No staging or old folder is left beside the destination, so the next
        run has nothing to recover."""
        left = sorted(path.name for path in self.root.iterdir() if path.name not in ("Patch", "tables"))
        self.assertEqual(left, [])

    def planted_three(self) -> "Planted":
        return Planted(
            self.root,
            [(f"DB/{name}.tbl", table_content(name.lower()), 5) for name in ("Alpha", "Beta", "Gamma")],
        )

    def test_a_refused_run_leaves_an_existing_folder_exactly_as_it_was(self):
        for corrupt in ("DB/Alpha.tbl", "DB/Gamma.tbl"):  # the first and the last file to be staged
            with self.subTest(corrupt=corrupt):
                shutil.rmtree(self.root, ignore_errors=True)
                self.root.mkdir()
                write_folder(self.destination, OLD_FILES)
                planted = self.planted_three()
                planted.corrupt(corrupt)
                with self.assertRaises(extract_tables.Corrupt) as refused:
                    extract_tables.extract(planted.patch, self.destination)
                self.assertEqual(refused.exception.name, corrupt)
                self.assertEqual(snapshot(self.destination), OLD_FILES)
                self.assert_nothing_beside_the_folder()

    def test_a_failure_while_the_whole_set_is_swapped_in_leaves_the_folder_as_it_was(self):
        # The disk refuses a rename of the folder a step of the swap moves: the old
        # folder aside (its source is the destination), or the staged set in (its
        # source is the staging folder).
        for moved in ("the old folder aside", "the staged set in"):
            with self.subTest(refused=moved):
                shutil.rmtree(self.root, ignore_errors=True)
                self.root.mkdir()
                write_folder(self.destination, OLD_FILES)
                planted = self.planted_three()
                source = self.destination if moved == "the old folder aside" else extract_tables.staging_of(self.destination)

                def refusing(real):
                    def rename(src, dst, *args, **kwargs):
                        if Path(src) == source:
                            raise OSError("planted: the disk refused the rename")
                        return real(src, dst, *args, **kwargs)

                    return rename

                with mock.patch("os.rename", refusing(os.rename)), mock.patch("os.replace", refusing(os.replace)):
                    with self.assertRaises(OSError):
                        extract_tables.extract(planted.patch, self.destination)
                self.assertEqual(snapshot(self.destination), OLD_FILES)
                self.assert_nothing_beside_the_folder()

    def test_a_set_of_another_size_than_expected_is_refused_and_publishes_nothing(self):
        write_folder(self.destination, OLD_FILES)
        planted = self.planted_three()
        with self.assertRaises(extract_tables.Corrupt) as refused:
            extract_tables.extract(planted.patch, self.destination, expected_count=384)
        self.assertIn("3", str(refused.exception))
        self.assertIn("384", str(refused.exception))
        self.assertEqual(snapshot(self.destination), OLD_FILES)
        self.assert_nothing_beside_the_folder()

    def test_an_index_of_another_build_is_refused_naming_the_build_and_publishes_nothing(self):
        # The server is written for build 16042 (client_archive.target_build,
        # GetVersionInfo 0x1406f8360); the tables of another build are not its tables.
        write_folder(self.destination, OLD_FILES)
        planted = Planted(self.root, [("DB/Alpha.tbl", table_content("alpha"), 5)], build=17000)
        with self.assertRaises(extract_tables.Corrupt) as refused:
            extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(refused.exception.name, "ClientData.index")
        self.assertIn("17000", str(refused.exception))
        self.assertIn("16042", str(refused.exception))
        self.assertEqual(snapshot(self.destination), OLD_FILES)
        self.assert_nothing_beside_the_folder()

    def test_an_index_of_another_build_is_refused_before_anything_beside_the_folder_is_touched(self):
        # A crash-cut run left an old folder and a staging folder; a refused run
        # must not recover them (recover would move the old folder back).
        aside, staging = extract_tables.aside_of(self.destination), extract_tables.staging_of(self.destination)
        write_folder(aside, OLD_FILES)
        write_folder(staging, {"Half.tbl": b"LBTD half written"})
        planted = Planted(self.root, [("DB/Alpha.tbl", table_content("alpha"), 5)], build=17000)
        with self.assertRaises(extract_tables.Corrupt):
            extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(snapshot(aside), OLD_FILES)
        self.assertEqual(snapshot(staging), {"Half.tbl": b"LBTD half written"})
        self.assertFalse(self.destination.exists())


class RecoveryTest(WorkInFolderCase):
    """A crash between the renames of a swap leaves folders beside the destination,
    and the next run puts them right."""

    NEW_FILES = {"Alpha.tbl": b"LBTD the new alpha"}

    def test_a_crash_after_the_old_folder_was_moved_aside_is_rolled_back(self):
        write_folder(extract_tables.aside_of(self.destination), OLD_FILES)
        write_folder(extract_tables.staging_of(self.destination), self.NEW_FILES)
        extract_tables.recover(self.destination)
        self.assertEqual(snapshot(self.destination), OLD_FILES)
        self.assertFalse(extract_tables.aside_of(self.destination).exists())
        self.assertFalse(extract_tables.staging_of(self.destination).exists())

    def test_a_run_after_a_cut_swap_publishes_the_new_set_whole(self):
        write_folder(extract_tables.aside_of(self.destination), OLD_FILES)
        write_folder(extract_tables.staging_of(self.destination), self.NEW_FILES)
        planted = Planted(self.root, [("DB/Beta.tbl", table_content("beta"), 5)])
        extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(snapshot(self.destination), {"Beta.tbl": table_content("beta")})
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ["Patch", "tables"])


def aidx_index(
    build: int = 16042,
    root: int = 2,
    root_block: bytes | None = None,
    aidx_signature: int = AIDX_SIGNATURE,
    aidx_version: int = 1,
    pack_signature: int = PACK_SIGNATURE,
    pack_version: int = 1,
) -> bytes:
    """An archive index of a header only: 3 blocks (0, 1 and 2) where block 2 is
    the AIDX block (unless root_block replaces it), the root block index `root`,
    laid out as the fact file's "archive_index.header" says. The block table is
    at 0x240 and the AIDX block at 0x270."""
    block = root_block if root_block is not None else struct.pack("<IIII", aidx_signature, aidx_version, build, 1)
    data = bytearray(pack([b"", block], root=root))
    struct.pack_into("<II", data, 0, pack_signature, pack_version)
    return bytes(data)


class IndexHeaderTest(unittest.TestCase):
    """The one reader of an archive index's header, `read_header`, with the cases
    the client's own reader decides (fact file, archive_index.header)."""

    def test_what_the_client_refuses_is_not_an_index(self):
        well_formed = aidx_index()
        cases = {
            "a PACK signature other than 0x5041434B (0x1401ba550)": aidx_index(pack_signature=0x41434B50),
            "a PACK version other than 1 (0x1401ba559)": aidx_index(pack_version=2),
            "root block index 0, which the block reader refuses even with a valid entry (0x1401b8600)": aidx_index(root=0),
            "a root block index equal to the block count (0x1401ba5c5, 0x1401b8600)": aidx_index(root=3),
            "a root block of size 0 (0x1401b8600)": aidx_index(root_block=b""),
            "a root block of 8 bytes, under the 16-byte AIDX header (0x1401bf64c)": aidx_index(root_block=bytes(8)),
            "an AIDX signature other than 0x41494458 (0x1401bf65c)": aidx_index(aidx_signature=0x58444941),
            "an AIDX version other than 1 (0x1401bf665)": aidx_index(aidx_version=2),
            "bytes that end inside the 0x230-byte PACK header (0x1401b7caa)": well_formed[:0x100],
            "bytes that end inside the block table (0x1401b7d16)": well_formed[: 0x240 + 40],
            "bytes that end inside the AIDX block": well_formed[: 0x270 + 8],
        }
        for why, data in cases.items():
            with self.subTest(why):
                with self.assertRaises(extract_tables.Corrupt):
                    extract_tables.read_header(data)
                build, reason = extract_tables.build_of_index(data)
                self.assertIsNone(build)
                self.assertTrue(reason)


if __name__ == "__main__":
    unittest.main()

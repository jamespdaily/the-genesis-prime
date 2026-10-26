"""extract_tables: every DB/*.tbl of the client's ClientData is written out, each
checked against the index's SHA-1, and a block that does not match is refused
by name.

The planted tests build a small index and archive in the layouts the script's
docstring gives (the PACK container from the fact file's "archive_index.header",
the directory node, the file entry, the AARC entries and the LZMA stream read
from the client's data), so no test touches the real client but the two real
ones, which are skipped where GENESIS_NO_CLIENT=1.

Expected values and their sources:
- the SHA-1 in the index is the SHA-1 of the stored block (the data checked: all
  384 tables of the client's index meet it), so a planted index holds the
  SHA-1 of the bytes the planted archive stores.
- 384 tables, 242,815,472 bytes of files in all, each starting with the
  signature 'LBTD' (0x4454424C): the fact file's "game_tables.ClientData" and
  "game_table.file".
- 26 of the 384 files are stored as is (flag 1), 358 LZMA-compressed (flag 5),
  read from the client's index; a stored file's SHA-1 is the index's.
- the settings: GENESIS_TABLE_DIR, else $GENESIS_HOME/tables, else
  ~/.genesis-prime/tables (setup_check/environment.sh); WILDSTAR_CLIENT_EXE
  names Client64/WildStar64.exe, whose Patch folder is beside Client64
  (setup_check.py, check_client).

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import hashlib
import lzma
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path

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
    files given as (path, content, flags)."""

    def __init__(self, root: Path, files: list[tuple[str, bytes, int]]):
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
        aidx = struct.pack("<IIII", AIDX_SIGNATURE, 1, 16042, 1)
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

    def test_only_tbl_files_directly_in_db_are_written(self):
        planted = Planted(
            self.root,
            [
                ("DB/Alpha.tbl", table_content("alpha"), 5),
                ("DB/Notes.txt", b"not a table", 1),
                ("Other/Gamma.tbl", table_content("gamma"), 5),
            ],
        )
        names = extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(names, ["Alpha.tbl"])
        self.assertEqual(sorted(p.name for p in self.destination.iterdir()), ["Alpha.tbl"])

    def test_the_index_lists_every_file_in_its_directory_tree(self):
        planted = Planted(
            self.root,
            [("DB/Alpha.tbl", table_content("alpha"), 5), ("Other/Gamma.tbl", table_content("gamma"), 1)],
        )
        files = extract_tables.read_index((planted.patch / "ClientData.index").read_bytes())
        self.assertEqual(sorted(f.path for f in files), ["DB/Alpha.tbl", "Other/Gamma.tbl"])
        gamma = next(f for f in files if f.path == "Other/Gamma.tbl")
        self.assertEqual((gamma.flags, gamma.size, gamma.stored_size), (1, len(table_content("gamma")), len(table_content("gamma"))))
        self.assertEqual(gamma.sha1, hashlib.sha1(table_content("gamma")).digest())

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

    def test_a_stored_file_whose_block_was_changed_is_refused_by_name(self):
        planted = Planted(self.root, [("DB/Alpha.tbl", table_content("alpha"), 1)])
        planted.corrupt("DB/Alpha.tbl")
        with self.assertRaises(extract_tables.Corrupt) as refused:
            extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(refused.exception.name, "DB/Alpha.tbl")

    def test_a_file_the_archive_does_not_hold_is_refused_by_name(self):
        planted = Planted(self.root, [("DB/Alpha.tbl", table_content("alpha"), 5)])
        index = bytearray((planted.patch / "ClientData.index").read_bytes())
        sha1 = hashlib.sha1(planted.stored["DB/Alpha.tbl"]).digest()
        at = bytes(index).index(sha1)
        index[at] ^= 0xFF
        (planted.patch / "ClientData.index").write_bytes(bytes(index))
        with self.assertRaises(extract_tables.Corrupt) as refused:
            extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(refused.exception.name, "DB/Alpha.tbl")

    def test_an_lzma_file_that_decodes_shorter_than_the_index_size_is_refused_by_name(self):
        planted = Planted(self.root, [("DB/Alpha.tbl", table_content("alpha"), 5)])
        index = bytearray((planted.patch / "ClientData.index").read_bytes())
        size = len(table_content("alpha"))
        at = bytes(index).index(struct.pack("<QQ", size, len(planted.stored["DB/Alpha.tbl"])))
        index[at : at + 8] = struct.pack("<Q", size + 100)
        (planted.patch / "ClientData.index").write_bytes(bytes(index))
        with self.assertRaises(extract_tables.Corrupt) as refused:
            extract_tables.extract(planted.patch, self.destination)
        self.assertEqual(refused.exception.name, "DB/Alpha.tbl")

    def test_a_second_run_replaces_the_files_of_the_first(self):
        planted = Planted(self.root, [("DB/Alpha.tbl", table_content("alpha"), 5)])
        extract_tables.extract(planted.patch, self.destination)
        (self.destination / "Alpha.tbl").write_bytes(b"changed")
        extract_tables.extract(planted.patch, self.destination)
        self.assertEqual((self.destination / "Alpha.tbl").read_bytes(), table_content("alpha"))


class SettingsTest(unittest.TestCase):
    def test_genesis_table_dir_names_the_folder(self):
        self.assertEqual(extract_tables.table_folder({"GENESIS_TABLE_DIR": "/x/tables", "GENESIS_HOME": "/h"}), Path("/x/tables"))

    def test_without_it_the_folder_is_tables_under_genesis_home(self):
        self.assertEqual(extract_tables.table_folder({"GENESIS_HOME": "/h"}), Path("/h/tables"))

    def test_without_either_the_folder_is_tables_under_the_genesis_prime_folder_in_home(self):
        self.assertEqual(extract_tables.table_folder({"HOME": "/home/jim"}), Path("/home/jim/.genesis-prime/tables"))

    def test_the_patch_folder_is_beside_client64(self):
        env = {"WILDSTAR_CLIENT_EXE": "/c/WildStar/Client64/WildStar64.exe"}
        self.assertEqual(extract_tables.patch_folder(env), Path("/c/WildStar/Patch"))

    def test_without_the_client_setting_there_is_no_patch_folder(self):
        with self.assertRaises(KeyError):
            extract_tables.patch_folder({})


@unittest.skipIf(os.environ.get("GENESIS_NO_CLIENT") == "1", "no client on this machine")
class RealClientTest(WorkInFolderCase):
    def real_patch(self) -> Path:
        self.assertTrue("WILDSTAR_CLIENT_EXE" in os.environ, "WILDSTAR_CLIENT_EXE is set by env.sh, which ./check reads")
        return extract_tables.patch_folder(os.environ)

    def test_all_384_tables_are_extracted_each_matching_the_index(self):
        patch = self.real_patch()
        names = extract_tables.extract(patch, self.destination)
        self.assertEqual(len(names), 384, "game_tables.ClientData: 384 tables")
        files = extract_tables.read_index((patch / "ClientData.index").read_bytes())
        tables = {f.path.split("/", 1)[1]: f for f in extract_tables.tables_of(files)}
        self.assertEqual(sorted(tables), names)
        total = 0
        for name in names:
            content = (self.destination / name).read_bytes()
            total += len(content)
            self.assertEqual(len(content), tables[name].size, name + ": the index's size")
            self.assertEqual(content[:4], b"LBTD", name + ": game_table.file signature 0x4454424C")
            if tables[name].flags == 1:
                self.assertEqual(hashlib.sha1(content).digest(), tables[name].sha1, name + ": a stored file's SHA-1 is the index's")
        self.assertEqual(total, 242_815_472, "game_tables.ClientData: 242,815,472 bytes of files")
        self.assertEqual(sum(1 for f in tables.values() if f.flags == 1), 26, "26 stored files")
        self.assertEqual(sum(1 for f in tables.values() if f.flags == 5), 358, "358 LZMA files")

    def test_the_real_index_and_archive_hold_the_planted_layouts(self):
        patch = self.real_patch()
        files = extract_tables.read_index((patch / "ClientData.index").read_bytes())
        db = [f for f in files if f.path == "DB/Creature2.tbl"]
        self.assertEqual(len(db), 1)
        self.assertEqual(db[0].size, 45_385_712, "game_tables.ClientData: Creature2's file is 45,385,712 bytes")


if __name__ == "__main__":
    unittest.main()

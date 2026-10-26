"""The place a new character starts has terrain: the area file of the starting
row's position is in the client's index.

The server's start is the WorldLocation2 row named by `starting_location_id` in
src/genesis_prime.gleam. The client loads a world from the .area files in its
map folder, and a world whose folder holds none shows grey ground and sky (the
fact file's "WorldLocation2.50230" and "area_file.cell"). So the test reads the
row's world, position and the World row's folder from the client's extracted
tables, builds the file's name with the area_file.cell rule and looks it up in
the client's ClientData.index.

Expected values and their sources:
- area_file.cell: the four hex digits are the row, 64 + floor(z / 512), then the
  column, 64 + floor(x / 512), of the position's first (x) and third (z) floats;
  the file is Map/<folder>/<folder>.<RRCC>.area, folder being the last part of
  the World row's assetPath. A position of 4605.65, 494.996 lies in 4048.
- game_table.file: the table file layout (header 0x60 bytes; record size at 0x18,
  record block offset at 0x40, lookup offset at 0x50, each counted from the end
  of the header; a u64 string offset counted from the record block's start, to
  UTF-16 text). game_table.schema: WorldLocation2's record is 52 bytes with
  worldId at 40, position0 at 12 and position2 at 20; World's assetPath is at 8.
- Map\\PreTutorialExile (world 3400, WorldLocation2 row 50177) holds no .area
  file in the index, and Map\\ExileArkShipTutorial (world 1537, row 50230)
  holds 210.

The real-client test is skipped where GENESIS_NO_CLIENT=1, as the other real-client
tests are; anywhere else a missing client or table fails it with the fix.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_*.py'
"""

import math
import os
import re
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import extract_tables  # noqa: E402

REPOSITORY = Path(__file__).resolve().parent.parent
HEADER = 0x60
WORLD_LOCATION2_RECORD = 52
WORLD_LOCATION2_POSITION_X = 12
WORLD_LOCATION2_POSITION_Z = 20
WORLD_LOCATION2_WORLD_ID = 40
WORLD_ASSET_PATH = 8


def area_file_name(folder: str, x: float, z: float) -> str:
    """The index path of the area file that holds a position of a world
    (area_file.cell)."""
    row = 64 + math.floor(z / 512)
    column = 64 + math.floor(x / 512)
    return "Map/%s/%s.%02x%02x.area" % (folder, folder, row, column)


def starting_location_id(source: str) -> int:
    """The WorldLocation2 row of `const starting_location_id = 50_230`."""
    found = re.search(r"^const starting_location_id = ([0-9_]+)$", source, re.MULTILINE)
    if found is None:
        raise AssertionError("src/genesis_prime.gleam holds no `const starting_location_id = <number>`")
    return int(found.group(1).replace("_", ""))


def record_of(table: bytes, row_id: int) -> tuple[bytes, bytes]:
    """The record of the row with the id, and the table's record block (the
    base of its string offsets), by the lookup array (game_table.file)."""
    record_size, record_block, lookup, lookup_count = (
        struct.unpack_from("<Q", table, 0x18)[0],
        struct.unpack_from("<Q", table, 0x40)[0],
        struct.unpack_from("<Q", table, 0x50)[0],
        struct.unpack_from("<Q", table, 0x48)[0],
    )
    if row_id >= lookup_count:
        raise AssertionError("the table holds no row %d" % row_id)
    (index,) = struct.unpack_from("<I", table, HEADER + lookup + 4 * row_id)
    if index == 0xFFFFFFFF:
        raise AssertionError("the table holds no row %d" % row_id)
    block = HEADER + record_block
    return table[block + record_size * index : block + record_size * (index + 1)], table[block:]


def text_at(block: bytes, offset: int) -> str:
    end = offset
    while block[end : end + 2] != b"\0\0" or (end - offset) % 2:
        end += 1
    return block[offset:end].decode("utf-16-le")


class AreaFileNameTest(unittest.TestCase):
    def test_the_arkship_start_lies_in_area_file_4048(self):
        self.assertEqual(
            area_file_name("ExileArkShipTutorial", 4605.650, 494.996),
            "Map/ExileArkShipTutorial/ExileArkShipTutorial.4048.area",
            "area_file.cell: the Cryo Awakening Protocol room is in ExileArkShipTutorial.4048.area",
        )

    def test_a_negative_position_counts_down_from_the_middle_cell(self):
        self.assertEqual(area_file_name("W", -5.0278, -0.1), "Map/W/W.3f3f.area", "area_file.cell: floor(-0.01) is -1, so 64 - 1 = 0x3f")

    def test_the_start_is_read_from_the_server_source(self):
        self.assertEqual(starting_location_id("const starting_location_id = 50_230\n"), 50230)


@unittest.skipIf(os.environ.get("GENESIS_NO_CLIENT") == "1", "no client on this machine")
class StartingAreaTest(unittest.TestCase):
    def test_the_starting_rows_position_lies_in_an_area_file_the_client_holds(self):
        self.assertTrue("WILDSTAR_CLIENT_EXE" in os.environ, "WILDSTAR_CLIENT_EXE is set by env.sh, which ./check reads")
        tables = extract_tables.table_folder(os.environ)
        for name in ("WorldLocation2.tbl", "World.tbl"):
            self.assertTrue((tables / name).is_file(), "%s is missing: run python3.13 -I setup_check/extract_tables.py" % (tables / name))
        row_id = starting_location_id((REPOSITORY / "src" / "genesis_prime.gleam").read_text())
        location, _ = record_of((tables / "WorldLocation2.tbl").read_bytes(), row_id)
        (x,) = struct.unpack_from("<f", location, WORLD_LOCATION2_POSITION_X)
        (z,) = struct.unpack_from("<f", location, WORLD_LOCATION2_POSITION_Z)
        (world_id,) = struct.unpack_from("<I", location, WORLD_LOCATION2_WORLD_ID)
        world, block = record_of((tables / "World.tbl").read_bytes(), world_id)
        (offset,) = struct.unpack_from("<Q", world, WORLD_ASSET_PATH)
        folder = text_at(block, offset).split("\\")[-1]
        wanted = area_file_name(folder, x, z)
        index = extract_tables.read_index((extract_tables.patch_folder(os.environ) / "ClientData.index").read_bytes())
        self.assertTrue(
            wanted in {file.path for file in index},
            "WorldLocation2 row %d (world %d, %s, x %.3f, z %.3f) lies in %s, which the client's index does not hold, "
            "so the world shows no terrain" % (row_id, world_id, folder, x, z, wanted),
        )


if __name__ == "__main__":
    unittest.main()

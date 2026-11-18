"""The server's ground files: the height layer of every area file the server's units stand in (and its
8 neighbours), read from the client's archive into a folder outside every git tree.

    python3.13 -I dev/terrain_extract.py

Run with ~/.genesis-prime/env.sh read (WILDSTAR_CLIENT_EXE names the client, whose Patch folder holds
ClientData.index and ClientData.archive; PGHOST, PGPORT and PGUSER name the Postgres that holds the spawn
table) and with the client's game tables extracted (setup_check/extract_tables.py), for World.tbl.
Reads: Patch/ClientData.index and .archive (a ClientData.index of any build but 16042 is refused), World.tbl
in $GENESIS_TABLE_DIR, and the `spawn` table of the database named by $GENESIS_TERRAIN_DATABASE (default
genesis_play). Writes: the terrain folder, $GENESIS_TERRAIN_DIR, else $GENESIS_HOME/terrain, else
~/.genesis-prime/terrain; one folder inside this repository or any git working tree is refused, as the
client's data never goes into one. The folder is replaced as a whole, so one that holds files and no
state.json was not made by this tool and is refused. Two runs at once are not guarded.

Which files: for each distinct (world, area square) a spawn row stands in (area_file.cell: row 64 + floor(z / 512),
column 64 + floor(x / 512)) and each of its 8 neighbouring squares, the world's area file
`Map/<asset>/<last part of asset>.<rr><cc>.area` when the index lists it (asset is World.tbl's assetPath).
A square with no file in the index is left out and counted in the report; so is a world whose asset holds no
area file.

Each file is checked against the SHA-1 its index holds before it is read (extract_tables.archive_contents).
One `<asset's last part>/<rrcc>.heights` is written per area file (rr and cc in lower-case hex, as the client's
file names), 184,864 bytes each, the client's own bytes of layer 0 of each chunk, unchanged:
  - bytes 0 to 31: a presence mask over the area file's 256 chunk slots (area_file.ground_height: slot =
    z row * 16 + x column); bit (slot % 8) of byte (slot / 8) is set when the slot holds a chunk;
  - then 256 slots of 722 bytes (19 by 19 little-endian u16 values, the rows along z, vertices -1 to 17 on
    each axis; 0x14037d790 builds the height from them), slot s at byte 32 + 722 * s. A slot with no chunk is
    zero-filled. A chunk whose layer flags lack layer 0 holds the client's shared default, every value 0x1fff
    (0x140c41340), and its bit is set.
The area file is read as 0x1402df540 (magic 'aera', version 0, tagged records), its 'CHNK' record as
0x1402df8a0 (a word of size and slots to skip, then the chunk) and each chunk as 0x1402e4ec0 (a word of layer
flags, the bytes of each flagged layer in bit order with layer 0 first, then tagged records to the end: one
'PROP' at most, and at most one each of 'WAtG', 'wbsP' and 'curD', whose counted entries must fill the record
exactly). A file holding a chunk the client's reader would refuse, at any layer or record, is refused here,
naming it; the run fails and the folder is as it was.

The report gives the file count, the bytes written and the time. state.json (build, and per file the area
file's path and index SHA-1 and the SHA-1 of the file written) lets a second run with nothing changed print
"current" and write nothing: it compares the wanted files with state.json and hashes each file in the folder.
"""

import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPOSITORY / ".claude" / "skills" / "decoding-the-client" / "scripts"))
sys.path.insert(0, str(REPOSITORY / "setup_check"))

import client_files  # noqa: E402
import decompiled  # noqa: E402
import extract_tables  # noqa: E402
from decompiled import Refused  # noqa: E402

STATE_FILE = "state.json"
FORMAT_VERSION = 1
AREA_MAGIC = 0x61726561  # 'aera' on disk, 0x1402df540
CHUNK_TAG = 0x43484E4B  # 'KNHC' on disk, the client's 'CHNK'
SLOTS = 256
LAYER_SIZE = 722  # 19 * 19 * 2, 0x140c41340
# Byte size of each of a chunk's 32 layers, in flag-bit order: the layer table's (max z - min z) * row bytes,
# row by row (0x140c41340, 56-byte rows; 0x1402e4ec0 steps through them).
LAYER_SIZES = (
    722, 16, 8450, 8450, 8450, 4, 64, 16, 4225, 2178, 4, 578, 1, 4624, 2312, 8450,
    4096, 2312, 2312, 2312, 2312, 1, 16, 16900, 8, 8450, 21316, 4096, 16, 8450, 8450, 2312,
)  # fmt: skip
# The chunk's trailing tagged records, as the words the client compares (0x1402e4ec0); other tags are skipped.
WATER_TAG, WATER_SKY_TAG, CURVE_TAG, PROP_TAG = 0x57417447, 0x77627350, 0x63757244, 0x50524F50
MASK_SIZE = SLOTS // 8
FILE_SIZE = MASK_SIZE + SLOTS * LAYER_SIZE
DEFAULT_LAYER = struct.pack("<H", 0x1FFF) * (19 * 19)
AREA_SIZE = 512
AREA_ORIGIN = 64  # area_file.cell
AREA_LIMIT = 0x80  # ParseAreaFileName 0x1402dca80: each digit pair at most 0x80
DEFAULT_DATABASE = "genesis_play"


def terrain_folder(env) -> Path:
    """The folder named in the module's description; raises Refused for one inside a git tree."""
    return decompiled.outside_work_tree_folder(env, "GENESIS_TERRAIN_DIR", "terrain", "the client's ground heights")


def heights_of_area(name: str, data: bytes) -> bytes:
    """The .heights file's bytes for one area file's bytes; raises Corrupt (naming the area file) for one
    the client's reader refuses."""

    def refuse(reason: str):
        raise extract_tables.Corrupt(name, reason)

    if len(data) < 8:
        refuse("shorter than the magic and version words")
    magic, version = struct.unpack_from("<II", data, 0)
    if magic != AREA_MAGIC or version != 0:
        refuse("does not start with the magic 'aera' and version 0")
    mask = bytearray(MASK_SIZE)
    layers = [bytes(LAYER_SIZE)] * SLOTS
    at = 8
    while at < len(data):
        if len(data) - at < 8:
            refuse("a record's tag and size run past the end")
        tag, size = struct.unpack_from("<II", data, at)
        at += 8
        if size > len(data) - at:
            refuse("a record of %d bytes runs past the end" % size)
        if tag == CHUNK_TAG:
            _read_chunks(data[at : at + size], mask, layers, refuse)
        at += size
    return bytes(mask) + b"".join(layers)


def _read_chunks(payload: bytes, mask: bytearray, layers: list[bytes], refuse) -> None:
    """Fills mask and layers from one CHNK record's payload (0x1402df8a0)."""
    at = 0
    slot = 0
    while at < len(payload):
        if len(payload) - at < 4:
            refuse("a chunk's size word runs past the end")
        (word,) = struct.unpack_from("<I", payload, at)
        at += 4
        slot += word >> 24
        size = word & 0xFFFFFF
        if slot >= SLOTS:
            refuse("a chunk is in slot %d, past 255" % slot)
        if size > len(payload) - at:
            refuse("the chunk of slot %d runs past the end" % slot)
        chunk = payload[at : at + size]
        at += size
        layers[slot] = _chunk_height_layer(chunk, slot, refuse)
        mask[slot // 8] |= 1 << (slot % 8)
        slot += 1


def _chunk_height_layer(chunk: bytes, slot: int, refuse) -> bytes:
    """Layer 0 of one chunk's bytes (the shared default when its flags lack layer 0), after walking the whole
    chunk as LoadTerrainChunk 0x1402e4ec0 does: every flagged layer's bytes, then the tagged records to the end."""
    if len(chunk) < 4:
        refuse("the chunk of slot %d is shorter than its layer flags word" % slot)
    (flags,) = struct.unpack_from("<I", chunk, 0)
    at = 4
    for bit in range(32):
        if flags >> bit & 1:
            if len(chunk) - at < LAYER_SIZES[bit]:
                refuse("the chunk of slot %d is shorter than its layer %d" % (slot, bit))
            at += LAYER_SIZES[bit]
    height = chunk[4 : 4 + LAYER_SIZE] if flags & 1 else DEFAULT_LAYER
    seen: set[int] = set()
    while at < len(chunk):
        if len(chunk) - at < 8:
            refuse("a record's tag and size in the chunk of slot %d run past the end" % slot)
        tag, size = struct.unpack_from("<II", chunk, at)
        at += 8
        if size > len(chunk) - at:
            refuse("a record of %d bytes in the chunk of slot %d runs past the end" % (size, slot))
        body = chunk[at : at + size]
        at += size
        if tag in (PROP_TAG, WATER_TAG, WATER_SKY_TAG, CURVE_TAG):
            if tag in seen:
                refuse("the chunk of slot %d holds a second record of tag 0x%08X" % (slot, tag))
            seen.add(tag)
            if tag != PROP_TAG:
                _walk_counted_entries(tag, body, slot, refuse)
    return height


def _walk_counted_entries(tag: int, body: bytes, slot: int, refuse) -> None:
    """Checks a 'WAtG', 'wbsP' or 'curD' record body as the client's reader does: a count word, then that many
    entries, the bytes ending exactly at the body's end. A 'WAtG' entry is 0x50 fixed bytes, a run of the word
    at 0x40 times 4 bytes, and a run of the word at 0x44 times 0x48 bytes (0x1402e5720); a 'wbsP' entry the
    same with 0x18 bytes in the first run (0x1402e5860); a 'curD' entry a count word and that many 12-byte
    items (0x1402e59b0)."""
    if len(body) < 4:
        refuse("the chunk of slot %d holds a record of tag 0x%08X shorter than its count word" % (slot, tag))
    (count,) = struct.unpack_from("<I", body, 0)
    at = 4
    for _ in range(count):
        left = len(body) - at
        if tag == CURVE_TAG:
            if left < 4:
                refuse("an entry of the chunk of slot %d's curve record runs past the end" % slot)
            (items,) = struct.unpack_from("<I", body, at)
            if left - 4 < items * 12:
                refuse("an entry of the chunk of slot %d's curve record runs past the end" % slot)
            at += 4 + items * 12
            continue
        if left < 0x50:
            refuse("an entry of the chunk of slot %d's record of tag 0x%08X runs past the end" % (slot, tag))
        first, second = struct.unpack_from("<II", body, at + 0x40)
        first_bytes = first * (4 if tag == WATER_TAG else 0x18)
        if left - 0x50 < first_bytes or left - 0x50 - first_bytes < second * 0x48:
            refuse("an entry of the chunk of slot %d's record of tag 0x%08X runs past the end" % (slot, tag))
        at += 0x50 + first_bytes + second * 0x48
    if at != len(body):
        refuse("the chunk of slot %d's record of tag 0x%08X holds bytes after its last entry" % (slot, tag))


def world_assets(table: bytes) -> dict[int, str]:
    """World.tbl's assetPath by world id (game_table.file layout, World.tbl: ID, then assetPath); raises
    Refused for a file that is not a game table or lacks either column. Own reader: client_files'
    spell4_text_ids reads Spell4's integer columns only, and no shared reader of a string column exists."""
    if len(table) < client_files.HEADER_END or table[:4] != client_files.TABLE_MAGIC:
        raise Refused("World.tbl does not start %r" % client_files.TABLE_MAGIC)
    record_size, column_count, column_table, record_count, block_size, block_at = struct.unpack_from("<QQQQQQ", table, 0x18)
    body = table[client_files.HEADER_END :]
    names_at = column_table + (24 * column_count + 15) // 16 * 16
    if names_at > len(body) or block_at + block_size > len(body) or record_count * record_size > block_size:
        raise Refused("World.tbl's columns or records run past the end of the file")
    where: dict[str, tuple[int, int]] = {}
    place = 0
    for number in range(column_count):
        name_length, _, name_at, type_number = struct.unpack_from("<IIQH", body, column_table + 24 * number)
        size = 8 if type_number in (20, 130) else 4
        if type_number not in (3, 4, 11, 20, 130):
            raise Refused("World.tbl column %d has type %d, which this reader does not know" % (number, type_number))
        place = (place + size - 1) // size * size
        start = names_at + name_at
        where[body[start : start + 2 * name_length - 2].decode("utf-16-le", errors="replace")] = (place, type_number)
        place += size
    if where.get("ID", (None, None))[1] != 3 or where.get("assetPath", (None, None))[1] != 130:
        raise Refused("World.tbl lacks an ID (type 3) or an assetPath (type 130) column")
    assets = {}
    for record in range(record_count):
        base = block_at + record * record_size
        (world_id,) = struct.unpack_from("<I", body, base + where["ID"][0])
        (offset,) = struct.unpack_from("<Q", body, base + where["assetPath"][0])
        start = block_at + offset
        end = start
        while body[end : end + 2] != b"\0\0" or (end - start) % 2:
            end += 1
            if end >= len(body):
                raise Refused("World.tbl row %d's assetPath has no ending zero" % world_id)
        assets[world_id] = body[start:end].decode("utf-16-le")
    return assets


def spawn_squares(database: str) -> set[tuple[int, int, int]]:
    """The distinct (world id, area row, area column) of the spawn table's rows (area_file.cell), by psql."""
    query = "select distinct world_id, 64 + floor(z / 512)::int, 64 + floor(x / 512)::int from spawn"
    done = subprocess.run(["psql", "-X", "-At", "-F", ",", "-d", database, "-c", query], capture_output=True, text=True)
    if done.returncode != 0:
        raise Refused("psql could not read the spawn table of %s (PGHOST, PGPORT and PGUSER are set by env.sh): %s" % (database, done.stderr.strip()))
    return {tuple(int(part) for part in line.split(",")) for line in done.stdout.split()}  # type: ignore[misc]


def wanted_files(
    squares: set[tuple[int, int, int]], assets: dict[int, str], listed: dict[str, extract_tables.IndexedFile]
) -> tuple[dict[str, extract_tables.IndexedFile], dict[str, int]]:
    """The area files to read, keyed by their .heights path (`<name>/<rrcc>.heights`) with the area file's
    index entry, and the report's counts: the spawn squares with no area file in the index, and the worlds
    with no asset row or no area file at all."""
    by_lower = {path.lower(): file for path, file in listed.items()}
    wanted: dict[str, extract_tables.IndexedFile] = {}
    squares_without_file = 0
    worlds_without_file = 0
    for world_id in sorted({world for world, _, _ in squares}):
        asset = assets.get(world_id)
        if asset is None:
            worlds_without_file += 1
            continue
        folder = asset.replace("\\", "/")
        name = folder.rsplit("/", 1)[-1]
        found = False
        for _, row, column in sorted(square for square in squares if square[0] == world_id):
            for near_row in range(max(row - 1, 0), min(row + 1, AREA_LIMIT) + 1):
                for near_column in range(max(column - 1, 0), min(column + 1, AREA_LIMIT) + 1):
                    area = by_lower.get("%s/%s.%02x%02x.area" % (folder.lower(), name.lower(), near_row, near_column))
                    if area is not None:
                        wanted["%s/%02x%02x.heights" % (name, near_row, near_column)] = area
                        found = True
                    elif (near_row, near_column) == (row, column):
                        squares_without_file += 1
        worlds_without_file += not found
    return wanted, {"spawn squares with no area file": squares_without_file, "worlds with no area file": worlds_without_file}


def _state(build: int, wanted: dict[str, extract_tables.IndexedFile], written: dict[str, str]) -> dict:
    return {
        "format": FORMAT_VERSION,
        "build": build,
        "files": {key: {"area": wanted[key].path, "sha1": wanted[key].sha1.hex(), "content_sha1": written[key]} for key in sorted(wanted)},
    }


def load_state(folder: Path) -> dict | None:
    """state.json of the folder, or None when there is none; raises Refused when it is not one this tool wrote."""
    path = folder / STATE_FILE
    if not path.is_file():
        return None
    try:
        saved = json.loads(path.read_text())
        if saved["format"] != FORMAT_VERSION or not isinstance(saved["build"], int):
            raise TypeError("another format or build")
        for key, entry in saved["files"].items():
            for field in ("area", "sha1", "content_sha1"):
                if not isinstance(entry[field], str):
                    raise TypeError("%s: %s is not text" % (key, field))
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as bad:
        raise Refused("%s cannot be read (%s); remove the folder to extract again" % (path, bad)) from None
    return saved


def is_current(folder: Path, build: int, wanted: dict[str, extract_tables.IndexedFile]) -> bool:
    """Whether state.json and the folder hold exactly the wanted files, from the index's SHA-1s, as written."""
    saved = load_state(folder)
    if saved is None or saved["build"] != build or saved["files"].keys() != wanted.keys():
        return False
    for key, file in wanted.items():
        entry = saved["files"][key]
        on_disk = folder / key
        if entry["sha1"] != file.sha1.hex() or not on_disk.is_file() or on_disk.stat().st_size != FILE_SIZE:
            return False
        with open(on_disk, "rb") as content:
            if hashlib.file_digest(content, "sha1").hexdigest() != entry["content_sha1"]:
                return False
    return True


def extract(patch: Path, folder: Path, wanted: dict[str, extract_tables.IndexedFile], build: int) -> int:
    """Writes the wanted files into folder as a whole (extract_tables' staging and swap); returns the bytes
    written. Raises Corrupt naming the area file that fails, or Refused for a folder this tool did not make;
    the folder is as it was after any failure."""
    folder.parent.mkdir(parents=True, exist_ok=True)
    if folder.exists() and any(folder.iterdir()) and not (folder / STATE_FILE).is_file():
        raise Refused("%s holds files and no %s: it is not a folder this tool made, and it is replaced as a whole" % (folder, STATE_FILE))
    extract_tables.recover(folder)
    staging = extract_tables.staging_of(folder)
    staging.mkdir()
    try:
        written: dict[str, str] = {}
        total = 0
        for key, data in extract_tables.archive_contents(patch / "ClientData.archive", wanted):
            heights = heights_of_area(wanted[key].path, data)
            target = staging / key
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(heights)
            written[key] = hashlib.sha1(heights).hexdigest()
            total += len(heights)
        (staging / STATE_FILE).write_text(json.dumps(_state(build, wanted, written), indent=0) + "\n")
        extract_tables.swap_whole(staging, folder)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return total


def main() -> int:
    if "WILDSTAR_CLIENT_EXE" not in os.environ:
        print("WILDSTAR_CLIENT_EXE is not set: add it to env.sh (GENESIS_HOME/env.sh), as ./setup-check says")
        return 1
    started = time.monotonic()
    try:
        folder = terrain_folder(os.environ)
        patch = extract_tables.patch_folder(os.environ)
        index = (patch / extract_tables.INDEX_NAME).read_bytes()
        extract_tables.require_target_build(index)
        table_path = extract_tables.table_folder(os.environ) / "World.tbl"
        if not table_path.is_file():
            raise Refused("no World.tbl in %s; run python3.13 -I setup_check/extract_tables.py" % table_path.parent)
        assets = world_assets(table_path.read_bytes())
        listed = {f.path: f for f in extract_tables.read_index(index) if f.path.startswith("Map/") and f.path.endswith(".area")}
        squares = spawn_squares(os.environ.get("GENESIS_TERRAIN_DATABASE", DEFAULT_DATABASE))
        wanted, counts = wanted_files(squares, assets, listed)
        if not wanted:
            raise Refused("the spawn table names no area file the index lists")
        build = extract_tables.TARGET_BUILD
        left_out = ", ".join("%s: %d" % item for item in counts.items())
        if is_current(folder, build, wanted):
            print("current: %d files in %s (%s)" % (len(wanted), folder, left_out))
            return 0
        written = extract(patch, folder, wanted, build)
    except (Refused, extract_tables.Corrupt) as refused:
        print("refused: %s" % refused)
        return 1
    print("extracted %d files, %d bytes into %s in %.1f seconds (%s)" % (len(wanted), written, folder, time.monotonic() - started, left_out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

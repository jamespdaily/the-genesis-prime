"""The client's UI files and texts, read from the client's archives into a folder outside every git tree.

    python3.13 -I client_files.py extract
    python3.13 -I client_files.py check
    python3.13 -I client_files.py text <id>...
    python3.13 -I client_files.py text --search <word>...

Run with ~/.genesis-prime/env.sh read: WILDSTAR_CLIENT_EXE names the client, whose Patch folder (beside
Client64) holds ClientData.index/.archive and ClientDataEN.index/.archive. Both indexes must be build
16042; another build is refused, naming the index.

The folder is $GENESIS_CLIENT_FILES_DIR, else $GENESIS_HOME/client-files, else ~/.genesis-prime/client-files.
It is the client's data, so a folder inside this repository or any git working tree is refused. It is
replaced as a whole, so a folder that exists, holds something and has no state.json is refused: it is not
one this script made.

extract   Writes every file under UI/ of ClientData (the forms, scripts and art the client's UI loads, about
          16,000 files and 1.8 GB) and en-US.bin of ClientDataEN (at the root of that index) into the
          folder, each file checked against the SHA-1 its index holds, as setup_check/extract_tables.py
          checks the game tables, and swapped in whole (a run that fails leaves the folder as it was).
          Prints the file count of each part. state.json records each file's path in the archive and its
          index SHA-1, and each index's build.
check     Reads both indexes and compares them with state.json and with the folder: exit 0 and "current";
          exit 1 and each file that is new, gone, has another SHA-1 or is missing or the wrong size on
          disk (the first 50), or "no copy". It changes nothing.
text      Prints `<id>\\t<text>` for each id given (decimal or 0x hex), in the order given; an id the file
          lacks prints `<id>\\t(none)` and the exit is 1. With --search, prints every text that holds all
          the words, ignoring case, in id order, then `N texts`. A newline, carriage return or tab inside
          a text prints as \\n, \\r or \\t. Without en-US.bin in the folder it says to run extract.

The layout of en-US.bin is the fact file's language_file.layout: magic 'XETL'; at 0x40 the entry count
(u32), at 0x48 the entries' place (u64), at 0x50 the text's length in UTF-16 characters (u64), at 0x58 the
text's place (u64), both places counted from byte 0x60; entries of 8 bytes, a text id then the character
offset of its text, sorted by id; each text zero-terminated UTF-16LE. The client looks an id up by binary
search (GetLocalizedText 0x14034bdd0). The reader refuses, naming the reason, a file with another magic,
entries or text past its end, an offset past the text, ids not in order, or a unit that is not UTF-16.
"""

import argparse
import bisect
import json
import os
import shutil
import struct
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_facts  # noqa: E402

sys.path.insert(0, str(check_facts.REPOSITORY / "setup_check"))

import decompiled  # noqa: E402
import extract_tables  # noqa: E402
import ghidra_env  # noqa: E402
from decompiled import Refused  # noqa: E402

STATE_FILE = "state.json"
LANGUAGE_FILE = "en-US.bin"  # the path in ClientDataEN's index: it sits at the root
UI_DIRECTORY = "UI/"
HEADER_END = 0x60
MAGIC = b"XETL"
SHOWN_CHANGES = 50


@dataclass(frozen=True)
class Part:
    """The files taken from one archive: its name (ClientData), its index's build and the files by their
    path in the archive, which is also their path in the folder."""

    archive: str
    build: int
    files: dict[str, extract_tables.IndexedFile]


def client_files_folder(env) -> Path:
    """The folder named in the module's description; raises Refused for one inside a git tree."""
    if env.get("GENESIS_CLIENT_FILES_DIR"):
        folder = Path(env["GENESIS_CLIENT_FILES_DIR"])
    else:
        folder = ghidra_env.genesis_home(env) / "client-files"
    decompiled.require_outside_work_trees(folder, "the client's files")
    return folder


def read_parts(patch: Path) -> list[Part]:
    """The UI files of ClientData and the language file of ClientDataEN, as the indexes list them. Raises
    Corrupt for an index that is not build 16042 or has no en-US.bin."""
    parts = []
    for archive, wanted in (("ClientData", lambda path: path.startswith(UI_DIRECTORY)), ("ClientDataEN", lambda path: path == LANGUAGE_FILE)):
        name = archive + ".index"
        index = (patch / name).read_bytes()
        extract_tables.require_target_build(index, name)
        listed = {f.path: f for f in extract_tables.read_index(index, name) if wanted(f.path)}
        if not listed:
            raise extract_tables.Corrupt(name, "lists none of the files wanted from it")
        parts.append(Part(archive, extract_tables.read_header(index, name).build, listed))
    return parts


def _state(parts: list[Part]) -> dict:
    return {
        "builds": {part.archive: part.build for part in parts},
        "files": {
            path: {"archive": part.archive, "sha1": file.sha1.hex()} for part in parts for path, file in sorted(part.files.items())
        },
    }


def extract(patch: Path, folder: Path) -> list[Part]:
    """Fills folder as the module's description says; raises Corrupt naming the file or index that fails, or
    Refused for a folder that is not one this script made. The folder is as it was after any failure."""
    parts = read_parts(patch)
    if folder.exists() and any(folder.iterdir()) and not (folder / STATE_FILE).is_file():
        raise Refused("%s holds files and no %s: it is not a folder this script made, and it is replaced as a whole" % (folder, STATE_FILE))
    folder.parent.mkdir(parents=True, exist_ok=True)
    extract_tables.recover(folder)
    staging = extract_tables.staging_of(folder)
    staging.mkdir()
    try:
        for part in parts:
            extract_tables.stage_files(patch / (part.archive + ".archive"), part.files, staging)
        (staging / STATE_FILE).write_text(json.dumps(_state(parts), indent=0) + "\n")
        extract_tables.swap_whole(staging, folder)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return parts


def changes(parts: list[Part], folder: Path) -> list[str] | None:
    """What differs between the indexes, state.json and the folder, one line each; None when there is no
    copy; an empty list when the copy is current."""
    path = folder / STATE_FILE
    if not path.is_file():
        return None
    saved = json.loads(path.read_text())
    found = []
    for part in parts:
        before = saved["builds"].get(part.archive)
        if before != part.build:
            found.append("%s.index is build %d, the copy was made from build %s" % (part.archive, part.build, before))
    wanted = {path: (part.archive, file) for part in parts for path, file in part.files.items()}
    for name in sorted(wanted.keys() - saved["files"].keys()):
        found.append("%s is new in the index" % name)
    for name in sorted(saved["files"].keys() - wanted.keys()):
        found.append("%s is gone from the index" % name)
    for name in sorted(wanted.keys() & saved["files"].keys()):
        archive, file = wanted[name]
        if saved["files"][name]["sha1"] != file.sha1.hex() or saved["files"][name]["archive"] != archive:
            found.append("%s has another SHA-1 in the index" % name)
        on_disk = folder / name
        if not on_disk.is_file():
            found.append("%s is missing from the folder" % name)
        elif on_disk.stat().st_size != file.size:
            found.append("%s is %d bytes in the folder, the index says %d" % (name, on_disk.stat().st_size, file.size))
    return found


@dataclass(frozen=True)
class LanguageFile:
    """en-US.bin read as the module's description says: the bytes, the ids and character offsets of the
    entries (parallel, ids ascending) and where the text starts and ends in the bytes."""

    data: bytes
    ids: list[int]
    offsets: list[int]
    text_at: int
    text_end: int

    def text(self, text_id: int) -> str | None:
        """The text of text_id, or None when the file has none."""
        at = bisect.bisect_left(self.ids, text_id)
        if at == len(self.ids) or self.ids[at] != text_id:
            return None
        return self._decode(text_id, self.offsets[at])

    def texts(self):
        """Every (id, text), in id order."""
        for text_id, offset in zip(self.ids, self.offsets):
            yield text_id, self._decode(text_id, offset)

    def _decode(self, text_id: int, offset: int) -> str:
        start = self.text_at + 2 * offset
        end = start
        while True:
            end = self.data.find(b"\0\0", end, self.text_end)
            if end == -1:
                raise Refused("text %d has no terminating zero before the end of the text" % text_id)
            if (end - start) % 2 == 0:
                break
            end += 1
        try:
            return self.data[start:end].decode("utf-16-le")
        except UnicodeDecodeError as bad:
            raise Refused("text %d is not UTF-16: %s" % (text_id, bad.reason)) from None


def read_language_file(data: bytes) -> LanguageFile:
    """Parses en-US.bin; raises Refused for anything the module's description lists."""
    if len(data) < HEADER_END:
        raise Refused("the language file is shorter than its %#x-byte header" % HEADER_END)
    if data[:4] != MAGIC:
        raise Refused("the language file starts %r, not %r" % (data[:4], MAGIC))
    (count,) = struct.unpack_from("<I", data, 0x40)
    entries_place, text_length, text_place = struct.unpack_from("<QQQ", data, 0x48)
    entries_at, text_at = HEADER_END + entries_place, HEADER_END + text_place
    if entries_at + 8 * count > len(data):
        raise Refused("the %d entries run past the end of the file" % count)
    if text_at + 2 * text_length > len(data):
        raise Refused("the text of %d characters runs past the end of the file" % text_length)
    words = struct.unpack_from("<%dI" % (2 * count), data, entries_at)
    ids, offsets = list(words[0::2]), list(words[1::2])
    for before, after in zip(ids, ids[1:]):
        if before >= after:
            raise Refused("the entries are not in id order: %d is followed by %d" % (before, after))
    for text_id, offset in zip(ids, offsets):
        if offset >= text_length:
            raise Refused("text %d starts at character %d, past the text's %d characters" % (text_id, offset, text_length))
    return LanguageFile(data, ids, offsets, text_at, text_at + 2 * text_length)


def _counted(count: int, noun: str) -> str:
    return "%d %s" % (count, noun if count == 1 else noun + "s")


def _printable(text: str) -> str:
    return text.replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")


def _text_id(word: str) -> int:
    try:
        return int(word, 0)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a text id (decimal or 0x hex)" % word) from None


def _run_text(arguments, folder: Path, out) -> int:
    path = folder / LANGUAGE_FILE
    if not path.is_file():
        print("client_files: no %s in %s; run extract" % (LANGUAGE_FILE, folder), file=sys.stderr)
        return 1
    language = read_language_file(path.read_bytes())
    if arguments.search:
        words = [word.lower() for word in arguments.search]
        found = 0
        for text_id, text in language.texts():
            lowered = text.lower()
            if all(word in lowered for word in words):
                print("%d\t%s" % (text_id, _printable(text)), file=out)
                found += 1
        print(_counted(found, "text"), file=out)
        return 0
    status = 0
    for text_id in arguments.ids:
        text = language.text(text_id)
        if text is None:
            status = 1
        print("%d\t%s" % (text_id, "(none)" if text is None else _printable(text)), file=out)
    return status


def _run_patch(command: str, folder: Path, env, out) -> int:
    if "WILDSTAR_CLIENT_EXE" not in env:
        print("client_files: WILDSTAR_CLIENT_EXE is not set: add it to env.sh (GENESIS_HOME/env.sh), as ./setup-check says", file=sys.stderr)
        return 1
    patch = extract_tables.patch_folder(env)
    if command == "extract":
        started = time.monotonic()
        parts = extract(patch, folder)
        for part in parts:
            print("%s: %s" % (part.archive, _counted(len(part.files), "file")), file=out)
        print("extracted into %s in %.0f seconds" % (folder, time.monotonic() - started), file=out)
        return 0
    found = changes(read_parts(patch), folder)
    if found is None:
        print("no copy in %s; run extract" % folder, file=out)
        return 1
    if not found:
        print("current", file=out)
        return 0
    print("stale: %s" % _counted(len(found), "difference"), file=out)
    for line in found[:SHOWN_CHANGES]:
        print(line, file=out)
    if len(found) > SHOWN_CHANGES:
        print("and %d more" % (len(found) - SHOWN_CHANGES), file=out)
    return 1


def main(argv: list[str], env, out=None) -> int:
    """Runs a command and returns the exit status."""
    out = out or sys.stdout
    parser = argparse.ArgumentParser(description="The client's UI files and texts.")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("extract")
    commands.add_parser("check")
    text = commands.add_parser("text")
    text.add_argument("ids", nargs="*", type=_text_id, help="decimal or 0x hex")
    text.add_argument("--search", nargs="+", metavar="word")
    arguments = parser.parse_args(argv)
    if arguments.command == "text" and bool(arguments.ids) == bool(arguments.search):
        parser.error("text takes ids, or --search and words, not both and not neither")
    try:
        folder = client_files_folder(env)
        if arguments.command == "text":
            return _run_text(arguments, folder, out)
        return _run_patch(arguments.command, folder, env, out)
    except (Refused, extract_tables.Corrupt) as refused:
        what = refused.name + ": " + refused.reason if isinstance(refused, extract_tables.Corrupt) else str(refused)
        print("client_files: refused %s" % what, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ))

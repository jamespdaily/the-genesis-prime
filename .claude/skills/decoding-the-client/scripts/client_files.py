"""The client's UI files and texts, read from the client's archives into a folder outside every git tree.

    python3.13 -I client_files.py extract
    python3.13 -I client_files.py check
    python3.13 -I client_files.py text <id>...
    python3.13 -I client_files.py text --search <word>...
    python3.13 -I client_files.py tokens --write [--list <path>]
    python3.13 -I client_files.py tokens --check [--list <path>]

Run with ~/.genesis-prime/env.sh read: WILDSTAR_CLIENT_EXE names the client, whose Patch folder (beside
Client64) holds ClientData.index/.archive and ClientDataEN.index/.archive. Both indexes must be build
16042; another build is refused, naming the index.

The folder is $GENESIS_CLIENT_FILES_DIR, else $GENESIS_HOME/client-files, else ~/.genesis-prime/client-files.
It is the client's data, so a folder inside this repository or any git working tree is refused. It is
replaced as a whole, so a folder that exists, holds something and has no state.json is refused: it is not
one this script made. A state.json that cannot be read is refused, naming the file; run extract.

extract   Writes every file under UI/ of ClientData (the forms, scripts and art the client's UI loads, about
          16,000 files and 1.8 GB) and en-US.bin of ClientDataEN (at the root of that index) into the
          folder, each file checked against the SHA-1 its index holds, as setup_check/extract_tables.py
          checks the game tables, then the whole staged set against the indexes' files and sizes, and
          swapped in whole (a run that fails leaves the folder as it was). About 20 seconds. Prints the
          file count of each part. state.json records each file's path in the archive, its index SHA-1 and
          the SHA-1 of its content as written, and each index's build. A second extract started while one
          runs is refused at once, naming the lock file (the folder's name and ".lock", left in place):
          the two would share one staging folder.
check     Reads both indexes and compares them with state.json and with the folder, hashing every file's
          content (about 2 seconds): exit 0 and "current"; exit 1 and each file that is new, gone, has
          another SHA-1 in the index, is missing, the wrong size, or is not the content extract wrote (the
          first 50), or "no copy". It changes nothing.
text      Prints `<id>\\t<text>` for each id given (decimal, leading zeros allowed, or 0x hex), in the order given; an id the file
          lacks prints `<id>\\t(none)` and the exit is 1. With --search, prints every text that holds all
          the words, ignoring case, in id order, then `N texts`. A newline, carriage return or tab inside
          a text prints as \\n, \\r or \\t. Without en-US.bin in the folder it says to run extract.
tokens    Lists the `$(kind=id.field)` tokens of every text a Spell4 tooltip column names (the seven columns
          localizedTextId ActionBarTooltip, CasterIconSpellText, PrimaryTargetIconSpellText,
          SecondaryTargetIconSpellText, TooltipCastInfo, TooltipCostInfo and LASTier), read from en-US.bin in
          the client-files folder and Spell4.tbl in the extracted tables folder (run extract, and
          setup_check/extract_tables.py, first). One tab-separated line per distinct token of a text, in text id
          order then first appearance, after the header `text_id<TAB>kind<TAB>id<TAB>field`: the kind and the
          field in lower case with their suffixes kept (data02rawint), an empty field for a token that names
          a spell, creature, item and so on without a value. The list holds ids and field names only, no
          English text, and defaults to test/fixture/tooltip_tokens/tokens.tsv (--list names another).
          --write writes it, and names each `$(` the client reads as no token (with its text id and why) as
          left out, exit 0. --check compares it with a fresh read: exit 0 and "current", or exit 1 and each
          text whose tokens differ (the first 50); with no list, or one with another header, exit 1.
          A `$(` is read as the client reads it, so a form the client never prints is no row and not an
          error: FormatTextTokens 0x1400c12b0 gives the text from `$(` to the first `)` to ReadParenToken
          0x1400b7780, which tries the kinds item, schematic, vitem, creature, achievement, bindpoint,
          keybinding, eff, spell, cc, smod, emod, thrsh and gf (ReadKindToken 0x1400b8010), each compared
          without case with `=` straight after (MatchWordAndNumber 0x1400b7f50); the id is read by wcstol
          (leading spaces skipped, 0 for no digits) and every evaluator refuses 0; the field is what follows
          the first `.`; a body that no kind matches is looked up as a named argument and prints nothing
          when unknown; a token with no `)` swallows the rest of the text. The forms left out are: no `)`; no
          kind; id 0; a field that holds whitespace (it runs over text to the next `)`, which the scan
          then skips too); an eff, cc, smod, emod, thrsh or gf token with no field.

The layout of en-US.bin is the fact file's language_file.layout: magic 'XETL'; at 0x40 the entry count
(u32), at 0x48 the entries' place (u64), at 0x50 the text's length in UTF-16 characters (u64), at 0x58 the
text's place (u64), both places counted from byte 0x60; entries of 8 bytes, a text id then the character
offset of its text, sorted by id; each text zero-terminated UTF-16LE. The client looks an id up by binary
search (GetLocalizedText 0x14034bdd0). The reader refuses, naming the reason, a file with another magic,
entries or text past its end, an offset past the text, ids not in order, or a unit that is not UTF-16.
"""

import argparse
import bisect
import contextlib
import fcntl
import hashlib
import json
import os
import re
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
from decompiled import Refused  # noqa: E402

STATE_FILE = "state.json"
LANGUAGE_FILE = "en-US.bin"  # the path in ClientDataEN's index: it sits at the root
UI_DIRECTORY = "UI/"
HEADER_END = 0x60
MAGIC = b"XETL"
SHOWN_CHANGES = 50
TABLE_MAGIC = b"LBTD"
# The column types of the fact file's game_table.column_type, by their size in a record.
COLUMN_SIZE = {3: 4, 4: 4, 11: 4, 20: 8, 130: 8}
TEXT_COLUMNS = [
    "localizedTextIdActionBarTooltip",
    "localizedTextIdCasterIconSpellText",
    "localizedTextIdPrimaryTargetIconSpellText",
    "localizedTextIdSecondaryTargetIconSpellText",
    "localizedTextIdTooltipCastInfo",
    "localizedTextIdTooltipCostInfo",
    "localizedTextIdLASTier",
]
TOKEN_OPEN = "$("
# The kinds ReadKindToken 0x1400b8010 tries: the ones that print a name need no field, a value kind needs one.
NAME_KINDS = ["item", "schematic", "vitem", "creature", "achievement", "bindpoint", "keybinding", "spell"]
VALUE_KINDS = ["eff", "cc", "smod", "emod", "thrsh", "gf"]
TOKEN_BODY = re.compile(
    r"(?P<kind>%s)=\s*(?P<id>[0-9]*)[^.]*(?:\.(?P<field>.*))?$" % "|".join(NAME_KINDS + VALUE_KINDS), re.IGNORECASE | re.DOTALL
)
TOKEN_HEADER = "text_id\tkind\tid\tfield"
TOKEN_LIST = check_facts.REPOSITORY / "test" / "fixture" / "tooltip_tokens" / "tokens.tsv"


@dataclass(frozen=True)
class Part:
    """The files taken from one archive: its name (ClientData), its index's build and the files by their
    path in the archive, which is also their path in the folder."""

    archive: str
    build: int
    files: dict[str, extract_tables.IndexedFile]


def client_files_folder(env) -> Path:
    """The folder named in the module's description; raises Refused for one inside a git tree."""
    return decompiled.outside_work_tree_folder(env, "GENESIS_CLIENT_FILES_DIR", "client-files", "the client's files")


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


def _state(parts: list[Part], written: dict[str, str]) -> dict:
    """What state.json holds: the builds, and per file its archive, its index SHA-1 and the SHA-1 of the
    content as written."""
    return {
        "builds": {part.archive: part.build for part in parts},
        "files": {
            path: {"archive": part.archive, "sha1": file.sha1.hex(), "content_sha1": written[path]}
            for part in parts
            for path, file in sorted(part.files.items())
        },
    }


def load_state(folder: Path) -> dict | None:
    """state.json of the folder, or None when there is none; raises Refused when it is not one extract wrote."""
    path = folder / STATE_FILE
    if not path.is_file():
        return None
    try:
        saved = json.loads(path.read_text())
        if not isinstance(saved["builds"], dict):
            raise TypeError("builds is not an object")
        for name, entry in saved["files"].items():
            for key in ("archive", "sha1", "content_sha1"):
                if not isinstance(entry[key], str):
                    raise TypeError("%s: %s is not text" % (name, key))
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as bad:
        raise Refused("%s cannot be read (%s); run extract" % (path, bad)) from None
    return saved


@contextlib.contextmanager
def _one_extract_at_a_time(folder: Path):
    """Holds an exclusive lock on the file beside folder for the block, or raises Refused when another
    extract holds it."""
    lock = folder.with_name(folder.name + ".lock")
    with open(lock, "a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Refused("another extract is running into %s (it holds %s); wait for it to end" % (folder, lock)) from None
        yield


def extract(patch: Path, folder: Path) -> list[Part]:
    """Fills folder as the module's description says; raises Corrupt naming the file or index that fails, or
    Refused for a folder that is not one this script made or one another extract is filling. The folder is as
    it was after any failure."""
    parts = read_parts(patch)
    folder.parent.mkdir(parents=True, exist_ok=True)
    with _one_extract_at_a_time(folder):
        if folder.exists() and any(folder.iterdir()) and not (folder / STATE_FILE).is_file():
            raise Refused("%s holds files and no %s: it is not a folder this script made, and it is replaced as a whole" % (folder, STATE_FILE))
        extract_tables.recover(folder)
        staging = extract_tables.staging_of(folder)
        staging.mkdir()
        try:
            written: dict[str, str] = {}
            for part in parts:
                written |= extract_tables.stage_files(patch / (part.archive + ".archive"), part.files, staging)
            extract_tables.verify_staged(staging, {path: file for part in parts for path, file in part.files.items()}, None)
            (staging / STATE_FILE).write_text(json.dumps(_state(parts, written), indent=0) + "\n")
            extract_tables.swap_whole(staging, folder)
        finally:
            shutil.rmtree(staging, ignore_errors=True)
    return parts


def changes(parts: list[Part], folder: Path) -> list[str] | None:
    """What differs between the indexes, state.json and the folder, one line each; None when there is no
    copy; an empty list when the copy is current."""
    saved = load_state(folder)
    if saved is None:
        return None
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
        entry = saved["files"][name]
        if entry["sha1"] != file.sha1.hex() or entry["archive"] != archive:
            found.append("%s has another SHA-1 in the index" % name)
        on_disk = folder / name
        if not on_disk.is_file():
            found.append("%s is missing from the folder" % name)
        elif on_disk.stat().st_size != file.size:
            found.append("%s is %d bytes in the folder, the index says %d" % (name, on_disk.stat().st_size, file.size))
        else:
            with open(on_disk, "rb") as content:
                if hashlib.file_digest(content, "sha1").hexdigest() != entry["content_sha1"]:
                    found.append("%s is not the content extract wrote" % name)
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
        return int(word, 16) if word[:2] in ("0x", "0X") else int(word, 10)
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


@dataclass(frozen=True)
class Token:
    """One `$(kind=id.field)` of a text: the kind and field in lower case, the id as written, and an empty field
    for a link."""

    kind: str
    id: int
    field: str

    def row(self, text_id: int) -> str:
        return "%d\t%s\t%d\t%s" % (text_id, self.kind, self.id, self.field)


def read_tokens(text: str) -> tuple[list[Token], list[tuple[str, str]]]:
    """The tokens of one text, each once, in the order they first appear, and the `$(` the client reads as no
    token, each as (why, the first 40 characters of its body), in order. A `$(` is read as the client's
    FormatTextTokens (0x1400c12b0, ReadParenToken 0x1400b7780) reads it: its body runs to the first `)`; the kind
    is one of the client's, compared without case, with `=` straight after; the id is read as wcstol reads it
    (leading spaces skipped, 0 when there are no digits); the field is what follows the first `.`. The client
    prints nothing for the forms it does not know, and the scan goes on after the `)`."""
    found: dict[Token, None] = {}
    irregular: list[tuple[str, str]] = []
    at = text.find(TOKEN_OPEN)
    while at != -1:
        close = text.find(")", at)
        if close == -1:
            irregular.append(("no closing parenthesis: the client reads the rest of the text as the token", text[at + 2 : at + 42]))
            break
        body = text[at + 2 : close]
        matched = TOKEN_BODY.match(body)
        if matched is None:
            irregular.append(("no kind of the client's and no id: the client looks the body up as a named argument", body[:40]))
        elif int(matched["id"] or 0) == 0:
            irregular.append(("the id is 0 or has no digits: every evaluator refuses it", body[:40]))
        else:
            kind, field = matched["kind"].lower(), matched["field"]
            if field is not None and any(character.isspace() for character in field):
                irregular.append(("the field runs over other text to the next `)`", body[:40]))
            elif kind == "eff" and field is None:
                # No '.', so EvaluateEffectToken (0x1404de8d0) gives no value; ReadKindToken (0x1400b8010) then tries
                # spell= with the same id, and FormatSpellTooltipToken (0x1404df2c0) with no '.' prints the spell's name.
                found[Token("spell", int(matched["id"]), "")] = None
            elif not field and kind in VALUE_KINDS:
                irregular.append(("an %s token with no field: the evaluator prints nothing" % kind, body[:40]))
            else:
                found[Token(kind, int(matched["id"]), (field or "").lower())] = None
        at = text.find(TOKEN_OPEN, close)
    return list(found), irregular


def spell4_text_ids(data: bytes) -> list[int]:
    """The ids the seven tooltip text columns of Spell4.tbl name, each once, ascending, without the 0 that means
    no text. The layout is the fact file's game_table.file and game_table.schema; raises Refused for a file that
    is not a game table, has a column or type this reader does not know, or lacks one of the seven columns.
    It mirrors src/genesis_prime/table/loader/tbl_file.gleam (layout) and the generated spell4.gleam (these seven
    columns are read signed, as every type 3 column not listed Unsigned in column_sign is); Python cannot call
    them, because `gleam run` recompiles, and the check lets only its gleam-build part compile (check, line 105)."""
    if len(data) < HEADER_END or data[:4] != TABLE_MAGIC:
        raise Refused("Spell4.tbl does not start %r" % TABLE_MAGIC)
    record_size, column_count, column_table, record_count, block_size, block_at = struct.unpack_from("<QQQQQQ", data, 0x18)
    body = data[HEADER_END:]
    names_at = column_table + (24 * column_count + 15) // 16 * 16
    if names_at > len(body) or block_at + block_size > len(body) or record_count * record_size > block_size:
        raise Refused("Spell4.tbl's columns or records run past the end of the file")
    where: dict[str, int] = {}
    place = 0
    for number in range(column_count):
        name_length, _, name_at, type_number = struct.unpack_from("<IIQH", body, column_table + 24 * number)
        if type_number not in COLUMN_SIZE:
            raise Refused("Spell4.tbl column %d has type %d, which this reader does not know" % (number, type_number))
        size = COLUMN_SIZE[type_number]
        place = (place + size - 1) // size * size
        start = names_at + name_at
        where[body[start : start + 2 * name_length - 2].decode("utf-16-le", errors="replace")] = place
        place += size
    for column in TEXT_COLUMNS:
        if column not in where:
            raise Refused("Spell4.tbl has no column %s" % column)
    ids: set[int] = set()
    for record in range(record_count):
        for column in TEXT_COLUMNS:
            (value,) = struct.unpack_from("<i", body, block_at + record * record_size + where[column])
            if value:
                ids.add(value)
    return sorted(ids)


def token_rows(env) -> tuple[list[str], list[str]]:
    """The list's lines after its header, for the texts the Spell4 tooltip columns name that en-US.bin has, in text
    id order, and a line for each `$(` the client reads as no token (text id, why, the start of its body)."""
    language_path = client_files_folder(env) / LANGUAGE_FILE
    table_path = extract_tables.table_folder(env) / "Spell4.tbl"
    if not language_path.is_file():
        raise Refused("no %s in %s; run extract" % (LANGUAGE_FILE, language_path.parent))
    if not table_path.is_file():
        raise Refused("no Spell4.tbl in %s; run python3.13 -I setup_check/extract_tables.py" % table_path.parent)
    language = read_language_file(language_path.read_bytes())
    rows, irregular = [], []
    for text_id in spell4_text_ids(table_path.read_bytes()):
        text = language.text(text_id)
        if text is not None:
            tokens, unread = read_tokens(text)
            rows.extend(token.row(text_id) for token in tokens)
            irregular.extend("text %d: %s: %s" % (text_id, why, _printable(start)) for why, start in unread)
    return rows, irregular


def _rows_by_text(lines: list[str]) -> dict[str, list[str]]:
    by_text: dict[str, list[str]] = {}
    for line in lines:
        by_text.setdefault(line.split("\t", 1)[0], []).append(line)
    return by_text


def _run_tokens(arguments, env, out) -> int:
    rows, irregular = token_rows(env)
    target = Path(arguments.list)
    if arguments.write:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("\n".join([TOKEN_HEADER, *rows]) + "\n")
        print("wrote %s: %s" % (target, _counted(len(rows), "row")), file=out)
        if irregular:
            print("%s the client reads as no token, left out:" % _counted(len(irregular), "form"), file=out)
            for line in irregular:
                print(line, file=out)
        return 0
    if not target.is_file():
        print("no list at %s; run tokens --write" % target, file=out)
        return 1
    committed = target.read_text().splitlines()
    if committed[:1] != [TOKEN_HEADER]:
        print("%s does not start with the header %r; run tokens --write" % (target, TOKEN_HEADER), file=out)
        return 1
    before, after = _rows_by_text(committed[1:]), _rows_by_text(rows)
    differing = sorted((before.keys() | after.keys()), key=int)
    differing = [text_id for text_id in differing if before.get(text_id) != after.get(text_id)]
    if not differing:
        print("current", file=out)
        return 0
    print("stale: %s with other tokens than the client's; run tokens --write" % _counted(len(differing), "text"), file=out)
    for text_id in differing[:SHOWN_CHANGES]:
        print("text %s: the list has %d, the client's file has %d" % (text_id, len(before.get(text_id, [])), len(after.get(text_id, []))), file=out)
    if len(differing) > SHOWN_CHANGES:
        print("and %d more" % (len(differing) - SHOWN_CHANGES), file=out)
    return 1


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
    tokens = commands.add_parser("tokens")
    action = tokens.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    tokens.add_argument("--list", default=str(TOKEN_LIST), metavar="path")
    arguments = parser.parse_args(argv)
    if arguments.command == "text" and bool(arguments.ids) == bool(arguments.search):
        parser.error("text takes ids, or --search and words, not both and not neither")
    try:
        if arguments.command == "tokens":
            return _run_tokens(arguments, env, out)
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

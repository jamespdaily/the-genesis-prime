"""Print the English text of each text id, from the client's en-US.bin.

The file holds a 96-byte header, then records of a 4-byte id and a 4-byte offset,
then UTF-16 strings; the header's four 8-byte values at 64 give the record count,
the records' offset, the strings' length and the strings' offset, and a record's
offset counts characters. A table's `localizedTextId...` columns hold these ids.

Usage: python3 -I english_text.py <text id> [<text id> ...]
"""
import struct
import sys
from pathlib import Path

TEXTS = Path.home() / "Coding/wildstar/client-data/ClientDataEN/en-US.bin"


def main():
    wanted = {int(arg) for arg in sys.argv[1:]}
    data = TEXTS.read_bytes()
    count, record_offset, _, string_offset = struct.unpack_from("<QQQQ", data, 64)
    for index in range(count):
        text_id, offset = struct.unpack_from("<II", data, 96 + record_offset + index * 8)
        if text_id in wanted:
            start = 96 + string_offset + offset * 2
            end = start
            while data[end:end + 2] != b"\0\0":
                end += 2
            print(text_id, data[start:end].decode("utf-16le"))


if __name__ == "__main__":
    main()

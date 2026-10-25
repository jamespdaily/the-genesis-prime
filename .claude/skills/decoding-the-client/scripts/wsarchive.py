"""Read WildStar .index/.archive pairs and extract files by path glob.

Usage: python3 -I wsarchive.py <patch folder> <glob> <out folder>
Each file lands at <out folder>/<index name>/<path in the archive>.
The game tables the server loads come from:
    python3 -I wsarchive.py ~/Coding/wildstar/client/WildStar/Patch 'db/*.tbl' ~/Coding/wildstar/client-data
"""
import fnmatch
import lzma
import mmap
import struct
import sys
import zlib
from pathlib import Path

AIDX, AARC = 0x41494458, 0x41415243


class Pack:
    """One PACK container: header, block table and root block."""

    def __init__(self, path):
        self.f = open(path, "rb")
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ)
        sig, ver = struct.unpack_from("<II", self.m, 0)
        if sig != 0x5041434B:
            raise ValueError(f"{path}: bad signature {sig:#x}")
        dh = 8 + 512
        _, _, table_off, block_count, root_idx, _ = struct.unpack_from("<QQQqqQ", self.m, dh)
        self.blocks = [struct.unpack_from("<QQ", self.m, table_off + i * 16) for i in range(block_count)]
        self.type, self.version = struct.unpack_from("<II", self.block(root_idx), 0)
        rb = self.block(root_idx)
        if self.version == 1:
            self.build, self.root_block = struct.unpack_from("<Ii", rb, 8)
            self.count = 0
        else:
            self.count, self.root_block = struct.unpack_from("<Ii", rb, 8)

    def block(self, i):
        off, size = self.blocks[i]
        return self.m[off:off + size]


class Index(Pack):
    """Folder tree of an index file."""

    def files(self, block=None, prefix=""):
        data = self.block(self.root_block if block is None else block)
        ndirs, nfiles = struct.unpack_from("<ii", data, 0)
        base = 8 + ndirs * 8 + nfiles * 56

        def name(off):
            end = data.index(b"\0", base + off)
            return data[base + off:end].decode("utf-8")

        p = 8
        dirs = []
        for _ in range(ndirs):
            noff, blk = struct.unpack_from("<Ii", data, p)
            dirs.append((name(noff), blk))
            p += 8
        for _ in range(nfiles):
            noff, flags, _, usize, csize = struct.unpack_from("<iIqqq", data, p)
            h = bytes(data[p + 32:p + 52])
            yield prefix + name(noff), flags, usize, csize, h
            p += 56
        for dname, blk in dirs:
            yield from self.files(blk, prefix + dname + "/")


class Archive(Pack):
    """Hash-addressed data blocks of an archive file."""

    def __init__(self, path):
        super().__init__(path)
        rb = self.block(self.root_block)
        self.by_hash = {}
        for i in range(self.count):
            blk = struct.unpack_from("<i", rb, i * 32)[0]
            self.by_hash[bytes(rb[i * 32 + 4:i * 32 + 24])] = blk

    def read(self, flags, usize, csize, h):
        raw = self.block(self.by_hash[h])
        if flags & 4:
            props = raw[:5]
            return lzma.decompress(props + struct.pack("<Q", usize) + raw[5:], format=lzma.FORMAT_ALONE)
        if flags & 2:
            try:
                return zlib.decompress(raw, -15)
            except zlib.error:
                return zlib.decompress(raw)
        return raw


def main():
    patch, pattern, out = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    for idx_path in sorted(patch.glob("*.index")):
        arc_path = idx_path.with_suffix(".archive")
        if not arc_path.exists():
            continue
        idx, arc = Index(idx_path), Archive(arc_path)
        n = 0
        for path, flags, usize, csize, h in idx.files():
            if not fnmatch.fnmatch(path.lower(), pattern.lower()):
                continue
            if h not in arc.by_hash:
                continue
            dest = out / idx_path.stem / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(arc.read(flags, usize, csize, h))
            n += 1
        print(f"{idx_path.name}: extracted {n} files matching {pattern}")


if __name__ == "__main__":
    main()

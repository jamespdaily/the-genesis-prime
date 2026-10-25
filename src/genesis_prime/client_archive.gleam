//// The client's archive indexes, the `.index` files in its `Patch` folder. The
//// server reads only an index whose build matches the one it is written for.

import gleam/bit_array

/// The client build this server is written against. Every archive index the
/// server reads must carry it.
pub const target_build = 16_042

/// Why an index's build could not be read.
pub type IndexError {
  /// The bytes do not start with an archive index's signature.
  NotAnIndex
  /// The index holds no block that names its build.
  NoBuildBlock
  /// The bytes end inside a header or block.
  Truncated
}

/// The build an archive index belongs to, read from its own header. The bytes
/// are a PACK container whose root block starts with an AIDX header; the build
/// is the third number in that header. Checks the client makes are made here
/// in the same order: PACK signature 0x5041434B (0x1401ba550) and version 1
/// (0x1401ba559), then the root block index below the block count (0x1401ba5c5)
/// and not 0, the block table entry at that index (16 bytes: file offset, size)
/// with a size of at least the 16-byte AIDX header (reader 0x1401b8600, length
/// 0x10 at 0x1401bf64c), then AIDX signature 0x41494458 (0x1401bf65c), version 1
/// (0x1401bf665) and the build at AIDX offset 8 (0x1401bf830).
pub fn build_of_index(bytes: BitArray) -> Result(Int, IndexError) {
  case bytes {
    <<signature:size(32)-little, version:size(32)-little, _:bits>> ->
      case signature == pack_signature && version == 1 {
        True -> read_pack(bytes)
        False -> Error(NotAnIndex)
      }
    _ -> Error(Truncated)
  }
}

const pack_signature = 0x5041434B

const aidx_signature = 0x41494458

const aidx_header_size = 16

fn read_pack(bytes: BitArray) -> Result(Int, IndexError) {
  case bytes {
    <<
      _:size(64),
      _:size(4096),
      _archive_end:size(64)-little,
      _:size(64),
      table_offset:size(64)-little,
      block_count:size(32)-little,
      _:size(32),
      root_index:size(32)-little,
      _:size(32),
      _:bits,
    >> ->
      case root_index == 0 || root_index >= block_count {
        True -> Error(NoBuildBlock)
        False -> read_root_entry(bytes, table_offset + root_index * 16)
      }
    _ -> Error(Truncated)
  }
}

fn read_root_entry(
  bytes: BitArray,
  entry_offset: Int,
) -> Result(Int, IndexError) {
  case bit_array.slice(bytes, entry_offset, 16) {
    Ok(<<offset:size(64)-little, size:size(64)-little>>) ->
      case size < aidx_header_size {
        True -> Error(NoBuildBlock)
        False -> read_root_block(from: bytes, at: offset, holding: size)
      }
    Ok(_) | Error(Nil) -> Error(Truncated)
  }
}

fn read_root_block(
  from bytes: BitArray,
  at offset: Int,
  holding size: Int,
) -> Result(Int, IndexError) {
  case bit_array.slice(bytes, offset, size) {
    Ok(<<
      signature:size(32)-little,
      version:size(32)-little,
      build:size(32)-little,
      _:size(32),
      _:bits,
    >>) ->
      case signature == aidx_signature && version == 1 {
        True -> Ok(build)
        False -> Error(NoBuildBlock)
      }
    Ok(_) | Error(Nil) -> Error(Truncated)
  }
}

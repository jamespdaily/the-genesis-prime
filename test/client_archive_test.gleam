//// The client's archive index and the build it carries. Expected values are
//// the fact file's record "archive_index.header": the PACK header checks at
//// 0x1401ba550 (signature) and 0x1401ba559 (version), the root block index
//// below the count at 0x1401ba5c5, the block reader 0x1401b8600 that refuses
//// index 0, an index at or past the count and a block of size 0, and the AIDX
//// header checks at 0x1401bf65c (signature) and 0x1401bf665 (version) with
//// the build at AIDX offset 8 (0x1401bf830). The client's own build, 16042
//// (0x3eaa), is the constant returned by GetVersionInfo at 0x1406f8360. Each
//// planted index is built in the test from defaults with one field changed.
//// The real indexes are the four in the client's Patch folder, read only
//// where the client is installed.

import envoy
import genesis_prime/client_archive
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

/// The fields of a planted index that a test changes. The header is 0x230
/// bytes, the block table starts at 0x240 and the AIDX block follows it.
type PlantedIndex {
  PlantedIndex(
    pack_signature: Int,
    pack_version: Int,
    root_index: Int,
    root_size: Int,
    aidx_signature: Int,
    aidx_version: Int,
    build: Int,
  )
}

/// Block count of every planted index; the real local indexes hold 3, 8680, 18
/// and 3 blocks, with the root at index 2 in the two small ones (fact file,
/// "archive_index.header").
const block_count = 3

const table_offset = 0x240

const block_offset = 0x270

/// PACK signature 0x5041434B at 0x1401ba550, the bytes "KCAP".
const pack_signature = 0x5041434B

/// AIDX signature 0x41494458 at 0x1401bf65c, the bytes "XDIA".
const aidx_signature = 0x41494458

fn well_formed() -> PlantedIndex {
  PlantedIndex(
    pack_signature: pack_signature,
    pack_version: 1,
    root_index: 2,
    root_size: 16,
    aidx_signature: aidx_signature,
    aidx_version: 1,
    build: client_archive.target_build,
  )
}

fn index_bytes(index: PlantedIndex) -> BitArray {
  let archive_end = block_offset + 16
  let header = <<
    index.pack_signature:size(32)-little,
    index.pack_version:size(32)-little,
    0:size(4096),
    archive_end:size(64)-little,
    0:size(64),
    table_offset:size(64)-little,
    block_count:size(32)-little,
    0:size(32),
    index.root_index:size(32)-little,
    0:size(32),
    0:size(128),
  >>
  let table =
    list.repeat(Nil, block_count)
    |> list.index_map(fn(_entry, position) {
      case position == index.root_index {
        True -> <<
          block_offset:size(64)-little,
          index.root_size:size(64)-little,
        >>
        False -> <<0:size(64), 0:size(64)>>
      }
    })
    |> bit_array.concat
  let block = <<
    index.aidx_signature:size(32)-little,
    index.aidx_version:size(32)-little,
    index.build:size(32)-little,
    1:size(32)-little,
  >>
  bit_array.concat([header, table, block])
}

fn cut(bytes: BitArray, at length: Int) -> BitArray {
  let assert Ok(kept) = bit_array.slice(bytes, 0, length)
    as "the planted index is shorter than the cut"
  kept
}

pub fn a_well_formed_index_gives_its_build_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_archive.build_of_index(index_bytes(well_formed())) == Ok(16_042)
    as "the build at AIDX offset 8 (0x1401bf830) of a 16042 index"
  let other = PlantedIndex(..well_formed(), build: 17_000)
  assert client_archive.build_of_index(index_bytes(other)) == Ok(17_000)
    as "the build at AIDX offset 8 (0x1401bf830) of a 17000 index"
}

pub fn the_target_build_is_the_clients_own_build_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_archive.target_build == 16_042
    as "GetVersionInfo 0x1406f8360 returns nBuildNumber 16042 (0x3eaa)"
}

pub fn a_wrong_pack_signature_is_not_an_index_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), pack_signature: 0x41434B50)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NotAnIndex)
    as "0x1401ba550 compares the signature with 0x5041434b"
}

pub fn a_pack_version_other_than_1_is_not_an_index_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), pack_version: 2)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NotAnIndex)
    as "0x1401ba559 compares the version with 1"
}

pub fn a_root_block_index_of_0_has_no_build_block_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), root_index: 0)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NoBuildBlock)
    as "0x1401b8600 refuses block index 0, even when its entry is valid"
}

pub fn a_root_block_index_equal_to_the_count_has_no_build_block_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), root_index: block_count)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NoBuildBlock)
    as "0x1401ba5c5 needs the root index below the count; 0x1401b8600 refuses an index at or past it"
}

pub fn a_root_block_of_size_0_has_no_build_block_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), root_size: 0)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NoBuildBlock)
    as "0x1401b8600 refuses a block of size 0"
}

pub fn a_root_block_of_size_8_has_no_build_block_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), root_size: 8)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NoBuildBlock)
    as "the AIDX header is 16 bytes (read of length 0x10 at 0x1401bf64c, in the reader 0x1401bf610), more than the block holds"
}

pub fn a_wrong_aidx_signature_has_no_build_block_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), aidx_signature: 0x58444941)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NoBuildBlock)
    as "0x1401bf65c compares the AIDX signature with 0x41494458"
}

pub fn an_aidx_version_other_than_1_has_no_build_block_test() -> Nil {
  use <- owned_test.run(5000)
  let planted = PlantedIndex(..well_formed(), aidx_version: 2)
  assert client_archive.build_of_index(index_bytes(planted))
    == Error(client_archive.NoBuildBlock)
    as "0x1401bf665 compares the AIDX version with 1"
}

pub fn bytes_that_end_inside_the_pack_header_are_truncated_test() -> Nil {
  use <- owned_test.run(5000)
  let bytes = cut(index_bytes(well_formed()), at: 0x100)
  assert client_archive.build_of_index(bytes) == Error(client_archive.Truncated)
    as "the PACK header is 0x230 bytes read at 0x1401b7caa"
}

pub fn bytes_that_end_inside_the_block_table_are_truncated_test() -> Nil {
  use <- owned_test.run(5000)
  let bytes = cut(index_bytes(well_formed()), at: table_offset + 40)
  assert client_archive.build_of_index(bytes) == Error(client_archive.Truncated)
    as "the table is block-count entries of 16 bytes, read at 0x1401b7d16; this one ends inside its third entry"
}

pub fn bytes_that_end_inside_the_aidx_block_are_truncated_test() -> Nil {
  use <- owned_test.run(5000)
  let bytes = cut(index_bytes(well_formed()), at: block_offset + 8)
  assert client_archive.build_of_index(bytes) == Error(client_archive.Truncated)
    as "the AIDX header is 16 bytes (0x1401bf64c); this one ends before its build and directory block"
}

pub fn each_real_index_in_the_client_gives_the_target_build_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.guard(envoy.get("GENESIS_NO_CLIENT") != Ok("1"))
  let executable =
    envoy.get("WILDSTAR_CLIENT_EXE")
    |> result_or(default_client_executable)
  let patch_folder =
    string.remove_suffix(executable, "/Client64/WildStar64.exe") <> "/Patch/"
  list.each(["Patch", "ClientData", "ClientDataEN", "Client64"], fn(name) {
    let path = patch_folder <> name <> ".index"
    let assert Ok(bytes) = simplifile.read_bits(path)
      as { "the client's index is missing or unreadable: " <> path }
    assert client_archive.build_of_index(bytes)
      == Ok(client_archive.target_build)
      as {
        name
        <> ".index: build "
        <> int.to_string(client_archive.target_build)
        <> " at AIDX offset 8 (fact file, archive_index.header, local files)"
      }
  })
}

/// The client's folder on Jim's machine, the same default as `check_support`
/// in the decoding-the-client skill's scripts.
const default_client_executable =
  "/Users/jimd/Coding/wildstar/client/WildStar/Client64/WildStar64.exe"

fn result_or(result: Result(String, Nil), default: String) -> String {
  case result {
    Ok(value) -> value
    Error(Nil) -> default
  }
}

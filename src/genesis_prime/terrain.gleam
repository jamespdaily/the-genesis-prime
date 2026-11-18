//// The ground's height at a place, read from the area files' height layers as the
//// client reads them. A `Ground` is one asset's loaded `.heights` files (the
//// extractor's folder: each file the client's own bytes of layer 0 of the 256 chunks
//// of one 512-unit square, 184,864 bytes), kept as the files' own binaries: they live
//// off every process's heap, and a lookup reads four 16-bit values out of one of them
//// and builds no list of heights.
////
//// ```
//// (x, z) ─▶ square_of ─▶ the area (row, column) ─▶ its file ─▶ the chunk's slot
////        ─▶ the cell's four corner values ─▶ blend ─▶ Ok(height) | Error(NoGround)
//// ```
////
//// - **The square.** Area column 64 + floor(x / 512) and the chunk column
////   floor(x / 32) modulo 16, likewise rows along z; a place outside -32768 to 32768
////   is in no area (area_file.cell, 0x1402dca80, 0x14036d040).
//// - **The chunk.** Slot row * 16 + column; a slot the file holds no chunk of has no
////   ground (0x1402df8a0). A chunk with no layer 0 holds the client's shared default,
////   every value 0x1fff, which is a terrain of -1024.09 under whatever the chunk holds;
////   the server has none of the objects, so such a chunk answers `NoLayer`, and the file
////   keeps the client's bytes (0x140c41340).
//// - **The cell.** floor(fraction * 16) of the chunk's 32 units, at most 15; the
////   corners are vertices (cx, cz), (cx + 1, cz), (cx, cz + 1) and (cx + 1, cz + 1) at
////   byte (z + 1) * 38 + (x + 1) * 2 of the chunk's 722 (0x140c41340, 0x1402da040).
//// - **A vertex's height.** Its low 15 bits times 4096 / 32767, less 2048; bit 15 of the
////   cell's low corner marks the cell as a hole (0x14037d790, 0x140386280).
//// - **The blend.** The cell's centre is the mean of its two diagonal pairs, each pair
////   weighted by 1 / (its own difference squared + 1); the height is the centre plus a
////   slope in each of the four triangles round it (0x14037d790). It is computed in 64-bit
////   floats where the client rounds each step to 32 bits: the two agree to the noise of
////   a 32-bit float, and across a cell's edge the blend is continuous.
////
//// The terrain alone is answered: the client's rule that a unit's ground counts the
//// terrain only at or below 2 above the unit, and the collision objects, are not here
//// (0x140386280).

import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// One asset's loaded ground files, by area: key `row * 128 + column` of the area's
/// row and column (each 0 to 127).
pub type Ground {
  Ground(areas: Dict(Int, Area))
}

/// One area's ground file: `file` is its bytes whole, `usable` a 32-byte presence mask
/// of the chunks that have a layer 0 of their own (the file's presence mask with the
/// chunks that hold the client's shared default cleared).
pub type Area {
  Area(usable: BitArray, file: BitArray)
}

/// Why a place has no ground: it is outside the world's 128 by 128 areas, its area has
/// no file, its chunk is not in the file, its chunk has no layer 0, or its cell is a
/// hole.
pub type NoGround {
  OutsideTheWorld
  NoFile
  NoChunk
  NoLayer
  Hole
}

/// The size of a `.heights` file: a 32-byte presence mask and 256 chunks of 722 bytes.
const file_size = 184_864

const mask_size = 32

const chunk_size = 722

/// A chunk's row: 19 vertices of 2 bytes.
const row_size = 38

/// The ground with no area.
pub fn empty() -> Ground {
  Ground(areas: dict.new())
}

/// The ground with this file's area at the row and column, in place of any area it had.
pub fn with_area(
  ground ground: Ground,
  row row: Int,
  column column: Int,
  area area: Area,
) -> Ground {
  Ground(areas: dict.insert(ground.areas, area_key(row:, column:), area))
}

/// The key of the area at a row and column in `Ground.areas`.
fn area_key(row row: Int, column column: Int) -> Int {
  row * 128 + column
}

/// The area of a `.heights` file's bytes, or an error when they are not exactly the
/// size of one.
pub fn area_from_file(bytes: BitArray) -> Result(Area, Nil) {
  use <- bool.guard(bit_array.byte_size(bytes) != file_size, Error(Nil))
  let default = default_layer()
  let usable =
    int.range(from: 0, to: 256, with: 0, run: fn(usable, slot) {
      case
        holds_a_chunk(bytes, slot)
        && !holds_the_default(bytes:, slot:, default:)
      {
        True -> usable + int.bitwise_shift_left(1, slot)
        False -> usable
      }
    })
  Ok(Area(usable: <<usable:size(256)-little>>, file: bytes))
}

/// The client's shared layer 0: 361 values of 0x1fff (0x140c41340).
fn default_layer() -> BitArray {
  bit_array.concat(list.repeat(<<0x1fff:16-little>>, 361))
}

fn holds_the_default(
  bytes bytes: BitArray,
  slot slot: Int,
  default default: BitArray,
) -> Bool {
  bit_array.slice(bytes, mask_size + chunk_size * slot, chunk_size)
  == Ok(default)
}

/// Whether the mask's bit for the slot is set: bit (slot % 8) of byte (slot / 8).
fn holds_a_chunk(mask: BitArray, slot: Int) -> Bool {
  let byte = slot / 8
  case mask {
    <<_:bytes-size(byte), held, _:bytes>> ->
      int.bitwise_and(held, int.bitwise_shift_left(1, slot % 8)) != 0
    _ -> False
  }
}

/// The area's row and column holding the place: 64 + floor(z / 512) and 64 + floor(x /
/// 512) (area_file.cell), or an error when the place is outside -32768 to 32768 in x or
/// z, where a row or column is not 0 to 127 (0x1402dca80).
pub fn square_of(x x: Float, z z: Float) -> Result(#(Int, Int), Nil) {
  use <- bool.guard(!{ inside_the_world(x) && inside_the_world(z) }, Error(Nil))
  Ok(#(64 + area_and_index(chunk_of(z)).0, 64 + area_and_index(chunk_of(x)).0))
}

fn inside_the_world(coordinate: Float) -> Bool {
  coordinate >=. -32_768.0 && coordinate <. 32_768.0
}

/// The index of the 32-unit chunk a coordinate is in, counted from 0 at the origin.
fn chunk_of(coordinate: Float) -> Int {
  float.truncate(float.floor(coordinate /. 32.0))
}

/// Which area (counted from the one holding the origin, negative below it) a chunk index
/// is in, and the chunk's place among the area's 16 along that axis.
fn area_and_index(chunk: Int) -> #(Int, Int) {
  let assert Ok(area) = int.floor_divide(chunk, 16) as "16 is not zero"
  let assert Ok(index) = int.modulo(chunk, 16) as "16 is not zero"
  #(area, index)
}

/// The ground's height at the place, whatever stands on it, or why there is none.
pub fn height_at(
  ground ground: Ground,
  x x: Float,
  z z: Float,
) -> Result(Float, NoGround) {
  use #(row, column) <- result.try(result.replace_error(
    square_of(x:, z:),
    OutsideTheWorld,
  ))
  use area <- result.try(result.replace_error(
    dict.get(ground.areas, area_key(row:, column:)),
    NoFile,
  ))
  let chunk_x = chunk_of(x)
  let chunk_z = chunk_of(z)
  let slot = area_and_index(chunk_z).1 * 16 + area_and_index(chunk_x).1
  use <- bool.guard(
    !holds_a_chunk(area.usable, slot),
    Error(case holds_a_chunk(area.file, slot) {
      True -> NoLayer
      False -> NoChunk
    }),
  )
  let #(cell_x, across) = cell_of(x /. 32.0 -. int.to_float(chunk_x))
  let #(cell_z, down) = cell_of(z /. 32.0 -. int.to_float(chunk_z))
  let chunk_start = mask_size + chunk_size * slot
  let vertex = { cell_z + 1 } * row_size + { cell_x + 1 } * 2
  let offset = chunk_start + vertex
  case corners(area.file, offset) {
    Ok(#(low, low_x, low_z, high)) ->
      case int.bitwise_and(low, 0x8000) {
        0 -> Ok(blend(low:, low_x:, low_z:, high:, across:, down:))
        _ -> Error(Hole)
      }
    Error(Nil) -> Error(NoChunk)
  }
}

/// A coordinate's cell and its fraction across the cell, from its fraction of the
/// chunk: floor(fraction * 16), at most 15.
fn cell_of(fraction: Float) -> #(Int, Float) {
  let cell = int.min(float.truncate(float.floor(fraction *. 16.0)), 15)
  #(cell, fraction *. 16.0 -. int.to_float(cell))
}

/// The raw values of the cell's corners (low, one step in x, one step in z, both) at
/// the byte offset of its low corner.
fn corners(file: BitArray, offset: Int) -> Result(#(Int, Int, Int, Int), Nil) {
  let next = offset + row_size
  case file {
    <<_:bytes-size(offset), low:16-little, low_x:16-little, _:bytes>> ->
      case file {
        <<_:bytes-size(next), low_z:16-little, high:16-little, _:bytes>> ->
          Ok(#(low, low_x, low_z, high))
        _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

/// A raw value's height: its low 15 bits times 4096 / 32767, less 2048 (0x14037d790).
fn height_of(raw: Int) -> Float {
  int.to_float(int.bitwise_and(raw, 0x7fff)) *. { 4096.0 /. 32_767.0 } -. 2048.0
}

/// The height inside a cell at the fraction `across` in x and `down` in z of its
/// width, from its four corners' raw values (0x14037d790).
fn blend(
  low low: Int,
  low_x low_x: Int,
  low_z low_z: Int,
  high high: Int,
  across across: Float,
  down down: Float,
) -> Float {
  let h00 = height_of(low)
  let h10 = height_of(low_x)
  let h01 = height_of(low_z)
  let h11 = height_of(high)
  let along_x = h00 -. h11
  let along_z = h10 -. h01
  let weight_x = 1.0 /. { along_x *. along_x +. 1.0 }
  let weight_z = 1.0 /. { along_z *. along_z +. 1.0 }
  let centre =
    { { h00 +. h11 } *. weight_x +. { h10 +. h01 } *. weight_z }
    *. { 0.5 /. { weight_x +. weight_z } }
  // The four triangles meet at the centre: u runs along the h00-h11 diagonal, v along
  // the h10-h01 one.
  let along_u = across +. down -. 1.0
  let along_v = down -. across
  let slope_u = case along_u >=. 0.0 {
    True -> h11 -. centre
    False -> centre -. h00
  }
  let slope_v = case along_v >=. 0.0 {
    True -> h01 -. centre
    False -> centre -. h10
  }
  centre +. slope_u *. along_u +. slope_v *. along_v
}

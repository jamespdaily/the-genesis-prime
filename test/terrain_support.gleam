//// What the tests of the ground share: a `.heights` file written from vertex
//// functions (the layout the ground files hold, dev/terrain_extract.py's header),
//// a ground built from such files, a reader that answers flat ground, and a
//// planted terrain folder.

import client_tables
import envoy
import genesis_prime/content/terrain as content_terrain
import genesis_prime/table/loader/store
import genesis_prime/table/world
import genesis_prime/terrain.{type Ground}
import genesis_prime/world_map/spawn
import gleam/bit_array
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import planted_table
import simplifile

/// The size of a `.heights` file: a 32-byte presence mask and 256 chunks of 722 bytes.
pub const file_size = 184_864

/// The raw value of a flat chunk: any value without the hole bit will do.
pub const flat_raw = 16_384

/// The client's height of one raw unit, 4096 / 32767 (0x14037d790, the float at
/// 0x140c41b9c).
pub fn step() -> Float {
  4096.0 /. 32_767.0
}

/// The height of a raw value: its low 15 bits times the step, less 2048
/// (0x14037d790).
pub fn height(raw raw: Int) -> Float {
  int.to_float(int.bitwise_and(raw, 0x7fff)) *. step() -. 2048.0
}

/// The ints from one to the other, both included.
pub fn span(from from: Int, to to: Int) -> List(Int) {
  int.range(from:, to: to + 1, with: [], run: list.prepend) |> list.reverse
}

/// A raw value of one vertex of a chunk as a function of the vertex's column and
/// row, each from -1 to 17.
pub type Vertices =
  fn(Int, Int) -> Int

/// A `.heights` file whose chunks are the slots given with the vertex function of
/// each: the presence bit of every given slot is set and every other slot is zeros.
pub fn file(chunks: List(#(Int, Vertices))) -> BitArray {
  let mask =
    list.map(span(from: 0, to: 31), fn(byte) {
      let bits =
        list.fold(span(from: 0, to: 7), 0, fn(bits, bit) {
          case list.key_find(chunks, byte * 8 + bit) {
            Ok(_) -> bits + int.bitwise_shift_left(1, bit)
            Error(Nil) -> bits
          }
        })
      <<bits>>
    })
  let slots =
    list.map(span(from: 0, to: 255), fn(slot) {
      case list.key_find(chunks, slot) {
        Ok(vertices) -> chunk(vertices)
        Error(Nil) -> <<0:size(5776)>>
      }
    })
  bit_array.concat([bit_array.concat(mask), ..slots])
}

/// One chunk's 19 by 19 little-endian 16-bit values, the rows along z.
fn chunk(vertices: Vertices) -> BitArray {
  list.flat_map(span(from: -1, to: 17), fn(row) {
    list.map(span(from: -1, to: 17), fn(column) {
      <<vertices(column, row):16-little>>
    })
  })
  |> bit_array.concat
}

/// The vertices of a chunk that holds the same raw value everywhere.
pub fn uniform(raw raw: Int) -> Vertices {
  fn(_, _) { raw }
}

/// A file with every slot present and holding the same raw value everywhere.
pub fn uniform_file(raw raw: Int) -> BitArray {
  file(list.map(span(from: 0, to: 255), fn(slot) { #(slot, uniform(raw:)) }))
}

/// A file with every slot present and flat.
pub fn flat_file() -> BitArray {
  uniform_file(raw: flat_raw)
}

/// Whether an answer is the height of a raw value to within 1e-6, the noise of the
/// blend's arithmetic.
pub fn is_height_of(
  found found: Result(Float, terrain.NoGround),
  raw raw: Int,
) -> Bool {
  result.map(found, float.loosely_equals(
    _,
    with: height(raw:),
    tolerating: 1.0e-6,
  ))
  == Ok(True)
}

/// The `Ground` of these files, each at an area's row and column.
pub fn ground_of(files: List(#(Int, Int, BitArray))) -> Ground {
  list.fold(files, terrain.empty(), fn(ground, held) {
    let #(row, column, bytes) = held
    let assert Ok(area) = terrain.area_from_file(bytes)
      as "a planted file is a whole ground file"
    terrain.with_area(ground:, row:, column:, area:)
  })
}

/// The `Ground` of one file at area (64, 64), the one holding the origin.
pub fn ground_at_origin(file file: BitArray) -> Ground {
  ground_of([#(64, 64, file)])
}

/// The slot, in its area's file, of the 32-unit chunk holding the place: the chunk's
/// row along z times 16 plus its column along x, each counted from the area's own
/// start (`terrain.height_at`).
pub fn slot_of(x x: Float, z z: Float) -> Int {
  let assert Ok(column) = int.modulo(chunk_of(x), 16) as "16 is not zero"
  let assert Ok(row) = int.modulo(chunk_of(z), 16) as "16 is not zero"
  row * 16 + column
}

fn chunk_of(coordinate: Float) -> Int {
  float.truncate(float.floor(coordinate /. 32.0))
}

/// A ground with a chunk of one raw value everywhere at each place given (x, z, raw),
/// and no file or chunk anywhere else.
pub fn ground_with_chunks(chunks chunks: List(#(Float, Float, Int))) -> Ground {
  let held =
    list.map(chunks, fn(chunk) {
      let #(x, z, raw) = chunk
      let assert Ok(square) = terrain.square_of(x:, z:)
        as "a planted chunk is inside the world"
      #(square, #(slot_of(x:, z:), uniform(raw:)))
    })
  list.unique(list.map(held, fn(each) { each.0 }))
  |> list.map(fn(square) {
    #(
      square.0,
      square.1,
      file(
        list.filter_map(held, fn(each) {
          case each.0 == square {
            True -> Ok(each.1)
            False -> Error(Nil)
          }
        }),
      ),
    )
  })
  |> ground_of
}

/// A reader that answers flat ground for each square it is asked, with the chunks at
/// the places given (x, z, raw) holding their raw value instead.
pub fn reader_with_chunks(
  chunks chunks: List(#(Float, Float, Int)),
) -> content_terrain.Reader {
  fn(_asset, squares) {
    Ok(
      ground_of(
        list.map(squares, fn(square: #(Int, Int)) {
          let own =
            list.filter_map(chunks, fn(chunk) {
              let #(x, z, raw) = chunk
              case terrain.square_of(x:, z:) == Ok(square) {
                True -> Ok(#(slot_of(x:, z:), uniform(raw:)))
                False -> Error(Nil)
              }
            })
          let flat_slots =
            list.filter_map(span(from: 0, to: 255), fn(slot) {
              case list.key_find(own, slot) {
                Ok(_) -> Error(Nil)
                Error(Nil) -> Ok(#(slot, uniform(raw: flat_raw)))
              }
            })
          #(square.0, square.1, file(list.append(own, flat_slots)))
        }),
      ),
    )
  }
}

/// A reader that answers flat ground for exactly the squares it is asked, whatever
/// the asset.
pub fn flat_reader() -> content_terrain.Reader {
  let flat = flat_file()
  fn(_asset, squares) {
    Ok(
      ground_of(
        list.map(squares, fn(square: #(Int, Int)) {
          #(square.0, square.1, flat)
        }),
      ),
    )
  }
}

/// A reader that answers what `flat_reader` does except for the squares it drops.
pub fn flat_reader_without(
  dropped dropped: List(#(Int, Int)),
) -> content_terrain.Reader {
  let flat = flat_reader()
  fn(asset, squares) {
    flat(
      asset,
      list.filter(squares, fn(square) { !list.contains(dropped, square) }),
    )
  }
}

/// The name a ground file of the area at this row and column has: both as two
/// lower-case hex digits.
pub fn file_name(row row: Int, column column: Int) -> String {
  hex(row) <> hex(column) <> ".heights"
}

fn hex(number: Int) -> String {
  string.pad_start(string.lowercase(int.to_base16(number)), to: 2, with: "0")
}

/// Makes a folder of its own, writes each file into it under its path inside the
/// folder (`Western/3447.heights`), runs the body with the folder's path and
/// removes the folder afterwards.
pub fn planted_folder(
  files files: List(#(String, BitArray)),
  body body: fn(String) -> a,
) -> a {
  planted_table.with_folder(
    result.unwrap(envoy.get("TMPDIR"), "/tmp"),
    fn(folder) {
      list.each(files, fn(file) {
        let path = folder <> "/" <> file.0
        let assert Ok(Nil) = simplifile.create_directory_all(parent(path))
          as "the planted folder's directory could not be made"
        let assert Ok(Nil) = simplifile.write_bits(path, file.1)
          as "the planted file could not be written"
      })
      body(folder)
    },
  )
}

fn parent(path: String) -> String {
  string.join(
    list.reverse(list.drop(list.reverse(string.split(path, "/")), 1)),
    "/",
  )
}

/// A planted folder with a flat file for every square the rows stand in, in the
/// asset of each row's world, so the server's own start finds ground for every
/// spawn.
pub fn flat_folder_for(
  rows rows: List(spawn.Row),
  tables tables: store.Tables,
  body body: fn(String) -> a,
) -> a {
  let flat = flat_file()
  let files =
    list.flat_map(world.all(tables), fn(row) {
      let squares =
        rows
        |> list.filter(fn(spawn_row) { spawn_row.world_id == row.id })
        |> list.filter_map(fn(spawn_row) {
          terrain.square_of(x: spawn_row.x, z: spawn_row.z)
        })
        |> list.unique
      list.map(squares, fn(square) {
        #(
          content_terrain.asset(world: row)
            <> "/"
            <> file_name(row: square.0, column: square.1),
          flat,
        )
      })
    })
    |> dict.from_list
    |> dict.to_list
  planted_folder(files:, body:)
}

/// The folder the real ground files are in: `GENESIS_TERRAIN_DIR`, else
/// `GENESIS_HOME/terrain`, else `~/.genesis-prime/terrain`.
pub fn real_folder() -> String {
  case envoy.get("GENESIS_TERRAIN_DIR") {
    Ok(folder) -> folder
    Error(Nil) -> {
      let home = case envoy.get("GENESIS_HOME") {
        Ok(home) -> home
        Error(Nil) -> result.unwrap(envoy.get("HOME"), "") <> "/.genesis-prime"
      }
      home <> "/terrain"
    }
  }
}

/// Whether the client is installed and the real ground folder exists: a machine
/// without them skips the tests of the real files.
pub fn real_folder_present() -> Bool {
  client_tables.present() && simplifile.is_directory(real_folder()) == Ok(True)
}

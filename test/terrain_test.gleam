//// The ground's height at a place (`genesis_prime/terrain.height_at`), read from the
//// ground files' raw vertices as the client reads them. The expected values are the
//// client's formula worked by hand, never a call of the code under test:
//// - a vertex's height is its low 15 bits times 4096 / 32767, less 2048; bit 15 of
////   a cell's low corner marks the cell as a hole (0x14037d790, 0x140386280,
////   0x1402da040);
//// - a cell's centre is the mean of its two diagonal pairs, each pair weighted by
////   1 / (its own difference squared + 1), and the place's height is the centre
////   plus a slope in each of the four triangles round it (0x14037d790);
//// - the area, the chunk and the cell a place stands in: area column 64 + floor(x /
////   512), chunk floor(x / 32), cell floor(fraction * 16), vertices at byte
////   (z + 1) * 38 + (x + 1) * 2 of the chunk's 722 (0x140c41340, area_file.ground_height,
////   0x14036d040, 0x1402dca80);
//// - a chunk the area file skips has no ground (0x1402df8a0), and a chunk with no
////   layer 0 reads the client's shared default of 361 values 0x1fff (0x1402e5c40).

import genesis_prime/terrain.{type NoGround}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import owned_test
import qcheck
import terrain_support

/// The raw value of a plane through the origin vertex: `base` at vertex (0, 0),
/// `a` more for each column and `b` more for each row.
fn plane(base base: Int, a a: Int, b b: Int) -> terrain_support.Vertices {
  fn(column, row) { base + a * column + b * row }
}

/// The height of that plane at vertex coordinates (vertices are 2 units apart).
fn plane_height(
  base base: Int,
  a a: Int,
  b b: Int,
  column column: Float,
  row row: Float,
) -> Float {
  terrain_support.height(raw: base)
  +. terrain_support.step()
  *. { int.to_float(a) *. column +. int.to_float(b) *. row }
}

fn close(got: Float, wanted: Float) -> Bool {
  float.loosely_equals(got, with: wanted, tolerating: 1.0e-6)
}

fn height_at(ground ground: terrain.Ground, x x: Float, z z: Float) -> Float {
  let assert Ok(found) = terrain.height_at(ground:, x:, z:)
    as "the place has ground"
  found
}

pub fn a_plane_of_vertices_reads_back_as_the_plane_test() -> Nil {
  use <- owned_test.run(60_000)
  qcheck.given(
    qcheck.tuple5(
      qcheck.bounded_int(from: 2000, to: 30_000),
      qcheck.bounded_int(from: -40, to: 40),
      qcheck.bounded_int(from: -40, to: 40),
      qcheck.bounded_float(from: 0.0, to: 31.999),
      qcheck.bounded_float(from: 0.0, to: 31.999),
    ),
    fn(drawn) {
      let #(base, a, b, x, z) = drawn
      let ground =
        terrain_support.ground_at_origin(
          terrain_support.file([#(0, plane(base:, a:, b:))]),
        )
      assert close(
        height_at(ground:, x:, z:),
        plane_height(base:, a:, b:, column: x /. 2.0, row: z /. 2.0),
      )
        as "a plane's four triangles and diagonal means are the plane (0x14037d790), the rows along z (0x140c41340)"
    },
  )
}

/// Raw values below this keep the slope of any grid under 300 units per unit, so a
/// step of 1e-9 moves the height by under 1e-6.
const gentle = 2047

pub fn a_cell_edge_reads_the_same_from_both_cells_test() -> Nil {
  use <- owned_test.run(120_000)
  qcheck.given(
    qcheck.tuple5(
      qcheck.fixed_length_list_from(
        qcheck.bounded_int(from: 0, to: gentle),
        35 * 35,
      ),
      qcheck.bounded_int(from: 1, to: 31),
      qcheck.bounded_int(from: 1, to: 31),
      qcheck.bounded_float(from: 0.0, to: 63.9),
      qcheck.bounded_float(from: 0.0, to: 63.9),
    ),
    fn(drawn) {
      let #(values, edge_column, edge_row, x, z) = drawn
      let ground = four_chunks(values)
      let column_edge = int.to_float(edge_column * 2)
      let row_edge = int.to_float(edge_row * 2)
      assert close(
        height_at(ground:, x: column_edge, z:),
        height_at(ground:, x: column_edge -. 1.0e-9, z:),
      )
        as "the cells either side of a column edge read the same on it: at the edge the triangle is the linear read of its two corners (0x14037d790), also at the border of two chunks"
      assert close(
        height_at(ground:, x:, z: row_edge),
        height_at(ground:, x:, z: row_edge -. 1.0e-9),
      )
        as "the cells either side of a row edge read the same on it"
    },
  )
}

/// Four chunks (slots 0, 1, 16 and 17: two columns by two rows) whose shared border
/// vertices hold the same value, from `values`, one for each vertex from -1 to 33
/// across and down, as the real files do.
fn four_chunks(values: List(Int)) -> terrain.Ground {
  let by_vertex =
    dict.from_list(list.index_map(values, fn(raw, at) { #(at, raw) }))
  let chunk = fn(slot: Int) {
    #(slot, fn(column, row) {
      let across = slot % 16 * 16 + column
      let down = slot / 16 * 16 + row
      let assert Ok(raw) = dict.get(by_vertex, { down + 1 } * 35 + across + 1)
        as "the grid holds a value for every vertex of the four chunks"
      raw
    })
  }
  terrain_support.ground_at_origin(
    terrain_support.file([chunk(0), chunk(1), chunk(16), chunk(17)]),
  )
}

pub fn a_hole_bit_marks_only_the_cell_it_is_the_low_corner_of_test() -> Nil {
  use <- owned_test.run(120_000)
  qcheck.given(
    qcheck.tuple3(
      qcheck.fixed_length_list_from(
        qcheck.bounded_int(from: 0, to: 32_767),
        19 * 19,
      ),
      qcheck.bounded_int(from: -1, to: 17),
      qcheck.bounded_int(from: -1, to: 17),
    ),
    fn(drawn) {
      let #(values, hole_column, hole_row) = drawn
      let by_vertex =
        dict.from_list(list.index_map(values, fn(raw, at) { #(at, raw) }))
      let raw_at = fn(column, row) {
        let assert Ok(raw) = dict.get(by_vertex, { row + 1 } * 19 + column + 1)
          as "the grid holds a value for every vertex"
        raw
      }
      let plain =
        terrain_support.ground_at_origin(terrain_support.file([#(0, raw_at)]))
      let holed =
        terrain_support.ground_at_origin(
          terrain_support.file([
            #(0, fn(column, row) {
              case column == hole_column && row == hole_row {
                True -> int.bitwise_or(raw_at(column, row), 0x8000)
                False -> raw_at(column, row)
              }
            }),
          ]),
        )
      list.each(terrain_support.span(from: 0, to: 15), fn(cell_row) {
        list.each(terrain_support.span(from: 0, to: 15), fn(cell_column) {
          let is_the_hole = cell_column == hole_column && cell_row == hole_row
          the_cell_reads_as_a_hole_or_as_the_plain_grid(
            holed:,
            plain:,
            is_the_hole:,
            at_cell: #(cell_column, cell_row),
          )
        })
      })
    },
  )
}

/// The centre of the cell: a hole where the bit sits, otherwise what the grid without the
/// bit reads.
fn the_cell_reads_as_a_hole_or_as_the_plain_grid(
  holed holed: terrain.Ground,
  plain plain: terrain.Ground,
  is_the_hole is_the_hole: Bool,
  at_cell cell: #(Int, Int),
) -> Nil {
  let across = int.to_float(cell.0 * 2) +. 1.0
  let down = int.to_float(cell.1 * 2) +. 1.0
  let found = terrain.height_at(ground: holed, x: across, z: down)
  case is_the_hole {
    True -> {
      assert found == Error(terrain.Hole)
        as "the cell whose low-x, low-z corner has bit 15 is a hole (0x140386280)"
      Nil
    }
    False -> {
      assert found == terrain.height_at(ground: plain, x: across, z: down)
        as "every other cell reads the low 15 bits of its corners (0x1402da040)"
      Nil
    }
  }
}

pub fn a_place_outside_the_world_has_no_ground_test() -> Nil {
  use <- owned_test.run(60_000)
  qcheck.given(
    qcheck.tuple4(
      qcheck.bool(),
      qcheck.bool(),
      qcheck.bounded_float(from: 0.0, to: 1_000_000.0),
      qcheck.bounded_float(from: -40_000.0, to: 40_000.0),
    ),
    fn(drawn) {
      let #(past_the_high_side, on_the_x_axis, beyond, other) = drawn
      let outside = case past_the_high_side {
        True -> 32_768.0 +. beyond
        False -> -32_768.0001 -. beyond
      }
      let #(x, z) = case on_the_x_axis {
        True -> #(outside, other)
        False -> #(other, outside)
      }
      assert terrain.height_at(ground: terrain.empty(), x:, z:)
        == Error(terrain.OutsideTheWorld)
        as "a place beyond -32768 to 32768 in x or z is in no area file (0x1402dca80: a digit pair is at most 0x80; 0x14036d040: 2048 chunks of 32)"
    },
  )
  qcheck.given(
    qcheck.tuple2(
      qcheck.bounded_float(from: -32_768.0, to: 32_767.999),
      qcheck.bounded_float(from: -32_768.0, to: 32_767.999),
    ),
    fn(drawn) {
      let #(x, z) = drawn
      assert terrain.height_at(ground: terrain.empty(), x:, z:)
        == Error(terrain.NoFile)
        as "a place inside the world with no area file loaded has no answer (0x14036d040)"
    },
  )
}

/// One row of the blend table: the files of the ground (area row, area column,
/// bytes), the place asked and what the client's formula gives there.
type Case {
  Case(
    name: String,
    files: List(#(Int, Int, BitArray)),
    place: #(Float, Float),
    expected: Result(Float, NoGround),
  )
}

/// The cell at vertices (3, 5) of slot 0: h00 = h10 = b, h01 = b + e, h11 = b + d,
/// with h01 = h00 + `rise_z` (32 raw units, 4.0001) and h11 = h00 + `rise_diagonal` (64 raw units,
/// 8.0002), so no two corners,
/// triangles or pairings of weights give the same answer.
fn one_cell() -> BitArray {
  terrain_support.file([
    #(0, fn(column, row) {
      case column, row {
        3, 6 -> terrain_support.flat_raw + 32
        4, 6 -> terrain_support.flat_raw + 64
        _, _ -> terrain_support.flat_raw
      }
    }),
  ])
}

pub fn the_ground_at_a_place_is_the_clients_blend_test() -> Nil {
  use <- owned_test.run(60_000)
  let corner = terrain_support.height(raw: terrain_support.flat_raw)
  let rise_z = 32.0 *. terrain_support.step()
  let rise_diagonal = 64.0 *. terrain_support.step()
  // 0x14037d790: each pair weighted by 1 / (its own difference squared + 1)
  let weight_diagonal = 1.0 /. { rise_diagonal *. rise_diagonal +. 1.0 }
  let weight_across = 1.0 /. { rise_z *. rise_z +. 1.0 }
  let centre =
    { rise_diagonal *. weight_diagonal +. rise_z *. weight_across }
    *. 0.5
    /. { weight_diagonal +. weight_across }
  let origin = fn(file) { [#(64, 64, file)] }
  let plane_base = 8000
  let plane_file =
    terrain_support.file([#(0, plane(base: plane_base, a: 8, b: 4))])
  let cases = [
    Case(
      "the centre of a cell is each pair weighted by its own difference",
      origin(one_cell()),
      #(7.0, 11.0),
      Ok(corner +. centre),
    ),
    Case(
      "the triangle with u >= 0 and v < 0 reads A = h11 - c and B = c - h10",
      origin(one_cell()),
      #(7.5, 11.0),
      Ok(corner +. 0.5 *. centre +. 0.25 *. rise_diagonal),
    ),
    Case(
      "the triangle with u >= 0 and v >= 0 reads A = h11 - c and B = h01 - c",
      origin(one_cell()),
      #(7.0, 11.5),
      Ok(corner +. 0.5 *. centre +. 0.25 *. rise_diagonal +. 0.25 *. rise_z),
    ),
    Case(
      "the triangle with u < 0 and v >= 0 reads A = c - h00 and B = h01 - c",
      origin(one_cell()),
      #(6.5, 11.0),
      Ok(corner +. 0.5 *. centre +. 0.25 *. rise_z),
    ),
    Case(
      "the triangle with u < 0 and v < 0 reads A = c - h00 and B = c - h10",
      origin(one_cell()),
      #(7.0, 10.5),
      Ok(corner +. 0.5 *. centre),
    ),
    Case(
      "a cell's high corner is vertex 16 of its own chunk, never the next chunk's vertex 0",
      origin(
        terrain_support.file([
          #(0, fn(column, _row) {
            case column >= 16 {
              True -> 14_000
              False -> 10_000
            }
          }),
          #(1, terrain_support.uniform(raw: 20_000)),
        ]),
      ),
      #(31.5, 1.0),
      Ok(
        terrain_support.height(raw: 10_000)
        +. 0.75
        *. {
          terrain_support.height(raw: 14_000)
          -. terrain_support.height(raw: 10_000)
        },
      ),
    ),
    Case(
      "a chunk border belongs to the chunk at or above it",
      origin(
        terrain_support.file([
          #(0, terrain_support.uniform(raw: 12_000)),
          #(1, terrain_support.uniform(raw: 18_000)),
        ]),
      ),
      #(32.0, 1.0),
      Ok(terrain_support.height(raw: 18_000)),
    ),
    Case(
      "a negative place floors, not truncates: -0.5 is the last cell of slot 255 of the area below and left",
      [
        #(
          63,
          63,
          terrain_support.file([#(255, plane(base: plane_base, a: 8, b: 4))]),
        ),
      ],
      #(-0.5, -0.5),
      Ok(plane_height(base: plane_base, a: 8, b: 4, column: 15.75, row: 15.75)),
    ),
    Case(
      "the last cell of the world, x 32767.5, is inside",
      [
        #(
          64,
          127,
          terrain_support.file([#(15, plane(base: plane_base, a: 8, b: 4))]),
        ),
      ],
      #(32_767.5, 1.0),
      Ok(plane_height(base: plane_base, a: 8, b: 4, column: 15.75, row: 0.5)),
    ),
    Case(
      "x 32768.0 is area column 128, outside",
      [#(64, 127, plane_file)],
      #(32_768.0, 1.0),
      Error(terrain.OutsideTheWorld),
    ),
    Case(
      "the first cell of the world, x -32768.0, is inside",
      [#(64, 0, plane_file)],
      #(-32_768.0, 1.0),
      Ok(plane_height(base: plane_base, a: 8, b: 4, column: 0.0, row: 0.5)),
    ),
    Case(
      "an area with no file has no ground",
      origin(plane_file),
      #(600.0, 10.0),
      Error(terrain.NoFile),
    ),
    Case(
      "a slot whose presence bit is clear holds no chunk",
      origin(plane_file),
      #(40.0, 1.0),
      Error(terrain.NoChunk),
    ),
    Case(
      "a cell whose low corner has bit 15 is a hole",
      origin(
        terrain_support.file([
          #(0, fn(column, row) {
            case column, row {
              3, 5 -> 0x8000 + terrain_support.flat_raw
              _, _ -> terrain_support.flat_raw
            }
          }),
        ]),
      ),
      #(7.0, 11.0),
      Error(terrain.Hole),
    ),
    Case(
      "the cell below and left of a hole vertex reads it as a high corner, its low 15 bits",
      origin(
        terrain_support.file([
          #(0, fn(column, row) {
            case column, row {
              3, 5 -> 0x8000 + plane(base: 9000, a: 8, b: 4)(column, row)
              _, _ -> plane(base: 9000, a: 8, b: 4)(column, row)
            }
          }),
        ]),
      ),
      #(5.0, 11.0),
      Ok(plane_height(base: 9000, a: 8, b: 4, column: 2.5, row: 5.5)),
    ),
    Case(
      "a chunk of 361 values 0x1fff is the client's shared default layer, no ground the server can use",
      origin(terrain_support.file([#(0, terrain_support.uniform(raw: 0x1fff))])),
      #(1.0, 1.0),
      Error(terrain.NoLayer),
    ),
    Case(
      "one value other than 0x1fff makes the layer real data, read at its cell corner",
      origin(
        terrain_support.file([
          #(0, fn(column, row) {
            case column, row {
              3, 5 -> 0x2000
              _, _ -> 0x1fff
            }
          }),
        ]),
      ),
      #(6.0, 10.0),
      Ok(terrain_support.height(raw: 0x2000)),
    ),
  ]
  list.each(cases, fn(held) {
    let got =
      terrain.height_at(
        ground: terrain_support.ground_of(held.files),
        x: held.place.0,
        z: held.place.1,
      )
    assert agrees(got, held.expected) as held.name
  })
}

fn agrees(
  got: Result(Float, NoGround),
  wanted: Result(Float, NoGround),
) -> Bool {
  result.replace(got, Nil) == result.replace(wanted, Nil)
  && close(result.unwrap(got, 0.0), result.unwrap(wanted, 0.0))
}

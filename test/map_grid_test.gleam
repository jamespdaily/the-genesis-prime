//// The spatial index of a map. A position's cell is the floor of its
//// coordinates over the cell size on each axis (cells on the negative side have
//// negative numbers); `near` finds exactly the units within range, which is
//// checked against a full scan of every unit on a fixed seed, as the topology
//// trial checked it (#28, measure 1: a move reaches every player in range and
//// no player outside it).

import genesis_prime/map/grid.{Cell}
import genesis_prime/map/position.{Position}
import gleam/int
import gleam/list
import owned_test
import seeded

pub fn the_distance_between_two_positions_uses_all_three_axes_test() -> Nil {
  use <- owned_test.run(5000)
  let origin = Position(x: 0.0, y: 0.0, z: 0.0)
  let away = Position(x: 3.0, y: 4.0, z: 12.0)
  assert position.distance_squared(origin, away) == 169.0
    as "the 3, 4, 12 triangle has a diagonal of 13 metres, so its square is 169"
  assert position.within(origin, away, 13.0)
    as "a position exactly in range is within range"
  assert !position.within(origin, away, 12.9)
    as "a position farther than the range is not"
}

pub fn a_position_is_in_the_cell_its_coordinates_floor_to_test() -> Nil {
  use <- owned_test.run(5000)
  assert grid.cell_of(Position(x: 0.0, y: 99.9, z: 100.0), 100.0)
    == Cell(x: 0, y: 0, z: 1)
    as "cells are 100 metres wide: 99.9 is in cell 0 and 100.0 begins cell 1"
  assert grid.cell_of(Position(x: -0.5, y: -100.0, z: -100.1), 100.0)
    == Cell(x: -1, y: -1, z: -2)
    as "cells on the negative side of an axis have negative numbers: -0.5 is in cell -1, -100.0 begins cell -1 and -100.1 is in cell -2"
}

pub fn a_search_as_wide_as_a_cell_reads_at_most_27_cells_test() -> Nil {
  use <- owned_test.run(5000)
  let cells = grid.cells_near(Position(x: 50.0, y: 50.0, z: 50.0), 100.0, 100.0)
  assert list.length(cells) == 27
    as "a range of one cell width from the middle of a cell reaches the cell before and after it on each of three axes"
  assert list.contains(cells, Cell(x: 0, y: 0, z: 0))
    && list.contains(cells, Cell(x: -1, y: -1, z: -1))
    && list.contains(cells, Cell(x: 1, y: 1, z: 1))
    as "the cells include the position's own and the two corners"
}

pub fn a_unit_is_found_within_range_and_not_beyond_it_test() -> Nil {
  use <- owned_test.run(5000)
  let index =
    grid.new(100.0)
    |> grid.insert(1, Position(x: 0.0, y: 0.0, z: 0.0))
    |> grid.insert(2, Position(x: 100.0, y: 0.0, z: 0.0))
    |> grid.insert(3, Position(x: 100.1, y: 0.0, z: 0.0))
  assert list.sort(
      grid.near(index, Position(x: 0.0, y: 0.0, z: 0.0), 100.0),
      int.compare,
    )
    == [1, 2]
    as "a unit exactly 100 metres away is in range; one at 100.1 is not"
}

pub fn inserting_a_unit_again_moves_it_test() -> Nil {
  use <- owned_test.run(5000)
  let index =
    grid.new(100.0)
    |> grid.insert(1, Position(x: 0.0, y: 0.0, z: 0.0))
    |> grid.insert(1, Position(x: 500.0, y: 0.0, z: 0.0))
  assert grid.near(index, Position(x: 0.0, y: 0.0, z: 0.0), 100.0) == []
    as "the unit left the cell it was in"
  assert grid.near(index, Position(x: 500.0, y: 0.0, z: 0.0), 100.0) == [1]
    as "and is in the cell it moved to"
}

pub fn a_removed_unit_is_not_found_and_removing_a_stranger_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let index =
    grid.new(100.0)
    |> grid.insert(1, Position(x: 0.0, y: 0.0, z: 0.0))
    |> grid.insert(2, Position(x: 10.0, y: 0.0, z: 0.0))
  let removed = grid.remove(index, 1)
  assert grid.near(removed, Position(x: 0.0, y: 0.0, z: 0.0), 100.0) == [2]
  assert grid.remove(removed, 99) == removed
    as "a unit that is not in the grid changes nothing"
}

pub fn near_finds_exactly_the_units_a_full_scan_finds_test() -> Nil {
  use <- owned_test.run(60_000)
  let checked =
    int.range(from: 0, to: 100, with: #(20_261_303, 0), run: fn(random, _) {
      let #(random, checked) = random
      let #(units, random) = random_units(random:, count: 60, spread: 700)
      let index =
        list.fold(units, grid.new(100.0), fn(index, unit) {
          grid.insert(index, unit.0, unit.1)
        })
      let #(centres, random) = random_units(random:, count: 10, spread: 700)
      list.each(centres, fn(centre) {
        let found = list.sort(grid.near(index, centre.1, 100.0), int.compare)
        let scanned =
          list.filter(units, fn(unit) {
            position.within(unit.1, centre.1, 100.0)
          })
          |> list.map(fn(unit) { unit.0 })
          |> list.sort(int.compare)
        assert found == scanned
          as "the cells read hold every unit in range and no other is returned"
      })
      #(random, checked + 1)
    })
  assert checked.1 == 100 as "every layout was checked"
}

fn random_units(
  random random: Int,
  count count: Int,
  spread spread: Int,
) -> #(List(#(Int, position.Position)), Int) {
  let #(units, random) =
    int.range(from: 0, to: count, with: #([], random), run: fn(state, id) {
      let #(units, random) = state
      let #(x, random) = seeded.up_to(state: random, most: 2 * spread)
      let #(y, random) = seeded.up_to(state: random, most: 2 * spread)
      let #(z, random) = seeded.up_to(state: random, most: 2 * spread)
      let position =
        Position(
          x: int.to_float(x - spread),
          y: int.to_float(y - spread),
          z: int.to_float(z - spread),
        )
      #([#(id, position), ..units], random)
    })
  #(units, random)
}

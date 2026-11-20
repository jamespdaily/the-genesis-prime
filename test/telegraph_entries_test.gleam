//// The positions a creature special's 0x7ff carries so the client draws its telegraph rows
//// (`genesis_prime/game/telegraph_entries`), on the client's committed rows. Expected values
//// come from these places.
//// - `CreateCastTelegraphs` `0x140546e60` and its placement branches: a row with neither
////   TelegraphDamage flag 0x4000 nor 0x1000 is placed by the client (no entry); 0x1000 alone
////   is drawn at the caster's initial position; 0x4000 only at the telegraph position of
////   (row, caster) (`spell.telegraph_position`, `spell.initial_position_flags`).
//// - `TelegraphShownForCast` `0x140542d90`: a row with flag 0x40 or 0x100 is never drawn.
//// - `0x14054b1b0.fixed_placement`, `0x14054b1b0.shape_turn` and `0x14054b1b0.aside_offset`:
////   under 0x4000 the client applies neither the row's offsets nor its rotation, so the entry
////   holds the final origin and facing; a positive x offset lies at (-cos yaw, 0, sin yaw)
////   from the unit and a positive z offset ahead along (-sin yaw, 0, -cos yaw), at yaw 0
////   toward -z; the rotation adds to the yaw.
//// - The rows, read with `table_rows`: Spell4Telegraph and TelegraphDamage of the spells
////   named in each test (the flags, offsets and rotations are the client's).
//// - `opcode.0x7ff`: the lists' counts are 8 bits.

import client_tables
import fixture_tables
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game/telegraph_entries.{type Opening, Placed}
import genesis_prime/message/float32
import genesis_prime/message/spell_initial_position.{SpellInitialPosition}
import genesis_prime/message/spell_position.{SpellPosition}
import genesis_prime/message/spell_telegraph_position.{SpellTelegraphPosition}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_telegraph
import gleam/int
import gleam/list
import owned_test
import place_support
import planted_table
import unitest

/// The creature's unit.
const unit = 7

/// A place at (100, 3, 200) facing `yaw`.
fn standing(yaw yaw: Float) -> Place {
  start_place.turned(
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 100.0,
      y: 3.0,
      z: 200.0,
    ),
    facing: Facing(yaw:, pitch: 0.0, roll: 0.0),
  )
}

fn opening_for(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  place place: Place,
) -> Opening {
  telegraph_entries.opening_of(
    draws: telegraph_entries.draws_of(tables:, spell4_id: Spell4Id(spell4_id)),
    caster: Placed(unit_id: unit, place:),
  )
}

fn position(
  x x: Float,
  y y: Float,
  z z: Float,
) -> spell_position.SpellPosition {
  SpellPosition(
    x: float32.to_bits(x),
    y: float32.to_bits(y),
    z: float32.to_bits(z),
  )
}

pub fn a_client_placed_row_gets_no_entry_test() -> Nil {
  use <- owned_test.run(5000)
  // Sim-Turret 85469's row 16212 has TelegraphDamage flags 0x0 and targetTypeFlags 1: the
  // client places it on the caster by itself each frame, so there is a draw and no entry.
  let tables = fixture_tables.shared()
  let draws = telegraph_entries.draws_of(tables:, spell4_id: Spell4Id(85_469))
  assert list.map(draws, fn(draw) { draw.telegraph_damage_id }) == [16_212]
  assert list.map(draws, fn(draw) { draw.placing })
    == [telegraph_entries.OnTheUnit]
  assert opening_for(tables:, spell4_id: 85_469, place: standing(yaw: 0.5))
    == telegraph_entries.none
    as "no initial position and no telegraph position for a client-placed row"
}

pub fn the_draws_of_a_spell_are_the_rows_the_client_makes_test() -> Nil {
  use <- owned_test.run(5000)
  // 34009: Spell4Telegraph rows 40 to 44 name TelegraphDamage 43 to 46 (flags 0x1040, the
  // never-drawn twins) and 47 (flags 0x1020, drawn). 55635 names 7956 and 7957 (0x101000, both
  // drawn). 41024 names 2738 (flags 0x100000, drawn) and 2739 (flag 0x40); 29710 names only 63
  // (flag 0x100): the rows with 0x40 and 0x100 are never drawn, so they are no draw.
  let tables = fixture_tables.shared()
  let drawn = fn(spell4_id) {
    list.map(
      telegraph_entries.draws_of(tables:, spell4_id: Spell4Id(spell4_id)),
      fn(draw) { draw.telegraph_damage_id },
    )
  }
  assert drawn(34_009) == [47] as "the twins are not draws"
  assert drawn(55_635) == [7956, 7957]
  assert drawn(41_024) == [2738] as "a row with flag 0x40 is never drawn"
  assert drawn(29_710) == [] as "a row with flag 0x100 is never drawn"
}

/// A case of `a_0x4000_caster_row_is_placed_at_its_final_origin_and_facing_test`: the spell,
/// the row among its entries, the place and the entry that row must have.
type Placed4000 {
  Placed4000(
    reason: String,
    spell4_id: Int,
    row: Int,
    yaw: Float,
    x: Float,
    y: Float,
    z: Float,
    entry_yaw: Float,
  )
}

pub fn a_0x4000_caster_row_is_placed_at_its_final_origin_and_facing_test() -> Nil {
  use <- owned_test.run(5000)
  // The place is (100, 3, 200). Row 7880 (Earthen Roar's cone) has no offset and no rotation.
  // Row 3881 has offsets x -6 and z 16 and a rotation of 125 degrees: at yaw 0 the z offset
  // lies 16 toward -z and the x offset 6 toward +x (positive x lies at -cos yaw), at yaw pi / 2
  // 16 toward -x and 6 toward -z (positive x at sin yaw); the entry's facing is the yaw plus
  // the 125 degrees in radians (2.1816615649929116).
  let tables = fixture_tables.shared()
  let half_turn = 1.570_796_326_794_896_6
  let rotation = 2.181_661_564_992_911_6
  [
    Placed4000(
      reason: "no offset, no rotation: the pose itself",
      spell4_id: 55_317,
      row: 7880,
      yaw: 1.0,
      x: 100.0,
      y: 3.0,
      z: 200.0,
      entry_yaw: 1.0,
    ),
    Placed4000(
      reason: "offsets turned by yaw 0, the rotation added",
      spell4_id: 44_146,
      row: 3881,
      yaw: 0.0,
      x: 106.0,
      y: 3.0,
      z: 184.0,
      entry_yaw: rotation,
    ),
    Placed4000(
      reason: "offsets turned by a quarter turn, the rotation added to the yaw",
      spell4_id: 44_146,
      row: 3881,
      yaw: half_turn,
      x: 84.0,
      y: 3.0,
      z: 194.0,
      entry_yaw: half_turn +. rotation,
    ),
  ]
  |> list.each(fn(case_) {
    let opening =
      opening_for(
        tables:,
        spell4_id: case_.spell4_id,
        place: standing(yaw: case_.yaw),
      )
    let assert Ok(entry) =
      list.find(opening.telegraph_positions, fn(entry) {
        entry.telegraph_damage_id == case_.row
      })
      as { case_.reason <> ": the row has a telegraph position" }
    assert entry
      == SpellTelegraphPosition(
        telegraph_damage_id: case_.row,
        unit_id: unit,
        target_flags: 1,
        position: position(x: case_.x, y: case_.y, z: case_.z),
        yaw: float32.to_bits(case_.entry_yaw),
        anchor_unit_id: 0,
      )
      as case_.reason
  })
}

pub fn a_0x4000_rows_y_offset_is_added_to_the_pose_height_test() -> Nil {
  use <- owned_test.run(5000)
  // Synthetic: no client row of a spell that loads has a y offset, so row 7880 is changed to
  // 1.5 to see that the height is the pose's plus the row's.
  use tables <- fixture_tables.changed(
    table: "TelegraphDamage",
    id: 7880,
    with: [#("yPositionOffset", planted_table.Float(1.5))],
  )
  let opening =
    opening_for(tables:, spell4_id: 55_317, place: standing(yaw: 0.0))
  let assert [entry] = opening.telegraph_positions
  assert entry.position == position(x: 100.0, y: 4.5, z: 200.0)
}

pub fn a_0x1000_row_gets_an_initial_position_at_the_unmoved_pose_and_no_telegraph_position_test() -> Nil {
  use <- owned_test.run(5000)
  // 52504's rows 7193 to 7195 (7195: offset x -1.15, rotation 215) and 33582's row 3939
  // (z offset 4) have flag 0x1000 and not 0x4000: the client moves and turns them itself, so
  // the entry is the pose as it is.
  let tables = fixture_tables.shared()
  let pose = standing(yaw: 0.5)
  list.each([52_504, 33_582], fn(spell4_id) {
    let opening = opening_for(tables:, spell4_id:, place: pose)
    assert opening.telegraph_positions == []
      as "no telegraph position for a 0x1000 row"
    assert opening.initial_positions
      == [
        SpellInitialPosition(
          unit_id: unit,
          target_flags: 1,
          position: position(x: 100.0, y: 3.0, z: 200.0),
          yaw: float32.to_bits(0.5),
          anchor_unit_id: 0,
        ),
      ]
      as "one initial position at the unmoved pose"
  })
}

pub fn two_rows_on_one_unit_share_one_initial_position_test() -> Nil {
  use <- owned_test.run(5000)
  // 54838's rows 7814 and 7815 (0x1000, targetTypeFlags 1) name the caster: one initial position
  // whose flags are the caster's role bit 1, never 3. 44146's four 0x4000 rows give one initial
  // position too, and a telegraph position for each row.
  let tables = fixture_tables.shared()
  let two = opening_for(tables:, spell4_id: 54_838, place: standing(yaw: 0.0))
  assert list.map(two.initial_positions, fn(entry) {
      #(entry.unit_id, entry.target_flags)
    })
    == [#(unit, 1)]
  let four = opening_for(tables:, spell4_id: 44_146, place: standing(yaw: 0.0))
  assert list.map(four.initial_positions, fn(entry) {
      #(entry.unit_id, entry.target_flags)
    })
    == [#(unit, 1)]
  assert list.map(four.telegraph_positions, fn(entry) {
      entry.telegraph_damage_id
    })
    == [3868, 3881, 3882, 3896]
    as "one telegraph position for each row"
}

pub fn every_spells_entries_fit_the_wire_counts_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // The 0x7ff's counts are 8 bits (`opcode.0x7ff`): no spell of the client's table makes
  // more than 255 entries in either list.
  let tables = client_tables.shared()
  let spells =
    list.map(spell4_telegraph.all(tables), fn(link) { link.spell4_id })
    |> list.unique
  let counts =
    list.map(spells, fn(spell4_id) {
      let opening = opening_for(tables:, spell4_id:, place: standing(yaw: 0.0))
      #(
        spell4_id,
        list.length(opening.initial_positions),
        list.length(opening.telegraph_positions),
      )
    })
  list.each(counts, fn(found) {
    let #(spell4_id, initial, telegraph) = found
    assert initial <= 255 && telegraph <= 255
      as {
        "Spell4 "
        <> int.to_string(spell4_id)
        <> " makes more entries than the wire's 8-bit counts hold"
      }
  })
  assert list.any(counts, fn(found) { found.2 > 0 })
    as "some spell has telegraph positions, so the check is not empty"
}

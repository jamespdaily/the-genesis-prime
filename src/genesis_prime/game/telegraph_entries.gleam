//// The positions a creature special's 0x7ff carries so that the client draws the
//// spell's telegraph rows, and the rows the client makes from a spell.
////
//// ```
//// Spell4Telegraph rows ──▶ draws_of ──▶ a Draw for each row the client makes
//// draws + the caster's unit and place ──▶ opening_of ──▶ the 0x7ff's initial and telegraph positions
//// ```
////
//// - **A row the client makes** is any row of the spell but one with TelegraphDamage flag
////   0x40 or 0x100, which it never draws (`0x140542d90`).
//// - **A row with neither 0x4000 nor 0x1000** is placed by the client on the caster each
////   frame and gets no entry (`0x140546e60.placement_branches`).
//// - **A row with 0x1000 and not 0x4000** is drawn at the caster's initial position, and the
////   client applies the row's offsets and rotation itself, so the entry holds the unmoved
////   pose (`0x14054b1b0.fixed_placement`).
//// - **A row with 0x4000** is drawn only at the telegraph position of (row, caster), and the
////   client applies neither the row's offsets nor its rotation, so the entry holds the
////   shape's final origin, the pose moved by the offsets (`area.origin_of`, y plus the row's y
////   offset), and its final facing, the pose's yaw plus the rotation
////   (`0x14054b1b0.shape_turn`, `0x14054b1b0.aside_offset`).
//// - **One initial position for the caster** however many rows name it, never two for a unit.
////   Its flags byte is the unit's role bit, 1 for the caster, which is what the rows and a
////   client missile match; that retail sent the same is a guess (`spell.telegraph_position`).
//// - **The anchor unit id is 0**, which leaves the entry in the world (`spell.position_unit`);
////   that retail sent 0 and not the unit's id is a guess.
//// - **A row placed on another unit or the ground** gets no entry here; the load refuses such
////   a row for a creature (`spell_area.TelegraphNotOnCaster`).

import genesis_prime/game/area
import genesis_prime/game/spell_effect
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/float32
import genesis_prime/message/spell_initial_position.{SpellInitialPosition}
import genesis_prime/message/spell_position.{type SpellPosition, SpellPosition}
import genesis_prime/message/spell_telegraph_position.{
  type SpellTelegraphPosition, SpellTelegraphPosition,
}
import genesis_prime/table/id.{type Spell4Id, TelegraphDamageId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/telegraph_damage
import gleam/list
import gleam_community/maths

/// The role bit of the caster in a row's `targetTypeFlags` and in an entry's flags byte.
const caster_bit = 1

/// How the client places a row.
pub type Placing {
  /// Neither 0x4000 nor 0x1000: on the unit, each frame, from its own place and facing.
  OnTheUnit
  /// 0x1000 without 0x4000: at the unit's initial position, offsets and rotation applied by
  /// the client.
  AtInitialPosition
  /// 0x4000: at the telegraph position of (row, unit), the final origin and facing.
  AtTelegraphPosition
}

/// One telegraph row of a spell that the client makes: its TelegraphDamage id, how it is
/// placed, the unit roles it is placed on (`targetTypeFlags`), and the offsets ahead, aside
/// and up and the rotation in degrees that its place is moved and turned by.
pub type Draw {
  Draw(
    telegraph_damage_id: Int,
    placing: Placing,
    target_type_flags: Int,
    ahead: Float,
    aside: Float,
    up: Float,
    turn_degrees: Float,
  )
}

/// A unit and where it stands, facing the way the telegraph is placed from.
pub type Placed {
  Placed(unit_id: Int, place: Place)
}

/// The two lists of a 0x7ff that the client draws a spell's server-placed rows from.
pub type Opening {
  Opening(
    initial_positions: List(spell_initial_position.SpellInitialPosition),
    telegraph_positions: List(spell_telegraph_position.SpellTelegraphPosition),
  )
}

/// No positions: the opening of a cast with no server-placed row.
pub const none = Opening(initial_positions: [], telegraph_positions: [])

/// The rows of the spell that the client makes, in table order: each Spell4Telegraph row
/// of the spell whose TelegraphDamage row exists (`Spell4Telegraph.telegraphDamageId.no_row`)
/// and is not flagged 0x40 or 0x100.
pub fn draws_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Spell4Id,
) -> List(Draw) {
  spell4_telegraph.all(tables)
  |> list.filter(fn(link) { link.spell4_id == spell4_id.value })
  |> list.filter_map(fn(link) {
    telegraph_damage.get(
      tables:,
      id: TelegraphDamageId(link.telegraph_damage_id),
    )
  })
  |> list.filter_map(fn(row) {
    let flags = row.telegraph_damage_flags
    case
      spell_effect.has_flag(flags:, bit: 0x40)
      || spell_effect.has_flag(flags:, bit: 0x100)
    {
      True -> Error(Nil)
      False ->
        Ok(Draw(
          telegraph_damage_id: row.id,
          placing: case
            spell_effect.has_flag(flags:, bit: 0x4000),
            spell_effect.has_flag(flags:, bit: 0x1000)
          {
            True, _ -> AtTelegraphPosition
            False, True -> AtInitialPosition
            False, False -> OnTheUnit
          },
          target_type_flags: row.target_type_flags,
          ahead: row.z_position_offset,
          aside: row.x_position_offset,
          up: row.y_position_offset,
          turn_degrees: row.rotation_degrees,
        ))
    }
  })
}

/// The entries of the draws placed on the caster at its pose: its one initial position when
/// any row is server-placed, and a telegraph position for each row with 0x4000.
pub fn opening_of(draws draws: List(Draw), caster caster: Placed) -> Opening {
  let on_caster =
    list.filter(draws, fn(draw) {
      draw.placing != OnTheUnit
      && spell_effect.has_flag(flags: draw.target_type_flags, bit: caster_bit)
    })
  case on_caster {
    [] -> none
    [_, ..] -> {
      let pose = area.pose_of(place: caster.place)
      Opening(
        initial_positions: [
          SpellInitialPosition(
            unit_id: caster.unit_id,
            target_flags: caster_bit,
            position: position_of(place: caster.place),
            yaw: float32.to_bits(pose.yaw),
            anchor_unit_id: 0,
          ),
        ],
        telegraph_positions: list.filter_map(on_caster, fn(draw) {
          case draw.placing {
            AtTelegraphPosition -> Ok(telegraph_position_of(draw:, caster:))
            AtInitialPosition | OnTheUnit -> Error(Nil)
          }
        }),
      )
    }
  }
}

/// The telegraph position of a 0x4000 row on the caster: the row's final origin, the pose
/// moved by its offsets, and its final facing, the pose's yaw plus its rotation.
fn telegraph_position_of(
  draw draw: Draw,
  caster caster: Placed,
) -> SpellTelegraphPosition {
  let pose = area.pose_of(place: caster.place)
  let origin =
    area.origin_of(centre: pose, ahead: draw.ahead, aside: draw.aside)
  SpellTelegraphPosition(
    telegraph_damage_id: draw.telegraph_damage_id,
    unit_id: caster.unit_id,
    target_flags: caster_bit,
    position: position_of(place: start_place.moved(
      place: caster.place,
      x: origin.x,
      y: start_place.y(caster.place) +. draw.up,
      z: origin.z,
    )),
    yaw: float32.to_bits(
      pose.yaw +. maths.degrees_to_radians(draw.turn_degrees),
    ),
    anchor_unit_id: 0,
  )
}

/// A place's position as a 0x7ff holds it (the same three 32-bit floats `cast/state`
/// writes for a cast's position, which this module cannot import: it reaches the creature
/// rule that imports this one).
fn position_of(place place: Place) -> SpellPosition {
  SpellPosition(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
  )
}

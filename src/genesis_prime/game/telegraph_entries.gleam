//// The positions a creature special's 0x7ff carries so that the client draws the
//// spell's telegraph rows, and the rows the client makes from a spell.
////
//// ```
//// Spell4Telegraph rows ──▶ draws_of ──▶ a Draw for each row the client makes
//// draws + the caster's and the target's units and places ──▶ opening_of ──▶ the 0x7ff's initial and telegraph positions
//// ```
////
//// - **A row the client makes** is any row of the spell but one with TelegraphDamage flag
////   0x40 or 0x100, which it never draws (`0x140542d90`).
//// - **A row with neither 0x4000 nor 0x1000** is placed by the client on its unit each
////   frame, the caster or the cast's target, and gets no entry
////   (`0x140546e60.placement_branches`).
//// - **A row with 0x1000 and not 0x4000** is drawn at its unit's initial position, and the
////   client applies the row's offsets and rotation itself, so the entry holds the unmoved
////   pose (`0x14054b1b0.fixed_placement`).
//// - **A row with 0x4000** is drawn only at the telegraph position of (row, unit), and the
////   client applies neither the row's offsets nor its rotation, so the entry holds the
////   shape's final origin, the pose moved by the offsets (`area.origin_of`, y plus the row's y
////   offset), and its final facing, the pose's yaw plus the rotation
////   (`0x14054b1b0.shape_turn`, `0x14054b1b0.aside_offset`).
//// - **A row names a unit by its role** in `targetTypeFlags`: bit 1 the caster, bit 2 the
////   cast's target, and a row with 0 is placed on the target. A row naming both would be
////   drawn on each, and the load refuses a spell whose rows are not placed alike.
//// - **One initial position for each unit** however many rows name it, never two for a unit.
////   Its flags byte is the unit's role bit, 1 for the caster and 2 for the target, which is
////   what the rows and a client missile match; that retail sent the same is a guess
////   (`spell.telegraph_position`).
//// - **The anchor unit id is 0**, which leaves the entry in the world (`spell.position_unit`);
////   that retail sent 0 and not the unit's id is a guess.
//// - **A row placed on each struck unit or on the ground** gets no entry here; the load
////   refuses such a row for a creature (`spell_area.TelegraphNotOnCaster`).

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
import gleam/option.{type Option, None, Some}
import gleam_community/maths

/// The role bit of the caster in a row's `targetTypeFlags` and in an entry's flags byte.
const caster_bit = 1

/// The role bit of the cast's target, the 0x7ff's primary target, in the same two places.
const target_bit = 2

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

/// How the client places a row with these TelegraphDamage flags: 0x4000 first, then 0x1000,
/// else on the unit (`0x140546e60.placement_branches`). The picture (`draws_of`) and the hit
/// (`spell_area` `anchor_of`) both read a row's placement through it.
pub fn placing_of(flags flags: Int) -> Placing {
  case
    spell_effect.has_flag(flags:, bit: 0x4000),
    spell_effect.has_flag(flags:, bit: 0x1000)
  {
    True, _ -> AtTelegraphPosition
    False, True -> AtInitialPosition
    False, False -> OnTheUnit
  }
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
          placing: placing_of(flags:),
          target_type_flags: row.target_type_flags,
          ahead: row.z_position_offset,
          aside: row.x_position_offset,
          up: row.y_position_offset,
          turn_degrees: row.rotation_degrees,
        ))
    }
  })
}

/// The entries of the draws placed on the caster and on the target at their places: for each
/// unit a row names, its one initial position when any row on it is server-placed, and a
/// telegraph position for each row with 0x4000. The caster's go first, then the target's.
pub fn opening_of(
  draws draws: List(Draw),
  caster caster: Placed,
  target target: Option(Placed),
) -> Opening {
  let for_caster = entries_of(draws:, unit: caster, role_bit: caster_bit)
  let for_target = case target {
    Some(placed) -> entries_of(draws:, unit: placed, role_bit: target_bit)
    None -> none
  }
  Opening(
    initial_positions: list.append(
      for_caster.initial_positions,
      for_target.initial_positions,
    ),
    telegraph_positions: list.append(
      for_caster.telegraph_positions,
      for_target.telegraph_positions,
    ),
  )
}

/// Whether a row with these `targetTypeFlags` is placed on the unit of this role: the row's
/// bit for the role, and a row with none (0) is placed on the target (`0x140546e60.placement_branches`:
/// the client-placed target is cast 0x158 when the flags are 0 or have bit 2, and an initial
/// position matches `(flags == 0 and the entry's bit 2) or flags and the entry's bits`).
fn names_role(
  target_type_flags target_type_flags: Int,
  role_bit role_bit: Int,
) -> Bool {
  spell_effect.has_flag(flags: target_type_flags, bit: role_bit)
  || { target_type_flags == 0 && role_bit == target_bit }
}

/// The entries of the draws that name one unit, at the place it stands: its one initial
/// position, and a telegraph position for each row with 0x4000, flagged with its role bit.
fn entries_of(
  draws draws: List(Draw),
  unit unit: Placed,
  role_bit role_bit: Int,
) -> Opening {
  let on_unit =
    list.filter(draws, fn(draw) {
      draw.placing != OnTheUnit
      && names_role(target_type_flags: draw.target_type_flags, role_bit:)
    })
  case on_unit {
    [] -> none
    [_, ..] -> {
      let pose = area.pose_of(place: unit.place)
      Opening(
        initial_positions: [
          SpellInitialPosition(
            unit_id: unit.unit_id,
            target_flags: role_bit,
            position: position_of(place: unit.place),
            yaw: float32.to_bits(pose.yaw),
            anchor_unit_id: 0,
          ),
        ],
        telegraph_positions: list.filter_map(on_unit, fn(draw) {
          case draw.placing {
            AtTelegraphPosition ->
              Ok(telegraph_position_of(draw:, unit:, role_bit:))
            AtInitialPosition | OnTheUnit -> Error(Nil)
          }
        }),
      )
    }
  }
}

/// The telegraph position of a 0x4000 row on a unit: the row's final origin, the pose moved
/// by its offsets, and its final facing, the pose's yaw plus its rotation.
fn telegraph_position_of(
  draw draw: Draw,
  unit unit: Placed,
  role_bit role_bit: Int,
) -> SpellTelegraphPosition {
  let pose = area.pose_of(place: unit.place)
  let origin =
    area.origin_of(centre: pose, ahead: draw.ahead, aside: draw.aside)
  SpellTelegraphPosition(
    telegraph_damage_id: draw.telegraph_damage_id,
    unit_id: unit.unit_id,
    target_flags: role_bit,
    position: position_of(place: start_place.moved(
      place: unit.place,
      x: origin.x,
      y: start_place.y(unit.place) +. draw.up,
      z: origin.z,
    )),
    yaw: float32.to_bits(
      pose.yaw +. maths.degrees_to_radians(draw.turn_degrees),
    ),
    anchor_unit_id: 0,
  )
}

/// A place's position as a 0x7ff holds it: three 32-bit floats. The entries and every
/// other position of a cast message are written through it.
pub fn position_of(place place: Place) -> SpellPosition {
  SpellPosition(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
  )
}

//// What the ability builder's save tests share: the bodies of the client's 0xB1 (the four
//// the 2026-11-19 sitting recorded and one packed by hand), a body packed from a list of
//// ids, the player of a class at a level on the committed rows, and what a rule step's
//// frames hold. The expected values are written in the tests, each from the client's rows
//// or the recording.

import ability_book_support
import fixture_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/ability_book
import genesis_prime/game/ability_points
import genesis_prime/game/limited_action_set.{type Effect, Log, Send}
import genesis_prime/game/spell_tier
import genesis_prime/message/action_set.{type ActionSet}
import genesis_prime/message/action_set_saved
import genesis_prime/step.{type LogLevel}
import genesis_prime/store
import genesis_prime/table/id.{type Spell4BaseId}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import message_support

/// The class of the sitting's character: Spellslinger. Its level 1 abilities are Spell4Base
/// 27638, 20684 and 20325 (SpellLevel rows 1 to 3 of the class), its level 4 ability 20718,
/// its level 5 ability 30666 and its level 10 ability 23468.
pub const spellslinger = 7

/// The faction of the tests' characters (Dominion).
pub const faction = 166

/// 0xB1 of the sitting, sequences 16176 and 16252 (`recording_dump` of Jim's 2026-11-19
/// sitting): 27638, 20684, 20325, 20718 in slots 0 to 3, the rest empty, set 0, no tier
/// change, no AMP. 51 bytes.
pub const save_a =
  "6CBF0600C00C050050F60400E00E05000000000000000000000000000000000000000000000000000000000000000000000000"

/// Sequence 16317: 20684, 27638, 20718 in slots 0 to 2, the rest empty.
pub const save_b =
  "CC0C050060BF0600E00E0500000000000000000000000000000000000000000000000000000000000000000000000000000000"

/// Sequence 16356: 27638, 20684 in slots 0 and 1, the rest empty.
pub const save_c =
  "6CBF0600C00C050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

/// The slots of `save_a`, packed by hand with two tier changes ((20684, 2) and (27638, 3))
/// and two AMP ids (101 and 202): the recording holds neither. 61 bytes.
pub const save_d =
  "6CBF0600C00C050050F60400E00E0500000000000000000000000000000000000000000000000000000000000000000000C10C8580FD1A038232006500"

/// The ids of `save_a`, `save_b` and `save_c`, slot 0 first, 0 for an empty slot.
pub const ids_a = [27_638, 20_684, 20_325, 20_718, 0, 0, 0, 0, 0, 0, 0, 0]

pub const ids_b = [20_684, 27_638, 20_718, 0, 0, 0, 0, 0, 0, 0, 0, 0]

pub const ids_c = [27_638, 20_684, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

/// The class's bar at entry: its level 1 abilities in slots 0 to 2.
pub const class_bar = [27_638, 20_684, 20_325, 0, 0, 0, 0, 0, 0, 0, 0, 0]

/// The rows of one saved set for these ids, slot 0 first, 0 for an empty slot (a row with no
/// ability): the shape the store hands the load.
pub fn rows_of(set set: Int, ids ids: List(Int)) -> List(store.ActionSlotRow) {
  list.index_map(ids, fn(id, slot) {
    store.ActionSlotRow(action_set: set, slot:, spell4_base_id: case id {
      0 -> None
      id -> Some(id)
    })
  })
}

/// The bytes of a vector written as hexadecimal.
pub fn hex(text text: String) -> BitArray {
  message_support.hex(text)
}

/// The levels from one to another, both included.
pub fn levels(from from: Int, to to: Int) -> List(Int) {
  int.range(from:, to: to + 1, with: [], run: fn(so_far, level) {
    [level, ..so_far]
  })
  |> list.reverse
}

/// The body of a 0xB1 for these ids and this set, with no tier change and no AMP.
pub fn body(ids ids: List(Int), set set: Int) -> BitArray {
  body_with(ids:, set:, tier_changes: [], amp_ids: [])
}

/// The body of a 0xB1 for these ids, this set, these tier changes (Spell4Base, tier) and
/// these AMP ids, packed by the client's writer's widths: a 4-bit count, the ids in 32 bits
/// each, the set in 3, a 5-bit count of tier changes of 18 and 8 bits, and a 7-bit count of
/// AMP ids of 16 bits (`opcode.0xb1`, the writer `0x14008a810`).
pub fn body_with(
  ids ids: List(Int),
  set set: Int,
  tier_changes tier_changes: List(#(Int, Int)),
  amp_ids amp_ids: List(Int),
) -> BitArray {
  message_support.packed(
    list.flatten([
      [#(4, list.length(ids))],
      list.map(ids, fn(id) { #(32, id) }),
      [#(3, set), #(5, list.length(tier_changes))],
      list.flat_map(tier_changes, fn(change) {
        [#(18, change.0), #(8, change.1)]
      }),
      [#(7, list.length(amp_ids))],
      list.map(amp_ids, fn(id) { #(16, id) }),
    ]),
  )
}

/// The player of the Spellslinger at a level: alive, out of combat, holding the book the
/// level gives.
pub fn player(
  tables tables: table_store.Tables,
  level level: Int,
) -> limited_action_set.Player {
  limited_action_set.Player(
    level:,
    points_total: ability_points.total(tables:, level:),
    book: ability_book.book(
      tables:,
      loadout: ability_book_support.loadout_of(tables:, class_id: spellslinger),
      level:,
    ),
    dead: False,
    in_combat: False,
  )
}

/// The class's level 1 abilities, the bar a player who saved none holds.
pub fn class_abilities(
  tables tables: table_store.Tables,
) -> List(Spell4BaseId) {
  ability_book_support.loadout_of(tables:, class_id: spellslinger).abilities
}

/// The ids of a bar, slot 0 first, 0 for an empty slot.
pub fn ids_of(bar bar: limited_action_set.Bar) -> List(Int) {
  list.map(limited_action_set.slots(bar:), fn(slot) {
    case slot {
      Some(base) -> base.value
      None -> 0
    }
  })
}

/// The bar a player holds after a rule step: what `bar_of` gives for the saved sets.
pub fn held_ids(
  tables tables: table_store.Tables,
  saved saved: limited_action_set.Saved,
) -> List(Int) {
  ids_of(bar: limited_action_set.bar_of(
    saved:,
    set: limited_action_set.first_set(),
    class_bar: class_abilities(tables:),
  ))
}

/// What a save leads to on the committed rows, for the Spellslinger at a level who is alive and
/// out of combat and holds this saved set.
pub fn taken(
  saved saved: limited_action_set.Saved,
  level level: Int,
  body body: BitArray,
) -> #(limited_action_set.Saved, List(Effect)) {
  let tables = fixture_tables.shared()
  let assert Ok(result) =
    limited_action_set.take(
      unlocks: limited_action_set.unlocks(tables:),
      tiers: spell_tier.tiers(tables:),
      player: player(tables:, level:),
      saved:,
      class_bar: class_abilities(tables:),
      body:,
    )
    as "the body is one the client's reader accepts"
  result
}

/// The frames among a step's effects, in order.
pub fn frames_of(effects effects: List(Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(frame:) -> Ok(frame)
      Log(..) -> Error(Nil)
    }
  })
}

/// The log lines among a step's effects, in order.
pub fn logs_of(effects effects: List(Effect)) -> List(#(LogLevel, String)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Log(level:, text:) -> Ok(#(level, text))
      Send(..) -> Error(Nil)
    }
  })
}

/// The 0x019D among frames, which must be one, read by the client's layout.
pub fn the_action_set(frames frames: List(Frame)) -> ActionSet {
  let assert [set] =
    list.filter_map(frames, fn(frame) {
      case frame.message_id == action_set.message_id {
        True -> action_set.decode(frame.body) |> result.replace_error(Nil)
        False -> Error(Nil)
      }
    })
    as "one 0x019D"
  set
}

/// The bit of the 0xB2 among frames, which must be one.
pub fn the_answer_bit(frames frames: List(Frame)) -> Int {
  let assert [saved] =
    list.filter_map(frames, fn(frame) {
      case frame.message_id == action_set_saved.message_id {
        True -> action_set_saved.decode(frame.body) |> result.replace_error(Nil)
        False -> Error(Nil)
      }
    })
    as "one 0xB2"
  saved.add_combat_log_line
}

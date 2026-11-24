//// What world entry sends and decides for a class's innate
//// (`genesis_prime/game/world_entry`), on the client's tables. Expected values
//// come from these places.
//// - `lua.ActionBarFrame.ActionBarInnate`: the innate button needs the active
////   spell's Spell4Base as an ability item (0x111, location 4), its tier (0x1A0)
////   and 0x19F {0} once the player exists, so they follow 0x19B; the innate is no
////   action set slot, so 0x19D keeps bar slots 0 to 2 (`opcode.0x19d`).
//// - `opcode.0x111.ability_bag`, `opcode.0x1a0`: an ability's item has location 4
////   and reason 49 adds it; an entry of the book holds four action sets and tier 1
////   is the first. The bag index is the server's choice, the one after the
////   abilities, 3.
//// - `Class.spell4IdInnateAbilityPassive00`: Warrior 44926, Engineer 45000 and
////   Stalker 45057 have a slot-0 passive, whose Spell4Base is 29035, 29076 and
////   29131; the client never casts it, so the server starts it at each join.
//// Skipped where the client's tables are not on the machine, but for the entry of
//// a class with no innate, which the client's Class row with its innate cleared
//// gives.

import cast_support
import client_tables
import fixture_tables
import genesis_prime/game/cast
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection/casting
import genesis_prime/game/world_entry
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers
import genesis_prime/message/action_set
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/innate_index_set.{InnateIndexSet}
import genesis_prime/step.{LogWarning}

import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import planted_table
import unitest
import world_entry_support

/// A class's id, its three level-1 abilities, its slot-0 innate's Spell4Base and
/// the Spell4Base of its slot-0 passive, when it has one.
fn classes() -> List(#(Int, List(Int), Int, option.Option(Int))) {
  [
    #(1, [18_309, 37_968, 38_017], 30_828, Some(29_035)),
    #(2, [26_468, 25_473, 25_635], 31_779, Some(29_076)),
    #(3, [19_102, 19_019, 19_022], 38_012, None),
    #(4, [38_201, 16_322, 26_543], 46_615, None),
    #(5, [23_148, 23_161, 23_173], 30_075, Some(29_131)),
    #(7, [27_638, 20_684, 20_325], 31_213, None),
  ]
}

pub fn the_entry_sends_the_innate_after_the_abilities_and_0x19f_after_0x19d_for_each_class_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each(classes(), fn(class) {
    let #(class_id, _, _, _) = class
    let #(effects, _) =
      world_entry_support.entry(
        tables: client_tables.shared(),
        character: world_entry_support.character(
          class: class_id,
          faction: 166,
          level: 1,
        ),
      )
    let frames = world_entry_support.frames_of(effects:)
    assert cast_support.ids(frames:)
      == [
        0x00AD,
        0x0262,
        0x019B,
        0x092C,
        0x0169,
        0x025E,
        0x035F,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x0111,
        0x01A0,
        0x019D,
        0x019F,
        0x06BC,
        0x0636,
        0x00F1,
        0x0061,
      ]
      as {
        "lua.ActionBarFrame.ActionBarInnate: class "
        <> int.to_string(class_id)
        <> " gets the innate's 0x111 after its three abilities' and before 0x1A0, 0x19D as before, then 0x19F, all after 0x19B and before 0x6BC"
      }
  })
}

pub fn the_innates_item_is_its_spell4_base_at_location_4_bag_index_3_with_reason_49_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each(classes(), fn(class) {
    let #(class_id, abilities, innate_base, _) = class
    let #(effects, _) =
      world_entry_support.entry(
        tables: client_tables.shared(),
        character: world_entry_support.character(
          class: class_id,
          faction: 166,
          level: 1,
        ),
      )
    let held =
      world_entry_support.items_added(frames: world_entry_support.frames_of(
        effects:,
      ))
      |> list.filter(fn(added) { added.held_item.item.location == 4 })
    assert list.map(held, fn(added) { added.held_item.item.item_id })
      == list.append(abilities, [innate_base])
      as "opcode.0x111.ability_bag: the item id of an ability is its Spell4Base"
    assert list.map(held, fn(added) { added.held_item.item.bag_index })
      == [0, 1, 2, 3]
      as "the innate is held after the three abilities, at index 3"
    assert list.all(held, fn(added) { added.held_item.reason == 49 })
      as "opcode.0x111.ability_bag: reason 49 holds the item with no book change"
    let assert Ok(innate) = list.last(held)
    assert innate.held_item.item.item_id == innate_base
      && innate.held_item.item.location == 4
      && innate.held_item.item.bag_index == 3
      && innate.held_item.reason == 49
  })
}

pub fn one_0x1a0_sets_tier_1_of_the_abilities_and_the_innate_in_action_sets_0_to_3_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each(classes(), fn(class) {
    let #(class_id, abilities, innate_base, _) = class
    let #(effects, _) =
      world_entry_support.entry(
        tables: client_tables.shared(),
        character: world_entry_support.character(
          class: class_id,
          faction: 166,
          level: 1,
        ),
      )
    let frames = world_entry_support.frames_of(effects:)
    let assert Ok(tiers) =
      ability_tiers.decode(
        { world_entry_support.only_frame(frames:, message_id: 0x01A0) }.body,
      )
      as "0x1a0 decodes"
    assert tiers.tiers
      == list.flat_map(
        list.append(
          list.append(abilities, [innate_base]),
          world_entry_support.alternate_bases(class_id:, level: 1),
        ),
        fn(base) {
          list.map([0, 1, 2, 3], fn(action_set_index) {
            AbilityTier(spell4_base_id: base, tier: 1, action_set_index:)
          })
        },
      )
      as "opcode.0x1a0: tier 1 of all four bases and of the alternates of the abilities, in each of the four action sets"
  })
}

pub fn the_action_set_keeps_the_three_bar_abilities_and_0x19f_names_slot_0_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each(classes(), fn(class) {
    let #(class_id, abilities, _, _) = class
    let #(effects, _) =
      world_entry_support.entry(
        tables: client_tables.shared(),
        character: world_entry_support.character(
          class: class_id,
          faction: 166,
          level: 1,
        ),
      )
    let frames = world_entry_support.frames_of(effects:)
    let assert Ok(set) =
      action_set.decode(
        { world_entry_support.only_frame(frames:, message_id: 0x019D) }.body,
      )
      as "0x19d decodes"
    assert set.shortcuts
      == list.index_map(abilities, fn(base, slot) {
        ActionShortcut(
          shortcut_type: 4,
          location: 4,
          bag_index: slot,
          object_id: base,
        )
      })
      as "opcode.0x19d: the innate is in no action set, so slots 0 to 2 hold the three abilities as before"
    assert innate_index_set.decode(
        { world_entry_support.only_frame(frames:, message_id: 0x019F) }.body,
      )
      == Ok(InnateIndexSet(innate_index: 0))
      as "opcode.0x19f: index 0, so the button points at slot 0's active spell and not the slot-1 passive"
  })
}

pub fn the_entry_starts_the_passive_of_a_class_that_has_one_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each(classes(), fn(class) {
    let #(class_id, _, _, passive) = class
    let #(effects, entered) =
      world_entry_support.entry(
        tables: client_tables.shared(),
        character: world_entry_support.character(
          class: class_id,
          faction: 166,
          level: 1,
        ),
      )
    let started =
      list.filter_map(effects, fn(effect) {
        case effect {
          world_entry.StartStanding -> Ok(Nil)
          world_entry.Send(..)
          | world_entry.AskStore(..)
          | world_entry.AskMap(..)
          | world_entry.WatchMap(..)
          | world_entry.Life(..)
          | world_entry.Warn(..) -> Error(Nil)
        }
      })
    assert started
      == case passive {
        Some(_) -> [Nil]
        None -> []
      }
      as {
        "Class.spell4IdInnateAbilityPassive00: class "
        <> int.to_string(class_id)
        <> " starts its slot-0 passive, if any"
      }
    assert list.last(effects)
      == case passive {
        Some(_) -> Ok(world_entry.StartStanding)
        None -> list.last(effects)
      }
      as "the standing spells' start is the last thing the entry asks, once its writes and the map's watch are out"
    let #(wanted, warnings) =
      casting.standing_wanted(entered:, plans: cast_support.real_plans())
    assert list.map(wanted, fn(spell) { spell.spell4_base_id.value })
      == case passive {
        Some(base) -> [base]
        None -> []
      }
      as "the list the start works from holds the class's slot-0 passive, if any"
    assert warnings == []
  })
}

pub fn a_class_with_no_innate_is_sent_neither_the_innates_item_nor_0x19f_and_starts_no_passive_test() -> Nil {
  use <- owned_test.run(60_000)
  // No client Class row lacks an innate (spell4IdInnateAbilityActive00 is not 0
  // in all six), so the Engineer's row is edited to have none: the test's subject.
  fixture_tables.changed(
    table: "Class",
    id: 2,
    with: [#("spell4IdInnateAbilityActive00", planted_table.Integer(0))],
    body: fn(tables) {
      let #(effects, entered) =
        world_entry_support.entry(
          tables:,
          character: world_entry_support.character(
            class: 2,
            faction: 166,
            level: 1,
          ),
        )
      let frames = world_entry_support.frames_of(effects:)
      assert list.length(
          list.filter(world_entry_support.items_added(frames:), fn(added) {
            added.held_item.item.location == 4
          }),
        )
        == 3
        as "the Class row names no innate: the three abilities only"
      assert !list.contains(cast_support.ids(frames:), 0x019F)
        as "0x19f is sent only with an innate to point the button at"
      assert entered.loadout.innate == None
      assert list.all(effects, fn(effect) {
        case effect {
          world_entry.StartStanding -> False
          world_entry.Send(..)
          | world_entry.AskStore(..)
          | world_entry.AskMap(..)
          | world_entry.WatchMap(..)
          | world_entry.Life(..)
          | world_entry.Warn(..) -> True
        }
      })
    },
  )
}

pub fn the_wanted_list_holds_the_innate_passive_of_the_loadout_and_leaves_out_a_base_the_plans_lack_with_a_warning_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Engineer's slot-0 passive is Spell4Base 29076 (`Class.spell4IdInnateAbilityPassive00`,
  // Spell4 45000); the plans are planted, so the test does not read the client's spell tree.
  let #(_, entered) =
    world_entry_support.entry(
      tables: fixture_tables.shared(),
      character: world_entry_support.character(class: 2, faction: 166, level: 1),
    )
  let passive = cast_support.child(spell4_id: 45_000, base: 29_076)
  let plans = cast_support.plans_of([passive])
  let #(wanted, warnings) = casting.standing_wanted(entered:, plans:)
  assert wanted == [passive]
    as "the loadout's passive is wanted, as the plan of its Spell4Base"
  assert warnings == []
  let #(wanted, warnings) =
    casting.standing_wanted(entered:, plans: dict.delete(plans, 29_076))
  assert wanted == []
    as "a base the plans lack is not in the list, so the rule never sees it"
  assert warnings
    == [
      cast_state.Log(
        level: LogWarning,
        text: "the innate passive with Spell4Base 29076 is in no plan, so it is not started",
      ),
    ]
    as "and is one warning"
}

/// Each frame the passive's start writes, its go answered, as the message id in hex, a
/// colon and the body's hex: the class's entry names the passive, and the first caster of
/// the cast tests casts it.
fn passive_frames(class_id class_id: Int) -> List(String) {
  let #(_, entered) =
    world_entry_support.entry(
      tables: client_tables.shared(),
      character: world_entry_support.character(
        class: class_id,
        faction: 166,
        level: 1,
      ),
    )
  let #(wanted, _) =
    casting.standing_wanted(entered:, plans: cast_support.real_plans())
  let caster = cast_support.caster()
  let #(state, effects) =
    cast.standing_changed(
      cast: cast_state.new(),
      caster:,
      wanted:,
      now: cast_support.at(ms: 1000),
    )
  let #(_, effects) =
    cast_support.answered_as(
      caster:,
      state:,
      effects:,
      at: 1000,
      struck: [],
      rolls: [],
    )
  list.map(cast_support.writes(effects:), fn(frame) {
    int.to_base16(frame.message_id)
    <> ":"
    <> string.lowercase(bit_array.base16_encode(frame.body))
  })
}

pub fn the_entry_starts_the_passive_of_classes_1_2_and_5_with_the_frames_the_single_passive_cast_wrote_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // The expected frames are what the server wrote for these casters and plans before the
  // standing set existed (the cast rule's `passive_started` of the same Spell4Base, its go
  // answered with no unit struck), captured from that code. The Engineer's passive also
  // starts and ends a child cast; the Warrior's and the Stalker's start one cast.
  let expected = [
    #(1, [
      "7FF:003800807eaff8bd0200c00100000000c0010000c04cfb639168913c70dfdffd10000000000040",
      "7F4:0038008066da1f8b448be481fbfeee87020e00000000000200a420c832010000000000000000000000e8b18c0000000000000000000000007c5335000000000000000000000080df541100000000000000000000000019370500000000000000000000000000000000",
    ]),
    #(2, [
      "7FF:00380080c8af20bf0200c00100000000c0010000c04cfb639168913c70dfdffd10000000000040",
      "7F4:0038008066da1f8b448be481fbfeee87020e000000000002008480423301000000000000000000000088ab95000000000000000000000000e46a35000000000000000000000000dcbf1100000000000000000000000000000000",
      "7FF:01380080d9b420bf82fcca0100000000c0010000c04cfb639168913c70dfdffd10000000000040",
      "7F4:0138008066da1f8b448be481fbfeee87000000000000",
      "7FE:01380080",
    ]),
    #(5, [
      "7FF:0038008001b004c00200c00100000000c0010000c04cfb639168913c70dfdffd10000000000040",
      "7F4:0038008066da1f8b448be481fbfeee87020e00000000000200a4e0d547010000000000000000000000e0f59100000000000000000000000040db340000000000000000000000809d8a1100000000000000000000004007670500000000000000000000000000000000",
    ]),
  ]
  list.each(expected, fn(row) {
    let #(class_id, frames) = row
    assert passive_frames(class_id:) == frames
      as {
        "class "
        <> int.to_string(class_id)
        <> ": the passive's frames are the bytes the single passive cast wrote"
      }
  })
}

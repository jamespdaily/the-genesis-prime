//// What world entry sends in 0x025E, the player character's own state
//// (`genesis_prime/game/world_entry`, `genesis_prime/game/character_state`).
//// Expected values come from these places.
//// - `opcode.0x25e.entry_order`: 0x25E goes once, right after 0x19B (before it
////   the client's handler fails, "no player") and before the loadout, 0x6BC,
////   0x636, 0xF1 and 0x61.
//// - `opcode.0x25e.safe_body`: the experience is the least experience of the
////   character's level, the XpPerLevel row with the level's ID (`table_rows --
////   XpPerLevel 1 3`: levels 1 and 3 are 0 and 1710); the item proficiencies are
////   the class's `Class.startingItemProficiencies` (`table_rows -- Class 1 2 3
////   4 5 7`: Warrior 18, Engineer 66, Esper 262152, Medic 260, Stalker 1048580,
////   Spellslinger 4104); the costume index is -1, the input key set 3, the active
////   action set 0, and every other value is 0 or empty.
//// The tests of the real rows are skipped where the client's tables are not on
//// the machine; the others run on the planted rows, which hold the same values
//// (`character_tables_test`).

import character_tables
import client_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/player_character_state.{type PlayerCharacterState}
import genesis_prime/message/reputation_list.{ReputationList}
import genesis_prime/store.{type Character, Character, CharacterId, NameStands}
import genesis_prime/table/id.{ClassId, RaceId}
import genesis_prime/table/loader/store as table_store
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import place_support
import unitest
import world_entry_support

fn character(class class: Int, level level: Int) -> Character {
  Character(
    character_id: CharacterId(42),
    name: "Ab Cd",
    gender: 0,
    race_id: RaceId(1),
    class_id: ClassId(class),
    faction_id: 166,
    level:,
    path: 3,
    place: Some(place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.0,
      y: -853.0,
      z: -560.0,
    )),
    look: [],
    bones: [],
    naming: NameStands,
  )
}

fn frames(
  tables tables: table_store.Tables,
  character character: Character,
) -> List(Frame) {
  let #(effects, _) = world_entry_support.entry(tables:, character:)
  world_entry_support.frames_of(effects:)
}

fn ids(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

/// The one 0x25E among the frames, decoded.
fn state_of(frames frames: List(Frame)) -> PlayerCharacterState {
  let assert [frame] =
    list.filter(frames, fn(frame) {
      frame.message_id == player_character_state.message_id
    })
    as "opcode.0x25e.entry_order: the entry sends 0x25E once"
  let assert Ok(state) = player_character_state.decode(frame.body)
    as "0x25E decodes"
  state
}

const classes = [1, 2, 3, 4, 5, 7]

pub fn the_entry_writes_0x25e_once_right_after_0x19b_before_the_loadout_for_every_class_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(classes, fn(class) {
    let sent =
      ids(frames: frames(
        tables: character_tables.shared(),
        character: character(class:, level: 1),
      ))
    assert sent
      == [
        0x00AD,
        0x0262,
        0x019B,
        0x025E,
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
        0x06BC,
        0x0636,
        0x00F1,
        0x0061,
      ]
      as {
        "opcode.0x25e.entry_order: class "
        <> int.to_string(class)
        <> " gets one 0x25E straight after 0x19B, which sets the player its handler needs, and before 0x6BC, 0x636, 0xF1 and 0x61"
      }
  })
}

pub fn the_experience_is_the_least_experience_of_the_saved_level_on_the_real_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each([#(1, 0), #(3, 1710)], fn(level_and_experience) {
    let #(level, minimum) = level_and_experience
    let state =
      state_of(frames: frames(
        tables: client_tables.shared(),
        character: character(class: 2, level:),
      ))
    assert state.experience == minimum
      as {
        "opcode.0x25e.safe_body, XpPerLevel row "
        <> int.to_string(level)
        <> ": minXpForLevel "
        <> int.to_string(minimum)
      }
  })
}

pub fn the_item_proficiencies_are_the_classs_starting_item_proficiencies_on_the_real_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each(
    [
      #(1, 18),
      #(2, 66),
      #(3, 262_152),
      #(4, 260),
      #(5, 1_048_580),
      #(7, 4104),
    ],
    fn(class_and_mask) {
      let #(class, mask) = class_and_mask
      let state =
        state_of(frames: frames(
          tables: client_tables.shared(),
          character: character(class:, level: 1),
        ))
      assert state.item_proficiencies == mask
        as {
          "opcode.0x25e.safe_body, Class row "
          <> int.to_string(class)
          <> ": startingItemProficiencies "
          <> int.to_string(mask)
        }
    },
  )
}

pub fn the_costume_key_set_and_action_set_are_the_clients_start_values_and_every_list_is_empty_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(classes, fn(class) {
    let state =
      state_of(frames: frames(
        tables: character_tables.shared(),
        character: character(class:, level: 1),
      ))
    assert state.costume_index == 0xFFFFFFFF
      as "opcode.0x25e.safe_body: -1, the value the client starts with"
    assert state.input_key_set == 3
      as "opcode.0x25e.safe_body: 3, the client's start value"
    assert state.active_action_set == 0
      as "opcode.0x25e.safe_body: below 4; the entry's bar is set 0"
    assert state.held_items == []
      as "opcode.0x25e.safe_body: no items, the server sends them by 0x111"
    assert state.reputations == ReputationList(field_1: 0, reputations: [])
      as "opcode.0x25e.safe_body: no reputations"
    assert state.pets == [] as "opcode.0x25e.safe_body: no pets"
    assert state.unlocked_amps == []
      as "opcode.0x25e.safe_body: no AMPs, and the client's list holds at most 54"
    assert state.character_entitlements == []
      as "opcode.0x25e.safe_body: no entitlements"
    assert state.currencies == <<0:size(960)>>
      as "opcode.0x25e: 15 amounts of 64 bits, all 0"
    assert state.supply_satchel_counts == <<0:size(8192)>>
      as "opcode.0x25e.safe_body: a 0 count is not copied"
    assert bit_array.byte_size(state.currencies) == 120
    assert state.money_trade_limit == 0
    assert state.rest_experience == 0
    assert state.elder_points == 0
    assert state.periodic_elder_points == 0
    assert state.bonus_amp_power == 0
    assert state.bonus_ability_tier_points == 0
    assert state.bind_point == 0
    assert state.attribute_points == 0
    assert state.pvp_flag_time_left_ms == 0
    assert state.gear_score == 0
    assert state.is_pvp_server == 0
    assert state.field_23 == 0
      as "opcode.0x25e.safe_body: every other value is 0"
  })
}

//// A kill's experience across a camp and a second entry, on the game connection
//// (`genesis_prime/game/connection`). Expected values come from these places.
//// - `opcode.0x25e` and `opcode.0x25e.safe_body`: the client takes its experience from
////   the 0x25E of an entry, so the experience a camp saved is the one the next entry
////   sends; the character's level stands.
//// - XpPerLevel.minXpForLevel: level 2 from 655 experience.
//// - The amount of a kill is the formula of `experience_test`: round(100 x 0.25 x 0.2 x 1)
////   = 5 for a level 1 player and a level 1 Beast (Creature2 73464).
//// - The stay rule the connection applies to `Struck` and `FightTold`: a message for a
////   stay other than the connection's current one, or for a player not in the world, is
////   dropped; a credit that waits behind a camp's final save meets it.
//// - `player.level1_base_health` and `CreatureLevel`: a player's Base Health (property 7)
////   is the row of its level plus its worn items'. Row 1's 135.97 and row 2's 216.533
////   (`gleam run -m genesis_prime/table_rows -- CreatureLevel 1 2`, unitPropertyValue07)
////   with the Novice set's 600 give 736 and 817 (816.533 rounded).
//// The store's part is played by the test: the experience the camp's save asks the
//// store to keep is the experience the store gives the next entry.

import connection_rule_support
import experience_support as experience
import fixture_tables
import game_connection_support as support
import genesis_prime/client_connection.{PropertiesChanged}
import genesis_prime/message/experience_gained.{
  type ExperienceGained, ExperienceGained,
}
import genesis_prime/message/float32
import genesis_prime/message/player_character_state
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/store
import genesis_prime/table/id.{Item2Id}
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/option.{Some}
import map_support
import owned_test
import world_entry_support

/// The 0x1ac of a kill of 5 as the client reads it.
fn gain_of_5() -> ExperienceGained {
  ExperienceGained(
    experience: 5,
    rest_experience_used: 0,
    bonus_experience: 0,
    source_kind: 2,
    source_unit_id: experience.creature_unit_id,
  )
}

pub fn experience_saved_at_camp_is_sent_in_player_character_state_on_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  // 650 experience at level 1: a kill of 5 reaches 655 and level 2.
  let state = experience.entered_at(level: 1, saved_experience: Some(650))
  let #(state, credit) =
    experience.credited(state:, creature_id: 73_464, level: 1)
  assert experience.gains(taken: credit) == [gain_of_5()]
  let #(camped, saved, level) = experience.camped(state:)
  assert #(saved, level) == #(655, 2)
    as "the camp's save asks the store to keep the experience and the level the kill made"
  // The store gives the next entry what the save kept.
  let #(_, entry) =
    support.entered_holding(
      in_character_select: camped,
      character: store.Character(..support.world_character(), level:),
      saved_experience: Some(saved),
    )
  let assert [sent] =
    support.decoded(
      support.heard(entry, support.keyed()),
      player_character_state.message_id,
      player_character_state.decode,
    )
    as "the second entry sends its one 0x25E"
  assert sent.experience == 655
    as "opcode.0x25e: the 0x25E carries the experience the camp saved"
  assert unit_fields.stat(tail: support.player_in(entry).tail, stat_id: 10)
    == Ok(2)
    as "and the level stands: the unit's stat 10 is 2"
}

pub fn a_credit_for_a_player_who_left_is_dropped_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = experience.entered_at(level: 1, saved_experience: Some(650))
  let #(camped, saved, level) = experience.camped(state:)
  assert #(saved, level) == #(650, 1)
  // The credit is for the first stay: the player has camped out of it.
  let #(after, taken) =
    experience.credited(state: camped, creature_id: 73_464, level: 1)
  assert connection_rule_support.written_frames(taken) == []
    as "a credit for a camped player writes nothing"
  assert connection_rule_support.effects_of(taken) == []
    as "and asks and tells nothing"
  assert after == camped as "and changes nothing"
  // The player enters again: its second stay. A credit of its first is dropped.
  let #(second, _) =
    support.entered_holding(
      in_character_select: camped,
      character: store.Character(..support.world_character(), level:),
      saved_experience: Some(saved),
    )
  let #(after, taken) =
    experience.credited_in(
      state: second,
      stay: support.own_stay(),
      creature_id: 73_464,
      level: 1,
    )
  assert connection_rule_support.effects_of(taken) == []
    as "a credit of an earlier stay sends, asks and tells nothing"
  assert after == second as "and changes nothing"
  let #(_, taken) =
    experience.credited_in(
      state: second,
      stay: map_support.stay(count: 2),
      creature_id: 73_464,
      level: 1,
    )
  assert experience.gains(taken:) == [gain_of_5()]
    as "while one of the present stay still counts"
}

pub fn a_level_up_sends_property_7_at_the_new_level_test() -> Nil {
  use <- owned_test.run(10_000)
  // 650 experience at level 1: a kill of 5 reaches 655 and level 2 (XpPerLevel).
  let state =
    support.watched_by(
      state: experience.entered_at(level: 1, saved_experience: Some(650)),
      viewers: [2, 3],
    )
  let #(_, credit) = experience.credited(state:, creature_id: 73_464, level: 1)
  assert experience.level_writes(taken: credit) == [#(support.own_unit_id, 2)]
    as "the kill makes level 2"
  let entry =
    UnitProperty(
      property_id: 7,
      base: float32.to_bits(817.0),
      value: float32.to_bits(817.0),
    )
  let written =
    list.map(
      support.decoded(
        support.written(credit),
        0x093A,
        unit_properties_changed.decode,
      ),
      fn(message) {
        assert message.unit_id == support.own_unit_id
        message.properties
      },
    )
  assert written == [[entry]]
    as "0x93a {7 = CreatureLevel row 2's 216.533 and the worn 600, rounded: 817}, and nothing else: only the level's property moves"
  list.each([2, 3], fn(viewer) {
    assert list.contains(
      support.news_told(taken: credit, viewer:),
      PropertiesChanged(properties: [entry]),
    )
      as "each viewer is told the same entry"
  })
}

/// Item2 27106 is a level-scaled heavy armor chest (flags bit 3) worn in the chest slot, over
/// the Novice set without its chest, by a level 3 player with 2859 experience: a kill of
/// 5 reaches 2864, level 4 (XpPerLevel.minXpForLevel 2860). The 0x93a that follows the
/// level holds every property the level moved: Base Health, the armor's budget property
/// 34 and its Assault Rating and Armor, each at level 4. Base Health is CreatureLevel row
/// 4's 569.698, the Novice set without the chest's 450 and the armor's 300, rounded:
/// 1320. The armor's values at level 4 are the client's code run on the row: 34 =
/// 111.25, Assault Rating 18.0 over the set's 194.0625, Armor 125.0 over its 187.5.
pub fn a_level_up_resends_the_properties_of_level_scaled_gear_test() -> Nil {
  use <- owned_test.run(10_000)
  let character = store.Character(..support.world_character(), level: 3)
  let worn =
    list.filter(world_entry_support.novice_items(character:), fn(item) {
      item.bag_index != 0
    })
  let state =
    support.entered_with_items(character:, saved_experience: Some(2859), items: [
      store.HeldItem(
        item_guid: 9,
        item2_id: Item2Id(fixture_tables.root(table: "Item2", id: 27_106)),
        location: 0,
        bag_index: 0,
        stack_count: 1,
        random_stats: 0,
      ),
      ..worn
    ])
  let #(_, credit) = experience.credited(state:, creature_id: 73_464, level: 1)
  assert experience.level_writes(taken: credit) == [#(support.own_unit_id, 4)]
    as "the kill makes level 4"
  let written =
    list.map(
      support.decoded(
        support.written(credit),
        0x093A,
        unit_properties_changed.decode,
      ),
      fn(message) {
        assert message.unit_id == support.own_unit_id
        message.properties
      },
    )
  assert written
    == [
      [
        support.property(id: 7, number: 1320.0),
        support.property(id: 34, number: 111.25),
        support.property(id: 35, number: 212.0625),
        support.property(id: 42, number: 312.5),
      ],
    ]
    as "0x93a: Base Health, the budget property, the Assault Rating and the Armor of the level-scaled chest at level 4, and nothing else"
}

//// What world entry sends in 0x092C, the player's reward properties
//// (`genesis_prime/game/world_entry`, `genesis_prime/game/reward_property`).
//// Expected values come from these places.
//// - `opcode.0x92c.bag_slots`: the client reads how many bag slots a worn bag may
////   take from BagSlots (property 26) and how many bank bag slots from BankSlots
////   (13), integers with data 0, which the premium tier it was sent gives: Hybrid
////   tier 1 gives 4 and 2 (`reward_property_test`).
//// - The body is the schema's layout (`schema.toml`, 0x140c1f178): an 8-bit count
////   of entries, and for each the property in 6 bits, the data in 32, the value as
////   a 2-bit type 1 and 32 bits, and an 8-bit count of modifiers, each value
////   starting at the next bit, least significant bit first. Two entries are
////   8 + 2 x (6 + 32 + 2 + 32 + 8) = 168 bits, 21 bytes.
//// - The message comes once per play, after 0x19B (the unit that is the player).
////   Where in the entry burst the client wants it is not proven by the client; the
////   server's place is the one `world_entry` states.

import cast_support
import character_tables
import genesis_prime/message/reward_properties.{RewardProperties}
import genesis_prime/message/reward_property_entry.{RewardPropertyEntry}
import genesis_prime/message/reward_property_integer.{RewardPropertyInteger}
import gleam/list
import owned_test
import world_entry_support

pub fn entry_sends_the_reward_properties_with_bag_and_bank_slots_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let character =
    world_entry_support.character(class: 2, faction: 166, level: 1)
  let #(effects, _) = world_entry_support.entry(tables:, character:)
  let frames = world_entry_support.frames_of(effects:)
  let frame =
    world_entry_support.only_frame(
      frames:,
      message_id: reward_properties.message_id,
    )
  assert reward_properties.decode(frame.body)
    == Ok(
      RewardProperties(properties: [
        RewardPropertyEntry(
          property_id: 26,
          data: 0,
          value: RewardPropertyInteger(value: 4),
          modifiers: [],
        ),
        RewardPropertyEntry(
          property_id: 13,
          data: 0,
          value: RewardPropertyInteger(value: 2),
          modifiers: [],
        ),
      ]),
    )
    as "BagSlots 4 then BankSlots 2, each an integer with data 0 and no modifiers"
  assert frame.body
    == <<
      0x02, 0x1A, 0x00, 0x00, 0x00, 0x40, 0x04, 0x00, 0x00, 0x00, 0x00, 0x0D,
      0x00, 0x00, 0x00, 0x40, 0x02, 0x00, 0x00, 0x00, 0x00,
    >>
    as "the schema's layout, bit by bit"
  let ids = cast_support.ids(frames:)
  let after_the_player_unit = list.drop_while(ids, fn(id) { id != 0x019B })
  assert list.contains(after_the_player_unit, 0x092C)
    as "0x92C is sent after 0x19B"
}

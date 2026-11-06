//// Message 0x025E, the player character's own state, against the client's
//// reader (`0x14008cee0`, the fact file's `opcode.0x25e`). Expected values come
//// from these places.
//// - `opcode.0x25e`: the order and the width of each field. No vector of the
////   client's own bytes exists for it, so the vectors below are packed by hand
////   from the widths: a field's value goes in at its bit offset, lowest bit
////   first, the way the client's reader takes bits (`bit_stream`'s vectors).
////   `packed` does it with one big number, apart from the codec under test.
//// - `opcode.0x25e.safe_body`: the smallest body is 9,768 bits, 1,221 bytes.
////
//// The offsets (in bits) of the body's fixed fields, from the statement of
//// `opcode.0x25e`: held items' count 0, currencies 32, money trade limit 992,
//// experience 1056, rest experience 1088, item proficiencies 1120, elder points
//// 1152, periodic elder points 1184, active action set 1216, bonus AMP power
//// 1219, bonus ability tier points 1235, reputations' 14-bit value 1267 and
//// count 1281, pets' count 1297, input key set 1329, bind point 1361, costume
//// index 1377, attribute points 1409, PvP flag time 1441, unlocked AMPs' count
//// 1473, supply satchel 1479, gear score 9671, is a PvP server 9703, the
//// matching word 9704, entitlements' count 9736, the end 9768.

import genesis_prime/message/bit_stream
import genesis_prime/message/character_entitlement.{CharacterEntitlement}
import genesis_prime/message/held_item.{HeldItem}
import genesis_prime/message/player_character_state.{PlayerCharacterState}
import genesis_prime/message/player_pet.{PlayerPet}
import genesis_prime/message/reputation.{Reputation}
import genesis_prime/message/reputation_list.{ReputationList}
import genesis_prime/message/shared_item.{type SharedItem, SharedItem}
import gleam/bit_array
import gleam/int
import gleam/list
import owned_test

/// One field of a hand-packed body: where it starts in bits, how wide it is
/// and its value.
type Placed {
  Placed(offset: Int, bits: Int, value: Int)
}

/// The bytes of a body of `bits` bits with each field put in at its offset,
/// built as one number whose bit `k` is bit `k` of the stream.
fn packed(bits bits: Int, fields fields: List(Placed)) -> BitArray {
  let number =
    list.fold(fields, 0, fn(number, field) {
      assert field.value < int.bitwise_shift_left(1, field.bits)
        as "a hand-packed value fits its width"
      int.bitwise_or(number, int.bitwise_shift_left(field.value, field.offset))
    })
  list.repeat(Nil, bits / 8)
  |> list.index_map(fn(_, index) {
    <<
      int.bitwise_and(int.bitwise_shift_right(number, index * 8), 255):size(8),
    >>
  })
  |> bit_array.concat
}

fn zeros(count count: Int) -> BitArray {
  <<0:size(count * 8)>>
}

fn minimal() -> player_character_state.PlayerCharacterState {
  PlayerCharacterState(
    held_items: [],
    currencies: zeros(count: 120),
    money_trade_limit: 0,
    experience: 0,
    rest_experience: 0,
    item_proficiencies: 0,
    elder_points: 0,
    periodic_elder_points: 0,
    active_action_set: 0,
    bonus_amp_power: 0,
    bonus_ability_tier_points: 0,
    reputations: ReputationList(field_1: 0, reputations: []),
    pets: [],
    input_key_set: 3,
    bind_point: 0,
    costume_index: 0xFFFFFFFF,
    attribute_points: 0,
    pvp_flag_time_left_ms: 0,
    unlocked_amps: [],
    supply_satchel_counts: zeros(count: 1024),
    gear_score: 0,
    is_pvp_server: 0,
    field_23: 0,
    character_entitlements: [],
  )
}

pub fn the_smallest_body_is_9768_bits_with_experience_proficiencies_costume_and_key_set_in_place_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    PlayerCharacterState(
      ..minimal(),
      experience: 1710,
      item_proficiencies: 1_048_580,
    )
  let expected =
    packed(bits: 9768, fields: [
      Placed(offset: 1056, bits: 32, value: 1710),
      Placed(offset: 1120, bits: 32, value: 1_048_580),
      Placed(offset: 1329, bits: 32, value: 3),
      Placed(offset: 1377, bits: 32, value: 0xFFFFFFFF),
    ])
  assert player_character_state.encode(body) == Ok(expected)
    as "opcode.0x25e.safe_body: 9,768 bits, with experience, proficiencies, key set 3 and costume -1 at the offsets the reader reads them"
  assert bit_array.byte_size(expected) == 1221
    as "opcode.0x25e.safe_body: the whole body is 9,768 bits, which is 1,221 bytes"
  assert player_character_state.decode(expected) == Ok(body)
    as "the same bytes decode to the same values"
}

pub fn every_fixed_field_is_written_at_its_own_width_and_offset_test() -> Nil {
  use <- owned_test.run(5000)
  let currencies = <<0x11, zeros(count: 118):bits, 0x22>>
  let satchel = <<0x5A, zeros(count: 1022):bits, 0xA5>>
  let body =
    PlayerCharacterState(
      held_items: [],
      currencies:,
      money_trade_limit: 0x8000_0000_0000_0001,
      experience: 0x8000_0001,
      rest_experience: 0x8000_0002,
      item_proficiencies: 0x8000_0003,
      elder_points: 0x8000_0004,
      periodic_elder_points: 0x8000_0005,
      active_action_set: 3,
      bonus_amp_power: 0x8001,
      bonus_ability_tier_points: 0x8000_0006,
      reputations: ReputationList(field_1: 0x2001, reputations: []),
      pets: [],
      input_key_set: 0x8000_0007,
      bind_point: 0x8002,
      costume_index: 0x8000_0008,
      attribute_points: 0x8000_0009,
      pvp_flag_time_left_ms: 0x8000_000A,
      unlocked_amps: [],
      supply_satchel_counts: satchel,
      gear_score: 0x3F80_0000,
      is_pvp_server: 1,
      field_23: 0x8000_000B,
      character_entitlements: [],
    )
  let expected =
    packed(bits: 9768, fields: [
      Placed(offset: 32, bits: 8, value: 0x11),
      Placed(offset: 32 + 119 * 8, bits: 8, value: 0x22),
      Placed(offset: 992, bits: 64, value: 0x8000_0000_0000_0001),
      Placed(offset: 1056, bits: 32, value: 0x8000_0001),
      Placed(offset: 1088, bits: 32, value: 0x8000_0002),
      Placed(offset: 1120, bits: 32, value: 0x8000_0003),
      Placed(offset: 1152, bits: 32, value: 0x8000_0004),
      Placed(offset: 1184, bits: 32, value: 0x8000_0005),
      Placed(offset: 1216, bits: 3, value: 3),
      Placed(offset: 1219, bits: 16, value: 0x8001),
      Placed(offset: 1235, bits: 32, value: 0x8000_0006),
      Placed(offset: 1267, bits: 14, value: 0x2001),
      Placed(offset: 1329, bits: 32, value: 0x8000_0007),
      Placed(offset: 1361, bits: 16, value: 0x8002),
      Placed(offset: 1377, bits: 32, value: 0x8000_0008),
      Placed(offset: 1409, bits: 32, value: 0x8000_0009),
      Placed(offset: 1441, bits: 32, value: 0x8000_000A),
      Placed(offset: 1479, bits: 8, value: 0x5A),
      Placed(offset: 1479 + 1023 * 8, bits: 8, value: 0xA5),
      Placed(offset: 9671, bits: 32, value: 0x3F80_0000),
      Placed(offset: 9703, bits: 1, value: 1),
      Placed(offset: 9704, bits: 32, value: 0x8000_000B),
    ])
  assert player_character_state.encode(body) == Ok(expected)
    as "opcode.0x25e: each fixed field is written at the offset and width the statement gives"
  assert player_character_state.decode(expected) == Ok(body)
    as "and read back from them"
}

fn item() -> SharedItem {
  SharedItem(
    item_guid: 0x1234,
    field_2: 0,
    item_id: 4321,
    location: 4,
    bag_index: 2,
    stack_count: 1,
    charges: 0,
    field_8: 0,
    field_9: 0,
    field_10: 0,
    durability: 0x3F80_0000,
    field_12: 0,
    field_13: 0,
    field_14: 0,
    field_15: 0,
    field_16: 0,
    field_17: 0,
    field_18: 0,
    field_19: 0,
    field_20: 0,
    field_21: 0,
    field_22: 0,
    field_23: 0,
    list_a: [],
    list_b: [],
    field_27: 0,
  )
}

/// The width of one held item in a list: the shared item's 776 bits (the fixed
/// widths of the schema's `shared_item` record, with its three small counts and
/// its 6-bit constant) and the 6-bit reason.
const item_bits = 782

/// The widths of one reputation (a 14-bit Faction2 id and a 32-bit float), one pet
/// (a 32-bit unit id and values of 18, 5 and 5 bits) and one unlocked AMP:
/// `opcode.0x25e`.
const reputation_bits = 46

const pet_bits = 60

const amp_bits = 16

pub fn one_entry_in_each_list_is_counted_and_written_at_its_element_widths_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    PlayerCharacterState(
      ..minimal(),
      experience: 1710,
      held_items: [HeldItem(item: item(), reason: 49)],
      reputations: ReputationList(field_1: 0, reputations: [
        Reputation(faction_id: 166, value: 0x4000_0000),
      ]),
      pets: [PlayerPet(unit_id: 77, field_2: 0x20001, field_3: 17, field_4: 18)],
      unlocked_amps: [54],
      character_entitlements: [
        CharacterEntitlement(entitlement_id: 0x2001, count: 5),
      ],
    )
  // Each list's entries push the fields after it later by their widths.
  let after_items = item_bits
  let after_reputations = after_items + reputation_bits
  let after_pets = after_reputations + pet_bits
  let after_amps = after_pets + amp_bits
  let expected =
    packed(bits: 10_720, fields: [
      Placed(offset: 0, bits: 32, value: 1),
      Placed(offset: 32, bits: 64, value: 0x1234),
      Placed(offset: 32 + 128, bits: 18, value: 4321),
      Placed(offset: 32 + 146, bits: 9, value: 4),
      Placed(offset: 32 + 155, bits: 32, value: 2),
      Placed(offset: 32 + 187, bits: 32, value: 1),
      Placed(offset: 32 + 411, bits: 32, value: 0x3F80_0000),
      Placed(offset: 32 + 776, bits: 6, value: 49),
      Placed(offset: 1056 + after_items, bits: 32, value: 1710),
      Placed(offset: 1281 + after_items, bits: 16, value: 1),
      Placed(offset: 1297 + after_items, bits: 14, value: 166),
      Placed(offset: 1297 + after_items + 14, bits: 32, value: 0x4000_0000),
      Placed(offset: 1297 + after_reputations, bits: 32, value: 1),
      Placed(offset: 1329 + after_reputations, bits: 32, value: 77),
      Placed(offset: 1329 + after_reputations + 32, bits: 18, value: 0x20001),
      Placed(offset: 1329 + after_reputations + 50, bits: 5, value: 17),
      Placed(offset: 1329 + after_reputations + 55, bits: 5, value: 18),
      Placed(offset: 1329 + after_pets, bits: 32, value: 3),
      Placed(offset: 1377 + after_pets, bits: 32, value: 0xFFFFFFFF),
      Placed(offset: 1473 + after_pets, bits: 6, value: 1),
      Placed(offset: 1479 + after_pets, bits: 16, value: 54),
      Placed(offset: 9736 + after_amps, bits: 32, value: 1),
      Placed(offset: 9768 + after_amps, bits: 14, value: 0x2001),
      Placed(offset: 9768 + after_amps + 14, bits: 32, value: 5),
    ])
  assert player_character_state.encode(body) == Ok(expected)
    as "opcode.0x25e: each list's count in its own width (32, 16, 32, 6 and 32 bits) and each entry at its element's width"
  assert player_character_state.decode(expected) == Ok(body)
    as "and read back from them"
}

pub fn lists_of_several_entries_round_trip_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    PlayerCharacterState(
      ..minimal(),
      held_items: [
        HeldItem(item: item(), reason: 49),
        HeldItem(item: item(), reason: 1),
      ],
      reputations: ReputationList(field_1: 0, reputations: [
        Reputation(faction_id: 166, value: 0x3F80_0000),
        Reputation(faction_id: 0x3FFF, value: 0xBF80_0000),
      ]),
      pets: [
        PlayerPet(unit_id: 77, field_2: 0x3FFFF, field_3: 31, field_4: 31),
        PlayerPet(unit_id: 78, field_2: 1, field_3: 1, field_4: 1),
      ],
      unlocked_amps: [1, 54, 0xFFFF],
      character_entitlements: [
        CharacterEntitlement(entitlement_id: 0x3FFF, count: 0xFFFF_FFFF),
        CharacterEntitlement(entitlement_id: 1, count: 1),
      ],
    )
  let assert Ok(bytes) = player_character_state.encode(body)
    as "a body with several entries in every list encodes"
  assert player_character_state.decode(bytes) == Ok(body)
    as "opcode.0x25e: it reads back as written"
}

pub fn a_body_that_ends_inside_the_last_field_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert player_character_state.decode(zeros(count: 1220))
    == Error(bit_stream.EndOfData)
    as "opcode.0x25e.safe_body: a body of 1,220 bytes ends inside the last field, where the reader fails"
}

pub fn an_action_set_of_4_or_more_is_refused_since_the_clients_action_bar_would_be_empty_test() -> Nil {
  use <- owned_test.run(5000)
  assert player_character_state.encode(
      PlayerCharacterState(..minimal(), active_action_set: 4),
    )
    == Error(bit_stream.ValueAtOrAboveLimit("active_action_set", 4, 4))
    as "opcode.0x25e.safe_body: 4 to 7 makes every action bar shortcut lookup answer none"
}

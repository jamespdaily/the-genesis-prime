//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x025E (player_character_state), server to client: the player
//// character's own state on entering the world, sent once right after message
//// 0x19B has set the player: held items, currencies, experience, points,
//// reputations, pets, settings, unlocked AMPs, the supply satchel and
//// entitlements; its handler then raises CharacterCreated, which the class
//// resource bar and about 25 other addons wait for; the unlocked AMPs are at
//// most 54, the cap the client's other writer of the list applies, since the
//// handler copies the count it reads into room for 56. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x25e` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/character_entitlement.{type CharacterEntitlement}
import genesis_prime/message/held_item.{type HeldItem}
import genesis_prime/message/player_pet.{type PlayerPet}
import genesis_prime/message/reputation_list.{type ReputationList}
import gleam/result

/// The message's number.
pub const message_id = 0x025E

/// The body of message 0x025E, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type PlayerCharacterState {
  PlayerCharacterState(
    held_items: List(HeldItem),
    currencies: BitArray,
    money_trade_limit: Int,
    experience: Int,
    rest_experience: Int,
    item_proficiencies: Int,
    elder_points: Int,
    periodic_elder_points: Int,
    active_action_set: Int,
    bonus_amp_power: Int,
    bonus_ability_tier_points: Int,
    reputations: ReputationList,
    pets: List(PlayerPet),
    input_key_set: Int,
    bind_point: Int,
    costume_index: Int,
    attribute_points: Int,
    pvp_flag_time_left_ms: Int,
    unlocked_amps: List(Int),
    supply_satchel_counts: BitArray,
    gear_score: Int,
    is_pvp_server: Int,
    /// Safe by `opcode.0x25e.safe_body`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    field_23: Int,
    character_entitlements: List(CharacterEntitlement),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: PlayerCharacterState) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_array(
    "held_items",
    message.held_items,
    32,
    held_item.write,
  )
  |> bit_stream.write_raw_bytes("currencies", message.currencies, 120)
  |> bit_stream.write_unsigned(
    "money_trade_limit",
    message.money_trade_limit,
    64,
  )
  |> bit_stream.write_unsigned("experience", message.experience, 32)
  |> bit_stream.write_unsigned("rest_experience", message.rest_experience, 32)
  |> bit_stream.write_unsigned(
    "item_proficiencies",
    message.item_proficiencies,
    32,
  )
  |> bit_stream.write_unsigned("elder_points", message.elder_points, 32)
  |> bit_stream.write_unsigned(
    "periodic_elder_points",
    message.periodic_elder_points,
    32,
  )
  |> bit_stream.write_unsigned_below(
    "active_action_set",
    message.active_action_set,
    3,
    4,
  )
  |> bit_stream.write_unsigned("bonus_amp_power", message.bonus_amp_power, 16)
  |> bit_stream.write_unsigned(
    "bonus_ability_tier_points",
    message.bonus_ability_tier_points,
    32,
  )
  |> reputation_list.write(message.reputations)
  |> bit_stream.write_array("pets", message.pets, 32, player_pet.write)
  |> bit_stream.write_unsigned("input_key_set", message.input_key_set, 32)
  |> bit_stream.write_unsigned("bind_point", message.bind_point, 16)
  |> bit_stream.write_unsigned("costume_index", message.costume_index, 32)
  |> bit_stream.write_unsigned("attribute_points", message.attribute_points, 32)
  |> bit_stream.write_unsigned(
    "pvp_flag_time_left_ms",
    message.pvp_flag_time_left_ms,
    32,
  )
  |> bit_stream.write_unsigned_array(
    "unlocked_amps",
    message.unlocked_amps,
    6,
    16,
  )
  |> bit_stream.write_raw_bytes(
    "supply_satchel_counts",
    message.supply_satchel_counts,
    1024,
  )
  |> bit_stream.write_float32_bits("gear_score", message.gear_score)
  |> bit_stream.write_unsigned("is_pvp_server", message.is_pvp_server, 1)
  |> bit_stream.write_unsigned("field_23", message.field_23, 32)
  |> bit_stream.write_array(
    "character_entitlements",
    message.character_entitlements,
    32,
    character_entitlement.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PlayerCharacterState, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(held_items, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    held_item.read,
  ))
  use #(currencies, reader) <- result.try(bit_stream.read_raw_bytes(reader, 120))
  use #(money_trade_limit, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(experience, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(rest_experience, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(item_proficiencies, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(elder_points, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(periodic_elder_points, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(active_action_set, reader) <- result.try(bit_stream.read_unsigned_below(
    reader,
    "active_action_set",
    3,
    4,
  ))
  use #(bonus_amp_power, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use #(bonus_ability_tier_points, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(reputations, reader) <- result.try(reputation_list.read(reader))
  use #(pets, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    player_pet.read,
  ))
  use #(input_key_set, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(bind_point, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(costume_index, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(attribute_points, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(pvp_flag_time_left_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(unlocked_amps, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    6,
    16,
  ))
  use #(supply_satchel_counts, reader) <- result.try(bit_stream.read_raw_bytes(
    reader,
    1024,
  ))
  use #(gear_score, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(is_pvp_server, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(field_23, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(character_entitlements, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    character_entitlement.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(PlayerCharacterState(
    held_items:,
    currencies:,
    money_trade_limit:,
    experience:,
    rest_experience:,
    item_proficiencies:,
    elder_points:,
    periodic_elder_points:,
    active_action_set:,
    bonus_amp_power:,
    bonus_ability_tier_points:,
    reputations:,
    pets:,
    input_key_set:,
    bind_point:,
    costume_index:,
    attribute_points:,
    pvp_flag_time_left_ms:,
    unlocked_amps:,
    supply_satchel_counts:,
    gear_score:,
    is_pvp_server:,
    field_23:,
    character_entitlements:,
  ))
}

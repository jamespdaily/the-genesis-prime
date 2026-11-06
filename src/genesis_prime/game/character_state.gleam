//// The player character's own state, which world entry sends once in message
//// 0x025E right after 0x19B. The client's handler keeps every field and then
//// raises `CharacterCreated`, which the class resource bar and about 25 other
//// addons wait for (`lua.event.CharacterCreated`, `opcode.0x25e`).
////
//// ```
//// Character.level  ─▶ XpPerLevel row with that ID ─▶ experience (minXpForLevel)
//// Character.class  ─▶ Class row ─▶ item_proficiencies (startingItemProficiencies)
//// the client's start values ─▶ costume index -1, input key set 3, action set 0
//// every other field          ─▶ 0 or empty (the server's choices below)
//// ```
////
//// - **Experience** is the least experience of the saved level, so the client's
////   progress shows the level the character is (`opcode.0x25e.safe_body`,
////   GetLevelForExperience `0x140029820`). No experience beyond it is saved.
//// - **Item proficiencies** are the class's `Class.startingItemProficiencies`; the
////   client's proficiency test fails every ItemProficiency row with a mask when
////   the mask is 0 (`0x1403ca2b0`).
//// - **The start values** are the client's own for a new game object: costume
////   index -1 (the value 0 would make the first costume slot the active one),
////   input key set 3, action set 0 (a value of 4 or more empties the action bar)
////   (`0x1403e1400`, `opcode.0x25e.safe_body`).
//// - **Server choices of 0 or empty**, until the system that holds each is built.
////   Each is the client's value for a character with none of it:
////   - the items, equipment, vendors, levels and currency system fills the held
////     items (world entry sends them one by one in 0x111), the 15 currencies, the
////     money trade limit, the rest experience and the gear score;
////   - the player and account system fills the elder points, the periodic elder
////     points, the attribute points, the bonus AMP power, the bonus ability tier
////     points, the unlocked AMPs (the client's list holds at most 54, so the list
////     it fills is capped there) and the character entitlements;
////   - the quests, zones and prerequisites system fills the reputations and the
////     bind point;
////   - the spells system fills the pets a player has summoned;
////   - the crafting and gathering system fills the supply satchel;
////   - the instances, matching and PvP system fills the PvP flag time left, and
////     the server is not a PvP server until it does;
////   - the matching word has no use the client's code shows, and stays 0
////     (`opcode.0x25e.safe_body`).

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/player_character_state.{PlayerCharacterState}
import genesis_prime/message/reputation_list.{ReputationList}
import genesis_prime/store.{type Character}
import genesis_prime/table/class
import genesis_prime/table/id.{XpPerLevelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import gleam/int
import gleam/result

/// Why a character has no 0x025E: a row of the client's tables the server's load
/// does not require is missing. The character is not entered.
pub type Refusal {
  /// No XpPerLevel row has the character's level as its ID.
  NoExperienceRow(level: Int)
  /// No Class row has the character's class.
  NoClassRow(class_id: Int)
}

/// A sentence that says why a character has no 0x025E, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NoExperienceRow(level:) ->
      "no XpPerLevel row has the character's level "
      <> int.to_string(level)
      <> " as its ID"
    NoClassRow(class_id:) ->
      "no Class row has the character's class " <> int.to_string(class_id)
  }
}

/// The least experience of a level a character can be (`XpPerLevel`, by the
/// level as the ID), which the client takes as the character's experience.
fn experience(
  tables tables: table_store.Tables,
  character character: Character,
) -> Result(Int, Refusal) {
  xp_per_level.get(tables:, id: XpPerLevelId(character.level))
  |> result.map(fn(row) { row.min_xp_for_level })
  |> result.replace_error(NoExperienceRow(level: character.level))
}

/// The item proficiencies of the character's class, from its Class row.
fn item_proficiencies(
  tables tables: table_store.Tables,
  character character: Character,
) -> Result(Int, Refusal) {
  class.get(tables:, id: character.class_id)
  |> result.map(fn(row) { row.starting_item_proficiencies })
  |> result.replace_error(NoClassRow(class_id: character.class_id.value))
}

/// 0x025E for the character at its level and class: the experience and the item
/// proficiencies the tables give, the client's start values, and every other
/// field 0 or empty.
pub fn frame(
  tables tables: table_store.Tables,
  character character: Character,
) -> Result(Frame, Refusal) {
  use experience <- result.try(experience(tables:, character:))
  use item_proficiencies <- result.map(item_proficiencies(tables:, character:))
  let assert Ok(body) =
    player_character_state.encode(
      PlayerCharacterState(
        held_items: [],
        currencies: <<0:size(960)>>,
        money_trade_limit: 0,
        experience:,
        rest_experience: 0,
        item_proficiencies:,
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
        supply_satchel_counts: <<0:size(8192)>>,
        gear_score: 0,
        is_pvp_server: 0,
        field_23: 0,
        character_entitlements: [],
      ),
    )
    as "a table's minXpForLevel and a class's proficiency mask of 32 bits fit the message"
  Frame(message_id: player_character_state.message_id, body:)
}

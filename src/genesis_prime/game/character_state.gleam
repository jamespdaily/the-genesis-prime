//// The player character's own state, which world entry sends once in message
//// 0x025E right after 0x19B. The client's handler keeps every field and then
//// raises `CharacterCreated`, which the class resource bar and about 25 other
//// addons wait for (`lua.event.CharacterCreated`, `opcode.0x25e`).
////
//// ```
//// the character's experience (saved, or the least of its level: genesis_prime/game/experience)
//// Character.class  ─▶ Class row ─▶ item_proficiencies (startingItemProficiencies)
//// the client's start values ─▶ costume index -1, input key set 3, action set 0
//// every other field          ─▶ 0 or empty
//// ```
////
//// - **Experience** is the character's own, given by world entry: the experience its
////   last save kept, or the least experience of its level when none was saved, so
////   the client's progress shows the level the character is
////   (`opcode.0x25e.safe_body`, GetLevelForExperience `0x140029820`). World entry
////   refuses a level with no XpPerLevel row before the map is asked
////   (genesis_prime/game/experience).
//// - **Item proficiencies** are the class's `Class.startingItemProficiencies`; the
////   client's proficiency test fails every ItemProficiency row with a mask when
////   the mask is 0 (`0x1403ca2b0`). The load requires a Class row for each
////   playable class (`requirements`).
//// - **The start values** are the client's own for a new game object: costume
////   index -1 (the value 0 would make the first costume slot the active one),
////   input key set 3, action set 0 (a value of 4 or more empties the action bar)
////   (`0x1403e1400`, `opcode.0x25e.safe_body`).
//// - **Sent as 0 or empty**, each the client's value for a character with none of
////   it (`opcode.0x25e.safe_body`): the held items (world entry sends them in
////   0x111), the 15 currencies, the money trade limit, the rest experience, the
////   elder points, the periodic elder points, the attribute points, the bonus AMP
////   power, the bonus ability tier points, no unlocked AMPs (the client's list
////   holds at most 54), no reputations, no pets, the bind point, the PvP flag time
////   left (0 is no flag), the supply satchel, the gear score, no PvP server, no
////   character entitlements and the matching word, which the client's code gives
////   no use.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/class_resource
import genesis_prime/message/player_character_state.{PlayerCharacterState}
import genesis_prime/message/reputation_list.{ReputationList}
import genesis_prime/store.{type Character}
import genesis_prime/table/class
import genesis_prime/table/id.{type ClassId, ClassId}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/result

/// The load's check that the Class rows 0x025E reads exist, so a client without
/// one fails the server's start: a row for each playable class.
pub fn requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "the server's playable classes",
      column: "Class id",
      to_table: "Class",
      missing: fn(tables) {
        list.filter(class_resource.playable_class_ids(), fn(class_id) {
          result.is_error(class.get(tables:, id: ClassId(class_id)))
        })
      },
    ),
  ]
}

/// The mask of item proficiencies the class starts with, which 0x025E tells the
/// client and the equip check reads (`Class.startingItemProficiencies`).
pub fn item_proficiencies(
  tables tables: table_store.Tables,
  class_id class_id: ClassId,
) -> Int {
  let assert Ok(class_row) = class.get(tables:, id: class_id)
    as "character creation makes only playable classes, and the load requires a Class row for each"
  class_row.starting_item_proficiencies
}

/// 0x025E for the character at its class with its `experience`, the class's item
/// proficiencies, the client's start values, and every other field 0 or empty.
pub fn frame(
  tables tables: table_store.Tables,
  character character: Character,
  experience experience: Int,
) -> Frame {
  let assert Ok(body) =
    player_character_state.encode(
      PlayerCharacterState(
        held_items: [],
        currencies: <<0:size(960)>>,
        money_trade_limit: 0,
        experience:,
        rest_experience: 0,
        item_proficiencies: item_proficiencies(
          tables:,
          class_id: character.class_id,
        ),
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
    as "an experience below 2147483648 and a class's proficiency mask of 32 bits fit the message"
  Frame(message_id: player_character_state.message_id, body:)
}

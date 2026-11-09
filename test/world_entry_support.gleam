//// What the world entry tests share: a character's entry through the rule
//// (`genesis_prime/game/world_entry`) on the tables given, with the effects it
//// decided and the player it keeps.

import character_support
import class_resource_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/message/item_added
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/step.{type Now, ConnectionId, Now}
import genesis_prime/store.{
  type Character, type HeldItem, type QuestRow, AccountId, Character,
  CharacterId, HeldItem, NameStands,
}
import genesis_prime/table/id.{ClassId, Item2Id, RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map
import genesis_prime/world_map/player_unit
import gleam/list
import gleam/option.{type Option, None, Some}
import map_support
import novice_tables
import place_support
import spawn_support
import unit_support

/// The system time every entry of the tests is made at, as a FILETIME.
pub const filetime = 133_900_000_000_000_000

/// The time every entry of the tests is made at.
pub fn now() -> Now {
  Now(monotonic_ms: 0, filetime:)
}

/// What the store's answer to a play of the character leads to on these tables,
/// when it holds these items: the map is asked, or the play is refused.
pub fn loaded(
  tables tables: table_store.Tables,
  character character: Character,
  items items: List(HeldItem),
) -> #(world_entry.State, world_entry.Loaded) {
  loaded_holding(
    tables:,
    character:,
    items:,
    saved_experience: None,
    quests: [],
  )
}

/// What the store's answer to a play of the character leads to on these tables,
/// when it holds these items, saved experience (`None` for none) and quest rows.
pub fn loaded_holding(
  tables tables: table_store.Tables,
  character character: Character,
  items items: List(HeldItem),
  saved_experience saved_experience: Option(Int),
  quests quests: List(QuestRow),
) -> #(world_entry.State, world_entry.Loaded) {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 42))
    as "a character id fits the message"
  let assert Ok(#(state, _asks)) =
    world_entry.take(account_id: AccountId(7), body:)
    as "the client's request to play decodes"
  let assert Ok(loaded) =
    world_entry.loaded(
      state:,
      answer: store.CharacterLoaded(
        character:,
        session_epoch: character_support.epoch(1),
        saved_health: None,
        saved_experience:,
        items:,
        quests:,
      ),
      connection: ConnectionId(1),
      stay: map_support.stay(count: 1),
      tables:,
    )
    as "the store's answer is the one world entry asked for"
  #(state, loaded)
}

/// The items a character of a created class and faction holds after its create:
/// the Novice set of its CharacterCreation row at location 0, each in the bag
/// index of its slot, with the guids 1 to 7 in bag order. A character of any
/// other class or faction holds none.
pub fn novice_items(character character: Character) -> List(HeldItem) {
  case
    list.find(novice_tables.sets(), fn(set) {
      set.class_id == character.class_id.value
      && set.faction_id == character.faction_id
    })
  {
    Ok(set) ->
      list.index_map(novice_tables.equipped_of(set:), fn(pair, index) {
        HeldItem(
          item_guid: index + 1,
          item2_id: Item2Id(pair.0),
          location: 0,
          bag_index: pair.1,
          stack_count: 1,
        )
      })
    Error(Nil) -> []
  }
}

/// What a character's entry decides on these tables, with the Novice set its
/// create stored: its effects, in order, and the player the connection keeps.
pub fn entry(
  tables tables: table_store.Tables,
  character character: Character,
) -> #(List(world_entry.Effect), world_entry.Entered) {
  entry_holding(tables:, character:, items: novice_items(character:))
}

/// What a character's entry decides on these tables when the store holds these
/// items for it: its effects, in order, and the player the connection keeps.
pub fn entry_holding(
  tables tables: table_store.Tables,
  character character: Character,
  items items: List(HeldItem),
) -> #(List(world_entry.Effect), world_entry.Entered) {
  entry_at(tables:, character:, items:, quests: [], now: now())
}

/// What a character's entry decides on these tables when the store holds these
/// items and quest rows for it and the entry is made at `now`: its effects, in
/// order, and the player the connection keeps.
pub fn entry_at(
  tables tables: table_store.Tables,
  character character: Character,
  items items: List(HeldItem),
  quests quests: List(QuestRow),
  now now: Now,
) -> #(List(world_entry.Effect), world_entry.Entered) {
  let assert world_entry.InTheWorld(entered:, effects:) =
    answered_at(tables:, character:, items:, quests:, now:)
    as "the map's answer to the join puts the player in the world"
  #(effects, entered)
}

/// What the rule makes of the map's answer to a join of the character on these tables
/// when the store holds these items and quest rows for it, made at `now`: the answer
/// the map gives a character of a created class and faction, which holds no health or
/// gear of its own.
pub fn answered_at(
  tables tables: table_store.Tables,
  character character: Character,
  items items: List(HeldItem),
  quests quests: List(QuestRow),
  now now: Now,
) -> world_entry.Joined {
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.0,
      y: -853.0,
      z: -560.0,
    )
  let assert #(_, world_entry.Join(state:, ..)) =
    loaded_holding(tables:, character:, items:, saved_experience: None, quests:)
    as "the store holds the character, its place and its level's row"
  let unit =
    unit_support.novice_unit(tables:, character:, place:, unit_id: 1, body: [])
  let assert Ok(joined) =
    world_entry.joined(
      state:,
      answer: map.Joined(
        unit: player_unit.create(unit:, realm_id: 1),
        loadout: player_unit.loadout(unit:),
        incarnation: 1,
        clock_origin_ms: 0,
      ),
      realm_id: 1,
      next_whisper: 1,
      classes: class_resource_support.classes(),
      numbers: spawn_support.numbers,
      defaults: unit_properties.defaults(tables:),
      tables:,
      now:,
    )
    as "the map's answer to the join is the one world entry asked for"
  joined
}

/// The frames among an entry's effects, in order.
pub fn frames_of(effects effects: List(world_entry.Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      world_entry.Send(frame:) -> Ok(frame)
      world_entry.AskStore(..)
      | world_entry.AskMap(..)
      | world_entry.WatchMap(..)
      | world_entry.Life(..)
      | world_entry.StartPassive(..)
      | world_entry.Warn(..) -> Error(Nil)
    }
  })
}

/// A character of the class, faction and level, a human male at the planted start
/// place of World 3460, that the world entry tests play.
pub fn character(
  class class: Int,
  faction faction: Int,
  level level: Int,
) -> Character {
  Character(
    character_id: CharacterId(42),
    name: "Ab Cd",
    gender: 0,
    race_id: RaceId(1),
    class_id: ClassId(class),
    faction_id: faction,
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

/// The `item_added` (0x0111) messages among the frames, decoded, in order.
pub fn items_added(frames frames: List(Frame)) -> List(item_added.ItemAdded) {
  list.filter(frames, fn(frame) { frame.message_id == item_added.message_id })
  |> list.map(fn(frame) {
    let assert Ok(added) = item_added.decode(frame.body)
      as "an item_added decodes"
    added
  })
}

/// The one frame with this message id among the frames.
pub fn only_frame(
  frames frames: List(Frame),
  message_id message_id: Int,
) -> Frame {
  let assert [frame] =
    list.filter(frames, fn(frame) { frame.message_id == message_id })
    as "the entry sends the message once"
  frame
}

//// What the world entry tests share: a character's entry through the rule
//// (`genesis_prime/game/world_entry`) on the tables given, with the effects it
//// decided and the player it keeps.

import character_support
import character_tables
import class_resource_support
import connection_rule_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/limited_action_set
import genesis_prime/game/objective
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/message/item_added
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/step.{type Now, ConnectionId, Now}
import genesis_prime/store.{
  type Character, type HeldItem, type QuestRow, type UnsetItem, AccountId,
  Character, CharacterId, HeldItem, NameStands,
}
import genesis_prime/table/id.{ClassId, Item2Id, RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/spawn_id.{type StoredSpawns}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import map_support
import novice_tables
import place_support
import spawn_support
import tutorial_support
import unit_support

/// The system time every entry of the tests is made at, as a FILETIME.
pub const filetime = 133_900_000_000_000_000

/// The Spell4Base of each alternate spell the class's abilities at the level name, in bag order:
/// the ability book holds them (GetAbilityBookSpell `0x1403bad30`), after the bag. Spell4.43468
/// (Quick Draw) names 76002 of base 52215 and Spell4.34718 (Charged Shot) names 34719 of base
/// 20685 in `spell4IdMechanicAlternateSpell`; no other class's level-1 spell names one. The
/// Spellslinger's SpellLevel 1012 (Spell4 34756, level 4) names 79171 of base 54909; its
/// level-6 Runes of Protection (SpellLevel 1144, Spell4 39092, base 23441) names 39327 of base
/// 23661 and its level-6 Vitality Burst (Spell4 39132, base 23479) names 39133 of base 23480
/// (`table_rows -- Spell4 39092 39327 39132 39133`), in bag order; the Spellslinger's other
/// rows through level 6 name none that is planned.
pub fn alternate_bases(class_id class_id: Int, level level: Int) -> List(Int) {
  case class_id, level >= 6, level >= 4 {
    7, True, _ -> [52_215, 20_685, 54_909, 23_661, 23_480]
    7, False, True -> [52_215, 20_685, 54_909]
    7, False, False -> [52_215, 20_685]
    _, _, _ -> []
  }
}

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
  loaded_seeing(
    tables:,
    character:,
    items:,
    saved_health: None,
    saved_experience:,
    quests:,
    visibility: dict.new(),
  )
}

/// What the store's answer to a play of the character leads to when the content
/// load holds these visibility prerequisites for the worlds (`Settings.visibility`).
pub fn loaded_seeing(
  tables tables: table_store.Tables,
  character character: Character,
  items items: List(HeldItem),
  saved_health saved_health: Option(Int),
  saved_experience saved_experience: Option(Int),
  quests quests: List(QuestRow),
  visibility visibility: Dict(Int, List(Prerequisite)),
) -> #(world_entry.State, world_entry.Loaded) {
  loaded_answer(
    tables:,
    character:,
    items:,
    unset: [],
    saved_health:,
    saved_experience:,
    quests:,
    action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    visibility:,
    stored: spawn_id.stored(ids: set.new()),
  )
}

/// What the store's answer to a play of the character leads to when its saved quests are
/// these rows and the loaded world's stored spawns are these.
pub fn loaded_with_spawns(
  tables tables: table_store.Tables,
  character character: Character,
  quests quests: List(QuestRow),
  stored stored: StoredSpawns,
) -> #(world_entry.State, world_entry.Loaded) {
  loaded_answer(
    tables:,
    character:,
    items: [],
    unset: [],
    saved_health: None,
    saved_experience: None,
    quests:,
    action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    visibility: dict.new(),
    stored:,
  )
}

/// What the load of a character whose saved quests are these rows leads to when the loaded
/// world's stored spawns are these: the effects the load asks and the player the connection
/// keeps once the map took it.
pub fn entry_with_spawns(
  tables tables: table_store.Tables,
  character character: Character,
  quests quests: List(QuestRow),
  stored stored: StoredSpawns,
) -> #(List(world_entry.Effect), world_entry.Entered) {
  let assert #(_, world_entry.Join(state:, effects:)) =
    loaded_with_spawns(tables:, character:, quests:, stored:)
    as "the store holds the character and its place"
  let assert world_entry.InTheWorld(entered:, ..) =
    joined_state(state:, tables:, character:, place: join_place(), now: now())
    as "the map's answer to the join puts the player in the world"
  #(effects, entered)
}

/// What the store's answer to a play of the character leads to when the store holds
/// the items `held` with their charges and the items `unset` with none recorded.
pub fn loaded_with_unset(
  tables tables: table_store.Tables,
  character character: Character,
  held items: List(HeldItem),
  unset unset: List(UnsetItem),
) -> #(world_entry.State, world_entry.Loaded) {
  loaded_answer(
    tables:,
    character:,
    items:,
    unset:,
    saved_health: None,
    saved_experience: None,
    quests: [],
    action_sets: limited_action_set.rows(saved: limited_action_set.none()),
    visibility: dict.new(),
    stored: spawn_id.stored(ids: set.new()),
  )
}

/// What the store's answer to a play of the character leads to when the store holds
/// these action slot rows for it and these items with no charges recorded.
pub fn loaded_with_action_sets(
  tables tables: table_store.Tables,
  character character: Character,
  action_sets action_sets: store.ActionSets,
  unset unset: List(UnsetItem),
) -> #(world_entry.State, world_entry.Loaded) {
  loaded_answer(
    tables:,
    character:,
    items: novice_items(character:),
    unset:,
    saved_health: None,
    saved_experience: None,
    quests: [],
    action_sets:,
    visibility: dict.new(),
    stored: spawn_id.stored(ids: set.new()),
  )
}

fn loaded_answer(
  tables tables: table_store.Tables,
  character character: Character,
  items items: List(HeldItem),
  unset unset: List(UnsetItem),
  saved_health saved_health: Option(Int),
  saved_experience saved_experience: Option(Int),
  quests quests: List(QuestRow),
  action_sets action_sets: store.ActionSets,
  visibility visibility: Dict(Int, List(Prerequisite)),
  stored stored: StoredSpawns,
) -> #(world_entry.State, world_entry.Loaded) {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 42))
    as "a character id fits the message"
  let assert Ok(#(state, _asks)) =
    world_entry.take(
      account_id: AccountId(7),
      body:,
      now_unix_ms: connection_rule_support.unix_ms_of_filetime(filetime:),
    )
    as "the client's request to play decodes"
  let assert Ok(loaded) =
    world_entry.loaded(
      state:,
      answer: store.CharacterLoaded(
        character:,
        session_epoch: character_support.epoch(1),
        saved_health:,
        saved_experience:,
        items:,
        quests:,
        currencies: [],
        unset:,
        action_sets:,
      ),
      connection: ConnectionId(1),
      stay: map_support.stay(count: 1),
      tables:,
      visibility:,
      stored:,
    )
    as "the store's answer is the one world entry asked for"
  #(state, loaded)
}

/// The join a fill asked for leads to once the store answers the fill `ItemsSaved`.
pub fn filled(
  state state: world_entry.State,
  tables tables: table_store.Tables,
) -> world_entry.State {
  let assert Ok(world_entry.Join(state:, ..)) =
    answered(
      state:,
      answer: store.ChargesFilled(answer: store.ItemsSaved),
      tables:,
    )
    as "the saved fill leads to the join"
  state
}

/// What the rule makes of the store's answer `answer` in the state `state`.
pub fn answered(
  state state: world_entry.State,
  answer answer: store.WorldAnswer,
  tables tables: table_store.Tables,
) -> Result(world_entry.Loaded, Nil) {
  world_entry.loaded(
    state:,
    answer:,
    connection: ConnectionId(1),
    stay: map_support.stay(count: 1),
    tables:,
    visibility: dict.new(),
    stored: spawn_id.stored(ids: set.new()),
  )
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
          words: store.ItemWords(
            random_stats: 0,
            charges: 0,
            item_flags: 0,
            expires_at_unix_ms: None,
          ),
        )
      })
    Error(Nil) -> []
  }
}

/// The frames of the entry of a Dominion character of the class and level on the committed
/// rows, and the player the connection keeps.
pub fn entering(
  class_id class_id: Int,
  level level: Int,
) -> #(List(Frame), world_entry.Entered) {
  let #(effects, entered) =
    entry(
      tables: character_tables.shared(),
      character: character(class: class_id, faction: 166, level:),
    )
  #(frames_of(effects:), entered)
}

/// The frames of the Holocrypt's join for a Dominion character of the class that entered at
/// `entered_at` and rose to `risen_to` in the session: the rejoin takes the level the
/// session holds (`experience.gained` keeps it in `Entered`).
pub fn rejoining(
  class_id class_id: Int,
  entered_at entered_at: Int,
  risen_to risen_to: Int,
) -> List(Frame) {
  let #(_, entered) = entering(class_id:, level: entered_at)
  rejoining_from(
    entered: world_entry.Entered(
      ..entered,
      character: Character(..entered.character, level: risen_to),
    ),
  )
}

/// The frames of the Holocrypt's join of this player on the committed rows: what it keeps of
/// the stay it leaves is sent again.
pub fn rejoining_from(entered entered: world_entry.Entered) -> List(Frame) {
  frames_of(effects: rejoining_effects(entered:))
}

/// The effects of the Holocrypt's join of this player on the committed rows, in order.
pub fn rejoining_effects(
  entered entered: world_entry.Entered,
) -> List(world_entry.Effect) {
  let #(_, effects) = rejoined(entered:)
  effects
}

/// The player the Holocrypt's join of this player on the committed rows builds, and its
/// effects, in order.
pub fn rejoined(
  entered entered: world_entry.Entered,
) -> #(world_entry.Entered, List(world_entry.Effect)) {
  let tables = character_tables.shared()
  let character = entered.character
  let landing =
    place_support.at(
      world_id: 426,
      world_zone_id: 648,
      x: 4098.16015625,
      y: -665.9780883789062,
      z: -5165.10009765625,
    )
  let #(state, _) =
    world_entry.rejoining(
      entered:,
      place: landing,
      health: None,
      told: None,
      connection: ConnectionId(1),
      stay: map_support.stay(count: 2),
      tables:,
      visibility: dict.new(),
    )
  let assert world_entry.InTheWorld(entered:, effects:, ..) =
    joined_state(state:, tables:, character:, place: landing, now: now())
    as "the map's answer to the rejoin puts the player in the world"
  #(entered, effects)
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
  let assert world_entry.InTheWorld(entered:, effects:, ..) =
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
  let assert #(_, world_entry.Join(state:, ..)) =
    loaded_holding(tables:, character:, items:, saved_experience: None, quests:)
    as "the store holds the character, its place and its level's row"
  joined_state(state:, tables:, character:, place: join_place(), now:)
}

fn join_place() -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: 29.0,
    y: -853.0,
    z: -560.0,
  )
}

/// What the rule makes of the map's answer to the join of a Dominion character of the class
/// and level on the committed rows when the store holds these action slot rows for it and
/// these items with no charges recorded. With none unset the load goes straight to the join;
/// with some the store is asked to fill them, and the join follows the fill's answer.
pub fn joined_with_action_sets(
  class_id class_id: Int,
  level level: Int,
  action_sets action_sets: store.ActionSets,
  unset unset: List(UnsetItem),
) -> world_entry.Joined {
  let tables = character_tables.shared()
  let character = character(class: class_id, faction: 166, level:)
  let #(_, loaded) =
    loaded_with_action_sets(tables:, character:, action_sets:, unset:)
  let joining = case loaded {
    world_entry.Join(state:, ..) -> state
    world_entry.Fill(state: filling, ..) -> {
      let assert Ok(world_entry.Join(state:, ..)) =
        answered(
          state: filling,
          answer: store.ChargesFilled(answer: store.ItemsSaved),
          tables:,
        )
        as "the fill's answer goes on to the join"
      state
    }
    world_entry.Refused(..) | world_entry.Fault(..) ->
      panic as "the store holds the character, its place and its level's row"
  }
  joined_state(
    state: joining,
    tables:,
    character:,
    place: join_place(),
    now: now(),
  )
}

/// What the rule makes of the map's answer to the join `state` asked for, the answer
/// the map gives a character of a created class and faction at `place`, made at `now`.
pub fn joined_state(
  state state: world_entry.State,
  tables tables: table_store.Tables,
  character character: Character,
  place place: Place,
  now now: Now,
) -> world_entry.Joined {
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
      chain: tutorial_support.none(),
      arrival_objectives: set.new(),
      scripts: objective.no_rows(),
      held_objectives: set.new(),
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
      | world_entry.StartStanding
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

/// A player that entered a map whose clock started at `clock_origin_ms` on the
/// monotonic clock: what the frames of another unit's movement are written from.
pub fn entered_after(
  clock_origin_ms clock_origin_ms: Int,
) -> world_entry.Entered {
  let #(_, entered) =
    entry(
      tables: character_tables.shared(),
      character: character(class: 4, faction: 167, level: 1),
    )
  world_entry.Entered(..entered, clock_origin_ms:)
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

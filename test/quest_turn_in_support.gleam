//// What the quest turn-in tests share: the quest of the client's rows a turn-in is taken
//// for, Dorian Walker (Creature2 74812) in reach as its receiver, and the rule's inputs.
//// The expected values are in the tests, each from the client's rows and code.
////
//// - Quest 10520 is the quest Dorian Walker receives (his `questIdReceive00`): five
////   objectives (QuestObjective 21294 to 21298), no Quest2Reward row, difficulty 6 and
////   an experience override of 1055.
//// - Another quest is turned in at him once a row of his `questIdReceive01` names it.

import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/currency.{type Currencies}
import genesis_prime/game/experience.{Progress}
import genesis_prime/game/interaction
import genesis_prime/game/prerequisite.{Factions}
import genesis_prime/game/quest.{type Asker, Asker}
import genesis_prime/game/quest_turn_in.{type Taken}
import genesis_prime/game/shown
import genesis_prime/game/vendor_trade.{type Effect, Log, Refuse, Send}
import genesis_prime/message/quest_turn_in.{QuestTurnIn} as quest_turn_in_message
import genesis_prime/store.{type HeldItem, type QuestRow, HeldItem}
import genesis_prime/table/id.{Item2Id, RaceId}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/set.{type Set}
import planted_table.{type Cell, Integer}
import prerequisite_support
import quest_support
import quest_walker_support

/// The Unix seconds a turn-in is taken at.
pub const unix_seconds = 1_700_000_000

/// The unit of Dorian Walker in `quest_walker_support.walker`'s picture.
pub const walker_unit = 40

/// Everything a turn-in reads, with Dorian Walker in reach, the player at level 1 with no
/// experience and no credits, and quest 10520 Achieved; each test changes what it is about.
pub type Scene {
  Scene(
    quest_id: Int,
    reward_id: Int,
    by_communicator: Int,
    log: List(QuestRow),
    items: List(HeldItem),
    level: Int,
    experience: Int,
    credits: Int,
    picture: shown.Picture,
    proficiencies: Int,
    logged: Set(String),
  )
}

/// A turn-in of quest `quest_id` that the log holds Achieved, with reward id 0.
pub fn scene(quest_id quest_id: Int) -> Scene {
  Scene(
    quest_id:,
    reward_id: 0,
    by_communicator: 0,
    log: [achieved(quest_id:)],
    items: [],
    level: 1,
    experience: 0,
    credits: 0,
    picture: quest_walker_support.walker(gap: 1.0, alive: True, hostile: False),
    proficiencies: 0,
    logged: set.new(),
  )
}

/// The saved row of a quest the player holds Achieved (state 2) with every objective done.
pub fn achieved(quest_id quest_id: Int) -> QuestRow {
  let objectives = quest_support.objective_count(quest_id:)
  quest_support.active(
    quest_id:,
    state: 2,
    placeholder: 0,
    tracked: False,
    done_mask: int.bitwise_shift_left(1, objectives) - 1,
    progress: list.repeat(1, objectives),
  )
}

/// A stack of Item2 `item2_id` in the inventory (location 1).
pub fn in_bag(
  guid guid: Int,
  item2_id item2_id: Int,
  index index: Int,
  count count: Int,
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2_id),
    location: 1,
    bag_index: index,
    stack_count: count,
  )
}

/// The credits held as the currencies the rule reads.
pub fn credits(total total: Int) -> Currencies {
  currency.with_amount(
    currencies: currency.from_held(held: []),
    currency_type_id: currency.credits_type,
    total:,
  )
}

/// The 0x35D the scene's player sends.
pub fn body(scene scene: Scene) -> BitArray {
  let assert Ok(body) =
    quest_turn_in_message.encode(QuestTurnIn(
      quest_id: scene.quest_id,
      reward_id: scene.reward_id,
      by_communicator: scene.by_communicator,
    ))
    as "a quest and a reward of 15 bits and one bit fit the message"
  body
}

/// What the scene's turn-in is taken as, with the shared tables.
pub fn taken(
  scene scene: Scene,
  tables tables: table_store.Tables,
) -> Result(Taken, quest.Refusal) {
  taken_from(scene:, body: body(scene:), tables:)
}

/// What the scene's player does with this body instead of its own.
pub fn taken_from(
  scene scene: Scene,
  body body: BitArray,
  tables tables: table_store.Tables,
) -> Result(Taken, quest.Refusal) {
  quest_turn_in.take(
    body:,
    asker: asker(scene:),
    standing: interaction.Player(
      race_id: RaceId(3),
      faction: shown.Exile,
      place: connection_support.entry_place(),
    ),
    picture: scene.picture,
    progress: Progress(experience: scene.experience, level: scene.level),
    currencies: credits(total: scene.credits),
    item_proficiencies: scene.proficiencies,
    tables:,
    now_ms: 0,
    unix_seconds:,
    logged: scene.logged,
  )
}

/// The player: a level of the scene, race 3, class 5, an Exile, with the scene's log and items.
pub fn asker(scene scene: Scene) -> Asker {
  Asker(
    player: prerequisite.Player(
      ..prerequisite_support.player(),
      level: scene.level,
    ),
    factions: Factions(current: 167, base: 167),
    log: quest_support.log_of(rows: scene.log),
    items: scene.items,
  )
}

/// The turn-in the rule asks the store to save, which it must have accepted.
pub fn asked(
  scene scene: Scene,
  tables tables: table_store.Tables,
) -> #(quest_turn_in.TurnIn, List(Effect)) {
  let assert Ok(quest_turn_in.Asks(turn_in:, effects:, ..)) =
    taken(scene:, tables:)
    as "the turn-in passes every check, so the store is asked"
  #(turn_in, effects)
}

/// The effects and log keys of a turn-in the rule refused.
pub fn refused(
  scene scene: Scene,
  tables tables: table_store.Tables,
) -> #(List(Effect), Set(String)) {
  let assert Ok(quest_turn_in.Refused(effects:, logged:)) =
    taken(scene:, tables:)
    as "the turn-in breaks a check, so it is answered and nothing is asked"
  #(effects, logged)
}

/// The codes of the 0x106s among the effects.
pub fn codes(effects effects: List(Effect)) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Refuse(code:) -> Ok(code)
      Send(..) | Log(..) -> Error(Nil)
    }
  })
}

/// Runs the body on the tables with these rows changed, each a table, an id and the cells
/// to replace, built on the body's heap; the shared tables are not touched.
pub fn with_changes(
  changes changes: List(#(String, Int, List(#(String, Cell)))),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(changes, fixture_tables.rows(), fn(rows, change) {
      case
        fixture_tables.change(
          rows:,
          table: change.0,
          id: change.1,
          with: change.2,
        )
      {
        Ok(changed) -> changed
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// The change that has Dorian Walker receive this quest as well (his `questIdReceive01`).
pub fn receiving(
  quest_id quest_id: Int,
) -> #(String, Int, List(#(String, Cell))) {
  receiving_in(quest_id:, slot: 1)
}

/// The same for his `questIdReceive0` slot, so a test can have him receive two more.
pub fn receiving_in(
  quest_id quest_id: Int,
  slot slot: Int,
) -> #(String, Int, List(#(String, Cell))) {
  #("Creature2", 74_812, [
    #("questIdReceive0" <> int.to_string(slot), Integer(quest_id)),
  ])
}

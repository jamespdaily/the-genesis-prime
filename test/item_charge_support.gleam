//// Shared scenes of the item charge tests: the tables with one Item2 row's charge columns
//// changed, items held with their charges (or with none recorded), and the world-entry
//// rule's output for a load. The rows are the client's own (`fixture_tables`): Item2 2509
//// holds maxCharges 99 and a stack of 1, 12402 holds none, 1039 stacks to 20, 14838 to 50
//// and 20791 to 99, and 74201 is the row GameFormula 1214 names for a proxy item, with
//// maxCharges 0 (`0x1404445d0.proxy`).

import character_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/world_entry
import genesis_prime/map/message.{ObjectsSeen}
import genesis_prime/message/item_place.{type ItemPlace, ItemPlace}
import genesis_prime/message/item_use.{ItemUse}
import genesis_prime/shared/creature_combat
import genesis_prime/shared/creature_path
import genesis_prime/shared/unit_news
import genesis_prime/step
import genesis_prime/store.{
  type HeldItem, type UnsetItem, type WorldRequest, HeldItem, UnsetItem,
}
import genesis_prime/table/id.{Creature2Id, Item2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/static_object.{StaticObject}
import gleam/list
import gleam/option.{type Option, None, Some}
import place_support
import planted_table.{Integer}
import quest_support
import spawn_support
import vendor_support
import world_entry_support

/// The flags of an Item2 row that make it a proxy item (`0x1404445d0.proxy`).
pub const proxy_flags = 0x4000

/// Runs the body on the tables with the row's maxCharges changed, and its flags and
/// maxStackCount too when they are given (`None` leaves the row's own).
pub fn tables_with(
  item2_id item2_id: Int,
  max_charges max_charges: Int,
  flags flags: Option(Int),
  max_stack_count max_stack_count: Option(Int),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let changes =
    list.flatten([
      [#("maxCharges", Integer(max_charges))],
      case flags {
        Some(flags) -> [#("flags", Integer(flags))]
        None -> []
      },
      case max_stack_count {
        Some(count) -> [#("maxStackCount", Integer(count))]
        None -> []
      },
    ])
  fixture_tables.changed(table: "Item2", id: item2_id, with: changes, body:)
}

/// An item held, with the charges it has left.
pub fn held(
  guid guid: Int,
  item2 item2: Int,
  location location: Int,
  bag_index bag_index: Int,
  count count: Int,
  charges charges: Int,
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2),
    location:,
    bag_index:,
    stack_count: count,
    words: store.ItemWords(
      random_stats: 0,
      charges:,
      item_flags: 0,
      expires_at_unix_ms: None,
    ),
  )
}

/// An item the database holds with no charges recorded (a row saved before the column).
pub fn unset(
  guid guid: Int,
  item2 item2: Int,
  location location: Int,
  bag_index bag_index: Int,
  count count: Int,
) -> UnsetItem {
  UnsetItem(
    item_guid: guid,
    item2_id: Item2Id(item2),
    location:,
    bag_index:,
    stack_count: count,
    random_stats: 0,
    item_flags: 0,
    expires_at_unix_ms: None,
  )
}

/// What the world-entry rule does with a load: the store requests it asked (none, or
/// the fill), the items the player enters with, and the 0x111 frames of the entry.
pub type Entry {
  Entry(asked: List(WorldRequest), items: List(HeldItem), frames: List(Frame))
}

/// The entry of a character on these tables whose load holds the items `held` (with their
/// charges) and `unset` (with none recorded): the store answers a fill it is asked with
/// `ItemsSaved` and the map takes the player.
pub fn entry_of(
  tables tables: table_store.Tables,
  held held: List(HeldItem),
  unset unset: List(UnsetItem),
) -> Entry {
  let character =
    world_entry_support.character(class: 4, faction: 167, level: 1)
  let #(_, loaded) =
    world_entry_support.loaded_with_unset(tables:, character:, held:, unset:)
  let #(asked, state) = case loaded {
    world_entry.Join(state:, ..) -> #([], state)
    world_entry.Fill(state: filling, effects:) -> #(
      list.filter_map(effects, requested),
      world_entry_support.filled(state: filling, tables:),
    )
    world_entry.Refused(..) | world_entry.Fault(..) ->
      panic as "the load is entered or filled"
  }
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.0,
      y: -853.0,
      z: -560.0,
    )
  let assert world_entry.InTheWorld(entered:, effects:, ..) =
    world_entry_support.joined_state(
      state:,
      tables:,
      character:,
      place:,
      now: world_entry_support.now(),
    )
    as "the map takes the player"
  Entry(
    asked:,
    items: entered.items,
    frames: world_entry_support.frames_of(effects:),
  )
}

fn requested(effect: world_entry.Effect) -> Result(WorldRequest, Nil) {
  case effect {
    world_entry.AskStore(request:) -> Ok(request)
    world_entry.Send(..)
    | world_entry.AskMap(..)
    | world_entry.WatchMap(..)
    | world_entry.Life(..)
    | world_entry.StartStanding
    | world_entry.Warn(..) -> Error(Nil)
  }
}

/// The session epoch the tests' load gave the character (`game_connection_support`).
pub fn epoch() -> store.SessionEpoch {
  character_support.epoch(1)
}

/// Item2 12444, the Incendiary Grenade: ItemSpecial 4363 -> Spell4 26663 (castTime 0,
/// spellCoolDown 2000, an Activate row on a creature of TargetGroup 1691), quest 4743
/// required.
pub const grenade = 12_444

/// The unit the shack is for the connection, and its creature: Creature2 17397, in
/// TargetGroup 1691 (`cast_item_use_test`), whose display is Creature2DisplayInfo 30233
/// (Creature2DisplayGroupEntry 33992).
pub const shack_unit = 40

const shack_creature = 17_397

const shack_display = 30_233

/// The Spell4 the grenade casts.
pub const grenade_spell = 26_663

/// The connection of the tests' character in the world on these tables, holding these
/// items besides the Novice set and quest 4743 accepted, and seeing the shack as unit 40,
/// 5.0 east of the player.
pub fn seeing_a_shack(
  tables tables: table_store.Tables,
  items items: List(HeldItem),
) -> game_connection.State {
  let #(state, _) =
    connection_support.entered_with_quests_and_items_on(
      tables:,
      quests: [quest_support.accepted(quest_id: 4743, progress: [0, 0, 0, 0])],
      items:,
    )
  let place =
    connection_support.standing_at(
      x: 29.128599166870117 +. 5.0,
      y: -853.87158203125,
      z: -560.18798828125,
    )
  connection_support.feed(
    state:,
    event: connection_support.sent_by_the_map(
      ObjectsSeen(units: [
        spawn_support.seen(
          object: StaticObject(
            ..spawn_support.holoring(number: shack_unit, place:),
            creature_id: Creature2Id(shack_creature),
            display_info_id: shack_display,
          ),
          unit_id: shack_unit,
        ),
      ]),
    ),
  ).0
}

/// The connection of `seeing_a_shack` where the shack is a creature of the same row that
/// runs straight away from the player at 10 units a second from monotonic time 0, standing
/// 29.0 from the player's edge at that time: Spell4 26663's targetMaxRange is 30.0, so the
/// grenade reaches it at 0 ms and not at 400 ms, where it is 33.0 away.
pub fn seeing_a_runner(
  tables tables: table_store.Tables,
  items items: List(HeldItem),
) -> game_connection.State {
  let #(state, _) =
    connection_support.entered_with_quests_and_items_on(
      tables:,
      quests: [quest_support.accepted(quest_id: 4743, progress: [0, 0, 0, 0])],
      items:,
    )
  let state =
    connection_support.feed(
      state:,
      event: connection_support.creature_appears(
        unit_id: shack_unit,
        creature_id: shack_creature,
        display_info_id: shack_display,
        outfit_info_id: 0,
        hit_radius: runner_radius,
        place: vendor_support.ahead_of_the_player(
          hit_radius: runner_radius,
          gap: 29.0,
        ),
        hostile_to: creature_combat.Hostile(exile: False, dominion: False),
      ),
    ).0
  connection_support.feed(
    state:,
    event: connection_support.news_sent_by_a_peer(
      unit_id: shack_unit,
      news: unit_news.CreatureMoved(path: creature_path.Running(
        from: vendor_support.ahead_of_the_player(
          hit_radius: runner_radius,
          gap: 29.0,
        ),
        via: [],
        to: vendor_support.ahead_of_the_player(
          hit_radius: runner_radius,
          gap: 129.0,
        ),
        started_ms: 0,
        speed: 10.0,
      )),
    ),
  ).0
}

/// The runner of `seeing_a_runner` set down again 10.0 from the player's edge at 400 ms,
/// where the grenade reaches it, for a press after the run took it out of range.
pub fn runner_set_down_in_range(
  state state: game_connection.State,
) -> game_connection.State {
  connection_support.feed(
    state:,
    event: connection_support.news_sent_by_a_peer(
      unit_id: shack_unit,
      news: unit_news.CreaturePlaced(
        place: vendor_support.ahead_of_the_player(
          hit_radius: runner_radius,
          gap: 10.0,
        ),
        at_ms: 400,
      ),
    ),
  ).0
}

const runner_radius = 1.0

/// The client's 0x943 of the item at `place`, at the shack, with this client cast id,
/// inside the client's 0x038C.
pub fn press(
  client_cast_id client_cast_id: Int,
  place place: ItemPlace,
) -> BitArray {
  let assert Ok(body) =
    item_use.encode(ItemUse(
      client_cast_id:,
      item: place,
      target_unit_id: shack_unit,
      second_item: ItemPlace(location: 300, bag_index: 0xffffffff),
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  connection_support.world_message(message_id: item_use.message_id, body:)
}

/// The store's items request the step ends in.
pub fn spend_asked(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> store.ItemsRequest {
  let assert client_connection.AskStore(store.Items(request)) =
    connection_support.ask_request(taken)
    as "the step ends in an ask of the store's items"
  request
}

/// The held items after the store applied the request of a spend or a delete, as its
/// statement does: the row lowered, or removed.
pub fn applied(
  items items: List(HeldItem),
  request request: store.ItemsRequest,
) -> List(HeldItem) {
  case request {
    store.SpendItem(item:, stack_count:, charges:, ..) ->
      list.map(items, fn(held) {
        case held.item_guid == item.item_guid {
          True ->
            HeldItem(
              ..held,
              stack_count:,
              words: store.ItemWords(..held.words, charges:),
            )
          False -> held
        }
      })
    store.DeleteItem(item:, ..) ->
      list.filter(items, fn(held) { held.item_guid != item.item_guid })
    store.MoveItems(..)
    | store.SplitItem(..)
    | store.MergeItems(..)
    | store.BuyFromVendor(..)
    | store.SellToVendor(..)
    | store.SetCurrency(..)
    | store.TurnInQuest(..) -> panic as "only a spend or a delete is applied"
  }
}

/// The rows with a heal over time on the caster added beside the grenade spell's Activate
/// row (Spell4Effects 43805): a type 10 Heal aimed at the caster (targetFlags 1) with
/// tickTime 1000 and durationTime 4000, so the spell's go gives the caster a lasting effect
/// and arms four ticks. Kept edit: the client's item spell with a heal over time (Spell4
/// 34993) is cast on its user and holds no Activate row, so the grenade's spell is given
/// one. The heal's formula is the caster's level (parameter kind 10,
/// `Spell4Effects.effectType.10`) times 40.
pub fn with_a_heal_over_time(
  rows rows: fixture_tables.Rows,
) -> fixture_tables.Rows {
  let assert Ok(rows) =
    fixture_tables.add(
      rows:,
      table: "Spell4Effects",
      copy_of: 43_805,
      id: 99_985,
      with: [
        #("targetFlags", Integer(1)),
        #("effectType", Integer(10)),
        #("tickTime", Integer(1000)),
        #("durationTime", Integer(4000)),
        #("flags", Integer(0)),
        #("dataBits00", Integer(1_065_353_216)),
        #("dataBits01", Integer(0)),
        #("parameterType00", Integer(10)),
        #("parameterValue00", planted_table.Float(40.0)),
        #("phaseFlags", Integer(-1)),
        #("orderIndex", Integer(1)),
      ],
    )
    as "Spell4Effects 43805, the grenade's Activate row, is in the fixture"
  rows
}

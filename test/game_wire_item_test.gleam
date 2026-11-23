//// Items on the whole server: a bot that moves, splits, equips, deletes, buys, sells and buys
//// back, the credits a relog keeps, a timed item that runs out and the development command
//// that puts an item in the bag.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import character_tables
import driven_time
import fight_bot
import game_client
import game_wire_support.{
  beast_place, bot_countdown_ms, entry_stat, new_player_at_level,
  on_rows_without_paralytic_surges_recharge, press_until_dead_reading, send_play,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/message/experience_gained
import genesis_prime/message/float32
import genesis_prime/message/item_added
import genesis_prime/message/item_place
import genesis_prime/message/item_removed
import genesis_prime/message/player_character_state
import genesis_prime/server
import genesis_prime/step
import genesis_prime/table/id.{XpPerLevelId}
import genesis_prime/table/xp_per_level
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import item_bot
import login_support
import owned_test
import pog
import rating_support
import spawn_support
import vendor_support

// ---- a purchase is saved ----

/// The credits the character is given before it buys (the table's value is a server
/// choice, `starting_credits`; the test gives its own so it does not depend on it).
const credits_before_the_buy = 1000

/// The credits slot of the entry's 0x25E: the first of 15 u64 little-endian, the types 1
/// to 15 in order, credits first (opcode.0x25e).
fn credits_in_entry(frames frames: List(Frame)) -> Int {
  let assert [Frame(body:, ..)] =
    list.filter(frames, fn(frame) { frame.message_id == 0x025E })
    as "the entry sends one 0x25E"
  let assert Ok(state) = player_character_state.decode(body)
    as "the client's reader reads the 0x25E"
  let assert <<credits:unsigned-little-size(64), _:bytes>> = state.currencies
  credits
}

pub fn credits_survive_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  // Supplier Ingavak (Creature2 28739) stands 3.0 from the player's edge, within the
  // 9.0 a vendor request is answered up to (opcode.0x7ea). The player is an Exile
  // (faction 167), to whom his faction 171 is friendly (Faction2Relationship 771). A
  // buy of one Item2 14838 costs the 67 the window shows (`vendor.start_zone_prices`),
  // and 0x919 kind 0 then carries the credits left (opcode.0x919). After a camp and a
  // new play, the 0x25E carries them in its first currency slot (opcode.0x25e).
  let vendors =
    vendor_support.stocking_items(
      creature_ids: [28_739],
      items: vendor_support.ingavaks_items,
    )
  let selection =
    spawn.select(
      rows: [
        spawn.Row(
          ..spawn_support.beast_row(number: 10_706),
          creature_id: 28_739,
          display_info_id: 29_772,
          outfit_info_id: 9029,
          faction_id: 171,
          base_faction_id: 171,
        ),
      ],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors:,
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the row passes the spawn checks"
  let assert Ok(spawns) = dict.get(selection.worlds, 3460)
  let assert Ok(selected) = dict.get(spawns.by_id, spawn_id.SpawnId(10_706))
  let ingavak =
    spawn.Spawn(
      ..selected,
      place: beast_place(
        x: 1.5,
        z: 3.5 -. { 3.0 +. 1.2 +. selected.combat.hit_radius },
      ),
    )
  let time = driven_time.new()
  let started =
    login_support.start_with(time:, change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: connection_state.Settings(
            ..game.settings,
            vendors:,
            game: GameSettings(
              ..game.settings.game,
              camp_countdown_ms: bot_countdown_ms,
            ),
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in(
            world_id: 1387,
            spawns: [ingavak],
            respawn_ms: 60_000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is of the faction Ingavak is friendly to"
  let assert Ok(_) =
    pog.query(
      "insert into character_currency (character_id, currency_type_id, amount) values ($1, 1, $2)",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(credits_before_the_buy))
    |> pog.execute(pool)
    as "the character holds credits"
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && game_client.creatures_created_in(frames:) != []
    })
  assert credits_in_entry(frames: entry) == credits_before_the_buy
    as "the entry carries the credits the character holds"
  let assert [shown] = game_client.creatures_created_in(frames: entry)
  assert shown.creature_id == 28_739
    as "the creature in sight is Supplier Ingavak"
  // The right-click opens the window; the item's unique id is the one the window shows.
  let #(window, have) =
    item_bot.open_vendor(game:, have:, unit_id: shown.unit_id)
  let assert Ok(stimpack) =
    list.find(window.items, fn(item) { item.entry_id == 14_838 })
    as "the window shows Item2 14838"
  let #(bought, have) =
    item_bot.buy(game:, have:, unique_id: stimpack.unique_id, quantity: 1)
  assert list.map(bought.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_before_the_buy - 67)]
    as "opcode.0x919: kind 0 sets the total, the credits less the 67 the client shows (vendor.start_zone_prices)"
  assert list.map(bought.added, fn(held) { held.item.item_id }) == [14_838]
    as "the bought item is added to the inventory"
  // The player camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert credits_in_entry(frames: second_entry) == credits_before_the_buy - 67
    as "opcode.0x25e: the first currency slot carries the credits the buy saved"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- a bot plays the items, the vendor and the levels ----

/// The Item2 the bot buys, splits, moves, sells and buys back: it stacks to 50 and a
/// lot is 1 item (`vendor_purchase_test`'s rows), and the client shows 67 credits for it
/// at the multiplier 1.0 (`vendor.start_zone_prices`).
const stimpack = 14_838

const stimpack_cost = 67

/// What Supplier Ingavak pays for one: the sell base 10 at his multiplier 1.0
/// (`item_price_test`).
const stimpack_sells_for = 10

/// The Item2 the bot buys a lot of and deletes: a lot is 5 items at 13 credits each
/// (`vendor_purchase_test`: 20791 stacks to 99, buyFromVendorStackCount 5).
const bandage = 20_791

const bandage_lot_cost = 65

/// A slot of the inventory (location 1).
fn in_bags(bag_index bag_index: Int) -> item_place.ItemPlace {
  item_place.ItemPlace(location: 1, bag_index:)
}

/// The chest's slot among the worn items: bag index 0, the lowest bit of its slot flags
/// (`inventory_test`).
const chest_slot = item_place.ItemPlace(location: 0, bag_index: 0)

pub fn a_bot_moves_splits_equips_deletes_buys_sells_buys_back_and_levels_up_and_finds_it_all_after_a_relog_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  // Supplier Ingavak (Creature2 28739) stands 3.0 from the player's edge, behind the
  // player, within the 9.0 a vendor request is answered up to (opcode.0x7ea); the Beast
  // stands 3 m ahead, where the fight of the medic's test strikes it. The player is an
  // Exile (faction 167), to whom his faction 171 is friendly (Faction2Relationship 771),
  // with 1000 credits and one experience point less than level 2 asks for
  // (XpPerLevel row 2's minXpForLevel).
  let time = driven_time.new()
  let vendors =
    vendor_support.stocking_items(
      creature_ids: [28_739],
      items: vendor_support.ingavaks_items,
    )
  let selection =
    spawn.select(
      rows: [
        spawn.Row(
          ..spawn_support.beast_row(number: 10_706),
          creature_id: 28_739,
          display_info_id: 29_772,
          outfit_info_id: 9029,
          faction_id: 171,
          base_faction_id: 171,
        ),
      ],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors:,
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the row passes the spawn checks"
  let assert Ok(spawns) = dict.get(selection.worlds, 3460)
  let assert Ok(selected) = dict.get(spawns.by_id, spawn_id.SpawnId(10_706))
  let ingavak =
    spawn.Spawn(
      ..selected,
      place: beast_place(
        x: 1.5,
        z: 3.5 +. { 3.0 +. 1.2 +. selected.combat.hit_radius },
      ),
    )
  let started =
    login_support.start_with(time:, change: fn(settings) {
      server.Settings(
        ..settings,
        game: server.Served(
          ..settings.game,
          settings: connection_state.Settings(
            ..settings.game.settings,
            tables:,
            vendors:,
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in(
            world_id: 1387,
            spawns: [
              ingavak,
              spawn_support.beast_without_deflect_at(
                number: 1,
                place: beast_place(x: 1.5, z: 0.5),
              ),
            ],
            respawn_ms: 1000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(level_two) = xp_per_level.get(tables:, id: XpPerLevelId(2))
    as "XpPerLevel has a row 2"
  let experience_before = level_two.min_xp_for_level - 1
  let assert Ok(_) =
    pog.query(
      "update character set faction_id = 167, experience = $2 where character_id = $1",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(experience_before))
    |> pog.execute(pool)
    as "the character is of the faction Ingavak is friendly to, one point short of level 2"
  let assert Ok(_) =
    pog.query(
      "insert into character_currency (character_id, currency_type_id, amount) values ($1, 1, $2)",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(credits_before_the_buy))
    |> pog.execute(pool)
    as "the character holds credits"
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.length(game_client.creatures_created_in(frames:)) >= 2
    })
  assert credits_in_entry(frames: entry) == credits_before_the_buy
    as "the entry carries the credits the character holds"
  assert entry_stat(entry:, stat_id: 10) == 1
    as "the entry's 0x262 shows level 1"
  let shown = game_client.creatures_created_in(frames: entry)
  let assert Ok(vendor) =
    list.find(shown, fn(unit) { unit.creature_id == 28_739 })
    as "Supplier Ingavak is in sight"
  let assert Ok(beast) =
    list.find(shown, fn(unit) { unit.creature_id != 28_739 })
    as "the Beast is in sight"
  let assert Ok(chest) =
    list.find(item_bot.answer_in(frames: entry).added, fn(held) {
      held.item.location == chest_slot.location
      && held.item.bag_index == chest_slot.bag_index
    })
    as "the creation loadout wears a chest piece"
  let chest = chest.item
  // 1: buys 3 of the stimpack. A lot is 1 item, so 3 lots; a new stack goes to the
  // lowest empty slot (`vendor_purchase_test`), for the credits the window shows.
  let #(window, have) =
    item_bot.open_vendor(game:, have:, unit_id: vendor.unit_id)
  let assert Ok(row) =
    list.find(window.items, fn(row) { row.entry_id == stimpack })
    as "the window shows the stimpack"
  assert window.buy_multiplier == float32.to_bits(1.0)
    as "the window's multiplier is the 1.0 at which the client shows 67 for the stimpack (vendor.start_zone_prices)"
  let #(bought, have) =
    item_bot.buy(game:, have:, unique_id: row.unique_id, quantity: 3)
  assert bought.refused == [] as "the buy is allowed"
  assert list.map(bought.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_before_the_buy - 3 * stimpack_cost)]
    as "opcode.0x919: kind 0 sets the total, the credits less 3 stimpacks"
  let assert [added] = bought.added as "3 lots of 1 item fill one new stack"
  let stack = added.item
  assert #(stack.item_id, stack.location, stack.bag_index, stack.stack_count)
    == #(stimpack, 1, 0, 3)
    as "vendor_purchase_test: a stack of 3 at the lowest empty slot of the inventory"
  // 2: splits 1 off into an empty slot.
  let #(split, have) =
    item_bot.split(
      game:,
      have:,
      item_guid: stack.item_guid,
      to: in_bags(bag_index: 5),
      count: 1,
    )
  assert split.refused == [] as "the split is allowed"
  assert list.map(split.count_changed, fn(changed) {
      #(changed.item_guid, changed.count)
    })
    == [#(stack.item_guid, 2)]
    as "opcode.0x17f: the stack keeps 2"
  let assert [split_off] = split.added as "the one split off is a new item"
  let single = split_off.item
  assert #(
      single.item_id,
      single.location,
      single.bag_index,
      single.stack_count,
    )
    == #(stimpack, 1, 5, 1)
    as "opcode.0x17d: the split goes to the slot the bot named, with the count it named"
  // 3: moves the one to another empty slot.
  let #(moved, have) =
    item_bot.move(
      game:,
      have:,
      from: in_bags(bag_index: 5),
      to: in_bags(bag_index: 7),
    )
  assert moved.refused == [] as "the move is allowed"
  assert list.map(moved.moved, fn(moved) {
      #(moved.item_guid, item_bot.place_of(moved.place))
    })
    == [#(single.item_guid, in_bags(bag_index: 7))]
    as "opcode.0x569: the item is at the new slot"
  // 4: sells the stack of 2: the vendor pays 10 for each, and the sale is the Buyback
  // list's first.
  let #(sold, have) =
    item_bot.sell(
      game:,
      have:,
      place: item_place.ItemPlace(
        location: stack.location,
        bag_index: stack.bag_index,
      ),
      quantity: 2,
    )
  let credits_after_the_sale =
    credits_before_the_buy - 3 * stimpack_cost + 2 * stimpack_sells_for
  assert sold.refused == [] as "the sale is allowed"
  assert list.map(sold.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_after_the_sale)]
    as "opcode.0x919: the credits plus the 10 the vendor pays for each of 2"
  assert list.map(sold.removed, fn(removed) {
      #(removed.item_guid, removed.reason)
    })
    == [#(stack.item_guid, 7)]
    as "opcode.0x148 with the reason 7, Vendor"
  let assert [listed] = sold.buyback_added
    as "the sale is added to the Buyback list"
  assert #(
      listed.item_id,
      listed.quantity,
      listed.amount_1,
      listed.currency_type_1,
    )
    == #(stimpack, 2, 2 * stimpack_sells_for, 1)
    as "opcode.0xba.price: the entry holds the item, its count, the credits paid and the currency type 1"
  // 5: buys it back for what the entry holds: the vendor_purchase rule fills a stack
  // below the stack limit first, so the held stack of 1 grows to 3.
  let #(back, have) =
    item_bot.buy_back(game:, have:, buyback_id: listed.buyback_id)
  assert back.refused == [] as "the buy back is allowed"
  assert list.map(back.currencies, fn(told) { #(told.kind, told.total) })
    == [#(0, credits_before_the_buy - 3 * stimpack_cost)]
    as "opcode.0xba.price: a buy back costs what its entry holds, so the credits are as before the sale"
  assert back.buyback_removed == [listed.buyback_id]
    as "opcode.0xbd: the entry leaves the Buyback list"
  assert back.added == [] as "the bought-back items make no new stack"
  assert list.map(back.count_changed, fn(changed) {
      #(changed.item_guid, changed.count, changed.reason)
    })
    == [#(single.item_guid, 3, 16)]
    as "opcode.0x17f with the reason 16, Buyback: the moved stack of 1 grows to 3"
  // 6: buys a lot of bandages and deletes it.
  let assert Ok(bandage_row) =
    list.find(window.items, fn(row) { row.entry_id == bandage })
    as "the window shows the bandage"
  let #(lot, have) =
    item_bot.buy(game:, have:, unique_id: bandage_row.unique_id, quantity: 1)
  assert lot.refused == [] as "the buy is allowed"
  assert list.map(lot.currencies, fn(told) { #(told.kind, told.total) })
    == [
      #(0, credits_before_the_buy - 3 * stimpack_cost - bandage_lot_cost),
    ]
    as "opcode.0x919: the credits less the 65 of a lot"
  let assert [lot_added] = lot.added as "a lot is one new stack"
  let bandages = lot_added.item
  assert #(bandages.item_id, bandages.stack_count) == #(bandage, 5)
    as "a lot of 20791 is 5 items"
  let #(deleted, have) =
    item_bot.delete(
      game:,
      have:,
      place: item_place.ItemPlace(
        location: bandages.location,
        bag_index: bandages.bag_index,
      ),
    )
  assert deleted.refused == [] as "the delete is allowed"
  assert list.map(deleted.removed, fn(removed) {
      #(removed.item_guid, removed.reason)
    })
    == [#(bandages.item_guid, 21)]
    as "opcode.0x149: the item goes with the reason 21, Delete"
  // 7 and 8: takes the chest off into an empty slot and puts it back on.
  let #(off, have) =
    item_bot.move(game:, have:, from: chest_slot, to: in_bags(bag_index: 10))
  assert off.refused == [] as "the chest comes off"
  assert list.map(off.moved, fn(moved) {
      #(moved.item_guid, item_bot.place_of(moved.place))
    })
    == [#(chest.item_guid, in_bags(bag_index: 10))]
    as "opcode.0x182: the chest is in the bag slot it was moved to"
  let #(on, have) =
    item_bot.move(game:, have:, from: in_bags(bag_index: 10), to: chest_slot)
  assert on.refused == [] as "the chest goes on"
  assert list.map(on.moved, fn(moved) {
      #(moved.item_guid, item_bot.place_of(moved.place))
    })
    == [#(chest.item_guid, chest_slot)]
    as "opcode.0x182: the chest is in the chest slot again"
  // 9: kills the Beast with the Medic's first ability, as the medic's test does.
  let own = game_client.unit_create_player_in(frames: entry)
  let own_place = game_client.placed_at(unit: own)
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    )),
    clock: 100,
  )
  let #(have, _, fight) =
    press_until_dead_reading(
      time:,
      game:,
      have:,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      lingers_ms: fight_bot.paralytic_surge_lingers_ms,
      beast: beast.unit_id,
      cast_id: 1,
    )
  let #(fight, have) = case
    list.any(fight, fn(frame) { frame.message_id == 0x01AC })
  {
    True -> #(fight, have)
    False -> {
      let #(more, have) =
        game_client.read_until(game:, have:, found: fn(more) {
          list.any(more, fn(frame) { frame.message_id == 0x01AC })
        })
      #(list.append(fight, more), have)
    }
  }
  // The shell writes each effect with its own send, so the level's 0x938 can come in a
  // later read than the 0x1AC; the pong follows all the connection wrote before it
  // took the ping (pongs 1 and 3 are the actions' and the press loop's).
  let #(after_the_gain, have) =
    game_client.read_until_pong(game:, have:, number: 4)
  let fight = list.append(fight, after_the_gain)
  let assert [Frame(body: gain, ..)] =
    list.filter(fight, fn(frame) { frame.message_id == 0x01AC })
    as "the kill sends one 0x1AC"
  let assert Ok(gained) = experience_gained.decode(gain)
    as "the client's reader reads the 0x1AC"
  assert gained.source_kind == 2 && gained.source_unit_id == beast.unit_id
    as "opcode.0x1ac: kind 2, KillCreature, naming the Beast"
  assert gained.experience > 0 as "the kill gives experience"
  assert list.contains(
    game_client.fight_in(frames: fight),
    game_client.LevelIs(unit_id: own.unit_id, level: 2),
  )
    as "opcode.0x938: stat 10 of the player is 2, as the experience crosses level 2's minXpForLevel"
  // 10: camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert entry_stat(entry: second_entry, stat_id: 10) == 2
    as "opcode.0x262: the entry shows level 2"
  let assert [Frame(body: state_body, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x025E })
    as "the entry sends one 0x25E"
  let assert Ok(state) = player_character_state.decode(state_body)
    as "the client's reader reads the 0x25E"
  assert state.experience == experience_before + gained.experience
    as "opcode.0x25e: the experience the character had and the kill's 0x1AC gave"
  assert credits_in_entry(frames: second_entry)
    == credits_before_the_buy - 3 * stimpack_cost - bandage_lot_cost
    as "opcode.0x25e: the credits after the buy, the sale, the buy back and the lot"
  let held =
    list.map(item_bot.answer_in(frames: second_entry).added, fn(held) {
      held.item
    })
  let in_the_bags =
    list.filter_map(held, fn(item) {
      case item.location == 1 {
        True -> Ok(#(item.bag_index, item.item_id, item.stack_count))
        False -> Error(Nil)
      }
    })
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  assert in_the_bags == [#(in_bags(bag_index: 7).bag_index, stimpack, 3)]
    as "one stack of 3 at the moved slot: the sold stack's slot is empty and the lot is deleted"
  assert list.any(held, fn(item) {
    item.location == chest_slot.location
    && item.bag_index == chest_slot.bag_index
    && item.item_id == chest.item_id
  })
    as "the chest is worn"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- a timed item runs out ----

/// The guid and time left of each 0x111 in the frames that adds an item of this Item2.
fn time_left_of(
  frames frames: List(Frame),
  item2_id item2_id: Int,
) -> List(#(Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == item_added.message_id {
      True -> {
        let assert Ok(added) = item_added.decode(frame.body)
          as "the 0x111 decodes"
        let item = added.held_item.item
        case item.item_id == item2_id {
          True -> Ok(#(item.item_guid, item.time_left_ms))
          False -> Error(Nil)
        }
      }
      False -> Error(Nil)
    }
  })
}

/// The guid and reason of each 0x148 in the frames.
fn removed_in(frames frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == item_removed.message_id {
      True -> {
        let assert Ok(removed) = item_removed.decode(frame.body)
          as "the 0x148 decodes"
        Ok(#(removed.item_guid, removed.reason))
      }
      False -> Error(Nil)
    }
  })
}

/// How many rows of the Item2 the character holds, read straight from the table.
fn rows_of_item(
  pool pool: pog.Connection,
  character_id character_id: Int,
  item2_id item2_id: Int,
) -> Int {
  let assert Ok(pog.Returned(rows: [count], ..)) =
    pog.query(
      "select count(*)::int from character_item where character_id = $1 and item2_id = $2",
    )
    |> pog.parameter(pog.int(character_id))
    |> pog.parameter(pog.int(item2_id))
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(pool)
    as "the rows were counted"
  count
}

/// A timed item counts down in real time, also while its owner is logged out: on the driven clock, one item runs out a minute
/// after the entry while the player is in the world, and the other while the player is away.
/// The entry sends each its time left (`opcode.0x111.time_left`); the one in the world is
/// removed with 0x148 reason 26 at its moment and not before (`opcode.0x148.expired`), its row
/// goes, and an item whose moment passed while the player was away is gone at the next entry.
pub fn a_timed_item_is_removed_at_its_moment_and_one_that_ran_out_while_away_is_gone_at_entry_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  // Item2 12402 (a single item) and 14838 (a stack) are rows of the client's tables; the
  // moments are 60,000 and 100,000 ms after the clock's time now.
  let now_unix_ms = step.unix_milliseconds(now: driven_time.now(time:))
  let put = fn(item2_id, bag_index, moment) {
    let assert Ok(_) =
      pog.query(
        "insert into character_item (character_id, item2_id, location, bag_index, stack_count, charges, expires_at_unix_ms) values ($1, $2, 1, $3, 1, 0, $4)",
      )
      |> pog.parameter(pog.int(character))
      |> pog.parameter(pog.int(item2_id))
      |> pog.parameter(pog.int(bag_index))
      |> pog.parameter(pog.int(moment))
      |> pog.execute(pool)
      as "the timed item is stored"
    Nil
  }
  put(12_402, 0, now_unix_ms + 60_000)
  put(14_838, 1, now_unix_ms + 100_000)
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert list.map(time_left_of(frames: entry, item2_id: 12_402), fn(sent) {
      sent.1
    })
    == [60_000]
    as "the entry sends the first item's time to its moment"
  assert list.map(time_left_of(frames: entry, item2_id: 14_838), fn(sent) {
      sent.1
    })
    == [100_000]
    as "and the second's"
  let assert [#(guid, _)] = time_left_of(frames: entry, item2_id: 12_402)
  // One millisecond before its moment nothing is removed.
  driven_time.advance(time:, ms: 59_999)
  let #(early, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert removed_in(frames: early) == []
    as "the client is told nothing before the moment"
  // At its moment the item is removed, as a delete is, with the reason Expired.
  driven_time.advance(time:, ms: 1)
  let #(due, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      removed_in(frames:) != []
    })
  assert removed_in(frames: due) == [#(guid, 26)]
    as "opcode.0x148.expired: 0x148 for the item with the reason 26"
  assert rows_of_item(pool:, character_id: character, item2_id: 12_402) == 0
    as "the store deleted its row"
  // The player camps; the second item's moment passes while it is away.
  game_client.send_world(game:, message_id: 0x00BF, body: <<1>>)
  let #(_, have) = game_client.read_message(game:, have:, message_id: 0x0092)
  game_client.send_world(game:, message_id: 0x00C0, body: <<>>)
  let #(_, have) = game_client.read_message(game:, have:, message_id: 0x0594)
  driven_time.advance(time:, ms: 600_000)
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let #(_, have) = game_client.read_message(game:, have:, message_id: 0x0117)
  send_play(game:, character_id: character)
  let #(second_entry, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert time_left_of(frames: second_entry, item2_id: 14_838) == []
    as "the second item ran out while its owner was away, so the entry does not send it"
  assert rows_of_item(pool:, character_id: character, item2_id: 14_838) == 0
    as "and its row is gone"
  game_client.close(game:)
  login_support.stop(started)
}

// ---- a development command's items ----

/// The tree started with the development commands on, on the driven clock `time`.
fn started_with_dev_commands(
  time time: driven_time.Time,
) -> login_support.Started {
  login_support.start_with(time:, change: fn(settings) {
    let game = settings.game
    server.Settings(
      ..settings,
      game: server.Served(
        ..game,
        settings: connection_state.Settings(
          ..game.settings,
          game: GameSettings(..game.settings.game, dev_commands: True),
        ),
      ),
    )
  })
}

pub fn an_item_command_puts_the_item_in_the_bag_the_client_reads_test() -> Nil {
  use <- owned_test.run(60_000)
  // The line `!item 90021` on Say is a purchase of cost 0 on the whole server. Item2 90021
  // has maxCharges 5. The client reads the 0x111 of the stack with the reason 4 (Cheat),
  // which raises its loot-channel notice (`opcode.0x111.reason_cheat`), in the first bag slot.
  let time = driven_time.new()
  let started = started_with_dev_commands(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  send_play(game:, character_id: character)
  let #(_, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  game_client.say(game:, text: "!item 90021", chat_message_id: 1)
  let given = fn(frames: List(Frame)) {
    list.filter_map(frames, fn(frame) {
      case frame.message_id == item_added.message_id {
        True ->
          case item_added.decode(frame.body) {
            Ok(added) if added.held_item.item.item_id == 90_021 ->
              Ok(added.held_item)
            Ok(_) | Error(_) -> Error(Nil)
          }
        False -> Error(Nil)
      }
    })
  }
  let #(frames, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      given(frames) != []
    })
  let assert [held] = given(frames)
    as "one 0x111 for the one item the line gave"
  assert held.reason == 4 as "Item.CodeEnumItemUpdateReason: Cheat"
  assert held.item.location == 1 && held.item.bag_index == 0
    as "the first slot of the inventory"
  assert held.item.charges == 5 as "Item2 90021's maxCharges"
  assert held.item.stack_count == 1
  game_client.close(game:)
  login_support.stop(started)
}

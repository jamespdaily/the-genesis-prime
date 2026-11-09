//// The player's item moves (`genesis_prime/game/inventory`): the client's 0x182,
//// taken against the held items, and the store's answer to the move it asked
//// for. Expected values come from these places.
//// - `opcode.0x182`, 0x1403ad100, 0x1403aecd0 and 0x1403b11b0: the checks the
////   client runs on a move and the GenericError code each gives, which the
////   server answers a move it refuses with (0x56A). The codes are the client's
////   `GameLib.CodeEnumGenericError`: 1 Params, 2 PlayerBusy, 5 DbFailure, 31
////   Item_NotValidforSlot, 32 Item_Locked, 37 Item_BagToSmall, 57
////   Player_CantDoWhileDead, 63 Player_CannotWhileInCombat.
//// - `opcode.0x569`: an item moved to an empty place is the item's guid and the
////   place as one 64-bit value, the bag index in bits 0 to 7 and the location
////   in bits 8 to 15, so inventory slot 5 is 1 * 256 + 5 = 261.
//// - `opcode.0x568`: a swap is two pairs of a guid and a place, the moved item
////   at the destination first and the other item at the source second.
//// - `opcode.0x111.guid`: an item keeps its guid when it moves.
//// - The items are the Engineer's Novice set the tests' character wears (guids 1
////   to 7 in bag order, `novice_tables`), each at the bag index of its slot, and
////   a second copy of the chest piece in inventory slot 0 (guid 8): the equipped
////   slot flags of an item are its own, so the copy fits the chest slot, bag
////   index 0, and no other.
//// - A refusal's guid is the guid of the item at the source, or 0 for no item:
////   the client reads none (`opcode.0x56a`), so which one is the server's choice.
//// - A move to a location the server keeps no items at (3 to 99 except 10) is
////   refused with code 1: the server's choice (the coordinator's decision on the
////   issue's test list), as the client sends such a move only for locations the
////   server never fills.

import character_support
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/inventory.{
  type Effect, type Moving, type Taken, Asks, Log, MoveAsked, NoItemRow,
  NotDecoded, Refused, Send,
}
import genesis_prime/game/player_life.{type Life}
import genesis_prime/message/item_action_failed.{ItemActionFailed}
import genesis_prime/message/item_move
import genesis_prime/message/item_moved.{ItemMoved}
import genesis_prime/message/item_place
import genesis_prime/message/items_swapped.{ItemsSwapped}
import genesis_prime/step
import genesis_prime/store.{
  type HeldItem, AccountId, CharacterId, HeldItem, ItemMove, ItemPlace,
  ItemsMoved, MoveItems, MoveRefused, NothingMoved,
}
import genesis_prime/table/id.{Item2Id}
import gleam/list
import gleam/option.{Some}
import gleam/set
import gleam/string
import owned_test
import player_life_support
import world_entry_support

/// The Engineer's seven worn items, guids 1 to 7 in bag order, with a second
/// chest piece in inventory slot 0 (guid 8).
fn held() -> List(HeldItem) {
  let worn =
    world_entry_support.novice_items(
      character: game_connection_support.world_character(),
    )
  let assert [chest, ..] = worn
    as "the Engineer's set has its chest piece first"
  assert chest.bag_index == 0
    as "the chest slot is bag index 0, the lowest bit of its slot flags"
  list.append(worn, [
    HeldItem(
      item_guid: 8,
      item2_id: chest.item2_id,
      location: 1,
      bag_index: 0,
      stack_count: 1,
    ),
  ])
}

/// A copy of the worn chest piece in the bank, which the server never opens.
fn bank_item() -> HeldItem {
  let assert [chest, ..] = held()
  HeldItem(..chest, item_guid: 9, location: 2, bag_index: 0)
}

fn alive() -> Life {
  player_life.new(
    health: 736,
    shield: 0,
    regeneration: player_life_support.regeneration,
  )
}

fn dead() -> Life {
  let #(life, _) =
    player_life.entering(
      saved: Some(0),
      max_health: 736,
      shield: 0,
      regeneration: player_life_support.regeneration,
      place: player_life_support.place(),
    )
  assert player_life.state(life:) == player_life.Dead
  life
}

fn fighting() -> Life {
  let #(life, _) =
    player_life.threatened(
      life: alive(),
      unit_id: 7,
      creature_life: 3,
      gone: set.new(),
    )
  assert player_life.in_combat(life:)
  life
}

/// The body of a 0x182 from one place to another.
fn move_body(from from: #(Int, Int), to to: #(Int, Int)) -> BitArray {
  let assert Ok(body) =
    item_move.encode(item_move.ItemMove(
      from: item_place.ItemPlace(location: from.0, bag_index: from.1),
      to: item_place.ItemPlace(location: to.0, bag_index: to.1),
    ))
    as "two places of 9 and 32 bits fit the message"
  body
}

fn taken(
  items items: List(HeldItem),
  life life: Life,
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Result(Taken, inventory.Refusal) {
  inventory.take(
    items:,
    life:,
    tables: fixture_tables.shared(),
    message: MoveAsked,
    body: move_body(from:, to:),
  )
}

/// The move the rule asks the store for, which it must have accepted.
fn accepted(
  items items: List(HeldItem),
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Moving {
  let assert Ok(Asks(moving:)) = taken(items:, life: alive(), from:, to:)
    as "the move passes every check, so the store is asked"
  moving
}

/// The 0x56A the effects write, decoded: its guid and code.
fn failed_with(effects: List(Effect)) -> List(#(Int, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(frame:) -> {
        assert frame.message_id == item_action_failed.message_id
          as "a refusal is written as 0x56A"
        let assert Ok(ItemActionFailed(item_guid:, code:)) =
          item_action_failed.decode(frame.body)
          as "0x56A decodes"
        Ok(#(item_guid, code))
      }
      Log(..) -> Error(Nil)
    }
  })
}

fn sent(effects: List(Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(frame:) -> Ok(frame)
      Log(..) -> Error(Nil)
    }
  })
}

fn at(items items: List(HeldItem), guid guid: Int) -> #(Int, Int) {
  let assert Ok(item) = list.find(items, fn(item) { item.item_guid == guid })
    as "the item is held"
  #(item.location, item.bag_index)
}

pub fn a_move_to_an_empty_slot_is_saved_then_answered_with_its_new_place_test() -> Nil {
  use <- owned_test.run(10_000)
  // The spare chest piece to inventory slot 5, then the worn chest piece to
  // inventory slot 3 (an unequip).
  let items = held()
  let moving = accepted(items:, from: #(1, 0), to: #(1, 5))
  assert moving.guid == 8
  assert moving.moves
    == [ItemMove(item_guid: 8, from: ItemPlace(1, 0), to: ItemPlace(1, 5))]
    as "one move, the item from where it is held to where the client asked"
  assert inventory.request(
      moving:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
    )
    == store.Items(MoveItems(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      moves: moving.moves,
    ))
    as "the store is asked for the moves, fenced by the login's epoch"
  assert items == held() as "nothing is moved before the store has answered"
  let #(moved, effects) =
    inventory.answered(items:, moving:, answer: ItemsMoved)
  assert at(items: moved, guid: 8) == #(1, 5)
    as "opcode.0x111.guid: the item is at its new place with the guid it had"
  assert list.length(moved) == list.length(items)
  assert list.filter(moved, fn(item) { item.item_guid != 8 })
    == list.filter(items, fn(item) { item.item_guid != 8 })
    as "no other item changed"
  assert list.map(sent(effects), fn(frame) {
      let assert Ok(message) = item_moved.decode(frame.body)
      #(frame.message_id, message)
    })
    == [#(0x0569, ItemMoved(item_guid: 8, place: 261))]
    as "opcode.0x569: the guid and the place, location 1 in bits 8 to 15 and slot 5 in bits 0 to 7"
  let unequipped = accepted(items:, from: #(0, 0), to: #(1, 3))
  let #(moved, effects) =
    inventory.answered(items:, moving: unequipped, answer: ItemsMoved)
  assert at(items: moved, guid: 1) == #(1, 3)
    as "an unequip is the same message: the chest piece is in inventory slot 3"
  assert list.map(sent(effects), fn(frame) {
      let assert Ok(message) = item_moved.decode(frame.body)
      message
    })
    == [ItemMoved(item_guid: 1, place: 259)]
    as "opcode.0x569: inventory slot 3 is 1 * 256 + 3"
}

pub fn a_move_onto_an_item_swaps_the_two_test() -> Nil {
  use <- owned_test.run(10_000)
  // The worn chest piece (guid 1) onto inventory slot 0, which holds the spare
  // chest piece (guid 8): the spare is equipped and the worn one unequipped.
  let items = held()
  let moving = accepted(items:, from: #(0, 0), to: #(1, 0))
  assert moving.moves
    == [
      ItemMove(item_guid: 1, from: ItemPlace(0, 0), to: ItemPlace(1, 0)),
      ItemMove(item_guid: 8, from: ItemPlace(1, 0), to: ItemPlace(0, 0)),
    ]
    as "two moves, each item to the other's place, which the store applies together"
  let #(moved, effects) =
    inventory.answered(items:, moving:, answer: ItemsMoved)
  assert at(items: moved, guid: 1) == #(1, 0)
  assert at(items: moved, guid: 8) == #(0, 0)
    as "each item keeps its guid and takes the other's place"
  assert list.map(sent(effects), fn(frame) {
      let assert Ok(message) = items_swapped.decode(frame.body)
      #(frame.message_id, message)
    })
    == [
      #(
        0x0568,
        ItemsSwapped(
          first_guid: 1,
          first_place: 256,
          second_guid: 8,
          second_place: 0,
        ),
      ),
    ]
    as "opcode.0x568: the moved item at the destination (1 * 256 + 0), then the other item at the source (0)"
}

pub fn a_move_the_client_would_refuse_is_refused_with_its_code_test() -> Nil {
  use <- owned_test.run(10_000)
  // The held items and a copy of the chest piece in the bank (guid 9), the one
  // place besides the bags and worn gear a move can start from.
  let items = list.append(held(), [bank_item()])
  // Each row: what it breaks, the life, the move and the code with the guid of
  // the item at the source (0 for none).
  let rows = [
    // 0x1403ad100's caller: a dead player or a ghost, Player_CantDoWhileDead.
    #("dead", dead(), #(1, 0), #(1, 5), 8, 57),
    #("dead before a locked destination", dead(), #(1, 0), #(100, 0), 8, 57),
    // The destination locations 100 to 299 are locked: Item_Locked, checked
    // before the source is looked for.
    #("destination 100", alive(), #(1, 0), #(100, 0), 8, 32),
    #("destination 299", alive(), #(1, 0), #(299, 0), 8, 32),
    #("a locked destination of no item", alive(), #(1, 40), #(150, 0), 0, 32),
    // No held item at the source: Params.
    #("no item at the source", alive(), #(1, 7), #(1, 8), 0, 1),
    // 0x1403ad100: the same slot, a destination location of 300 or more, an
    // equipped bag index above 30 and an inventory index of 96 or more are
    // Params.
    #("the same slot", alive(), #(1, 0), #(1, 0), 8, 1),
    #("destination location 300", alive(), #(1, 0), #(300, 0), 8, 1),
    #("equipped index 31", alive(), #(1, 0), #(0, 31), 8, 1),
    #("inventory index 96", alive(), #(1, 0), #(1, 96), 8, 1),
    // 0x1403ad100 tests the inventory index after the combat and the closed
    // checks, so an index of 96 or more in combat or from the bank is 63 or 2.
    #("in combat, an unequip to index 96", fighting(), #(0, 0), #(1, 96), 1, 63),
    #("the bank to index 96", alive(), #(2, 0), #(1, 96), 9, 2),
    // 0x1403aecd0: in combat a move with an equipped side is refused,
    // Player_CannotWhileInCombat.
    #("in combat, an unequip", fighting(), #(0, 0), #(1, 5), 1, 63),
    #("in combat, an equip", fighting(), #(1, 0), #(0, 0), 8, 63),
    // The bank, a bank bag slot (equipped 21 to 30) and location 10 are not
    // opened by the server: PlayerBusy.
    #("bank", alive(), #(1, 0), #(2, 0), 8, 2),
    #("equipped bank bag slot 21", alive(), #(1, 0), #(0, 21), 8, 2),
    #("equipped bank bag slot 30", alive(), #(1, 0), #(0, 30), 8, 2),
    #("location 10", alive(), #(1, 0), #(10, 0), 8, 2),
    // 0x1403b11b0: the inventory holds 16 slots with no bags worn:
    // Item_BagToSmall.
    #("inventory index 16", alive(), #(1, 0), #(1, 16), 8, 37),
    // An item entering location 0 at a slot whose bit its equipped slot flags
    // lack, or at bag slot 17 to 20, is Item_NotValidforSlot; the other item of
    // a swap is checked too when the source is equipped.
    #("a chest piece at the legs slot", alive(), #(1, 0), #(0, 1), 8, 31),
    #("a chest piece at bag slot 17", alive(), #(1, 0), #(0, 17), 8, 31),
    #("a chest piece at bag slot 20", alive(), #(1, 0), #(0, 20), 8, 31),
    #("the legs swapped with a chest piece", alive(), #(0, 1), #(1, 0), 2, 31),
    // A location the server keeps no items at: Params (server choice).
    #("location 5", alive(), #(1, 0), #(5, 0), 8, 1),
    #("location 99", alive(), #(1, 0), #(99, 0), 8, 1),
  ]
  list.each(rows, fn(row) {
    let #(what, life, from, to, guid, code) = row
    let result = taken(items:, life:, from:, to:)
    let assert Ok(Refused(effects:)) = result
      as { what <> ": refused, so no ask is made" }
    assert failed_with(effects) == [#(guid, code)]
      as { what <> ": one 0x56A with the client's code" }
    assert list.length(effects) == 1
      as { what <> ": nothing else is written or logged" }
  })
  // The checks do not refuse what the client allows: a move in combat with no
  // equipped side, the worn chest piece's own slot and a bag slot the client
  // accepts.
  assert list.all(
    [
      taken(items:, life: fighting(), from: #(1, 0), to: #(1, 5)),
      taken(items:, life: alive(), from: #(1, 0), to: #(0, 0)),
      taken(items:, life: alive(), from: #(1, 0), to: #(1, 15)),
    ],
    is_ask,
  )
    as "a move that breaks no check asks the store"
  // A body the client's own reader refuses is no move at all.
  let assert Error(NotDecoded(undecoded:)) =
    inventory.take(
      items:,
      life: alive(),
      tables: fixture_tables.shared(),
      message: MoveAsked,
      body: <<1, 2, 3>>,
    )
    as "a body too short for two places is refused"
  assert undecoded_message(undecoded) == 0x0182
}

/// The held items with one more in inventory slot 1: this Item2 row, guid 9.
fn with_spare(item2_id: Int) -> List(HeldItem) {
  list.append(held(), [
    HeldItem(
      item_guid: 9,
      item2_id: Item2Id(item2_id),
      location: 1,
      bag_index: 1,
      stack_count: 1,
    ),
  ])
}

pub fn gear_with_stats_is_equipped_into_its_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client's Item2 row 8527 is a chest piece with a budget (itemBudgetId 3)
  // and a stat (itemStatId 6), of the same Item2Type (8) as the novice chest
  // piece (row 1229), so its slot is the chest, bag index 0; the gear of the
  // quests and the vendors is all of this kind. The rule must not read the
  // budget or stat as a reason to refuse the slot.
  let items = with_spare(8527)
  let moving = accepted(items:, from: #(1, 1), to: #(0, 0))
  assert moving.moves
    == [
      ItemMove(item_guid: 9, from: ItemPlace(1, 1), to: ItemPlace(0, 0)),
      ItemMove(item_guid: 1, from: ItemPlace(0, 0), to: ItemPlace(1, 1)),
    ]
    as "the statted chest piece is worn in place of the novice one, which goes to the bag slot it left"
  let assert Ok(Refused(effects:)) =
    taken(items:, life: alive(), from: #(1, 1), to: #(0, 1))
    as "the chest piece is still refused at the legs slot, bag index 1"
  assert failed_with(effects) == [#(9, 31)]
}

pub fn a_held_item_with_no_item_row_ends_the_move_as_a_bug_test() -> Nil {
  use <- owned_test.run(10_000)
  // No row of Item2 has this id, so the client could not hold the item: the
  // server's state is broken, which no GenericError code describes (0x1403b11b0
  // gives Item_BadId 6 only for an id the client could not look up).
  let items = with_spare(99_999_999)
  let assert Error(NoItemRow(item2_id:)) =
    taken(items:, life: alive(), from: #(1, 1), to: #(0, 0))
    as "an item with no row ends the move, it is not refused as a wrong slot"
  assert item2_id == Item2Id(99_999_999)
    as "the refusal names the item that has no row"
  assert list.all(
    [taken(items:, life: alive(), from: #(1, 1), to: #(1, 2))],
    is_ask,
  )
    as "no row matters only for a slot that needs the item's equipped slot flags"
}

fn is_ask(result: Result(Taken, inventory.Refusal)) -> Bool {
  case result {
    Ok(Asks(..)) -> True
    Ok(Refused(..)) | Error(NotDecoded(..)) | Error(NoItemRow(..)) -> False
  }
}

fn undecoded_message(undecoded: Undecoded) -> Int {
  undecoded.message_id
}

pub fn a_move_the_store_did_not_make_is_refused_db_failure_test() -> Nil {
  use <- owned_test.run(10_000)
  let items = held()
  let moving = accepted(items:, from: #(1, 0), to: #(1, 5))
  let #(unmoved, effects) =
    inventory.answered(items:, moving:, answer: NothingMoved)
  assert unmoved == items as "nothing was moved, so the items are as they were"
  assert failed_with(effects) == [#(8, 5)]
    as "GenericError 5 DbFailure, naming the item"
  let assert [Log(level: level, text: text), Send(..)] = effects
    as "a log line, then the refusal"
  assert level == step.LogWarning
    as "a later login, a stale place or no such character is an outside failure of the store, a warning"
  assert string.contains(text, "moved")
  let #(unmoved, effects) =
    inventory.answered(
      items:,
      moving:,
      answer: MoveRefused(constraint: "character_item_one_per_slot"),
    )
  assert unmoved == items as "a refused place leaves the items as they were"
  assert failed_with(effects) == [#(8, 5)]
  let assert [Log(level: level, text: text), Send(..)] = effects
    as "a log line, then the refusal"
  assert level == step.LogError
    as "no place the rule asks for breaks a constraint, so it is a bug of the server's"
  assert string.contains(text, "character_item_one_per_slot")
    as "the failed write names the constraint"
}

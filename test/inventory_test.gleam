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
//// - Stacks: `opcode.0x17d` (a split is 0x17D {guid, place, count}, which the
////   client sends only onto an empty slot, 0x1406d48c0), `opcode.0x149` (a
////   delete is 0x149 {place}; its sender 0x1403c1360 refuses an Item2 with flags
////   0x10000 with 156), `opcode.0x17f` and `opcode.0x148` (the replies),
////   `opcode.0x111` (the new stack) and 0x1403b8060 (the reason 0, StackSplit,
////   raises no notice). A merge is a 0x182 onto a stack of the same stackable
////   Item2 (0x1406d50f0). The Item2 rows are the client's own, roots of the
////   fixture: 1039 stacks to 20 (its category's flags hold 0x4), 12049 is a bag
////   that holds 6 with no stackable flag, and 80875 has flags 0x10000 and
////   stacks to 1.

import character_support
import equip_requirement_support
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/equip_requirement.{type Wearer, Wearer}
import genesis_prime/game/inventory.{
  type Effect, type Moving, type Taken, Asks, DeleteAsked, EquipCheckBroken, Log,
  MoveAsked, NoItemRow, NotDecoded, Refused, Send, SplitAsked,
}
import genesis_prime/game/player_life.{type Life}
import genesis_prime/message/item_action_failed.{ItemActionFailed}
import genesis_prime/message/item_added
import genesis_prime/message/item_count_changed.{ItemCountChanged}
import genesis_prime/message/item_delete.{ItemDelete}
import genesis_prime/message/item_move
import genesis_prime/message/item_moved.{ItemMoved}
import genesis_prime/message/item_place
import genesis_prime/message/item_removed.{ItemRemoved}
import genesis_prime/message/item_split.{ItemSplit}
import genesis_prime/message/items_swapped.{ItemsSwapped}
import genesis_prime/step
import genesis_prime/store.{
  type HeldItem, AccountId, CharacterId, HeldItem, ItemMade, ItemMove, ItemPlace,
  ItemsNotSaved, ItemsSaved, MergeItems, MoveItems, SaveRefused, SplitItem,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/derivation
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import gleam/int
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

/// The move of the Engineer of the tests (`equip_requirement_support.engineer`).
fn taken(
  items items: List(HeldItem),
  life life: Life,
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Result(Taken, inventory.Refusal) {
  taken_by(
    wearer: equip_requirement_support.engineer(),
    items:,
    life:,
    from:,
    to:,
  )
}

fn taken_by(
  wearer wearer: Wearer,
  items items: List(HeldItem),
  life life: Life,
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Result(Taken, inventory.Refusal) {
  taken_with(wearer:, bag_slots: 0, items:, life:, from:, to:)
}

/// A move with the BagSlots value the client was sent.
fn taken_with(
  wearer wearer: Wearer,
  bag_slots bag_slots: Int,
  items items: List(HeldItem),
  life life: Life,
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Result(Taken, inventory.Refusal) {
  inventory.take(
    items:,
    life:,
    tables: fixture_tables.shared(),
    wearer:,
    bag_slots:,
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

/// The moves of an accepted move or swap.
fn moves_of(moving: Moving) -> List(store.ItemMove) {
  let assert inventory.Moved(moves:, ..) = moving.change
    as "a 0x182 onto an empty slot or a different item is saved as moves"
  moves
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
  assert moves_of(moving)
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
      moves: moves_of(moving),
    ))
    as "the store is asked for the moves, fenced by the login's epoch"
  assert items == held() as "nothing is moved before the store has answered"
  let #(moved, effects) =
    inventory.answered(items:, moving:, answer: ItemsSaved)
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
    inventory.answered(items:, moving: unequipped, answer: ItemsSaved)
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
  assert moves_of(moving)
    == [
      ItemMove(item_guid: 1, from: ItemPlace(0, 0), to: ItemPlace(1, 0)),
      ItemMove(item_guid: 8, from: ItemPlace(1, 0), to: ItemPlace(0, 0)),
    ]
    as "two moves, each item to the other's place, which the store applies together"
  let #(moved, effects) =
    inventory.answered(items:, moving:, answer: ItemsSaved)
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
      wearer: equip_requirement_support.engineer(),
      bag_slots: 0,
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
  //
  // The row requires class 24 (classes 4 and 5, masks of bit `class - 1`) and its
  // category 2's ItemProficiency is mask 4, which the Engineer's 66 lacks
  // (0x1403b4710): the wearer is a Medic (class 4) with that one proficiency.
  let items = with_spare(8527)
  let wearer =
    Wearer(
      ..equip_requirement_support.of_class(
        equip_requirement_support.engineer(),
        class_id: 4,
      ),
      item_proficiencies: 4,
    )
  let assert Ok(Asks(moving:)) =
    taken_by(wearer:, items:, life: alive(), from: #(1, 1), to: #(0, 0))
    as "the move passes every check, so the store is asked"
  assert moves_of(moving)
    == [
      ItemMove(item_guid: 9, from: ItemPlace(1, 1), to: ItemPlace(0, 0)),
      ItemMove(item_guid: 1, from: ItemPlace(0, 0), to: ItemPlace(1, 1)),
    ]
    as "the statted chest piece is worn in place of the novice one, which goes to the bag slot it left"
  let assert Ok(Refused(effects:)) =
    taken_by(wearer:, items:, life: alive(), from: #(1, 1), to: #(0, 1))
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
    Ok(Refused(..))
    | Error(NotDecoded(..))
    | Error(NoItemRow(..))
    | Error(EquipCheckBroken(..)) -> False
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
    inventory.answered(items:, moving:, answer: ItemsNotSaved)
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
      answer: SaveRefused(constraint: "character_item_one_per_slot"),
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

/// Item2 1039, a stackable item of the client's tables that holds 20.
fn stackable() -> Int {
  fixture_tables.root("Item2", 1039)
}

/// Item2 12049: a bag the client lets hold 6 with no stackable flag.
fn bag() -> Int {
  fixture_tables.root("Item2", 12_049)
}

/// Item2 80875: its flags hold 0x10000, so it cannot be deleted, and it stacks
/// to 1.
fn undeletable() -> Int {
  fixture_tables.root("Item2", 80_875)
}

/// An item of the inventory.
fn in_bag(
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

fn body_of_split(
  guid guid: Int,
  to to: #(Int, Int),
  count count: Int,
) -> BitArray {
  let assert Ok(body) =
    item_split.encode(ItemSplit(
      item_guid: guid,
      to: item_place.ItemPlace(location: to.0, bag_index: to.1),
      count:,
    ))
    as "a guid, a place and a count fit 0x17D"
  body
}

fn body_of_delete(at at: #(Int, Int)) -> BitArray {
  let assert Ok(body) =
    item_delete.encode(
      ItemDelete(place: item_place.ItemPlace(location: at.0, bag_index: at.1)),
    )
    as "a place of 9 and 32 bits fits 0x149"
  body
}

fn split_taken(
  items items: List(HeldItem),
  life life: Life,
  guid guid: Int,
  to to: #(Int, Int),
  count count: Int,
) -> Result(Taken, inventory.Refusal) {
  inventory.take(
    items:,
    life:,
    tables: fixture_tables.shared(),
    wearer: equip_requirement_support.engineer(),
    bag_slots: 0,
    message: SplitAsked,
    body: body_of_split(guid:, to:, count:),
  )
}

fn delete_taken(
  items items: List(HeldItem),
  at at: #(Int, Int),
) -> Result(Taken, inventory.Refusal) {
  inventory.take(
    items:,
    life: alive(),
    tables: fixture_tables.shared(),
    wearer: equip_requirement_support.engineer(),
    bag_slots: 0,
    message: DeleteAsked,
    body: body_of_delete(at:),
  )
}

fn asked(result: Result(Taken, inventory.Refusal)) -> Moving {
  let assert Ok(Asks(moving:)) = result
    as "the change passes every check, so the store is asked"
  moving
}

/// The guid, count and reason of each 0x17F the effects write, in order.
fn counts_in(effects: List(Effect)) -> List(#(Int, Int, Int)) {
  list.map(sent(effects), fn(frame) {
    assert frame.message_id == item_count_changed.message_id
      as "opcode.0x17f: only count changes are written"
    let assert Ok(ItemCountChanged(item_guid:, count:, reason:)) =
      item_count_changed.decode(frame.body)
    #(item_guid, count, reason)
  })
}

fn count_of(items items: List(HeldItem), guid guid: Int) -> Int {
  let assert Ok(item) = list.find(items, fn(item) { item.item_guid == guid })
    as "the item is held"
  item.stack_count
}

fn without(
  items items: List(HeldItem),
  guids guids: List(Int),
) -> List(HeldItem) {
  list.filter(items, fn(item) { !list.contains(guids, item.item_guid) })
}

pub fn a_split_onto_an_empty_slot_is_saved_then_answered_with_the_new_stack_test() -> Nil {
  use <- owned_test.run(10_000)
  // A stack of 10 of Item2 1039 in inventory slot 1; 3 of it go to slot 2.
  let stack = in_bag(guid: 20, item2_id: stackable(), index: 1, count: 10)
  let items = list.append(held(), [stack])
  let moving =
    asked(split_taken(items:, life: alive(), guid: 20, to: #(1, 2), count: 3))
  assert moving.guid == 20 as "a refusal would name the stack the player split"
  assert moving.change
    == inventory.Split(source: stack, count: 3, to: ItemPlace(1, 2))
    as "3 of the stack to the empty slot"
  assert inventory.request(
      moving:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
    )
    == store.Items(SplitItem(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      source: stack,
      count: 3,
      to: ItemPlace(1, 2),
    ))
    as "the store is asked for the split, fenced by the login's epoch and the stack as held"
  let #(made, effects) =
    inventory.answered(items:, moving:, answer: ItemMade(item_guid: 77))
  assert count_of(items: made, guid: 20) == 7
    as "the source keeps what is left of it"
  assert list.find(made, fn(item) { item.item_guid == 77 })
    == Ok(in_bag(guid: 77, item2_id: stackable(), index: 2, count: 3))
    as "opcode.0x111.guid: the new stack is held with the guid the store made, the same Item2, the empty slot and the count"
  assert without(items: made, guids: [20, 77]) == without(items:, guids: [20])
    as "no other item changed"
  let frames = sent(effects)
  assert list.map(frames, fn(frame) { frame.message_id }) == [0x017F, 0x0111]
    as "opcode.0x17f of the source then opcode.0x111 of the new stack"
  let assert [counted, added] = frames
  assert item_count_changed.decode(counted.body)
    == Ok(ItemCountChanged(item_guid: 20, count: 7, reason: 0))
    as "opcode.0x17f: the source's new count, reason 0 (StackSplit, which raises no loot notice, 0x1403b8060)"
  let assert Ok(item_added.ItemAdded(held_item:)) =
    item_added.decode(added.body)
  let shared = held_item.item
  assert #(
      shared.item_guid,
      shared.item_id,
      shared.location,
      shared.bag_index,
      shared.stack_count,
      held_item.reason,
    )
    == #(77, 1039, 1, 2, 3, 0)
    as "opcode.0x111: the new stack's guid, item, place and count, reason 0"
}

pub fn a_split_the_client_would_not_send_is_refused_with_its_code_test() -> Nil {
  use <- owned_test.run(10_000)
  let stack = in_bag(guid: 20, item2_id: stackable(), index: 1, count: 10)
  let items = list.append(held(), [stack])
  // Each row: what it breaks, the guid, the destination, the count, and the
  // guid and code of the 0x56A.
  let rows = [
    // Check 1: no held item has the guid, so the guid is 0.
    #("no held item has the guid", 999, #(1, 2), 3, 0, 1),
    // Check 2: the count is 0, or the held count or more (10).
    #("count 0", 20, #(1, 2), 0, 20, 1),
    #("count equal to the stack", 20, #(1, 2), 10, 20, 1),
    #("count past the stack", 20, #(1, 2), 11, 20, 1),
    #("count 0 to the bank", 20, #(2, 0), 0, 20, 1),
    // Check 3: the bank, an equipped bank bag slot and location 10 are not
    // opened by the server.
    #("bank destination", 20, #(2, 0), 3, 20, 2),
    #("equipped bank bag slot 21", 20, #(0, 21), 3, 20, 2),
    #("location 10", 20, #(10, 0), 3, 20, 2),
    // Check 4: any other place that is not the inventory, or an index of 96 or
    // more.
    #("equipped destination", 20, #(0, 5), 3, 20, 1),
    #("location 300", 20, #(300, 0), 3, 20, 1),
    #("inventory index 96", 20, #(1, 96), 3, 20, 1),
    // Check 5: the inventory holds 16 slots with no bags worn.
    #("inventory index 16", 20, #(1, 16), 3, 20, 37),
    // Check 6: an item is held at the destination (the spare chest piece).
    #("an occupied slot", 20, #(1, 0), 3, 20, 1),
  ]
  list.each(rows, fn(row) {
    let #(what, guid, to, count, shown, code) = row
    let assert Ok(Refused(effects:)) =
      split_taken(items:, life: alive(), guid:, to:, count:)
      as { what <> ": refused, so no ask is made" }
    assert failed_with(effects) == [#(shown, code)]
      as { what <> ": one 0x56A with the code of the check" }
    assert list.length(effects) == 1
      as { what <> ": nothing else is written or logged" }
  })
  // The client's split path has no dead or combat check (opcode.0x17d), so a
  // player in either is asked for.
  list.each([dead(), fighting()], fn(life) {
    assert is_ask(split_taken(items:, life:, guid: 20, to: #(1, 2), count: 3))
      as "a split in combat or dead is asked for"
  })
  let assert Error(NotDecoded(undecoded:)) =
    inventory.take(
      items:,
      life: alive(),
      tables: fixture_tables.shared(),
      wearer: equip_requirement_support.engineer(),
      bag_slots: 0,
      message: SplitAsked,
      body: <<1, 2, 3>>,
    )
    as "a body too short for a split is refused"
  assert undecoded_message(undecoded) == 0x017D
}

pub fn a_move_onto_a_stack_of_the_same_item_merges_it_whole_test() -> Nil {
  use <- owned_test.run(10_000)
  // 3 of Item2 1039 in slot 1 dropped on 4 of it in slot 2: the limit is 20, so
  // all 3 fit.
  let source = in_bag(guid: 20, item2_id: stackable(), index: 1, count: 3)
  let target = in_bag(guid: 21, item2_id: stackable(), index: 2, count: 4)
  let items = list.append(held(), [source, target])
  let moving = accepted(items:, from: #(1, 1), to: #(1, 2))
  assert moving.guid == 20 as "the item the player dragged"
  assert moving.change == inventory.Merged(source:, target:, count: 3)
    as "all 3 of the source go onto the target"
  assert inventory.request(
      moving:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
    )
    == store.Items(MergeItems(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      source:,
      target:,
      count: 3,
    ))
    as "the store is asked for the merge, fenced by the login's epoch and both stacks as held"
  let #(merged, effects) =
    inventory.answered(items:, moving:, answer: ItemsSaved)
  assert count_of(items: merged, guid: 21) == 7 as "the target holds the sum"
  assert list.find(merged, fn(item) { item.item_guid == 20 }) == Error(Nil)
    as "the source is gone"
  assert without(items: merged, guids: [21]) == without(items:, guids: [20, 21])
    as "no other item changed"
  let frames = sent(effects)
  assert list.map(frames, fn(frame) { frame.message_id }) == [0x017F, 0x0148]
    as "opcode.0x17f of the target then opcode.0x148 of the source"
  let assert [counted, removed] = frames
  assert item_count_changed.decode(counted.body)
    == Ok(ItemCountChanged(item_guid: 21, count: 7, reason: 0))
    as "opcode.0x17f: the target's new count, reason 0, which also clears the move wait"
  assert item_removed.decode(removed.body)
    == Ok(ItemRemoved(item_guid: 20, reason: 0))
    as "opcode.0x148: the source is gone, reason 0"
}

pub fn a_merge_past_the_stack_limit_fills_the_target_and_keeps_the_rest_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 1039 holds 20 (maxStackCount): the target at 18 has room for 2 of the
  // source's 5.
  let source = in_bag(guid: 20, item2_id: stackable(), index: 1, count: 5)
  let target = in_bag(guid: 21, item2_id: stackable(), index: 2, count: 18)
  let items = list.append(held(), [source, target])
  let moving = accepted(items:, from: #(1, 1), to: #(1, 2))
  assert moving.change == inventory.Merged(source:, target:, count: 2)
    as "only the 2 that fit move"
  let #(merged, effects) =
    inventory.answered(items:, moving:, answer: ItemsSaved)
  assert count_of(items: merged, guid: 21) == 20
    as "the target is full, at the Item2's maxStackCount"
  assert count_of(items: merged, guid: 20) == 3
    as "the source keeps the 3 that did not fit"
  assert list.length(merged) == list.length(items)
  assert counts_in(effects) == [#(21, 20, 0), #(20, 3, 0)]
    as "opcode.0x17f of the target at the limit then of the source at what is left, reason 0"
}

pub fn a_move_onto_a_full_stack_or_an_item_that_does_not_stack_swaps_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each row: what it is, the item in slot 1, the item in slot 2. A 0x182 of
  // slot 1 onto slot 2 is #579's swap for each.
  let rows = [
    #(
      "a full target",
      in_bag(guid: 20, item2_id: stackable(), index: 1, count: 5),
      in_bag(guid: 21, item2_id: stackable(), index: 2, count: 20),
    ),
    #(
      "a stack that holds only 1",
      in_bag(guid: 20, item2_id: undeletable(), index: 1, count: 1),
      in_bag(guid: 21, item2_id: undeletable(), index: 2, count: 1),
    ),
    #(
      "a bag of the same Item2 id",
      in_bag(guid: 20, item2_id: bag(), index: 1, count: 1),
      in_bag(guid: 21, item2_id: bag(), index: 2, count: 1),
    ),
    #(
      "a different Item2 id",
      in_bag(guid: 20, item2_id: stackable(), index: 1, count: 5),
      in_bag(guid: 21, item2_id: bag(), index: 2, count: 1),
    ),
  ]
  list.each(rows, fn(row) {
    let #(what, first, second) = row
    let items = list.append(held(), [first, second])
    let moving = accepted(items:, from: #(1, 1), to: #(1, 2))
    assert moves_of(moving)
      == [
        ItemMove(item_guid: 20, from: ItemPlace(1, 1), to: ItemPlace(1, 2)),
        ItemMove(item_guid: 21, from: ItemPlace(1, 2), to: ItemPlace(1, 1)),
      ]
      as { what <> ": the two items trade places" }
    let #(swapped, effects) =
      inventory.answered(items:, moving:, answer: ItemsSaved)
    assert at(items: swapped, guid: 20) == #(1, 2)
    assert at(items: swapped, guid: 21) == #(1, 1)
    assert count_of(items: swapped, guid: 20) == first.stack_count
      as { what <> ": no count changed" }
    assert list.map(sent(effects), fn(frame) { frame.message_id }) == [0x0568]
      as { what <> ": opcode.0x568, the swap's answer" }
  })
}

pub fn a_delete_is_saved_then_answered_with_the_destroy_reason_test() -> Nil {
  use <- owned_test.run(10_000)
  let stack = in_bag(guid: 20, item2_id: stackable(), index: 1, count: 10)
  let items = list.append(held(), [stack])
  let moving = asked(delete_taken(items:, at: #(1, 1)))
  assert moving.guid == 20
  assert moving.change == inventory.Deleted(item: stack)
    as "the whole stack at the place"
  assert inventory.request(
      moving:,
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
    )
    == store.Items(store.DeleteItem(
      account_id: AccountId(7),
      character_id: CharacterId(42),
      session_epoch: character_support.epoch(1),
      item: stack,
    ))
    as "the store is asked for the delete, fenced by the login's epoch and the item as held"
  let #(left, effects) = inventory.answered(items:, moving:, answer: ItemsSaved)
  assert left == held() as "the stack is gone and no other item changed"
  let assert [frame] = sent(effects)
  assert frame.message_id == 0x0148
  assert item_removed.decode(frame.body)
    == Ok(ItemRemoved(item_guid: 20, reason: 21))
    as "opcode.0x148 with the reason 21, PlayerRequested"
  assert list.length(effects) == 1
}

pub fn a_delete_the_client_would_not_send_is_refused_with_its_code_test() -> Nil {
  use <- owned_test.run(10_000)
  let stack = in_bag(guid: 20, item2_id: stackable(), index: 1, count: 10)
  let locked = in_bag(guid: 21, item2_id: undeletable(), index: 3, count: 1)
  let items = list.append(held(), [stack, locked])
  // Each row: what it breaks, the place, and the guid and code of the 0x56A.
  // The first four are places the client's sender (0x1403c1360) sends nothing
  // for, so the guid is 0.
  let rows = [
    #("location 300", #(300, 0), 0, 1),
    #("bag index 0xffffffff", #(1, 0xffffffff), 0, 1),
    #("equipped index 31", #(0, 31), 0, 1),
    #("an empty place", #(1, 50), 0, 1),
    // Item2 80875's flags hold 0x10000: Item_CannotBeDeleted.
    #("an Item2 whose flags hold 0x10000", #(1, 3), 21, 156),
  ]
  list.each(rows, fn(row) {
    let #(what, at, guid, code) = row
    let assert Ok(Refused(effects:)) = delete_taken(items:, at:)
      as { what <> ": refused, so no ask is made" }
    assert failed_with(effects) == [#(guid, code)]
      as { what <> ": one 0x56A with the code" }
    assert list.length(effects) == 1
      as { what <> ": nothing else is written or logged" }
  })
  // An item with no Item2 row is the server's broken state: the connection ends.
  let broken =
    list.append(held(), [
      in_bag(guid: 22, item2_id: 99_999_999, index: 4, count: 1),
    ])
  let assert Error(NoItemRow(item2_id:)) =
    delete_taken(items: broken, at: #(1, 4))
    as "no row for the item ends the connection, as the client's sender gives Item_BadId"
  assert item2_id == Item2Id(99_999_999)
  let assert Error(NotDecoded(undecoded:)) =
    inventory.take(
      items:,
      life: alive(),
      tables: fixture_tables.shared(),
      wearer: equip_requirement_support.engineer(),
      bag_slots: 0,
      message: DeleteAsked,
      body: <<1>>,
    )
    as "a body too short for a place is refused"
  assert undecoded_message(undecoded) == 0x0149
}

pub fn a_split_merge_or_delete_the_store_did_not_save_is_refused_db_failure_test() -> Nil {
  use <- owned_test.run(10_000)
  let source = in_bag(guid: 20, item2_id: stackable(), index: 1, count: 5)
  let target = in_bag(guid: 21, item2_id: stackable(), index: 2, count: 4)
  let items = list.append(held(), [source, target])
  // Each row: what the change does, the word its log line holds, the change.
  let changes = [
    #(
      "split",
      "split",
      asked(split_taken(items:, life: alive(), guid: 20, to: #(1, 3), count: 2)),
    ),
    #("merge", "merged", accepted(items:, from: #(1, 1), to: #(1, 2))),
    #("delete", "deleted", asked(delete_taken(items:, at: #(1, 1)))),
  ]
  list.each(changes, fn(change) {
    let #(what, word, moving) = change
    let #(unchanged, effects) =
      inventory.answered(items:, moving:, answer: ItemsNotSaved)
    assert unchanged == items
      as { what <> ": nothing was saved, so the items are as they were" }
    assert failed_with(effects) == [#(20, 5)]
      as {
        what <> ": GenericError 5 DbFailure, naming the stack the player named"
      }
    let assert [Log(level:, text:), Send(..)] = effects
      as { what <> ": a log line, then the refusal" }
    assert level == step.LogWarning
      as {
        what
        <> ": a later login or a stale row is an outside failure, a warning"
      }
    assert string.contains(text, word)
    let #(unchanged, effects) =
      inventory.answered(
        items:,
        moving:,
        answer: SaveRefused(constraint: "character_item_one_per_slot"),
      )
    assert unchanged == items
      as { what <> ": a refused change leaves the items as they were" }
    assert failed_with(effects) == [#(20, 5)]
    let assert [Log(level:, text:), Send(..)] = effects
      as { what <> ": a log line, then the refusal" }
    assert level == step.LogError
      as {
        what
        <> ": no change the rule asks for breaks a constraint, so it is a bug of the server's"
      }
    assert string.contains(text, "character_item_one_per_slot")
      as { what <> ": the failed write names the constraint" }
  })
}

/// The Engineer's worn items with one more in inventory slot 0: this Item2
/// row, guid 9. The spare chest piece of `held` is not there.
fn worn_with_slot_zero(item2_id: Int) -> List(HeldItem) {
  let assert [_, ..] as worn =
    list.filter(held(), fn(item) { item.location == 0 })
  list.append(worn, [
    HeldItem(
      item_guid: 9,
      item2_id: Item2Id(item2_id),
      location: 1,
      bag_index: 0,
      stack_count: 1,
    ),
  ])
}

pub fn an_item_that_is_not_slotted_is_refused_not_valid_for_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client's Item2 row 80982 has its own equippedSlotFlags 0x1, but its
  // Item2Type, Item2Category and Item2Family flags hold no 0x400, so
  // CheckItemEquipSlot (0x1403b11b0) refuses every equipped location 0 slot for
  // it, the chest slot (bag index 0, bit 0x1) included: Item_NotValidforSlot,
  // 31. The server took the item's own flags alone and accepted the move.
  let items = worn_with_slot_zero(80_982)
  let assert Ok(Refused(effects:)) =
    taken(items:, life: alive(), from: #(1, 0), to: #(0, 0))
    as "the item is refused, so the store is not asked"
  assert failed_with(effects) == [#(9, 31)]
    as "one 0x56A with the guid of the item at the source and code 31"
  assert list.length(effects) == 1 as "nothing else is written or logged"
}

pub fn an_item_whose_type_has_no_slot_row_is_refused_not_valid_for_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client's Item2 row 84594 is of Item2Type 537, whose itemSlotId is 0, and
  // ItemSlot has no row 0; its type, category and family flags hold no 0x400, so
  // CheckItemEquipSlot (0x1403b11b0) refuses it at every equipped location 0 slot
  // with Item_NotValidforSlot, 31, before it reads any slot flags. The server read
  // the missing ItemSlot row first and ended the connection.
  let items = worn_with_slot_zero(84_594)
  let assert Ok(Refused(effects:)) =
    taken(items:, life: alive(), from: #(1, 0), to: #(0, 0))
    as "the item is refused, not a broken state, and the store is not asked"
  assert failed_with(effects) == [#(9, 31)]
    as "one 0x56A with the guid of the item at the source and code 31"
  assert list.length(effects) == 1 as "nothing else is written or logged"
}

/// The log lines of the effects, each with its level.
fn logged(effects: List(Effect)) -> List(#(step.LogLevel, String)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Log(level:, text:) -> Ok(#(level, text))
      Send(..) -> Error(Nil)
    }
  })
}

pub fn gear_the_character_cannot_wear_is_refused_with_its_code_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each row: what it shows, the Item2 row put in inventory slot 1 (guid 9), the
  // equipped bag index it is moved to (its slot's bit in the ItemSlot of its
  // Item2Type: 12769 a primary weapon, bit 16; 1229 and 50770 a chest, bit 0;
  // 77689 a head, bit 2) and the code the client's CheckEquipRequirements
  // (0x1403b4710) gives the Engineer: 12769 is for class mask 64, 1229's
  // category needs proficiency 4, 50770 needs level 3 and 77689's prerequisite
  // is a loyalty. The codes are those of the first rows of
  // `equip_requirement_test.the_checks_run_in_the_clients_order_test`.
  let rows = [
    #("class", 12_769, 16, 40),
    #("proficiency", 1229, 0, 41),
    #("level", 50_770, 0, 42),
    #("a prerequisite the server does not read", 77_689, 2, 144),
  ]
  list.each(rows, fn(row) {
    let #(what, item2_id, bag_index, code) = row
    let result =
      taken(items: with_spare(item2_id), life: alive(), from: #(1, 1), to: #(
        0,
        bag_index,
      ))
    let assert Ok(Refused(effects:)) = result
      as { what <> ": refused, so the store is not asked and the items stay" }
    assert failed_with(effects) == [#(9, code)]
      as {
        what
        <> ": one 0x56A with the guid of the item at the source and the code"
      }
    // Only the prerequisite the server cannot read is logged: the client would
    // decide it.
    case code {
      144 -> {
        let assert [#(level, text)] = logged(effects)
          as "the refusal is logged once"
        assert level == step.LogWarning
        assert string.contains(text, "PrerequisiteType 270")
          as "the log names the condition type of prerequisite 39240, a loyalty"
      }
      _ -> {
        assert list.length(effects) == 1
          as { what <> ": nothing else is written or logged" }
      }
    }
  })
}

/// The fixture's tables with one row of a table gone and no requirement checked,
/// which the server's own load would refuse: the tables an equip check meets only
/// when the load is wrong.
fn tables_without(table table: String, id id: Int) -> table_store.Tables {
  let assert Ok(rows) =
    fixture_tables.remove(rows: fixture_tables.rows(), table:, id:)
    as "the fixture holds the row"
  let assert Ok(tables) =
    fixture_tables.edited(
      rows:,
      entries: server_table.entries(),
      requirements: [],
      derivations: derivation.all(),
    )
    as "the tables load with no requirement checked"
  tables
}

pub fn a_prerequisite_row_the_tables_lack_ends_the_move_and_the_log_names_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // 77689 is worn at the head slot (bag index 2) and names prerequisite 39240; the
  // tables here lack that row, which the load refuses, so the move ends as the
  // server's own state broken. The description names the row that is missing, not
  // the item's own row, which the tables hold.
  let assert Error(refusal) =
    inventory.take(
      items: with_spare(77_689),
      life: alive(),
      tables: tables_without(table: "Prerequisite", id: 39_240),
      wearer: equip_requirement_support.engineer(),
      bag_slots: 0,
      message: MoveAsked,
      body: move_body(from: #(1, 1), to: #(0, 2)),
    )
    as "a prerequisite the tables lack ends the move, it is not refused with a code"
  let description = inventory.describe(refusal:)
  assert string.contains(description, "Item2 77689")
    as "the description names the item"
  assert string.contains(description, "the table Prerequisite has no row 39240")
    as "and the table and the row the check could not read"
}

pub fn a_swap_checks_the_other_item_against_the_source_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  // 0x1403ad100 checks the item at the destination for the place the moved item
  // leaves. 1133 is a chest piece for class mask 4, and 1229 a chest piece
  // whose category needs proficiency 4, which the Engineer lacks: the unequip
  // of the Engineer's chest piece onto either is refused.
  let rows = [#("class", 1133, 40), #("proficiency", 1229, 41)]
  list.each(rows, fn(row) {
    let #(what, item2_id, code) = row
    let result =
      taken(
        items: worn_with_slot_zero(item2_id),
        life: alive(),
        from: #(0, 0),
        to: #(1, 0),
      )
    let assert Ok(Refused(effects:)) = result
      as { what <> ": refused, so the store is not asked and the items stay" }
    assert failed_with(effects) == [#(1, code)]
      as {
        what
        <> ": the guid of the worn chest piece, the item at the source, and the code"
      }
    assert list.length(effects) == 1
      as { what <> ": nothing else is written or logged" }
  })
}

/// The Engineer's worn items with a bag, 17814, worn at equipped slot 17 (guid
/// 20) and a second one in inventory slot 0 (guid 21).
fn with_two_bags() -> List(HeldItem) {
  let assert [_, ..] as worn =
    list.filter(held(), fn(item) { item.location == 0 })
  list.append(worn, [
    HeldItem(
      item_guid: 20,
      item2_id: Item2Id(17_814),
      location: 0,
      bag_index: 17,
      stack_count: 1,
    ),
    HeldItem(
      item_guid: 21,
      item2_id: Item2Id(17_814),
      location: 1,
      bag_index: 0,
      stack_count: 1,
    ),
  ])
}

pub fn a_second_unique_equipped_item_is_refused_unique_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 17814 has bindFlags 10, which holds bit 1, the unique-equipped bit
  // (Item2.bindFlags), and its slot flags 0x7FFE0000 are the bag slots 17 to 30.
  // 0x1403ad100: an item entering location 0 from outside is refused with
  // Item_Unique, 30, when an item of its Item2 is worn, before the slot fit
  // (bag slots 17 to 20 are closed, 31); a destination holding an item of the
  // same Item2 skips the unique test.
  let items = with_two_bags()
  let assert Ok(Refused(effects:)) =
    taken(items:, life: alive(), from: #(1, 0), to: #(0, 18))
    as "a second bag is refused"
  assert failed_with(effects) == [#(21, 30)]
  assert list.length(effects) == 1 as "nothing else is written or logged"
  let assert Ok(Refused(effects:)) =
    taken(items:, life: alive(), from: #(1, 0), to: #(0, 17))
    as "a bag onto its own copy is refused as a closed bag slot"
  assert failed_with(effects) == [#(21, 31)]
    as "the unique test is skipped for a destination of the same Item2, the slot fit follows"
}

pub fn gear_the_character_can_wear_is_equipped_test() -> Nil {
  use <- owned_test.run(10_000)
  // 0x1403b4710 passes: 50770 needs level 3, which the wearer has reached, and
  // 12918 has requiredLevel 36 with flags bit 0, which sets it to 1. Each takes
  // the place of the chest piece worn.
  let rows = [
    #(
      "level reached",
      50_770,
      Wearer(..equip_requirement_support.engineer(), level: 3),
    ),
    #("flags bit 0 sets level 1", 12_918, equip_requirement_support.engineer()),
  ]
  list.each(rows, fn(row) {
    let #(what, item2_id, wearer) = row
    let assert Ok(Asks(moving:)) =
      taken_by(
        wearer:,
        items: worn_with_slot_zero(item2_id),
        life: alive(),
        from: #(1, 0),
        to: #(0, 0),
      )
      as { what <> ": the move passes every check, so the store is asked" }
    assert moves_of(moving)
      == [
        ItemMove(item_guid: 9, from: ItemPlace(1, 0), to: ItemPlace(0, 0)),
        ItemMove(item_guid: 1, from: ItemPlace(0, 0), to: ItemPlace(1, 0)),
      ]
      as {
        what <> ": worn in place of the chest piece, which takes the bag slot"
      }
  })
}

// ---- worn bags ----

/// A wearer of level 18, which Item2 5423 needs.
fn bagger() -> Wearer {
  Wearer(..equip_requirement_support.engineer(), level: 18)
}

/// A move with BagSlots 4, the value Hybrid tier 1 gives (`reward_property`).
fn bagged(
  items items: List(HeldItem),
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Result(Taken, inventory.Refusal) {
  taken_with(wearer: bagger(), bag_slots: 4, items:, life: alive(), from:, to:)
}

/// The Engineer's seven worn items.
fn worn_set() -> List(HeldItem) {
  list.filter(held(), fn(item) { item.location == 0 })
}

/// A bag of the Item2 worn at an equipped slot.
fn worn_bag(
  guid guid: Int,
  item2_id item2_id: Int,
  slot slot: Int,
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2_id),
    location: 0,
    bag_index: slot,
    stack_count: 1,
  )
}

/// One item of Item2 1039 in each inventory index, guid 200 plus the index.
fn fillers(indexes indexes: List(Int)) -> List(HeldItem) {
  list.map(indexes, fn(index) {
    in_bag(guid: 200 + index, item2_id: stackable(), index:, count: 1)
  })
}

/// The inventory indexes from `first` to `last`.
fn indexes(first first: Int, to last: Int) -> List(Int) {
  int.range(from: last, to: first - 1, with: [], run: list.prepend)
}

fn size_of(items: List(HeldItem)) -> Int {
  let assert Ok(size) = inventory.size(items:, tables: fixture_tables.shared())
    as "every held item has its rows"
  size
}

/// The guid and code of the one 0x56A a refused move writes.
fn refusal(result: Result(Taken, inventory.Refusal)) -> List(#(Int, Int)) {
  let assert Ok(Refused(effects:)) = result
    as "the move is refused and answered with a 0x56A"
  assert list.length(effects) == 1 as "nothing else is written or logged"
  failed_with(effects)
}

/// The guid and place of each 0x569 the effects write.
fn moved_places(effects: List(Effect)) -> List(#(Int, Int)) {
  list.map(sent(effects), fn(frame) {
    assert frame.message_id == item_moved.message_id
      as "opcode.0x569: an item moved to an empty place"
    let assert Ok(ItemMoved(item_guid:, place:)) = item_moved.decode(frame.body)
    #(item_guid, place)
  })
}

/// The bag tests' expected values come from these places.
/// - `player.inventory_capacity` and 0x1403d2e10: the inventory holds 16 slots
///   and the size of each bag worn at equipped 17 to 20, a bag's size being the
///   Item2's maxStackCount (`Item2.bags`): 4753 holds 4, 5423 holds 8 and needs
///   level 18, 4763 is a proxy and so no bag (`0x1404445d0.proxy`).
/// - 0x1403aecd0: a bag worn at 17 to 20 that goes anywhere else is refused
///   with 35 Item_BagMustBeEmpty when its size less the size of the bag that
///   takes its place (0 for none) is above 0 and the empty slots among the usable
///   ones are no more than that, counted before the move.
/// - 0x1403ad100.reverse: a swap runs the same check for the item at the
///   destination going to the source place.
/// - 0x1403b11b0: location 0 at 17 + n is refused with 31 when n is at or past
///   BagSlots (the value 0x92C gave), and for an item whose slot flags lack the
///   slot's bit, so a non-bag and a proxy are refused at every bag slot.
/// - 0x1403aecd0.index and the server's rule: an inventory index at or past the
///   usable size is refused with 37.
/// - The server's choices, where the client's rule gives none: the items past a
///   shrunk inventory go to the lowest free slots in index order (a 0x569 each,
///   before the bag's answer), a bag dropped at or past the new size is refused
///   with 38 (CantPutBagInItself) and a worn bag cannot be deleted (1 Params),
///   as the client never sends it (0x1403c1360).
pub fn a_bag_worn_in_a_bag_slot_opens_its_slots_test() -> Nil {
  use <- owned_test.run(10_000)
  let big = fixture_tables.root("Item2", 5423)
  let small = fixture_tables.root("Item2", 4753)
  let items =
    list.append(held(), [
      in_bag(guid: 20, item2_id: big, index: 1, count: 1),
      in_bag(guid: 21, item2_id: small, index: 2, count: 1),
    ])
  assert size_of(items) == 16 as "no bag is worn"
  list.each([17, 18, 19, 20], fn(slot) {
    let moving = asked(bagged(items:, from: #(1, 2), to: #(0, slot)))
    assert moves_of(moving)
      == [
        ItemMove(item_guid: 21, from: ItemPlace(1, 2), to: ItemPlace(0, slot)),
      ]
      as "a bag goes into each of the four bag slots"
  })
  let moving = asked(bagged(items:, from: #(1, 1), to: #(0, 17)))
  assert moves_of(moving)
    == [ItemMove(item_guid: 20, from: ItemPlace(1, 1), to: ItemPlace(0, 17))]
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
      moves: moves_of(moving),
    ))
    as "the store is asked for the bag's move"
  let #(worn, effects) = inventory.answered(items:, moving:, answer: ItemsSaved)
  assert at(items: worn, guid: 20) == #(0, 17)
  assert moved_places(effects) == [#(20, 17)]
    as "opcode.0x569: the bag at location 0, index 17"
  assert size_of(worn) == 24 as "16 and the 8 slots of Item2 5423"
  // The room the bag opened takes a move: slots 16 to 23 exist, 24 does not.
  assert is_ask(bagged(items: worn, from: #(1, 0), to: #(1, 23)))
  assert refusal(bagged(items: worn, from: #(1, 0), to: #(1, 24))) == [#(8, 37)]
    as "an index at the size is past the last slot"
  // A second bag adds its slots to the first's.
  let moving = asked(bagged(items: worn, from: #(1, 2), to: #(0, 18)))
  let #(both, effects) =
    inventory.answered(items: worn, moving:, answer: ItemsSaved)
  assert moved_places(effects) == [#(21, 18)]
    as "opcode.0x569: the second bag at location 0, index 18"
  assert size_of(both) == 28 as "16, 8 and the 4 slots of Item2 4753"
  assert is_ask(bagged(items: both, from: #(1, 0), to: #(1, 27)))
  assert refusal(bagged(items: both, from: #(1, 0), to: #(1, 28))) == [#(8, 37)]
}

pub fn a_bag_slot_past_the_unlocked_count_is_refused_31_test() -> Nil {
  use <- owned_test.run(10_000)
  // 0x1403b11b0: equipped 17 + n with n at or past BagSlots is refused. The
  // client has 4 bag slots, so the count the rule is given is lowered to reach
  // the check.
  let small = fixture_tables.root("Item2", 4753)
  let items =
    list.append(held(), [in_bag(guid: 20, item2_id: small, index: 1, count: 1)])
  let with_slots = fn(slots, slot) {
    taken_with(
      wearer: bagger(),
      bag_slots: slots,
      items:,
      life: alive(),
      from: #(1, 1),
      to: #(0, slot),
    )
  }
  assert is_ask(with_slots(2, 18)) as "n = 1 is below BagSlots 2"
  assert refusal(with_slots(2, 19)) == [#(20, 31)] as "n = 2 is at BagSlots 2"
  assert refusal(with_slots(0, 17)) == [#(20, 31)]
    as "no 0x92C: BagSlots is 0, so no bag can be worn"
  assert is_ask(with_slots(4, 20)) as "n = 3 is below BagSlots 4"
}

pub fn only_a_bag_goes_in_a_bag_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  let small = fixture_tables.root("Item2", 4753)
  let proxy = fixture_tables.root("Item2", 4763)
  let items =
    list.append(held(), [
      in_bag(guid: 20, item2_id: small, index: 1, count: 1),
      in_bag(guid: 21, item2_id: proxy, index: 2, count: 1),
      worn_bag(guid: 22, item2_id: small, slot: 17),
    ])
  assert is_ask(bagged(items:, from: #(1, 1), to: #(0, 18)))
    as "a bag goes into a free bag slot"
  assert refusal(bagged(items:, from: #(1, 0), to: #(0, 18))) == [#(8, 31)]
    as "a chest piece has no bag slot bit"
  assert refusal(bagged(items:, from: #(1, 2), to: #(0, 18))) == [#(21, 31)]
    as "0x1404445d0.proxy: a proxy has no slot flags, whatever its row says"
  assert refusal(bagged(items:, from: #(0, 17), to: #(0, 3))) == [#(22, 31)]
    as "a bag does not go into a gear slot"
  assert refusal(bagged(items:, from: #(1, 1), to: #(0, 21))) == [#(20, 2)]
    as "equipped 21 is a bank bag slot, and the bank is closed"
}

pub fn a_bag_whose_items_would_not_fit_is_refused_35_test() -> Nil {
  use <- owned_test.run(10_000)
  let big = fixture_tables.root("Item2", 5423)
  let small = fixture_tables.root("Item2", 4753)
  let bag_8 = worn_bag(guid: 20, item2_id: big, slot: 17)
  // Size 24 with the bag worn. Taking it off needs more than its 8 slots empty
  // among the 24: 16 held leave 8, 15 held leave 9.
  let off = fn(held_slots) {
    bagged(
      items: list.flatten([worn_set(), [bag_8], fillers(indexes: held_slots)]),
      from: #(0, 17),
      to: #(1, 15),
    )
  }
  assert refusal(off(list.append(indexes(first: 0, to: 14), [17])))
    == [#(20, 35)]
    as "8 empty slots are not more than the bag's 8"
  assert is_ask(off(indexes(first: 0, to: 14)))
    as "9 empty slots are more than 8"
  // A swap with a smaller bag: 8 less 4 is 4, counted for the bag that goes.
  let swapped = fn(held_slots) {
    bagged(
      items: list.flatten([
        worn_set(),
        [bag_8, in_bag(guid: 21, item2_id: small, index: 0, count: 1)],
        fillers(indexes: held_slots),
      ]),
      from: #(1, 0),
      to: #(0, 17),
    )
  }
  assert refusal(swapped(indexes(first: 1, to: 19))) == [#(21, 35)]
    as "0x1403ad100.reverse: 4 empty slots are not more than 4"
  assert is_ask(swapped(indexes(first: 1, to: 18)))
    as "5 empty slots are more than 4"
  // Between two bag slots nothing leaves the bags, so a full inventory does not
  // matter.
  assert is_ask(
    bagged(
      items: list.flatten([
        worn_set(),
        [bag_8],
        fillers(indexes: indexes(first: 0, to: 23)),
      ]),
      from: #(0, 17),
      to: #(0, 18),
    ),
  )
    as "a bag moved to another bag slot keeps its slots"
  // In combat the bag slots are as locked as every equipped slot.
  assert refusal(
      taken_with(
        wearer: bagger(),
        bag_slots: 4,
        items: list.append(worn_set(), [bag_8]),
        life: fighting(),
        from: #(0, 17),
        to: #(1, 15),
      ),
    )
    == [#(20, 63)]
}

pub fn items_past_a_shrunk_inventory_move_to_free_slots_test() -> Nil {
  use <- owned_test.run(10_000)
  let big = fixture_tables.root("Item2", 5423)
  // Size 24: items at 20, 21 and 23 are past the 16 slots left once the bag is
  // off. Slots 0, 1, 2, 4, 6 and 8 are held; 3 is where the bag goes.
  let items =
    list.flatten([
      worn_set(),
      [worn_bag(guid: 20, item2_id: big, slot: 17)],
      fillers(indexes: [0, 1, 2, 4, 6, 8, 20, 21, 23]),
    ])
  let moving = asked(bagged(items:, from: #(0, 17), to: #(1, 3)))
  assert moves_of(moving)
    == [
      ItemMove(item_guid: 20, from: ItemPlace(0, 17), to: ItemPlace(1, 3)),
      ItemMove(item_guid: 220, from: ItemPlace(1, 20), to: ItemPlace(1, 5)),
      ItemMove(item_guid: 221, from: ItemPlace(1, 21), to: ItemPlace(1, 7)),
      ItemMove(item_guid: 223, from: ItemPlace(1, 23), to: ItemPlace(1, 9)),
    ]
    as "the bag, then each item past the new end, in index order, to the lowest free slot but the bag's own"
  let #(moved, effects) =
    inventory.answered(items:, moving:, answer: ItemsSaved)
  assert moved_places(effects)
    == [#(220, 261), #(221, 263), #(223, 265), #(20, 259)]
    as "opcode.0x569: each displaced item's new place, then the bag's, 1 * 256 + the index"
  assert at(items: moved, guid: 220) == #(1, 5)
  assert at(items: moved, guid: 221) == #(1, 7)
  assert at(items: moved, guid: 223) == #(1, 9)
  assert at(items: moved, guid: 20) == #(1, 3)
  assert size_of(moved) == 16
  assert list.length(moved) == list.length(items) as "no item is lost"
  let #(unchanged, effects) =
    inventory.answered(items:, moving:, answer: ItemsNotSaved)
  assert unchanged == items as "a save the store did not make leaves every item"
  assert failed_with(effects) == [#(20, 5)]
}

pub fn a_bag_dropped_into_its_own_slots_is_refused_38_test() -> Nil {
  use <- owned_test.run(10_000)
  let big = fixture_tables.root("Item2", 5423)
  let items =
    list.flatten([
      worn_set(),
      [worn_bag(guid: 20, item2_id: big, slot: 17)],
      fillers(indexes: indexes(first: 0, to: 14)),
    ])
  assert refusal(bagged(items:, from: #(0, 17), to: #(1, 20))) == [#(20, 38)]
    as "slot 20 is one of the slots the bag opens, and is gone once it is off"
  assert is_ask(bagged(items:, from: #(0, 17), to: #(1, 15)))
    as "slot 15 stays when the bag is off"
}

pub fn a_worn_bag_cannot_be_deleted_test() -> Nil {
  use <- owned_test.run(10_000)
  let big = fixture_tables.root("Item2", 5423)
  let items =
    list.append(worn_set(), [worn_bag(guid: 20, item2_id: big, slot: 17)])
  let assert Ok(Refused(effects:)) = delete_taken(items:, at: #(0, 17))
    as "a worn bag is refused"
  assert failed_with(effects) == [#(0, 1)]
    as "0x1403c1360: the client sends no delete of a worn bag, so it is Params with no guid, as for any place the client does not send"
  // A split onto the room the worn bag opened: slots 16 to 23 exist, 24 does
  // not.
  let stacked =
    list.append(items, [
      in_bag(guid: 22, item2_id: stackable(), index: 3, count: 10),
    ])
  let moving =
    asked(split_taken(
      items: stacked,
      life: alive(),
      guid: 22,
      to: #(1, 23),
      count: 3,
    ))
  assert moving.guid == 22
  let #(_, effects) =
    inventory.answered(items: stacked, moving:, answer: ItemMade(item_guid: 77))
  let assert [_, added] = sent(effects)
    as "opcode.0x17f of the source then opcode.0x111 of the new stack"
  let assert Ok(item_added.ItemAdded(held_item:)) =
    item_added.decode(added.body)
  assert #(
      held_item.item.item_guid,
      held_item.item.location,
      held_item.item.bag_index,
    )
    == #(77, 1, 23)
    as "opcode.0x111: the new stack is at inventory index 23"
  assert refusal(split_taken(
      items: stacked,
      life: alive(),
      guid: 22,
      to: #(1, 24),
      count: 3,
    ))
    == [#(22, 37)]
    as "a split onto an index at the size is refused"
}

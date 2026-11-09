//// The player's moves of held items: the client's 0x182, which a drag in the bags
//// or the character window sends, a feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in
//// the world.
////
//// ```
//// 0x182 {from, to} ─▶ take(items, life, tables, message, body)
////                      ├─ refused ─▶ Refused([Send(0x56A guid, code)])       no ask, items unchanged
////                      └─ accepted ─▶ Asks(moving) ─▶ the connection asks the store (request(moving, ..))
////                                                     and waits in MovingItem, frames held
//// the store's answer ─▶ answered(items, moving, answer) ─▶ ItemsMoved:    0x569 or 0x568, items updated
////                                                         NothingMoved:   Note, 0x56A code 5, items unchanged
////                                                         MoveRefused(c): Fault naming c, 0x56A code 5
//// ```
////
//// - **A move is one message.** A move, a swap, an equip and an unequip are all
////   0x182: from {location 9 bits, bag index 32} to {location 9, bag index 32};
////   a swap is a move onto an occupied slot (`opcode.0x182`). The client sends
////   one at a time and refuses the others with PlayerBusy until 0x569, 0x568,
////   0x56A or 0x17F clears its wait (`opcode.0x182`).
//// - **The replies.** An empty destination is answered 0x569, the item's guid and
////   its new place as one 64-bit value, bag index in bits 0 to 7 and location in
////   bits 8 to 15 (`opcode.0x569`). An occupied destination is answered 0x568,
////   two {guid, place} pairs: the moved item at the destination and the other
////   item at the source (`opcode.0x568`). A refusal is 0x56A, a guid the client
////   does not read and a GenericError code (`opcode.0x56a`).
//// - **The guid is the item's identity** and stays with it when it moves
////   (`opcode.0x111.guid`).
//// - **The check order** is the client's (`opcode.0x182`, `0x1403ad100`,
////   `0x1403aecd0`, `0x1403b11b0`), so a refusal's code is the one the client
////   would show:
////   1. the player is dead: 57 Player_CantDoWhileDead
////   2. the destination location is 100 to 299: 32 Item_Locked
////   3. no held item at the source: 1 Params
////   4. the same slot, a destination location of 300 or more, an equipped index
////      above 30 or an inventory index of 96 or more: 1 Params
////   5. in combat with either side equipped: 63 Player_CannotWhileInCombat
////   6. either side the bank, a bank bag slot (equipped 21 to 30) or location 10,
////      which the server never opens: 2 PlayerBusy
////   7. an inventory destination index of 16 or more, the usable size with no
////      bags worn: 37 Item_BagToSmall
////   8. an item entering location 0 at a slot whose bit is not in its equipped
////      slot flags (`item_property.equipped_slot_flags`), or at bag slot 17 to 20:
////      31 Item_NotValidforSlot; for both items of a swap when the source is
////      equipped
////   9. any other location the server keeps no items at (3 to 99 except 10): 1
////      Params, a server choice
//// - **The store's answer** decides the reply, so storage and the client agree
////   after it: `NothingMoved` and `MoveRefused` leave `items` as they were and
////   answer 0x56A code 5 DbFailure, and the connection stays. A store that is
////   unavailable, not running or past its deadline ends the connection with
////   reason 8, which the connection decides.
//// - **Left to other steps:** gear properties, max health, worn visuals and the
////   cast's weapon, which still read the fixed loadout, not the held items.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/player_life.{type Life}
import genesis_prime/step.{type LogLevel}
import genesis_prime/store.{
  type AccountId, type CharacterId, type HeldItem, type ItemMove,
  type ItemsAnswer, type SessionEpoch,
}
import genesis_prime/table/loader/store as table_store

/// The inventory message of the player in the world, which the client sends
/// inside 0x038C (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x0182, the player moves an item to a place.
  MoveAsked
}

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a frame to the player's client.
  Send(frame: Frame)
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// A move the rule accepted and the store is asked for: `moves` is one move, or
/// two for a swap, `items` the held items as they stand once the store has
/// moved them, and `moved` the frame (0x569 or 0x568) the client is answered
/// with then. `guid` is the moved item's, which a refusal's 0x56A names.
pub type Moving {
  Moving(guid: Int, moves: List(ItemMove), items: List(HeldItem), moved: Frame)
}

/// What the rule makes of a move the client sent.
pub type Taken {
  /// The move breaks a check: the effects answer it, no ask is made and the
  /// items are unchanged.
  Refused(effects: List(Effect))
  /// The move passes every check: the store is asked for it.
  Asks(moving: Moving)
}

/// Why the move is refused without an answer: the client's own code never sends
/// it. The connection ends.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
}

/// What the client's 0x0182 is answered with: a refusal with the code of the
/// first check it breaks, or the store's ask, or the refusal for a body the
/// client's reader refuses.
pub fn take(
  items _items: List(HeldItem),
  life _life: Life,
  tables _tables: table_store.Tables,
  message _message: Message,
  body _body: BitArray,
) -> Result(Taken, Refusal) {
  panic as "shape: #579 take is filled by the check order and the 0x569 or 0x568 it builds"
}

/// The store's request for an accepted move, fenced by the login's epoch.
pub fn request(
  moving _moving: Moving,
  account_id _account_id: AccountId,
  character_id _character_id: CharacterId,
  session_epoch _session_epoch: SessionEpoch,
) -> store.Request {
  panic as "shape: #579 request is filled by store.Items(MoveItems(..))"
}

/// The held items and the effects the store's answer to the move leaves: the
/// items of `moving` and its 0x569 or 0x568 for `ItemsMoved`, and the items as
/// they were with a log line and 0x56A code 5 for any other answer.
pub fn answered(
  items _items: List(HeldItem),
  moving _moving: Moving,
  answer _answer: ItemsAnswer,
) -> #(List(HeldItem), List(Effect)) {
  panic as "shape: #579 answered is filled by the 0x569, 0x568 and 0x56A of each answer"
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  let NotDecoded(undecoded:) = refusal
  client_connection.describe_undecoded(undecoded:)
}

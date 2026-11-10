//// The player's request to talk to a unit: the client's 0x07EA, which it sends when
//// the player right-clicks a quest giver, and the client's 0x0356, a feature of the
//// game connection's rule (genesis_prime/game/connection) taken from inside 0x038C
//// with the player in the world.
////
//// ```
//// 0x7EA {unit, 37}, inside 0x38C ─▶ take(Requested, ...) ─▶ a shown, alive creature whose row gives or
////                                                           receives a quest the client would show, within
////                                                           reach: OpenDialog(unit)
////                                                        ─▶ any other: a log line, nothing written
//// 0x7EA {unit, 0x31}             ─▶ a shown, alive creature of the vendor table, within reach and not
////                                   Hostile: OpenVendor(unit, vendor)
////                                ─▶ any other: RefuseVendor(unit, the client's code) and a log line
//// 0x7EA {0, 0x65}                ─▶ nothing: the client's own end of an interaction
//// 0x356 {}                       ─▶ nothing: the client shows a dialog with more than one response
//// ```
////
//// - **0x0357 alone opens the dialog** (`opcode.0x357`): a click sends the request
////   and nothing opens until the server answers. The client builds the responses
////   from its own quest state, and sends 0x0356 when there is more than one
////   (`opcode.0x356`), which needs no answer.
//// - **The client sends the request** only for a creature that is alive, not Hostile
////   to the player and one that marks a quest interaction kind with a click handler
////   (`0x14047a060`, `0x1405a8d40`), so a unit that is not shown, not a creature, dead,
////   Hostile, with no quest in its row or with none the player's log shows is one the
////   client would not have sent: it is logged and answered with nothing. The connection
////   goes on, since the picture is one news message stale at worst
////   (genesis_prime/game/shown).
//// - **The reach** is 6.0 for a quest kind, measured between the two bodies' edges
////   (`0x1403ad690`), plus the 3.0 a request may add (`opcode.0x7ea`). The gap here
////   is on the ground, with the hit radii at scale 1.0, from the player's place at
////   its last movement message; the 3.0 covers both for any gap the client opens at.
//// - **A quest to show** is what the client marks for the creature from the player's quest
////   log (`0x1405a8d40`), which `offers` says for the creature's row: a creature with
////   nothing to show gets no request, and one whose quest the server cannot decide for a
////   table row it lacks is logged and gets no dialog. The rule is
////   genesis_prime/game/quest's (`offers`), which imports this module, so the connection
////   passes it in; the checks the client's accept makes of the log are its too. The
////   client marks the creature before any click, so the order of this check and the
////   reach changes only the reason that is logged.
//// - **A creature an objective names** is marked with the talk kind while an open type 3
////   objective of the player's log names its Creature2 id (`0x140553110`), whatever its
////   row gives, so the client sends the request for it. `take` answers it with the dialog
////   and then `TalkedTo`, which the connection counts (genesis_prime/game/objective); a
////   creature that also offers a quest opens one dialog. Its dead, Hostile and reach checks
////   are the same.
//// - **A vendor's request** (kind 0x31) is checked as the client's CheckInteractionTarget
////   checks it (`opcode.0x7ea`), in its order: a unit not in the picture is 59, a unit that is
////   not a creature, a creature with no stock or a dead one is 16, a gap over the reach is
////   17, and a creature Hostile to the player is 62. The client sends none of these, so each
////   is answered as the client would be: 0x106 with the code, then a 0x90b that opens and
////   refuses, which ends the interaction (`opcode.0x90b`), and the log line says why. The
////   control states (60 and 61) and the combat checks are left to the client, so the server
////   opens the window for a vendor whose player is stunned; that gap and the contents of
////   buying, selling and buyback, which stay empty, are the vendor trading step's (#583).
//// - **The vendor window ends with any 0x07EA but the one that opens a vendor**: the
////   client sets its interaction kind and closes the previous interaction's window before
////   it sends any 0x07EA, its own end (unit 0, kind 0x65) among them, and it sends 0x00BE only
////   while its kind is 0x31 (`opcode.0x7ea`, `opcode.0xbe`). Each result of `take` says whether the
////   window opens, closes or stays: 0x0356 keeps it, and a refused or unhandled 0x07EA closes it.
//// - **A kind no step takes** is logged, not answered: any kind but 37 and 0x31 waits for a
////   step of its own.
//// - **A log line** is a warning the first time its reason is met on the connection
////   and a debug line after, so a client that repeats a click is not a flood.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/game/area
import genesis_prime/game/hit_radius
import genesis_prime/game/shown.{
  type Picture, type PlayerFaction, ShownCreature, ShownObject, ShownPlayer,
}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/vendor.{type Vendor, type Vendors}
import genesis_prime/message/dialog_responses_shown
import genesis_prime/message/interaction_request
import genesis_prime/step.{type LogLevel, LogDebug, LogWarning}
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/id.{type Creature2Id, type RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{type Hostile}
import genesis_prime/world_map/creature_path.{type Path}
import genesis_prime/world_map/spawn
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}

/// The interaction messages of the player in the world, which the client sends
/// inside 0x038C (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x07EA, the player's request to talk to a unit, or to end the interaction.
  Requested
  /// 0x0356, the client shows a dialog with more than one response.
  ResponsesShown
}

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a log line.
  Log(level: LogLevel, text: String)
  /// Write 0x0357, which opens the unit's dialog.
  OpenDialog(unit_id: Int)
  /// The player talked to a creature that an open type 3 objective names: the connection
  /// counts the talk (genesis_prime/game/objective), after the dialog is opened.
  TalkedTo(creature_id: Int)
  /// Write 0x090B with the vendor's stock, which opens its window, then 0x00BC with no
  /// buyback entries.
  OpenVendor(unit_id: Int, vendor: Vendor)
  /// Write 0x0106 with the code the client's own check would have shown, then the 0x090B
  /// that refuses, which ends the interaction.
  RefuseVendor(unit_id: Int, code: Int)
}

/// Why the message is refused: a body the client's own reader would refuse. The
/// connection ends.
pub type Refusal {
  NotDecoded(undecoded: Undecoded)
}

/// The player a request is made by.
pub type Player {
  Player(race_id: RaceId, faction: PlayerFaction, place: Place)
}

/// What a message does to the vendor window the player has open, which a purchase
/// is made from (genesis_prime/game/vendor_purchase).
pub type Window {
  /// The vendor's window is open on this unit.
  Opens(opened: vendor.Opened)
  /// The player has no vendor window open.
  Closes
  /// The window is as it was.
  Keeps
}

/// The effects of a message, what it does to the vendor window and the reasons now
/// logged on the connection.
pub type Taken {
  Taken(effects: List(Effect), window: Window, logged: Set(String))
}

/// What a player's quest log says of a creature's quests, as the client marks the
/// creature (`0x1405a8d40`).
pub type Offer {
  /// A quest of the creature shows its dialog.
  Offered
  /// No quest of the creature shows its dialog.
  NothingToOffer
  /// No quest of the creature shows its dialog, and a check of one needed a table row
  /// the tables lack: the quest and a sentence that says which row.
  Undecided(quest_id: Int, cause: String)
}

/// Why a request is answered with nothing.
type Declined {
  NotShown(unit_id: Int)
  NotACreature(unit_id: Int)
  Dead(unit_id: Int)
  HostileToPlayer(unit_id: Int)
  NoQuest(unit_id: Int, creature_id: Creature2Id)
  NothingOffered(unit_id: Int, creature_id: Creature2Id)
  OfferUndecided(
    unit_id: Int,
    creature_id: Creature2Id,
    quest_id: Int,
    cause: String,
  )
  TooFar(unit_id: Int)
  KindNotTaken(kind: Int)
}

/// Why a vendor request is refused with the client's code: the unit, the code
/// (`opcode.0x7ea`), the reason that is logged once, and what to say of the unit.
pub type VendorRefusal {
  VendorRefusal(unit_id: Int, code: Int, reason: VendorReason, why: String)
}

/// The check a vendor request breaks, in the order of the client's
/// CheckInteractionTarget (`opcode.0x7ea`).
pub type VendorReason {
  VendorNotShown
  VendorNotACreature
  VendorNoStock
  VendorDead
  VendorTooFar
  VendorHostile
}

/// Whether the vendor's window is checked against the reach of a request.
pub type ReachCheck {
  /// The gap between the two edges is no more than the request's reach.
  CheckReach
  /// The request has a range of its own, which the caller checks.
  SkipReach
}

/// The words a reason is logged under, one key for each reason.
pub fn reason_key(reason reason: VendorReason) -> String {
  case reason {
    VendorNotShown -> "not shown"
    VendorNotACreature -> "not a creature"
    VendorNoStock -> "no stock"
    VendorDead -> "dead"
    VendorTooFar -> "too far"
    VendorHostile -> "hostile"
  }
}

/// The kind of a request to talk to a quest giver (`opcode.0x7ea`).
const talk_to = 37

/// The kind of a request to open a vendor's window (`opcode.0x7ea`).
const vendor_kind = 0x31

/// The kind, with unit 0, that ends an interaction (`opcode.0x7ea`).
const end = 0x65

/// Vendor_NoVendor, the client's code for a unit that is not in its picture.
const vendor_no_vendor = 59

/// Vendor_NotAVendor, the client's code for a unit that is not a creature of the
/// vendor table, or is dead.
const vendor_not_a_vendor = 16

/// Vendor_TooFar, the client's code for a vendor beyond the reach.
const vendor_too_far = 17

/// Vendor_Vendor_Disposition, the client's code for a vendor Hostile to the player.
const vendor_disposition = 62

/// The edge to edge gap a request is answered within: 6.0 for a quest kind
/// (`0x1403ad690`) and for the vendor kind (`0x140c48160`, entry 0x31), and the 3.0 a
/// request may add (`opcode.0x7ea`).
const reach = 9.0

/// What a message is answered with: the dialog's opening for a request to talk to a
/// giver within reach, a log line for one that is declined, nothing for the client's
/// own end and for 0x0356, and a refusal for a body the client's reader refuses.
pub fn take(
  message message: Message,
  body body: BitArray,
  player player: Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  vendors vendors: Vendors,
  now_ms now_ms: Int,
  offers offers: fn(Creature2) -> Offer,
  talk_targets talk_targets: Set(Int),
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  case message {
    ResponsesShown ->
      dialog_responses_shown.decode(body)
      |> client_connection.decoded(
        message_id: dialog_responses_shown.message_id,
      )
      |> result.map_error(NotDecoded)
      |> result.map(fn(_) { Taken(effects: [], window: Keeps, logged:) })
    Requested ->
      interaction_request.decode(body)
      |> client_connection.decoded(message_id: interaction_request.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) {
        case request.kind, request.unit_id {
          kind, _ if kind == talk_to ->
            case
              talked_to(
                unit_id: request.unit_id,
                player:,
                picture:,
                tables:,
                now_ms:,
                offers:,
                talk_targets:,
              )
            {
              Ok(creature_id) ->
                Taken(
                  effects: dialog_effects(
                    unit_id: request.unit_id,
                    creature_id:,
                    talk_targets:,
                  ),
                  window: Closes,
                  logged:,
                )
              Error(declined) -> declined_with(declined:, logged:)
            }
          kind, _ if kind == vendor_kind ->
            case
              vendor_opened(
                unit_id: request.unit_id,
                player:,
                picture:,
                tables:,
                vendors:,
                reach: CheckReach,
                now_ms:,
              )
            {
              Ok(opened) ->
                Taken(
                  effects: [
                    OpenVendor(unit_id: request.unit_id, vendor: opened),
                  ],
                  window: Opens(opened: vendor.Opened(
                    unit_id: request.unit_id,
                    vendor: opened,
                  )),
                  logged:,
                )
              Error(refusal) -> vendor_refused_with(refusal:, logged:)
            }
          kind, 0 if kind == end -> Taken(effects: [], window: Closes, logged:)
          kind, _ -> declined_with(declined: KindNotTaken(kind:), logged:)
        }
      })
  }
}

/// The dialog's opening, and the talk's count when an open type 3 objective names the
/// creature.
fn dialog_effects(
  unit_id unit_id: Int,
  creature_id creature_id: Creature2Id,
  talk_targets talk_targets: Set(Int),
) -> List(Effect) {
  case set.contains(talk_targets, creature_id.value) {
    True -> [OpenDialog(unit_id:), TalkedTo(creature_id: creature_id.value)]
    False -> [OpenDialog(unit_id:)]
  }
}

/// The creature whose dialog the player may open: the unit is a shown creature that is
/// alive, not Hostile to the player and within reach, and either one an open type 3
/// objective names (`talk_targets`, whatever its row gives), or one whose row gives or
/// receives a quest that `offers` says the player's log shows. A creature's Creature2 row
/// and the player's Race row are in the tables (the load fails otherwise), so a missing
/// one crashes.
fn talked_to(
  unit_id unit_id: Int,
  player player: Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
  offers offers: fn(Creature2) -> Offer,
  talk_targets talk_targets: Set(Int),
) -> Result(Creature2Id, Declined) {
  use shown <- result.try(
    dict.get(picture, unit_id) |> result.replace_error(NotShown(unit_id:)),
  )
  case shown {
    ShownPlayer | ShownObject(..) -> Error(NotACreature(unit_id:))
    ShownCreature(
      creature_id:,
      path:,
      alive:,
      hit_radius: creature_radius,
      hostile_to:,
      ..,
    ) -> {
      use <- bool.guard(when: !alive, return: Error(Dead(unit_id:)))
      use <- bool.guard(
        when: hostile_to_player(player:, hostile_to:),
        return: Error(HostileToPlayer(unit_id:)),
      )
      let assert Ok(row) = creature2.get(tables, creature_id)
        as "a shown creature's Creature2 row is in the tables its spawn was loaded from"
      let target = set.contains(talk_targets, creature_id.value)
      use <- bool.guard(
        when: !target && !list.any(spawn.quest_ids(row), fn(id) { id != 0 }),
        return: Error(NoQuest(unit_id:, creature_id:)),
      )
      use <- bool.guard(
        when: !within_reach(player:, tables:, path:, creature_radius:, now_ms:),
        return: Error(TooFar(unit_id:)),
      )
      use <- bool.guard(when: target, return: Ok(creature_id))
      case offers(row) {
        Offered -> Ok(creature_id)
        NothingToOffer -> Error(NothingOffered(unit_id:, creature_id:))
        Undecided(quest_id:, cause:) ->
          Error(OfferUndecided(unit_id:, creature_id:, quest_id:, cause:))
      }
    }
  }
}

/// Whether the creature is Hostile to the player's faction, as the client's own
/// disposition of the creature toward the player gives it (`0x14045a950`).
pub fn hostile_to_player(
  player player: Player,
  hostile_to hostile_to: Hostile,
) -> Bool {
  case player.faction {
    shown.Exile -> hostile_to.exile
    shown.Dominion -> hostile_to.dominion
  }
}

/// Whether the creature, at its place now, is within reach of the player: the gap
/// between the two bodies' edges is no more than the reach. The player's Race row is
/// in the tables (the load fails otherwise), so a missing one crashes.
pub fn within_reach(
  player player: Player,
  tables tables: table_store.Tables,
  path path: Path,
  creature_radius creature_radius: Float,
  now_ms now_ms: Int,
) -> Bool {
  within(player:, tables:, path:, creature_radius:, now_ms:, range: reach)
}

/// Whether the creature, at its place now, is within `range` of the player, the gap
/// counted between the two bodies' edges. The player's Race row is in the tables (the
/// load fails otherwise), so a missing one crashes.
pub fn within(
  player player: Player,
  tables tables: table_store.Tables,
  path path: Path,
  creature_radius creature_radius: Float,
  now_ms now_ms: Int,
  range range: Float,
) -> Bool {
  let assert Ok(player_radius) =
    hit_radius.of_player(tables:, race_id: player.race_id)
    as "hit_radius.requirements fails the load when a playable race has no Race row"
  let gap =
    area.edge_gap(
      from: area.point_of(place: player.place),
      from_radius: player_radius,
      to: area.point_of(place: creature_path.place_at(path:, now_ms:)),
      to_radius: creature_radius,
    )
  gap <=. range
}

/// The vendor whose window the player may open: the unit is a shown creature that is
/// alive and has stock, within reach and not Hostile to the player, checked in the order
/// of the client's CheckInteractionTarget (`opcode.0x7ea`), or the refusal the client's
/// check would have given. `reach` says whether the gap is checked: a trade with a range
/// of its own skips it.
pub fn vendor_opened(
  unit_id unit_id: Int,
  player player: Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  vendors vendors: Vendors,
  reach reach_check: ReachCheck,
  now_ms now_ms: Int,
) -> Result(Vendor, VendorRefusal) {
  use shown <- result.try(
    dict.get(picture, unit_id)
    |> result.replace_error(VendorRefusal(
      unit_id:,
      code: vendor_no_vendor,
      reason: VendorNotShown,
      why: "which is not shown in the player's picture",
    )),
  )
  case shown {
    ShownPlayer | ShownObject(..) ->
      Error(VendorRefusal(
        unit_id:,
        code: vendor_not_a_vendor,
        reason: VendorNotACreature,
        why: "which is not a creature",
      ))
    ShownCreature(
      creature_id:,
      path:,
      alive:,
      hit_radius: creature_radius,
      hostile_to:,
      ..,
    ) -> {
      use stock <- result.try(
        vendor.get(vendors:, creature_id:)
        |> result.replace_error(VendorRefusal(
          unit_id:,
          code: vendor_not_a_vendor,
          reason: VendorNoStock,
          why: "whose Creature2 row "
            <> int.to_string(creature_id.value)
            <> " has no stock",
        )),
      )
      use <- bool.guard(
        when: !alive,
        return: Error(VendorRefusal(
          unit_id:,
          code: vendor_not_a_vendor,
          reason: VendorDead,
          why: "a dead creature",
        )),
      )
      use <- bool.guard(
        when: reach_check == CheckReach
          && !within_reach(player:, tables:, path:, creature_radius:, now_ms:),
        return: Error(VendorRefusal(
          unit_id:,
          code: vendor_too_far,
          reason: VendorTooFar,
          why: "too far from the player: the client's reach is "
            <> float.to_string(reach)
            <> " between the two edges",
        )),
      )
      use <- bool.guard(
        when: hostile_to_player(player:, hostile_to:),
        return: Error(VendorRefusal(
          unit_id:,
          code: vendor_disposition,
          reason: VendorHostile,
          why: "a creature Hostile to the player",
        )),
      )
      Ok(stock)
    }
  }
}

/// The answer to a vendor request the client would have refused: the log line, then the
/// client's code and the refusing window. One warning for each reason, a debug line after.
fn vendor_refused_with(
  refusal refusal: VendorRefusal,
  logged logged: Set(String),
) -> Taken {
  let #(log, logged) =
    log_once(
      key: "vendor " <> reason_key(reason: refusal.reason),
      text: "0x07EA kind 0x31 names unit "
        <> int.to_string(refusal.unit_id)
        <> ", "
        <> refusal.why
        <> ": the client would refuse it with code "
        <> int.to_string(refusal.code)
        <> ", so the server sends that",
      logged:,
    )
  Taken(
    effects: [log, RefuseVendor(unit_id: refusal.unit_id, code: refusal.code)],
    window: Closes,
    logged:,
  )
}

/// The log line for a reason: a warning the first time the key is met on the
/// connection and a debug line after, with the keys met so far.
fn log_once(
  key key: String,
  text text: String,
  logged logged: Set(String),
) -> #(Effect, Set(String)) {
  let #(level, logged) = log_level(key:, logged:)
  #(Log(level:, text:), logged)
}

/// The level a reason is logged at: a warning the first time its key is met on the
/// connection and a debug line after, with the keys met so far.
pub fn log_level(
  key key: String,
  logged logged: Set(String),
) -> #(LogLevel, Set(String)) {
  let level = case set.contains(logged, key) {
    True -> LogDebug
    False -> LogWarning
  }
  #(level, set.insert(logged, key))
}

/// The log line of a declined request: a warning the first time its reason is met,
/// a debug line after.
fn declined_with(
  declined declined: Declined,
  logged logged: Set(String),
) -> Taken {
  let #(log, logged) =
    log_once(key: reason_of(declined:), text: describe(declined:), logged:)
  Taken(effects: [log], window: Closes, logged:)
}

/// The reason of a declined request, one for each kind of reason.
fn reason_of(declined declined: Declined) -> String {
  case declined {
    NotShown(..) -> "not shown"
    NotACreature(..) -> "not a creature"
    Dead(..) -> "dead"
    HostileToPlayer(..) -> "hostile"
    NoQuest(..) -> "no quest"
    NothingOffered(..) -> "nothing offered"
    OfferUndecided(..) -> "offer undecided"
    TooFar(..) -> "too far"
    KindNotTaken(kind:) -> "kind " <> int.to_string(kind)
  }
}

/// A sentence that says why the request is answered with nothing, for the log.
fn describe(declined declined: Declined) -> String {
  case declined {
    NotShown(unit_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", which is not shown in the player's picture: nothing is answered"
    NotACreature(unit_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", which is not a creature: only a creature opens a quest dialog"
    Dead(unit_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", a dead creature: the client sends no request for one"
    HostileToPlayer(unit_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", a creature Hostile to the player: the client sends no request for one"
    NoQuest(unit_id:, creature_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", whose Creature2 row "
      <> int.to_string(creature_id.value)
      <> " has no quest to give or receive: the client sends no request for it"
    NothingOffered(unit_id:, creature_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", whose Creature2 row "
      <> int.to_string(creature_id.value)
      <> " has no quest to show for the player's log: the client sends no request for it"
    OfferUndecided(unit_id:, creature_id:, quest_id:, cause:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", whose Creature2 row "
      <> int.to_string(creature_id.value)
      <> " has no quest to show unless quest "
      <> int.to_string(quest_id)
      <> " can be decided, which needs a row the tables lack ("
      <> cause
      <> "): nothing is answered"
    TooFar(unit_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", too far from the player: the client's reach is "
      <> float.to_string(reach)
      <> " between the two edges"
    KindNotTaken(kind:) ->
      "0x07EA kind "
      <> int.to_string(kind)
      <> " is taken by no step yet: nothing is answered"
  }
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe_refusal(refusal refusal: Refusal) -> String {
  let NotDecoded(undecoded:) = refusal
  client_connection.describe_undecoded(undecoded:)
}

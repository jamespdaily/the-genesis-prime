//// The player's request to talk to a unit: the client's 0x07EA, which it sends when
//// the player right-clicks a quest giver, and the client's 0x0356, a feature of the
//// game connection's rule (genesis_prime/game/connection) taken from inside 0x038C
//// with the player in the world.
////
//// ```
//// 0x7EA {unit, 37}, inside 0x38C ─▶ take(Requested, ...) ─▶ a shown, alive creature whose row gives or
////                                                           receives a quest, within reach: OpenDialog(unit)
////                                                        ─▶ any other: a log line, nothing written
//// 0x7EA {0, 0x65}                ─▶ nothing: the client's own end of an interaction
//// 0x356 {}                       ─▶ nothing: the client shows a dialog with more than one response
//// ```
////
//// - **0x0357 alone opens the dialog** (`opcode.0x357`): a click sends the request
////   and nothing opens until the server answers. The client builds the responses
////   from its own quest state, and sends 0x0356 when there is more than one
////   (`opcode.0x356`), which needs no answer.
//// - **The client sends the request** only for a creature that is alive, not Hostile
////   to the player and a quest giver (`0x14047a060`), so a unit that is not shown,
////   not a creature, dead, Hostile or with no quest in its row is one the client
////   would not have sent: it is logged and answered with nothing. The connection goes on, since the picture is
////   one news message stale at worst (genesis_prime/game/shown).
//// - **The reach** is 6.0 for a quest kind, measured between the two bodies' edges
////   (`0x1403ad690`), plus the 3.0 a request may add (`opcode.0x7ea`). The gap here
////   is on the ground, with the hit radii at scale 1.0, from the player's place at
////   its last movement message; the 3.0 covers both for any gap the client opens at.
//// - **The kind is not checked against the player's quest log**: the client opens the
////   dialog only for responses it builds from its own quest state, so the server's
////   0x0357 for a giver with nothing to offer shows no dialog. The log is the quest
////   log step's (#591).
//// - **A kind no step takes** is logged, not answered: 0x31 is a vendor (#582), and
////   any other waits for a step of its own.
//// - **A log line** is a warning the first time its reason is met on the connection
////   and a debug line after, so a client that repeats a click is not a flood.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/game/area
import genesis_prime/game/hit_radius
import genesis_prime/game/shown.{
  type Picture, type PlayerFaction, ShownCreature, ShownObject, ShownPlayer,
}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/dialog_responses_shown
import genesis_prime/message/interaction_request
import genesis_prime/step.{type LogLevel, LogDebug, LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{type Creature2Id, type RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_path
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

/// The effects of a message and the reasons now logged on the connection.
pub type Taken {
  Taken(effects: List(Effect), logged: Set(String))
}

/// Why a request is answered with nothing.
type Declined {
  NotShown(unit_id: Int)
  NotACreature(unit_id: Int)
  Dead(unit_id: Int)
  HostileToPlayer(unit_id: Int)
  NoQuest(unit_id: Int, creature_id: Creature2Id)
  TooFar(unit_id: Int)
  KindNotTaken(kind: Int)
}

/// The kind of a request to talk to a quest giver (`opcode.0x7ea`).
const talk_to = 37

/// The kind, with unit 0, that ends an interaction (`opcode.0x7ea`).
const end = 0x65

/// The edge to edge gap a request is answered within: 6.0 for a quest kind
/// (`0x1403ad690`) and the 3.0 a request may add (`opcode.0x7ea`).
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
  now_ms now_ms: Int,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  case message {
    ResponsesShown ->
      dialog_responses_shown.decode(body)
      |> client_connection.decoded(
        message_id: dialog_responses_shown.message_id,
      )
      |> result.map_error(NotDecoded)
      |> result.map(fn(_) { Taken(effects: [], logged:) })
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
              )
            {
              Ok(Nil) ->
                Taken(effects: [OpenDialog(unit_id: request.unit_id)], logged:)
              Error(declined) -> declined_with(declined:, logged:)
            }
          kind, 0 if kind == end -> Taken(effects: [], logged:)
          kind, _ -> declined_with(declined: KindNotTaken(kind:), logged:)
        }
      })
  }
}

/// Whether the player may open the unit's dialog: the unit is a shown creature that is
/// alive, not Hostile to the player, whose row gives or receives a quest, within
/// reach. A creature's Creature2 row and the player's Race row are in the tables
/// (the load fails otherwise), so a missing one crashes.
fn talked_to(
  unit_id unit_id: Int,
  player player: Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> Result(Nil, Declined) {
  use shown <- result.try(
    dict.get(picture, unit_id) |> result.replace_error(NotShown(unit_id:)),
  )
  case shown {
    ShownPlayer | ShownObject -> Error(NotACreature(unit_id:))
    ShownCreature(
      creature_id:,
      path:,
      alive:,
      hit_radius: creature_radius,
      hostile_to:,
      ..,
    ) -> {
      use <- bool.guard(when: !alive, return: Error(Dead(unit_id:)))
      let hostile = case player.faction {
        shown.Exile -> hostile_to.exile
        shown.Dominion -> hostile_to.dominion
      }
      use <- bool.guard(when: hostile, return: Error(HostileToPlayer(unit_id:)))
      let assert Ok(row) = creature2.get(tables, creature_id)
        as "a shown creature's Creature2 row is in the tables its spawn was loaded from"
      use <- bool.guard(
        when: !list.any(spawn.quest_ids(row), fn(id) { id != 0 }),
        return: Error(NoQuest(unit_id:, creature_id:)),
      )
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
      case gap >. reach {
        True -> Error(TooFar(unit_id:))
        False -> Ok(Nil)
      }
    }
  }
}

/// The log line of a declined request: a warning the first time its reason is met,
/// a debug line after.
fn declined_with(
  declined declined: Declined,
  logged logged: Set(String),
) -> Taken {
  let key = reason_of(declined:)
  let level = case set.contains(logged, key) {
    True -> LogDebug
    False -> LogWarning
  }
  Taken(
    effects: [Log(level:, text: describe(declined:))],
    logged: set.insert(logged, key),
  )
}

/// The reason of a declined request, one for each kind of reason.
fn reason_of(declined declined: Declined) -> String {
  case declined {
    NotShown(..) -> "not shown"
    NotACreature(..) -> "not a creature"
    Dead(..) -> "dead"
    HostileToPlayer(..) -> "hostile"
    NoQuest(..) -> "no quest"
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
    TooFar(unit_id:) ->
      "0x07EA names unit "
      <> int.to_string(unit_id)
      <> ", too far from the player: the client's reach is "
      <> float.to_string(reach)
      <> " between the two edges"
    KindNotTaken(kind: 0x31) ->
      "0x07EA kind 0x31 is a vendor, which waits for the vendor step (#582): nothing is answered"
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

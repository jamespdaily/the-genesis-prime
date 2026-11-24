//// The names of the news a creature sends a viewer, by the client frame each becomes, for the
//// tests that read what a viewer was sent.

import genesis_prime/client_connection.{
  type Message, type News, CastFinished, CastStarted, CastWent, CombatState,
  CreatureAppeared, CreatureMoved, CreaturePlaced, ForStay, Health, PeerNews,
  SentByPeer, Targeting, Threat,
}
import genesis_prime/world_map/creature_turn
import gleam/int
import gleam/list

/// The name of one news: the opcode of the frame the viewer's connection writes for it, with
/// the values the tests tell apart.
pub fn name_of(news: News) -> String {
  case news {
    Targeting(target_unit_id:, threat:) ->
      "0x908("
      <> int.to_string(target_unit_id)
      <> ", "
      <> int.to_string(threat)
      <> ")"
    Threat(other_unit_id:, threat:) ->
      "0x90a("
      <> int.to_string(other_unit_id)
      <> ", "
      <> int.to_string(threat)
      <> ")"
    CombatState(in_combat: True) -> "0x89a(1)"
    CombatState(in_combat: False) -> "0x89a(0)"
    CreatureMoved(..) -> "0x638"
    CreaturePlaced(..) -> "0x638(placed)"
    client_connection.CreatureFaces(face: creature_turn.Unit(unit_id:), ..) ->
      "turn(kind 18, unit " <> int.to_string(unit_id) <> ")"
    client_connection.CreatureFaces(face: creature_turn.Point(..), ..) ->
      "turn(kind 19, home)"
    client_connection.CreatureFaces(face: creature_turn.Fixed(..), ..) ->
      "turn(kind 14)"
    client_connection.CreatureFaces(face: creature_turn.Home(..), ..) ->
      "turn(kind 19, spawn facing)"
    CastStarted(..) -> "0x7ff"
    CastWent(..) -> "0x7f4"
    client_connection.CastMissed(..) -> "0x7fb"
    client_connection.CastTicked(..) -> "0x7f8"
    CastFinished(..) -> "0x7fe"
    client_connection.CastInterrupted(..) -> "0x7f9"
    client_connection.CastTargetsRemoved(..) -> "0x811"
    Health(health:, ..) -> "0x937(" <> int.to_string(health) <> ")"
    client_connection.Died -> "0x88c"
    CreatureAppeared(..) -> "0x262"
    client_connection.Removed -> "0x355"
    client_connection.CrowdControlApplied(..) -> "0x87f"
    client_connection.CrowdControlEnded(..) -> "0x880"
    client_connection.InterruptArmor(armor:) ->
      "0x938(21, " <> int.to_string(armor) <> ")"
    client_connection.Absorption(absorption:) ->
      "0x938(22, " <> int.to_string(absorption) <> ")"
    client_connection.Level(level:) ->
      "0x938(10, " <> int.to_string(level) <> ")"
    _ -> "other"
  }
}

/// A function that takes the news a viewer was sent from a message and names it when its name
/// is one of `names`, so a test lists the frames it asserts on and no others.
pub fn named_among(
  names names: List(String),
) -> fn(Message) -> Result(String, Nil) {
  fn(message) {
    case message {
      ForStay(sent: SentByPeer(PeerNews(news:, ..)), ..) -> {
        let name = name_of(news)
        case list.contains(names, name) {
          True -> Ok(name)
          False -> Error(Nil)
        }
      }
      ForStay(..)
      | client_connection.SentBySessions(..)
      | client_connection.SentByChat(..) -> Error(Nil)
    }
  }
}

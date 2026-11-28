//// The names of the news a creature sends a viewer, by the client frame each becomes, for the
//// tests that read what a viewer was sent.

import connection_rule_support as support
import genesis_prime/client_connection.{type Message, ForStay, SentByPeer}
import genesis_prime/map/message as map_message
import genesis_prime/shared/creature_turn
import genesis_prime/shared/strike_tell.{
  Answered, Attacks, Landed, Refused, Released, Threatened,
}
import genesis_prime/shared/unit_news.{
  type News, CastFinished, CastStarted, CastWent, CombatState, CreatureAppeared,
  CreatureMoved, CreaturePlaced, Health, PeerNews, Targeting, Threat,
}
import genesis_prime/step.{
  type ConnectionId, type ServiceStep, Connection, ConnectionId, Effects,
  OwnEffect, Send, Stop,
}
import genesis_prime/world_map/creature
import genesis_prime/world_map/generation
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/int
import gleam/list
import map_support

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
    unit_news.CreatureFaces(face: creature_turn.Unit(unit_id:), ..) ->
      "turn(kind 18, unit " <> int.to_string(unit_id) <> ")"
    unit_news.CreatureFaces(face: creature_turn.Point(..), ..) ->
      "turn(kind 19, home)"
    unit_news.CreatureFaces(face: creature_turn.Fixed(..), ..) ->
      "turn(kind 14)"
    unit_news.CreatureFaces(face: creature_turn.Home(..), ..) ->
      "turn(kind 19, spawn facing)"
    CastStarted(..) -> "0x7ff"
    CastWent(..) -> "0x7f4"
    unit_news.CastMissed(..) -> "0x7fb"
    unit_news.CastTicked(..) -> "0x7f8"
    CastFinished(..) -> "0x7fe"
    unit_news.CastInterrupted(..) -> "0x7f9"
    unit_news.CastTargetsRemoved(..) -> "0x811"
    Health(health:, ..) -> "0x937(" <> int.to_string(health) <> ")"
    unit_news.Died -> "0x88c"
    CreatureAppeared(..) -> "0x262"
    unit_news.Removed -> "0x355"
    unit_news.CrowdControlApplied(..)
    | unit_news.CasterRestrictionApplied(..) -> "0x87f"
    unit_news.CrowdControlEnded(..) | unit_news.CasterRestrictionEnded(..) ->
      "0x880"
    unit_news.InterruptArmor(armor:) ->
      "0x938(21, " <> int.to_string(armor) <> ")"
    unit_news.Absorption(absorption:) ->
      "0x938(22, " <> int.to_string(absorption) <> ")"
    unit_news.Level(level:) -> "0x938(10, " <> int.to_string(level) <> ")"
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

/// What the step sends the creature's map, in order.
pub fn to_the_map(
  taken: ServiceStep(creature.Outgoing),
) -> List(creature.Outgoing) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: step.Map(..), message:)) -> Ok(message)
      OwnEffect(_) | step.Watch(..) | step.Unwatch(..) | step.Log(..) | Stop ->
        Error(Nil)
    }
  })
}

/// What the step sends the creature's map, one line each: news for every viewer by its name
/// and `to all`; a tell to a player by what it says and the player's number; a snapshot by
/// the viewer's number.
pub fn said_to_the_map(taken: ServiceStep(creature.Outgoing)) -> List(String) {
  list.map(to_the_map(taken), fn(sent) {
    case sent {
      creature.Broadcast(news: PeerNews(news:, ..), ..) ->
        name_of(news) <> " to all"
      creature.Snapshot(by:, ..) ->
        "snapshot for " <> int.to_string(unit_address.joiner(address: by))
      creature.Expired(unit_id:, life:) ->
        "expired "
        <> int.to_string(unit_id)
        <> " of life "
        <> int.to_string(life)
      creature.Relay(to:, payload:, ..) -> {
        let number = unit_address.joiner(address: to)
        case payload {
          map_message.Struck(answered: Answered(outcome: Landed(..), ..)) ->
            "answer to " <> int.to_string(number)
          map_message.Struck(answered: Answered(outcome: Refused(why:), ..)) ->
            "Refused(" <> refusal_name(why) <> ") to " <> int.to_string(number)
          map_message.Struck(..) -> "answer to " <> int.to_string(number)
          map_message.KillCredit(..) -> "credit to " <> int.to_string(number)
          map_message.Fight(told: Threatened(unit_id:, life:)) ->
            "Threatened("
            <> int.to_string(unit_id)
            <> ", "
            <> int.to_string(life)
            <> ") to "
            <> int.to_string(number)
          map_message.Fight(told: Released(unit_id:)) ->
            "Released("
            <> int.to_string(unit_id)
            <> ") to "
            <> int.to_string(number)
          map_message.Fight(told: Attacks(..)) ->
            "Attacks to " <> int.to_string(number)
        }
      }
    }
  })
}

fn refusal_name(why: strike_tell.Refusal) -> String {
  case why {
    strike_tell.Dead -> "Dead"
    strike_tell.Returning -> "Returning"
    strike_tell.Despawned -> "Despawned"
  }
}

/// The map's `Seen` of a viewer that the creature takes, under the generation every first
/// viewer of the tests' creatures holds, so the `unseen` that follows it ends the sight.
pub fn seen(by by: ConnectionId) -> creature.Message {
  creature.Seen(by: address_of(connection: by), generation: generation.first())
}

/// The address the tests' map issues the player of `connection`: its number.
pub fn address_of(connection connection: ConnectionId) -> UnitAddress {
  let ConnectionId(number) = connection
  map_support.address(number:)
}

/// The connection the address was issued for.
pub fn connection_of(address address: UnitAddress) -> ConnectionId {
  ConnectionId(unit_address.joiner(address:))
}

/// The map's `Unseen` of the sight `seen` or a creature's start began.
pub fn unseen(by by: ConnectionId) -> creature.Message {
  creature.Unseen(
    by: address_of(connection: by),
    generation: generation.first(),
  )
}

/// The map's `Unseen` of the sight `seen` began, for the unit named by its address.
pub fn unseen_address(by by: UnitAddress) -> creature.Message {
  creature.Unseen(by:, generation: generation.first())
}

/// The step as the players it concerns would hear it, one send to each, so the tests that
/// read what each viewer is told keep their reading while the creature tells its map once:
/// a broadcast becomes one send to each viewer of `state` (the state after the step) in
/// connection order, a snapshot one send of each item of its burst to the viewer it is for,
/// and a relay a send to the player it names; each stays the creature's own message. Other
/// effects stay as they are.
pub fn at_each_player(
  state state: creature.State,
  taken taken: ServiceStep(creature.Outgoing),
) -> ServiceStep(creature.Outgoing) {
  let viewers = unit_address.sorted(creature.viewers(state))
  Effects(
    list.flat_map(support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(Send(
          to: step.Map(..),
          message: creature.Broadcast(..) as message,
        )) ->
          list.map(viewers, fn(viewer) {
            OwnEffect(Send(
              to: Connection(connection_of(address: viewer)),
              message:,
            ))
          })
        OwnEffect(Send(
          to: step.Map(..),
          message: creature.Snapshot(unit_id:, life:, by:, burst:, ..),
        )) ->
          list.map(burst, fn(news) {
            OwnEffect(Send(
              to: Connection(connection_of(address: by)),
              message: creature.Broadcast(unit_id:, life:, news:),
            ))
          })
        OwnEffect(Send(
          to: step.Map(..),
          message: creature.Relay(to:, ..) as message,
        )) -> [
          OwnEffect(Send(to: Connection(connection_of(address: to)), message:)),
        ]
        OwnEffect(_)
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | Stop -> [effect]
      }
    }),
  )
}

/// What the creature's step tells the player of connection `connection` once its map has
/// relayed it, in order, for a player whose relation with the creature is relaying: the
/// items of a snapshot for it, every broadcast and each relay that names it. The map's checks
/// are the map's own (`genesis_prime/world_map/map`), tested there.
pub fn relayed_to(
  taken taken: ServiceStep(creature.Outgoing),
  connection connection: ConnectionId,
) -> List(map_message.Delivered) {
  let address = address_of(connection:)
  list.flat_map(to_the_map(taken), fn(sent) {
    case sent {
      creature.Snapshot(by:, burst:, ..) if by == address ->
        list.map(burst, fn(news) { map_message.News(news:) })
      creature.Broadcast(news:, ..) -> [map_message.News(news:)]
      creature.Relay(to:, payload:, ..) if to == address -> [
        map_message.Tell(payload:),
      ]
      creature.Snapshot(..) | creature.Relay(..) | creature.Expired(..) -> []
    }
  })
}

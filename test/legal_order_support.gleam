//// The legal orders of a viewer, a creature and their map, run as the pure rules they
//// are: the three processes' rules, each with its mailbox, and every order in which
//// the BEAM may deliver what is sent, checked against the invariants a viewer's frames
//// keep. Expected values come from these places.
//// - OTP orders the signals of one sender to one receiver, and no others: a receiver's
////   mailbox holds one first-in-first-out queue for each sender, and it takes the head
////   of any of them next. A delivery of this scene is the head of one such queue.
//// - The invariants are the client's: a unit is created once and removed once, and it is
////   told no frame before its 0x262 or after its 0x355 (`opcode.0x262`, `opcode.0x355`).
////
//// ```
//// scene(map, creature, viewer, mail) ─▶ orders ─▶ one scene for each order of deliveries
////                                                    each delivery takes one rule's step and
////                                                    puts what the step sends in the mail
//// check(scene) ─▶ Ok, or the first invariant the viewer's frames break
//// ```

import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{type Answer, type Message}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_death_state
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_health
import genesis_prime/message/unit_movement
import genesis_prime/server
import genesis_prime/step.{
  type ConnectionEvent, type Event, type ServiceEvent, Connection, ConnectionId,
  Creature, OwnEffect, OwnEvent, Send, Told, Woken,
}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map
import genesis_prime/world_map/relay
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import map_spawn_support
import spawn_support

/// The processes of the scene, each a receiver of mail.
pub type Receiver {
  MapProcess
  CreatureProcess
  ViewerProcess
}

/// The senders whose queues a receiver's mailbox keeps apart: the map, the creature, the
/// connection of the player the viewer stands for, a caster that strikes the creature, and
/// a timer, which is the receiver's own.
pub type Sender {
  FromMap
  FromCreature
  FromConnection
  FromCaster
  FromTimer
}

/// An input of one of the processes.
pub type Input {
  ToMap(event: Event(ServiceEvent(map.Message)))
  ToCreature(event: Event(ServiceEvent(creature.Message)))
  ToViewer(event: Event(ConnectionEvent(Message, Answer)))
}

/// One message in a mailbox: its receiver, its sender, what it is and its name, which the
/// tests read the order of deliveries by.
pub type Mail {
  Mail(to: Receiver, from: Sender, input: Input, name: String)
}

/// What a receiver took: from whom, and the name of the message.
pub type Taken {
  Taken(by: Receiver, from: Sender, name: String)
}

/// The three processes' states, what is in flight, the monotonic time the next delivery is
/// taken at, the deliveries so far in order, the frames the viewer wrote in order and the
/// first news the map relayed to the viewer that its relation did not allow (`early`).
pub type Scene {
  Scene(
    map: map.State,
    creature: creature.State,
    viewer: game_connection.State,
    mail: List(Mail),
    now_ms: Int,
    taken: List(Taken),
    frames: List(Frame),
    early: Option(Violation),
  )
}

/// A rule a viewer's frames keep.
pub type Invariant {
  /// No frame names a unit after its 0x355, until a 0x262 creates it again.
  NoFrameAfterRemoval
  /// No 0x262 creates a unit the client already shows.
  NoSecondCreationWhileShown
  /// No frame about a unit is written before its 0x262.
  NoNewsBeforeCreation
  /// When every message is delivered, the map holds a relation with the viewer exactly
  /// when the viewer's client shows the creature, and no relation awaits its snapshot.
  RelationEndsMatchTheMap
  /// The map relays the creature's news to the viewer only through its relation: a
  /// broadcast only while the relation relays, and a snapshot's burst only while the relation
  /// awaits that very generation. Read from the map's mail to the viewer, which the viewer's
  /// own frames hide (the viewer drops news of a unit it does not show).
  NoNewsRelayedOutsideTheRelation
}

/// The invariant a trace broke, at the frame it broke it (counted from 0, and past the
/// last for an invariant of the end), for the unit.
pub type Violation {
  Violation(invariant: Invariant, at_frame: Int, unit_id: Int)
}

/// A scene: the states, and the mail already in flight in the order it was sent.
pub fn scene(
  map map: map.State,
  creature creature: creature.State,
  viewer viewer: game_connection.State,
  mail mail: List(Mail),
) -> Scene {
  Scene(
    map:,
    creature:,
    viewer:,
    mail:,
    now_ms: 10_000,
    taken: [],
    frames: [],
    early: None,
  )
}

/// The deliveries the scene allows now: the head of each queue, one for each receiver and
/// sender, in the order they were sent.
pub fn deliverable(scene scene: Scene) -> List(Mail) {
  list.fold(scene.mail, [], fn(heads: List(Mail), mail: Mail) {
    case
      list.any(heads, fn(head) { head.to == mail.to && head.from == mail.from })
    {
      True -> heads
      False -> [mail, ..heads]
    }
  })
  |> list.reverse
}

/// Every scene the deliveries can end in: each order that takes the head of one queue at a
/// time until no mail is left. A delivery with no other order to compete with is made at
/// once: a receiver whose mailbox holds one queue, and no other sender of it has mail it
/// could still send, takes that head first in every order, so it is not branched on.
pub fn orders(scene scene: Scene) -> List(Scene) {
  let heads = deliverable(scene:)
  case list.find(heads, fn(mail) { has_no_rival(scene:, mail:, heads:) }) {
    Ok(mail) -> orders(scene: deliver(scene:, mail:))
    Error(Nil) ->
      case heads {
        [] -> [scene]
        _ ->
          list.flat_map(heads, fn(mail) {
            orders(scene: deliver(scene:, mail:))
          })
      }
  }
}

/// The scene after every delivery is made in the order the heads are found: one order,
/// for a setup the tests do not vary.
pub fn settle(scene scene: Scene) -> Scene {
  case deliverable(scene:) {
    [] -> scene
    [mail, ..] -> settle(scene: deliver(scene:, mail:))
  }
}

/// Whether the mail's receiver has only this queue now and no process that sends to it
/// has mail to take, so no other message can reach the receiver before this one: the map
/// is sent to by the creature, the creature by the map, the viewer by the map.
fn has_no_rival(
  scene scene: Scene,
  mail mail: Mail,
  heads heads: List(Mail),
) -> Bool {
  let alone = list.count(heads, fn(head) { head.to == mail.to }) == 1
  let sender_is_busy = case mail.to {
    MapProcess -> has_mail(scene:, receiver: CreatureProcess)
    CreatureProcess -> has_mail(scene:, receiver: MapProcess)
    ViewerProcess -> False
  }
  alone && !sender_is_busy
}

fn has_mail(scene scene: Scene, receiver receiver: Receiver) -> Bool {
  list.any(scene.mail, fn(mail) { mail.to == receiver })
}

/// The scene after the receiver takes the mail: its rule's step, and what the step sends
/// put in the mail behind what is there.
pub fn deliver(scene scene: Scene, mail mail: Mail) -> Scene {
  let rest = remove_first(scene.mail, mail)
  let now_ms = scene.now_ms + 1
  let scene =
    Scene(
      ..scene,
      mail: rest,
      now_ms:,
      taken: list.append(scene.taken, [
        Taken(by: mail.to, from: mail.from, name: mail.name),
      ]),
    )
  case mail.input {
    ToMap(event:) -> {
      let #(state, taken) =
        map.step(scene.map, support.input_at_ms(ms: now_ms, event:))
      Scene(
        ..scene,
        map: state,
        mail: list.append(scene.mail, mail_of_the_map(taken)),
        early: case scene.early {
          Some(_) -> scene.early
          None -> news_outside_the_relation(scene:, event:, taken:)
        },
      )
    }
    ToCreature(event:) -> {
      let #(state, taken) =
        creature.step(scene.creature, support.input_at_ms(ms: now_ms, event:))
      Scene(
        ..scene,
        creature: state,
        mail: list.append(scene.mail, mail_of_the_creature(taken)),
      )
    }
    ToViewer(event:) -> {
      let #(state, taken) =
        game_connection_support.feed(state: scene.viewer, event:)
      Scene(
        ..scene,
        viewer: state,
        frames: list.append(
          scene.frames,
          game_connection_support.heard(taken, game_connection_support.keyed()),
        ),
      )
    }
  }
}

/// The violation of `NoNewsRelayedOutsideTheRelation` a map's step makes, when it relays
/// the creature's news to the viewer that the relation the map held before the step did not
/// allow.
fn news_outside_the_relation(
  scene scene: Scene,
  event event: Event(ServiceEvent(map.Message)),
  taken taken: step.ServiceStep(map.Outgoing),
) -> Option(Violation) {
  let relays_news =
    list.any(support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(Send(
          to: Connection(ConnectionId(1)),
          message: map.Relayed(delivered: relay.News(..), ..),
        )) -> True
        OwnEffect(_)
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | step.Stop -> False
      }
    })
  let held = relation_held(map: scene.map)
  let allowed = case event, held {
    OwnEvent(Told(message: map.Broadcast(..))),
      Some(map.Relation(state: map.Relaying, ..))
    -> True
    OwnEvent(Told(message: map.Snapshot(generation:, ..))),
      Some(map.Relation(
        generation: held_generation,
        state: map.AwaitingSnapshot,
        ..,
      ))
    -> generation == held_generation
    _, _ -> False
  }
  case relays_news && !allowed {
    False -> None
    True ->
      Some(Violation(
        NoNewsRelayedOutsideTheRelation,
        list.length(scene.frames),
        unit_of_the_spawn(map: scene.map),
      ))
  }
}

/// The relation the map holds between the viewer and the creature of the scene's spawn,
/// while the spawn lives or is released.
fn relation_held(map state: map.State) -> Option(map.Relation) {
  case map.spawn_state(state:, spawn: SpawnId(1)) {
    Ok(map.Live(relations:, ..)) | Ok(map.Releasing(relations:, ..)) ->
      dict_get(relations, ConnectionId(1))
    Ok(_) | Error(Nil) -> None
  }
}

/// The unit id of the creature of the scene's spawn, 0 when it has none.
fn unit_of_the_spawn(map state: map.State) -> Int {
  case map.spawn_state(state:, spawn: SpawnId(1)) {
    Ok(map.Live(unit_id:, ..))
    | Ok(map.Retiring(unit_id:, ..))
    | Ok(map.Releasing(unit_id:, ..)) -> unit_id
    Ok(map.WaitingForRestart) | Ok(map.Failed) | Error(Nil) -> 0
  }
}

fn remove_first(mail: List(Mail), taken: Mail) -> List(Mail) {
  case mail {
    [] -> []
    [first, ..rest] ->
      case first == taken {
        True -> rest
        False -> [first, ..remove_first(rest, taken)]
      }
  }
}

/// What a map's step sends to the creatures and to the viewer's connection, in order, as
/// mail.
pub fn mail_of_the_map(taken: step.ServiceStep(map.Outgoing)) -> List(Mail) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: Creature(..), message:)) ->
        case creature.told_by_map(message) {
          Ok(told) ->
            Ok(Mail(
              to: CreatureProcess,
              from: FromMap,
              input: ToCreature(OwnEvent(Told(told))),
              name: creature_message_name(told),
            ))
          Error(Nil) -> Error(Nil)
        }
      OwnEffect(Send(to: Connection(ConnectionId(1)), message:)) ->
        case server.map_message(outgoing: message) {
          Ok(sent) ->
            Ok(Mail(
              to: ViewerProcess,
              from: FromMap,
              input: ToViewer(OwnEvent(Woken(sent))),
              name: "map " <> map_outgoing_name(message),
            ))
          Error(Nil) -> Error(Nil)
        }
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// What a creature's step sends to its map, in order, as mail.
pub fn mail_of_the_creature(
  taken: step.ServiceStep(creature.Outgoing),
) -> List(Mail) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: step.Map(..), message:)) -> {
        let told = creature.told_to_map(outgoing: message)
        Ok(Mail(
          to: MapProcess,
          from: FromCreature,
          input: ToMap(OwnEvent(Told(told))),
          name: map_message_name(told),
        ))
      }
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

fn creature_message_name(message: creature.Message) -> String {
  case message {
    creature.Seen(..) -> "Seen"
    creature.Unseen(..) -> "Unseen"
    creature.Retire
    | creature.Strike(..)
    | creature.Approached(..)
    | creature.Withdrew(..)
    | creature.PlayerDied(..)
    | creature.TargetMoved(..)
    | creature.StrikeAnswered(..)
    | creature.ModifierStarts(..)
    | creature.ModifierEnds(..)
    | creature.Thrown(..)
    | creature.Despawn(..)
    | creature.UnitStates(..)
    | creature.CastViewSet(..)
    | creature.CastViewEnds(..)
    | creature.ControlsEnd(..) -> "another tell"
  }
}

fn map_message_name(message: map.Message) -> String {
  case message {
    map.Snapshot(..) -> "Snapshot"
    map.Broadcast(..) -> "Broadcast"
    map.Relay(..) -> "Relay"
    map.Join(..)
    | map.Leave(..)
    | map.Moved(..)
    | map.Ready(..)
    | map.StealthChanged(..)
    | map.LifeChanged(..)
    | map.VisibilityChanged(..)
    | map.Released(..)
    | map.Summon(..) -> "another tell"
  }
}

fn map_outgoing_name(message: map.Outgoing) -> String {
  case message {
    map.Relayed(..) -> "Relayed"
    map.Noticed(notice: map.UnitUnseen(..), ..) -> "Unseen"
    map.Noticed(..) -> "a notice"
    map.Joined(..)
    | map.NotJoined(..)
    | map.Summoned(..)
    | map.NotSummoned(..)
    | map.Left
    | map.Seen(..)
    | map.Unseen(..)
    | map.Retire
    | map.Approached(..)
    | map.Withdrew(..)
    | map.PlayerDied(..) -> "another send"
  }
}

/// The names of what the receiver took, in order.
pub fn order_at(
  scene scene: Scene,
  receiver receiver: Receiver,
) -> List(String) {
  list.filter(scene.taken, fn(taken) { taken.by == receiver })
  |> list.map(fn(taken) { taken.name })
}

/// What the frames that name a unit the scene follows say, one line each: the opcode and
/// the unit, `0x262(7)`. A frame that names none is left out.
pub fn names(frames frames: List(Frame)) -> List(String) {
  list.filter_map(frames, fn(frame) {
    let opcode = "0x" <> int.to_base16(frame.message_id)
    case unit_of(frame:) {
      Some(unit_id) -> Ok(opcode <> "(" <> int.to_string(unit_id) <> ")")
      None -> Error(Nil)
    }
  })
}

/// The unit a frame the scene follows names: 0x262 of a creature, 0x355, 0x937, 0x88c and
/// 0x638.
fn unit_of(frame frame: Frame) -> Option(Int) {
  let Frame(message_id:, body:) = frame
  case message_id {
    0x0262 ->
      unit_create_creature.decode(body)
      |> result.map(fn(created) { created.unit_id })
      |> option.from_result
    0x0355 ->
      unit_destroyed.decode(body)
      |> result.map(fn(destroyed) { destroyed.unit_id })
      |> option.from_result
    0x0937 ->
      unit_health.decode(body)
      |> result.map(fn(health) { health.unit_id })
      |> option.from_result
    0x088C ->
      unit_death_state.decode(body)
      |> result.map(fn(death) { death.unit_id })
      |> option.from_result
    0x0638 ->
      unit_movement.decode(body)
      |> result.map(fn(movement) { movement.unit_id })
      |> option.from_result
    _ -> None
  }
}

/// The first invariant the frames break, or `Ok(Nil)`: a frame is checked against the units
/// the frames before it created and removed.
pub fn check_frames(frames frames: List(Frame)) -> Result(Nil, Violation) {
  list.index_fold(frames, Ok(#([], [])), fn(held, frame, index) {
    use #(shown, removed) <- result.try(held)
    case unit_of(frame:) {
      None -> Ok(#(shown, removed))
      Some(unit_id) -> frame_taken(frame:, index:, unit_id:, shown:, removed:)
    }
  })
  |> result.replace(Nil)
}

/// The units shown and removed after a frame that names `unit_id`, or the invariant it breaks.
fn frame_taken(
  frame frame: Frame,
  index index: Int,
  unit_id unit_id: Int,
  shown shown: List(Int),
  removed removed: List(Int),
) -> Result(#(List(Int), List(Int)), Violation) {
  let is_shown = list.contains(shown, unit_id)
  case frame.message_id, is_shown, list.contains(removed, unit_id) {
    0x0262, True, _ ->
      Error(Violation(NoSecondCreationWhileShown, index, unit_id))
    0x0262, False, _ ->
      Ok(#([unit_id, ..shown], list.filter(removed, fn(id) { id != unit_id })))
    0x0355, True, _ ->
      Ok(#(list.filter(shown, fn(id) { id != unit_id }), [unit_id, ..removed]))
    0x0355, False, _ -> Error(Violation(NoNewsBeforeCreation, index, unit_id))
    _, True, _ -> Ok(#(shown, removed))
    _, False, True -> Error(Violation(NoFrameAfterRemoval, index, unit_id))
    _, False, False -> Error(Violation(NoNewsBeforeCreation, index, unit_id))
  }
}

/// The first invariant a finished scene breaks: its frames' (`check_frames`), the news the map
/// relayed outside the viewer's relation, and the end's:
/// the map holds a relation with the viewer exactly when the viewer's client shows the
/// creature of the spawn, and no relation still awaits its snapshot.
pub fn check(scene scene: Scene) -> Result(Nil, Violation) {
  use Nil <- result.try(check_frames(frames: scene.frames))
  use Nil <- result.try(case scene.early {
    Some(violation) -> Error(violation)
    None -> Ok(Nil)
  })
  case map.spawn_state(state: scene.map, spawn: SpawnId(1)) {
    Ok(map.Live(unit_id:, relations:, ..)) -> {
      let shown = shows(frames: scene.frames, unit_id:)
      let at_end = list.length(scene.frames)
      case dict_get(relations, ConnectionId(1)), shown {
        Some(map.Relation(state: map.Relaying, ..)), _ -> Ok(Nil)
        Some(map.Relation(state: map.AwaitingSnapshot, ..)), _ ->
          Error(Violation(RelationEndsMatchTheMap, at_end, unit_id))
        None, True -> Error(Violation(RelationEndsMatchTheMap, at_end, unit_id))
        None, False -> Ok(Nil)
      }
    }
    Ok(_) | Error(Nil) -> Ok(Nil)
  }
}

fn dict_get(
  relations: dict.Dict(step.ConnectionId, map.Relation),
  connection: step.ConnectionId,
) -> Option(map.Relation) {
  dict.get(relations, connection) |> option.from_result
}

/// Whether the frames leave the unit shown: its last 0x262 or 0x355 is a 0x262.
fn shows(frames frames: List(Frame), unit_id unit_id: Int) -> Bool {
  list.fold(frames, False, fn(shown, frame) {
    case unit_of(frame:), frame.message_id {
      Some(id), 0x0262 if id == unit_id -> True
      Some(id), 0x0355 if id == unit_id -> False
      _, _ -> shown
    }
  })
}

/// The health the frames leave the viewer's client showing for the unit: its last 0x262's,
/// then each 0x937's after it, none when the unit is not shown.
pub fn health_shown(
  frames frames: List(Frame),
  unit_id unit_id: Int,
) -> Option(Int) {
  list.fold(frames, None, fn(health, frame) {
    case unit_of(frame:), frame.message_id {
      Some(id), 0x0262 if id == unit_id ->
        unit_create_creature.decode(frame.body)
        |> result.map(creature_unit.health_of)
        |> option.from_result
      Some(id), 0x0937 if id == unit_id ->
        unit_health.decode(frame.body)
        |> result.map(fn(message) { message.health })
        |> option.from_result
      Some(id), 0x0355 if id == unit_id -> None
      _, _ -> health
    }
  })
}

/// The creature the map's start names, as the server builds it at the spawn, and its first
/// step at `at_ms`: its state and what the step sends.
pub fn creature_started(
  start start: step.CreatureStart,
  spawn spawn: spawn.Spawn,
  at_ms at_ms: Int,
) -> #(creature.State, step.ServiceStep(creature.Outgoing)) {
  creature.step(
    creature.new(creature.Settings(
      creature: start,
      spawn:,
      kind: map_spawn_support.default_kinds().default,
      numbers: spawn_support.numbers,
    )),
    support.input_at_ms(ms: at_ms, event: OwnEvent(step.Started)),
  )
}

//// The legal orders of a viewer, a creature and their map, run as the pure rules they
//// are: the three processes' rules, each with its mailbox, and every order in which
//// the BEAM may deliver what is sent, checked against the invariants a viewer's frames
//// keep. Expected values come from these places.
//// - OTP orders the signals of one sender to one receiver, and no others: a receiver's
////   mailbox holds one first-in-first-out queue for each sender, and it takes the head
////   of any of them next. A delivery of this scene is the head of one such queue. The
////   end of a process reaches a process that monitors it as one more signal of that
////   sender, after everything the process sent it (`WatchEnded`), and what is sent to a
////   process that has ended is lost: the scene drops mail addressed to a creature that has
////   stopped, whether it is in flight when the creature stops or sent after.
//// - A creature that stops is replaced by the next life its map starts when it takes the
////   creature's `WatchEnded`: a second creature process, a sender of its own, whose first
////   step is its `Started` (the shell takes it before the creature's mailbox).
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
import genesis_prime/map/message as map_message
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_death_state
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_health
import genesis_prime/message/unit_movement
import genesis_prime/server
import genesis_prime/shared/strike_tell
import genesis_prime/step.{
  type ConnectionEvent, type Event, type ServiceEvent, Connection, ConnectionId,
  Creature, OwnEffect, OwnEvent, Send, Told, Woken,
}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/unit_address
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import map_spawn_support
import map_support
import order_explorer
import spawn_support

/// The processes of the scene, each a receiver of mail.
pub type Receiver {
  MapProcess
  CreatureProcess
  NextCreatureProcess
  ViewerProcess
}

/// The senders whose queues a receiver's mailbox keeps apart: the map, the creature, the
/// creature the map started when the first one ended, the connection of the player the
/// viewer stands for, the connection of the first player, the caster that strikes the
/// creature, which tells the map, and a timer, which is the receiver's own.
pub type Sender {
  FromMap
  FromCreature
  FromNextCreature
  FromConnection
  FromCaster
  FromTimer
}

/// An input of one of the processes.
pub type Input {
  ToMap(event: Event(ServiceEvent(map_message.Message)))
  ToCreature(event: Event(ServiceEvent(creature.Message)))
  ToNextCreature(event: Event(ServiceEvent(creature.Message)))
  ToViewer(event: Event(ConnectionEvent(Message, Answer)))
}

/// One message in a mailbox (`order_explorer.Mail`) of this scene.
pub type Mail =
  order_explorer.Mail(Receiver, Sender, Input)

/// What a receiver took (`order_explorer.Taken`) in this scene.
pub type Taken =
  order_explorer.Taken(Receiver, Sender)

/// The three processes' states (the creature's none once it stopped), the life of the
/// creature and the creature the map started after it (`next_creature`, with its life), what is in flight, the monotonic time the
/// next delivery is taken at, the deliveries so far in order, the frames the viewer wrote
/// in order and the first news the map relayed to the viewer that its relation did not
/// allow (`early`).
pub type Scene {
  Scene(
    map: map.State,
    creature: Option(creature.State),
    life: Int,
    next_creature: Option(creature.State),
    next_life: Option(Int),
    viewer: game_connection.State,
    mail: List(Mail),
    clocks: order_explorer.Clocks(Receiver),
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

/// A scene: the states, and the mail already in flight in the order it was sent. Mail that
/// no process of the scene may send stops the test (`refused`).
pub fn scene(
  map map: map.State,
  creature creature: creature.State,
  viewer viewer: game_connection.State,
  mail mail: List(Mail),
) -> Scene {
  with_mail(
    scene: Scene(
      map:,
      creature: Some(creature),
      life: map_spawn_support.creature_of(state: map, spawn: 1).1,
      next_creature: None,
      next_life: None,
      viewer:,
      mail: [],
      clocks: order_explorer.clocks(start_ms: 10_000),
      taken: [],
      frames: [],
      early: None,
    ),
    mail:,
  )
}

/// Why a scene cannot hold some mail.
pub type Refusal {
  /// A creature takes mail from its map and its own timer only: this mail comes from
  /// another sender.
  CreatureMailedByAnotherSender(from: Sender, name: String)
}

/// The refusal as a message that names the sender.
pub fn describe(refusal refusal: Refusal) -> String {
  let CreatureMailedByAnotherSender(from:, name:) = refusal
  "a creature takes mail from its map and its timer only, not "
  <> sender_name(sender: from)
  <> " ("
  <> name
  <> ")"
}

/// The refusals among the mail: a creature has one external sender, its map, and its own
/// timer, so mail to a creature from any other sender is refused. Every way mail enters a
/// scene is checked by this: `scene` and `with_mail` when it is added, `deliver` when it is
/// taken, so mail put in by a record update is refused too.
pub fn refused(mail mail: List(Mail)) -> List(Refusal) {
  list.filter_map(mail, fn(mail) {
    case mail.to, mail.from {
      CreatureProcess, FromMap
      | CreatureProcess, FromTimer
      | NextCreatureProcess, FromMap
      | NextCreatureProcess, FromTimer
      -> Error(Nil)
      CreatureProcess, FromCreature
      | CreatureProcess, FromNextCreature
      | CreatureProcess, FromConnection
      | CreatureProcess, FromCaster
      | NextCreatureProcess, FromCreature
      | NextCreatureProcess, FromNextCreature
      | NextCreatureProcess, FromConnection
      | NextCreatureProcess, FromCaster
      -> Ok(CreatureMailedByAnotherSender(from: mail.from, name: mail.name))
      MapProcess, _ | ViewerProcess, _ -> Error(Nil)
    }
  })
}

/// The scene with the mail added behind what is in flight, or the refusal of the first
/// mail that no process of the scene may send (`refused`).
pub fn mailed(
  scene scene: Scene,
  mail mail: List(Mail),
) -> Result(Scene, Refusal) {
  case refused(mail:) {
    [] -> Ok(Scene(..scene, mail: list.append(scene.mail, mail)))
    [refusal, ..] -> Error(refusal)
  }
}

/// The scene with the mail added behind what is in flight; mail that no process of the
/// scene may send stops the test, naming the sender.
pub fn with_mail(scene scene: Scene, mail mail: List(Mail)) -> Scene {
  case mailed(scene:, mail:) {
    Ok(scene) -> scene
    Error(refusal) -> panic as describe(refusal:)
  }
}

/// The name of a sender, as a refusal writes it.
pub fn sender_name(sender sender: Sender) -> String {
  case sender {
    FromMap -> "FromMap"
    FromCreature -> "FromCreature"
    FromNextCreature -> "FromNextCreature"
    FromConnection -> "FromConnection"
    FromCaster -> "FromCaster"
    FromTimer -> "FromTimer"
  }
}

/// The name of a receiver, as the order of the walk reads it.
fn receiver_name(receiver receiver: Receiver) -> String {
  case receiver {
    MapProcess -> "map"
    CreatureProcess -> "creature"
    NextCreatureProcess -> "next creature"
    ViewerProcess -> "viewer"
  }
}

/// The scheduler of the scene's processes (`order_explorer`).
fn scheduler() -> order_explorer.Scheduler(Scene, Receiver, Sender, Input) {
  order_explorer.Scheduler(
    mail: fn(scene: Scene) { scene.mail },
    in_flight: fn(scene: Scene) { scene.mail },
    deliver:,
    taken: fn(scene: Scene) { scene.taken },
    same_state:,
    queue_name: fn(receiver, sender) {
      receiver_name(receiver:) <> " from " <> sender_name(sender:)
    },
  )
}

/// Every scene the deliveries can end in, one for each outcome: each order that takes the
/// head of one queue at a time until no mail is left, with the deliveries to different
/// processes not ordered against each other (`order_explorer.orders`).
pub fn orders(scene scene: Scene) -> List(Scene) {
  order_explorer.orders(scheduler: scheduler(), scene:)
}

/// The scenes of `orders` with every two deliveries to one receiver taken as dependent
/// (`order_explorer.orders_by_receiver`).
pub fn orders_by_receiver(scene scene: Scene) -> List(Scene) {
  order_explorer.orders_by_receiver(scheduler: scheduler(), scene:)
}

/// Whether two scenes hold the same state in every process and the same first violation,
/// whatever order was taken to reach them.
pub fn same_state(first first: Scene, second second: Scene) -> Bool {
  Scene(..first, mail: [], taken: []) == Scene(..second, mail: [], taken: [])
}

/// Whether the walk by commuting and the walk by receiver alone end in the same scenes
/// from `scene` (`order_explorer.relations_end_alike`).
pub fn relations_end_alike(scene scene: Scene) -> Bool {
  order_explorer.relations_end_alike(scheduler: scheduler(), scene:)
}

/// The scenes of every order with no reduction (`order_explorer.orders_in_full`).
pub fn orders_in_full(scene scene: Scene) -> List(Scene) {
  order_explorer.orders_in_full(scheduler: scheduler(), scene:)
}

/// The scene after every delivery is made in the order the heads are found: one order,
/// for a setup the tests do not vary.
pub fn settle(scene scene: Scene) -> Scene {
  order_explorer.settle(scheduler: scheduler(), scene:)
}

/// The scene after the receiver takes the mail: its rule's step, and what the step sends
/// put in the mail behind what is there.
pub fn deliver(scene scene: Scene, mail mail: Mail) -> Scene {
  case refused(mail: [mail]) {
    [] -> Nil
    [refusal, ..] -> panic as describe(refusal:)
  }
  let rest = order_explorer.remove_first(mail: scene.mail, taken: mail)
  let #(clocks, now_ms) =
    order_explorer.ticked(clocks: scene.clocks, receiver: mail.to)
  let scene =
    Scene(
      ..scene,
      mail: rest,
      clocks:,
      taken: list.append(scene.taken, [
        order_explorer.Taken(by: mail.to, from: mail.from, name: mail.name),
      ]),
    )
  case mail.input {
    ToMap(event:) -> {
      let #(state, taken) =
        map.step(scene.map, support.input_at_ms(ms: now_ms, event:))
      let scene =
        Scene(..scene, map: state, early: case scene.early {
          Some(_) -> scene.early
          None -> news_outside_the_relation(scene:, event:, taken:)
        })
      case started_by(taken:) {
        Ok(start) -> {
          let #(clocks, started_ms) =
            order_explorer.ticked(
              clocks: scene.clocks,
              receiver: NextCreatureProcess,
            )
          let #(next, started) =
            creature_started(start:, spawn: the_beast(), at_ms: started_ms)
          Scene(
            ..scene,
            clocks:,
            next_creature: Some(next),
            next_life: Some(start.life),
            mail: list.flatten([
              scene.mail,
              reaching_a_running_creature(
                scene:,
                mail: mail_of_the_map_for(taken:, next_life: Some(start.life)),
              ),
              mail_of_the_creature_as(
                taken: started,
                sender: FromNextCreature,
                prefix: "Next ",
              ),
            ]),
          )
        }
        Error(Nil) ->
          Scene(
            ..scene,
            mail: list.append(
              scene.mail,
              reaching_a_running_creature(
                scene:,
                mail: mail_of_the_map_for(taken:, next_life: scene.next_life),
              ),
            ),
          )
      }
    }
    ToCreature(event:) -> {
      let assert Some(held) = scene.creature
        as "the scene delivers no mail to a creature that stopped"
      let #(state, taken) =
        creature.step(held, support.input_at_ms(ms: now_ms, event:))
      let sent = mail_of_the_creature(taken)
      case support.stops(taken) {
        False ->
          Scene(
            ..scene,
            creature: Some(state),
            mail: list.append(scene.mail, sent),
          )
        True ->
          // The creature ends: what is still in its mailbox is lost, and its map, which
          // watches it, takes its end after what it sent.
          Scene(
            ..scene,
            creature: None,
            mail: list.flatten([
              list.filter(scene.mail, fn(waiting) {
                waiting.to != CreatureProcess
              }),
              sent,
              [creature_ended(life: scene.life)],
            ]),
          )
      }
    }
    ToNextCreature(event:) ->
      case scene.next_creature {
        Some(held) -> {
          let #(state, taken) =
            creature.step(held, support.input_at_ms(ms: now_ms, event:))
          Scene(
            ..scene,
            next_creature: Some(state),
            mail: list.append(
              scene.mail,
              mail_of_the_creature_as(
                taken:,
                sender: FromNextCreature,
                prefix: "Next ",
              ),
            ),
          )
        }
        None -> panic as "no creature was started to take mail"
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
  event event: Event(ServiceEvent(map_message.Message)),
  taken taken: step.ServiceStep(map_message.Outgoing),
) -> Option(Violation) {
  let relays_news =
    list.any(support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(Send(
          to: Connection(ConnectionId(1)),
          message: map_message.Relayed(delivered: map_message.News(..)),
        )) -> True
        OwnEffect(_)
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | step.Stop -> False
      }
    })
  let held =
    map_spawn_support.relation_of(state: scene.map, spawn: 1, connection: 1)
  let allowed = case event, held {
    OwnEvent(Told(message: map_message.Broadcast(..))),
      Some(map.Relation(state: map.Relaying, ..))
    -> True
    OwnEvent(Told(message: map_message.Snapshot(generation:, ..))),
      Some(map.Relation(
        generation: held_generation,
        state: map.AwaitingSnapshot,
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
        map_spawn_support.creature_of(state: scene.map, spawn: 1).0,
      ))
  }
}

/// The mail with what is addressed to a creature that stopped left out: a process that has
/// ended takes nothing.
fn reaching_a_running_creature(
  scene scene: Scene,
  mail mail: List(Mail),
) -> List(Mail) {
  case scene.creature {
    Some(_) -> mail
    None -> list.filter(mail, fn(sent) { sent.to != CreatureProcess })
  }
}

/// What a map's step sends to the creatures and to the viewer's connection, in order, as
/// mail.
pub fn mail_of_the_map(
  taken: step.ServiceStep(map_message.Outgoing),
) -> List(Mail) {
  mail_of_the_map_for(taken:, next_life: None)
}

/// The same when a creature of life `next_life` runs after the first: what the map sends
/// to the creature of that life is the next creature's mail.
pub fn mail_of_the_map_for(
  taken taken: step.ServiceStep(map_message.Outgoing),
  next_life next_life: Option(Int),
) -> List(Mail) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: Creature(life:, ..), message:)) ->
        result.map(creature.told_by_map(message), fn(told) {
          creature_mail(told:, to_the_next: next_life == Some(life))
        })
      OwnEffect(Send(to: step.Unit(address), message:)) ->
        case unit_address.number(address:) == 1 {
          True ->
            case server.map_message(to: step.Unit(address), outgoing: message) {
              Ok(sent) ->
                Ok(order_explorer.Mail(
                  to: ViewerProcess,
                  from: FromMap,
                  input: ToViewer(OwnEvent(Woken(sent))),
                  name: "map " <> map_outgoing_name(message),
                ))
              Error(Nil) -> Error(Nil)
            }
          False -> Error(Nil)
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
  mail_of_the_creature_as(taken:, sender: FromCreature, prefix: "")
}

/// The same for the creature that is `sender`, each mail named after `prefix`.
fn mail_of_the_creature_as(
  taken taken: step.ServiceStep(creature.Outgoing),
  sender sender: Sender,
  prefix prefix: String,
) -> List(Mail) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: step.Map(..), message:)) -> {
        let told = creature.told_to_map(outgoing: message)
        Ok(order_explorer.Mail(
          to: MapProcess,
          from: sender,
          input: ToMap(OwnEvent(Told(told))),
          name: prefix <> map_message_name(told),
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

/// The map's tell to the creature, as mail to the next creature or to the first.
fn creature_mail(
  told told: creature.Message,
  to_the_next to_the_next: Bool,
) -> Mail {
  use <- bool.guard(
    when: to_the_next,
    return: order_explorer.Mail(
      to: NextCreatureProcess,
      from: FromMap,
      input: ToNextCreature(OwnEvent(Told(told))),
      name: creature_message_name(told),
    ),
  )
  order_explorer.Mail(
    to: CreatureProcess,
    from: FromMap,
    input: ToCreature(OwnEvent(Told(told))),
    name: creature_message_name(told),
  )
}

/// The end of the creature of `life`, which its map watches: the watch's end, as one more
/// signal of the creature.
fn creature_ended(life life: Int) -> Mail {
  order_explorer.Mail(
    to: MapProcess,
    from: FromCreature,
    input: ToMap(step.WatchEnded(step.WatchId(life))),
    name: "Creature ended",
  )
}

/// The creature the step starts, if it starts one.
fn started_by(
  taken taken: step.ServiceStep(map_message.Outgoing),
) -> Result(step.CreatureStart, Nil) {
  list.find_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.StartCreature(creature:, ..)) -> Ok(creature)
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The Battle Beast of the scenes, which every creature of them is.
pub fn the_beast() -> spawn.Spawn {
  spawn_support.battle_beast(number: 1, x: 0.0)
}

fn creature_message_name(message: creature.Message) -> String {
  case message {
    creature.Seen(..) -> "Seen"
    creature.Unseen(..) -> "Unseen"
    creature.Strike(..) -> "Strike"
    creature.Retire
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
    | creature.ControlsEnd(..)
    | creature.CasterGone(..) -> "another tell"
  }
}

fn map_message_name(message: map_message.Message) -> String {
  case message {
    map_message.Snapshot(by:, ..) ->
      "Snapshot for " <> int.to_string(unit_address.rank(address: by))
    map_message.Broadcast(..) -> "Broadcast"
    map_message.Relay(
      payload: map_message.Fight(told: strike_tell.Threatened(..)),
      ..,
    ) -> "Relay Threatened"
    map_message.Relay(
      payload: map_message.Fight(told: strike_tell.Released(..)),
      ..,
    ) -> "Relay Released"
    map_message.Relay(..) -> "Relay"
    map_message.Expired(..) -> "Expired"
    map_message.Join(..)
    | map_message.Leave(..)
    | map_message.Moved(..)
    | map_message.Ready(..)
    | map_message.StealthChanged(..)
    | map_message.LifeChanged(..)
    | map_message.VisibilityChanged(..)
    | map_message.Released(..)
    | map_message.Summon(..)
    | map_message.TellCreature(..)
    | map_message.PlayerSnapshot(..)
    | map_message.PlayerBroadcast(..)
    | map_message.TellLanding(..)
    | map_message.Say(..) -> "another tell"
  }
}

fn map_outgoing_name(message: map_message.Outgoing) -> String {
  case message {
    map_message.Relayed(..) -> "Relayed"
    map_message.Noticed(notice: map_message.UnitUnseen(..)) -> "Unseen"
    map_message.Noticed(..) -> "a notice"
    map_message.Joined(..)
    | map_message.NotJoined(..)
    | map_message.Summoned(..)
    | map_message.NotSummoned(..)
    | map_message.Left
    | map_message.Seen(..)
    | map_message.Unseen(..)
    | map_message.Retire
    | map_message.Approached(..)
    | map_message.Withdrew(..)
    | map_message.PlayerDied(..)
    | map_message.CasterGone(..)
    | map_message.ToldCreature(..) -> "another send"
  }
}

/// The names of what the receiver took, in order.
pub fn order_at(
  scene scene: Scene,
  receiver receiver: Receiver,
) -> List(String) {
  order_explorer.order_at(taken: scene.taken, receiver:)
}

/// A scene whose result a test did not expect, as what the test reads of it: what each
/// process took, in order, and the result against the one wanted.
pub type Deviation {
  Deviation(
    taken_by_the_map: List(String),
    taken_by_the_creature: List(String),
    observed: List(String),
    wanted: List(String),
  )
}

/// The scenes whose `observed` result is not the one `wanted` names for them, at most three,
/// each as a `Deviation`: a test that asserts this is empty prints what went wrong in a few
/// scenes, not all of them.
pub fn deviations(
  scenes scenes: List(Scene),
  observed observed: fn(Scene) -> List(String),
  wanted wanted: fn(Scene) -> List(String),
) -> List(Deviation) {
  scenes
  |> list.filter(fn(scene) { observed(scene) != wanted(scene) })
  |> list.take(3)
  |> list.map(fn(scene) {
    Deviation(
      taken_by_the_map: order_at(scene:, receiver: MapProcess),
      taken_by_the_creature: order_at(scene:, receiver: CreatureProcess),
      observed: observed(scene),
      wanted: wanted(scene),
    )
  })
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

/// The unit a frame the scene follows names: 0x262 of a creature or a player, 0x355, 0x937, 0x88c and
/// 0x638.
pub fn unit_of(frame frame: Frame) -> Option(Int) {
  let Frame(message_id:, body:) = frame
  case message_id {
    0x0262 ->
      unit_create_creature.decode(body)
      |> result.map(fn(created) { created.unit_id })
      |> result.lazy_or(fn() {
        unit_create_player.decode(body)
        |> result.map(fn(created) { created.unit_id })
      })
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
      case dict_get(relations, map_support.address(number: 1)), shown {
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
  relations: dict.Dict(unit_address.UnitAddress, map.Relation),
  address: unit_address.UnitAddress,
) -> Option(map.Relation) {
  dict.get(relations, address) |> option.from_result
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

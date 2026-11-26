//// Players on one map, as the pure rules they are: a map and the connections of its
//// players, each with its mailbox, and every order in which the BEAM may deliver what is
//// sent, checked against the invariants a viewer's frames keep. Expected values come from
//// these places.
//// - OTP orders the signals of one sender to one receiver, and no others: a receiver's
////   mailbox holds one first-in-first-out queue for each sender, and it takes the head of
////   any of them next. A delivery of this scene is the head of one such queue. A player's
////   client is a sender of its own connection, so a message the client sends is mail of
////   its own queue.
//// - What a connection's step tells is what the server delivers it as: the same two
////   functions the server's shell uses (`client_connection.told_to_the_map`,
////   `client_connection.told_to_a_connection`, `server.map_message`).
//// - The invariants are the client's: a unit is created once and removed once, and it is
////   told no frame before its 0x262 or after its 0x355 (`opcode.0x262`, `opcode.0x355`).
////
//// ```
//// scene(map, connections) ─▶ enter(each player) ─▶ settle ─▶ mail(a client's message, a tell of a connection)
////   orders(scene) ─▶ one scene for each order of deliveries; each delivery takes one rule's
////                    step and puts what the step sends in the mail
//// check(scene) ─▶ Ok, or the first invariant a viewer's frames break
//// ```

import cast_support
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Answer, type Message}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/unit_news
import genesis_prime/server
import genesis_prime/step.{
  type ConnectionEvent, type Event, type ServiceEvent, type TimerId, CallerId,
  ConnectionId, OwnEffect, OwnEvent, TimerFired, Told, Woken,
}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import legal_order_support
import map_spawn_support
import map_support

/// The processes of the scene, each a receiver of mail.
pub type Receiver {
  MapProcess
  ConnectionProcess(connection: Int)
}

/// The senders whose queues a receiver's mailbox keeps apart: the map, a player's
/// connection, a player's client, and the timers of a player's connection.
pub type Sender {
  FromMap
  FromConnection(connection: Int)
  FromClient(connection: Int)
  FromTimer(connection: Int)
}

/// An input of one of the processes.
pub type Input {
  ToMap(event: Event(ServiceEvent(map.Message)))
  ToConnection(event: Event(ConnectionEvent(Message, Answer)))
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

/// The map's state, the state of each player's connection, what is in flight, the
/// monotonic time the next delivery is taken at, the deliveries so far in order, the
/// frames each connection wrote in order, and the cast timers each connection started that
/// are still to fire, each with the connection, the monotonic time it is due and the timer.
pub type Scene {
  Scene(
    tables: table_store.Tables,
    map: map.State,
    connections: Dict(Int, game_connection.State),
    mail: List(Mail),
    now_ms: Int,
    taken: List(Taken),
    frames: Dict(Int, List(Frame)),
    timers: List(#(Int, Int, TimerId)),
  )
}

/// A scene on the tests' map with no player, on these tables.
pub fn new(tables tables: table_store.Tables) -> Scene {
  Scene(
    tables:,
    map: connection_support.empty_map_of_world(
      map: connection_support.camp_map(),
      run: connection_support.incarnation,
    ),
    connections: dict.new(),
    mail: [],
    now_ms: 10_000,
    taken: [],
    frames: dict.new(),
    timers: [],
  )
}

/// The settings of the connections of the scene: the tests' own on the scene's tables.
fn settings(scene scene: Scene) -> game_connection.Settings {
  Settings(..connection_support.settings(), tables: scene.tables)
}

/// The player of connection `connection`, a character of the class and level, enters the
/// map standing at `place`: the connection's own steps up to the map's answer, then the
/// map's join, then the connection's entry burst. What the map and the connection sent
/// is in the mail, behind what was there; none of it is delivered.
pub fn enter(
  scene scene: Scene,
  connection connection: Int,
  class_id class_id: Int,
  level level: Int,
  place place: Place,
) -> Scene {
  let accepted =
    connection_support.feed(
      state: game_connection.new(settings(scene:)),
      event: OwnEvent(step.Accepted(
        ConnectionId(connection),
        support.peer,
        support.seed(1),
      )),
    ).0
  let #(state, asked) =
    connection_support.joining_saved(
      in_character_select: connection_support.in_select_from(accepted),
      character: Character(
        ..connection_support.world_character(),
        class_id: ClassId(class_id),
        level:,
        place: Some(place),
      ),
      saved_health: None,
    )
  let message = case connection_support.ask_request(asked) {
    client_connection.AskMap(message:, ..)
    | client_connection.AskMapRun(message:, ..) -> message
    _ -> panic as "the connection's step ends in an ask of the map"
  }
  let #(map_state, joined) =
    map.step(
      scene.map,
      support.input_at_ms(
        ms: scene.now_ms,
        event: OwnEvent(step.Asked(caller: CallerId(connection), message:)),
      ),
    )
  let assert [#(_, outgoing)] = support.replies(joined)
    as "the map answers the join once, to its caller"
  let #(state, burst) =
    connection_support.answer(
      state:,
      taken: asked,
      outcome: step.Answer(
        client_connection.FromMap(connection_support.with_the_tables_loadout(
          joined: outgoing,
          tables: scene.tables,
          class_id:,
        )),
      ),
    )
  Scene(
    ..scene,
    map: map_state,
    connections: dict.insert(scene.connections, connection, state),
    mail: list.flatten([
      scene.mail,
      mail_of_the_map(taken: joined),
      mail_of_the_connection(connection:, taken: burst),
    ]),
    frames: frames_added(
      frames: scene.frames,
      connection:,
      added: connection_support.heard(
        taken: burst,
        cipher: connection_support.keyed(),
      ),
    ),
    timers: timers_after(
      timers: scene.timers,
      connection:,
      now_ms: scene.now_ms,
      taken: burst,
    ),
  )
}

/// The cast timers still to fire after the connection's step at `now_ms`: the ones it
/// started, less the ones it cancelled.
fn timers_after(
  timers timers: List(#(Int, Int, TimerId)),
  connection connection: Int,
  now_ms now_ms: Int,
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(#(Int, Int, TimerId)) {
  let effects = support.effects_of(taken)
  let cancelled =
    list.filter_map(effects, fn(effect) {
      case effect {
        OwnEffect(step.CancelTimer(timer:)) -> Ok(timer)
        _ -> Error(Nil)
      }
    })
  let kept =
    list.filter(timers, fn(held) {
      !{ held.0 == connection && list.contains(cancelled, held.2) }
    })
  let started =
    list.filter_map(effects, fn(effect) {
      case effect {
        OwnEffect(step.StartTimer(timer:, after_ms:)) ->
          case cast_state.owns(timer:) {
            True -> Ok(#(connection, now_ms + after_ms, timer))
            False -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    })
  list.append(kept, started)
}

/// The cast timers that are due by `until_ms` delivered to their connections in time order
/// (the timers a delivery starts are fired too when they are due), the clock standing at each
/// timer's due time. What the steps sent is left in the mail.
pub fn fire_timers(scene scene: Scene, until_ms until_ms: Int) -> Scene {
  case
    list.sort(scene.timers, fn(first, second) { int.compare(first.1, second.1) })
  {
    [#(connection, due, timer) as first, ..] if due <= until_ms -> {
      let scene =
        Scene(
          ..scene,
          timers: list.filter(scene.timers, fn(held) { held != first }),
          now_ms: int.max(scene.now_ms, due - 1),
        )
      fire_timers(
        scene: deliver(
          scene:,
          mail: Mail(
            to: ConnectionProcess(connection),
            from: FromTimer(connection),
            input: ToConnection(OwnEvent(TimerFired(timer:))),
            name: "timer of " <> int_name(connection),
          ),
        ),
        until_ms:,
      )
    }
    _ -> scene
  }
}

/// A message a player's client sends its connection, as mail of the client's queue.
pub fn client_sends(
  scene scene: Scene,
  connection connection: Int,
  bytes bytes: BitArray,
  name name: String,
) -> Scene {
  Scene(
    ..scene,
    mail: list.append(scene.mail, [
      Mail(
        to: ConnectionProcess(connection),
        from: FromClient(connection),
        input: ToConnection(OwnEvent(step.Read(bytes))),
        name:,
      ),
    ]),
  )
}

/// The tell of the connection `connection` to the map that its player now stands at
/// `place`, as its connection's accepted 0x637 sends it, as mail of the connection's queue
/// to the map.
pub fn tells_the_map_it_moved(
  scene scene: Scene,
  connection connection: Int,
  place place: Place,
  seq seq: Int,
) -> Scene {
  Scene(
    ..scene,
    mail: list.append(scene.mail, [
      Mail(
        to: MapProcess,
        from: FromConnection(connection),
        input: ToMap(
          OwnEvent(
            Told(message: map.Moved(
              connection: ConnectionId(connection),
              place:,
              seq:,
            )),
          ),
        ),
        name: "Moved by " <> int_name(connection),
      ),
    ]),
  )
}

fn int_name(number: Int) -> String {
  int.to_string(number)
}

/// The state of a connection of the scene.
pub fn connection_state(
  scene scene: Scene,
  connection connection: Int,
) -> game_connection.State {
  let assert Ok(state) = dict.get(scene.connections, connection)
    as "the player entered the scene"
  state
}

/// The frames the connection wrote, in order, from the first.
pub fn frames_of(
  scene scene: Scene,
  connection connection: Int,
) -> List(Frame) {
  dict.get(scene.frames, connection) |> result.unwrap([])
}

fn frames_added(
  frames frames: Dict(Int, List(Frame)),
  connection connection: Int,
  added added: List(Frame),
) -> Dict(Int, List(Frame)) {
  dict.insert(
    frames,
    connection,
    list.append(dict.get(frames, connection) |> result.unwrap([]), added),
  )
}

/// What a map's step sends to the players' connections, in order, as mail of the map's
/// queues.
pub fn mail_of_the_map(
  taken taken: step.ServiceStep(map.Outgoing),
) -> List(Mail) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Send(to: step.Connection(ConnectionId(number)), message:)) ->
        case server.map_message(outgoing: message) {
          Ok(sent) ->
            Ok(Mail(
              to: ConnectionProcess(number),
              from: FromMap,
              input: ToConnection(OwnEvent(Woken(sent))),
              name: "map "
                <> outgoing_name(message:)
                <> " to "
                <> int_name(number),
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

/// What a connection's step tells the map and the connections of other players, in
/// order, as mail of the connection's queues.
pub fn mail_of_the_connection(
  connection connection: Int,
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(Mail) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(to: step.Map(..), request:)) ->
        client_connection.told_to_the_map(request:)
        |> result.map(fn(message) {
          Mail(
            to: MapProcess,
            from: FromConnection(connection),
            input: ToMap(OwnEvent(Told(message:))),
            name: "tell of "
              <> int_name(connection)
              <> " to the map: "
              <> request_name(request:),
          )
        })
      OwnEffect(step.Tell(to: step.Connection(ConnectionId(other)), request:)) ->
        client_connection.told_to_a_connection(request:)
        |> result.map(fn(message) {
          Mail(
            to: ConnectionProcess(other),
            from: FromConnection(connection),
            input: ToConnection(OwnEvent(Woken(message))),
            name: "tell of "
              <> int_name(connection)
              <> " to "
              <> int_name(other)
              <> ": "
              <> request_name(request:),
          )
        })
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The name of a request, as the mail's name says it.
pub fn request_name(request request: client_connection.Request) -> String {
  case request {
    client_connection.TellMoved(..) -> "Moved"
    client_connection.TellPeer(news:, ..) ->
      "TellPeer " <> unit_news_name(news: news.news)
    client_connection.TellMove(..) -> "TellMove"
    client_connection.TellBroadcast(news:, ..) ->
      "TellBroadcast " <> unit_news_name(news: news.news)
    client_connection.TellSnapshot(..) -> "TellSnapshot"
    client_connection.TellLanding(..) -> "TellLanding"
    client_connection.TellSay(..) -> "TellSay"
    client_connection.TellPlayer(..) -> "TellPlayer"
    client_connection.TellLine(..) -> "TellLine"
    client_connection.TellChat(..) -> "TellChat"
    client_connection.TellReady(..) -> "TellReady"
    client_connection.TellStealthChanged(..) -> "TellStealthChanged"
    client_connection.TellLifeChanged(..) -> "TellLifeChanged"
    client_connection.TellVisibilityChanged(..) -> "TellVisibilityChanged"
    client_connection.TellReleased(..) -> "TellReleased"
    client_connection.TellCreature(..) -> "TellCreature"
    client_connection.AskStore(..)
    | client_connection.AskHandOff(..)
    | client_connection.AskSessions(..)
    | client_connection.AskMap(..)
    | client_connection.AskMapRun(..) -> "an ask"
  }
}

/// The constructor of the news, as the mail's name says it, for the news a scene's tests tell
/// apart.
fn unit_news_name(news news: unit_news.News) -> String {
  case news {
    unit_news.Appeared(..) -> "Appeared"
    unit_news.Departed(..) -> "Departed"
    unit_news.CastStarted(..) -> "CastStarted"
    unit_news.CastWent(..) -> "CastWent"
    unit_news.CastFinished(..) -> "CastFinished"
    unit_news.HeldCastStarted(..) -> "HeldCastStarted"
    unit_news.HeldCastEnded(..) -> "HeldCastEnded"
    unit_news.Health(..) -> "Health"
    _ -> "another news"
  }
}

/// The name of what a map sends, as the mail's name says it.
fn outgoing_name(message message: map.Outgoing) -> String {
  case message {
    map.Noticed(notice: map.SeenBy(..), ..) -> "SeenBy"
    map.Noticed(notice: map.UnseenBy(..), ..) -> "UnseenBy"
    map.Noticed(notice: map.PlayerUnseen(..), ..) -> "PlayerUnseen"
    map.Noticed(notice: map.Gone(..), ..) -> "Gone"
    map.Noticed(..) -> "a notice"
    map.Relayed(..) -> "Relayed"
    _ -> "another send"
  }
}

/// The scene without the settle: the deliveries the scene allows now, the head of each
/// queue, one for each receiver and sender, in the order they were sent.
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

/// The most scenes `orders` explores exhaustively: a scene with more distinct states is
/// sampled instead.
const exhaustive_limit = 400

/// How many orders `orders` samples from a scene it cannot explore exhaustively.
const sampled_orders = 16

/// The scenes the deliveries can end in: each order that takes the head of one queue at a
/// time until no mail is left. Two orders in which each receiver takes the same messages in
/// the same order are one scene (a receiver's steps change only itself and the mail it
/// sends), so the scenes are the distinct sequences each receiver takes. A scene with more
/// than `exhaustive_limit` distinct states is not explored exhaustively: `sampled_orders`
/// orders are walked instead, each choosing among the heads by a fixed pseudo-random
/// sequence, so the same orders are walked every run. A delivery with no other order to
/// compete with is made at once: a receiver whose mailbox holds one queue head, and no other
/// process has mail it could still send to it, takes that head first in every order, so it is
/// not branched on.
pub fn orders(scene scene: Scene) -> List(Scene) {
  case explore(scene:, seen: set.new(), finished: []) {
    Ok(#(finished, _)) -> list.reverse(finished)
    Error(Nil) -> sampled(scene:)
  }
}

fn explore(
  scene scene: Scene,
  seen seen: Set(String),
  finished finished: List(Scene),
) -> Result(#(List(Scene), Set(String)), Nil) {
  use <- bool.guard(when: set.size(seen) > exhaustive_limit, return: Error(Nil))
  let key = state_key(scene:)
  use <- bool.guard(
    when: set.contains(seen, key),
    return: Ok(#(finished, seen)),
  )
  let seen = set.insert(seen, key)
  let heads = deliverable(scene:)
  case list.find(heads, fn(mail) { has_no_rival(scene:, mail:, heads:) }) {
    Ok(mail) -> explore(scene: deliver(scene:, mail:), seen:, finished:)
    Error(Nil) ->
      case heads {
        [] -> Ok(#([scene, ..finished], seen))
        _ ->
          list.try_fold(heads, #(finished, seen), fn(so_far, mail) {
            explore(
              scene: deliver(scene:, mail:),
              seen: so_far.1,
              finished: so_far.0,
            )
          })
      }
  }
}

/// `sampled_orders` orders of the scene, distinct, each walked by choosing the next head
/// with a fixed pseudo-random sequence of its own.
fn sampled(scene scene: Scene) -> List(Scene) {
  list.repeat(Nil, sampled_orders)
  |> list.index_map(fn(_, index) { walk(scene:, seed: { index + 1 } * 7919) })
  |> list.fold(#([], set.new()), fn(so_far, done) {
    let key = state_key(scene: done)
    case set.contains(so_far.1, key) {
      True -> so_far
      False -> #([done, ..so_far.0], set.insert(so_far.1, key))
    }
  })
  |> fn(found) { list.reverse(found.0) }
}

fn walk(scene scene: Scene, seed seed: Int) -> Scene {
  case deliverable(scene:) {
    [] -> scene
    heads -> {
      let next = { seed * 1_103_515_245 + 12_345 } % 2_147_483_648
      let assert Ok(mail) =
        list.drop(heads, next % list.length(heads)) |> list.first
        as "a pick among the heads is one of them"
      walk(scene: deliver(scene:, mail:), seed: next)
    }
  }
}

/// What a scene is for the orders: what each receiver took, in order, and the mail still in
/// flight, each message named by its sender and its name.
fn state_key(scene scene: Scene) -> String {
  let taken =
    list.fold(scene.taken, dict.new(), fn(by_receiver, taken) {
      let key = receiver_name(receiver: taken.by)
      dict.insert(
        by_receiver,
        key,
        list.append(dict.get(by_receiver, key) |> result.unwrap([]), [
          sender_name(sender: taken.from) <> " " <> taken.name,
        ]),
      )
    })
  string.join(
    list.map(
      list.sort(dict.to_list(taken), fn(first, second) {
        string.compare(first.0, second.0)
      }),
      fn(entry) { entry.0 <> ": " <> string.join(entry.1, "; ") },
    ),
    " | ",
  )
  <> " || "
  <> string.join(
    list.map(scene.mail, fn(mail) {
      receiver_name(receiver: mail.to)
      <> " from "
      <> sender_name(sender: mail.from)
      <> " "
      <> mail.name
    }),
    "; ",
  )
}

/// The name of a receiver, for a key.
fn receiver_name(receiver receiver: Receiver) -> String {
  case receiver {
    MapProcess -> "map"
    ConnectionProcess(connection:) -> "connection " <> int.to_string(connection)
  }
}

/// The name of a sender, for a key.
fn sender_name(sender sender: Sender) -> String {
  case sender {
    FromMap -> "map"
    FromConnection(connection:) -> "connection " <> int.to_string(connection)
    FromClient(connection:) -> "client " <> int.to_string(connection)
    FromTimer(connection:) -> "timer " <> int.to_string(connection)
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

/// Whether the mail's receiver has only this head now and no other process has mail to take,
/// so no other message can reach the receiver before this one.
fn has_no_rival(
  scene scene: Scene,
  mail mail: Mail,
  heads heads: List(Mail),
) -> Bool {
  let alone = list.count(heads, fn(head) { head.to == mail.to }) == 1
  let others_are_busy =
    list.any(scene.mail, fn(waiting) {
      waiting.to != mail.to && !is_external(waiting.from)
    })
  alone && !others_are_busy
}

/// Whether the sender is a client, which sends only when a test says so.
fn is_external(sender: Sender) -> Bool {
  case sender {
    FromClient(..) -> False
    FromMap | FromConnection(..) | FromTimer(..) -> False
  }
}

/// The scene after the receiver takes the mail: its rule's step, and what the step sends
/// put in the mail behind what is there.
pub fn deliver(scene scene: Scene, mail mail: Mail) -> Scene {
  let now_ms = scene.now_ms + 1
  let scene =
    Scene(
      ..scene,
      mail: remove_first(scene.mail, mail),
      now_ms:,
      taken: list.append(scene.taken, [
        Taken(by: mail.to, from: mail.from, name: mail.name),
      ]),
    )
  case mail.input, mail.to {
    ToMap(event:), _ -> {
      let #(state, taken) =
        map.step(scene.map, support.input_at_ms(ms: now_ms, event:))
      Scene(
        ..scene,
        map: state,
        mail: list.append(scene.mail, mail_of_the_map(taken:)),
      )
    }
    ToConnection(event:), ConnectionProcess(connection:) -> {
      let #(state, taken) =
        connection_support.feed_at(
          state: connection_state(scene:, connection:),
          filetime: connection_support.filetime + now_ms * 10_000,
          event:,
        )
      Scene(
        ..scene,
        connections: dict.insert(scene.connections, connection, state),
        mail: list.append(
          scene.mail,
          mail_of_the_connection(connection:, taken:),
        ),
        frames: frames_added(
          frames: scene.frames,
          connection:,
          added: connection_support.heard(
            taken:,
            cipher: connection_support.keyed(),
          ),
        ),
        timers: timers_after(timers: scene.timers, connection:, now_ms:, taken:),
      )
    }
    ToConnection(..), MapProcess ->
      panic as "mail of a connection is never to the map"
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

/// The names of what the receiver took, in order.
pub fn order_at(
  scene scene: Scene,
  receiver receiver: Receiver,
) -> List(String) {
  list.filter(scene.taken, fn(taken) { taken.by == receiver })
  |> list.map(fn(taken) { taken.name })
}

/// The first invariant a connection's frames break, or `Ok(Nil)`: a frame is checked
/// against the units the frames before it created and removed
/// (`legal_order_support.check_frames`).
pub fn check(
  scene scene: Scene,
  connection connection: Int,
) -> Result(Nil, legal_order_support.Violation) {
  legal_order_support.check_frames(frames: frames_of(scene:, connection:))
}

/// The frames the connection wrote that name the unit `unit_id`, as
/// `legal_order_support.names` writes them (`0x262(7)`), in order, so a test states what a
/// viewer was written.
pub fn written_for(
  scene scene: Scene,
  connection connection: Int,
  unit_id unit_id: Int,
) -> List(String) {
  let wanted = "(" <> int_name(unit_id) <> ")"
  legal_order_support.names(frames: frames_of(scene:, connection:))
  |> list.filter(fn(name) { string.ends_with(name, wanted) })
}

/// A place of the scene's map `x` along the x axis of Warfare Woods.
pub fn at(x x: Float) -> Place {
  map_spawn_support.at(x)
}

/// What the connection `from` told the connection `to` directly, by name, in order: a
/// player tells another player only through the map, except its own moves, so a test of
/// the streams asks for none.
pub fn direct_news(
  scene scene: Scene,
  from from: Int,
  to to: Int,
) -> List(String) {
  list.filter_map(scene.taken, fn(taken) {
    case taken {
      Taken(
        by: ConnectionProcess(receiver),
        from: FromConnection(sender),
        name:,
      )
        if receiver == to && sender == from
      ->
        case string.contains(name, "TellMove") {
          True -> Error(Nil)
          False -> Ok(name)
        }
      Taken(..) -> Error(Nil)
    }
  })
}

/// The client's press (0x009A) of the bag index at the unit `target`, as mail of the
/// client's queue.
pub fn client_presses(
  scene scene: Scene,
  connection connection: Int,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  target target: Int,
) -> Scene {
  client_sends(
    scene:,
    connection:,
    bytes: connection_support.world_message(
      message_id: 0x009A,
      body: cast_support.press_body(
        client_cast_id:,
        bag_index:,
        target:,
        press: 1,
      ),
    ),
    name: "press by " <> int_name(connection),
  )
}

/// The snapshot of the sight `generation` that `viewer` has of the owner, as the owner's
/// connection tells the map, with one item, a health that no real snapshot holds: mail of
/// the owner's queue to the map, which a test uses for a snapshot that comes late.
pub fn tells_the_map_a_snapshot(
  scene scene: Scene,
  owner owner: Int,
  viewer viewer: Int,
  generation generation: Generation,
) -> Scene {
  Scene(
    ..scene,
    mail: list.append(scene.mail, [
      Mail(
        to: MapProcess,
        from: FromConnection(owner),
        input: ToMap(
          OwnEvent(
            Told(
              message: map.PlayerSnapshot(
                by: ConnectionId(owner),
                stay: map_support.stay(count: 1),
                viewer: ConnectionId(viewer),
                generation:,
                burst: [
                  unit_news.PeerNews(
                    unit_id: owner,
                    news: unit_news.Health(health: 12_345, dead: False),
                  ),
                ],
              ),
            ),
          ),
        ),
        name: "stale snapshot of " <> int_name(owner),
      ),
    ]),
  )
}

/// An event of a connection that comes from no other process of the scene, as mail of the
/// client's queue: a creature's strike, say.
pub fn connection_is_told(
  scene scene: Scene,
  connection connection: Int,
  event event: Event(ConnectionEvent(Message, Answer)),
  name name: String,
) -> Scene {
  Scene(
    ..scene,
    mail: list.append(scene.mail, [
      Mail(
        to: ConnectionProcess(connection),
        from: FromClient(connection),
        input: ToConnection(event),
        name:,
      ),
    ]),
  )
}

/// The ids of the cast frames (0x7ff, 0x7f4, 0x7fe, 0x811) the connection wrote, in order.
pub fn cast_frames(
  scene scene: Scene,
  connection connection: Int,
) -> List(Int) {
  list.filter_map(frames_of(scene:, connection:), fn(frame) {
    case frame.message_id {
      0x07FF | 0x07F4 | 0x07FE | 0x0811 -> Ok(frame.message_id)
      _ -> Error(Nil)
    }
  })
}

/// An input of the map from another process, as mail of that sender's queue: the end of a
/// connection's process, say, which reaches the map as one more signal of that connection.
pub fn map_is_told(
  scene scene: Scene,
  from from: Sender,
  event event: Event(ServiceEvent(map.Message)),
  name name: String,
) -> Scene {
  Scene(
    ..scene,
    mail: list.append(scene.mail, [
      Mail(to: MapProcess, from:, input: ToMap(event), name:),
    ]),
  )
}

/// The player of connection `connection` joins the map a second time, in the stay `stay`,
/// at `place`, as its connection asks: the map's step is taken at once and what it sends is
/// left in the mail. The connection itself is not stepped.
pub fn join_again(
  scene scene: Scene,
  connection connection: Int,
  stay stay: Stay,
  place place: Place,
) -> Scene {
  let #(map_state, taken) =
    map.step(
      scene.map,
      support.input_at_ms(
        ms: scene.now_ms,
        event: OwnEvent(step.Asked(
          caller: CallerId(connection),
          message: map.Join(
            connection: ConnectionId(connection),
            character: connection_support.world_character(),
            place:,
            stay:,
            alive: True,
            hidden: set.new(),
          ),
        )),
      ),
    )
  Scene(
    ..scene,
    map: map_state,
    mail: list.append(scene.mail, mail_of_the_map(taken:)),
  )
}

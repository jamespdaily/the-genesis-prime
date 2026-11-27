//// Players on one map, as the pure rules they are: a map and the connections of its
//// players, each with its mailbox, and every order in which the BEAM may deliver what is
//// sent, checked against the invariants a viewer's frames keep. Expected values come from
//// these places.
//// - OTP orders the signals of one sender to one receiver, and no others: a receiver's
////   mailbox holds one first-in-first-out queue for each sender, and it takes the head of
////   any of them next. A delivery of this scene is the head of one such queue
////   (`order_explorer`, which also walks the orders). A player's client is a sender of its
////   own connection, so a message the client sends is mail of its own queue. Each process
////   keeps a clock of its own.
//// - What a connection's step tells is what the server delivers it as: the same two
////   functions the server's shell uses (`client_connection.told_to_the_map`,
////   `client_connection.told_to_a_connection`, `server.map_message`).
//// - A connection that asks the map takes no other input until the answer: the shell waits
////   for it in a selective receive (`connection/shell` "An ask"), and the answer is no
////   message of the map's ordinary queue to that connection. An ask is mail of the asking
////   connection's queue to the map, its answer mail of the answer's own queue, and the mail
////   of an asking connection waits. The store answers an ask at once: a worker's answer is
////   taken by the same wait, so nothing is lost by taking it in the step that asked.
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
import creature_news_support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Answer, type Message}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/unit_news
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/server
import genesis_prime/step.{
  type ConnectionEvent, type Event, type ServiceEvent, type TimerId, CallerId,
  ConnectionId, OwnEffect, OwnEvent, TimerFired, Told, Woken,
}
import genesis_prime/store.{type Character, Character}
import genesis_prime/table/id.{ClassId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map
import genesis_prime/world_map/relay
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import legal_order_support
import map_spawn_support
import order_explorer

/// The processes of the scene, each a receiver of mail.
pub type Receiver {
  MapProcess
  ConnectionProcess(connection: Int)
}

/// The senders whose queues a receiver's mailbox keeps apart: the map, a player's
/// connection, a player's client, and the timers of a player's connection.
pub type Sender {
  FromMap
  FromMapAnswer
  FromConnection(connection: Int)
  FromClient(connection: Int)
  FromTimer(connection: Int)
}

/// An input of one of the processes.
pub type Input {
  ToMap(event: Event(ServiceEvent(map.Message)))
  ToConnection(event: Event(ConnectionEvent(Message, Answer)))
  /// The client of a connection in character select picks the character, the store
  /// answers with its rows, and the connection asks the map to take it.
  ToConnectionSelecting(character: Character)
}

/// One message in a mailbox (`order_explorer.Mail`) of this scene.
pub type Mail =
  order_explorer.Mail(Receiver, Sender, Input)

/// What a receiver took (`order_explorer.Taken`) in this scene.
pub type Taken =
  order_explorer.Taken(Receiver, Sender)

/// The map's state, the state of each player's connection, what is in flight, the
/// monotonic clock of each process, the deliveries so far in order, the
/// frames each connection wrote in order, the cast timers each connection started that
/// are still to fire, each with the connection, the monotonic time it is due and the timer,
/// and the ask of the map each connection waits for the answer to.
pub type Scene {
  Scene(
    tables: table_store.Tables,
    map: map.State,
    connections: Dict(Int, game_connection.State),
    mail: List(Mail),
    clocks: order_explorer.Clocks(Receiver),
    taken: List(Taken),
    frames: Dict(Int, List(Frame)),
    timers: List(#(Int, Int, TimerId)),
    asking: Dict(Int, step.Ask(client_connection.Request)),
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
    clocks: order_explorer.clocks(start_ms: 10_000),
    taken: [],
    frames: dict.new(),
    timers: [],
    asking: dict.new(),
  )
}

/// The settings of the connections of the scene: the tests' own on the scene's tables.
fn settings(scene scene: Scene) -> game_connection.Settings {
  Settings(..connection_support.settings(), tables: scene.tables)
}

/// The character of the class and level the scene's players are, standing at `place`.
pub fn character_of(
  class_id class_id: Int,
  level level: Int,
  place place: Place,
) -> Character {
  Character(
    ..connection_support.world_character(),
    class_id: ClassId(class_id),
    level:,
    place: Some(place),
  )
}

/// The player of connection `connection`, a character of the class and level, enters the
/// map standing at `place`: the connection's own steps up to the map's answer, then the
/// map's join, then the connection's entry burst. What the map and the connection sent
/// is in the mail, behind what was there; none of it is delivered. A connection the scene
/// holds already enters again from its own state, camped out to character select, so its
/// join names the stay after its last, and the map, which has not taken its leave, takes
/// the join as a player that joins again.
pub fn enter(
  scene scene: Scene,
  connection connection: Int,
  class_id class_id: Int,
  level level: Int,
  place place: Place,
) -> Scene {
  let in_select = case dict.get(scene.connections, connection) {
    Ok(held) -> connection_support.camp_from(held)
    Error(Nil) -> {
      let accepted =
        connection_support.feed(
          state: game_connection.new(settings(scene:)),
          event: OwnEvent(step.Accepted(
            ConnectionId(connection),
            support.peer,
            support.seed(1),
          )),
        ).0
      connection_support.in_select_from(accepted)
    }
  }
  let #(state, asked) =
    connection_support.joining_saved(
      in_character_select: in_select,
      character: character_of(class_id:, level:, place:),
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
        ms: order_explorer.now_ms(clocks: scene.clocks, receiver: MapProcess),
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
      now_ms: order_explorer.now_ms(
        clocks: scene.clocks,
        receiver: ConnectionProcess(connection),
      ),
      taken: burst,
    ),
    asking: dict.delete(scene.asking, connection),
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

/// The cast timers that are due within `within_ms` of their connection's clock as it stands
/// delivered to their connections in time order (the timers a delivery starts are fired too
/// when they are due), each connection's clock standing at its timer's due time. What the
/// steps sent is left in the mail.
pub fn fire_timers(scene scene: Scene, within_ms within_ms: Int) -> Scene {
  let horizons =
    dict.map_values(scene.connections, fn(connection, _) {
      order_explorer.now_ms(
        clocks: scene.clocks,
        receiver: ConnectionProcess(connection),
      )
      + within_ms
    })
  fire_timers_due(scene:, horizons:)
}

fn fire_timers_due(
  scene scene: Scene,
  horizons horizons: Dict(Int, Int),
) -> Scene {
  let due_within_horizon =
    list.filter(scene.timers, fn(held) {
      held.1 <= { dict.get(horizons, held.0) |> result.unwrap(0) }
    })
  case
    list.sort(due_within_horizon, fn(first, second) {
      int.compare(first.1, second.1)
    })
  {
    [#(connection, due, timer) as first, ..] -> {
      let receiver = ConnectionProcess(connection)
      let scene =
        Scene(
          ..scene,
          timers: list.filter(scene.timers, fn(held) { held != first }),
          clocks: order_explorer.advanced_to(
            clocks: scene.clocks,
            receiver:,
            ms: due - 1,
          ),
        )
      fire_timers_due(
        scene: deliver(
          scene:,
          mail: order_explorer.Mail(
            to: receiver,
            from: FromTimer(connection),
            input: ToConnection(OwnEvent(TimerFired(timer:))),
            name: "timer of " <> int_name(connection),
          ),
        ),
        horizons:,
      )
    }
    [] -> scene
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
      order_explorer.Mail(
        to: ConnectionProcess(connection),
        from: FromClient(connection),
        input: ToConnection(OwnEvent(step.Read(bytes))),
        name:,
      ),
    ]),
  )
}

/// The client of a connection in character select picks the character, as mail of the
/// client's queue.
pub fn client_selects(
  scene scene: Scene,
  connection connection: Int,
  character character: Character,
) -> Scene {
  Scene(
    ..scene,
    mail: list.append(scene.mail, [
      order_explorer.Mail(
        to: ConnectionProcess(connection),
        from: FromClient(connection),
        input: ToConnectionSelecting(character:),
        name: "client of " <> int_name(connection) <> " picks its character",
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
      order_explorer.Mail(
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
            Ok(order_explorer.Mail(
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

/// What a map's step answers to the connections that asked it, as mail of the answer's own
/// queue to each (the ask the connection waits for, `Scene.asking`): the map's reply, with
/// the loadout the scene's tables give a joined character's class.
fn answers_of_the_map(
  scene scene: Scene,
  taken taken: step.ServiceStep(map.Outgoing),
) -> List(Mail) {
  list.map(support.replies(taken), fn(reply) {
    let #(CallerId(number), outgoing) = reply
    let assert Ok(ask) = dict.get(scene.asking, number)
      as "a reply of the map names a connection that waits for it"
    let answer = case ask.request, outgoing {
      client_connection.AskMap(message: map.Join(character:, ..), ..),
        map.Joined(..)
      | client_connection.AskMapRun(message: map.Join(character:, ..), ..),
        map.Joined(..)
      -> {
        let ClassId(class_id) = character.class_id
        connection_support.with_the_tables_loadout(
          joined: outgoing,
          tables: scene.tables,
          class_id:,
        )
      }
      _, _ -> outgoing
    }
    order_explorer.Mail(
      to: ConnectionProcess(number),
      from: FromMapAnswer,
      input: ToConnection(
        OwnEvent(step.Answered(
          ask: ask.ask,
          outcome: step.Answer(client_connection.FromMap(answer)),
        )),
      ),
      name: "map answers " <> int_name(number) <> ": " <> answer_name(answer:),
    )
  })
}

/// The name of what a map answers, as the mail's name says it.
fn answer_name(answer answer: map.Outgoing) -> String {
  case answer {
    map.Joined(..) -> "Joined"
    map.Left -> "Left"
    _ -> "another answer"
  }
}

/// What a connection's step tells the map and the connections of other players, in
/// order, and the ask of the map it ends in, as mail of the connection's queues.
pub fn mail_of_the_connection(
  connection connection: Int,
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(Mail) {
  list.append(
    tells_of_the_connection(connection:, taken:),
    case support.asked(taken) {
      Some(step.Ask(request: client_connection.AskMap(message:, ..), ..))
      | Some(step.Ask(request: client_connection.AskMapRun(message:, ..), ..)) -> [
        order_explorer.Mail(
          to: MapProcess,
          from: FromConnection(connection),
          input: ToMap(
            OwnEvent(step.Asked(caller: CallerId(connection), message:)),
          ),
          name: "ask of " <> int_name(connection) <> ": " <> ask_name(message:),
        ),
      ]
      Some(step.Ask(request: client_connection.AskStore(..), ..)) | None -> []
      Some(step.Ask(request:, ..)) ->
        panic as {
          "a connection of the scene asks the map or the store; it asked "
          <> request_name(request:)
        }
    },
  )
}

/// The name of what a connection asks the map, as the mail's name says it.
fn ask_name(message message: map.Message) -> String {
  case message {
    map.Join(..) -> "Join"
    map.Leave(..) -> "Leave"
    _ -> "another ask"
  }
}

fn tells_of_the_connection(
  connection connection: Int,
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(Mail) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(to: step.Map(..), request:)) ->
        client_connection.told_to_the_map(request:)
        |> result.map(fn(message) {
          order_explorer.Mail(
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
          order_explorer.Mail(
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
    client_connection.TellMove(..) -> "TellMove"
    client_connection.TellBroadcast(news:, ..) ->
      "TellBroadcast " <> unit_news_name(news: news.news)
    client_connection.TellSnapshot(..) -> "TellSnapshot"
    client_connection.TellLanding(..) -> "TellLanding"
    client_connection.TellSay(..) -> "TellSay"
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
    map.Relayed(
      delivered: relay.News(news: unit_news.PeerNews(unit_id:, news:)),
      ..,
    ) ->
      "Relayed "
      <> case news {
        unit_news.Appeared(..) -> "0x262"
        unit_news.HeldCastStarted(..) -> "held start"
        unit_news.HeldCastEnded(..) -> "held end"
        _ -> creature_news_support.name_of(news)
      }
      <> " of "
      <> int.to_string(unit_id)
    map.Relayed(delivered: relay.Landed(landing:), ..) ->
      "Relayed " <> landing_name(landing:)
    map.Relayed(delivered: relay.Said(..), ..) -> "Relayed line"
    map.Relayed(..) -> "Relayed"
    _ -> "another send"
  }
}

/// The name of a landing, as the mail's name says it.
fn landing_name(landing landing: relay.Landing) -> String {
  case landing {
    relay.HealStrike(..) -> "heal strike"
    relay.HealAnswer(..) -> "heal answer"
    relay.ChangeStart(..) -> "change start"
    relay.ChangeEnd(..) -> "change end"
    relay.CastWent(..) -> "cast went"
    relay.AllyEvent(..) -> "ally event"
  }
}

/// The name of a receiver, as the order of the walk reads it.
fn receiver_name(receiver receiver: Receiver) -> String {
  case receiver {
    MapProcess -> "map"
    ConnectionProcess(connection:) -> "connection " <> int.to_string(connection)
  }
}

/// The name of a sender, as the order of the walk reads it.
fn sender_name(sender sender: Sender) -> String {
  case sender {
    FromMap -> "map"
    FromMapAnswer -> "the map's answer"
    FromConnection(connection:) -> "connection " <> int.to_string(connection)
    FromClient(connection:) -> "client " <> int.to_string(connection)
    FromTimer(connection:) -> "timer " <> int.to_string(connection)
  }
}

/// The scheduler of the scene's processes (`order_explorer`).
fn scheduler() -> order_explorer.Scheduler(Scene, Receiver, Sender, Input) {
  order_explorer.Scheduler(
    mail: takeable,
    in_flight: fn(scene: Scene) { scene.mail },
    deliver:,
    taken: fn(scene: Scene) { scene.taken },
    same_state:,
    queue_name: fn(receiver, sender) {
      receiver_name(receiver:) <> " from " <> sender_name(sender:)
    },
  )
}

/// The mail a receiver may take now: all of it, except that a connection waiting for the
/// map's answer takes that answer alone, and the rest of its mail waits.
fn takeable(scene scene: Scene) -> List(Mail) {
  list.filter(scene.mail, fn(mail) {
    case mail.to {
      ConnectionProcess(connection:) ->
        !dict.has_key(scene.asking, connection) || mail.from == FromMapAnswer
      MapProcess -> True
    }
  })
}

/// The deliveries the scene allows now: the head of each queue, one for each receiver and
/// sender, in the order they were sent.
pub fn deliverable(scene scene: Scene) -> List(Mail) {
  order_explorer.heads(mail: takeable(scene:))
}

/// The scenes the deliveries can end in, one for each outcome: each order that takes the
/// head of one queue at a time until no mail is left, the deliveries to different
/// processes not ordered against each other (`order_explorer.orders`).
pub fn orders(scene scene: Scene) -> List(Scene) {
  order_explorer.orders(scheduler: scheduler(), scene:)
}

/// The scenes of `orders` with every two deliveries to one receiver taken as dependent
/// (`order_explorer.orders_by_receiver`).
pub fn orders_by_receiver(scene scene: Scene) -> List(Scene) {
  order_explorer.orders_by_receiver(scheduler: scheduler(), scene:)
}

/// Whether two scenes hold the same state in the map and every connection: the same map,
/// connections, frames, timers, asks and clocks, whatever order was taken to reach them.
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
  let #(clocks, now_ms) =
    order_explorer.ticked(clocks: scene.clocks, receiver: mail.to)
  let scene =
    Scene(
      ..scene,
      mail: order_explorer.remove_first(mail: scene.mail, taken: mail),
      clocks:,
      taken: list.append(scene.taken, [
        order_explorer.Taken(by: mail.to, from: mail.from, name: mail.name),
      ]),
    )
  case mail.input, mail.to {
    ToMap(event:), _ -> {
      let #(state, taken) =
        map.step(scene.map, support.input_at_ms(ms: now_ms, event:))
      Scene(
        ..scene,
        map: state,
        mail: list.flatten([
          scene.mail,
          mail_of_the_map(taken:),
          answers_of_the_map(scene:, taken:),
        ]),
      )
    }
    ToConnection(event:), ConnectionProcess(connection:) -> {
      let #(state, taken) =
        connection_support.feed_at(
          state: connection_state(scene:, connection:),
          filetime: filetime_at(now_ms:),
          event:,
        )
      connection_stepped(scene:, connection:, state:, taken:, now_ms:)
    }
    ToConnectionSelecting(character:), ConnectionProcess(connection:) -> {
      let #(state, taken) =
        connection_support.joining_saved(
          in_character_select: connection_state(scene:, connection:),
          character:,
          saved_health: None,
        )
      connection_stepped(scene:, connection:, state:, taken:, now_ms:)
    }
    ToConnection(..), MapProcess | ToConnectionSelecting(..), MapProcess ->
      panic as "mail of a connection is never to the map"
  }
}

fn filetime_at(now_ms now_ms: Int) -> Int {
  connection_support.filetime + now_ms * 10_000
}

/// The scene after a connection's step: its state, what it sent, the frames it wrote and
/// the cast timers it started put in the scene. A step that ends in an ask of the store is
/// followed by the store's answer at once, since the connection takes nothing else while it
/// waits; a step that ends in an ask of the map leaves the connection waiting for the map's
/// answer.
fn connection_stepped(
  scene scene: Scene,
  connection connection: Int,
  state state: game_connection.State,
  taken taken: step.ConnectionStep(client_connection.Request),
  now_ms now_ms: Int,
) -> Scene {
  let #(state, steps) = store_answered(state:, taken:, now_ms:, steps: [taken])
  let scene =
    Scene(
      ..scene,
      connections: dict.insert(scene.connections, connection, state),
      asking: case support.asked(list.last(steps) |> result.unwrap(taken)) {
        Some(ask) -> dict.insert(scene.asking, connection, ask)
        None -> dict.delete(scene.asking, connection)
      },
    )
  list.fold(steps, scene, fn(scene, taken) {
    Scene(
      ..scene,
      mail: list.append(scene.mail, mail_of_the_connection(connection:, taken:)),
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
  })
}

/// The state after the store answered each ask of the store the step ends in, and the steps
/// that took the answers, after `steps`.
fn store_answered(
  state state: game_connection.State,
  taken taken: step.ConnectionStep(client_connection.Request),
  now_ms now_ms: Int,
  steps steps: List(step.ConnectionStep(client_connection.Request)),
) -> #(
  game_connection.State,
  List(step.ConnectionStep(client_connection.Request)),
) {
  case support.asked(taken) {
    Some(step.Ask(request: client_connection.AskStore(request:), ask:, ..)) -> {
      let #(state, answered) =
        connection_support.feed_at(
          state:,
          filetime: filetime_at(now_ms:),
          event: OwnEvent(step.Answered(ask:, outcome: store_answer(request:))),
        )
      store_answered(
        state:,
        taken: answered,
        now_ms:,
        steps: list.append(steps, [answered]),
      )
    }
    Some(_) | None -> #(state, steps)
  }
}

/// What the store answers a connection's ask in a scene: the save a camp makes.
fn store_answer(request request: store.Request) -> step.Outcome(Answer) {
  case request {
    store.Move(request: store.SavePlace(..)) -> connection_support.place_saved()
    store.Login(..) | store.Select(..) | store.World(..) | store.Items(..) ->
      panic as "the scene answers the store's save of a camp and no other ask"
  }
}

/// The names of what the receiver took, in order.
pub fn order_at(
  scene scene: Scene,
  receiver receiver: Receiver,
) -> List(String) {
  order_explorer.order_at(taken: scene.taken, receiver:)
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
      order_explorer.Taken(
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
      order_explorer.Taken(..) -> Error(Nil)
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
      order_explorer.Mail(
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

/// The unit ids the connection's 0x7f4 frames name as targets, in order.
pub fn go_targets(scene scene: Scene, connection connection: Int) -> List(Int) {
  list.flat_map(frames_of(scene:, connection:), fn(frame) {
    case frame.message_id {
      0x07F4 -> {
        let assert Ok(go) = spell_go.decode(frame.body)
          as "a 0x7f4 the connection wrote decodes"
        list.map(go.targets, fn(target) { target.unit_id })
      }
      _ -> []
    }
  })
}

/// A timer of a connection fires, as mail of the timer's own queue.
pub fn timer_fires(
  scene scene: Scene,
  connection connection: Int,
  timer timer: TimerId,
) -> Scene {
  Scene(
    ..scene,
    mail: list.append(scene.mail, [
      order_explorer.Mail(
        to: ConnectionProcess(connection),
        from: FromTimer(connection),
        input: ToConnection(OwnEvent(TimerFired(timer:))),
        name: "timer of " <> int_name(connection) <> " fires",
      ),
    ]),
  )
}

/// The cast a cast frame (0x7ff, 0x7f4, 0x7fe, 0x811) names; any other frame names none.
fn cast_of(frame frame: Frame) -> Result(Int, Nil) {
  case frame.message_id {
    0x07FF ->
      spell_started.decode(frame.body)
      |> result.map(fn(started) { started.cast_id })
      |> result.replace_error(Nil)
    0x07F4 ->
      spell_go.decode(frame.body)
      |> result.map(fn(go) { go.cast_id })
      |> result.replace_error(Nil)
    0x07FE ->
      spell_finished.decode(frame.body)
      |> result.map(fn(finished) { finished.cast_id })
      |> result.replace_error(Nil)
    0x0811 ->
      spell_targets_removed.decode(frame.body)
      |> result.map(fn(removed) { removed.cast_id })
      |> result.replace_error(Nil)
    _ -> Error(Nil)
  }
}

/// The cast ids of the 0x7ff frames the connection wrote, in order.
pub fn started_cast_ids(
  scene scene: Scene,
  connection connection: Int,
) -> List(Int) {
  list.filter_map(frames_of(scene:, connection:), fn(frame) {
    case frame.message_id {
      0x07FF -> cast_of(frame:)
      _ -> Error(Nil)
    }
  })
}

/// The ids of the cast frames (0x7ff, 0x7f4, 0x7fe, 0x811) the connection wrote that name
/// one of the casts `cast_ids`, in order.
pub fn cast_frames_of(
  scene scene: Scene,
  connection connection: Int,
  cast_ids cast_ids: List(Int),
) -> List(Int) {
  list.filter_map(frames_of(scene:, connection:), fn(frame) {
    case cast_of(frame:) {
      Ok(cast_id) ->
        case list.contains(cast_ids, cast_id) {
          True -> Ok(frame.message_id)
          False -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
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
      order_explorer.Mail(to: MapProcess, from:, input: ToMap(event), name:),
    ]),
  )
}

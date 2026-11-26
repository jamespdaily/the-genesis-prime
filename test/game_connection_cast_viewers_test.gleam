//// What each viewer of a player's cast is written: the caster's connection, the ally's
//// connection and the viewers run as the pure rules they are, each one's tells carried by
//// hand to the next. Expected values come from these places.
//// - The caster C's connection tells the cast's news to the connections that saw C at a send
////   (the cast's audience) and the change the cast lands on the ally T to T's connection,
////   which tells it to the viewers of T that C's audience did not hold the cast for
////   (`genesis_prime/game/connection/landing`).
//// - A viewer's client is written a cast's start once, by the first connection that tells
////   it (`opcode.0x7ff`: a cast id the client holds restarts that cast), and the cast's end
////   by the connection it holds the cast from: its caster's 0x7fe, or the ally's 0x811
////   naming the ally (`opcode.0x7fe`, `opcode.0x811`).
//// - Phantasmal Armor (Spell4 32823, an Esper's at level 6, Spell4Base 19033) pressed at an
////   ally holds its node on the ally alone for 10 000 ms. Savage Strike (Spell4 57248,
////   Spell4Base 36860, a Warrior's at level 9) gives its caster the Grounded state of
////   Spell4Effects 210674 (`table_rows -- Spell4Effects 210674`), which a go tells as 0x87f
////   and the end of the state as 0x880 (`opcode.0x87f`, `opcode.0x880`).
//// - Every test connection is the tests' player, unit 5: the rows of a viewer number the
////   caster as unit 7 and the ally as unit 9 (`unit_as_seen`).

import cast_support
import client_tables
import connection_rule_support as rule_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request, SentByPlayer, TellPeer}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/unit_news.{type News, Appeared, PeerNews}
import genesis_prime/message/spell_go.{type SpellGo}
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/message/spell_target_info
import genesis_prime/message/unit_create_cast
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, OwnEffect, OwnEvent,
}
import genesis_prime/world_map/map.{SeenBy}
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table
import unitest

const caster_unit = 7

const ally_unit = 9

const ally_connection = 3

const early_viewer = 2

const late_viewer = 4

/// The frames that carry a cast: the start, the go, the finish, the targets removed and the
/// two of a crowd-control state.
const cast_frames = [0x07FF, 0x07F4, 0x07FE, 0x0811, 0x087F, 0x0880]

/// The unit id the viewers number a unit by: the test connection's own unit 5 is the
/// sender, and unit 101 (the first connection's unit, as the ally's connection numbers the
/// caster) is the caster.
fn unit_as_seen(unit_id unit_id: Int, sender sender: Int) -> Int {
  case unit_id {
    5 -> sender
    101 -> caster_unit
    _ -> unit_id
  }
}

fn started_as_seen(
  start start: SpellStarted,
  sender sender: Int,
) -> SpellStarted {
  spell_started.SpellStarted(
    ..start,
    caster_unit_id: unit_as_seen(unit_id: start.caster_unit_id, sender:),
    primary_target_unit_id: unit_as_seen(
      unit_id: start.primary_target_unit_id,
      sender:,
    ),
  )
}

fn gone_as_seen(go go: SpellGo, sender sender: Int) -> SpellGo {
  spell_go.SpellGo(
    ..go,
    targets: list.map(go.targets, fn(target) {
      spell_target_info.SpellTargetInfo(
        ..target,
        unit_id: unit_as_seen(unit_id: target.unit_id, sender:),
      )
    }),
  )
}

/// The news of the connection that stands for the unit `sender`, as a viewer's connection
/// takes it.
fn news_as_seen(news news: News, sender sender: Int) -> News {
  case news {
    unit_news.CastStarted(start:) ->
      unit_news.CastStarted(start: started_as_seen(start:, sender:))
    unit_news.HeldCastStarted(start:, go:) ->
      unit_news.HeldCastStarted(
        start: started_as_seen(start:, sender:),
        go: gone_as_seen(go:, sender:),
      )
    unit_news.CastWent(go:) ->
      unit_news.CastWent(go: gone_as_seen(go:, sender:))
    Appeared(unit:) ->
      Appeared(
        unit: UnitCreatePlayer(
          ..unit,
          unit_id: unit_as_seen(unit_id: unit.unit_id, sender:),
          tail: UnitCreateTail(
            ..unit.tail,
            casts: list.map(unit.tail.casts, fn(cast) {
              unit_create_cast.UnitCreateCast(
                ..cast,
                caster_unit_id: unit_as_seen(
                  unit_id: cast.caster_unit_id,
                  sender:,
                ),
                primary_target_unit_id: unit_as_seen(
                  unit_id: cast.primary_target_unit_id,
                  sender:,
                ),
              )
            }),
          ),
        ),
      )
    _ -> news
  }
}

/// What a connection told the others in its steps, in order: the connection and the news,
/// by the unit the sender stands for, and the changes it told a player's connection.
type Told {
  News(to: Int, news: unit_news.PeerNews)
  Change(to: Int, change: client_connection.PlayerTell)
}

fn told_in(
  steps steps: List(ConnectionStep(Request)),
  sender sender: Int,
) -> List(Told) {
  list.flat_map(steps, fn(taken) {
    list.filter_map(rule_support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(step.Tell(
          to: step.Connection(ConnectionId(to)),
          request: TellPeer(news: PeerNews(news:, ..), ..),
        )) ->
          Ok(News(
            to:,
            news: PeerNews(unit_id: sender, news: news_as_seen(news:, sender:)),
          ))
        OwnEffect(step.Tell(
          to: step.Connection(ConnectionId(to)),
          request: client_connection.TellPlayer(tell:, ..),
        )) -> Ok(Change(to:, change: tell))
        _ -> Error(Nil)
      }
    })
  })
}

/// What the ally's connection `ally` tells its viewers when the caster's connection tells it
/// `change`, and the connection after it.
fn ally_taking(
  ally ally: game_connection.State,
  change change: client_connection.PlayerTell,
) -> #(game_connection.State, List(#(Int, unit_news.PeerNews))) {
  let #(ally, taken) =
    connection_support.feed(
      state: ally,
      event: connection_support.for_stay(
        connection_support.own_stay(),
        SentByPlayer(change),
      ),
    )
  #(
    ally,
    list.filter_map(told_in(steps: [taken], sender: ally_unit), fn(told) {
      case told {
        News(to:, news:) -> Ok(#(to, news))
        Change(..) -> Error(Nil)
      }
    }),
  )
}

/// Everything the caster's steps led to, in the order it was told: the caster's news to the
/// connections, and, after each change it told the ally's connection `ally`, what that
/// connection told its own viewers.
fn deliveries(
  steps steps: List(ConnectionStep(Request)),
  ally ally: game_connection.State,
) -> List(#(Int, unit_news.PeerNews)) {
  list.fold(told_in(steps:, sender: caster_unit), #(ally, []), fn(so_far, told) {
    let #(ally, delivered) = so_far
    case told {
      News(to:, news:) -> #(ally, list.append(delivered, [#(to, news)]))
      Change(to:, change:) if to == ally_connection -> {
        let #(ally, from_the_ally) = ally_taking(ally:, change:)
        #(ally, list.append(delivered, from_the_ally))
      }
      Change(..) -> so_far
    }
  }).1
}

/// The cast frames a viewer connection is written for the news told it, in order, after it
/// takes the creates of the units it sees.
fn written_to(
  viewer viewer: Int,
  sees sees: List(News),
  told told: List(#(Int, unit_news.PeerNews)),
) -> List(Int) {
  let state =
    list.fold(sees, connection_support.in_world(), fn(state, news) {
      let assert Appeared(unit:) = news
      connection_support.feed(
        state:,
        event: connection_support.sent_by_a_peer(connection_support.news_of(
          unit_id: unit.unit_id,
          news:,
        )),
      ).0
    })
  list.fold(told, #(state, []), fn(so_far, delivery) {
    let #(state, written) = so_far
    case delivery.0 == viewer {
      False -> so_far
      True -> {
        let #(state, taken) =
          connection_support.feed(
            state:,
            event: connection_support.sent_by_a_peer(delivery.1),
          )
        #(
          state,
          list.append(
            written,
            list.filter(connection_support.written_ids(taken), fn(id) {
              list.contains(cast_frames, id)
            }),
          ),
        )
      }
    }
  }).1
}

/// A plain create of the player unit `unit_id`, no cast listed.
fn appears(unit_id unit_id: Int) -> News {
  Appeared(
    unit: UnitCreatePlayer(..connection_support.another_unit(), unit_id:),
  )
}

/// The caster's press of `bag_index` at `target` at 1000 ms, the viewer `late` coming into
/// its sight right after the go, and its cast timers run to 12 000 ms: every step.
fn pressed_then_seen_by(
  state state: game_connection.State,
  bag_index bag_index: Int,
  target target: Int,
  late late: Int,
) -> List(ConnectionStep(Request)) {
  let #(state, pressed) =
    connection_support.at(
      state:,
      ms: 1000,
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id: 1,
            bag_index:,
            target:,
            press: 1,
          ),
        )),
      ),
    )
  let #(state, seen) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(late),
        stay: connection_support.viewer_stay(late),
        unit_id: connection_support.viewer_unit_id(late),
      )),
    )
  let #(_, later) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [pressed], ms: 1000),
      until_ms: 12_000,
      steps: [],
    )
  [pressed, seen, ..later]
}

/// The viewers decide what they are written: a viewer that saw the caster at the go is
/// written the caster's frames, and one that came into its sight after the go and holds the
/// cast from the ally is written the ally's start once and its end, and none of the caster's
/// restriction news for a state it was never written.
pub fn the_viewers_decisions_give_the_frames_the_audience_gave_for_a_go_a_restriction_and_an_ally_start_test() -> Nil {
  // deadline: measured under 1 s here with the client's tables read once (about 3 s cold), 30 s for a loaded machine
  use <- owned_test.run(30_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  // Phantasmal Armor's Spell4 rows are in the fixture and the client's SpellLevel row 773
  // that gives it to an Esper at level 6 is not, so the row is added as the client holds it.
  use tables <- fixture_tables.added(
    table: "SpellLevel",
    copy_of: 647,
    id: 773,
    with: [
      #("characterLevel", planted_table.Integer(6)),
      #("spell4Id", planted_table.Integer(32_823)),
    ],
  )
  let armor = {
    let #(caster, _) =
      connection_support.entered_at_level(
        settings: Settings(..connection_support.settings(), tables:),
        class_id: 3,
        level: 6,
        saved_health: None,
      )
    let caster =
      connection_support.watched_by(state: caster, viewers: [
        early_viewer,
      ])
    let caster =
      list.fold(
        [
          connection_support.sent_by_the_map(SeenBy(
            by: ConnectionId(ally_connection),
            stay: connection_support.viewer_stay(ally_connection),
            unit_id: ally_unit,
          )),
          connection_support.sent_by_a_peer(connection_support.news_of(
            unit_id: ally_unit,
            news: appears(unit_id: ally_unit),
          )),
        ],
        caster,
        fn(state, event) { connection_support.feed(state:, event:).0 },
      )
    pressed_then_seen_by(
      state: caster,
      bag_index: connection_support.bag_index_of(
        tables:,
        class_id: 3,
        level: 6,
        ability: 19_033,
      ),
      target: ally_unit,
      late: late_viewer,
    )
  }
  let ally =
    connection_support.watched_by(
      state: connection_support.in_world(),
      viewers: [1, early_viewer, late_viewer],
    )
  let told = deliveries(steps: armor, ally:)
  assert written_to(
      viewer: early_viewer,
      sees: [appears(unit_id: caster_unit), appears(unit_id: ally_unit)],
      told:,
    )
    == [0x07FF, 0x07F4, 0x07FF, 0x07F4, 0x07FE, 0x07FE]
    as "Phantasmal Armor: the viewer that saw the caster at the go is written its two casts' starts and goes, the ally's start of neither, and the caster's two finishes, the ally's ends writing nothing"
  assert written_to(
      viewer: late_viewer,
      sees: [appears(unit_id: ally_unit)],
      told:,
    )
    == [0x07FF, 0x07F4, 0x07FF, 0x07F4, 0x0811, 0x0811]
    as "Phantasmal Armor: the viewer that came into the caster's sight after the go is written each cast's start once, from the ally, and the ally's two ends, the caster's finishes of casts it holds from the ally writing nothing"
  // Savage Strike's Spell4 rows are not in the fixture, so this row reads the client's tables.
  let real = client_tables.shared()
  let strike = {
    let #(caster, _) =
      connection_support.entered_at_level(
        settings: Settings(..connection_support.settings(), tables: real),
        class_id: 1,
        level: 9,
        saved_health: None,
      )
    let caster =
      connection_support.watched_by(state: caster, viewers: [
        early_viewer,
      ])
    let caster =
      connection_support.feed(
        state: caster,
        event: connection_support.beast_appears(unit_id: 21),
      ).0
    pressed_then_seen_by(
      state: caster,
      bag_index: connection_support.bag_index_of(
        tables: real,
        class_id: 1,
        level: 9,
        ability: 36_860,
      ),
      target: 21,
      late: late_viewer,
    )
  }
  let told = deliveries(steps: strike, ally:)
  let restrictions = fn(viewer, sees) {
    list.filter(written_to(viewer:, sees:, told:), fn(id) {
      id == 0x087F || id == 0x0880
    })
  }
  assert restrictions(early_viewer, [appears(unit_id: caster_unit)])
    == [0x087F, 0x0880]
    as "Savage Strike: the viewer that saw the caster at the go is written the 0x87f and then the 0x880 of the state the go gave the caster"
  assert restrictions(late_viewer, []) == []
    as "Savage Strike: the viewer that came into the caster's sight after the go is written neither"
}

//// The map's spawns under random play (`genesis_prime/world_map/map`), the rule
//// run with the shell's part played by the test: a creature that is told `Retire`
//// ends cleanly, the sweep and each spawn's restart timer fire when due on a clock
//// the test owns, and a creature may crash. Expected values come from these places.
//// - The design of the world spawns (the Design artifact of issue 375, sections 3
////   and 5, test 18): a spawn has a running creature exactly when a player sees it
////   or no player has seen it for less than 70 s (60 s of idle stop and a sweep
////   every 10 s); the players who see a live spawn are exactly the viewers the map
////   holds for it; unit ids are distinct and below 2^20.
//// - Sight (`genesis_prime/world_map/sight`): 1024 units, inclusive; the spawns and
////   the players stand on the x axis, so a spawn is seen when its x is within 1024
////   of the player's.
//// The harness has a planted bug to prove it can fail: with the sweep never fired,
//// a creature no one sees is still live after 70 s, and the check names it.

import connection_rule_support as support
import genesis_prime/step.{
  type WatchId, CancelServiceTimer, Connection, ConnectionId, Creature,
  OwnEffect, OwnEvent, Reply, Send, ServiceTimerFired, StartCreature,
  StartServiceTimer, TimerId, WatchEnded, WatchId,
}
import genesis_prime/world_map/map.{type State, Live, Retire, Retiring}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import map_spawn_support
import map_support
import owned_test
import qcheck

/// The spawns' x positions: spawn n is the n-th.
const spawn_xs = [0.0, 300.0, 900.0, 1400.0, 2500.0, 4000.0]

/// The x positions the players move among.
const stops = [0.0, 500.0, 1200.0, 2000.0, 3500.0, 6000.0, 9000.0]

/// What the test does next.
type Op {
  JoinAt(connection: Int, stop: Int)
  MoveTo(connection: Int, stop: Int)
  Leaves(connection: Int)
  Ends(connection: Int)
  Waits(ms: Int)
  Crashes(pick: Int)
}

/// The map, the clock and what the shell has been asked.
type Play {
  Play(
    state: State,
    now_ms: Int,
    /// The players' x by connection.
    players: Dict(Int, Float),
    /// The watch of each player's connection.
    watches: Dict(Int, WatchId),
    /// Each player's unit id.
    units: Dict(Int, Int),
    /// The restart timers running, by spawn number, with when they are due.
    restarts: Dict(Int, Int),
    /// When the sweep is next due, `None` when the harness never fires it.
    next_sweep_ms: option.Option(Int),
    sweep_ms: Int,
    violations: List(String),
  )
}

fn op_of(n: Int) -> Op {
  let argument = n / 7
  let connection = argument % 4 + 1
  let stop = { argument / 4 } % list.length(stops)
  case n % 7 {
    0 -> JoinAt(connection:, stop:)
    1 | 2 -> MoveTo(connection:, stop:)
    3 -> Leaves(connection:)
    4 -> Ends(connection:)
    5 -> Waits(ms: { argument % 12 + 1 } * 5000)
    _ -> Crashes(pick: argument)
  }
}

fn x_of(stop: Int) -> Float {
  let assert Ok(x) = list.first(list.drop(stops, stop)) as "a stop"
  x
}

/// A map with the six spawns, started at time 5000, and the clock after it.
fn begin(fire_sweeps fire_sweeps: Bool) -> Play {
  let #(state, taken) = map_spawn_support.started(at: spawn_xs)
  settle(
    play: Play(
      state:,
      now_ms: map_spawn_support.started_at_ms,
      players: dict.new(),
      watches: dict.new(),
      units: dict.new(),
      restarts: dict.new(),
      next_sweep_ms: None,
      sweep_ms: map_support.sweep_ms,
      violations: [],
    ),
    taken:,
    connection: 0,
    fire_sweeps:,
  )
}

/// The effects of a step as the shell would carry them out: timers are kept for
/// the clock to fire, a creature told to retire ends cleanly at once, and the
/// player's watch and unit id are noted.
fn settle(
  play play: Play,
  taken taken: step.ServiceStep(map.Outgoing),
  connection connection: Int,
  fire_sweeps fire_sweeps: Bool,
) -> Play {
  let #(play, retired) =
    list.fold(support.effects_of(taken), #(play, []), fn(held, effect) {
      let #(play, retired) = held
      case effect {
        OwnEffect(Reply(answer: map.Joined(unit:, ..), ..)) -> #(
          Play(..play, units: dict.insert(play.units, connection, unit.unit_id)),
          retired,
        )
        step.Watch(watch:, target: Connection(ConnectionId(number))) -> #(
          Play(..play, watches: dict.insert(play.watches, number, watch)),
          retired,
        )
        OwnEffect(Send(to: Creature(life:, ..), message: Retire)) -> #(play, [
          life,
          ..retired
        ])
        OwnEffect(StartServiceTimer(timer: TimerId(0), after_ms:)) -> #(
          case fire_sweeps {
            True -> Play(..play, next_sweep_ms: Some(play.now_ms + after_ms))
            False -> play
          },
          retired,
        )
        OwnEffect(StartServiceTimer(timer: TimerId(number), after_ms:)) -> #(
          Play(
            ..play,
            restarts: dict.insert(play.restarts, number, play.now_ms + after_ms),
          ),
          retired,
        )
        OwnEffect(StartCreature(..))
        | OwnEffect(Send(..))
        | OwnEffect(Reply(..))
        | OwnEffect(CancelServiceTimer(..))
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | step.Stop -> #(play, retired)
      }
    })
  // The creatures told to retire end cleanly; each end may start a creature.
  list.fold(list.reverse(retired), play, fn(play, life) {
    let #(state, taken) =
      map.step(
        play.state,
        support.input_at_ms(ms: play.now_ms, event: WatchEnded(WatchId(life))),
      )
    settle(play: Play(..play, state:), taken:, connection: 0, fire_sweeps:)
  })
}

fn feed(
  play play: Play,
  event event: step.Event(step.ServiceEvent(map.Message)),
  connection connection: Int,
  fire_sweeps fire_sweeps: Bool,
) -> Play {
  let #(state, taken) =
    map.step(play.state, support.input_at_ms(ms: play.now_ms, event:))
  settle(play: Play(..play, state:), taken:, connection:, fire_sweeps:)
}

/// Moves the clock to `target_ms`, firing each timer that falls due on the way,
/// in the order of their times.
fn advance(
  play play: Play,
  to target_ms: Int,
  fire_sweeps fire_sweeps: Bool,
) -> Play {
  let due =
    [
      option.map(play.next_sweep_ms, fn(at_ms) { #(at_ms, 0) }),
      ..list.map(dict.to_list(play.restarts), fn(restart) {
        Some(#(restart.1, restart.0))
      })
    ]
    |> list.filter_map(option.to_result(_, Nil))
    |> list.filter(fn(timer) { timer.0 <= target_ms })
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  case due {
    [] -> Play(..play, now_ms: target_ms)
    [#(at_ms, number), ..] -> {
      let play = Play(..play, now_ms: at_ms)
      let play = case number {
        0 -> Play(..play, next_sweep_ms: None)
        _ -> Play(..play, restarts: dict.delete(play.restarts, number))
      }
      let play =
        feed(
          play:,
          event: OwnEvent(ServiceTimerFired(timer: TimerId(number))),
          connection: 0,
          fire_sweeps:,
        )
      advance(play:, to: target_ms, fire_sweeps:)
    }
  }
}

/// Applies one operation, then checks the rule.
fn apply(play play: Play, op op: Op, fire_sweeps fire_sweeps: Bool) -> Play {
  let play = case op {
    JoinAt(connection:, stop:) ->
      case dict.has_key(play.players, connection) {
        True -> play
        False ->
          feed(
            play: Play(
              ..play,
              players: dict.insert(play.players, connection, x_of(stop)),
            ),
            event: OwnEvent(step.Asked(
              caller: step.CallerId(connection),
              message: map.Join(
                connection: ConnectionId(connection),
                character: map_support.character(100 + connection),
                place: map_spawn_support.at(x_of(stop)),
              ),
            )),
            connection:,
            fire_sweeps:,
          )
      }
    MoveTo(connection:, stop:) ->
      case dict.has_key(play.players, connection) {
        False -> play
        True ->
          feed(
            play: Play(
              ..play,
              players: dict.insert(play.players, connection, x_of(stop)),
            ),
            event: OwnEvent(
              step.Told(message: map.Moved(
                connection: ConnectionId(connection),
                place: map_spawn_support.at(x_of(stop)),
                seq: stop,
              )),
            ),
            connection:,
            fire_sweeps:,
          )
      }
    Leaves(connection:) ->
      case dict.has_key(play.players, connection) {
        False -> play
        True ->
          feed(
            play: Play(..play, players: dict.delete(play.players, connection)),
            event: OwnEvent(step.Asked(
              caller: step.CallerId(99),
              message: map.Leave(connection: ConnectionId(connection)),
            )),
            connection:,
            fire_sweeps:,
          )
      }
    Ends(connection:) ->
      case dict.get(play.watches, connection) {
        Error(Nil) -> play
        Ok(watch) ->
          case dict.has_key(play.players, connection) {
            False -> play
            True ->
              feed(
                play: Play(
                  ..play,
                  players: dict.delete(play.players, connection),
                ),
                event: WatchEnded(watch),
                connection:,
                fire_sweeps:,
              )
          }
      }
    Waits(ms:) -> advance(play:, to: play.now_ms + ms, fire_sweeps:)
    Crashes(pick:) -> {
      let lives =
        list.index_map(spawn_xs, fn(_, index) { index + 1 })
        |> list.filter_map(fn(number) {
          case map.spawn_state(state: play.state, spawn: SpawnId(number)) {
            Ok(Live(life:, ..)) -> Ok(life)
            Ok(Retiring(..))
            | Ok(map.WaitingForRestart)
            | Ok(map.Failed)
            | Error(Nil) -> Error(Nil)
          }
        })
      case lives {
        [] -> play
        _ -> {
          let assert Ok(life) =
            list.first(list.drop(lives, pick % list.length(lives)))
            as "a live creature"
          feed(
            play:,
            event: WatchEnded(WatchId(life)),
            connection: 0,
            fire_sweeps:,
          )
        }
      }
    }
  }
  Play(..play, violations: list.append(play.violations, broken(play)))
}

/// What the rule breaks in this state, as sentences.
fn broken(play: Play) -> List(String) {
  let sees = fn(number: Int) {
    let assert Ok(spawn_x) = list.first(list.drop(spawn_xs, number - 1))
      as "a spawn"
    dict.to_list(play.players)
    |> list.filter(fn(player) { float_abs(player.1 -. spawn_x) <=. 1024.0 })
    |> list.map(fn(player) { ConnectionId(player.0) })
    |> set.from_list
  }
  let spawn_problems =
    list.index_map(spawn_xs, fn(_, index) {
      let number = index + 1
      let seen = sees(number)
      let name = "spawn " <> int.to_string(number)
      case
        map.spawn_state(state: play.state, spawn: SpawnId(number)),
        set.is_empty(seen)
      {
        Ok(Live(viewers:, idle_since_ms:, ..)), _ ->
          list.flatten([
            case viewers == seen {
              True -> []
              False -> [
                name
                <> " is live with viewers other than the players who see it",
              ]
            },
            case idle_since_ms, set.is_empty(viewers) {
              None, True -> [name <> " is live with no viewer and no idle time"]
              Some(since), True ->
                case play.now_ms - since < 70_000 {
                  True -> []
                  False -> [
                    name
                    <> " is live and unseen for "
                    <> int.to_string(play.now_ms - since)
                    <> " ms",
                  ]
                }
              Some(_), False -> [name <> " has viewers and an idle time"]
              None, False -> []
            },
          ])
        Ok(Retiring(..)), _
        | Ok(map.WaitingForRestart), _
        | Ok(map.Failed), _
        -> []
        Error(Nil), True -> []
        Error(Nil), False -> [name <> " is dormant and a player sees it"]
      }
    })
    |> list.flatten
  let lives =
    list.index_map(spawn_xs, fn(_, index) {
      case map.spawn_state(state: play.state, spawn: SpawnId(index + 1)) {
        Ok(Live(unit_id:, ..)) | Ok(Retiring(unit_id:, ..)) -> [unit_id]
        Ok(map.WaitingForRestart) | Ok(map.Failed) | Error(Nil) -> []
      }
    })
    |> list.flatten
  let units = list.append(dict.values(play.units), lives)
  let dormant_ids_are_distinct =
    list.length(list.unique(units)) == list.length(units)
  case
    dormant_ids_are_distinct
    && list.all(units, fn(id) { id > 0 && id < 1_048_576 })
  {
    True -> spawn_problems
    False -> [
      "a unit id is given twice or is outside 1 to 2^20 - 1",
      ..spawn_problems
    ]
  }
}

fn float_abs(value: Float) -> Float {
  use <- bool.guard(when: value <. 0.0, return: 0.0 -. value)
  value
}

/// The rule's breaches over these operations, with the sweep fired or not.
fn run(ops ops: List(Op), fire_sweeps fire_sweeps: Bool) -> List(String) {
  list.fold(ops, begin(fire_sweeps:), fn(play, op) {
    apply(play:, op:, fire_sweeps:)
  }).violations
}

pub fn across_random_joins_moves_leaves_ends_sweeps_and_crashes_a_spawn_runs_exactly_while_seen_or_idle_under_70_seconds_test() -> Nil {
  use <- owned_test.run(120_000)
  use numbers <- qcheck.given(qcheck.generic_list(
    qcheck.bounded_int(from: 0, to: 1_000_000),
    qcheck.bounded_int(from: 1, to: 60),
  ))
  assert run(ops: list.map(numbers, op_of), fire_sweeps: True) == []
    as "a spawn is live exactly when a player sees it or it has been idle under 70 s, its viewers are the players who see it, and unit ids are distinct"
}

pub fn the_harness_names_a_creature_nobody_sees_when_the_sweep_never_fires_test() -> Nil {
  use <- owned_test.run(5000)
  // The planted bug: no sweep. A player sees spawn 1, goes far away, and 100 s
  // pass: the creature is live and unseen for far more than 70 s.
  let violations =
    run(
      ops: [
        JoinAt(connection: 1, stop: 0),
        MoveTo(connection: 1, stop: 6),
        Waits(ms: 60_000),
        Waits(ms: 40_000),
      ],
      fire_sweeps: False,
    )
  assert list.any(violations, fn(violation) {
    violation == "spawn 1 is live and unseen for 100000 ms"
  })
    as "the check names the live unseen creature"
  assert run(
      ops: [
        JoinAt(connection: 1, stop: 0),
        MoveTo(connection: 1, stop: 6),
        Waits(ms: 60_000),
        Waits(ms: 40_000),
      ],
      fire_sweeps: True,
    )
    == []
    as "with the sweep the same play breaks nothing"
}

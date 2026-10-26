//// Both process-topology prototypes must be right before they are measured.
//// Each check runs against prototype A (one process per unit,
//// `per_unit.start`) and prototype B (one map process, `map_process.start`).
////
//// No expected value here is a client fact. Each is a game rule the
//// prototypes share, fixed by the plan and shape comments on the topology
//// step's issue:
////
//// - A hit takes `hit_damage` health, one hit at a time. Health stops at 0,
////   the hit that brings it there kills the creature once, and a hit on a dead
////   creature is refused. So with maximum health `h` and damage `d` the hits
////   leave `h - d`, `h - 2d`, ..., the first hit that takes at least what is
////   left lands at 0, and every later one is refused.
//// - An attack hits the nearest creature in visibility range; a dead creature
////   stays where it died and returns after `unit.return_delay_microseconds`.
//// - A move is sent to every other player whose unit is within visibility
////   range of the move's new position, the range inclusive
////   (`position.within`), and never to the mover.
////
//// The checks that decide a prototype's correctness are measure 1 of the
//// step; the spawn list, and so every id and position used below, comes from
//// `workload.spawn_list` on a fixed workload.

import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/per_unit
import genesis_prime/topology/position.{type Position, Position}
import genesis_prime/topology/unit.{type HitOutcome, type Unit}
import genesis_prime/topology/update.{type Delivery}
import genesis_prime/topology/workload.{type Workload, Workload}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Selector}
import gleam/erlang/reference.{type Reference}
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/pair
import gleam/result
import gleam/set
import owned_test

/// Starts a prototype from a workload and the key its spawn list is kept
/// under.
type Starter =
  fn(Workload, Reference) -> Result(actor.Started(Owner), actor.StartError)

/// A delivery, and the id of the connection it arrived on.
type Event {
  Event(connection: Int, delivery: Delivery)
}

/// A prototype with every player joined: the door the players act through,
/// the key its spawn list is kept under, the spawn list, and a selector over
/// every player's connection. The test process owns all the connections, so
/// one selector receives from all of them, in the order they arrived.
type Run {
  Run(
    prototype: Owner,
    key: Reference,
    spawn: Dict(Int, Unit),
    connections: Selector(Event),
  )
}

/// What the hits on the creature produced: each connection's `Hit` replies,
/// newest first, and how many `Died` updates of the creature each connection
/// received.
type Hits {
  Hits(replies: Dict(Int, List(update.HitReply)), died: Dict(Int, Int))
}

const hit_damage = 7

const hitters = 100

const creature_id = 101

const mover_id = 1

const move_count = 50

const first_move_sent_at = 1000

const marker_sent_at = 9999

pub fn a_creature_hit_by_100_players_at_once_in_prototype_a_loses_the_sum_of_the_hits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_hits_sum_below_health(per_unit.start)
}

pub fn a_creature_hit_by_100_players_at_once_in_prototype_b_loses_the_sum_of_the_hits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_hits_sum_below_health(start_prototype_b)
}

pub fn a_creature_hit_by_more_than_its_health_at_once_in_prototype_a_dies_exactly_once_test() -> Nil {
  use <- owned_test.run(5000)
  assert_hits_sum_above_health(per_unit.start)
}

pub fn a_creature_hit_by_more_than_its_health_at_once_in_prototype_b_dies_exactly_once_test() -> Nil {
  use <- owned_test.run(5000)
  assert_hits_sum_above_health(start_prototype_b)
}

pub fn a_move_reaches_every_player_in_range_and_none_outside_in_prototype_a_test() -> Nil {
  use <- owned_test.run(5000)
  assert_moves_reach_exactly_the_players_in_range(per_unit.start)
}

pub fn a_move_reaches_every_player_in_range_and_none_outside_in_prototype_b_test() -> Nil {
  use <- owned_test.run(5000)
  assert_moves_reach_exactly_the_players_in_range(start_prototype_b)
}

fn start_prototype_b(
  workload: Workload,
  key: Reference,
) -> Result(actor.Started(Owner), actor.StartError) {
  map_process.start(workload, key, map_process.SendsItself)
}

/// 1000 health and 100 hits of 7 take 700: every hit lands, the remaining
/// healths are 993, 986, ... 300 each once (no hit is lost or applied twice),
/// and the creature does not die.
fn assert_hits_sum_below_health(start: Starter) -> Nil {
  let #(outcomes, died) = hit_creature_together(start, 1000)
  assert list.length(outcomes) == hitters as "every attacker gets one reply"
  assert landed_healths(outcomes) == remaining_after_each_hit(1000, hitters)
    as "every hit lands and leaves the health the sum of the hits before it"
  assert list.last(landed_healths(outcomes)) == Ok(300)
    as "the lowest health is the maximum minus 100 hits of 7"
  assert dict.is_empty(died) as "the creature does not die"
}

/// 500 health and hits of 7: 71 hits leave 3, the 72nd lands at 0 and kills,
/// and the other 28 are refused. Every connection is told of the death once.
/// All the hits are sent back to back, so they reach the creature's owner
/// well inside the one second that passes before a dead creature returns; no
/// `Returned` update is expected before the end of the test.
fn assert_hits_sum_above_health(start: Starter) -> Nil {
  let #(outcomes, died) = hit_creature_together(start, 500)
  assert list.length(outcomes) == hitters as "every attacker gets one reply"
  assert landed_healths(outcomes)
    == list.append(remaining_after_each_hit(500, 71), [0])
    as "71 hits land leaving 500 - 7 * n, the 72nd lands at 0"
  assert list.count(outcomes, fn(outcome) { outcome == unit.RefusedDead }) == 28
    as "the 28 hits after the death are refused"
  assert list.last(landed_healths(outcomes)) == Ok(0)
    as "the killing hit leaves 0 health"
  assert died == dict.from_list(list.map(ids(1, hitters), fn(id) { #(id, 1) }))
    as "every connection receives exactly one Died of the creature"
}

/// The remaining health after the first `hits` hits of `hit_damage`, from the
/// first hit's down to the last's.
fn remaining_after_each_hit(maximum_health: Int, hits: Int) -> List(Int) {
  list.map(ids(1, hits), fn(hit) { maximum_health - hit * hit_damage })
}

/// The health left by each hit that landed, highest first.
fn landed_healths(outcomes: List(HitOutcome)) -> List(Int) {
  outcomes
  |> list.filter_map(filter_map_landed)
  |> list.sort(fn(first, second) { int.compare(second, first) })
}

fn filter_map_landed(outcome: HitOutcome) -> Result(Int, Nil) {
  case outcome {
    unit.Landed(remaining_health:) -> Ok(remaining_health)
    unit.RefusedDead -> Error(Nil)
  }
}

/// 100 players in one small cluster, all within visibility range of the one
/// creature, hit it back to back. Returns each attacker's outcome and how many
/// `Died` updates of the creature each connection received.
///
/// To be sure no second `Died` arrives late, one more attack is sent after
/// the 100 replies, and the test waits for its reply. Everything about the
/// creature, the `Died` updates and the replies, is sent by the one process
/// that owns the creature (the map process in B, the creature's own process in
/// A), and a process's messages to one receiver arrive in the order they were
/// sent. The test process is the receiver of every connection, so the reply to
/// the last attack arrives after every earlier update and reply, and none
/// can arrive after it.
fn hit_creature_together(
  start: Starter,
  maximum_health: Int,
) -> #(List(HitOutcome), Dict(Int, Int)) {
  let run =
    begin(
      start,
      Workload(
        ..workload.default(),
        players: hitters,
        creatures: 1,
        map_size: 20.0,
        visibility_range: 100.0,
        cluster_count: 1,
        cluster_radius: 5.0,
        hit_damage: hit_damage,
        creature_maximum_health: maximum_health,
      ),
    )
  assert dict.get(run.spawn, creature_id)
    |> result.map(fn(creature) { creature.kind })
    == Ok(unit.Creature)
    as "the creature is unit 101"
  let now = measurement.monotonic_microseconds()
  list.each(ids(1, hitters), fn(id) {
    run.prototype.attack_nearest_creature(id, now)
  })
  let after_hits =
    collect(
      run.connections,
      Hits(replies: dict.new(), died: dict.new()),
      note_hits,
      fn(hits) { dict.size(hits.replies) == hitters },
    )
  run.prototype.attack_nearest_creature(
    mover_id,
    measurement.monotonic_microseconds(),
  )
  let hits =
    collect(run.connections, after_hits, note_hits, fn(hits) {
      list.length(replies_of(hits, mover_id)) == 2
    })
  finish(run)
  let outcomes =
    list.flat_map(ids(1, hitters), fn(id) {
      let assert [first_reply, ..] = list.reverse(replies_of(hits, id))
        as "every attacker received a reply"
      assert first_reply.target_id == creature_id
        as "every attack hits the creature"
      assert list.length(replies_of(hits, id)) == replies_expected(id)
        as "an attacker receives one reply per attack"
      [first_reply.outcome]
    })
  #(outcomes, hits.died)
}

/// How many replies an attacker receives: one for its own attack, and a
/// second for the marker attack when it is the one that sends it.
fn replies_expected(connection: Int) -> Int {
  use <- bool.guard(connection == mover_id, 2)
  1
}

fn replies_of(hits: Hits, connection: Int) -> List(update.HitReply) {
  dict.get(hits.replies, connection) |> result.unwrap([])
}

fn note_hits(hits: Hits, event: Event) -> Hits {
  case event.delivery {
    update.Hit(reply) ->
      Hits(
        ..hits,
        replies: dict.upsert(hits.replies, event.connection, fn(replies) {
          [reply, ..option.unwrap(replies, [])]
        }),
      )
    update.Updated(update.Died(unit_id:, ..)) if unit_id == creature_id ->
      Hits(
        ..hits,
        died: dict.upsert(hits.died, event.connection, fn(count) {
          option.unwrap(count, 0) + 1
        }),
      )
    update.Updated(_) | update.Joined(_) -> hits
  }
}

/// A fixed workload of 200 players in 4 clusters and 50 creatures. The mover,
/// player 1, makes 50 moves along a seeded random walk; no other player moves.
/// Each move must reach exactly the other players whose spawn position is
/// within visibility range of its new position, found by a scan of every
/// player, and each of them once.
///
/// To know nothing more is coming, a marker move of the mover onto player 2's
/// spawn position follows, and the test waits for it on player 2's
/// connection. All of the mover's updates are sent by one process (the map
/// process in B, the mover's own process in A), and the test process is the
/// receiver of every connection, so when the marker's update arrives every
/// earlier update of the mover has arrived.
fn assert_moves_reach_exactly_the_players_in_range(start: Starter) -> Nil {
  let workload =
    Workload(
      ..workload.default(),
      players: 200,
      creatures: 50,
      map_size: 1000.0,
      visibility_range: 100.0,
      cluster_count: 4,
      cluster_radius: 150.0,
      seed: 28,
    )
  let run = begin(start, workload)
  let players =
    run.spawn
    |> dict.filter(fn(id, _) { id <= workload.players })
    |> dict.map_values(fn(_, player) { player.position })
  let assert Ok(start_position) = dict.get(players, mover_id)
    as "the mover is in the spawn list"
  let assert Ok(marker_position) = dict.get(players, 2)
    as "player 2 is in the spawn list"
  let destinations = random_walk(players:, workload:, start: start_position)
  let moves =
    list.index_map(destinations, fn(destination, index) {
      #(first_move_sent_at + index, destination)
    })
  list.each(moves, fn(move) { run.prototype.move(mover_id, move.1, move.0) })
  run.prototype.move(mover_id, marker_position, marker_sent_at)
  let received =
    collect(run.connections, dict.new(), note_moves, fn(received) {
      dict.get(received, marker_sent_at)
      |> result.map(list.contains(_, 2))
      == Ok(True)
    })
  finish(run)
  list.each(moves, fn(move) {
    let #(sent_at, destination) = move
    let expected =
      recipients(players:, destination:, range: workload.visibility_range)
    assert expected != [] as "a move with no player in range proves nothing"
    assert list.length(expected) < workload.players - 1
      as "a move with every player in range proves nothing"
    let actual =
      dict.get(received, sent_at)
      |> result.unwrap([])
      |> list.sort(int.compare)
    assert actual == expected
      as "a move reaches each player in range once and no one else"
  })
}

/// Records which connections received each move of the mover, by the time
/// the move was sent.
fn note_moves(
  received: Dict(Int, List(Int)),
  event: Event,
) -> Dict(Int, List(Int)) {
  case event.delivery {
    update.Updated(update.Moved(unit_id: 1, sent_at:, ..)) ->
      dict.upsert(received, sent_at, fn(connections) {
        [event.connection, ..option.unwrap(connections, [])]
      })
    update.Updated(_) | update.Hit(_) | update.Joined(_) -> received
  }
}

/// The ids of the players, other than the mover, whose positions are within
/// `range` of a position, found by looking at every player. Sorted.
fn recipients(
  players players: Dict(Int, Position),
  destination destination: Position,
  range range: Float,
) -> List(Int) {
  players
  |> dict.to_list
  |> list.filter(fn(entry) {
    entry.0 != mover_id && position.within(entry.1, destination, range)
  })
  |> list.map(pair.first)
  |> list.sort(int.compare)
}

/// The positions of a random walk of `move_count` steps from `start`, drawn
/// from the workload's seed. A step is up to twice the visibility range in
/// each direction and stays on the map. A step that would leave no player in
/// range, or every player in range, is drawn again, so every move of the
/// walk has some players in range and some outside it.
fn random_walk(
  players players: Dict(Int, Position),
  workload workload: Workload,
  start start: Position,
) -> List(Position) {
  walk(
    players:,
    workload:,
    remaining: move_count,
    from: start,
    random: workload.seed,
    taken: [],
  )
}

fn walk(
  players players: Dict(Int, Position),
  workload workload: Workload,
  remaining remaining: Int,
  from from: Position,
  random random: Int,
  taken taken: List(Position),
) -> List(Position) {
  case remaining {
    0 -> list.reverse(taken)
    _ -> {
      let #(next, random) =
        next_step(players:, workload:, from:, random:, attempts: 1000)
      walk(
        players:,
        workload:,
        remaining: remaining - 1,
        from: next,
        random:,
        taken: [next, ..taken],
      )
    }
  }
}

fn next_step(
  players players: Dict(Int, Position),
  workload workload: Workload,
  from from: Position,
  random random: Int,
  attempts attempts: Int,
) -> #(Position, Int) {
  case attempts {
    0 -> panic as "no step of the walk has some players in range and some out"
    _ -> {
      let reach = 2.0 *. workload.visibility_range
      let #(dx, random) =
        draw_between(state: random, low: -1.0 *. reach, high: reach)
      let #(dy, random) =
        draw_between(state: random, low: -1.0 *. reach, high: reach)
      let candidate =
        Position(
          x: float.clamp(from.x +. dx, min: 0.0, max: workload.map_size),
          y: float.clamp(from.y +. dy, min: 0.0, max: workload.map_size),
        )
      let in_range =
        list.length(recipients(
          players:,
          destination: candidate,
          range: workload.visibility_range,
        ))
      case in_range > 0 && in_range < workload.players - 1 {
        True -> #(candidate, random)
        False ->
          next_step(players:, workload:, from:, random:, attempts: attempts - 1)
      }
    }
  }
}

/// A linear congruential generator (the constants of the C standard's
/// example, modulus 2^31): the float between `low` and `high` drawn from a
/// state, and the next state.
fn draw_between(
  state state: Int,
  low low: Float,
  high high: Float,
) -> #(Float, Int) {
  let next = { state * 1_103_515_245 + 12_345 } % 2_147_483_648
  let fraction = int.to_float(next) /. 2_147_483_648.0
  #(low +. fraction *. { high -. low }, next)
}

/// Starts a prototype on a workload and joins every player's connection to
/// its unit. Returns once every connection has received `Joined` for its own
/// unit, so nothing acts before the owner has the connection.
fn begin(start: Starter, workload: Workload) -> Run {
  let spawn =
    workload.spawn_list(workload)
    |> list.map(fn(unit) { #(unit.id, unit) })
    |> dict.from_list
  let key = reference.new()
  measurement.put_spawn_list(key, spawn)
  let assert Ok(started) = start(workload, key) as "the prototype did not start"
  let prototype = started.data
  let connections =
    list.map(ids(1, workload.players), fn(id) { #(id, process.new_subject()) })
  let selector =
    list.fold(connections, process.new_selector(), fn(selector, connection) {
      process.select_map(selector, connection.1, fn(delivery) {
        Event(connection: connection.0, delivery: delivery)
      })
    })
  list.each(connections, fn(connection) {
    prototype.join(connection.0, connection.1)
  })
  let joined =
    collect(selector, set.new(), note_joined, fn(joined) {
      set.size(joined) == workload.players
    })
  assert joined == set.from_list(ids(1, workload.players))
    as "every connection is joined to its own unit"
  Run(prototype:, key:, spawn:, connections: selector)
}

fn note_joined(joined: set.Set(Int), event: Event) -> set.Set(Int) {
  case event.delivery {
    update.Joined(unit_id:) -> {
      assert unit_id == event.connection
        as "a connection is joined to its own unit"
      set.insert(joined, unit_id)
    }
    update.Updated(_) | update.Hit(_) -> joined
  }
}

/// Stops the prototype and removes its spawn list.
fn finish(run: Run) -> Nil {
  run.prototype.stop()
  measurement.erase_spawn_list(run.key)
}

/// Receives deliveries from the connections one by one, folding each into the
/// accumulator, until the accumulator says it is finished. Waits for an event
/// each time, never for a fixed time; a delivery that does not come fails the
/// test after two seconds.
fn collect(
  connections: Selector(Event),
  accumulator: accumulator,
  note: fn(accumulator, Event) -> accumulator,
  finished: fn(accumulator) -> Bool,
) -> accumulator {
  use <- bool.guard(finished(accumulator), accumulator)
  let assert Ok(event) = process.selector_receive(connections, within: 2000)
    as "a delivery the test waits for did not arrive"
  collect(connections, note(accumulator, event), note, finished)
}

/// The integers from `first` to `last`, ascending.
fn ids(first: Int, last: Int) -> List(Int) {
  int.range(last, first - 1, [], fn(ids, id) { [id, ..ids] })
}

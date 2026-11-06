//// The map's rings under random moves, readiness and stealth
//// (`genesis_prime/world_map/map`), the rule run with the shell's part played by the
//// test. Expected values come from these places.
//// - A stealthed player stands in no ring: Jim's decision on issue 483 (Discord,
////   2026-11-06, option A), a server choice, since the client holds no rule
////   (`UnitProperty2.stealth_detection`).
//// - The ring rule (`genesis_prime/world_map/map` module doc): a ready player is in
////   a hostile creature's ring while within the aggro range of its place, and the map
////   sends `Approached` when it enters a ring and `Withdrew` when it leaves, to Live
////   creatures.
//// - The aggro range is 10 units (migration 0010); the Virtual Defense Dagun is
////   hostile to the Dominion, whose faction is the tests' players' (`Creature2.73465`).
//// The two Dagun spawns stand at x = 100 and 104 and their creatures stay Live: the
//// test fires no sweep and crashes none.

import genesis_prime/step
import genesis_prime/world_map/map.{type State}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import map_spawn_support
import map_support
import owned_test
import qcheck
import spawn_support

/// The spawns' x positions: spawn n is the n-th.
const spawn_xs = [100.0, 104.0]

/// The x positions the players move among: inside neither ring, inside one, inside
/// both.
const stops = [60.0, 92.0, 97.0, 102.0, 108.0, 112.0, 120.0]

/// The aggro range (migration 0010).
const aggro_range = 10.0

/// The connections of the players, who join before the first input.
const players = [1, 2, 3]

type Op {
  Moves(player: Int, stop: Int)
  Readies(player: Int)
  Stealths(player: Int, stealthed: Bool)
}

/// What the test knows of a player from the inputs it has given.
type Standing {
  Standing(x: Float, ready: Bool, stealthed: Bool)
}

type Play {
  Play(
    state: State,
    now_ms: Int,
    standing: Dict(Int, Standing),
    /// The creatures, by unit id, with the spawn's x.
    creatures: List(#(Int, Float)),
    /// The last ring message each creature was sent for each player.
    last: Dict(#(Int, Int), String),
    violations: List(String),
  )
}

fn op_of(n: Int) -> Op {
  let player = n % list.length(players) + 1
  let argument = n / list.length(players)
  case argument % 4 {
    0 | 1 -> Moves(player:, stop: { argument / 4 } % list.length(stops))
    2 -> Readies(player:)
    _ -> Stealths(player:, stealthed: { argument / 4 } % 2 == 0)
  }
}

fn x_of(stop: Int) -> Float {
  let assert Ok(x) = list.first(list.drop(stops, stop)) as "a stop"
  x
}

/// A map with the two Dagun spawns, started, and three players joined at x = 60,
/// each not ready.
fn begin() -> Play {
  let state =
    map_support.standing_with(
      incarnation: 1,
      spawns: list.index_map(spawn_xs, fn(x, index) {
        spawn_support.dagun(number: index + 1, x:)
      }),
      kinds: map_spawn_support.default_kinds(),
    )
  let #(state, _) =
    map_spawn_support.feed(
      state:,
      at_ms: map_spawn_support.started_at_ms,
      event: step.OwnEvent(step.Started),
    )
  let #(state, creatures) =
    list.fold(players, #(state, []), fn(held, player) {
      let #(state, creatures) = held
      let #(state, joined) =
        map_spawn_support.join(
          state:,
          at_ms: map_spawn_support.started_at_ms + player,
          connection: player,
          x: 60.0,
        )
      #(
        state,
        list.append(
          creatures,
          list.map(map_spawn_support.starts(joined), fn(start) {
            start.1.unit_id
          }),
        ),
      )
    })
  Play(
    state:,
    now_ms: map_spawn_support.started_at_ms + list.length(players),
    standing: dict.from_list(
      list.map(players, fn(player) {
        #(player, Standing(x: 60.0, ready: False, stealthed: False))
      }),
    ),
    creatures: list.zip(list.sort(creatures, int.compare), spawn_xs),
    last: dict.new(),
    violations: [],
  )
}

/// What the last ring message of a creature for a player was, for a violation's text.
fn last_said(last: Result(String, Nil)) -> String {
  case last {
    Ok(kind) -> kind
    Error(Nil) -> "nothing"
  }
}

/// The ring message a send says and the player it is for: `Approached by 2`.
fn parse(said: String) -> Result(#(String, Int), Nil) {
  case string.split(said, " by ") {
    [kind, number] ->
      result.map(int.parse(number), fn(player) { #(kind, player) })
    _ -> Error(Nil)
  }
}

/// The step's ring messages kept in `last`, with a violation for each that does not
/// follow the one before: the first to a creature for a player is `Approached`, and
/// they alternate.
fn noted(
  play play: Play,
  taken taken: step.ServiceStep(map.Outgoing),
  after after: String,
) -> Play {
  list.fold(map_spawn_support.ring_sends(taken), play, fn(play, sent) {
    let assert Ok(#(kind, player)) = parse(sent.1)
      as "a ring send says who it is by"
    let before = dict.get(play.last, #(sent.0, player))
    let follows = case kind, before {
      "Approached", Error(Nil) | "Approached", Ok("Withdrew") -> True
      "Withdrew", Ok("Approached") -> True
      _, _ -> False
    }
    Play(
      ..play,
      last: dict.insert(play.last, #(sent.0, player), kind),
      violations: case follows {
        True -> play.violations
        False -> [
          after
            <> ": creature "
            <> int.to_string(sent.0)
            <> " was sent "
            <> kind
            <> " for player "
            <> int.to_string(player)
            <> " after "
            <> last_said(before),
          ..play.violations
        ]
      },
    )
  })
}

/// A violation for each creature and player whose last ring message is not what the
/// ring rule says: `Approached` exactly when the player is ready, not stealthed and
/// within the aggro range of the creature's spawn.
fn checked(play play: Play, after after: String) -> Play {
  let found =
    list.flat_map(play.creatures, fn(creature) {
      list.filter_map(dict.to_list(play.standing), fn(entry) {
        let standing = entry.1
        let in_ring =
          standing.ready
          && !standing.stealthed
          && float.absolute_value(standing.x -. creature.1) <=. aggro_range
        let told =
          dict.get(play.last, #(creature.0, entry.0)) == Ok("Approached")
        case in_ring == told {
          True -> Error(Nil)
          False ->
            Ok(
              after
              <> ": player "
              <> int.to_string(entry.0)
              <> " is "
              <> case in_ring {
                True -> "in"
                False -> "not in"
              }
              <> " the ring of creature "
              <> int.to_string(creature.0)
              <> " but its last send was "
              <> last_said(dict.get(play.last, #(creature.0, entry.0))),
            )
        }
      })
    })
  Play(..play, violations: list.append(play.violations, found))
}

fn apply(play play: Play, op op: Op) -> Play {
  let at_ms = play.now_ms + 100
  let play = Play(..play, now_ms: at_ms)
  case op {
    Moves(player:, stop:) -> {
      let place_x = x_of(stop)
      let #(state, taken) =
        map_spawn_support.move(
          state: play.state,
          at_ms:,
          connection: player,
          x: place_x,
        )
      let assert Ok(held) = dict.get(play.standing, player)
      checked(
        play: noted(
          play: Play(
            ..play,
            state:,
            standing: dict.insert(
              play.standing,
              player,
              Standing(..held, x: place_x),
            ),
          ),
          taken:,
          after: "move "
            <> int.to_string(player)
            <> " to "
            <> float.to_string(place_x),
        ),
        after: "move "
          <> int.to_string(player)
          <> " to "
          <> float.to_string(place_x),
      )
    }
    Readies(player:) -> {
      let #(state, taken) =
        map_spawn_support.ready(state: play.state, at_ms:, connection: player)
      let assert Ok(held) = dict.get(play.standing, player)
      let after = "ready " <> int.to_string(player)
      checked(
        play: noted(
          play: Play(
            ..play,
            state:,
            standing: dict.insert(
              play.standing,
              player,
              Standing(..held, ready: True),
            ),
          ),
          taken:,
          after:,
        ),
        after:,
      )
    }
    Stealths(player:, stealthed:) -> {
      let #(state, taken) =
        map_spawn_support.stealth(
          state: play.state,
          at_ms:,
          connection: player,
          stealthed:,
        )
      let assert Ok(held) = dict.get(play.standing, player)
      let after =
        "stealth "
        <> int.to_string(player)
        <> case stealthed {
          True -> " on"
          False -> " off"
        }
      checked(
        play: noted(
          play: Play(
            ..play,
            state:,
            standing: dict.insert(
              play.standing,
              player,
              Standing(..held, stealthed:),
            ),
          ),
          taken:,
          after:,
        ),
        after:,
      )
    }
  }
}

fn run(ops ops: List(Op)) -> List(String) {
  list.fold(ops, begin(), fn(play, op) { apply(play:, op:) }).violations
}

pub fn over_random_moves_readies_and_stealth_changes_the_ring_sends_alternate_and_the_last_is_approached_exactly_for_a_ready_unstealthed_player_in_the_ring_test() -> Nil {
  use <- owned_test.run(60_000)
  use numbers <- qcheck.given(qcheck.generic_list(
    qcheck.bounded_int(from: 0, to: 1_000_000),
    qcheck.bounded_int(from: 1, to: 60),
  ))
  assert run(ops: list.map(numbers, op_of)) == []
    as "each creature is sent Approached, Withdrew in turn for each player, starting with Approached, and after each input the last one sent is Approached exactly when the player is ready, not stealthed and within 10 of the spawn"
}

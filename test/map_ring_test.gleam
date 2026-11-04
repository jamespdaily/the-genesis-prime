//// The map's rings (`genesis_prime/world_map/map`): which ready players stand within
//// a hostile creature's aggro range, told to the creature as `Approached` and
//// `Withdrew`. Expected values come from these places.
//// - The design of step F (the Design artifact of issue 367, section 1, option C and
////   options 1 and 8): a ready player crossing into a hostile Live creature's ring
////   sends one `Approached` with its place and its move's sequence number, crossing
////   out one `Withdrew`, moving inside or outside nothing; only after its client's
////   first 0xF2 (`opcode.0xf2`); at `Ready` and at a creature's start, one for each
////   ring the player stands in.
//// - The aggro range is 10 units (migration 0010).
//// - Hostile is a faction level of 0 to 2 (`world_data.creature_disposition`): the
////   Virtual Defense Dagun's faction 1442 is level 0 to Dominion 166 and 10 to Exile
////   167, the Virtual Battle Beast's 1441 the reverse (`Creature2.73465`,
////   `Creature2.73464`, `0x1403ad540`). The tests' characters are of the Dominion
////   (faction 166, `character_support`).

import connection_rule_support as support
import genesis_prime/game/start_place
import genesis_prime/step.{ConnectionId, OwnEvent, Started, Told}
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import gleam/list
import map_spawn_support
import map_support
import owned_test
import spawn_support

/// A map with these spawns, started.
fn map_with(spawns spawns: List(Spawn)) -> State {
  let state =
    map_support.standing_with(
      incarnation: 1,
      spawns:,
      kinds: map_spawn_support.default_kinds(),
    )
  let #(state, _) =
    map_spawn_support.feed(
      state:,
      at_ms: map_spawn_support.started_at_ms,
      event: OwnEvent(Started),
    )
  state
}

fn ready(
  state state: State,
  connection connection: Int,
) -> #(State, step.ServiceStep(map.Outgoing)) {
  map_spawn_support.feed(
    state:,
    at_ms: map_spawn_support.started_at_ms + 10,
    event: OwnEvent(
      Told(message: map.Ready(connection: ConnectionId(connection), seq: 0)),
    ),
  )
}

/// What the step tells creatures of the rings, by the creature's unit id.
fn ring_sends(taken: step.ServiceStep(map.Outgoing)) -> List(#(Int, String)) {
  map_spawn_support.creature_sends(taken)
  |> list.filter(fn(sent) {
    case sent.1 {
      "Approached by " <> _ | "Withdrew by " <> _ -> True
      _ -> False
    }
  })
}

/// The `Approached` the step sends, with its place's x and its sequence number.
fn approaches(taken: step.ServiceStep(map.Outgoing)) -> List(#(Float, Int)) {
  list.filter_map(map_spawn_support.sends(taken), fn(sent) {
    case sent.1 {
      map.Approached(place:, seq:, ..) -> Ok(#(start_place.x(place), seq))
      map.Withdrew(..)
      | map.Watched(..)
      | map.Unwatched(..)
      | map.Gone(..)
      | map.Retire
      | map.Joined(..)
      | map.NotJoined(..)
      | map.Left -> Error(Nil)
    }
  })
}

/// A Dagun at x = 100, joined by a Dominion player at x = 80 who is then ready.
fn one_dagun_and_a_ready_player() -> State {
  let state = map_with(spawns: [spawn_support.dagun(number: 1, x: 100.0)])
  let #(state, _) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 80.0,
    )
  let #(state, _) = ready(state:, connection: 1)
  state
}

pub fn a_ready_player_crossing_a_hostile_creatures_ring_sends_it_one_approached_and_crossing_out_one_withdrew_test() -> Nil {
  use <- owned_test.run(5000)
  let state = one_dagun_and_a_ready_player()
  let #(state, into) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  assert ring_sends(into) == [#(2, "Approached by 1")]
    as "92 is 8 from the Dagun at 100, inside the 10-unit ring; the creature is unit 2, after the player's 1"
  assert approaches(into) == [#(92.0, 6000)]
    as "the Approached carries the place and the move's sequence number"
  let #(state, inside) =
    map_spawn_support.move(state:, at_ms: 6100, connection: 1, x: 95.0)
  assert ring_sends(inside) == [] as "a move inside the ring sends nothing"
  let #(state, out) =
    map_spawn_support.move(state:, at_ms: 6200, connection: 1, x: 85.0)
  assert ring_sends(out) == [#(2, "Withdrew by 1")]
    as "85 is 15 away: out of the ring, one Withdrew"
  let #(_, outside) =
    map_spawn_support.move(state:, at_ms: 6300, connection: 1, x: 84.0)
  assert ring_sends(outside) == [] as "a move outside the ring sends nothing"
}

pub fn a_creature_friendly_or_neutral_to_the_mover_gets_no_approached_test() -> Nil {
  use <- owned_test.run(5000)
  // The Beast is level 10, Friendly, to the Dominion player (Faction2Relationship
  // 1441-166); the second spawn is synthetic, a creature Neutral to both factions
  // (hostile to neither), which a player may attack but which does not aggro.
  let beast = spawn_support.battle_beast(number: 1, x: 100.0)
  let neutral =
    Spawn(
      ..spawn_support.battle_beast(number: 2, x: 120.0),
      combat: creature_life.Combat(
        ..beast.combat,
        hostile_to: Hostile(exile: False, dominion: False),
      ),
    )
  let state = map_with(spawns: [beast, neutral])
  let #(state, _) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 80.0,
    )
  let #(state, _) = ready(state:, connection: 1)
  let #(state, friendly) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 95.0)
  let #(_, neutral_ring) =
    map_spawn_support.move(state:, at_ms: 6100, connection: 1, x: 118.0)
  assert ring_sends(friendly) == [] && ring_sends(neutral_ring) == []
    as "a Friendly or a Neutral creature has no ring for the player"
}

pub fn no_approached_before_ready_and_at_ready_one_for_each_ring_the_player_stands_in_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    map_with(spawns: [
      spawn_support.dagun(number: 1, x: 100.0),
      spawn_support.dagun(number: 2, x: 104.0),
    ])
  let #(state, joined) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 102.0,
    )
  assert ring_sends(joined) == [] as "a loading player is in no ring"
  let #(state, moved) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 101.0)
  assert ring_sends(moved) == [] as "still loading: no creature fights it"
  let #(_, readied) = ready(state:, connection: 1)
  assert ring_sends(readied)
    == [#(2, "Approached by 1"), #(3, "Approached by 1")]
    as "at its first 0xF2 the player stands in both rings: one Approached to each creature (units 2 and 3, after the player's 1), in the order of the spawns"
  assert approaches(readied) == [#(101.0, 6000), #(101.0, 6000)]
    as "each with the place and sequence number of the player's last move"
}

pub fn a_second_ready_in_one_stay_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let state = one_dagun_and_a_ready_player()
  let #(state, _) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  let #(_, again) = ready(state:, connection: 1)
  assert ring_sends(again) == [] as "the connection sends one Ready a stay"
}

pub fn a_creature_starting_where_a_ready_player_stands_in_its_ring_is_sent_one_approached_after_its_start_test() -> Nil {
  use <- owned_test.run(5000)
  let state = map_with(spawns: [spawn_support.dagun(number: 1, x: 100.0)])
  let #(state, joined) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 80.0,
    )
  let assert [#(watch, _)] = map_spawn_support.starts(joined)
    as "the player's sight starts the Dagun's creature"
  let #(state, _) = ready(state:, connection: 1)
  let #(state, _) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  // The creature crashes; its spawn waits its respawn time and starts again with
  // the player still in its ring.
  let #(state, _) =
    map_spawn_support.feed(state:, at_ms: 7000, event: step.WatchEnded(watch:))
  let #(_, restarted) =
    map_spawn_support.feed(
      state:,
      at_ms: 7000 + map_support.respawn_ms,
      event: OwnEvent(step.ServiceTimerFired(timer: step.TimerId(1))),
    )
  let assert [#(_, creature)] = map_spawn_support.starts(restarted)
  assert ring_sends(restarted) == [#(creature.unit_id, "Approached by 1")]
    as "the new creature is told the player stands in its ring"
  let kinds =
    list.filter_map(support.effects_of(restarted), fn(effect) {
      case effect {
        step.OwnEffect(step.StartCreature(..)) -> Ok("start")
        step.OwnEffect(step.Send(message:, ..)) ->
          case map_spawn_support.said(message) {
            "Approached by " <> _ -> Ok("approached")
            _ -> Error(Nil)
          }
        step.OwnEffect(step.Reply(..))
        | step.OwnEffect(step.StartServiceTimer(..))
        | step.OwnEffect(step.CancelServiceTimer(..))
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | step.Stop -> Error(Nil)
      }
    })
  assert kinds == ["start", "approached"] as "after the start, in the same step"
}

pub fn a_player_ready_before_any_move_of_its_stay_is_approached_with_the_connections_sequence_number_test() -> Nil {
  use <- owned_test.run(5000)
  // The player camped and entered again; its connection's last move was 5, before
  // the camp, and it has not moved in this stay (the review of 0929cb9).
  let state = map_with(spawns: [spawn_support.dagun(number: 1, x: 100.0)])
  let #(state, _) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 95.0,
    )
  let #(_, readied) =
    map_spawn_support.feed(
      state:,
      at_ms: map_spawn_support.started_at_ms + 10,
      event: OwnEvent(
        Told(message: map.Ready(connection: ConnectionId(1), seq: 5)),
      ),
    )
  assert approaches(readied) == [#(95.0, 5)]
    as "the Approached carries move 5, not 0: a creature holding move 5 of the earlier stay takes it"
}

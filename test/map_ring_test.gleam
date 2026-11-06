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
import genesis_prime/step.{ConnectionId, LogError, OwnEvent, Started, Told}
import genesis_prime/world_map/creature_life.{Hostile}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/stay.{type Stay}
import gleam/list
import map_spawn_support
import map_support
import owned_test
import spawn_support

/// The Virtual Defense Dagun's Creature2 id (`Creature2.73465`).
const virtual_defense_dagun = 73_465

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

/// The `Approached` the step sends, with its place's x and its sequence number.
fn approaches(taken: step.ServiceStep(map.Outgoing)) -> List(#(Float, Int)) {
  list.filter_map(map_spawn_support.sends(taken), fn(sent) {
    case sent.1 {
      map.Approached(place:, seq:, ..) -> Ok(#(start_place.x(place), seq))
      map.Withdrew(..)
      | map.Watched(..)
      | map.Unwatched(..)
      | map.Noticed(..)
      | map.Retire
      | map.Joined(..)
      | map.NotJoined(..)
      | map.Summoned(..)
      | map.NotSummoned(..)
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
  assert map_spawn_support.ring_sends(into) == [#(2, "Approached by 1")]
    as "92 is 8 from the Dagun at 100, inside the 10-unit ring; the creature is unit 2, after the player's 1"
  assert approaches(into) == [#(92.0, 6000)]
    as "the Approached carries the place and the move's sequence number"
  let #(state, inside) =
    map_spawn_support.move(state:, at_ms: 6100, connection: 1, x: 95.0)
  assert map_spawn_support.ring_sends(inside) == []
    as "a move inside the ring sends nothing"
  let #(state, out) =
    map_spawn_support.move(state:, at_ms: 6200, connection: 1, x: 85.0)
  assert map_spawn_support.ring_sends(out) == [#(2, "Withdrew by 1")]
    as "85 is 15 away: out of the ring, one Withdrew"
  let #(_, outside) =
    map_spawn_support.move(state:, at_ms: 6300, connection: 1, x: 84.0)
  assert map_spawn_support.ring_sends(outside) == []
    as "a move outside the ring sends nothing"
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
  assert map_spawn_support.ring_sends(friendly) == []
    && map_spawn_support.ring_sends(neutral_ring) == []
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
  assert map_spawn_support.ring_sends(joined) == []
    as "a loading player is in no ring"
  let #(state, moved) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 101.0)
  assert map_spawn_support.ring_sends(moved) == []
    as "still loading: no creature fights it"
  let #(_, readied) = ready(state:, connection: 1)
  assert map_spawn_support.ring_sends(readied)
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
  assert map_spawn_support.ring_sends(again) == []
    as "the connection sends one Ready a stay"
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
  assert map_spawn_support.ring_sends(restarted)
    == [#(creature.unit_id, "Approached by 1")]
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

// ---- a stealthed player (issue 483) ----

/// What the step sends creatures as `Approached`: the player's connection, its unit,
/// the place's x, the move's sequence number and the stay, in the order sent.
fn approaches_in_full(
  taken: step.ServiceStep(map.Outgoing),
) -> List(#(Int, Int, Float, Int, Stay)) {
  list.filter_map(map_spawn_support.sends(taken), fn(sent) {
    case sent.1 {
      map.Approached(by: ConnectionId(by), unit_id:, place:, seq:, stay:) ->
        Ok(#(by, unit_id, start_place.x(place), seq, stay))
      map.Withdrew(..)
      | map.Watched(..)
      | map.Unwatched(..)
      | map.Noticed(..)
      | map.Retire
      | map.Joined(..)
      | map.NotJoined(..)
      | map.Summoned(..)
      | map.NotSummoned(..)
      | map.Left -> Error(Nil)
    }
  })
}

fn stealth(
  state state: State,
  at_ms at_ms: Int,
  stealthed stealthed: Bool,
) -> #(State, step.ServiceStep(map.Outgoing)) {
  map_spawn_support.stealth(state:, at_ms:, connection: 1, stealthed:)
}

pub fn a_stealthed_ready_player_crossing_a_hostile_creatures_ring_sends_it_no_approached_and_crossing_out_no_withdrew_test() -> Nil {
  use <- owned_test.run(5000)
  let state = one_dagun_and_a_ready_player()
  let #(state, entered) = stealth(state:, at_ms: 5900, stealthed: True)
  assert map_spawn_support.ring_sends(entered) == []
    as "outside the ring (80 is 20 from the Dagun at 100): nothing to withdraw from"
  let #(state, into) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  assert map_spawn_support.ring_sends(into) == []
    as "92 is 8 from the Dagun, inside the 10-unit ring, but a stealthed player stands in no ring"
  let #(state, inside) =
    map_spawn_support.move(state:, at_ms: 6100, connection: 1, x: 95.0)
  assert map_spawn_support.ring_sends(inside) == []
  let #(_, out) =
    map_spawn_support.move(state:, at_ms: 6200, connection: 1, x: 85.0)
  assert map_spawn_support.ring_sends(out) == []
    as "crossing out sends no Withdrew: the creature never held the player in its ring"
}

pub fn a_ready_player_in_two_rings_that_enters_stealth_sends_withdrew_to_each_live_creature_in_spawn_order_and_its_ring_is_then_empty_test() -> Nil {
  use <- owned_test.run(5000)
  // Spawns at 100, 104 and 106; the player at 103 is within 10 of each. The second
  // spawn's creature crashes, so its spawn is waiting for its restart, not Live.
  let state =
    map_with(spawns: [
      spawn_support.dagun(number: 1, x: 100.0),
      spawn_support.dagun(number: 2, x: 104.0),
      spawn_support.dagun(number: 3, x: 106.0),
    ])
  let #(state, joined) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 103.0,
    )
  let assert [#(_, first), #(second_watch, _), #(_, third)] =
    map_spawn_support.starts(joined)
    as "the player's sight starts the three creatures, in spawn order"
  let #(state, readied) = ready(state:, connection: 1)
  assert list.length(map_spawn_support.ring_sends(readied)) == 3
    as "the player stands in all three rings once ready"
  let #(state, crashed) =
    map_spawn_support.creature_ended(state:, at_ms: 6000, watch: second_watch)
  let assert [#(restart, _)] = map_spawn_support.timers(crashed)
    as "the crashed spawn waits for its restart timer"
  let #(state, entered) = stealth(state:, at_ms: 6100, stealthed: True)
  assert map_spawn_support.ring_sends(entered)
    == [
      #(first.unit_id, "Withdrew by 1"),
      #(third.unit_id, "Withdrew by 1"),
    ]
    as "Withdrew to the two Live creatures, in spawn order; nothing to the spawn that is waiting"
  let #(_, restarted) =
    map_spawn_support.feed(
      state:,
      at_ms: 6000 + map_support.respawn_ms,
      event: OwnEvent(step.ServiceTimerFired(timer: step.TimerId(restart))),
    )
  assert list.length(map_spawn_support.starts(restarted)) == 1
    as "the waiting spawn's creature starts again, a player sees it"
  assert map_spawn_support.ring_sends(restarted) == []
    as "the player's ring is empty: the spawn that was not Live had its ring dropped with the others, and the new creature is sent no Approached"
}

pub fn a_stealthed_player_that_leaves_stealth_inside_a_ring_sends_that_creature_one_approached_as_a_walk_in_does_test() -> Nil {
  use <- owned_test.run(5000)
  let state = one_dagun_and_a_ready_player()
  let #(state, _) = stealth(state:, at_ms: 5900, stealthed: True)
  let #(state, _) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  let #(state, left) = stealth(state:, at_ms: 6100, stealthed: False)
  assert map_spawn_support.ring_sends(left) == [#(2, "Approached by 1")]
    as "one Approached to the Dagun (unit 2, after the player's 1)"
  assert approaches_in_full(left)
    == [#(1, 1, 92.0, 6000, map_support.stay(count: 1))]
    as "the player's connection and unit, its place, the sequence number of its last move and its stay"
  let #(_, again) = stealth(state:, at_ms: 6200, stealthed: False)
  assert map_spawn_support.ring_sends(again) == []
    as "a second tell of the same value sends nothing"
}

pub fn a_stealth_changed_of_the_value_the_map_holds_sends_nothing_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let state = one_dagun_and_a_ready_player()
  let #(state, _) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  let #(unchanged, not_stealthed) =
    stealth(state:, at_ms: 6100, stealthed: False)
  assert support.effects_of(not_stealthed) == [] && unchanged == state
    as "a player the map holds unstealthed, told unstealthed: no send, no log, the same state"
  let #(state, entered) = stealth(state:, at_ms: 6200, stealthed: True)
  assert map_spawn_support.ring_sends(entered) == [#(2, "Withdrew by 1")]
    as "the first tell of True is a change"
  let #(again, repeated) = stealth(state:, at_ms: 6300, stealthed: True)
  assert support.effects_of(repeated) == [] && again == state
    as "a player the map holds stealthed, told stealthed: no send, no log, the same state"
}

pub fn a_player_stealthed_before_its_ready_is_sent_to_no_creature_at_ready_and_leaving_stealth_sends_approached_to_each_ring_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    map_with(spawns: [
      spawn_support.dagun(number: 1, x: 100.0),
      spawn_support.dagun(number: 2, x: 104.0),
    ])
  let #(state, _) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 102.0,
    )
  let #(state, entered) = stealth(state:, at_ms: 5100, stealthed: True)
  assert support.effects_of(entered) == []
    as "a player still loading is only marked"
  let #(state, _) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 101.0)
  let #(state, readied) = ready(state:, connection: 1)
  assert map_spawn_support.ring_sends(readied) == []
    as "its first 0xF2 finds it in no ring: opcode.0xf2 makes it ready, stealth keeps it out"
  let #(_, left) = stealth(state:, at_ms: 6100, stealthed: False)
  assert map_spawn_support.ring_sends(left)
    == [#(2, "Approached by 1"), #(3, "Approached by 1")]
    as "leaving stealth sends one Approached to each ring it stands in, in spawn order"
  assert approaches_in_full(left)
    == [
      #(1, 1, 101.0, 6000, map_support.stay(count: 1)),
      #(1, 1, 101.0, 6000, map_support.stay(count: 1)),
    ]
}

/// A Dagun at x = 100 whose creature a player at x = 80 started, and that player
/// ready, then stealthed, with the creature's watch.
fn a_stealthed_ready_player_and_the_creature_it_started() -> #(
  State,
  step.WatchId,
) {
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
  let #(state, _) = stealth(state:, at_ms: 5900, stealthed: True)
  #(state, watch)
}

fn a_first_viewer_starts_the_creature_with_the_stealthed_player_in_its_ring() -> Nil {
  // The player is far, ready and stealthed; its one move puts it in sight of the
  // Dagun and in its ring together.
  let state = map_with(spawns: [spawn_support.dagun(number: 1, x: 100.0)])
  let #(state, _) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: map_spawn_support.far,
    )
  let #(state, _) = ready(state:, connection: 1)
  let #(state, _) = stealth(state:, at_ms: 5900, stealthed: True)
  let #(state, moved) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  let assert [#(_, creature)] = map_spawn_support.starts(moved)
    as "the move starts the creature: the player is the first to see the spawn"
  assert map_spawn_support.ring_sends(moved) == []
    as "first viewer: the creature starts and is sent no Approached"
  let #(_, left) = stealth(state:, at_ms: 6100, stealthed: False)
  assert map_spawn_support.ring_sends(left)
    == [#(creature.unit_id, "Approached by 1")]
    as "after the player leaves stealth the Live creature gets one"
}

fn a_restart_after_a_crash_with_the_stealthed_player_in_its_ring() -> Nil {
  let #(state, watch) = a_stealthed_ready_player_and_the_creature_it_started()
  let #(state, _) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  let #(state, crashed) =
    map_spawn_support.creature_ended(state:, at_ms: 7000, watch:)
  let assert [#(restart, _)] = map_spawn_support.timers(crashed)
    as "the spawn waits for its restart timer"
  let #(state, restarted) =
    map_spawn_support.feed(
      state:,
      at_ms: 7000 + map_support.respawn_ms,
      event: OwnEvent(step.ServiceTimerFired(timer: step.TimerId(restart))),
    )
  let assert [#(_, creature)] = map_spawn_support.starts(restarted)
    as "a creature starts again, the player sees the spawn"
  assert map_spawn_support.ring_sends(restarted) == []
    as "restart after a crash: the creature is sent no Approached"
  let #(_, left) =
    stealth(state:, at_ms: 8000 + map_support.respawn_ms, stealthed: False)
  assert map_spawn_support.ring_sends(left)
    == [#(creature.unit_id, "Approached by 1")]
}

fn a_retired_creatures_end_with_a_viewer_and_the_stealthed_player_in_its_ring() -> Nil {
  let #(state, watch) = a_stealthed_ready_player_and_the_creature_it_started()
  let #(state, _) =
    map_spawn_support.move(
      state:,
      at_ms: 7000,
      connection: 1,
      x: map_spawn_support.far,
    )
  let #(state, retired) = map_spawn_support.sweep(state:, at_ms: 75_000)
  assert list.length(map_spawn_support.creature_sends(retired)) == 1
    as "the idle creature is told to retire"
  let #(state, back) =
    map_spawn_support.move(state:, at_ms: 75_050, connection: 1, x: 92.0)
  assert map_spawn_support.starts(back) == []
    && map_spawn_support.ring_sends(back) == []
    as "the creature retires: nothing starts and it is told nothing"
  let #(state, ended) =
    map_spawn_support.creature_ended(state:, at_ms: 75_100, watch:)
  let assert [#(_, creature)] = map_spawn_support.starts(ended)
    as "at its end a creature starts for the viewer"
  assert map_spawn_support.ring_sends(ended) == []
    as "retired creature's end with a viewer: no Approached"
  let #(_, left) = stealth(state:, at_ms: 75_200, stealthed: False)
  assert map_spawn_support.ring_sends(left)
    == [#(creature.unit_id, "Approached by 1")]
}

pub fn a_creature_that_starts_where_a_stealthed_ready_player_stands_in_its_ring_is_sent_no_approached_for_each_start_path_test() -> Nil {
  use <- owned_test.run(5000)
  a_first_viewer_starts_the_creature_with_the_stealthed_player_in_its_ring()
  a_restart_after_a_crash_with_the_stealthed_player_in_its_ring()
  a_retired_creatures_end_with_a_viewer_and_the_stealthed_player_in_its_ring()
}

pub fn a_summoned_creature_whose_ring_holds_a_stealthed_ready_player_gets_no_approached_at_its_start_and_one_when_the_player_leaves_stealth_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = map_spawn_support.started(at: [])
  let #(state, _) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 100.0,
    )
  let #(state, _) = ready(state:, connection: 1)
  let #(state, _) = stealth(state:, at_ms: 5900, stealthed: True)
  let #(state, summoned) =
    map_spawn_support.summon(
      state:,
      at_ms: 6000,
      caller: 50,
      connection: 1,
      creature_id: virtual_defense_dagun,
    )
  let assert [#(_, creature)] = map_spawn_support.starts(summoned)
    as "the summon starts the Dagun's creature at the player's place"
  assert map_spawn_support.ring_sends(summoned) == []
    as "the player stands at the creature's place, in its ring, but is stealthed: no Approached at its start"
  let #(_, left) = stealth(state:, at_ms: 6100, stealthed: False)
  assert map_spawn_support.ring_sends(left)
    == [#(creature.unit_id, "Approached by 1")]
    as "one when the player leaves stealth"
}

pub fn a_stealth_changed_from_a_connection_not_in_the_map_changes_nothing_and_writes_one_error_line_test() -> Nil {
  use <- owned_test.run(5000)
  let state = one_dagun_and_a_ready_player()
  let #(after, taken) =
    map_spawn_support.stealth(
      state:,
      at_ms: 6000,
      connection: 9,
      stealthed: True,
    )
  assert after == state as "nothing changes"
  assert map_spawn_support.sends(taken) == [] as "nothing is sent"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "one error line, as a Moved from a connection not in the map"
}

pub fn a_player_stealthed_in_one_stay_that_leaves_and_joins_again_is_not_stealthed_in_the_map_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = a_stealthed_ready_player_and_the_creature_it_started()
  let #(state, _) = map_spawn_support.leave(state:, at_ms: 6000, connection: 1)
  let #(state, joined) =
    map_spawn_support.join(state:, at_ms: 6100, connection: 1, x: 80.0)
  assert map_spawn_support.starts(joined) == []
    as "the creature still runs: the new stay is told Watched"
  let #(state, _) = ready(state:, connection: 1)
  let #(_, into) =
    map_spawn_support.move(state:, at_ms: 6200, connection: 1, x: 92.0)
  assert list.length(map_spawn_support.ring_sends(into)) == 1
    && list.all(map_spawn_support.ring_sends(into), fn(sent) {
      sent.1 == "Approached by 1"
    })
    as "the next stay starts unstealthed (cast.left clears the stealth, #474): its move into the ring sends Approached"
}

pub fn the_watch_of_a_stealthed_player_in_a_ring_ending_sends_its_creatures_unwatched_and_no_withdrew_or_approached_test() -> Nil {
  use <- owned_test.run(5000)
  let state = map_with(spawns: [spawn_support.dagun(number: 1, x: 100.0)])
  let #(state, joined) =
    map_spawn_support.join(
      state:,
      at_ms: map_spawn_support.started_at_ms + 1,
      connection: 1,
      x: 80.0,
    )
  let assert [#(_, creature)] = map_spawn_support.starts(joined)
    as "the player's sight starts the creature"
  let assert [#(player_watch, _)] = support.watches(joined)
    as "the join opens a watch on the player's connection"
  let #(state, _) = ready(state:, connection: 1)
  let #(state, _) = stealth(state:, at_ms: 5900, stealthed: True)
  let #(state, _) =
    map_spawn_support.move(state:, at_ms: 6000, connection: 1, x: 92.0)
  let #(_, ended) =
    map_spawn_support.feed(
      state:,
      at_ms: 6100,
      event: step.WatchEnded(watch: player_watch),
    )
  assert map_spawn_support.creature_sends(ended)
    == [#(creature.unit_id, "Unwatched by 1")]
    as "the map's end rule: the creature that saw the player is sent Unwatched, and nothing else (the failure table row 'a player in a ring leaves, camps or its connection ends')"
}

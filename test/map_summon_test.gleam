//// A development summon in the map's rule (`genesis_prime/world_map/map`
//// `Summon`): a creature of a Creature2 row starts at a player's place and facing
//// as a run-only spawn, is seen and fights as any spawn, and never comes back.
//// Expected values come from these places.
//// - The summon sequence in the map's module doc (the Design artifact of issue
////   425): the creature starts at the asking player's place and facing for the
////   players who see that place, under the next run-only id, which counts down
////   from -1 and is never a stored id (a stored id is above 0, migration 0008's
////   `spawn_id_is_positive`); the asker is answered `Summoned` with the unit id
////   once the start's outcome is known, and `NotSummoned` otherwise; a creature
////   that ends is dropped with no restart timer.
//// - The service shell's contract (`genesis_prime/service/shell` `take`): a
////   creature that did not start is the rule's next input after the step's
////   effects, before any timer's firing, so a timer the step started is the first
////   input that says the start had no failure.
//// - The Virtual Defense Dagun (Creature2 73465) is hostile to the Dominion, whose
////   faction is the tests' players' (`Creature2.73465`, `0x1403ad540`), and the
////   aggro range is 10 units (migration 0010). Sight is 1024 units
////   (`genesis_prime/world_map/sight`).
//// - The world's unit ids start at 1 and each player and creature takes the next.

import character_tables
import connection_rule_support as support
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/step.{CallerId, ConnectionId, WatchId}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source.{RunOnly, Summoned}
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import map_spawn_support as spawns
import map_support
import owned_test
import place_support
import planted_table
import spawn_support

/// The Virtual Defense Dagun.
const dagun = 73_465

/// The Virtual Battle Beast.
const beast = 73_464

/// A Creature2 id with no row in any table.
const no_such_creature = 200_002

/// Where the first player stands when it summons: a place with a facing of its
/// own, so a summon that took the creature's facing from elsewhere is caught.
fn standing() -> Place {
  start_place.turned(
    spawns.at(100.0),
    Facing(yaw: 1.5, pitch: 0.25, roll: -0.5),
  )
}

/// A map with no stored spawn, started, and three Dominion players: connection 1
/// at `standing()` (unit 1), connection 2 400 units from it (unit 2, sees it) and
/// connection 3 far from both (unit 3, does not).
fn three_players() -> State {
  let #(state, _) = spawns.started(at: [])
  let #(state, _) = spawns.join(state:, at_ms: 5100, connection: 1, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 5200, connection: 2, x: 500.0)
  let #(state, _) =
    spawns.join(state:, at_ms: 5300, connection: 3, x: spawns.far)
  let #(state, _) =
    spawns.move_to(state:, at_ms: 5400, connection: 1, place: standing())
  state
}

/// The summon of a Dagun by connection 1, asked by caller 50, at 6000.
fn summoned_dagun(
  state state: State,
) -> #(State, step.ServiceStep(map.Outgoing)) {
  spawns.summon(
    state:,
    at_ms: 6000,
    caller: 50,
    connection: 1,
    creature_id: dagun,
  )
}

/// The only creature a step starts, with its watch.
fn the_start(
  taken: step.ServiceStep(map.Outgoing),
) -> #(step.WatchId, step.CreatureStart) {
  let assert [start] = spawns.starts(taken) as "the step starts one creature"
  start
}

pub fn a_summon_starts_the_creature_at_the_players_place_and_facing_for_the_players_who_see_that_place_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = summoned_dagun(state: three_players())
  let #(_, creature) = the_start(taken)
  assert creature.spawn
    == RunOnly(Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(dagun),
      level: Some(1),
      place: standing(),
    ))
    as "the first run-only id, the creature asked for, the Dagun's minLevel 1 (Creature2.73465) the summon had no level to replace, and the asking player's place with its facing"
  assert creature.unit_id == 4
    as "the unit id after the three players', so none is a player's"
  assert creature.viewers
    == [
      #(ConnectionId(1), map_support.stay(count: 1)),
      #(ConnectionId(2), map_support.stay(count: 1)),
    ]
    as "the players who see the place get the creature, each by its stay, in connection order; the far one does not"
}

pub fn the_summoner_is_answered_once_the_start_is_known_not_with_the_start_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = summoned_dagun(state: three_players())
  assert support.replies(taken) == []
    as "a start that fails is the rule's next input, so the answer waits for it"
  assert spawns.timers(taken) == [#(-1, 0)]
    as "a timer under the run-only id is the next input after a start that did not fail"
  let #(_, settled) = spawns.start_settled(state:, at_ms: 6000, spawn: -1)
  assert support.replies(settled) == [#(CallerId(50), map.Summoned(unit_id: 4))]
    as "the timer's firing answers the asker with the creature's unit id"
}

pub fn a_summoned_creature_is_live_under_its_run_only_spawn_with_its_viewers_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = summoned_dagun(state: three_players())
  let #(watch, creature) = the_start(taken)
  let assert Ok(map.Live(unit_id: 4, life:, viewers:, idle_since_ms: None)) =
    map.spawn_state(state:, spawn: SpawnId(-1))
    as "the run-only spawn is live under the unit id the creature started with"
  let WatchId(creature_life) = watch
  assert life == creature_life && creature.life == life
    as "its life is the number of the watch it is started under"
  assert viewers == set.from_list([ConnectionId(1), ConnectionId(2)])
  let assert Ok(spawn) = map.run_spawn(state:, spawn: SpawnId(-1))
    as "the map keeps the run-only spawn"
  assert spawn.place == standing()
  assert map.unit_id_of(state:, spawn: SpawnId(-1)) == Ok(4)
}

pub fn a_summon_tells_the_creature_of_each_ready_player_in_its_aggro_range_test() -> Nil {
  use <- owned_test.run(5000)
  // The Dagun is hostile to the Dominion (level 0 to faction 166). Player 1
  // stands where it is summoned, inside the 10-unit ring; player 2, ready too,
  // stands 400 away; player 3 is not ready.
  let state = three_players()
  let #(state, _) = spawns.ready(state:, at_ms: 5500, connection: 1)
  let #(state, _) = spawns.ready(state:, at_ms: 5600, connection: 2)
  let #(_, taken) = summoned_dagun(state:)
  assert spawns.creature_sends(taken) == [#(4, "Approached by 1")]
    as "the creature is told of the one ready player in its ring, and is started first"
}

pub fn a_player_not_ready_is_not_told_to_a_summoned_creature_but_is_when_ready_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = summoned_dagun(state: three_players())
  assert spawns.creature_sends(taken) == []
    as "no player's client has loaded the world, so no ring holds anyone"
  let #(_, ready) = spawns.ready(state:, at_ms: 6100, connection: 1)
  assert spawns.creature_sends(ready) == [#(4, "Approached by 1")]
    as "the player's first 0xF2 finds it in the run-only creature's ring"
}

pub fn a_ready_player_crossing_a_summoned_creatures_ring_is_sent_approached_and_withdrew_test() -> Nil {
  use <- owned_test.run(5000)
  let state = three_players()
  let #(state, _) = spawns.ready(state:, at_ms: 5500, connection: 2)
  let #(state, _) = summoned_dagun(state:)
  let #(state, into) = spawns.move(state:, at_ms: 7000, connection: 2, x: 92.0)
  assert spawns.creature_sends(into) == [#(4, "Approached by 2")]
    as "92 is 8 from the creature at 100, inside the ring the run-only spawn holds"
  let #(_, out) = spawns.move(state:, at_ms: 7100, connection: 2, x: 85.0)
  assert spawns.creature_sends(out) == [#(4, "Withdrew by 2")]
    as "85 is 15 away, out of it"
}

pub fn a_player_moving_into_and_out_of_sight_of_a_summoned_creature_is_told_watched_and_unwatched_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = summoned_dagun(state: three_players())
  let #(state, into) =
    spawns.move(state:, at_ms: 7000, connection: 3, x: 1000.0)
  assert spawns.creature_sends(into) == [#(4, "Watched by 3")]
    as "900 from the creature at 100 is inside the 1024 sight, as a stored spawn's"
  let #(state, still) =
    spawns.move(state:, at_ms: 7100, connection: 3, x: 1010.0)
  assert spawns.creature_sends(still) == []
    as "it saw the creature and still does"
  let #(state, out) =
    spawns.move(state:, at_ms: 7200, connection: 3, x: spawns.far)
  assert spawns.creature_sends(out) == [#(4, "Unwatched by 3")]
  let #(_, joined) = spawns.join(state:, at_ms: 7300, connection: 4, x: 600.0)
  assert spawns.creature_sends(joined) == [#(4, "Watched by 4")]
    as "a player that joins in sight of it is told to it as a join near a stored spawn is"
}

pub fn a_summon_at_a_level_starts_the_creature_at_that_level_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    spawns.summon_at_level(
      state: three_players(),
      at_ms: 6000,
      caller: 50,
      connection: 1,
      creature_id: dagun,
      level: Some(3),
    )
  let #(_, creature) = the_start(taken)
  assert creature.spawn
    == RunOnly(Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(dagun),
      level: Some(3),
      place: standing(),
    ))
    as "the level asked for goes with the run-only spawn to the creature's start, which builds the spawn again from it"
  let assert Ok(run_spawn) = map.run_spawn(state:, spawn: SpawnId(-1))
    as "the map keeps the spawn the summon made"
  assert run_spawn.level == 3 as "stat 10 is the level the summon named"
}

pub fn a_level_with_no_creature_level_row_is_refused_naming_it_and_starts_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    spawns.summon_at_level(
      state: three_players(),
      at_ms: 6000,
      caller: 50,
      connection: 1,
      creature_id: dagun,
      level: Some(51),
    )
  assert support.replies(taken)
    == [
      #(
        CallerId(50),
        map.NotSummoned(
          map.CreatureRefused(spawn.NoCreatureLevelRow(level: 51)),
        ),
      ),
    ]
    as "the answer is at once, naming the level the tables hold no CreatureLevel row for (the planted tables hold rows 1 to 50 and 101)"
  assert spawns.starts(taken) == [] && spawns.timers(taken) == []
  assert map.run_spawn(state:, spawn: SpawnId(-1)) == Error(Nil)
    as "nothing was kept"
  let #(_, next) = summoned_dagun(state:)
  let #(_, creature) = the_start(next)
  assert creature.unit_id == 4
    as "a refusal takes no run-only id and no unit id"
}

pub fn a_creature2_id_with_no_row_is_refused_and_starts_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    spawns.summon(
      state: three_players(),
      at_ms: 6000,
      caller: 50,
      connection: 1,
      creature_id: no_such_creature,
    )
  assert support.replies(taken)
    == [
      #(
        CallerId(50),
        map.NotSummoned(
          map.CreatureRefused(
            spawn.FailsTheChecks(
              spawn.NoCreatureRow(Creature2Id(no_such_creature)),
            ),
          ),
        ),
      ),
    ]
    as "the answer is at once, naming the Creature2 id the client has no row for"
  assert spawns.starts(taken) == [] && spawns.timers(taken) == []
  assert map.run_spawn(state:, spawn: SpawnId(-1)) == Error(Nil)
    as "nothing was kept"
  let #(_, next) = summoned_dagun(state:)
  let #(_, creature) = the_start(next)
  assert creature.spawn
    == RunOnly(Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(dagun),
      level: Some(1),
      place: standing(),
    ))
    as "a refusal takes no run-only id and no unit id"
  assert creature.unit_id == 4
}

pub fn a_creature_failing_a_client_check_is_refused_and_starts_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x140485790: the client loads no creature whose modelScale is not above 0.
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("modelScale", planted_table.Float(0.0)),
    ])
  let taken =
    spawn_support.with_summon_checks_of(files:, then: fn(checks) {
      let state =
        map_support.with_summons(
          incarnation: 1,
          spawns: [],
          objects: [],
          kinds: spawns.default_kinds(),
          summons: checks,
        )
      let #(state, _) =
        spawns.feed(
          state:,
          at_ms: spawns.started_at_ms,
          event: step.OwnEvent(step.Started),
        )
      let #(state, _) = spawns.join(state:, at_ms: 5100, connection: 1, x: 0.0)
      let #(_, taken) =
        spawns.summon(
          state:,
          at_ms: 6000,
          caller: 50,
          connection: 1,
          creature_id: beast,
        )
      taken
    })
  assert support.replies(taken)
    == [
      #(
        CallerId(50),
        map.NotSummoned(
          map.CreatureRefused(
            spawn.FailsTheChecks(spawn.NotLoadedByTheClient(
              creature_id: Creature2Id(beast),
              rule: spawn.ModelScaleNotAbove0,
            )),
          ),
        ),
      ),
    ]
    as "the row the client would not load is refused naming its rule"
  assert spawns.starts(taken) == []
}

pub fn a_connection_with_no_player_here_is_answered_no_player_here_and_nothing_starts_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    spawns.summon(
      state: three_players(),
      at_ms: 6000,
      caller: 50,
      connection: 9,
      creature_id: dagun,
    )
  assert support.replies(taken)
    == [#(CallerId(50), map.NotSummoned(map.NoPlayerHere))]
  assert spawns.starts(taken) == [] && spawns.timers(taken) == []
}

pub fn two_summons_get_two_distinct_negative_run_only_ids_never_a_stored_one_test() -> Nil {
  use <- owned_test.run(5000)
  // A stored spawn, number 1, stands far from the players: a run-only id is not
  // its id or any other positive one.
  let state =
    map_support.standing(incarnation: 1, spawns: [
      spawn_support.battle_beast(number: 1, x: 40_000.0),
    ])
  let #(state, _) =
    spawns.feed(
      state:,
      at_ms: spawns.started_at_ms,
      event: step.OwnEvent(step.Started),
    )
  let #(state, _) = spawns.join(state:, at_ms: 5100, connection: 1, x: 0.0)
  let #(state, first) =
    spawns.summon(
      state:,
      at_ms: 6000,
      caller: 50,
      connection: 1,
      creature_id: dagun,
    )
  let #(state, second) =
    spawns.summon(
      state:,
      at_ms: 6000,
      caller: 51,
      connection: 1,
      creature_id: dagun,
    )
  let ids =
    list.map([first, second], fn(taken) {
      let #(_, creature) = the_start(taken)
      spawn_source.id(creature.spawn)
    })
  assert ids == [SpawnId(-1), SpawnId(-2)]
    as "run-only ids count down from -1, one to each summon"
  let units =
    list.map([first, second], fn(taken) {
      let #(_, creature) = the_start(taken)
      creature.unit_id
    })
  assert units == [2, 3] as "each creature has a unit id of its own"
  assert spawns.timers(first) == [#(-1, 0)]
    && spawns.timers(second) == [#(-2, 0)]
    as "each answer waits for its own start"
  let #(state, one) = spawns.start_settled(state:, at_ms: 6000, spawn: -2)
  assert support.replies(one) == [#(CallerId(51), map.Summoned(unit_id: 3))]
    as "the answers are told apart by their run-only id, whichever settles first"
  let #(_, other) = spawns.start_settled(state:, at_ms: 6000, spawn: -1)
  assert support.replies(other) == [#(CallerId(50), map.Summoned(unit_id: 2))]
}

pub fn a_summoned_creature_that_ends_is_gone_to_every_player_and_never_comes_back_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = summoned_dagun(state: three_players())
  let #(watch, _) = the_start(taken)
  let #(state, _) = spawns.start_settled(state:, at_ms: 6000, spawn: -1)
  let #(state, ended) = spawns.creature_ended(state:, at_ms: 66_000, watch:)
  assert spawns.player_sends(ended)
    == [#(1, "Gone 4"), #(2, "Gone 4"), #(3, "Gone 4")]
    as "its corpse goes as any creature's, to every player, those who see it and those who do not"
  assert spawns.timers(ended) == [] && spawns.starts(ended) == []
    as "a run-only spawn sets no restart timer and starts nothing"
  assert map.spawn_state(state:, spawn: SpawnId(-1)) == Error(Nil)
    as "its state is dropped"
  assert map.run_spawn(state:, spawn: SpawnId(-1)) == Error(Nil)
    as "its run-only spawn is dropped"
  assert map.unit_id_of(state:, spawn: SpawnId(-1)) == Error(Nil)
    as "its unit id is dropped"
  let #(state, _) =
    spawns.move(state:, at_ms: 67_000, connection: 1, x: spawns.far)
  let #(state, back) =
    spawns.move(state:, at_ms: 68_000, connection: 1, x: 100.0)
  assert spawns.starts(back) == [] && spawns.creature_sends(back) == []
    as "a player that sees the place again finds no creature to start"
  let #(_, joined) = spawns.join(state:, at_ms: 69_000, connection: 4, x: 100.0)
  assert spawns.starts(joined) == []
}

pub fn a_summoned_creature_that_crashes_is_not_started_again_where_a_stored_one_is_test() -> Nil {
  use <- owned_test.run(5000)
  // A stored spawn and a summon, both crash while a player sees them: the stored
  // spawn waits its kind's 60 s respawn, the run-only one has no timer.
  let state =
    map_support.standing(incarnation: 1, spawns: [
      spawn_support.battle_beast(number: 1, x: 100.0),
    ])
  let #(state, _) =
    spawns.feed(
      state:,
      at_ms: spawns.started_at_ms,
      event: step.OwnEvent(step.Started),
    )
  let #(state, joined) = spawns.join(state:, at_ms: 5100, connection: 1, x: 0.0)
  let #(stored_watch, _) = the_start(joined)
  let #(state, taken) = summoned_dagun(state:)
  let #(summoned_watch, _) = the_start(taken)
  let #(state, stored) =
    spawns.creature_ended(state:, at_ms: 7000, watch: stored_watch)
  assert spawns.timers(stored) == [#(1, map_support.respawn_ms)]
    as "the stored spawn is started again after its kind's respawn time"
  let #(state, crashed) =
    spawns.creature_ended(state:, at_ms: 7100, watch: summoned_watch)
  assert spawns.timers(crashed) == [] && spawns.starts(crashed) == []
    as "the run-only spawn is not"
  let #(_, sweep) = spawns.sweep(state:, at_ms: 200_000)
  assert spawns.starts(sweep) == [] && spawns.creature_sends(sweep) == []
    as "nothing later brings it back"
}

pub fn a_creature_that_does_not_start_answers_not_summoned_and_drops_the_run_spawn_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = summoned_dagun(state: three_players())
  let #(watch, _) = the_start(taken)
  let #(state, failed) =
    spawns.creature_not_started(
      state:,
      at_ms: 6000,
      watch:,
      reason: "the creature supervisor is not running",
    )
  assert support.replies(failed)
    == [
      #(
        CallerId(50),
        map.NotSummoned(map.CreatureNotStarted(
          reason: "the creature supervisor is not running",
        )),
      ),
    ]
    as "the player is told it was not summoned, with the supervisor's reason"
  assert list.contains(
    support.effects_of(failed),
    step.OwnEffect(step.CancelServiceTimer(timer: step.TimerId(-1))),
  )
    as "the timer that would have said the start did not fail is cancelled"
  assert map.run_spawn(state:, spawn: SpawnId(-1)) == Error(Nil)
    && map.spawn_state(state:, spawn: SpawnId(-1)) == Error(Nil)
    && map.unit_id_of(state:, spawn: SpawnId(-1)) == Error(Nil)
    as "the run-only spawn, its state and its unit id are dropped"
  assert list.length(support.logs(failed)) == 1 as "one error line says why"
  let #(_, moved) = spawns.move(state:, at_ms: 7000, connection: 3, x: 1000.0)
  assert spawns.creature_sends(moved) == [] && spawns.starts(moved) == []
    as "a player that sees the place finds no creature, and no later one starts"
}

pub fn a_creature_that_ends_before_the_answer_is_still_answered_summoned_test() -> Nil {
  use <- owned_test.run(5000)
  // The start was carried out, and the creature ended before the timer that says
  // so fired: the start did not fail, so the answer is Summoned, whatever became
  // of the creature.
  let #(state, taken) = summoned_dagun(state: three_players())
  let #(watch, _) = the_start(taken)
  let #(state, ended) = spawns.creature_ended(state:, at_ms: 6000, watch:)
  assert support.replies(ended) == [] as "the answer still waits"
  let #(_, settled) = spawns.start_settled(state:, at_ms: 6000, spawn: -1)
  assert support.replies(settled) == [#(CallerId(50), map.Summoned(unit_id: 4))]
}

pub fn a_run_only_creature_no_player_sees_is_not_retired_by_the_sweep_test() -> Nil {
  use <- owned_test.run(5000)
  // A retired creature's spawn goes dormant and a creature starts there again at
  // full health when a player sees it, which would bring a dead summon back.
  let #(state, _) = summoned_dagun(state: three_players())
  let #(state, _) = spawns.leave(state:, at_ms: 7000, connection: 1)
  let #(state, _) = spawns.leave(state:, at_ms: 7000, connection: 2)
  let #(_, sweep) = spawns.sweep(state:, at_ms: 7000 + map_support.idle_stop_ms)
  assert spawns.creature_sends(sweep) == []
    as "no Retire goes to a run-only creature that has no viewer"
}

pub fn a_summon_stands_at_the_place_the_map_holds_for_the_player_after_its_moves_test() -> Nil {
  use <- owned_test.run(5000)
  let elsewhere =
    start_place.turned(
      place_support.at(
        world_id: 3460,
        world_zone_id: spawn_support.warfare_woods,
        x: 300.0,
        y: 4.0,
        z: -20.0,
      ),
      Facing(yaw: -2.0, pitch: 0.0, roll: 0.0),
    )
  let #(state, _) =
    spawns.move_to(
      state: three_players(),
      at_ms: 5500,
      connection: 1,
      place: elsewhere,
    )
  let #(_, taken) = summoned_dagun(state:)
  let #(_, creature) = the_start(taken)
  assert creature.spawn
    == RunOnly(Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(dagun),
      level: Some(1),
      place: elsewhere,
    ))
    as "the place the player last moved to, with its facing"
}

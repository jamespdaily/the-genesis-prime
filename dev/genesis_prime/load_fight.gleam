//// The fight load run: what the map and the creatures cost when many ready players
//// walk among a pack of creatures that fight them.
////
//// ```
//// gleam run -m genesis_prime/load_fight -- [WALKERS] [WORD ...]
//// ```
////
//// WALKERS is 50 when left out. The words, in any order:
//// - `mutual`: each walker also strikes each creature that threatens it, one strike a
////   second (a blow of 1; a Dagun has 50 health, so a creature dies only with
////   `respawning`), every fifth with Stagger's stun (Spell4Effects 83827), so the
////   creatures also die and are stunned;
//// - `leaving`: every walker is shown 2,000 units out of the creatures' sight and leash
////   from the tenth second to the twentieth, so the creatures lose their targets;
//// - `delayed MS`: walker 1's answers reach the creature MS ms after it sent them;
//// - `held MS`: walker 1 sends each answer MS ms after the strike reached it;
//// - `behind MS`: the map is held, taking nothing, for MS ms, and walker 1's first answer is
////   sent to it in that time, as to a map that has fallen behind;
//// - `respawning`: the Daguns' kind (Creature2 73465, which has no row of its own and takes
////   the default row's 60 s) respawns after `respawn_ms` (1,500, above the strike deadline
////   the load refuses a kind below), and with `mutual` each blow is 100 (above a Dagun's 50
////   health), so every blow that lands kills and the Daguns die over and over, their next
////   lives starting in the run. The kinds are put over the load's own before the tree
////   starts (`content/creature_kind.put`, which replaces the term); the database is
////   untouched. Each walker counts the respawn gap: the time from the removal of a unit it
////   was sent to the next creation of the same unit, from the creature's own news or the
////   map's notices (`genesis_prime/load_respawn`);
//// - `unrecorded`: the operating system's timers for every deadline, as the server runs
////   without the recorder, and the strike rounds are not counted: the run that shows
////   what the recorder costs.
////
//// The environment is the server's own: PGHOST, PGPORT, PGUSER, PGPASSWORD and
//// PGDATABASE name a migrated database, whose 27 Virtual Defense Daguns (Creature2
//// 73465) of migration 0008 stand in World 3460; GENESIS_TABLE_DIR names the client's
//// tables and GENESIS_TERRAIN_DIR the ground's. The server listens on no port of its
//// own (port 0), so another server may be running.
////
//// The server's whole tree runs in this node, with the strike deadlines recorded
//// (`genesis_prime/load_deadline`). The walkers are processes of this node that are
//// connections in the server's registry: each is a Dominion player (faction 166, to
//// which the Daguns are hostile) that joins the map at the centre of the Daguns, tells
//// it Ready, and for `hold_ms` sends a `Moved` with its next move sequence number every
//// 125 ms, walking at 7 units a second within 40 units of the centre. It does what a
//// player's connection does in a fight: it tells each creature that threatens it each
//// move (`TargetMoved`), answers each strike as landed, and forgets a creature that
//// releases it, each tell to a creature going to the map, as a player's connection tells
//// it, for the map to admit and pass on.
////
//// What it prints, counters only, nothing traced:
//// - the map's longest and mean message queue and the share of samples that found
////   it running (sampled every 10 ms, genesis_prime/load_moves), and its reductions
////   for each `Moved`;
//// - what the creatures were sent: the `Approached` and `Withdrew` of the rings the
////   walkers crossed, and the `TargetMoved` of their streams, in all and for each
////   creature;
//// - what the creatures sent the walkers: each news of a unit (a send to one viewer),
////   in all and a second, beside the map's notices;
//// - the strike rounds (`genesis_prime/load_round`): each walker stamps a strike's
////   answer when it hands it over and just before the creature has it, and the recorded
////   deadline of the creature's round gives when the round was armed, fell due and
////   closed. An answer is **lost** when it was sent before the round's deadline fell
////   due and the round closed without it (a round the deadline closed has no answer in
////   it, whatever the walker stamped); **late** when it was sent at or after it; the
////   rounds are counted by how they closed: an answer, the deadline, a death, a state, a
////   broken charge, the leash, or a cancel with no sign of why, or still open;
//// - with `respawning`, the respawn gaps the walkers counted: how many, their mean and 99th
////   percentile in microseconds as the walker was sent them, and the longest, and whether the
////   mean is under 1 ms;
//// - the judged counts (`genesis_prime/load_judged`): the strike rounds and the strike
////   answers (unless `mutual` and `respawning` together, where each blow kills the
////   creature before it strikes), with `mutual` (and the same exception) the walkers' own
////   strikes that a creature answered with `Struck` and, with `respawning`, the respawns,
////   each with its minimum, and the condition that no answer was lost. The run fails, with
////   exit status 1, when a count is below its minimum, when an answer was lost, when the
////   map falls behind, or when it judges none. The minimum of the rounds and the answers
////   is 1 (without the recorder, only the answers, as the walkers counted them). A walker
////   strikes only while it has `strike_tell.deadline_ms` left to hear the answer
////   (`load_round.may_strike`), and counts a strike only when the registry holds a creature at the
////   address and life the strike names as it is told to the map, since a creature answers
////   every strike it takes (`Answered`, a `Refused` one too): the minimum of the strikes
////   answered is the strikes the walkers made, and at least 1. A creature that ends between
////   that lookup and the map taking the strike leaves it with no answer, and the map drops
////   it, so the minimum counts it all the same. The
////   respawns' is the creatures killed that were owed one (a death in the last `settle_ms`
////   is not), and at least 1. With `mutual` and `respawning` together a `delayed` or `held`
////   plant has no strike to lose or delay, so it is measured by nothing;
//// - option A's count: for each move, the creatures in the mover's sight, summed
////   over the moves, the messages a design that told every seen creature of every
////   move would send.
//// The ring crossings and option A's count are worked out by each walker from the
//// same positions the map decides on, by the map's rule (a 10-unit ring of each
//// Dagun, sight of 1024 units, every seen spawn Live while a walker sees it), so the
//// map's state carries no counter for a load run.
////
//// **The planted failure.** `delayed MS` makes walker 1 hand its answers to a process
//// that tells the creature MS ms later: they are sent before the deadline and reach
//// the creature after it closed the round, so they are lost. `held MS` makes walker 1
//// send each answer MS ms after the strike reached it: sent after the deadline, so late.
//// `behind MS` makes walker 1 hold the map for MS ms and tell it its first answer in that time,
//// stamped sent and arrived before the deadline: the map has the answer in its mailbox when
//// the creature's round closes by its deadline, so it is lost, and the only thing that could
//// count it is the round's closure, not the walker's stamps. Another walker's answer already
//// on its way to the map when it is held is lost as well. With
//// MS above 1,000 (`strike_tell.deadline_ms`) a counter that stays at 0 under any of
//// the three is not counting.
////
//// The walkers all join and are ready before any walks, each starting at its own
//// offset within one 125 ms interval, as clients' timers are. The run passes when
//// the map's queue stays bounded: its mean below the moves of one round (the
//// walkers' count) and its process idle in most samples, and every judged count is at or
//// above its minimum. The longest queue is printed beside them.

import argv
import genesis_prime/client_connection.{
  type Message, type StaySent, ForStay, SentByFoe, SentByMap, SentByPeer,
  SentByTarget,
}
import genesis_prime/connection/registry
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/crowd_control
import genesis_prime/game/hit
import genesis_prime/game/hit_radius
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_news
import genesis_prime/load_deadline
import genesis_prime/load_judged.{Judged}
import genesis_prime/load_move_delay
import genesis_prime/load_moves
import genesis_prime/load_respawn.{type Gaps}
import genesis_prime/load_round.{
  type Answer, type Mark, type Rounds, Answer, Mark,
}
import genesis_prime/load_run
import genesis_prime/load_sample
import genesis_prime/message/crowd_control_state
import genesis_prime/server
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type ConnectionId, ConnectionId}
import genesis_prime/step/runtime
import genesis_prime/store.{Character, CharacterId, NameStands}
import genesis_prime/table/id.{ClassId, Creature2Id, RaceId}
import genesis_prime/world_map/creature_kind.{Kind, Kinds}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/relay
import genesis_prime/world_map/sight
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/spawn_id.{type SpawnId}
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam_community/maths

/// The world of the pack: Warfare Woods of the training simulation.
const world_id = 3460

/// The Dominion player faction, to which the Daguns are hostile.
const dominion = 166

/// How often a walker moves, in milliseconds: the client's send interval.
const move_every_ms = 125

/// The client's walking speed in units a second.
const speed = 7.0

/// How far from the pack's centre a walker goes.
const radius = 40.0

/// How long the walkers walk.
const hold_ms = 30_000

/// The creature the walkers fight: the Virtual Defense Daguns (Creature2 73465) of
/// migration 0008, and how many of them it places in the world.
const dagun = 73_465

const daguns = 27

/// The Daguns' respawn time in the `respawning` scene, in milliseconds: above the strike
/// deadline (1,000), which a kind may not undercut (`creature_kind.select`).
const respawning_ms = 1500

/// A death within this many milliseconds of the walkers' end is not owed a respawn: the
/// corpse timer (`respawning_ms`) and the next life are still to come.
const settle_ms = 3000

/// Whether a creature of the scene lives to strike: with `mutual` and `respawning` each
/// blow that lands kills (`killing_blow`), so the strike rounds and the answers are not
/// there to judge.
fn creatures_strike(scene scene: Scene) -> Bool {
  !{ scene.mutual && scene.respawning }
}

/// The damage of a blow in the `respawning` scene, above a Dagun's 50 health, so each
/// blow that lands kills.
const killing_blow = 100

/// A walker of the `mutual` scene strikes each creature that threatens it once in this
/// many moves (a second), and every `stun_every`th strike carries Stagger's stun
/// (Spell4Effects 83827: delay 0, duration 2,500 ms, 1 armor).
const strike_every_steps = 8

const stun_every = 5

/// The `leaving` scene: each walker is shown `away_units` along x from where it walks
/// for the moves from `away_from_step` up to `away_until_step`, which is beyond the
/// creatures' sight (1,024) and leash.
const away_from_step = 80

const away_until_step = 160

const away_units = 2000.0

/// What one walker counted.
type Counts {
  Counts(
    moves: Int,
    approached: Int,
    withdrew: Int,
    target_moved: Int,
    option_a: Int,
    strikes: Int,
    made: Int,
    answered_to_own: Int,
    strikers: Dict(Pid, Int),
    marks: List(Mark),
    by_creature: Dict(Int, Int),
    creature_news: Int,
    map_notices: Int,
    respawns: Gaps,
  )
}

/// What a walker does with the answers it gives: all of them as they are, or, for
/// walker 1, with a planted failure (see the module's doc).
type Plant {
  Honest
  Delayed(ms: Int)
  Held(ms: Int)
  Behind(ms: Int)
}

/// What a run does: its walkers, the plant of walker 1, and the words that change what
/// the walkers and the recorder do (see the module's doc).
type Scene {
  Scene(
    walkers: Int,
    plant: Plant,
    mutual: Bool,
    leaving: Bool,
    respawning: Bool,
    recorded: Bool,
  )
}

@external(erlang, "load_fight_ffi", "reductions")
fn reductions(pid: Pid) -> Int

@external(erlang, "load_fight_ffi", "suspend")
fn suspend(pid: Pid) -> Nil

@external(erlang, "load_fight_ffi", "resume")
fn resume(pid: Pid) -> Nil

pub fn main() -> Nil {
  let scene = scene_of(argv.load().arguments)
  let recorder = load_deadline.start()
  let settings =
    load_run.start_server_with(change: fn(settings) {
      case scene.respawning {
        True -> respawn_daguns_quickly(settings:)
        False -> Nil
      }
      server.Settings(
        ..load_run.on_free_ports(settings),
        service_time: case scene.recorded {
          True ->
            service_shell.ServiceTime(
              ..service_shell.real_time(),
              schedule: load_deadline.scheduler(recorder:),
            )
          False -> service_shell.real_time()
        },
      )
    })
  let numbers = content_game_number.numbers(key: settings.world.spawns)
  let spawns =
    dict.values(
      content_spawn.world(key: settings.world.spawns, world_id:).by_id,
    )
  let pack = daguns_of(spawns)
  let centre = centre_of(pack)
  let assert Ok(run) =
    world_map_registry.find_or_start(
      settings.world.maps,
      MapId(world_id:, instance: 0),
      deadline_ms: now() + 5000,
    )
    as "the map of the world started"
  let done = process.new_subject()
  let joined = process.new_subject()
  let answers = process.new_subject()
  list.each(ids(scene.walkers), fn(id) {
    walker(
      plant: case id {
        1 -> scene.plant
        _ -> Honest
      },
      scene:,
      answers:,
      settings:,
      run:,
      id:,
      centre:,
      spawns:,
      pack:,
      aggro_range: numbers.aggro_range,
      joined:,
      done:,
    )
  })
  // Every walker joins and is ready before any walks, so the probe and the
  // reductions measure the walk and not the joins' creature starts.
  let starts =
    list.map(ids(scene.walkers), fn(_) {
      let assert Ok(start) = process.receive(joined, within: 60_000)
        as "every walker joined"
      start
    })
  load_moves.start_probe(settings.world.map_supervisor)
  let before = reductions(run.pid)
  list.each(starts, fn(start) { process.send(start, Nil) })
  let counts =
    list.map(ids(scene.walkers), fn(_) {
      let assert Ok(counts) = process.receive(done, within: hold_ms + 60_000)
        as "every walker finished"
      counts
    })
  let ended_us = load_sample.microseconds()
  let after = reductions(run.pid)
  let #(longest, sum, samples, running) = load_moves.stop_probe()
  // A planted answer is delivered up to its delay after the walkers finish, and the
  // round it was sent in falls due a deadline after that.
  process.sleep(planted_ms(scene.plant) + strike_tell.deadline_ms)
  let rounds = case scene.recorded {
    True ->
      Some(load_round.rounds_of(
        answers: drain(answers, []),
        strikers: list.fold(counts, dict.new(), fn(all, one) {
          dict.merge(all, one.strikers)
        }),
        marks: list.flat_map(counts, fn(one) { one.marks }),
        deadlines: load_deadline.deadlines(recorder:),
      ))
    False -> None
  }
  report(
    scene:,
    counts:,
    rounds:,
    ended_us:,
    reductions: after - before,
    longest:,
    sum:,
    samples:,
    running:,
  )
}

/// The Daguns' kind with a respawn time of `respawning_ms`, put over the kinds the load put
/// under the world's key before the tree starts, so the maps and creatures read it. The
/// kind is the Daguns' own when they have a row, else the default row's.
fn respawn_daguns_quickly(settings settings: server.Settings) -> Nil {
  let kinds = content_creature_kind.kinds(settings.world.spawns)
  let own = creature_kind.kind_of(kinds:, creature2_id: dagun)
  content_creature_kind.put(
    key: settings.world.spawns,
    kinds: Kinds(
      ..kinds,
      by_creature: dict.insert(
        kinds.by_creature,
        dagun,
        Kind(..own, respawn_ms: respawning_ms),
      ),
    ),
  )
}

/// The scene the arguments name: a count of walkers, when the first is a number, and
/// the words.
fn scene_of(arguments: List(String)) -> Scene {
  let scene =
    Scene(
      walkers: 50,
      plant: Honest,
      mutual: False,
      leaving: False,
      respawning: False,
      recorded: True,
    )
  case arguments {
    [count, ..words] ->
      case int.parse(count) {
        Ok(walkers) -> words_of(words:, scene: Scene(..scene, walkers:))
        Error(Nil) -> words_of(words: arguments, scene:)
      }
    [] -> scene
  }
}

fn words_of(words words: List(String), scene scene: Scene) -> Scene {
  case words {
    [] -> scene
    ["mutual", ..rest] ->
      words_of(words: rest, scene: Scene(..scene, mutual: True))
    ["leaving", ..rest] ->
      words_of(words: rest, scene: Scene(..scene, leaving: True))
    ["respawning", ..rest] ->
      words_of(words: rest, scene: Scene(..scene, respawning: True))
    ["unrecorded", ..rest] ->
      words_of(words: rest, scene: Scene(..scene, recorded: False))
    ["delayed", ms, ..rest] ->
      words_of(
        words: rest,
        scene: Scene(..scene, plant: Delayed(ms: whole(ms))),
      )
    ["held", ms, ..rest] ->
      words_of(words: rest, scene: Scene(..scene, plant: Held(ms: whole(ms))))
    ["behind", ms, ..rest] ->
      words_of(words: rest, scene: Scene(..scene, plant: Behind(ms: whole(ms))))
    [_, ..] ->
      panic as "the arguments are: [walkers] [mutual] [leaving] [respawning] [unrecorded] [delayed|held|behind milliseconds]"
  }
}

/// How long after the walkers finish the plant's answers are still to be delivered.
fn planted_ms(plant: Plant) -> Int {
  case plant {
    Honest -> 0
    Delayed(ms:) | Held(ms:) | Behind(ms:) -> ms
  }
}

/// The whole number the text names, for an argument.
fn whole(text: String) -> Int {
  let assert Ok(number) = int.parse(text)
    as "the arguments' numbers are whole numbers"
  number
}

/// The Daguns' spawns, the pack the walkers walk among: the world also holds hostile
/// spawns far from it, which would pull the pack's centre out of the walkers' reach.
/// The world must place exactly the 27 of migration 0008.
fn daguns_of(spawns: List(Spawn)) -> List(Spawn) {
  let pack =
    list.filter(spawns, fn(found) {
      found.creature_id == Creature2Id(dagun)
      && found.combat.hostile_to.dominion
    })
  assert list.length(pack) == daguns
    as "migration 0008 places 27 Daguns hostile to the Dominion in World 3460"
  pack
}

fn drain(answers: Subject(Answer), found: List(Answer)) -> List(Answer) {
  case process.receive(answers, within: 0) {
    Ok(answer) -> drain(answers, [answer, ..found])
    Error(Nil) -> found
  }
}

/// The walkers' connection numbers, from 1.
fn ids(walkers: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, walkers), fn(_, index) { index + 1 })
}

fn now() -> Int {
  runtime.now().monotonic_ms
}

fn centre_of(pack: List(Spawn)) -> Place {
  let count = int.to_float(list.length(pack))
  let sum = fn(axis: fn(Place) -> Float) {
    list.fold(pack, 0.0, fn(total, found) { total +. axis(found.place) })
    /. count
  }
  let assert [first, ..] = pack as "the pack is not empty"
  start_place.moved(
    place: first.place,
    x: sum(start_place.x),
    y: sum(start_place.y),
    z: sum(start_place.z),
  )
}

/// A walker: a connection in the registry that joins, is ready, sends `joined` the
/// subject it waits on, walks and fights for `hold_ms` once told, leaves, and sends
/// what it counted to `done`.
fn walker(
  plant plant: Plant,
  scene scene: Scene,
  answers answers: Subject(Answer),
  settings settings: server.Settings,
  run run: world_map_registry.MapProcess,
  id id: Int,
  centre centre: Place,
  spawns spawns: List(Spawn),
  pack pack: List(Spawn),
  aggro_range aggro_range: Float,
  joined joined: Subject(Subject(Nil)),
  done done: Subject(Counts),
) -> Nil {
  let _pid =
    process.spawn_unlinked(fn() {
      let connection = ConnectionId(id)
      registry.join(settings.registry, connection:)
      let selector =
        registry.select_delivered(
          settings.registry,
          process.new_selector(),
          fn(message) { message },
        )
      let replies = process.new_subject()
      let start = step_from(place: centre, id:, step: 0, centre:)
      let _sent =
        service.call_subject(
          run.subject,
          map.Join(
            connection:,
            character: character(id),
            place: start,
            stay: walkers_stay(),
            alive: True,
            hidden: set.new(),
          ),
          fn(answer) { process.send(replies, answer) },
        )
      let assert Ok(_joined) = process.receive(replies, within: 60_000)
        as "the map answered the join"
      let _sent =
        service.tell_subject(run.subject, map.Ready(connection:, seq: 0))
      let start_walking = process.new_subject()
      process.send(joined, start_walking)
      let assert Ok(Nil) = process.receive(start_walking, within: 120_000)
        as "the run let the walkers walk"
      // Clients' send timers are not in step: each walker starts at its own
      // offset within one interval.
      process.sleep(id * move_every_ms / scene.walkers)
      let counts =
        walk(
          plant:,
          scene:,
          answers:,
          settings:,
          run:,
          selector:,
          connection:,
          id:,
          step: 1,
          place: start,
          centre:,
          spawns:,
          pack:,
          aggro_range:,
          inside: set.new(),
          fighters: dict.new(),
          ends_ms: now() + hold_ms,
          counts: Counts(
            moves: 0,
            approached: 0,
            withdrew: 0,
            target_moved: 0,
            option_a: 0,
            strikes: 0,
            made: 0,
            answered_to_own: 0,
            strikers: dict.new(),
            marks: [],
            by_creature: dict.new(),
            creature_news: 0,
            map_notices: 0,
            respawns: load_respawn.none(),
          ),
        )
      let _sent =
        service.call_subject(run.subject, map.Leave(connection:), fn(answer) {
          process.send(replies, answer)
        })
      let _left = process.receive(replies, within: 60_000)
      process.send(done, counts)
    })
  Nil
}

fn walk(
  plant plant: Plant,
  scene scene: Scene,
  answers answers: Subject(Answer),
  settings settings: server.Settings,
  run run: world_map_registry.MapProcess,
  selector selector: process.Selector(Message),
  connection connection: ConnectionId,
  id id: Int,
  step step: Int,
  place place: Place,
  centre centre: Place,
  spawns spawns: List(Spawn),
  pack pack: List(Spawn),
  aggro_range aggro_range: Float,
  inside inside: Set(SpawnId),
  fighters fighters: Dict(Int, Int),
  ends_ms ends_ms: Int,
  counts counts: Counts,
) -> Counts {
  use <- bool.guard(when: now() >= ends_ms, return: counts)
  {
    let next_ms = now() + move_every_ms
    let #(fighters, counts) =
      hear(
        plant:,
        answers:,
        settings:,
        run:,
        connection:,
        selector:,
        until_ms: next_ms,
        fighters:,
        counts:,
      )
    let place = step_from(place:, id:, step:, centre:)
    let shown = shown_at(scene:, place:, step:)
    let _sent =
      service.tell_subject(
        run.subject,
        map.Moved(connection:, place: shown, seq: step),
      )
    let counts =
      struck_back(
        scene:,
        settings:,
        run:,
        connection:,
        id:,
        place: shown,
        step:,
        fighters:,
        ends_ms:,
        counts:,
      )
    list.each(dict.to_list(fighters), fn(fighter) {
      tell_the_map(
        run:,
        connection:,
        unit_id: fighter.0,
        life: fighter.1,
        payload: relay.TargetMoved(
          place: shown,
          seq: step,
          hit_radius: hit_radius.of_playing(
            tables: settings.game.settings.tables,
            race_id: RaceId(1),
          ),
        ),
      )
    })
    let now_inside =
      list.filter(pack, fn(found) {
        creature_path.distance(from: shown, to: found.place) <=. aggro_range
      })
      |> list.map(fn(found) { found.id })
      |> set.from_list
    let seen = list.count(spawns, fn(found) { sight.sees(shown, found.place) })
    let counts =
      Counts(
        ..counts,
        moves: counts.moves + 1,
        approached: counts.approached
          + set.size(set.difference(now_inside, inside)),
        withdrew: counts.withdrew + set.size(set.difference(inside, now_inside)),
        target_moved: counts.target_moved + dict.size(fighters),
        option_a: counts.option_a + seen,
        by_creature: list.fold(
          dict.keys(fighters),
          counts.by_creature,
          fn(by, unit_id) {
            dict.upsert(by, unit_id, fn(found) { option.unwrap(found, 0) + 1 })
          },
        ),
      )
    walk(
      plant:,
      scene:,
      answers:,
      settings:,
      run:,
      selector:,
      connection:,
      id:,
      step: step + 1,
      place:,
      centre:,
      spawns:,
      pack:,
      aggro_range:,
      inside: now_inside,
      fighters:,
      ends_ms:,
      counts:,
    )
  }
}

/// Where the map and the creatures are told the walker is at this move: where it walks,
/// or, in the `leaving` scene, between `away_from_step` and `away_until_step`,
/// `away_units` along x from there.
fn shown_at(scene scene: Scene, place place: Place, step step: Int) -> Place {
  use <- bool.guard(
    when: !scene.leaving || step < away_from_step || step >= away_until_step,
    return: place,
  )
  start_place.moved(
    place:,
    x: start_place.x(place) +. away_units,
    y: start_place.y(place),
    z: start_place.z(place),
  )
}

/// The counts after the walker's strikes of this move: in the `mutual` scene, once a
/// second, a strike of each creature it fights.
fn struck_back(
  scene scene: Scene,
  settings settings: server.Settings,
  run run: world_map_registry.MapProcess,
  connection connection: ConnectionId,
  id id: Int,
  place place: Place,
  step step: Int,
  fighters fighters: Dict(Int, Int),
  ends_ms ends_ms: Int,
  counts counts: Counts,
) -> Counts {
  use <- bool.guard(
    when: !scene.mutual
      || step % strike_every_steps != 0
      || !load_round.may_strike(at_ms: now(), ends_ms:),
    return: counts,
  )
  Counts(
    ..counts,
    made: strike_fighters(
      settings:,
      run:,
      connection:,
      id:,
      place:,
      step:,
      fighters:,
      made: counts.made,
      damage: case scene.respawning {
        True -> killing_blow
        False -> 1
      },
    ),
  )
}

/// Strikes each creature the walker fights as the walker's connection does: one blow of `damage`
/// (Spell4Effects 184741), and Stagger's stun with every `stun_every`th strike, each told to
/// the map. `made` is the strikes the walker has made; it gives the count after these. A
/// strike counts as made when the registry holds a creature at its address and life as it is
/// told and the map's process is reached: the map drops a strike for a creature that ended
/// with no answer, and such a strike must not raise the minimum of the answers.
fn strike_fighters(
  settings settings: server.Settings,
  run run: world_map_registry.MapProcess,
  connection connection: ConnectionId,
  id id: Int,
  place place: Place,
  step step: Int,
  fighters fighters: Dict(Int, Int),
  made made: Int,
  damage damage: Int,
) -> Int {
  let hit_radius =
    hit_radius.of_playing(
      tables: settings.game.settings.tables,
      race_id: RaceId(1),
    )
  list.fold(dict.to_list(fighters), made, fn(made, fighter) {
    let next = made + 1
    let stun =
      strike_tell.ControlTell(
        effect_id: 83_827,
        instance_id: crowd_control.instance_id(caster_unit_id: id, count: next),
        row: crowd_control.Row(
          state: crowd_control_state.Stun,
          delay_ms: 0,
          duration_ms: 2500,
          armor_removed: 1,
          until_removed: False,
        ),
        throw: None,
      )
    let running =
      creature_registry.find(
        settings.world.creatures,
        map: MapId(world_id:, instance: 0),
        incarnation: run.incarnation,
        unit_id: fighter.0,
        life: fighter.1,
      )
      |> result.is_ok
    let told =
      tell_the_map(
        run:,
        connection:,
        unit_id: fighter.0,
        life: fighter.1,
        payload: relay.Strike(
          tell: strike_tell.Strike(
            key: strike_tell.Key(
              cast_id: id * 100_000 + next,
              occasion: strike_tell.AtGo(phase: 0),
              unit_id: fighter.0,
            ),
            from: step.Connection(connection),
            striker: strike_tell.PlayerStriker(
              unit_id: id,
              place:,
              seq: step,
              stay: walkers_stay(),
              hit_radius:,
              rolls: hit.Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
            ),
            offence: hit.Offence(
              blows: [
                hit.Blow(
                  spell4_effects_id: 184_741,
                  damage_type: 3,
                  damage: hit.Worked(damage),
                  delay_ms: 0,
                  threat_multiplier: 1.0,
                ),
              ],
              crit_chance: 0.0,
              crit_severity: 1.5,
              strikethrough: 0.0,
            ),
            controls: case next % stun_every {
              0 -> [stun]
              _ -> []
            },
            gates: [],
          ),
        ),
      )
    case running && told {
      True -> next
      False -> made
    }
  })
}

/// What the walker hears until the next move: a creature's threat makes it a
/// fighter, its release forgets it, and its strike is answered as landed
/// (`answered`). The news of the creatures and the map's notices are counted.
fn hear(
  plant plant: Plant,
  answers answers: Subject(Answer),
  settings settings: server.Settings,
  run run: world_map_registry.MapProcess,
  connection connection: ConnectionId,
  selector selector: process.Selector(Message),
  until_ms until_ms: Int,
  fighters fighters: Dict(Int, Int),
  counts counts: Counts,
) -> #(Dict(Int, Int), Counts) {
  let again = fn(fighters, counts) {
    hear(
      plant:,
      answers:,
      settings:,
      run:,
      connection:,
      selector:,
      until_ms:,
      fighters:,
      counts:,
    )
  }
  let received =
    process.selector_receive(selector, int.max(0, until_ms - now()))
  let counts = case received {
    Ok(ForStay(sent:, ..)) ->
      case load_round.is_answer_to_strike(sent:) {
        True -> Counts(..counts, answered_to_own: counts.answered_to_own + 1)
        False -> counts
      }
    Ok(_) | Error(Nil) -> counts
  }
  case received {
    Error(Nil) -> #(fighters, counts)
    Ok(ForStay(
      sent: SentByFoe(fight: strike_tell.Threatened(unit_id:, life:)),
      ..,
    )) -> again(dict.insert(fighters, unit_id, life), counts)
    Ok(ForStay(sent: SentByFoe(fight: strike_tell.Released(unit_id:)), ..)) ->
      again(
        dict.delete(fighters, unit_id),
        marked(counts:, unit_id:, sign: load_round.Released),
      )
    Ok(ForStay(sent: SentByFoe(fight: strike_tell.Attacks(tell:)), ..)) -> {
      let taken_us = load_sample.microseconds()
      let counts = Counts(..counts, strikes: counts.strikes + 1)
      case
        answered(
          plant: planted_now(plant:, strikes: counts.strikes),
          answers:,
          settings:,
          run:,
          connection:,
          tell:,
          taken_us:,
        )
      {
        Ok(#(creature, unit_id)) ->
          again(
            fighters,
            Counts(
              ..counts,
              strikers: dict.insert(counts.strikers, creature, unit_id),
            ),
          )
        Error(Nil) -> again(fighters, counts)
      }
    }
    Ok(ForStay(sent: SentByPeer(news:) as sent, ..)) -> {
      let counts = Counts(..counts, creature_news: counts.creature_news + 1)
      let counts = respawn_told(counts:, sent:)
      case sign_of(news.news) {
        Ok(sign) ->
          again(fighters, marked(counts:, unit_id: news.unit_id, sign:))
        Error(Nil) -> again(fighters, counts)
      }
    }
    Ok(ForStay(
      sent: SentByTarget(answered: strike_tell.Answered(
        key:,
        outcome: strike_tell.Landed(controls:, ..),
      )),
      ..,
    )) ->
      case
        list.any(controls, fn(control) { option.is_some(control.interrupted) })
      {
        True ->
          again(
            fighters,
            marked(counts:, unit_id: key.unit_id, sign: load_round.Controlled),
          )
        False -> again(fighters, counts)
      }
    Ok(ForStay(sent: SentByMap(..) as sent, ..)) ->
      again(
        fighters,
        respawn_told(
          counts: Counts(..counts, map_notices: counts.map_notices + 1),
          sent:,
        ),
      )
    Ok(_) -> again(fighters, counts)
  }
}

/// The counts after the walker was sent `sent`: its removals and creations of units are
/// read for the respawn gaps, whether the creature or the map told them.
fn respawn_told(counts counts: Counts, sent sent: StaySent) -> Counts {
  Counts(
    ..counts,
    respawns: load_respawn.told(
      gaps: counts.respawns,
      sent:,
      at_us: load_sample.microseconds(),
    ),
  )
}

/// A sign of the creature in a news of it, when it is one that closes a round: its death
/// or its broken charge.
fn sign_of(news: unit_news.News) -> Result(load_round.Sign, Nil) {
  case news {
    unit_news.Died -> Ok(load_round.Died)
    unit_news.CastInterrupted(..) -> Ok(load_round.Interrupted)
    unit_news.Removed
    | unit_news.Appeared(..)
    | unit_news.Moving(..)
    | unit_news.CastStarted(..)
    | unit_news.CastWent(..)
    | unit_news.CastMissed(..)
    | unit_news.CastTicked(..)
    | unit_news.CastTargetsRemoved(..)
    | unit_news.CastStackRemoved(..)
    | unit_news.CastFinished(..)
    | unit_news.Health(..)
    | unit_news.CameBack
    | unit_news.DeathLogged
    | unit_news.CameBackLogged
    | unit_news.CreatureAppeared(..)
    | unit_news.CreatureMoved(..)
    | unit_news.CreaturePlaced(..)
    | unit_news.CreatureFaces(..)
    | unit_news.Targeting(..)
    | unit_news.Threat(..)
    | unit_news.CombatState(..)
    | unit_news.Shield(..)
    | unit_news.InterruptArmor(..)
    | unit_news.Absorption(..)
    | unit_news.Level(..)
    | unit_news.CrowdControlApplied(..)
    | unit_news.CrowdControlEnded(..)
    | unit_news.UnitStateHeld(..)
    | unit_news.UnitStateEnded(..)
    | unit_news.PropertiesChanged(..)
    | unit_news.Stealth(..)
    | unit_news.LookChanged(..)
    | unit_news.HeldCastEnded(..)
    | unit_news.HeldCastStarted(..) -> Error(Nil)
  }
}

/// The counts with a sign of the creature `unit_id`, stamped when this is called.
fn marked(
  counts counts: Counts,
  unit_id unit_id: Int,
  sign sign: load_round.Sign,
) -> Counts {
  Counts(..counts, marks: [
    Mark(unit_id:, sign:, at_us: load_sample.microseconds()),
    ..counts.marks
  ])
}

/// Answers the strike as landed, as the walker's plant says, and tells `answers` when it
/// handed the answer over and when the creature had it, and gives the creature's process
/// and unit. A strike of anything but a creature that is running is left unanswered, and
/// not recorded.
fn answered(
  plant plant: Plant,
  answers answers: Subject(Answer),
  settings settings: server.Settings,
  run run: world_map_registry.MapProcess,
  connection connection: ConnectionId,
  tell tell: strike_tell.Tell,
  taken_us taken_us: Int,
) -> Result(#(Pid, Int), Nil) {
  case tell.from {
    step.Creature(map:, incarnation:, unit_id:, life:) -> {
      let tell_creature = fn() {
        tell_the_map(
          run:,
          connection:,
          unit_id:,
          life:,
          payload: relay.StrikeAnswered(answered: strike_tell.Answered(
            key: tell.key,
            outcome: strike_tell.Landed(
              descriptions: [],
              controls: [],
              armor_removed: 0,
              gates_passed: [],
            ),
          )),
        )
      }
      use creature <- result.map(creature_registry.find(
        settings.world.creatures,
        map:,
        incarnation:,
        unit_id:,
        life:,
      ))
      handed_over(
        plant:,
        answers:,
        creature:,
        map_pid: run.pid,
        taken_us:,
        tell_creature:,
      )
      #(creature, unit_id)
    }
    _ -> Error(Nil)
  }
}

/// The plant the walker's answer to its strike number `strikes` is handed over with: a
/// `Behind` plant holds the map for the first answer only, so the run is not otherwise a
/// map held for good.
fn planted_now(plant plant: Plant, strikes strikes: Int) -> Plant {
  case plant, strikes {
    Behind(..), 1 -> plant
    Behind(..), _ -> Honest
    Honest, _ | Delayed(..), _ | Held(..), _ -> plant
  }
}

/// Hands the answer to the creature, through the map, as the plant says and records it: at
/// once; after `ms` with the send stamped before the wait (`Delayed`: sent early, reaching
/// the map late); after `ms` with the send stamped after it (`Held`); or with the map
/// `map_pid` held for `ms` and the answer sent to it in that time (`Behind`: sent and arrived
/// early, taken late). The arrival is stamped just before the send to the map
/// (`load_round.stamped_send`). `tell_creature` tells the creature through the map and says whether the map was reached.
fn handed_over(
  plant plant: Plant,
  answers answers: Subject(Answer),
  creature creature: Pid,
  map_pid map_pid: Pid,
  taken_us taken_us: Int,
  tell_creature tell_creature: fn() -> Bool,
) -> Nil {
  let record = fn(sent_us: Int) {
    let #(arrived_us, delivered) = load_round.stamped_send(send: tell_creature)
    process.send(
      answers,
      Answer(creature:, taken_us:, sent_us:, arrived_us:, delivered:),
    )
  }
  case plant {
    Honest -> record(load_sample.microseconds())
    Delayed(ms:) -> {
      let sent_us = load_sample.microseconds()
      let _pid =
        process.spawn_unlinked(fn() {
          process.sleep(ms)
          record(sent_us)
        })
      Nil
    }
    Held(ms:) -> {
      let _pid =
        process.spawn_unlinked(fn() {
          process.sleep(ms)
          record(load_sample.microseconds())
        })
      Nil
    }
    Behind(ms:) -> {
      // The process that suspends the map is the one that resumes it.
      let _pid =
        process.spawn_unlinked(fn() {
          suspend(map_pid)
          record(load_sample.microseconds())
          process.sleep(ms)
          resume(map_pid)
        })
      Nil
    }
  }
}

/// The stay the walkers join the map in, which each tell of theirs to a creature names.
fn walkers_stay() -> Stay {
  stay.next(stay.none_yet())
}

/// The tell of a walker's connection to the creature `unit_id` of life `life`, as a
/// player's connection tells it: to the map, which admits it and passes it on to the
/// creature. Whether the map's process was reached.
fn tell_the_map(
  run run: world_map_registry.MapProcess,
  connection connection: ConnectionId,
  unit_id unit_id: Int,
  life life: Int,
  payload payload: relay.Inbound,
) -> Bool {
  service.tell_subject(
    run.subject,
    map.TellCreature(
      from: connection,
      stay: walkers_stay(),
      unit_id:,
      life:,
      payload:,
    ),
  )
  |> result.is_ok
}

/// The walker's next place: a step of `speed` per second along a heading that
/// turns with the walker and the time, turned back toward the centre beyond the
/// radius.
fn step_from(
  place place: Place,
  id id: Int,
  step step: Int,
  centre centre: Place,
) -> Place {
  let length = speed *. int.to_float(move_every_ms) /. 1000.0
  let away = creature_path.distance(from: place, to: centre)
  let heading = case away >. radius {
    True ->
      maths.atan2(
        start_place.z(centre) -. start_place.z(place),
        start_place.x(centre) -. start_place.x(place),
      )
    False ->
      int.to_float({ id * 37 + step / 40 * 91 } % 360) *. maths.pi() /. 180.0
  }
  start_place.moved(
    place:,
    x: start_place.x(place) +. length *. maths.cos(heading),
    y: start_place.y(place),
    z: start_place.z(place) +. length *. maths.sin(heading),
  )
}

fn character(id: Int) -> store.Character {
  Character(
    character_id: CharacterId(id),
    name: "Walker",
    gender: 0,
    race_id: RaceId(1),
    class_id: ClassId(1),
    faction_id: dominion,
    level: 1,
    path: 0,
    place: None,
    look: [],
    bones: [],
    naming: NameStands,
  )
}

/// The respawn gaps of every walker, in microseconds.
fn total_gaps(counts: List(Counts)) -> List(Int) {
  list.flat_map(counts, fn(one) { one.respawns.gaps_us })
}

/// What the respawn gaps say: how many, the mean, the 99th percentile and the longest, and
/// whether the mean is under 1 ms (1,000 microseconds).
fn respawn_gaps(gaps gaps: List(Int)) -> String {
  let summary =
    load_move_delay.summary(delays: load_move_delay.Delays(
      microseconds: gaps,
      expected: list.length(gaps),
    ))
  "respawn gaps (a removal to the next creation of the unit, as a walker was sent them): "
  <> int.to_string(summary.moves)
  <> ", mean "
  <> int.to_string(summary.mean_us)
  <> " us, 99th "
  <> int.to_string(summary.p99_us)
  <> " us, longest "
  <> int.to_string(summary.longest_us)
  <> " us; "
  <> case summary.moves > 0 && summary.mean_us < 1000 {
    True -> "the mean is under 1 ms"
    False -> "the mean is not under 1 ms, or no respawn was seen"
  }
}

fn report(
  scene scene: Scene,
  rounds rounds: Option(Rounds),
  counts counts: List(Counts),
  ended_us ended_us: Int,
  reductions reductions: Int,
  longest longest: Int,
  sum sum: Int,
  samples samples: Int,
  running running: Int,
) -> Nil {
  let total = fn(field: fn(Counts) -> Int) {
    list.fold(counts, 0, fn(all, one) { all + field(one) })
  }
  let moves = total(fn(one) { one.moves })
  let by_creature =
    list.fold(counts, dict.new(), fn(all, one) {
      dict.fold(one.by_creature, all, fn(all, unit_id, sent) {
        dict.upsert(all, unit_id, fn(found) { option.unwrap(found, 0) + sent })
      })
    })
  let most = list.fold(dict.values(by_creature), 0, int.max)
  let walkers = scene.walkers
  io.println(
    int.to_string(walkers)
    <> " walkers, "
    <> int.to_string(hold_ms / 1000)
    <> " s"
    <> case scene.mutual {
      True -> ", mutual strikes"
      False -> ""
    }
    <> case scene.leaving {
      True -> ", the walkers leaving sight"
      False -> ""
    }
    <> case scene.respawning {
      True ->
        ", the Daguns respawning after "
        <> int.to_string(respawning_ms)
        <> " ms"
      False -> ""
    }
    <> case scene.recorded {
      True -> ""
      False -> ", deadlines not recorded"
    },
  )
  io.println(
    "the map: longest queue "
    <> int.to_string(longest)
    <> ", mean "
    <> load_moves.per(total: sum, count: samples)
    <> ", running in "
    <> load_moves.percent(part: running, whole: samples)
    <> " of samples; "
    <> load_moves.per(total: reductions, count: moves)
    <> " reductions per Moved ("
    <> int.to_string(moves)
    <> " moves)",
  )
  io.println(
    "the creatures were sent "
    <> int.to_string(total(fn(one) { one.approached }))
    <> " Approached, "
    <> int.to_string(total(fn(one) { one.withdrew }))
    <> " Withdrew and "
    <> int.to_string(total(fn(one) { one.target_moved }))
    <> " TargetMoved (the most to one creature "
    <> int.to_string(most)
    <> ", over "
    <> int.to_string(dict.size(by_creature))
    <> " creatures); "
    <> int.to_string(total(fn(one) { one.strikes }))
    <> " strikes answered",
  )
  let per_second = fn(count) {
    load_moves.per(total: count * 1000, count: hold_ms)
  }
  io.println(
    "the creatures sent the walkers "
    <> int.to_string(total(fn(one) { one.creature_news }))
    <> " news of units, one to a viewer each ("
    <> per_second(total(fn(one) { one.creature_news }))
    <> " a second); the map sent them "
    <> int.to_string(total(fn(one) { one.map_notices }))
    <> " notices ("
    <> per_second(total(fn(one) { one.map_notices }))
    <> " a second)",
  )
  io.println(
    "the walkers made "
    <> int.to_string(total(fn(one) { one.made }))
    <> " strikes of their own",
  )
  case rounds {
    None -> io.println("the strike rounds were not recorded")
    Some(rounds) -> {
      let closed = rounds.closed
      io.println(
        "strike rounds closed: "
        <> int.to_string(closed.answer)
        <> " by an answer, "
        <> int.to_string(closed.deadline)
        <> " by the deadline, "
        <> int.to_string(closed.death)
        <> " by a death, "
        <> int.to_string(closed.control)
        <> " by a state, "
        <> int.to_string(closed.leash)
        <> " by the leash, "
        <> int.to_string(closed.interrupt)
        <> " by a broken charge, "
        <> int.to_string(closed.unexplained)
        <> " cancelled with no sign of why, "
        <> int.to_string(closed.open)
        <> " still open",
      )
      io.println(
        "strike answers of the walkers: lost (sent before the deadline fell due, the round closed without it): "
        <> int.to_string(rounds.lost)
        <> "; late (sent at or after it): "
        <> int.to_string(rounds.late)
        <> "; told to no creature: "
        <> int.to_string(rounds.undelivered)
        <> "; matched to no round: "
        <> int.to_string(rounds.unmatched),
      )
    }
  }
  case scene.respawning {
    True -> io.println(respawn_gaps(gaps: total_gaps(counts)))
    False -> Nil
  }
  let gaps = list.map(counts, fn(one) { one.respawns })
  let strikes = creatures_strike(scene:)
  let keeps_up = sum < walkers * samples && running * 2 < samples
  let judged =
    load_judged.judge(
      judged: list.flatten([
        case rounds, strikes {
          Some(rounds), True -> [
            Judged(
              event: load_judged.StrikeRounds,
              count: load_round.round_count(rounds.closed),
              minimum: 1,
            ),
            Judged(
              event: load_judged.StrikeAnswers,
              count: rounds.answers,
              minimum: 1,
            ),
          ]
          None, True -> [
            Judged(
              event: load_judged.StrikeAnswers,
              count: total(fn(one) { one.strikes }),
              minimum: 1,
            ),
          ]
          Some(_), False | None, False -> []
        },
        case scene.mutual && strikes {
          True -> [
            Judged(
              event: load_judged.StrikesAnswered,
              count: total(fn(one) { one.answered_to_own }),
              minimum: int.max(1, total(fn(one) { one.made })),
            ),
          ]
          False -> []
        },
        case scene.respawning {
          True -> [
            Judged(
              event: load_judged.Respawns,
              count: load_respawn.seen(all: gaps),
              minimum: load_respawn.needed(
                all: gaps,
                ended_us:,
                settle_us: settle_ms * 1000,
              ),
            ),
          ]
          False -> []
        },
      ]),
      conditions: list.flatten([
        case rounds {
          Some(rounds) -> [load_judged.nothing_lost(lost: rounds.lost)]
          None -> []
        },
        [
          load_judged.Condition(held: keeps_up, said: case keeps_up {
            True ->
              "the map keeps up: its mean queue stays below one round of moves and it is idle in most samples"
            False ->
              "the map falls behind: its mean queue reached one round of moves, or it is running in most samples"
          }),
        ],
      ]),
    )
  case strikes {
    True -> Nil
    False ->
      io.println(
        "strike rounds, strike answers and strikes answered are not judged: each blow kills the creature before it strikes",
      )
  }
  list.each(judged.lines, io.println)
  io.println(
    "option A's count: "
    <> int.to_string(total(fn(one) { one.option_a }))
    <> " (the creatures in sight, summed over the moves)",
  )
  load_judged.require(verdict: judged)
}

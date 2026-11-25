//// The fight load run: what the map and the creatures cost when many ready players
//// walk among a pack of creatures that fight them.
////
//// ```
//// gleam run -m genesis_prime/load_fight                    50 walkers
//// gleam run -m genesis_prime/load_fight -- 200             200 walkers
//// gleam run -m genesis_prime/load_fight -- 200 delayed 1100
////                      walker 1's answers reach the creature 1,100 ms after it sent them
//// gleam run -m genesis_prime/load_fight -- 200 held 1100
////                      walker 1 sends each answer 1,100 ms after the strike reached it
//// ```
////
//// The environment is the server's own: PGHOST, PGPORT, PGUSER, PGPASSWORD and
//// PGDATABASE name a migrated database, whose 27 Virtual Defense Daguns of
//// migration 0008 stand in World 3460; GENESIS_TABLE_DIR names the client's tables
//// and GENESIS_TERRAIN_DIR the ground's. The server listens on no port of its own
//// (port 0), so another server may be running.
////
//// The server's whole tree runs in this node, with the strike deadlines recorded
//// (`genesis_prime/load_deadline`). The walkers are processes of this node that are
//// connections in the server's registry: each is a Dominion player (faction 166, to
//// which the Daguns are hostile) that joins the map at the centre of the pack (the
//// hostile spawns of the creature that has the most of them: the Daguns), tells it
//// Ready, and for `hold_ms` sends a `Moved` with its next move sequence number every
//// 125 ms, walking at 7 units a second within 40 units of the centre. It does what a
//// player's connection does in a fight: it tells each creature that threatens it each
//// move (`TargetMoved`), answers each strike as landed, and forgets a creature that
//// releases it.
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
//// - the strike rounds: each walker stamps a strike's answer when it hands it over
////   and when the creature has it, and the recorded deadline of the creature's round
////   gives when the round was armed, fell due and closed. An answer is **lost** when
////   it was sent before the round's deadline fell due and was not in the round when it
////   closed; **late** when it was sent at or after the deadline and so was not in the
////   round; the rounds are counted by how they closed: answered, deadline, cancelled
////   with no answer (a death or a control), or still open. A strike is matched to the
////   creature's latest round armed no later than 20 ms after the walker took the
////   strike; an answer that matches none is counted as unmatched;
//// - option A's count: for each move, the creatures in the mover's sight, summed
////   over the moves, the messages a design that told every seen creature of every
////   move would send.
//// The ring crossings and option A's count are worked out by each walker from the
//// same positions the map decides on, by the map's rule (a 10-unit ring of each
//// hostile spawn, sight of 1024 units, every seen spawn Live while a walker sees
//// it), so the map's state carries no counter for a load run.
////
//// **The planted failure.** `delayed MS` makes walker 1 hand its answers to a process
//// that tells the creature MS ms later: they are sent before the deadline and reach
//// the creature after it closed the round, so they are lost. `held MS` makes walker 1
//// send each answer MS ms after the strike reached it: sent after the deadline, so late. With
//// MS above 1,000 (`strike_tell.deadline_ms`) a counter that stays at 0 under either
//// is not counting.
////
//// The walkers all join and are ready before any walks, each starting at its own
//// offset within one 125 ms interval, as clients' timers are. The run passes when
//// the map's queue stays bounded: its mean below the moves of one round (the
//// walkers' count) and its process idle in most samples. The longest queue is
//// printed beside them.

import argv
import genesis_prime/client_connection.{
  type Message, ForStay, SentByFoe, SentByMap, SentByPeer,
}
import genesis_prime/connection/registry
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/hit_radius
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/load_deadline.{type Deadline}
import genesis_prime/load_moves
import genesis_prime/load_run
import genesis_prime/load_sample
import genesis_prime/server
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type ConnectionId, ConnectionId}
import genesis_prime/step/runtime
import genesis_prime/store.{Character, CharacterId, NameStands}
import genesis_prime/table/id.{ClassId, RaceId}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/sight
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/spawn_id.{type SpawnId}
import genesis_prime/world_map/stay
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
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

/// What one walker counted.
type Counts {
  Counts(
    moves: Int,
    approached: Int,
    withdrew: Int,
    target_moved: Int,
    option_a: Int,
    strikes: Int,
    by_creature: Dict(Int, Int),
    creature_news: Int,
    map_notices: Int,
  )
}

/// What a walker does with the answers it gives: all of them as they are, or, for
/// walker 1, with a planted failure (see the module's doc).
type Plant {
  Honest
  Delayed(ms: Int)
  Held(ms: Int)
}

/// One strike a walker was told and answered, on the monotonic clock in
/// microseconds: when it took the strike, when it handed the answer over, and when the
/// creature had it (`delivered` is false when no creature was left to tell). The
/// creature is the process of the creature that struck.
type Answer {
  Answer(
    creature: Pid,
    taken_us: Int,
    sent_us: Int,
    arrived_us: Int,
    delivered: Bool,
  )
}

@external(erlang, "load_fight_ffi", "reductions")
fn reductions(pid: Pid) -> Int

pub fn main() -> Nil {
  let #(walkers, plant) = case argv.load().arguments {
    [count] -> #(whole(count), Honest)
    [count, "delayed", ms] -> #(whole(count), Delayed(ms: whole(ms)))
    [count, "held", ms] -> #(whole(count), Held(ms: whole(ms)))
    [] -> #(50, Honest)
    _ -> panic as "the arguments are: [walkers [delayed|held milliseconds]]"
  }
  let recorder = load_deadline.start()
  let settings =
    load_run.start_server_with(change: fn(settings) {
      let login = settings.login
      server.Settings(
        ..settings,
        login: server.Login(
          sts: server.Served(..login.sts, port: 0),
          auth: server.Served(..login.auth, port: 0),
        ),
        game: server.Served(..settings.game, port: 0),
        service_time: service_shell.ServiceTime(
          ..service_shell.real_time(),
          schedule: load_deadline.scheduler(recorder:),
        ),
      )
    })
  let numbers = content_game_number.numbers(key: settings.world.spawns)
  let spawns =
    dict.values(
      content_spawn.world(key: settings.world.spawns, world_id:).by_id,
    )
  let pack = largest_pack(spawns)
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
  list.each(ids(walkers), fn(id) {
    walker(
      plant: case id {
        1 -> plant
        _ -> Honest
      },
      answers:,
      settings:,
      run:,
      id:,
      centre:,
      spawns:,
      pack:,
      aggro_range: numbers.aggro_range,
      walkers:,
      joined:,
      done:,
    )
  })
  // Every walker joins and is ready before any walks, so the probe and the
  // reductions measure the walk and not the joins' creature starts.
  let starts =
    list.map(ids(walkers), fn(_) {
      let assert Ok(start) = process.receive(joined, within: 60_000)
        as "every walker joined"
      start
    })
  load_moves.start_probe(settings.world.map_supervisor)
  let before = reductions(run.pid)
  list.each(starts, fn(start) { process.send(start, Nil) })
  let counts =
    list.map(ids(walkers), fn(_) {
      let assert Ok(counts) = process.receive(done, within: hold_ms + 60_000)
        as "every walker finished"
      counts
    })
  let after = reductions(run.pid)
  let #(longest, sum, samples, running) = load_moves.stop_probe()
  // A planted answer is delivered up to its delay after the walker finished.
  process.sleep(2 * strike_tell.deadline_ms)
  let rounds =
    rounds_of(
      answers: drain(answers, []),
      deadlines: load_deadline.deadlines(recorder:),
    )
  report(
    walkers:,
    counts:,
    rounds:,
    reductions: after - before,
    longest:,
    sum:,
    samples:,
    running:,
  )
}

/// The whole number the text names, for an argument.
fn whole(text: String) -> Int {
  let assert Ok(number) = int.parse(text)
    as "the arguments' numbers are whole numbers"
  number
}

/// The hostile spawns of the creature that has the most hostile spawns: the pack the
/// walkers walk among. The world also holds hostile spawns far from it, which would
/// pull the pack's centre out of the walkers' reach.
fn largest_pack(spawns: List(Spawn)) -> List(Spawn) {
  let hostile =
    list.filter(spawns, fn(found) { found.combat.hostile_to.dominion })
  let assert Ok(pack) =
    list.group(hostile, fn(found) { found.creature_id })
    |> dict.values
    |> list.reduce(fn(best, group) {
      case list.length(group) > list.length(best) {
        True -> group
        False -> best
      }
    })
    as "the world holds creatures hostile to the Dominion"
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
  answers answers: Subject(Answer),
  settings settings: server.Settings,
  run run: world_map_registry.MapProcess,
  id id: Int,
  centre centre: Place,
  spawns spawns: List(Spawn),
  pack pack: List(Spawn),
  aggro_range aggro_range: Float,
  walkers walkers: Int,
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
            stay: stay.next(stay.none_yet()),
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
      process.sleep(id * move_every_ms / walkers)
      let counts =
        walk(
          plant:,
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
            by_creature: dict.new(),
            creature_news: 0,
            map_notices: 0,
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
        selector:,
        until_ms: next_ms,
        fighters:,
        counts:,
      )
    let place = step_from(place:, id:, step:, centre:)
    let _sent =
      service.tell_subject(
        run.subject,
        map.Moved(connection:, place:, seq: step),
      )
    list.each(dict.to_list(fighters), fn(fighter) {
      creature_registry.tell(
        settings.world.creatures,
        map: MapId(world_id:, instance: 0),
        incarnation: run.incarnation,
        unit_id: fighter.0,
        life: fighter.1,
        message: creature.TargetMoved(
          by: connection,
          place:,
          seq: step,
          stay: stay.next(stay.none_yet()),
          hit_radius: hit_radius.of_playing(
            tables: settings.game.settings.tables,
            race_id: RaceId(1),
          ),
        ),
      )
    })
    let now_inside =
      list.filter(pack, fn(found) {
        creature_path.distance(from: place, to: found.place) <=. aggro_range
      })
      |> list.map(fn(found) { found.id })
      |> set.from_list
    let seen = list.count(spawns, fn(found) { sight.sees(place, found.place) })
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

/// What the walker hears until the next move: a creature's threat makes it a
/// fighter, its release forgets it, and its strike is answered as landed
/// (`answered`). The news of the creatures and the map's notices are counted.
fn hear(
  plant plant: Plant,
  answers answers: Subject(Answer),
  settings settings: server.Settings,
  selector selector: process.Selector(Message),
  until_ms until_ms: Int,
  fighters fighters: Dict(Int, Int),
  counts counts: Counts,
) -> #(Dict(Int, Int), Counts) {
  let again = fn(fighters, counts) {
    hear(plant:, answers:, settings:, selector:, until_ms:, fighters:, counts:)
  }
  case process.selector_receive(selector, int.max(0, until_ms - now())) {
    Error(Nil) -> #(fighters, counts)
    Ok(ForStay(
      sent: SentByFoe(fight: strike_tell.Threatened(unit_id:, life:)),
      ..,
    )) -> again(dict.insert(fighters, unit_id, life), counts)
    Ok(ForStay(sent: SentByFoe(fight: strike_tell.Released(unit_id:)), ..)) ->
      again(dict.delete(fighters, unit_id), counts)
    Ok(ForStay(sent: SentByFoe(fight: strike_tell.Attacks(tell:)), ..)) -> {
      let taken_us = load_sample.microseconds()
      answered(plant:, answers:, settings:, tell:, taken_us:)
      again(fighters, Counts(..counts, strikes: counts.strikes + 1))
    }
    Ok(ForStay(sent: SentByPeer(..), ..)) ->
      again(fighters, Counts(..counts, creature_news: counts.creature_news + 1))
    Ok(ForStay(sent: SentByMap(..), ..)) ->
      again(fighters, Counts(..counts, map_notices: counts.map_notices + 1))
    Ok(_) -> again(fighters, counts)
  }
}

/// Answers the strike as landed, as the walker's plant says, and tells `answers` when
/// it handed the answer over and when the creature had it. A strike of anything but a
/// creature, or of one no longer running, is left unanswered and not recorded.
fn answered(
  plant plant: Plant,
  answers answers: Subject(Answer),
  settings settings: server.Settings,
  tell tell: strike_tell.Tell,
  taken_us taken_us: Int,
) -> Nil {
  case tell.from {
    step.Creature(map:, incarnation:, unit_id:, life:) -> {
      let tell_creature = fn() {
        let told =
          creature_registry.tell(
            settings.world.creatures,
            map:,
            incarnation:,
            unit_id:,
            life:,
            message: creature.StrikeAnswered(answered: strike_tell.Answered(
              key: tell.key,
              outcome: strike_tell.Landed(
                descriptions: [],
                controls: [],
                armor_removed: 0,
                gates_passed: [],
              ),
            )),
          )
        #(load_sample.microseconds(), told == Ok(Nil))
      }
      case
        creature_registry.find(
          settings.world.creatures,
          map:,
          incarnation:,
          unit_id:,
          life:,
        )
      {
        Ok(creature) ->
          handed_over(plant:, answers:, creature:, taken_us:, tell_creature:)
        Error(Nil) -> Nil
      }
    }
    _ -> Nil
  }
}

/// Hands the answer to the creature as the plant says and records it: at once; after
/// `ms` with the send stamped before the wait (`Delayed`: sent early, reaching the
/// creature late); or after `ms` with the send stamped after it (`Held`). `tell_creature`
/// tells the creature and gives the microsecond it had the answer and whether it was told.
fn handed_over(
  plant plant: Plant,
  answers answers: Subject(Answer),
  creature creature: Pid,
  taken_us taken_us: Int,
  tell_creature tell_creature: fn() -> #(Int, Bool),
) -> Nil {
  let record = fn(sent_us: Int) {
    let #(arrived_us, delivered) = tell_creature()
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
  }
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

/// What the strike rounds came to, from the walkers' answers and the recorded
/// deadlines.
type Rounds {
  Rounds(
    answers: Int,
    undelivered: Int,
    unmatched: Int,
    lost: Int,
    late: Int,
    closed_by_answer: Int,
    closed_by_deadline: Int,
    cancelled_without_answer: Int,
    open: Int,
  )
}

/// How far from a round's arming a walker's taking of its strike may be, in
/// microseconds, for the strike to be matched to the round: the creature sends the
/// strike and then arms the deadline in one step, and the walker stamps the strike
/// when it takes it.
const match_slack_us = 20_000

/// The round each answer belongs to: the latest round of the creature that struck,
/// armed no later than `match_slack_us` after the walker took the strike, and not
/// fallen due more than `match_slack_us` before it.
fn round_of(
  answer answer: Answer,
  rounds rounds: List(Deadline),
) -> Result(Deadline, Nil) {
  list.filter(rounds, fn(round) {
    round.armed_us <= answer.taken_us + match_slack_us
  })
  |> list.last
  |> result.try(fn(round) {
    case answer.taken_us <= round.due_us + match_slack_us {
      True -> Ok(round)
      False -> Error(Nil)
    }
  })
}

/// Whether the creature had the answer when the round closed: any answer to a round
/// that is still open, and one that reached the creature no later than the closure
/// otherwise.
fn in_round(answer answer: Answer, round round: Deadline) -> Bool {
  case round.closure {
    load_deadline.Open -> True
    load_deadline.Cancelled(at_us:) | load_deadline.Fired(at_us:) ->
      answer.arrived_us <= at_us
  }
}

fn rounds_of(
  answers answers: List(Answer),
  deadlines deadlines: List(Deadline),
) -> Rounds {
  let by_creature = list.group(answers, fn(answer) { answer.creature })
  let matched =
    list.flat_map(dict.to_list(by_creature), fn(group) {
      let rounds = load_deadline.of_creature(deadlines:, creature: group.0)
      list.map(group.1, fn(answer) { #(answer, round_of(answer:, rounds:)) })
    })
  let #(undelivered, delivered) =
    list.partition(matched, fn(pair) { !{ pair.0 }.delivered })
  let #(unmatched, in_a_round) =
    list.partition(delivered, fn(pair) { result.is_error(pair.1) })
  let judged =
    list.filter_map(in_a_round, fn(pair) {
      result.map(pair.1, fn(round) { #(pair.0, round) })
    })
  let not_in_round =
    list.filter(judged, fn(pair) { !in_round(answer: pair.0, round: pair.1) })
  let lost =
    list.count(not_in_round, fn(pair) { { pair.0 }.sent_us < { pair.1 }.due_us })
  // The first answer to reach each round, by the creature and the round's arming.
  let first_arrival =
    list.fold(judged, dict.new(), fn(first, pair) {
      dict.upsert(first, #({ pair.1 }.creature, { pair.1 }.armed_us), fn(found) {
        case found {
          Some(earlier) -> int.min(earlier, { pair.0 }.arrived_us)
          None -> { pair.0 }.arrived_us
        }
      })
    })
  let closures =
    list.flat_map(dict.keys(by_creature), fn(creature) {
      load_deadline.of_creature(deadlines:, creature:)
    })
  Rounds(
    answers: list.length(answers),
    undelivered: list.length(undelivered),
    unmatched: list.length(unmatched),
    lost:,
    late: list.length(not_in_round) - lost,
    closed_by_answer: list.count(closures, fn(round) {
      case
        round.closure,
        dict.get(first_arrival, #(round.creature, round.armed_us))
      {
        load_deadline.Cancelled(at_us:), Ok(arrived_us) -> arrived_us <= at_us
        _, _ -> False
      }
    }),
    closed_by_deadline: list.count(closures, fn(round) {
      case round.closure {
        load_deadline.Fired(..) -> True
        load_deadline.Open | load_deadline.Cancelled(..) -> False
      }
    }),
    cancelled_without_answer: list.count(closures, fn(round) {
      case
        round.closure,
        dict.get(first_arrival, #(round.creature, round.armed_us))
      {
        load_deadline.Cancelled(at_us:), Ok(arrived_us) -> arrived_us > at_us
        load_deadline.Cancelled(..), Error(Nil) -> True
        _, _ -> False
      }
    }),
    open: list.count(closures, fn(round) { round.closure == load_deadline.Open }),
  )
}

fn report(
  walkers walkers: Int,
  rounds rounds: Rounds,
  counts counts: List(Counts),
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
  io.println(
    int.to_string(walkers)
    <> " walkers, "
    <> int.to_string(hold_ms / 1000)
    <> " s",
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
    "strike rounds: "
    <> int.to_string(rounds.closed_by_answer)
    <> " closed by an answer, "
    <> int.to_string(rounds.closed_by_deadline)
    <> " by the deadline, "
    <> int.to_string(rounds.cancelled_without_answer)
    <> " cancelled with no answer, "
    <> int.to_string(rounds.open)
    <> " still open",
  )
  io.println(
    "strike answers: "
    <> int.to_string(rounds.answers)
    <> " in all; lost (sent before the deadline fell due, not in the round at its closure): "
    <> int.to_string(rounds.lost)
    <> "; late (sent at or after it): "
    <> int.to_string(rounds.late)
    <> "; told to no creature: "
    <> int.to_string(rounds.undelivered)
    <> "; matched to no round: "
    <> int.to_string(rounds.unmatched),
  )
  io.println(
    "option A's count: "
    <> int.to_string(total(fn(one) { one.option_a }))
    <> " (the creatures in sight, summed over the moves)",
  )
  io.println(case sum < walkers * samples && running * 2 < samples {
    True ->
      "pass: the map keeps up: its mean queue stays below one round of moves and it is idle in most samples"
    False ->
      "fail: the map falls behind: its mean queue reached one round of moves, or it is running in most samples"
  })
}

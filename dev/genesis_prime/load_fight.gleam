//// The fight load run: what the map and the creatures cost when many ready players
//// walk among a pack of creatures that fight them (issue 367's load run).
////
//// ```
//// gleam run -m genesis_prime/load_fight              50 walkers
//// gleam run -m genesis_prime/load_fight -- 200       200 walkers
//// ```
////
//// The environment is the server's own: PGHOST, PGPORT, PGUSER, PGPASSWORD and
//// PGDATABASE name a migrated database, whose 27 Virtual Defense Daguns of
//// migration 0008 stand in World 3460 (the pack); GENESIS_TABLE_DIR names the
//// client's tables. The server's ports are the client's defaults, so no server may
//// be running.
////
//// The server's whole tree runs in this node. The walkers are processes of this
//// node that are connections in the server's registry: each is a Dominion player
//// (faction 166, to which the Daguns are hostile) that joins the map at the pack's
//// centre, tells it Ready, and for `hold_ms` sends a `Moved` with its next move
//// sequence number every 125 ms, walking at 7 units a second within 40 units of the
//// centre. It does what a player's connection does in a fight: it tells each
//// creature that threatens it each move (`TargetMoved`), answers each strike as
//// landed, and forgets a creature that releases it.
////
//// What it prints, counters only, nothing traced:
//// - the map's longest and mean message queue and the share of samples that found
////   it running (sampled every 10 ms, genesis_prime/load_moves), and its reductions
////   for each `Moved`;
//// - what the creatures were sent: the `Approached` and `Withdrew` of the rings the
////   walkers crossed, and the `TargetMoved` of their streams, in all and for each
////   creature;
//// - option A's count: for each move, the creatures in the mover's sight, summed
////   over the moves, the messages a design that told every seen creature of every
////   move would send.
//// The ring crossings and option A's count are worked out by each walker from the
//// same positions the map decides on, by the map's rule (a 10-unit ring of each
//// hostile spawn, sight of 1024 units, every seen spawn Live while a walker sees
//// it), so the map's state carries no counter for a load run.
////
//// The walkers all join and are ready before any walks, each starting at its own
//// offset within one 125 ms interval, as clients' timers are. The run passes when
//// the map's queue stays bounded: its mean below the moves of one round (the
//// walkers' count) and its process idle in most samples. The longest queue is
//// printed beside them.

import argv
import genesis_prime/client_connection.{type Message, ForStay, SentByFoe}
import genesis_prime/connection/registry
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/load_moves
import genesis_prime/load_run
import genesis_prime/server
import genesis_prime/service
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
import gleam/option.{None}
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
  )
}

@external(erlang, "load_fight_ffi", "reductions")
fn reductions(pid: Pid) -> Int

pub fn main() -> Nil {
  let walkers = case argv.load().arguments {
    [count] -> {
      let assert Ok(count) = int.parse(count)
        as "the number of walkers is a whole number"
      count
    }
    _ -> 50
  }
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
      )
    })
  let numbers = content_game_number.numbers(key: settings.world.spawns)
  let spawns =
    dict.values(
      content_spawn.world(key: settings.world.spawns, world_id:).by_id,
    )
  let pack = list.filter(spawns, fn(found) { found.combat.hostile_to.dominion })
  let assert [_, ..] = pack
    as "the world holds creatures hostile to the Dominion"
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
  list.each(ids(walkers), fn(id) {
    walker(
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
  report(
    walkers:,
    counts:,
    reductions: after - before,
    longest:,
    sum:,
    samples:,
    running:,
  )
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
      hear(settings:, selector:, until_ms: next_ms, fighters:, counts:)
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
/// fighter, its release forgets it, and its strike is answered as landed.
fn hear(
  settings settings: server.Settings,
  selector selector: process.Selector(Message),
  until_ms until_ms: Int,
  fighters fighters: Dict(Int, Int),
  counts counts: Counts,
) -> #(Dict(Int, Int), Counts) {
  case process.selector_receive(selector, int.max(0, until_ms - now())) {
    Error(Nil) -> #(fighters, counts)
    Ok(ForStay(
      sent: SentByFoe(fight: strike_tell.Threatened(unit_id:, life:)),
      ..,
    )) ->
      hear(
        settings:,
        selector:,
        until_ms:,
        fighters: dict.insert(fighters, unit_id, life),
        counts:,
      )
    Ok(ForStay(sent: SentByFoe(fight: strike_tell.Released(unit_id:)), ..)) ->
      hear(
        settings:,
        selector:,
        until_ms:,
        fighters: dict.delete(fighters, unit_id),
        counts:,
      )
    Ok(ForStay(sent: SentByFoe(fight: strike_tell.Attacks(tell:)), ..)) -> {
      let _told = case tell.from {
        step.Creature(map:, incarnation:, unit_id:, life:) ->
          creature_registry.tell(
            settings.world.creatures,
            map:,
            incarnation:,
            unit_id:,
            life:,
            message: creature.StrikeAnswered(answered: strike_tell.Answered(
              key: tell.key,
              outcome: strike_tell.Landed(descriptions: []),
            )),
          )
        _ -> Error(Nil)
      }
      hear(
        settings:,
        selector:,
        until_ms:,
        fighters:,
        counts: Counts(..counts, strikes: counts.strikes + 1),
      )
    }
    Ok(_) -> hear(settings:, selector:, until_ms:, fighters:, counts:)
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

fn report(
  walkers walkers: Int,
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

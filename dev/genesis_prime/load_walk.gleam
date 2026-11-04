//// The walking load run: what a map and its creatures cost when a player walks
//// through a world of the whole world database, and when many players crowd the
//// densest place in it (issue 375, tests 21 and 22).
////
//// ```
//// gleam run -m genesis_prime/load_walk                 one player walks world 51 corner to corner
//// gleam run -m genesis_prime/load_walk -- crowd 50     50 players walk about the densest place of world 51
//// ```
////
//// The environment is the server's own: PGHOST, PGPORT, PGUSER, PGPASSWORD and
//// PGDATABASE name a migrated database that holds the imported world database
//// (`gleam run -m genesis_prime/import_world_data`), GENESIS_TABLE_DIR the client's
//// tables. The server's ports are the client's defaults, so no server may be running.
////
//// The server's whole tree runs in this node, loaded as `gleam run` loads it. The
//// players are processes of this node that are connections in the server's registry
//// (genesis_prime/connection/registry): each joins the map of world 51 and sends the
//// map a `Moved` every 125 ms, the rate of the client's own movement, at 7 units a
//// second; the creatures send each its 0x262s and 0x355s as messages, which it counts.
//// So the run measures the map and the creatures and not the sockets, the cipher or
//// the frames.
////
//// - **The walk** goes from the spawn of the world's started creatures with the
////   least x plus z to the one with the most, in a straight line, at the client's
////   own speed, and then the player leaves. The creature count must return to 0
////   within 70 s of the leave.
//// - **The crowd** walks about the densest place of the world (the spawn with the
////   most spawns within 1024 units) for two minutes, each player at 7 units a
////   second, turning every 5 s, within 300 units of the place.
//// - **What it prints:** the start-up (the content load's terms and the literal
////   area the tables and terms take), and a line for each 30 s: the creatures
////   running and the memory of the creatures and of the node; then the peak
////   creatures; the map's longest and mean message queue and the share of its
////   samples that found it running, sampled every 10 ms by the movement load run's
////   probe (genesis_prime/load_moves); the time a creature takes to start (from the
////   `Moved` or the Join that starts them to the last of their 0x262s reaching the
////   player, divided by how many), for the Join and for the walk's moves; the most
////   creatures started in any second; and the time the creatures took to end.

import argv
import genesis_prime/client_connection.{
  type Message, CreatureAppeared, PeerNews, SentByPeer,
}
import genesis_prime/connection/registry
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/start_place
import genesis_prime/load_moves
import genesis_prime/load_run
import genesis_prime/server
import genesis_prime/service
import genesis_prime/step.{ConnectionId}
import genesis_prime/step/runtime
import genesis_prime/store.{Character, CharacterId, NameStands}
import genesis_prime/table/id.{ClassId, RaceId}
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/spawn_cell
import gleam/bool
import gleam/dict
import gleam/erlang/process.{type Name, type Subject}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam_community/maths

/// The world walked in: Eastern, with 12,788 spawns that start.
const world_id = 51

/// How often a player sends its position, in milliseconds: the client's.
const move_every_ms = 125

/// The client's walking speed in units a second.
const speed = 7.0

/// How long the crowd walks, and how far from its place each player may go.
const crowd_ms = 120_000

const crowd_radius = 300.0

/// One sample of the creatures, once a second.
type Sample {
  Sample(at_ms: Int, creatures: Int, creature_bytes: Int, node_bytes: Int)
}

/// What one player saw: when each creature's 0x262 reached it, and how long each
/// burst of starts took.
type Seen {
  Seen(join: Burst, appeared_us: List(Int), bursts: List(Burst))
}

/// The creatures one Join or one `Moved` started, as the player saw them: how many
/// of their 0x262s arrived, and the microseconds from the ask to the last of them.
type Burst {
  Burst(count: Int, span_us: Int)
}

@external(erlang, "load_walk_ffi", "sample")
fn take_sample(creatures: Name(a)) -> #(Int, Int, Int)

@external(erlang, "load_walk_ffi", "term_bytes")
fn term_bytes(term: a) -> Int

@external(erlang, "load_walk_ffi", "literal_bytes")
fn literal_bytes() -> Int

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: MicroSecond) -> Int

type MicroSecond {
  Microsecond
}

fn now_us() -> Int {
  monotonic_time(Microsecond)
}

pub fn main() -> Nil {
  let started_at = now()
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
  io.println(
    "the server started in "
    <> int.to_string(now() - started_at)
    <> " ms, with the content loaded before its tree",
  )
  let terms =
    list.fold([22, 51, 426, 870, 990, 1061, 1387, 3460], 0, fn(bytes, world) {
      bytes
      + term_bytes(content_spawn.world(
        key: settings.world.spawns,
        world_id: world,
      ))
    })
  io.println(
    "the content terms of the worlds that have spawns: "
    <> int.to_string(terms / 1_000_000)
    <> " MB; the literal area after the start, where the client's tables and these terms sit: "
    <> int.to_string(literal_bytes() / 1_000_000)
    <> " MB",
  )
  let spawns =
    dict.values(
      content_spawn.world(key: settings.world.spawns, world_id:).by_id,
    )
  load_moves.start_probe(settings.world.map_supervisor)
  let samples = process.new_subject()
  let _sampler = start_sampler(settings:, into: samples)
  case argv.load().arguments {
    ["crowd", players] -> {
      let assert Ok(players) = int.parse(players)
        as "the number of players is a whole number"
      crowd(settings:, spawns:, players:)
    }
    _ -> walk(settings:, spawns:)
  }
  report(settings:, samples:)
}

fn now() -> Int {
  runtime.now().monotonic_ms
}

/// A process that takes a sample every second into the subject, until the node
/// ends.
fn start_sampler(
  settings settings: server.Settings,
  into samples: Subject(Sample),
) -> process.Pid {
  process.spawn_unlinked(fn() { sample_forever(settings, samples) })
}

fn sample_forever(settings: server.Settings, samples: Subject(Sample)) -> Nil {
  let #(creatures, creature_bytes, node_bytes) =
    take_sample(settings.world.creature_supervisor)
  process.send(
    samples,
    Sample(at_ms: now(), creatures:, creature_bytes:, node_bytes:),
  )
  process.sleep(1000)
  sample_forever(settings, samples)
}

/// A player standing where the walk says, a connection in the server's
/// registry that joins the map of the world, sends it a `Moved` every
/// `move_every_ms`, hears the 0x262s the creatures send it, and leaves at the end.
/// What it saw is sent to `done`: when each creature appeared and how long each
/// burst of starts took.
fn player(
  settings settings: server.Settings,
  id id: Int,
  steps steps: Int,
  position position: fn(Int) -> #(Float, Float, Float),
  done done: Subject(Seen),
) -> Nil {
  let _pid =
    process.spawn_unlinked(fn() {
      registry.join(settings.registry, connection: ConnectionId(id))
      let selector =
        registry.select_delivered(
          settings.registry,
          process.new_selector(),
          fn(message) { message },
        )
      let assert Ok(run) =
        world_map_registry.find_or_start(
          settings.world.maps,
          MapId(world_id:, instance: 0),
          deadline_ms: now() + 5000,
        )
        as "the map of the world started"
      let replies = process.new_subject()
      let #(x, y, z) = position(0)
      let joined_us = now_us()
      let _sent =
        service.call_subject(
          run.subject,
          map.Join(
            connection: ConnectionId(id),
            character: character(id),
            place: place(x:, y:, z:),
          ),
          fn(answer) { process.send(replies, answer) },
        )
      let assert Ok(_joined) = process.receive(replies, within: 60_000)
        as "the map answered the join"
      let at_join = collect(selector:, wait: fn() { join_quiet_ms }, found: [])
      let seen =
        walk_steps(
          run:,
          selector:,
          id:,
          step: 1,
          steps:,
          position:,
          seen: Seen(
            join: burst(at_join, from: joined_us),
            appeared_us: at_join,
            bursts: [],
          ),
        )
      let _sent =
        service.call_subject(
          run.subject,
          map.Leave(connection: ConnectionId(id)),
          fn(answer) { process.send(replies, answer) },
        )
      let _left = process.receive(replies, within: 60_000)
      process.send(done, seen)
    })
  Nil
}

/// How long after the Join's answer the player waits for the creatures of the
/// Join to stop arriving.
const join_quiet_ms = 500

fn walk_steps(
  run run: world_map_registry.MapProcess,
  selector selector: process.Selector(Message),
  id id: Int,
  step step: Int,
  steps steps: Int,
  position position: fn(Int) -> #(Float, Float, Float),
  seen seen: Seen,
) -> Seen {
  use <- bool.guard(when: step > steps, return: seen)
  let #(x, y, z) = position(step)
  let sent_us = now_us()
  let _sent =
    service.tell_subject(
      run.subject,
      map.Moved(connection: ConnectionId(id), place: place(x:, y:, z:)),
    )
  let deadline_us = sent_us + move_every_ms * 1000
  let arrived =
    collect(
      selector:,
      wait: fn() { int.max(0, { deadline_us - now_us() } / 1000) },
      found: [],
    )
  walk_steps(
    run:,
    selector:,
    id:,
    step: step + 1,
    steps:,
    position:,
    seen: Seen(
      ..seen,
      appeared_us: list.append(arrived, seen.appeared_us),
      bursts: case arrived {
        [] -> seen.bursts
        _ -> [burst(arrived, from: sent_us), ..seen.bursts]
      },
    ),
  )
}

/// The creatures that appeared to the player, as the microsecond each arrived
/// (newest first) added to `found`: it listens for `wait()` milliseconds after each
/// message and stops when that passes with none.
fn collect(
  selector selector: process.Selector(Message),
  wait wait: fn() -> Int,
  found found: List(Int),
) -> List(Int) {
  case process.selector_receive(selector, within: wait()) {
    Error(Nil) -> found
    Ok(SentByPeer(PeerNews(news: CreatureAppeared(..), ..))) ->
      collect(selector:, wait:, found: [now_us(), ..found])
    Ok(_other) -> collect(selector:, wait:, found:)
  }
}

/// The burst of starts whose creatures appeared at `appeared` (newest first),
/// asked for at `from_us`.
fn burst(appeared: List(Int), from from_us: Int) -> Burst {
  Burst(count: list.length(appeared), span_us: case appeared {
    [] -> 0
    [last, ..] -> last - from_us
  })
}

fn character(id: Int) -> store.Character {
  Character(
    character_id: CharacterId(id),
    name: "Walker",
    gender: 0,
    race_id: RaceId(1),
    class_id: ClassId(1),
    faction_id: 166,
    level: 1,
    path: 0,
    place: None,
    look: [],
    bones: [],
    naming: NameStands,
  )
}

fn place(x x: Float, y y: Float, z z: Float) -> start_place.Place {
  let assert Ok(place) =
    start_place.place(
      world_id:,
      world_zone_id: 0,
      x:,
      y:,
      z:,
      facing: start_place.unturned,
    )
    as "the world is not 0"
  place
}

/// One player walks from one corner of the world's spawns to the other.
fn walk(settings settings: server.Settings, spawns spawns: List(Spawn)) -> Nil {
  let sorted =
    list.sort(spawns, fn(first, second) {
      float.compare(
        start_place.x(first.place) +. start_place.z(first.place),
        start_place.x(second.place) +. start_place.z(second.place),
      )
    })
  let assert Ok(from) = list.first(sorted) as "the world has spawns"
  let assert Ok(to) = list.last(sorted) as "the world has spawns"
  let #(fx, fy, fz) = #(
    start_place.x(from.place),
    start_place.y(from.place),
    start_place.z(from.place),
  )
  let #(tx, ty, tz) = #(
    start_place.x(to.place),
    start_place.y(to.place),
    start_place.z(to.place),
  )
  let length = distance(#(fx, fy, fz), #(tx, ty, tz))
  let steps =
    float.truncate(length /. speed *. 1000.0 /. int.to_float(move_every_ms))
  io.println(
    "one player walks "
    <> float.to_string(float.to_precision(length, 0))
    <> " units, from ("
    <> float.to_string(float.to_precision(fx, 0))
    <> ", "
    <> float.to_string(float.to_precision(fz, 0))
    <> ") to ("
    <> float.to_string(float.to_precision(tx, 0))
    <> ", "
    <> float.to_string(float.to_precision(tz, 0))
    <> "), in "
    <> int.to_string(steps * move_every_ms / 1000)
    <> " s",
  )
  let done = process.new_subject()
  player(
    settings:,
    id: 1,
    steps:,
    position: fn(step) {
      let share = int.to_float(step) /. int.to_float(steps)
      #(
        fx +. { tx -. fx } *. share,
        fy +. { ty -. fy } *. share,
        fz +. { tz -. fz } *. share,
      )
    },
    done:,
  )
  let assert Ok(seen) =
    process.receive(done, within: steps * move_every_ms + 120_000)
    as "the player finished its walk"
  io.println("the player left; " <> describe_starts([seen]))
  let left_at = now()
  wait_for_no_creatures(settings:, left_at:)
}

fn distance(from: #(Float, Float, Float), to: #(Float, Float, Float)) -> Float {
  let dx = to.0 -. from.0
  let dy = to.1 -. from.1
  let dz = to.2 -. from.2
  float.square_root(dx *. dx +. dy *. dy +. dz *. dz) |> result.unwrap(0.0)
}

/// Many players walk about the densest place of the world.
fn crowd(
  settings settings: server.Settings,
  spawns spawns: List(Spawn),
  players players: Int,
) -> Nil {
  let world = content_spawn.world(key: settings.world.spawns, world_id:)
  let densest =
    list.fold(spawns, #(0, spawns), fn(best, candidate) {
      let near =
        spawn_cell.near(
          cells: world.cells,
          x: start_place.x(candidate.place),
          z: start_place.z(candidate.place),
          range: 1024.0,
        )
        |> list.length
      case near > best.0 {
        True -> #(near, [candidate])
        False -> best
      }
    })
  let assert Ok(centre) = list.first(densest.1) as "a densest place"
  let #(cx, cy, cz) = #(
    start_place.x(centre.place),
    start_place.y(centre.place),
    start_place.z(centre.place),
  )
  io.println(
    int.to_string(players)
    <> " players walk about ("
    <> float.to_string(float.to_precision(cx, 0))
    <> ", "
    <> float.to_string(float.to_precision(cz, 0))
    <> "), which has "
    <> int.to_string(densest.0)
    <> " spawns within 1024 units, for "
    <> int.to_string(crowd_ms / 1000)
    <> " s",
  )
  let steps = crowd_ms / move_every_ms
  let done = process.new_subject()
  let ids =
    int.range(from: 1, to: players + 1, with: [], run: fn(ids, id) {
      [id, ..ids]
    })
  list.each(ids, fn(id) {
    player(
      settings:,
      id:,
      steps:,
      position: fn(step) { around(cx:, cy:, cz:, id:, step:) },
      done:,
    )
  })
  let seen =
    list.map(ids, fn(_id) {
      let assert Ok(seen) = process.receive(done, within: crowd_ms + 120_000)
        as "a player finished"
      seen
    })
  io.println("the players left; " <> describe_starts(seen))
  wait_for_no_creatures(settings:, left_at: now())
}

/// Where player `id` is at `step`: a walk about the place that turns every 5 s,
/// each player on a heading of its own, kept within `crowd_radius` of the place by
/// an out-and-back path along it.
fn around(
  cx cx: Float,
  cy cy: Float,
  cz cz: Float,
  id id: Int,
  step step: Int,
) -> #(Float, Float, Float) {
  let per_leg = 5000 / move_every_ms
  let leg = step / per_leg
  let along =
    int.to_float(step % per_leg)
    *. speed
    *. int.to_float(move_every_ms)
    /. 1000.0
  let heading = int.to_float({ id * 7 + leg * 13 } % 360) *. 3.14159265 /. 180.0
  let #(sin, cos) = #(maths.sin(heading), maths.cos(heading))
  let out = case leg % 2 {
    0 -> along
    _ -> 5.0 *. speed -. along
  }
  let out = float.min(out, crowd_radius)
  #(cx +. cos *. out, cy, cz +. sin *. out)
}

/// Waits until the creatures running are none, up to 120 s, and says how long it
/// took.
fn wait_for_no_creatures(
  settings settings: server.Settings,
  left_at left_at: Int,
) -> Nil {
  let #(creatures, _bytes, _node) =
    take_sample(settings.world.creature_supervisor)
  case creatures, now() - left_at > 120_000 {
    0, _ ->
      io.println(
        "the creatures were all stopped "
        <> int.to_string({ now() - left_at } / 1000)
        <> " s after the last player left",
      )
    _, True ->
      io.println(
        int.to_string(creatures)
        <> " creatures were still running 120 s after the last player left",
      )
    _, False -> {
      process.sleep(1000)
      wait_for_no_creatures(settings:, left_at:)
    }
  }
}

/// What the players saw of the starts: how many appearances were sent to them,
/// the most in any one second, and how long a creature took to start, as the time
/// from the ask (the Join, or the `Moved`) to the last of the burst's 0x262s,
/// divided by the creatures in the burst: for the Joins, and for the walks' moves.
fn describe_starts(seen: List(Seen)) -> String {
  let appeared = list.flat_map(seen, fn(one) { one.appeared_us })
  int.to_string(list.length(appeared))
  <> " creature appearances were sent to them, the most in any second: "
  <> int.to_string(most_in_a_second(appeared))
  <> "; time to start a creature, from the ask to the last 0x262 of its burst: "
  <> "at the Join "
  <> per_start(list.map(seen, fn(one) { one.join }))
  <> "; at the walk's moves "
  <> per_start(list.flat_map(seen, fn(one) { one.bursts }))
}

/// A set of bursts as the mean microseconds a creature took to start, the bursts'
/// count and the slowest of them.
fn per_start(bursts: List(Burst)) -> String {
  let counted = list.filter(bursts, fn(one) { one.count > 0 })
  let creatures = list.fold(counted, 0, fn(sum, one) { sum + one.count })
  let span = list.fold(counted, 0, fn(sum, one) { sum + one.span_us })
  case counted {
    [] -> "no creatures started"
    _ -> {
      let slowest =
        list.fold(counted, Burst(count: 0, span_us: 0), fn(worst, one) {
          case one.span_us > worst.span_us {
            True -> one
            False -> worst
          }
        })
      int.to_string(span / int.max(creatures, 1))
      <> " us each over "
      <> int.to_string(creatures)
      <> " creatures in "
      <> int.to_string(list.length(counted))
      <> " bursts, the slowest "
      <> int.to_string(slowest.span_us / 1000)
      <> " ms for "
      <> int.to_string(slowest.count)
    }
  }
}

/// The most appearances in any one second of the run.
fn most_in_a_second(times: List(Int)) -> Int {
  list.group(times, fn(at_us) { at_us / 1_000_000 })
  |> dict.values
  |> list.map(list.length)
  |> list.fold(0, int.max)
}

/// The samples as a line each 30 s and the totals.
fn report(
  settings settings: server.Settings,
  samples samples: Subject(Sample),
) -> Nil {
  let _settings = settings
  let #(longest, queued, probed, running) = load_moves.stop_probe()
  let by_time = list.reverse(drain(samples, []))
  case by_time {
    [] -> io.println("no sample was taken")
    [first, ..] -> {
      list.each(by_time, fn(sample) { print_each_30_s(sample:, first:) })
      io.println(totals(by_time:, first:))
    }
  }
  io.println(
    "the map's message queue: longest "
    <> int.to_string(longest)
    <> ", mean "
    <> load_moves.per(total: queued, count: probed)
    <> " over "
    <> int.to_string(probed)
    <> " samples, one every 10 ms; its process was found running in "
    <> load_moves.percent(part: running, whole: probed)
    <> " of them",
  )
}

/// The line of a sample taken a whole 30 s after the first, and none for another.
fn print_each_30_s(sample sample: Sample, first first: Sample) -> Nil {
  let seconds = { sample.at_ms - first.at_ms } / 1000
  use <- bool.guard(when: seconds % 30 != 0, return: Nil)
  io.println(
    "t+"
    <> int.to_string(seconds)
    <> " s: "
    <> int.to_string(sample.creatures)
    <> " creatures, creatures "
    <> int.to_string(sample.creature_bytes / 1_000_000)
    <> " MB, node "
    <> int.to_string(sample.node_bytes / 1_000_000)
    <> " MB",
  )
}

/// The peak of creatures, with the memory each took.
fn totals(by_time by_time: List(Sample), first first: Sample) -> String {
  let peak =
    list.fold(by_time, first, fn(best, sample) {
      case sample.creatures > best.creatures {
        True -> sample
        False -> best
      }
    })
  "peak "
  <> int.to_string(peak.creatures)
  <> " creatures running, using "
  <> int.to_string(peak.creature_bytes / 1_000_000)
  <> " MB ("
  <> int.to_string(peak.creature_bytes / int.max(peak.creatures, 1) / 1000)
  <> " KB each), over "
  <> int.to_string(list.length(by_time))
  <> " samples, one a second"
}

fn drain(samples: Subject(Sample), found: List(Sample)) -> List(Sample) {
  case process.receive(samples, within: 0) {
    Ok(sample) -> drain(samples, [sample, ..found])
    Error(Nil) -> found
  }
}

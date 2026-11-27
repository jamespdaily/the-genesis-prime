//// Players on one map, with the map's rule and each player's connection rule, each with its
//// mailbox, and every order in which the BEAM may deliver what they send
//// (`player_scene_support`). Expected values come from these places.
//// - A player's unit reaches its viewers only through the map: the map names a sight and its
////   generation to the owner (`SeenBy`), the owner answers with one snapshot, the map relays
////   it, and the map tells the viewer the sight ended (`PlayerUnseen`). The owner's moves
////   are the one thing it tells a viewer itself, stamped with the generation
////   (`genesis_prime/game/move_stamp`).
//// - The client's rules: a unit is created once and removed once and is told no frame before
////   its 0x262 or after its 0x355 (`opcode.0x262`, `opcode.0x355`); a cast the viewer was
////   told by its caster is ended by the caster's frames (`opcode.0x7fe`, `cast.target_node_end`).
//// - Sight is symmetric and 1024 units (`genesis_prime/world_map/sight`).

import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection
import genesis_prime/game/effect_kind
import genesis_prime/game/held_changes
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_casts.{EndsAt, HeldEffect}
import genesis_prime/game/unit_news.{Appeared, PeerNews}
import genesis_prime/game/unit_properties.{Source}
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/generation
import genesis_prime/world_map/map
import genesis_prime/world_map/relay
import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/set
import gleam/string
import legal_order_support
import map_support
import order_explorer
import owned_test
import planted_table
import player_scene_support as scene
import spawn_support
import strike_support

/// The unit the map gives the player of connection `connection` when the scene's players
/// enter in the order of their numbers from 1.
fn unit_of(connection connection: Int) -> Int {
  connection
}

/// The class and level of a plain player of the scenes: a Medic (class 4) of level 1.
const medic = 4

/// Two players in sight of each other, after every message of their entry is delivered: the
/// owner C (connection 1) at x 1000 and the viewer V (connection 2) at x 0, 1000 apart, with
/// sight 1024.
fn two_players() -> scene.Scene {
  scene.settle(scene: two_players_entering())
}

/// The same two players with no message of their entry delivered: the map has taken both
/// joins, and C has not yet taken its `SeenBy` of V, so C's snapshot of the first sight is
/// still to be built and sent.
fn two_players_entering() -> scene.Scene {
  scene.new(tables: connection_support.settings().tables)
  |> scene.enter(
    connection: 1,
    class_id: medic,
    level: 1,
    place: scene.at(x: 1000.0),
  )
  |> scene.enter(
    connection: 2,
    class_id: medic,
    level: 1,
    place: scene.at(x: 0.0),
  )
}

/// What V was written for the owner's unit, as `0x262(1)` and so on.
fn written_for_c(scene scene: scene.Scene) -> List(String) {
  scene.written_for(scene:, connection: 2, unit_id: unit_of(connection: 1))
}

/// The relation the map holds with V as a viewer of C.
fn relation(scene scene: scene.Scene) -> option.Option(map.Relation) {
  map.player_relation(
    state: scene.map,
    owner: ConnectionId(1),
    viewer: ConnectionId(2),
  )
}

pub fn a_pair_is_shown_by_the_owners_snapshot_and_one_that_leaves_and_returns_is_two_generations_and_needs_a_new_snapshot_in_every_legal_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let entered = two_players_entering()
  let assert Some(map.Relation(
    generation: first,
    state: map.AwaitingSnapshot,
    ..,
  )) = relation(scene: entered)
    as "the pair awaits the owner's snapshot of its first generation"
  // C's snapshot of that generation is in flight to the map while V's client moves out of
  // C's sight and back: V's connection tells the map each place, and the map takes C's
  // snapshot before, between or after them.
  let moving =
    list.fold([3000.0, 0.0], entered, fn(so_far, x) {
      scene.client_sends(
        scene: so_far,
        connection: 2,
        bytes: connection_support.a_move(x),
        name: "0x637 of V to " <> float.to_string(x),
      )
    })
  let scenes = scene.orders(scene: moving)
  assert scenes != [] as "the scene has an order"
  list.each(scenes, fn(done) {
    assert scene.check(scene: done, connection: 2) == Ok(Nil)
      as "no frame of C before its 0x262 or after its 0x355, whatever the order"
    assert shows_c_once_at_the_end(names: written_for_c(scene: done))
      as "V is written C's 0x262, and after a 0x355 a 0x262 of the new sight: the snapshot of the sight that ended, taken after it, writes nothing"
    let assert Some(map.Relation(generation: second, state: map.Relaying, ..)) =
      relation(scene: done)
      as "the new sight relays after its own snapshot"
    assert generation.compare(second, first) == order.Gt
      as "the new sight is a new generation"
    assert scene.direct_news(scene: done, from: 1, to: 2) == []
      as "C told V nothing itself: its 0x262 and its 0x355 are the map's"
  })
  let results =
    list.map(scenes, fn(done) { written_for_c(scene: done) })
    |> list.unique
  assert list.contains(results, ["0x262(1)", "0x355(1)", "0x262(1)"])
    && list.contains(results, ["0x262(1)"])
    as "the snapshot of the first sight taken before the unseen shows C twice; taken after it, it is dropped and C is shown once, from the new sight's"
}

/// Whether V's frames for C's unit are one 0x262, or a 0x262, a 0x355 and a 0x262: the unit
/// is shown at the end, in the sight that ended or in the new one.
fn shows_c_once_at_the_end(names names: List(String)) -> Bool {
  names == ["0x262(1)"] || names == ["0x262(1)", "0x355(1)", "0x262(1)"]
}

/// Whether V's frames for C's unit are the shape of a unit that leaves and returns: its
/// 0x262, any moves, one 0x355, a second 0x262 and then only moves.
fn leaves_and_returns(names names: List(String)) -> Bool {
  let opcodes = list.map(names, fn(name) { string.slice(name, 0, 5) })
  case list.split_while(opcodes, fn(opcode) { opcode != "0x355" }) {
    #(before, ["0x355", ..after]) ->
      list.first(before) == Ok("0x262")
      && list.all(list.drop(before, 1), fn(opcode) { opcode == "0x638" })
      && list.first(after) == Ok("0x262")
      && list.all(list.drop(after, 1), fn(opcode) { opcode == "0x638" })
    _ -> False
  }
}

/// C's client sends the 0x637 that takes V out of its sight: C stands 1000 from V, whose
/// sight is 1024, and moves to 2000. C tells the map the place and V the move (its own
/// message), and the map tells V the unit is unseen (its own): V takes them in either order.
fn c_moves_out_of_v_sight() -> scene.Scene {
  scene.client_sends(
    scene: two_players(),
    connection: 1,
    bytes: connection_support.a_move(2000.0),
    name: "0x637 of C",
  )
}

pub fn a_move_that_takes_a_viewer_out_of_sight_is_written_before_its_0x355_or_not_at_all_and_never_after_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let scenes = scene.orders(scene: c_moves_out_of_v_sight())
  let results =
    list.map(scenes, fn(done) {
      assert scene.check(scene: done, connection: 2) == Ok(Nil)
        as "no frame of C after its 0x355, whatever the order"
      assert scene.direct_news(scene: done, from: 1, to: 2) == []
        as "C told V nothing itself but its move: the 0x355 is the map's"
      list.drop(written_for_c(scene: done), 1)
    })
  assert list.all(results, fn(result) {
    result == ["0x638(1)", "0x355(1)"] || result == ["0x355(1)"]
  })
    as "V is written the move and then the 0x355, or the 0x355 alone; never the move after it"
  assert list.contains(results, ["0x638(1)", "0x355(1)"])
    && list.contains(results, ["0x355(1)"])
    as "both orders are legal and each has its own result: the unit is removed either way"
}

pub fn a_unit_that_leaves_and_returns_is_shown_in_its_new_generation_and_a_move_of_the_old_one_never_moves_it_test() -> Nil {
  use <- owned_test.run(10_000)
  // C leaves V's sight, comes back and goes on: three 0x637s of C's client, taken in
  // order by C; their moves, the map's notices and its snapshots reach V in any legal order.
  let settled = two_players()
  let assert Some(map.Relation(generation: first, ..)) =
    relation(scene: settled)
    as "the map holds the sight V has of C"
  let moving =
    list.fold([3000.0, 1000.0, 1001.0], settled, fn(so_far, x) {
      scene.client_sends(
        scene: so_far,
        connection: 1,
        bytes: connection_support.a_move(x),
        name: "0x637 of C to " <> float.to_string(x),
      )
    })
  list.each(scene.orders(scene: moving), fn(done) {
    assert scene.check(scene: done, connection: 2) == Ok(Nil)
      as "no frame of C before its 0x262 or after its 0x355"
    assert leaves_and_returns(names: written_for_c(scene: done))
      as "V is written C's 0x262, then its 0x355, then a 0x262 of the new sight and only moves after it: a move of the sight that ended never moves the unit again"
    let assert Some(map.Relation(generation: second, state: map.Relaying, ..)) =
      relation(scene: done)
      as "the new sight relays"
    assert generation.compare(second, first) == order.Gt
      as "the new sight is a new generation"
    assert scene.direct_news(scene: done, from: 1, to: 2) == []
      as "C told V nothing itself but its moves"
  })
}

// ---- casts: Phantasmal Armor pressed by an Esper at an ally ----

/// What a viewer outside the cast's two units is written of the Esper's Phantasmal Armor on an
/// ally in sight, as the server writes it today: the cast's start and go, twice (the cast and
/// its child), and nothing that ends the cast, since the spell keeps its buff after its caster
/// leaves (propertyFlags 0x100, `cast.target_node_end`). The same frames must reach it
/// whichever order the messages are taken in.
const armor_frames = [0x07FF, 0x07F4, 0x07FF, 0x07F4]

/// Spell4 32823, Phantasmal Armor, is an Esper's at level 6 by SpellLevel row 773, which
/// the fixture lacks (`game_connection_cast_viewers_test` adds it the same way).
fn with_the_armor(body body: fn(table_store.Tables) -> Nil) -> Nil {
  fixture_tables.added(
    table: "SpellLevel",
    copy_of: 647,
    id: 773,
    with: [
      #("characterLevel", planted_table.Integer(6)),
      #("spell4Id", planted_table.Integer(32_823)),
    ],
    body:,
  )
}

/// An Esper of level 6, C (connection 1, at x 0), the ally T (connection 2, at x 20, inside
/// the spell's target range) and the control viewer V (connection 3, at x 1000), all in sight
/// of each other, settled; and the bag index of Phantasmal Armor.
fn armor_world(tables tables: table_store.Tables) -> #(scene.Scene, Int) {
  let world =
    scene.new(tables:)
    |> scene.enter(
      connection: 1,
      class_id: 3,
      level: 6,
      place: scene.at(x: 0.0),
    )
    |> scene.enter(
      connection: 2,
      class_id: medic,
      level: 1,
      place: scene.at(x: 20.0),
    )
    |> scene.enter(
      connection: 3,
      class_id: medic,
      level: 1,
      place: scene.at(x: 1000.0),
    )
    |> scene.settle
  #(
    world,
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_033,
    ),
  )
}

/// C's connection takes the press of Phantasmal Armor at T: its go runs in that step, and
/// what the step sent (its cast news for the map, its tells to T) is in flight, none of it
/// taken yet.
fn pressed(world world: scene.Scene, bag_index bag_index: Int) -> scene.Scene {
  let with_the_press =
    scene.client_presses(
      scene: world,
      connection: 1,
      bag_index:,
      client_cast_id: 1,
      target: unit_of(connection: 2),
    )
  let assert [press] = scene.deliverable(scene: with_the_press)
    as "the press is the one message in flight"
  scene.deliver(scene: with_the_press, mail: press)
}

/// The number of times the id is in the ids.
fn count(ids ids: List(Int), id id: Int) -> Int {
  list.count(ids, fn(found) { found == id })
}

/// Whether a cast frame that starts a cast follows one that finishes a cast.
fn starts_after_a_finish(ids ids: List(Int)) -> Bool {
  case list.drop_while(ids, fn(id) { id != 0x07FE }) {
    [] -> False
    [_, ..after] -> list.contains(after, 0x07FF)
  }
}

pub fn an_ally_start_is_taken_after_its_casters_start_at_every_viewer_in_every_legal_order_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  // C's start of the cast (to V through the map), its change tell and its went tell to T
  // (through the map), and T's start of the cast it holds (HeldCastStarted, through the map)
  // are in flight together after C's go.
  let scenes = scene.orders(scene: pressed(world:, bag_index:))
  assert scenes != [] as "the scene has an order"
  list.each(scenes, fn(done) {
    assert scene.cast_frames(scene: done, connection: 3) == armor_frames
      as "V is written the casts' starts and goes once, in every order: the caster's start is first and the ally's start is dropped"
    assert scene.direct_news(scene: done, from: 1, to: 3) == []
      && scene.direct_news(scene: done, from: 2, to: 3) == []
      as "neither C nor T tells V anything itself: the cast news is the map's"
  })
}

/// The casts the 0x262 of the unit `unit_id` lists, as the connection was written it last.
fn listed_casts(
  scene scene: scene.Scene,
  connection connection: Int,
  unit_id unit_id: Int,
) -> List(Int) {
  list.fold(scene.frames_of(scene:, connection:), [], fn(listed, frame) {
    case frame.message_id {
      0x0262 ->
        case unit_create_player.decode(frame.body) {
          Ok(created) if created.unit_id == unit_id ->
            list.map(created.tail.casts, fn(cast) { cast.cast_id })
          _ -> listed
        }
      _ -> listed
    }
  })
}

pub fn a_viewer_that_arrives_mid_cast_holds_the_live_casts_from_its_create_and_one_whose_create_listed_none_is_written_nothing_for_them_in_every_legal_order_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  // Another viewer W (connection 4) comes into sight before the press, after the press and
  // after the casts' nodes ended. The entry mid-cast is walked in every order: W's join, the
  // owners' snapshots and the map's relays reach W in each order the BEAM allows.
  let enters = fn(world: scene.Scene) {
    scene.enter(
      scene: world,
      connection: 4,
      class_id: medic,
      level: 1,
      place: scene.at(x: 500.0),
    )
  }
  let before =
    scene.settle(scene: pressed(
      world: scene.settle(scene: enters(world)),
      bag_index:,
    ))
  let held = scene.settle(scene: pressed(world:, bag_index:))
  let mid_cast = scene.orders(scene: enters(held))
  let ended =
    scene.settle(
      scene: enters(
        scene.settle(scene: scene.fire_timers(scene: held, within_ms: 12_000)),
      ),
    )
  assert scene.cast_frames(scene: before, connection: 4) == armor_frames
    as "a viewer that was in sight before the press is written the casts' starts and goes"
  assert mid_cast != [] as "the entry has an order"
  list.each(mid_cast, fn(done) {
    assert listed_casts(
        scene: done,
        connection: 4,
        unit_id: unit_of(connection: 2),
      )
      != []
      as "a viewer that arrived while T holds the casts has them listed by T's create, in every order"
    assert scene.cast_frames(scene: done, connection: 4) == []
      as "and is written no start of them, in every order: it holds them from the create"
  })
  assert listed_casts(
      scene: ended,
      connection: 4,
      unit_id: unit_of(connection: 2),
    )
    == []
    as "a viewer that arrived after the casts ended is listed none"
  assert scene.cast_frames(scene: ended, connection: 4) == []
    as "and is written nothing of them"
  list.each([before, ended, ..mid_cast], fn(done) {
    assert scene.direct_news(scene: done, from: 1, to: 4) == []
      && scene.direct_news(scene: done, from: 2, to: 4) == []
      as "neither C nor T told the viewer anything itself"
  })
}

pub fn a_caster_that_dies_between_its_go_and_the_allys_start_writes_its_own_client_nothing_of_it_and_another_viewer_the_start_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  // C is struck dead by a creature as its go is taken: its own client is written no start
  // of the cast it already holds, whichever of its death and T's start it takes first.
  let gone = pressed(world:, bag_index:)
  let casts = scene.started_cast_ids(scene: gone, connection: 1)
  assert casts != [] as "C's own go wrote the start of each of its casts"
  let own = scene.cast_frames_of(scene: gone, connection: 1, cast_ids: casts)
  let dying =
    scene.connection_is_told(
      scene: gone,
      connection: 1,
      event: connection_support.foe(
        strike_tell.Attacks(
          tell: strike_tell.Strike(
            key: strike_tell.Key(
              cast_id: 2_147_500_001,
              occasion: strike_tell.AtGo(phase: 0),
              unit_id: unit_of(connection: 1),
            ),
            from: connection_support.fighter(),
            striker: spawn_support.beast_striker(),
            offence: spawn_support.dealing(
              offence: spawn_support.beast_attack().offence,
              damage: 100_000,
            ),
            controls: [],
            gates: [],
          ),
        ),
      ),
      name: "a killing strike on C",
    )
  let wrote_no_more_of_its_casts = fn(done: scene.Scene) {
    let after_its_go =
      list.drop(
        scene.cast_frames_of(scene: done, connection: 1, cast_ids: casts),
        list.length(own),
      )
    assert list.filter(after_its_go, fn(id) { id != 0x07FE }) == []
      as "C's own client is written no 0x7ff, 0x7f4 or 0x811 of its own casts after its go: the finish is all T's start could not turn into a restart"
    assert count(ids: scene.cast_frames(scene: done, connection: 3), id: 0x07FF)
      >= 1
      as "another viewer is written the start (positive control)"
    assert scene.direct_news(scene: done, from: 2, to: 1) == []
      as "T told C nothing itself"
  }
  wrote_no_more_of_its_casts(scene.settle(scene: dying))
  list.each(scene.orders(scene: dying), wrote_no_more_of_its_casts)
}

pub fn a_cast_finished_at_a_viewer_before_the_allys_start_through_the_maps_relays_is_written_the_finish_and_no_start_in_both_orders_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  // T moves to 1030, out of C's sight (1030 from it) and still in V's (30 from it), as C's go
  // is taken, which finishes C's casts on it: C's finish and T's start of the casts it held
  // both reach V through the map, in any legal order. (Out of V's sight too, T's start could
  // never reach V and the order this test is about could not occur.)
  let leaving =
    scene.map_is_told(
      scene: pressed(world:, bag_index:),
      from: scene.FromConnection(2),
      event: step.OwnEvent(
        step.Told(message: map.Moved(
          connection: ConnectionId(2),
          place: scene.at(x: 1030.0),
          seq: 1,
        )),
      ),
      name: "T moves out of C's sight",
    )
  let judged = fn(done: scene.Scene) {
    let frames = scene.cast_frames(scene: done, connection: 3)
    assert list.contains(frames, 0x07FE) || list.contains(frames, 0x0811)
      as "V is written the end of the cast, whichever of C's finish and T's start it took first: C's 0x7fe, or T's 0x811 when V holds the cast from T's start"
    assert !starts_after_a_finish(ids: frames)
      as "a start after a finish is dropped: V is written no start of a cast it was written the finish of"
    assert scene.check(scene: done, connection: 3) == Ok(Nil)
      as "no frame of T after its 0x355"
    assert scene.direct_news(scene: done, from: 1, to: 3) == []
      && scene.direct_news(scene: done, from: 2, to: 3) == []
      as "neither C nor T told V anything itself"
  }
  judged(scene.settle(scene: leaving))
  let scenes = scene.orders(scene: leaving)
  list.each(scenes, judged)
  let both_taken =
    list.filter_map(scenes, fn(done) {
      case
        took(scene: done, connection: 3, part: "0x7fe of 1"),
        took(scene: done, connection: 3, part: "held start")
      {
        [finish, ..], [start, ..] -> Ok(finish < start)
        _, _ -> Error(Nil)
      }
    })
  assert list.contains(both_taken, True) && list.contains(both_taken, False)
    as "both orders occur: V takes C's finish before T's start in some orders and after it in others"
}

/// The places, in the order the connection took its messages, of the messages whose name
/// holds `part`.
fn took(
  scene scene: scene.Scene,
  connection connection: Int,
  part part: String,
) -> List(Int) {
  order_explorer.order_at(
    taken: scene.taken,
    receiver: scene.ConnectionProcess(connection),
  )
  |> list.index_map(fn(name, index) { #(name, index) })
  |> list.filter_map(fn(named) {
    case string.contains(named.0, part) {
      True -> Ok(named.1)
      False -> Error(Nil)
    }
  })
}

pub fn a_viewer_that_leaves_the_casters_sight_between_its_go_and_the_allys_start_borrows_the_cast_on_the_ally_in_both_orders_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  // V moves to 1030, out of C's sight (1030 from it) and still in T's (1010 from it), as C's
  // go is taken: the map's unseen of C at V and T's start of each of the two casts reach V
  // in either order, and then the casts' nodes end on T.
  let leaving =
    scene.map_is_told(
      scene: pressed(world:, bag_index:),
      from: scene.FromConnection(3),
      event: step.OwnEvent(
        step.Told(message: map.Moved(
          connection: ConnectionId(3),
          place: scene.at(x: 1030.0),
          seq: 1,
        )),
      ),
      name: "V moves out of C's sight",
    )
  let ended_of = fn(done) {
    scene.settle(scene: scene.fire_timers(scene: done, within_ms: 12_000))
  }
  let judged =
    list.map(scene.orders(scene: leaving), fn(done) {
      let ended = ended_of(done)
      assert scene.check(scene: ended, connection: 3) == Ok(Nil)
        as "no frame of C after its 0x355"
      assert scene.direct_news(scene: ended, from: 1, to: 3) == []
        && scene.direct_news(scene: ended, from: 2, to: 3) == []
        as "neither C nor T told V anything itself"
      let unseen = took(scene: done, connection: 3, part: "PlayerUnseen")
      let held_starts = took(scene: done, connection: 3, part: "held start")
      let casters_starts = took(scene: done, connection: 3, part: "0x7ff of 1")
      #(
        scene.cast_frames(scene: ended, connection: 3),
        unseen,
        held_starts,
        casters_starts,
      )
    })
  // (a) The unseen of C comes before C's start and before T's starts: V holds no cast of C,
  // so each of T's starts borrows the cast on T (`cast.unknown_caster`), and T's end of each
  // writes 0x811 naming T: the frames a viewer that comes into sight after the go is written.
  let unseen_first =
    list.filter(judged, fn(one) {
      let #(_, unseen, held_starts, casters_starts) = one
      let assert [unseen_at] = unseen
      list.all(list.append(held_starts, casters_starts), fn(at) {
        at > unseen_at
      })
    })
  assert unseen_first != [] as "the unseen comes first in some orders"
  assert list.all(unseen_first, fn(one) {
    one.0 == [0x07FF, 0x07F4, 0x07FF, 0x07F4, 0x0811, 0x0811]
  })
    as "V is written each cast's 0x7ff and 0x7f4 on T, and T's 0x811 {X, [T]} for each when its node ends"
  // (b) C's start and T's start of each cast come, in that order, before the unseen: V holds
  // both casts as written by C when T's starts arrive, so they are dropped, and the unseen
  // finishes them.
  let starts_first =
    list.filter(judged, fn(one) {
      let #(_, unseen, held_starts, casters_starts) = one
      let assert [unseen_at] = unseen
      list.all(list.append(held_starts, casters_starts), fn(at) {
        at < unseen_at
      })
      && list.length(casters_starts) == 2
      && list.length(held_starts) == 2
      && list.all(list.zip(casters_starts, held_starts), fn(pair) {
        pair.0 < pair.1
      })
    })
  assert starts_first != [] as "the starts come first in some orders"
  assert list.all(starts_first, fn(one) {
    count(ids: one.0, id: 0x07FF) == 2 && count(ids: one.0, id: 0x0811) == 0
  })
    as "T's starts are dropped as V holds the casts from C, and nothing of them follows the unseen"
}

pub fn a_snapshot_built_before_a_casters_disappearance_lists_its_held_cast_and_one_built_after_does_not_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  let held = scene.settle(scene: pressed(world:, bag_index:))
  let ends = fn(world: scene.Scene) {
    scene.map_is_told(
      scene: world,
      from: scene.FromConnection(1),
      event: step.WatchEnded(step.WatchId(1)),
      name: "C's connection ends",
    )
  }
  // W stands 1040 from C (out of its sight, which is 1024) and 1020 from T (in T's): W takes
  // one snapshot that lists the cast, T's, so the cast can only be borrowed.
  let enters = fn(world: scene.Scene) {
    scene.enter(
      scene: world,
      connection: 4,
      class_id: medic,
      level: 1,
      place: scene.at(x: 1040.0),
    )
  }
  // The map takes C's end first: the viewer's snapshot of T is built after it.
  let gone_first = scene.settle(scene: enters(scene.settle(scene: ends(held))))
  assert listed_casts(
      scene: gone_first,
      connection: 4,
      unit_id: unit_of(connection: 2),
    )
    == []
    as "a snapshot built after the caster's disappearance lists no cast of it: the 0x262 holds none"
  assert scene.cast_frames(scene: gone_first, connection: 4) == []
    as "and no frame of the cast is written"
  // The viewer joins first: its snapshot of T is built while T holds the casts.
  let seen_first = scene.settle(scene: ends(scene.settle(scene: enters(held))))
  assert listed_casts(
      scene: seen_first,
      connection: 4,
      unit_id: unit_of(connection: 2),
    )
    != []
    as "a snapshot built while T holds the casts lists them, borrowed: no 0x7ff is written for them"
  assert scene.cast_frames(scene: seen_first, connection: 4) == [0x0811, 0x0811]
    as "and the casts end with C's disappearance: T's 0x811 for each, naming T"
}

pub fn the_other_player_that_shows_a_player_who_joins_again_is_written_its_0x355_then_its_new_0x262_and_its_heals_reach_the_new_stay_test() -> Nil {
  use <- owned_test.run(10_000)
  let settled = two_players()
  let assert Some(map.Relation(generation: first, ..)) =
    relation(scene: settled)
    as "the map holds the sight V has of C"
  // C's connection joins the map again, in its second stay: the map ends each pair and
  // begins it again.
  let again =
    scene.join_again(
      scene: settled,
      connection: 1,
      stay: map_support.stay(count: 2),
      place: scene.at(x: 1000.0),
    )
  let assert Some(map.Relation(generation: second, stay: viewer_stay, ..)) =
    relation(scene: again)
    as "the map holds a new sight of C for V"
  assert generation.compare(second, first) == order.Gt
    as "the new sight is a new generation"
  assert viewer_stay == map_support.stay(count: 1)
    as "V is in the stay it was in"
  // C's own new connection state answers the new sight's SeenBy with its snapshot; here the
  // map is told the snapshot for the new stay as C's connection tells it.
  let told =
    scene.map_is_told(
      scene: again,
      from: scene.FromConnection(1),
      event: step.OwnEvent(
        step.Told(
          message: map.PlayerSnapshot(
            by: ConnectionId(1),
            stay: map_support.stay(count: 2),
            viewer: ConnectionId(2),
            generation: second,
            burst: [
              PeerNews(
                unit_id: 1,
                news: Appeared(
                  unit: UnitCreatePlayer(
                    ..connection_support.another_unit(),
                    unit_id: 1,
                  ),
                  generation: second,
                ),
              ),
            ],
          ),
        ),
      ),
      name: "C's snapshot of the new sight",
    )
  let done = scene.settle(scene: told)
  assert list.drop(written_for_c(scene: done), 1) == ["0x355(1)", "0x262(1)"]
    as "V is written C's 0x355 and then its new 0x262: the shown unit is removed and created again, not kept under the earlier address"
  assert scene.direct_news(scene: done, from: 1, to: 2) == []
    as "C told V nothing itself"
}

/// The moves the connection `from` has told the connection `to` so far (`TellMove`).
fn moves_told(scene scene: scene.Scene, from from: Int, to to: Int) -> Int {
  list.count(scene.taken, fn(taken) {
    case taken {
      order_explorer.Taken(
        by: scene.ConnectionProcess(receiver),
        from: scene.FromConnection(sender),
        name:,
      ) -> receiver == to && sender == from && string.contains(name, "TellMove")
      order_explorer.Taken(..) -> False
    }
  })
}

pub fn an_unseen_ends_a_real_cast_the_departed_ally_is_relayed_nothing_after_it_and_a_remaining_control_viewer_writes_the_finish_from_its_ledger_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  // C's Phantasmal Armor holds its node on T alone; T leaves C's sight (and V's), which
  // ends the casts on it. V, the control viewer, stays in C's sight.
  let held = scene.settle(scene: pressed(world:, bag_index:))
  let leaving =
    scene.map_is_told(
      scene: held,
      from: scene.FromConnection(2),
      event: step.OwnEvent(
        step.Told(message: map.Moved(
          connection: ConnectionId(2),
          place: scene.at(x: 3000.0),
          seq: 1,
        )),
      ),
      name: "T moves out of C's sight",
    )
  list.each(scene.orders(scene: leaving), fn(done) {
    assert scene.check(scene: done, connection: 2) == Ok(Nil)
      as "the departed ally is relayed nothing of C after its 0x355"
    assert scene.cast_frames(scene: done, connection: 3)
      |> list.contains(0x07FE)
      as "the control viewer that stays is relayed the finish and writes it from its ledger"
    assert scene.direct_news(scene: done, from: 1, to: 3) == []
      && scene.direct_news(scene: done, from: 1, to: 2) == []
      as "C told neither viewer anything itself: the finish is the map's"
    // C's next move goes, from its copy, to the viewers it still has and not to T.
    let moving =
      scene.settle(scene: scene.client_sends(
        scene: done,
        connection: 1,
        bytes: connection_support.a_move(1.5),
        name: "0x637 of C",
      ))
    assert moves_told(scene: moving, from: 1, to: 3)
      == moves_told(scene: done, from: 1, to: 3) + 1
      as "C's next move reaches the control viewer"
    assert moves_told(scene: moving, from: 1, to: 2)
      == moves_told(scene: done, from: 1, to: 2)
      as "and not the ally that left: its sight left C's copy at the map's notice"
  })
}

pub fn a_players_line_is_relayed_to_its_relaying_viewers_with_their_stay_and_before_the_snapshot_a_viewer_is_told_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let line = connection_support.chat_line_message(4, "Hello")
  // After V's snapshot: C's Say reaches V through the map, as a line for V's stay.
  let told =
    scene.settle(scene: scene.client_sends(
      scene: two_players(),
      connection: 1,
      bytes: line,
      name: "Say by C",
    ))
  let lines = fn(done: scene.Scene, connection: Int) {
    list.count(scene.frames_of(scene: done, connection:), fn(frame) {
      frame.message_id == 0x01C8
    })
  }
  assert lines(told, 2) == 1
    as "a line of C is written to a viewer whose relation relays"
  assert scene.direct_news(scene: told, from: 1, to: 2) == []
    as "C told V nothing itself: the map relayed the line as one for V's stay"
  // Before a viewer's snapshot: a third player W enters and C speaks before W has taken the
  // snapshot of C; whichever order the messages are taken in, W is written no line before
  // C's 0x262.
  let entering =
    scene.client_sends(
      scene: scene.enter(
        scene: two_players(),
        connection: 3,
        class_id: medic,
        level: 1,
        place: scene.at(x: 500.0),
      ),
      connection: 1,
      bytes: line,
      name: "Say by C",
    )
  list.each(scene.orders(scene: entering), fn(done) {
    let frames = scene.frames_of(scene: done, connection: 3)
    let shown_at =
      list.index_fold(frames, None, fn(found, frame, index) {
        case found, frame.message_id, legal_order_support.unit_of(frame:) {
          None, 0x0262, Some(1) -> Some(index)
          _, _, _ -> found
        }
      })
    let line_at =
      list.index_fold(frames, None, fn(found, frame, index) {
        case found, frame.message_id {
          None, 0x01C8 -> Some(index)
          _, _ -> found
        }
      })
    assert case shown_at, line_at {
      Some(shown), Some(spoken) -> shown < spoken
      _, None -> True
      None, Some(_) -> False
    }
      as "a viewer is written a line only after C's 0x262: before its snapshot the map relays it nothing"
    assert scene.direct_news(scene: done, from: 1, to: 3) == []
      as "C told W nothing itself"
  })
}

pub fn at_the_ally_a_change_start_then_the_casters_unseen_ends_or_keeps_it_by_its_flag_and_the_unseen_first_refuses_the_start_test() -> Nil {
  use <- owned_test.run(10_000)
  // C (connection 1) holds an absorb pool on T (connection 2) from its cast 100: a start
  // tell, and C's move out of T's sight, which the map takes in the order C sent them.
  let settled = two_players()
  let source = Source(cast_id: 100, effect_id: Spell4EffectsId(62_024))
  let start = fn(sight: held_changes.Sight) {
    relay.ChangeStart(change: held_changes.PlayerChangeStarts(
      from: ConnectionId(1),
      from_stay: map_support.stay(count: 1),
      source:,
      change: held_changes.Applies(held_changes.Absorb(amount: 300, mask: 7)),
      sight:,
      spell4_id: Spell4Id(54_806),
      effect: HeldEffect(
        effect_id: Spell4EffectsId(62_024),
        starts_ms: 1000,
        ends: EndsAt(ms: 11_000),
      ),
    ))
  }
  let tells_the_start = fn(world: scene.Scene, sight) {
    scene.map_is_told(
      scene: world,
      from: scene.FromConnection(1),
      event: step.OwnEvent(
        step.Told(message: map.TellLanding(
          from: ConnectionId(1),
          stay: map_support.stay(count: 1),
          to: ConnectionId(2),
          to_stay: map_support.stay(count: 1),
          landing: start(sight),
        )),
      ),
      name: "C's start of its change on T",
    )
  }
  let moves_away = fn(world: scene.Scene) {
    scene.tells_the_map_it_moved(
      scene: world,
      connection: 1,
      place: scene.at(x: 3000.0),
      seq: 1,
    )
  }
  let absorptions = fn(done: scene.Scene) {
    list.count(scene.frames_of(scene: done, connection: 2), fn(frame) {
      frame.message_id == 0x0938
    })
    - list.count(scene.frames_of(scene: settled, connection: 2), fn(frame) {
      frame.message_id == 0x0938
    })
  }
  let rows = [
    #(
      "a start of a change that ends with C's sight, then C's unseen: the pool is put on and taken off",
      scene.settle(
        scene: moves_away(tells_the_start(settled, held_changes.EndsWhenUnseen)),
      ),
      2,
    ),
    #(
      "a start of a change of a spell with propertyFlags 0x100, then C's unseen: the pool stays",
      scene.settle(
        scene: moves_away(tells_the_start(settled, held_changes.KeptWhenUnseen)),
      ),
      1,
    ),
    #(
      "C's unseen first, then its start: T takes a change only from a caster it sees, so the start is refused",
      scene.settle(scene: tells_the_start(
        moves_away(settled),
        held_changes.EndsWhenUnseen,
      )),
      0,
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, done, writes) = row
    assert absorptions(done) == writes as reason
    assert scene.direct_news(scene: done, from: 1, to: 2) == []
      as { reason <> ": C told T nothing itself" }
  })
}

pub fn a_heal_the_map_accepted_before_its_caster_left_sight_is_applied_and_one_for_a_stay_the_player_left_after_the_map_accepted_it_is_dropped_at_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let settled = two_players()
  let heal =
    strike_support.heal_strike(
      from: ConnectionId(1),
      stay: map_support.stay(count: 1),
      cast_id: 100,
      unit_id: unit_of(connection: 2),
      outgoing: 1.0,
      heals: [#(effect_kind.Health, 10)],
    )
  // C's heal reaches the map and then C's move out of T's sight: the heal is taken and
  // answered whichever comes first at T.
  let sent =
    scene.map_is_told(
      scene: settled,
      from: scene.FromConnection(1),
      event: step.OwnEvent(
        step.Told(message: map.TellLanding(
          from: ConnectionId(1),
          stay: map_support.stay(count: 1),
          to: ConnectionId(2),
          to_stay: map_support.stay(count: 1),
          landing: relay.HealStrike(strike: heal),
        )),
      ),
      name: "C's heal of T",
    )
  list.each(
    scene.orders(scene: scene.tells_the_map_it_moved(
      scene: sent,
      connection: 1,
      place: scene.at(x: 3000.0),
      seq: 1,
    )),
    fn(done) {
      assert list.any(done.taken, fn(taken) {
        string.contains(taken.name, "tell of 2 to the map: TellLanding")
      })
        as "T took the heal the map accepted and answered it through the map, though C left its sight"
      assert scene.direct_news(scene: done, from: 2, to: 1) == []
        as "T told C nothing itself: the answer is the map's"
    },
  )
  // A heal for a stay T is no longer in is dropped at its connection: nothing is told.
  let #(_, taken) =
    connection_support.feed(
      state: scene.connection_state(scene: settled, connection: 2),
      event: connection_support.for_stay(
        stay: map_support.stay(count: 0),
        sent: client_connection.SentByPlayer(tell: client_connection.Strike(
          strike: heal,
        )),
      ),
    )
  assert connection_support.tells(taken) == []
    as "a heal told for an earlier stay is dropped at the connection: no answer, no news"
}

pub fn the_explorer_matches_the_full_walk_on_every_scene_small_enough_to_walk_in_full_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- with_the_armor
  let #(world, bag_index) = armor_world(tables:)
  // The scenes of the move that takes a viewer out of sight (34 states at the shape) and of
  // the ally's start (1,175 states there): each walked in full and reduced.
  let rows = [
    #("a move out of sight", c_moves_out_of_v_sight()),
    #("the ally's start", pressed(world:, bag_index:)),
  ]
  list.each(rows, fn(row) {
    let #(name, start) = row
    let outcomes = fn(scenes: List(scene.Scene)) {
      list.map(scenes, fn(done) { order_explorer.outcome(taken: done.taken) })
    }
    let reduced = outcomes(scene.orders(scene: start))
    let full = outcomes(scene.orders_in_full(scene: start))
    assert set.from_list(reduced) == set.from_list(full)
      as {
        name
        <> ": the reduced walk reaches the outcomes of the full walk, and no other"
      }
    assert list.length(reduced) == set.size(set.from_list(reduced))
      as { name <> ": the reduced walk reaches each outcome once" }
  })
}

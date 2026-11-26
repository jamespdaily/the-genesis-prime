//// What a viewer of a creature is written in every order the BEAM may deliver the map's,
//// the creature's and the viewer's messages (`legal_order_support`). Expected values come
//// from these places.
//// - The relation protocol of the map (the doc comment of `genesis_prime/world_map/map`):
////   the map relays a creature's news to a viewer only after it relayed that viewer's
////   snapshot of the generation it holds, and tells the viewer `Unseen` when the pair leaves
////   sight, so a viewer has one sender for a creature and writes nothing for a unit after
////   its 0x355.
//// - The client's rules, which the invariants name: a unit is created once, removed once,
////   and told nothing before its 0x262 or after its 0x355 (`opcode.0x262`, `opcode.0x355`).
//// - The creature's rule: its snapshot is built from its state when it takes `Seen`, and its
////   health after a strike is 52 less the strike's damage (the Battle Beast's 52 health,
////   `spawn_support`).

import exception
import game_connection_support
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_news.{CreatureAppeared, Removed}
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/step.{
  Asked, CallerId, Connection, ConnectionId, OwnEvent, ServiceTimerFired,
  TimerId, Told,
}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/generation
import genesis_prime/world_map/map
import genesis_prime/world_map/relay
import genesis_prime/world_map/spawn.{type Spawn}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import legal_order_support.{
  type Mail, type Scene, type Violation, CreatureProcess, FromCaster,
  FromConnection, FromTimer, MapProcess, NoFrameAfterRemoval, ToCreature, ToMap,
  Violation,
}
import map_spawn_support as spawns
import map_support
import order_explorer
import owned_test
import world_watch_support

/// The unit id the Battle Beast has in these scenes: the first player's is 1 and the
/// creature's, started for it, the next.
const beast_unit = 2

/// The first player, a connection of its own; the messages sent to it are not read.
const first_player = 2

/// The viewer's connection, the one `game_connection_support.in_world` holds.
const viewer = 1

fn beast() -> Spawn {
  legal_order_support.the_beast()
}

/// The Battle Beast, started for the first player, its first snapshot taken by the map: a
/// map with the creature live and its first player relaying, and the viewer's connection in
/// the world, which has not seen the creature.
fn standing() -> Scene {
  let #(map_state, joined) =
    spawns.join(
      state: spawns.started_with_spawns(spawns: [beast()]),
      at_ms: 6000,
      connection: first_player,
      x: 0.0,
    )
  let assert [#(_, start)] = spawns.starts(joined)
    as "the first player's join starts the creature"
  let #(state, started) =
    legal_order_support.creature_started(start:, spawn: beast(), at_ms: 6000)
  let settled =
    legal_order_support.settle(legal_order_support.scene(
      map: map_state,
      creature: state,
      viewer: game_connection_support.in_world(),
      mail: list.append(
        legal_order_support.mail_of_the_map(joined),
        legal_order_support.mail_of_the_creature(started),
      ),
    ))
  legal_order_support.Scene(..settled, taken: [])
}

/// The scene after the viewer's player joins the map at the creature's place: the map's
/// step taken, and what it sent in the mail.
fn joined(scene scene: Scene) -> Scene {
  let #(state, taken) =
    spawns.join(state: scene.map, at_ms: 7000, connection: viewer, x: 0.0)
  legal_order_support.Scene(
    ..scene,
    map: state,
    mail: list.append(scene.mail, legal_order_support.mail_of_the_map(taken)),
  )
}

/// A strike of `damage` on the Beast, told to the map by the first player's connection
/// (`FromCaster`), as that connection tells it: the strike names the connection and its first stay as its
/// striker.
fn strike(damage damage: Int) -> Mail {
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id: beast_unit,
      damage_type: 3,
      damage:,
      cast_id: 1,
      occasion: strike_tell.AtGo(phase: 0),
    )
  order_explorer.Mail(
    to: MapProcess,
    from: FromCaster,
    input: ToMap(
      OwnEvent(
        Told(map.TellCreature(
          from: ConnectionId(first_player),
          stay: map_support.stay(count: 1),
          unit_id: beast_unit,
          life: spawns.creature_of(state: standing().map, spawn: 1).1,
          payload: relay.Strike(
            tell: strike_tell.Strike(
              ..tell,
              from: Connection(ConnectionId(first_player)),
            ),
          ),
        )),
      ),
    ),
    name: "Strike",
  )
}

/// The viewer's player joins the map at the creature's place, as the viewer's connection asks
/// it: the map takes the join in its own turn, among what the first player's connection tells
/// it, and sends the creature its `Seen`.
fn viewer_joins() -> Mail {
  order_explorer.Mail(
    to: MapProcess,
    from: FromConnection,
    input: ToMap(
      OwnEvent(Asked(
        caller: CallerId(viewer),
        message: map.Join(
          connection: ConnectionId(viewer),
          character: map_support.character(100 + viewer),
          place: spawns.at(0.0),
          stay: map_support.stay(count: 1),
          alive: True,
          hidden: set.new(),
        ),
      )),
    ),
    name: "Join",
  )
}

/// The viewer's connection moves out of sight of the creature, or back, as its connection
/// tells the map.
fn moves(x x: Float, seq seq: Int, name name: String) -> Mail {
  order_explorer.Mail(
    to: MapProcess,
    from: FromConnection,
    input: ToMap(
      OwnEvent(
        Told(map.Moved(
          connection: ConnectionId(viewer),
          place: spawns.at(x),
          seq:,
        )),
      ),
    ),
    name:,
  )
}

/// The corpse timer of the creature fires.
fn corpse_timer() -> Mail {
  order_explorer.Mail(
    to: CreatureProcess,
    from: FromTimer,
    input: ToCreature(OwnEvent(ServiceTimerFired(TimerId(1)))),
    name: "Corpse timer",
  )
}

/// Each scene a legal order ends in, with the invariants it breaks, which a test of an
/// order that is right has none of.
fn broken_in_each_order(scene scene: Scene) -> List(Violation) {
  list.filter_map(legal_order_support.orders(scene:), fn(ended) {
    case legal_order_support.check(scene: ended) {
      Ok(Nil) -> Error(Nil)
      Error(violation) -> Ok(violation)
    }
  })
}

fn frame_of(message_id: Int, body: Result(BitArray, a)) -> Frame {
  let assert Ok(body) = body as "the planted message encodes"
  Frame(message_id:, body:)
}

pub fn legal_order_support_catches_a_frame_written_for_a_unit_after_its_removal_test() -> Nil {
  use <- owned_test.run(5000)
  let created =
    frame_of(
      0x0262,
      unit_create_creature.encode(creature_unit.create(
        spawn: beast(),
        unit_id: 7,
        health: 52,
        interrupt_armor: None,
        server_time_estimate_start: 0,
      )),
    )
  let removed =
    frame_of(
      0x0355,
      unit_destroyed.encode(UnitDestroyed(
        unit_id: 7,
        chest_world_object_delay: 0,
      )),
    )
  let moved =
    frame_of(
      0x0638,
      unit_movement.encode(
        UnitMovement(
          unit_id: 7,
          server_time: 0,
          reset_movement: 0,
          kept: 0,
          commands: [],
        ),
      ),
    )
  assert legal_order_support.check_frames(frames: [created, removed, moved])
    == Error(Violation(invariant: NoFrameAfterRemoval, at_frame: 2, unit_id: 7))
    as "a planted viewer that writes a 0x638 for the unit after its 0x355 breaks the invariant, at that frame"
  // The same three messages to the real viewer.
  let #(shown, taken) =
    game_connection_support.feed(
      state: game_connection_support.in_world(),
      event: game_connection_support.sent_by_a_peer(
        game_connection_support.news_of(
          unit_id: 7,
          news: CreatureAppeared(
            spawn_id: beast().id,
            unit_type: beast().unit_type,
            unit: creature_unit.create(
              spawn: beast(),
              unit_id: 7,
              health: 52,
              interrupt_armor: None,
              server_time_estimate_start: 0,
            ),
            life: 3,
            place: beast().place,
            hit_radius: beast().combat.hit_radius,
            attackable: beast().combat.attackable,
            hostile_to: beast().combat.hostile_to,
            fights: beast().combat.fights,
          ),
        ),
      ),
    )
  let #(removed_state, removal) =
    game_connection_support.feed(
      state: shown,
      event: game_connection_support.sent_by_a_peer(
        game_connection_support.news_of(unit_id: 7, news: Removed),
      ),
    )
  let #(_, late) =
    game_connection_support.feed(
      state: removed_state,
      event: game_connection_support.sent_by_a_mover(
        game_connection_support.moving(
          unit_id: 7,
          server_time_ms: 0,
          commands: [],
          generation: generation.first(),
        ),
      ),
    )
  let frames =
    list.flat_map([taken, removal, late], fn(step) {
      game_connection_support.heard(step, game_connection_support.keyed())
    })
  assert legal_order_support.names(frames:) == ["0x262(7)", "0x355(7)"]
    as "the real viewer writes the creation and the removal and drops the move of a unit it no longer shows"
  assert legal_order_support.check_frames(frames:) == Ok(Nil)
    as "so the same scene with the real viewer passes"
}

pub fn news_before_a_snapshot_and_a_snapshot_of_an_earlier_generation_are_dropped_in_every_legal_order_test() -> Nil {
  use <- owned_test.run(10_000)
  // (a) and (b): the first player's strike and the viewer's join reach the map from two
  // connections, in either order; the map tells the creature a strike and a `Seen` in the
  // order it took them.
  let arriving =
    legal_order_support.with_mail(standing(), [
      viewer_joins(),
      strike(damage: 14),
    ])
  let strike_first = fn(ended: Scene) {
    legal_order_support.order_at(scene: ended, receiver: CreatureProcess)
    == ["Strike", "Seen"]
  }
  let ended = legal_order_support.orders(scene: arriving)
  assert broken_in_each_order(scene: arriving) == []
    as "(a) and (b): no order breaks an invariant"
  let #(first, second) = list.partition(ended, strike_first)
  assert first != [] && second != []
    as "both orders of the map's two senders are legal"
  // The strike pulls the creature, which chases its caster: its path (0x638) follows the
  // health in the news and is in the snapshot's burst when the strike came first.
  assert list.all(first, fn(scene) {
    legal_order_support.names(frames: scene.frames) == ["0x262(2)", "0x638(2)"]
    && legal_order_support.health_shown(frames: scene.frames, unit_id: 2)
    == Some(38)
  })
    as "(a) the strike first: its news reaches the map before the snapshot and is dropped (no 0x937 is written), and the snapshot, built after the strike, shows the health it left and the path it runs"
  assert list.all(second, fn(scene) {
    legal_order_support.names(frames: scene.frames)
    == ["0x262(2)", "0x937(2)", "0x638(2)"]
    && legal_order_support.health_shown(frames: scene.frames, unit_id: 2)
    == Some(38)
  })
    as "(b) the snapshot first, at full health, and then the news of the strike, both written in the order the map relayed them"
  // (c) `Seen(g)`, `Unseen`, `Seen(g')`, and a strike in between the snapshots.
  let leaving =
    legal_order_support.with_mail(standing(), [
      viewer_joins(),
      strike(damage: 14),
      moves(x: spawns.far, seq: 1, name: "Moved out"),
      moves(x: 0.0, seq: 2, name: "Moved in"),
    ])
  assert broken_in_each_order(scene: leaving) == []
    as "(c) no order breaks an invariant, which holds a snapshot of the earlier generation dropped wherever it falls among the viewer's moves"
  assert list.all(legal_order_support.orders(scene: leaving), fn(scene) {
    legal_order_support.health_shown(frames: scene.frames, unit_id: 2)
    == Some(38)
  })
    as "(c) the viewer ends showing the creature at the health it has, in every order: a snapshot of the earlier generation, built before the strike, is never the picture it keeps"
}

/// The health the scene's frames leave the viewer's client showing for the creature, as
/// text.
fn health_text(scene scene: Scene) -> String {
  case legal_order_support.health_shown(frames: scene.frames, unit_id: 2) {
    Some(health) -> "health " <> int.to_string(health)
    None -> "no creature"
  }
}

/// Where the first of `names` is among the map's takes, counted from 0: none when the map
/// took no such message.
fn position_of(
  names names: List(String),
  name name: String,
) -> Result(Int, Nil) {
  list.index_map(names, fn(taken, index) { #(taken, index) })
  |> list.find(fn(entry) { entry.0 == name })
  |> result.map(fn(entry) { entry.1 })
}

pub fn a_viewer_that_arrives_or_leaves_as_the_creature_expires_is_shown_one_picture_in_every_legal_order_test() -> Nil {
  use <- owned_test.run(10_000)
  // A creature that lies dead tells its map when its corpse timer fires: the removal of its
  // unit for every viewer, that it expired, and then its end, in the order of its one queue to
  // the map. The map starts the next life when it takes the end, so everything the first life
  // sent is taken before the second life's first send: a snapshot of the first life cannot
  // reach the map after the next life started, and the map's relations of the first life are
  // gone when it does.
  // (a) A viewer arrives as the corpse timer fires: the map's `Seen` and the timer reach the
  // creature in either order.
  let dead =
    legal_order_support.settle(
      legal_order_support.with_mail(standing(), [strike(damage: 60)]),
    )
  let arriving =
    legal_order_support.with_mail(
      joined(scene: legal_order_support.Scene(..dead, taken: [])),
      [
        corpse_timer(),
      ],
    )
  assert broken_in_each_order(scene: arriving) == []
    as "(a) no order breaks an invariant"
  let #(seen_first, timer_first) =
    list.partition(legal_order_support.orders(scene: arriving), fn(scene) {
      legal_order_support.order_at(scene:, receiver: CreatureProcess)
      == ["Seen", "Corpse timer"]
    })
  assert seen_first != [] && timer_first != []
    as "(a) both orders of the creature's two senders are legal"
  assert legal_order_support.deviations(
      scenes: seen_first,
      observed: fn(scene) {
        legal_order_support.names(frames: scene.frames)
        |> list.append([health_text(scene:)])
        |> list.append(legal_order_support.order_at(
          scene:,
          receiver: MapProcess,
        ))
      },
      wanted: fn(_) {
        [
          "0x262(2)",
          "0x355(2)",
          "0x262(2)",
          "health 52",
          "Snapshot for 1",
          "Broadcast",
          "Expired",
          "Creature ended",
          "Next Snapshot for 1",
          "Next Snapshot for 2",
        ]
      },
    )
    == []
    as "(a) the snapshot first: the viewer is shown the corpse, then its removal, then the next life's creation at full health, and the map takes every send of the first life before the end that starts the next"
  assert legal_order_support.deviations(
      scenes: timer_first,
      observed: fn(scene) {
        legal_order_support.names(frames: scene.frames)
        |> list.append([health_text(scene:)])
        |> list.append(legal_order_support.order_at(
          scene:,
          receiver: MapProcess,
        ))
      },
      wanted: fn(_) {
        [
          "0x262(2)",
          "health 52",
          "Broadcast",
          "Expired",
          "Creature ended",
          "Next Snapshot for 1",
          "Next Snapshot for 2",
        ]
      },
    )
    == []
    as "(a) the timer first: the creature stops and its Seen is lost, the removal is dropped for the viewer that awaits a snapshot, and the viewer is shown only the next life: never both lives' pictures at once"

  // (b) The viewer that is shown the corpse leaves sight as the corpse timer fires: the
  // connection's move and the creature's sends reach the map in any order.
  let shown = legal_order_support.settle(joined(scene: standing()))
  let corpse =
    legal_order_support.settle(
      legal_order_support.with_mail(
        legal_order_support.Scene(..shown, taken: []),
        [
          strike(damage: 60),
        ],
      ),
    )
  let before = legal_order_support.names(frames: corpse.frames)
  let leaving =
    legal_order_support.with_mail(
      legal_order_support.Scene(..corpse, taken: []),
      [
        moves(x: spawns.far, seq: 1, name: "Moved out"),
        corpse_timer(),
      ],
    )
  assert broken_in_each_order(scene: leaving) == []
    as "(b) no order breaks an invariant"
  let ended = legal_order_support.orders(scene: leaving)
  assert legal_order_support.deviations(
      scenes: ended,
      observed: fn(scene) { legal_order_support.names(frames: scene.frames) },
      wanted: fn(scene) {
        let map_takes =
          legal_order_support.order_at(scene:, receiver: MapProcess)
        // The viewer (connection 1) is shown the next life only when the map took its
        // snapshot before the move out of sight.
        let shown_again = case
          position_of(names: map_takes, name: "Moved out"),
          position_of(names: map_takes, name: "Next Snapshot for 1")
        {
          Ok(moved), Ok(snapshot) -> snapshot < moved
          Ok(_), Error(Nil) | Error(Nil), Ok(_) | Error(Nil), Error(Nil) ->
            False
        }
        list.append(before, case shown_again {
          True -> ["0x355(2)", "0x262(2)", "0x355(2)"]
          False -> ["0x355(2)"]
        })
      },
    )
    == []
    as "(b) the viewer is written one 0x355 for the corpse and, when the map relayed the next life's picture before it took the move, that creation and a second 0x355; nothing of the next life otherwise"
  assert list.any(ended, fn(scene) {
      list.length(legal_order_support.names(frames: scene.frames))
      == list.length(before) + 1
    })
    && list.any(ended, fn(scene) {
      list.length(legal_order_support.names(frames: scene.frames))
      == list.length(before) + 3
    })
    as "(b) both results are legal: the move before the next life's picture is relayed, and after"
}

pub fn legal_order_support_delivers_nothing_to_a_creature_that_stopped_test() -> Nil {
  use <- owned_test.run(10_000)
  // A process that has ended takes nothing (the header of `legal_order_support`): the
  // corpse timer stops the creature, and the map, still holding the spawn live until it
  // takes the creature's end, tells the creature `Unseen` for the viewer that moves out
  // of sight. That tell is lost, so the creature's last take is its timer in every order.
  let shown = legal_order_support.settle(joined(scene: standing()))
  let corpse =
    legal_order_support.settle(
      legal_order_support.with_mail(
        legal_order_support.Scene(..shown, taken: []),
        [
          strike(damage: 60),
        ],
      ),
    )
  let scene =
    legal_order_support.with_mail(
      legal_order_support.Scene(..corpse, taken: []),
      [
        moves(x: spawns.far, seq: 1, name: "Moved out"),
        corpse_timer(),
      ],
    )
  let ended = legal_order_support.orders(scene:)
  assert list.all(ended, fn(scene) {
    list.last(legal_order_support.order_at(scene:, receiver: CreatureProcess))
    == Ok("Corpse timer")
  })
    as "no order delivers anything to the creature after its timer stopped it"
  assert list.any(ended, fn(scene) {
    let map_takes = legal_order_support.order_at(scene:, receiver: MapProcess)
    let at = fn(name) {
      result.unwrap(position_of(names: map_takes, name:), or: -1)
    }
    legal_order_support.order_at(scene:, receiver: CreatureProcess)
    == ["Corpse timer"]
    && at("Moved out") < at("Expired")
  })
    as "the planted case is reached: the creature stopped, and the map, still live, takes the move and sends it an Unseen before it takes the creature's Expired"
}

pub fn an_unseen_and_the_creatures_news_write_nothing_after_the_unit_is_removed_in_every_legal_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let shown = legal_order_support.settle(joined(scene: standing()))
  assert legal_order_support.names(frames: shown.frames) == ["0x262(2)"]
    as "the viewer shows the creature before the orders start"
  let scene =
    legal_order_support.with_mail(
      legal_order_support.Scene(..shown, taken: []),
      [
        moves(x: spawns.far, seq: 1, name: "Moved out"),
        strike(damage: 14),
      ],
    )
  assert broken_in_each_order(scene:) == []
    as "no order writes a frame for the unit after its removal"
  let ended = legal_order_support.orders(scene:)
  let names =
    list.map(ended, fn(scene) {
      legal_order_support.names(frames: scene.frames)
    })
  // The strike pulls the creature, which chases its caster: the news of the strike is the
  // health and then the path (0x638).
  assert list.all(names, fn(frames) {
    frames == ["0x262(2)", "0x355(2)"]
    || frames == ["0x262(2)", "0x937(2)", "0x355(2)"]
    || frames == ["0x262(2)", "0x937(2)", "0x638(2)", "0x355(2)"]
  })
    as "the news the map took before the unit left sight is written and then the 0x355; the news it took after is written nowhere: the creature's news sent after the map's Unseen and before the creature took it is one of these"
  assert list.contains(names, ["0x262(2)", "0x355(2)"])
    && list.contains(names, ["0x262(2)", "0x937(2)", "0x638(2)", "0x355(2)"])
    as "both orders at the map are legal: the strike's news reaches the map before the unit leaves sight, or after"
}

/// The scene with the mail added behind what is in flight.
/// The first player's connection moves out of sight of the creature, as it tells the map.
fn first_player_moves_out(seq seq: Int) -> Mail {
  order_explorer.Mail(
    to: MapProcess,
    from: FromCaster,
    input: ToMap(
      OwnEvent(
        Told(map.Moved(
          connection: ConnectionId(first_player),
          place: spawns.at(spawns.far),
          seq:,
        )),
      ),
    ),
    name: "Moved out",
  )
}

pub fn a_strike_and_the_senders_move_out_of_sight_are_taken_in_the_order_the_sender_told_them_and_each_order_has_its_own_result_test() -> Nil {
  use <- owned_test.run(10_000)
  // The first player P stands at the creature, which the viewer W also sees. P's connection
  // tells the map a strike and its move out of the creature's sight; one sender, so the map
  // takes them in the order P told them, in either order of P's two tells. The creature's
  // sends to the map (its news, its tells to P) come in their own queue.
  let shown = legal_order_support.settle(joined(scene: standing()))
  let ready = legal_order_support.Scene(..shown, taken: [])
  let assert Ok(strike_first) =
    legal_order_support.mailed(scene: ready, mail: [
      strike(damage: 14),
      first_player_moves_out(seq: 1),
    ])
  let assert Ok(move_first) =
    legal_order_support.mailed(scene: ready, mail: [
      first_player_moves_out(seq: 1),
      strike(damage: 14),
    ])
  let strike_first = legal_order_support.orders(scene: strike_first)
  let move_first = legal_order_support.orders(scene: move_first)
  assert list.all(list.append(strike_first, move_first), fn(scene) {
    legal_order_support.check(scene:) == Ok(Nil)
  })
    as "no order of either tells breaks an invariant of W's frames"
  let creature_takes = fn(scene) {
    list.filter(
      legal_order_support.order_at(scene:, receiver: CreatureProcess),
      fn(name) { name == "Strike" || name == "Unseen" },
    )
  }
  let relays_to_p = fn(scene) {
    list.filter(
      legal_order_support.order_at(scene:, receiver: MapProcess),
      fn(name) { name == "Relay Threatened" || name == "Relay Released" },
    )
  }
  assert list.all(strike_first, fn(scene) {
    creature_takes(scene) == ["Strike", "Unseen"]
  })
    as "the strike first: the creature takes the strike, then P's leaving sight, in every order"
  assert list.all(strike_first, fn(scene) {
    relays_to_p(scene) == ["Relay Threatened", "Relay Released"]
  })
    as "P is a viewer when the strike lands: it is threatened, and then released when it leaves sight"
  assert list.all(move_first, fn(scene) {
    creature_takes(scene) == ["Unseen", "Strike"]
  })
    as "the move first: the creature takes P's leaving sight, then the strike"
  assert list.all(move_first, fn(scene) { relays_to_p(scene) == [] })
    as "P is no viewer when the strike lands: the damage applies and P is neither threatened nor released"
  assert list.all(strike_first, fn(scene) {
    legal_order_support.names(frames: scene.frames)
    == ["0x262(2)", "0x937(2)", "0x638(2)", "0x937(2)", "0x638(2)"]
  })
    as "the strike first: W is shown the damage, the creature's chase of P, then, with P released and no one left on its threat list, the creature's health restored and its walk home (`creature_fight`: with no threat left the creature leashes, restoring its health and walking home)"
  assert list.all(strike_first, fn(scene) {
    legal_order_support.health_shown(frames: scene.frames, unit_id: beast_unit)
    == Some(52)
  })
    as "and W ends showing the creature at full health, the leash's restore (`creature_fight`: with no threat left the creature leashes)"
  assert list.all(move_first, fn(scene) {
    legal_order_support.names(frames: scene.frames) == ["0x262(2)", "0x937(2)"]
    && legal_order_support.health_shown(
      frames: scene.frames,
      unit_id: beast_unit,
    )
    == Some(38)
  })
    as "the move first: W is shown the damage alone, 52 less 14, and no chase: the strike threatened no one"
}

pub fn legal_order_support_refuses_mail_to_a_creature_from_any_sender_but_its_map_and_its_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let mail = fn(sender) {
    order_explorer.Mail(
      to: CreatureProcess,
      from: sender,
      input: ToCreature(OwnEvent(ServiceTimerFired(TimerId(1)))),
      name: "a tell",
    )
  }
  list.each(
    [
      #(FromCaster, True),
      #(FromConnection, True),
      #(legal_order_support.FromMap, False),
      #(FromTimer, False),
    ],
    fn(row) {
      let #(sender, refused) = row
      let name = legal_order_support.sender_name(sender:)
      let taken =
        legal_order_support.mailed(scene: standing(), mail: [mail(sender)])
      assert result.is_error(taken) == refused
        as {
          "mail to a creature from "
          <> name
          <> case refused {
            True -> " is refused"
            False -> " is taken"
          }
        }
      case taken {
        Error(refusal) -> {
          assert string.contains(legal_order_support.describe(refusal:), name)
            as { "the refusal names the sender " <> name }
          Nil
        }
        Ok(_) -> Nil
      }
    },
  )
  // Every other way mail enters a scene is guarded too: the helper that adds it, the
  // scene's own mail, and a record update, whose mail is refused when it is delivered.
  let stops = fn(attempt) { result.is_error(exception.rescue(attempt)) }
  assert stops(fn() {
    legal_order_support.with_mail(scene: standing(), mail: [mail(FromCaster)])
  })
    as "mail to a creature from FromCaster stops the test when it is added to a scene"
  assert stops(fn() {
    legal_order_support.scene(
      map: standing().map,
      creature: creature_state_of(scene: standing()),
      viewer: game_connection_support.in_world(),
      mail: [mail(FromConnection)],
    )
  })
    as "and when a scene is made with it"
  assert stops(fn() {
    legal_order_support.settle(
      scene: legal_order_support.Scene(..standing(), mail: [
        mail(FromCaster),
      ]),
    )
  })
    as "and when a scene whose mail a record update put in delivers it"
  assert !stops(fn() {
    legal_order_support.with_mail(scene: standing(), mail: [
      mail(legal_order_support.FromMap),
    ])
  })
    as "mail from the map is added without a stop"
}

fn creature_state_of(scene scene: Scene) -> creature.State {
  let assert Some(state) = scene.creature
    as "the standing scene holds a creature"
  state
}

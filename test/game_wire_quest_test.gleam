//// Quests on the whole server: the objective progress a move, an activated target, a crate, a
//// mine or a kill sends (0x35c and the objective messages), what a relog keeps of it, a timed
//// quest botched, the quest bot and the tutorial played to the Northern Wilds landing.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import bot_frames
import character_support
import character_tables
import driven_time
import event_wait
import fight_bot
import game_client
import game_connection_support
import game_wire_support.{
  a_medic_of_a_level_at_the_marker_ring, beast_place, bot_countdown_ms,
  created_result, destroyed_units, in_select, is_near,
  kills_the_target_at_slot_0, new_player, new_player_at_level,
  on_rows_with_turrets_that_never_deflect,
  on_rows_without_paralytic_surges_recharge, refusals, ring_slot, send_move,
  send_play, start_with_creatures, start_with_world_data_on,
  static_objects_created_in, targets_in, the_target_at_slot_0, world_on,
  world_with_the_markers_creatures,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/movement
import genesis_prime/game_settings.{GameSettings}
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_result.{TargetIsNotUseable}
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/create_character_result
import genesis_prime/message/create_result
import genesis_prime/message/enter_world
import genesis_prime/message/experience_gained
import genesis_prime/message/float32
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/interaction_result
import genesis_prime/message/quest_log as quest_message
import genesis_prime/message/quest_objective_progress.{QuestObjectiveProgress}
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/static_unit_type
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_create_static
import genesis_prime/message/unit_destroyed
import genesis_prime/server
import genesis_prime/store.{AccountId}
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id
import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import login_support
import message_support
import owned_test
import pog
import quest_bot
import rating_support
import spawn_support
import tutorial_bot
import vendor_support

// ---- an objective's progress is saved ----

pub fn objective_progress_survives_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  // Scientist Lusk (Creature2 12484) stands 3.0 from the player's edge. Quest 3668's
  // objective 0 (4744) is a type 3 objective for him with count 1, and its objectives 1
  // and 2 are not talks, so the quest stays Accepted (QuestObjective rows). The talk is
  // the client's 0x7ea kind 37 (opcode.0x7ea) and is counted with a 0x361 (opcode.0x361);
  // after a camp and a new play, the 0x35f entry of the quest carries state 1, the flags
  // word 6 (tracked bit 1 and the done bit of objective 0, bit 2) and the progress 1, 0, 0
  // (opcode.0x35f).
  let selection =
    spawn.select(
      rows: [
        spawn.Row(
          ..spawn_support.beast_row(number: 10_707),
          creature_id: 12_484,
          display_info_id: 27_273,
          outfit_info_id: 0,
          faction_id: 171,
          base_faction_id: 171,
        ),
      ],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor_support.stocking(creature_ids: []),
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the row passes the spawn checks"
  let assert Ok(spawns) = dict.get(selection.worlds, 3460)
  let assert Ok(selected) = dict.get(spawns.by_id, spawn_id.SpawnId(10_707))
  let lusk =
    spawn.Spawn(
      ..selected,
      place: beast_place(
        x: 1.5,
        z: 3.5 -. { 3.0 +. 1.2 +. selected.combat.hit_radius },
      ),
    )
  let time = driven_time.new()
  let started =
    login_support.start_with(time:, change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: connection_state.Settings(
            ..game.settings,
            game: GameSettings(
              ..game.settings.game,
              camp_countdown_ms: bot_countdown_ms,
            ),
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in(
            world_id: 1387,
            spawns: [lusk],
            respawn_ms: 60_000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is of the faction Lusk's faction 171 is friendly to"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 3668, 1, 0, true, 0, '{0,0,0}', 0, '{0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 3668 with nothing done"
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && game_client.creatures_created_in(frames:) != []
    })
  let assert [shown] = game_client.creatures_created_in(frames: entry)
  assert shown.creature_id == 12_484
    as "the creature in sight is Scientist Lusk"
  let assert Ok(request) =
    interaction_request.encode(InteractionRequest(
      unit_id: shown.unit_id,
      kind: 37,
    ))
  game_client.send_world(
    game:,
    message_id: interaction_request.message_id,
    body: request,
  )
  let #(talked, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(talked, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 3668), #(32, 0), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the talk counts objective 0 of quest 3668"
  // The player camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  let assert [Frame(body: log, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x035F })
    as "the entry sends one 0x35f"
  let assert Ok(quest_message.QuestLog(active: [entry], ..)) =
    quest_message.decode(log)
    as "the client's reader reads the 0x35f, which holds the one quest"
  assert entry.quest_id == 3668 && entry.state == 1
    as "the quest is still Accepted: objectives 1 and 2 are open"
  assert entry.flags == 6
    as "opcode.0x35f: tracked (bit 1) and the done bit of objective 0 (bit 2)"
  assert entry.progress == [1, 0, 0]
    as "opcode.0x35f: the progress of each objective, the talk's saved"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_move_into_a_marker_sends_its_objective_progress_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 10513's objective 21271 (index 0, type 22, count 1) names WorldLocation2 51735
  // as its marker: World 3460, centre (32.5895, -854.5823, -544.8400), radius 1.0 and no
  // vertical limit. The client sends nothing for a place; its movement update (0x637) is
  // all the server sees of the arrival (opcode.0x637), and the server tells the client the
  // objective's progress (opcode.0x361: the quest, the objective, the value).
  let time = driven_time.new()
  let started = start_with_creatures(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 10513, 1, 0, true, 0, '{0,0,0,0,0}', 0, '{0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 10513 with nothing done"
  // Five units west of the marker's centre, outside its radius.
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: 6009,
    position: #(27.5895, -854.5823, -544.84),
  )
  send_play(game:, character_id: character)
  let #(_burst, have) = game_client.read_entry_kept(game:, have: <<>>)
  send_move(game:, position: #(33.0, -854.5823, -544.84), rotation: #(
    0.0,
    0.0,
    0.0,
  ))
  let #(arrived, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(arrived, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_513), #(32, 0), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: 0.41 from the centre of 51735 completes objective 21271 of quest 10513"
  // A later move inside the same marker: the server has written all it held for this
  // connection when its pong comes, so a 0x361 that the move would send is among the
  // frames.
  send_move(game:, position: #(32.8, -854.5823, -544.9), rotation: #(
    0.0,
    0.0,
    0.0,
  ))
  let #(later, _) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.filter(later, fn(frame) { frame.message_id == 0x0361 }) == []
    as "opcode.0x361: the objective is done, so a second move inside the marker counts nothing"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_checklist_target_shows_its_index_and_counts_once_when_activated_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 5855 holds objective 8782 at its index 1 (QuestObjective: type 14, count 5, data
  // TargetGroup 2766, whose member is Creature2 26016), and objective 8781 at index 0
  // (type 8). Creature2 26016 has activate spell 1817 behind Prerequisite 0, an
  // activateSpellCastTime of 1500 ms and an activateSpellMaxRange of 3.0; the spell is of
  // castMethod 0, so its go waits for no answer. Spawns 70878 and 70880 of World 1387 are
  // two of its objects, both with the world data's checklist index 0, so the server must
  // give them two distinct bits of the 32-bit mask (opcode.0x361, `checklist_index`): in
  // spawn order, the lowest index no earlier target holds, 0 and 1. The 0x262 carries the
  // index (opcode.0x262), the activate counts the bit of the object activated in the one
  // 0x361 (opcode.0x361: the quest, the objective, the whole mask), and the 0x35f of a
  // later entry carries the mask as the objective's progress (opcode.0x35f).
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_checklist",
      time:,
      adjusted: fn(settings) { settings },
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 5855, 1, 0, true, 0, '{0,0}', 0, '{0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 5855 with nothing done"
  // One unit east of spawn 70880, the second of the two: within the 3.0 of the creature's
  // activateSpellMaxRange, and 17.4 from spawn 70878, which is still in sight.
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 1387,
    world_zone_id: 1100,
    position: #(-3513.5, -979.1523, -6123.66),
  )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.length(static_objects_created_in(frames:)) == 2
    })
  let assert [_, second] as objects = static_objects_created_in(frames: entry)
  assert list.map(objects, fn(object) {
      #(object.creature_id, object.checklist_index)
    })
    == [#(26_016, 0), #(26_016, 1)]
    as "the two objects of Creature2 26016 are shown in spawn order with the two distinct indexes of objective 8782's bits"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: 1,
      target_unit_id: second.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: press,
  )
  // The server has taken the press, and armed the go's timer, when its pong comes: the
  // confirmation is sent before the timer starts, so the clock moves only after the pong.
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.any(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the first press is confirmed"
  driven_time.advance(time:, ms: 1500)
  let #(went, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 5855), #(32, 1), #(32, 2)]),
      ),
    ]
    as "opcode.0x361: the go of the activate counts the bit of index 1, the second object's, in objective 8782 of quest 5855"
  // The same object activated a second time: its bit is set in objective 8782. Creature2
  // 26016 links through prerequisiteIdAnimState 11686, whose two type 11 conditions nest
  // Prerequisite 11687 (type 43 on quest 5855's objective at index 1, and type 94
  // comparison 2, which fails once the unit's bit is set) and 11688 (the same for quest
  // 6780) (Prerequisite.prerequisiteTypeId.11, .94). A prerequisite that fails sets the
  // unit's anim state 1 (0x14046c4d0), and the client offers a unit in it nothing
  // (0x140479560.anim_state_exit), so the press is refused as not useable (100) with no
  // cast; the server has written all it held for this connection when its pong comes. The
  // used object goes out of sight at its go and comes back under its unit id after the
  // release time (migration 0033, 30 s), when the press meets the closed link.
  driven_time.advance(time:, ms: 31_000)
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(static_objects_created_in(frames:), fn(object) {
        object.unit_id == second.unit_id
      })
    })
  let assert Ok(again) =
    cast_activate.encode(CastActivate(
      client_cast_id: 2,
      target_unit_id: second.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: again,
  )
  let #(pressed_again, have) =
    game_client.read_until_pong(game:, have:, number: 2)
  assert refusals(frames: pressed_again)
    == [cast_result.to_value(TargetIsNotUseable)]
    as "opcode.0x7fc: the second press of the marked object is refused as not useable"
  assert list.filter(pressed_again, fn(frame) {
      frame.message_id == 0x07FD || frame.message_id == 0x0361
    })
    == []
    as "opcode.0x7fd and opcode.0x361: no cast starts and nothing is counted, the bit of index 1 is set in objective 8782"
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  let assert [Frame(body: log, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x035F })
    as "the entry sends one 0x35f"
  let assert Ok(quest_message.QuestLog(active: [quest], ..)) =
    quest_message.decode(log)
    as "the client's reader reads the 0x35f, which holds the one quest"
  assert quest.quest_id == 5855 && quest.progress == [0, 2]
    as "opcode.0x35f: the progress of objective 8782 is the mask with the bit of index 1, kept over the relog"
  game_client.close(game:)
  login_support.stop(started)
}

/// A character of this number one unit west of crate 18256's place in World 426, holding
/// quest 3741 ("Scattered Supplies", objective 4813) with nothing done when it is asked to:
/// its game, the bytes its client has read beyond its entry, and the frames of its entry,
/// read until the crate of the world data is shown.
fn near_the_crates(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  holds_the_quest holds_the_quest: Bool,
) -> #(game_client.Game, BitArray, List(Frame)) {
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number:,
      character_name:,
      class_id: 4,
      level: 1,
    )
  case holds_the_quest {
    True -> {
      let assert Ok(_) =
        pog.query(
          "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 3741, 1, 0, true, 0, '{0}', 0, '{0}', '{0,0,0,0,0,0}')",
        )
        |> pog.parameter(pog.int(character))
        |> pog.execute(pool)
        as "the character holds quest 3741 with nothing done"
      Nil
    }
    False -> Nil
  }
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 426,
    world_zone_id: 648,
    position: #(4453.227, -741.5363, -5457.145),
  )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && static_objects_created_in(frames:) != []
    })
  #(game, have, entry)
}

pub fn a_crate_of_scattered_supplies_counts_once_and_vanishes_for_everyone_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 12919 (Exile Supply Crate, quest 3741) casts activate spell 1817 after its
  // activateSpellCastTime of 2000 ms, from at most 5.0 away, and links to quest 3741's
  // objective index 0 (objective 4813, type 32, count 6) through its questAnim columns.
  // The fixture imports six of its crates (rows 18256 to 18261), as many as the
  // objective's count, so the load does not take the objective as short of units and
  // the connection releases a crate it counts (`objective_units.reused`).
  // The client keeps no record of a crate it has used and offers it again until the
  // objective is done (`QuestObjective.type.32.repeat_use`); the server counts a crate
  // once and takes it out of sight of everyone, so the client is sent 0x361 once and
  // 0x355 to each viewer (opcode.0x361, opcode.0x355; a used quest object vanishing for
  // everyone is Jim's decision of 2026-11-16).
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_crates",
      time:,
      adjusted: fn(settings) { settings },
    )
  let #(game, have, entry) =
    near_the_crates(
      started:,
      number: 1,
      character_name: "Zed Qu",
      holds_the_quest: True,
    )
  let #(viewer, viewer_have, _) =
    near_the_crates(
      started:,
      number: 2,
      character_name: "Ann Qu",
      holds_the_quest: False,
    )
  let assert Ok(crate) =
    nearest_object_of(
      objects: static_objects_created_in(frames: entry),
      creature_id: 12_919,
      to: #(4454.227, -5457.145),
    )
    as "crate 18256 is shown to the player who holds the quest"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: 1,
      target_unit_id: crate.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: press,
  )
  // The server has taken the press, and armed the go's timer, when its pong comes.
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.any(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press is confirmed"
  driven_time.advance(time:, ms: 2000)
  // The map takes the crate out of sight after the connection has told it the use: a
  // message from another process, so the 0x355 is waited for with the 0x361.
  let #(went, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0361 })
      && destroyed_units(frames:) != []
    })
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 3741), #(32, 0), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go counts one of the six"
  assert destroyed_units(frames: went) == [crate.unit_id]
    as "opcode.0x355: the crate goes out of the sight of the player who used it"
  let #(seen_by_viewer, _viewer_have) =
    game_client.read_until(game: viewer, have: viewer_have, found: fn(frames) {
      destroyed_units(frames:) != []
    })
  assert destroyed_units(frames: seen_by_viewer) == [crate.unit_id]
    as "opcode.0x355: and out of the sight of a second player, who holds no quest"
  // The same unit pressed again is a unit the player's client no longer holds: the
  // press is refused and counts nothing.
  let assert Ok(again) =
    cast_activate.encode(CastActivate(
      client_cast_id: 2,
      target_unit_id: crate.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: again,
  )
  let #(pressed_again, _) = game_client.read_until_pong(game:, have:, number: 2)
  assert list.filter(pressed_again, fn(frame) {
      frame.message_id == 0x0361 || frame.message_id == 0x07FD
    })
    == []
    as "opcode.0x361 and opcode.0x7fd: a second press of the same crate counts nothing and starts no cast"
  game_client.close(game:)
  game_client.close(game: viewer)
  login_support.stop(started)
}

// ---- two players see each other ----

/// What a character who has pressed a mine's activate leaves: the game, the mine's
/// unit, what the client has read after the cast's finish and its pong, the frames of
/// its entry and the frames it has read since the press.
type MineCast {
  MineCast(
    started: login_support.Started,
    game: game_client.Game,
    mine: unit_create_static.UnitCreateStatic,
    have: BitArray,
    entry: List(Frame),
    pressed: List(Frame),
    time: driven_time.Time,
  )
}

/// A character in World 3460 at the position, of the faction, holding the quest with its
/// objective 0 done, who has pressed the activate of the mine (the nearest object of
/// Creature2 `mine` to the character) after the entry showed every object of `shown`
/// (a Creature2 and its place), and whose cast has gone. The mine's activate is a cast
/// of Spell4 85452's castTime, 2000 ms (`Creature2.activateSpellCastTime` is 0, so
/// `0x14054e340` takes the spell's). The server runs on a driven clock, which the
/// helper moves by the cast's 2000 ms once the server has taken the press.
fn player_whose_mine_cast_went(
  character_name character_name: String,
  faction faction: Int,
  quest quest: Int,
  zone zone: Int,
  position position: #(Float, Float, Float),
  shown shown: List(#(Int, #(Float, Float, Float))),
  mine mine: Int,
) -> MineCast {
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_mine",
      time:,
      adjusted: fn(settings) { settings },
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name:,
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = $2 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(faction))
    |> pog.execute(pool)
    as "the character has the faction"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, $2, 1, 0, true, 1, '{1,0,0,0,0,0}', 0, '{0,0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.parameter(pog.int(quest))
    |> pog.execute(pool)
    as "the character holds the quest with objective 0 done"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: zone,
    position:,
  )
  send_play(game:, character_id: character)
  // Every object of `shown` is in the frames read, so the choice of the mine among the
  // objects of its Creature2 does not rest on the order they came in. The Sim-Turrets
  // of objectives 21288 and 21316 stand within sight of the mine, and each writes its
  // own 0x262 from its own process, so they may come before or after the mine's.
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.all(shown, fn(pair) {
        objects_standing_at(
          objects: static_objects_created_in(frames:),
          creature_id: pair.0,
          place: pair.1,
        )
        != []
      })
    })
  let assert Ok(mine) =
    nearest_object_of(
      objects: static_objects_created_in(frames: entry),
      creature_id: mine,
      to: #(position.0, position.2),
    )
    as "a static object of the mine's Creature2 is shown"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(
      client_cast_id: 1,
      target_unit_id: mine.unit_id,
    ))
    as "the right-click fits the message"
  game_client.send_world(
    game:,
    message_id: cast_activate.message_id,
    body: press,
  )
  // The server has taken the press, and armed the go's timer, when its pong comes: the
  // confirmation is sent before the timer starts, so the clock moves only after the pong.
  // The cast goes and finishes after its time, so the client waits for the server's 0x7fe,
  // and the server has written all it held for this connection when its second pong comes.
  let #(confirmed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert list.any(confirmed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press is confirmed"
  driven_time.advance(time:, ms: 2000)
  let #(cast, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x07FE })
    })
  let #(rest, have) = game_client.read_until_pong(game:, have:, number: 2)
  MineCast(
    started:,
    game:,
    mine:,
    have:,
    entry:,
    pressed: list.flatten([confirmed, cast, rest]),
    time:,
  )
}

/// An Exile in World 3460 one unit east of the tutorial's mine (Creature2 73463, world
/// database row 29098), holding quest 10518 with its objective 0 done, who has pressed
/// the mine's activate: the game, the mine's unit, what the client has read after the
/// cast's finish and its pong and the frames the client has read so far. The Dominion's
/// marker 52899 holds a mine of the same Creature2, 143 units away (a click target with
/// no spawn stands at its objective's marker), so the entry is read until both are in
/// and the Exile's mine is the one nearest the Exile.
fn exile_whose_mine_cast_went() -> #(
  login_support.Started,
  game_client.Game,
  Int,
  BitArray,
  List(Frame),
  driven_time.Time,
) {
  let cast =
    player_whose_mine_cast_went(
      character_name: "Zed Qu",
      faction: 167,
      quest: 10_518,
      zone: 6009,
      // One unit east of the mine (spawn 29098 stands at x -70.4453).
      position: #(-69.4453, -868.5904, 383.553),
      shown: [
        #(73_463, #(-70.4453, -868.5904, 383.553)),
        #(73_463, #(72.98709869384766, -872.089111328125, 357.6340026855469)),
      ],
      mine: 73_463,
    )
  #(
    cast.started,
    cast.game,
    cast.mine.unit_id,
    cast.have,
    cast.pressed,
    cast.time,
  )
}

pub fn a_mine_cast_counts_the_exile_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 73463 casts activate spell 85452 (activateSpellCastTime 0, so the cast goes
  // after the spell's castTime, 2000 ms) and links to quest 10518 through Prerequisite 41818 (type 43 on quest 10518
  // value 1 or on quest 10524 value 1). Objective 21287 is index 1 of quest 10518
  // (type 5, count 1, flags 3). The client sends nothing at the go, and the server
  // tells it the progress (opcode.0x361: the quest, the objective, the value 1). The
  // used mine goes out of sight, as any used quest object does (Jim, 2026-11-16): a
  // 0x355 for its unit follows (opcode.0x355).
  let #(started, game, mine, have, went, _) = exile_whose_mine_cast_went()
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 1), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go of the mine's cast counts objective 21287 of quest 10518"
  let #(destroyed, _) = destroyed_after(game:, have:, seen: went)
  assert destroyed == [mine]
    as "opcode.0x355: the mine that was used goes out of the player's sight, and no other unit does"
  game_client.close(game:)
  login_support.stop(started)
}

/// The unit ids the 0x355 among the frames remove, or, when none is among them, those of
/// the first 0x355 the map sends the game next: the map takes a used object out of sight
/// after the connection has told it the use, so the news may come before or after the
/// frames the caller has read.
fn destroyed_after(
  game game: game_client.Game,
  have have: BitArray,
  seen seen: List(Frame),
) -> #(List(Int), BitArray) {
  case destroyed_units(frames: seen) {
    [] -> {
      let #(more, have) =
        game_client.read_until(game:, have:, found: fn(frames) {
          destroyed_units(frames:) != []
        })
      #(destroyed_units(frames: more), have)
    }
    units -> #(units, have)
  }
}

/// A Dominion character in World 3460 one unit east of marker 52899 (WorldLocation2
/// 52899, x 72.98709869384766, y -872.089111328125, z 357.6340026855469), holding quest
/// 10524 with its objective 0 done, who sees the mines the markers hold: the markers
/// 52899, 52900 and 52901 (the click objectives 21313, 21314 and 21315, indexes 1, 2
/// and 3 of quest 10524) have no stored spawn, the world database holds only the
/// Exile's mines (rows 29098 to 29100) in that world, and each mine of the tutorial
/// is a Creature2 of its own (73463, 73667 and 73668, CreationTypeEnum 20, unit type
/// 32).
pub fn a_dominion_player_sees_and_counts_the_mines_at_their_markers_test() -> Nil {
  use <- owned_test.run(60_000)
  // The marker of each mine: its centre (WorldLocation2 position0, 1 and 2).
  let markers = [
    #(73_463, #(72.98709869384766, -872.089111328125, 357.6340026855469)),
    #(73_667, #(53.51499938964844, -872.089111328125, 374.47900390625)),
    #(73_668, #(43.11709976196289, -872.089111328125, 395.1889953613281)),
  ]
  // The character is one unit east of marker 52899, whose mine is the nearest of its
  // Creature2.
  let MineCast(started:, game:, mine:, have:, entry:, pressed:, ..) =
    player_whose_mine_cast_went(
      character_name: "Dax Qu",
      faction: 166,
      quest: 10_524,
      zone: 5967,
      position: #(73.98709869384766, -872.089111328125, 357.6340026855469),
      shown: markers,
      mine: 73_463,
    )
  let at_markers =
    list.map(markers, fn(pair) {
      objects_standing_at(
        objects: static_objects_created_in(frames: entry),
        creature_id: pair.0,
        place: pair.1,
      )
    })
  let assert [[at_52899], [_], [_]] = at_markers
    as "opcode.0x262: one mine of each Creature2 stands at its marker"
  assert list.all(list.flatten(at_markers), fn(object) {
    object.unit_type == static_unit_type.SimpleCollidable
  })
    as "opcode.0x262: each mine is sent as unit type 32, the type CreationTypeEnum 20 pairs with"
  assert mine == at_52899 as "the mine pressed is the one at marker 52899"
  assert list.filter(pressed, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_524), #(32, 1), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go of the mine's cast counts objective 21313 of quest 10524"
  let #(destroyed, _) = destroyed_after(game:, have:, seen: pressed)
  assert destroyed == [mine.unit_id]
    as "opcode.0x355: the mine that was used goes out of the player's sight, and no other mine does"
  game_client.close(game:)
  login_support.stop(started)
}

/// A level 1 Medic of the Exile holding quest 10518 with objectives 0 to 4 done and `sixth`
/// of the 3 kills the sixth asks, played into World 3460 12 beyond ring slot 0 and facing
/// it, and read until both of Creature2 73492's 0x262 have arrived: the game, the burst's
/// frames and the bytes beyond.
fn a_medic_at_the_marker_ring(
  started started: login_support.Started,
  sixth sixth: Int,
) -> #(game_client.Game, List(Frame), BitArray, Int) {
  a_medic_of_a_level_at_the_marker_ring(
    started:,
    sixth:,
    level: 1,
    saved_experience: None,
  )
}

pub fn a_placed_target_is_shown_killed_and_counted_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have, _) = a_medic_at_the_marker_ring(started:, sixth: 0)
  let shown = targets_in(frames:)
  assert list.map(shown, fn(creature) {
      game_client.placed_by_tail(tail: creature.tail)
    })
    |> list.all(fn(place) {
      is_near(left: place, right: ring_slot(index: 0))
      || is_near(left: place, right: ring_slot(index: 2))
    })
    as "opcode.0x262: the two 73492 of the ring stand at its slots 0 and 2, the group's creatures taking the slots in order, 73492, 73567, 73492"
  let target = the_target_at_slot_0(frames:)
  assert target.tail.faction_id == 170 && target.tail.base_faction_id == 170
    as "opcode.0x262: both factions are the Creature2 row's, 170"
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  // The kill's credit comes from the creature after its death is written.
  let #(counted, _) = game_client.read_until_pong(game:, have:, number: 7)
  assert list.filter(list.append(killed, counted), fn(frame) {
      frame.message_id == 0x0361
    })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 5), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the kill counts objective 21290, the sixth of quest 10518, once"
  game_client.close(game:)
  login_support.stop(started)
}

/// Whether the frames hold the 0x35c that completes quest 10518 (state 3, objective 0).
fn quest_10518_completed_in(frames frames: List(Frame)) -> Bool {
  list.any(frames, fn(frame) {
    frame.message_id == 0x035C
    && quest_state.decode(frame.body)
    == Ok(QuestState(quest_id: 10_518, state: 3, objective_id: 0))
  })
}

pub fn the_last_kill_of_quest_10518_is_followed_by_0x35c_state_2_its_rewards_and_0x35c_state_3_test() -> Nil {
  use <- owned_test.run(120_000)
  // Quest 10518 has no creature that receives it (`table_rows -- Creature2
  // questIdReceive00=10518` names none), so the client shows it Achieved itself and only
  // the server's 0x35c state 3 completes it (Quest2.10513.completion). The sixth objective
  // has 2 of its 3 kills done, so the kill of the target at ring slot 0 is the last.
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have, _) = a_medic_at_the_marker_ring(started:, sixth: 2)
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  // No wait on time: the read goes on until the frame that completes the quest arrives.
  let #(rest, _) =
    game_client.read_until(game:, have:, found: fn(rest) {
      quest_10518_completed_in(frames: list.append(killed, rest))
    })
  let quest_frames =
    list.filter(list.append(killed, rest), fn(frame) {
      list.contains([0x0361, 0x035C, 0x01AC], frame.message_id)
    })
  assert list.map(quest_frames, fn(frame) { frame.message_id })
    == [0x01AC, 0x0361, 0x035C, 0x01AC, 0x035C]
    as "the kill's experience, then the progress and the state 2 the kill makes, then the completion's experience and its state 3"
  let assert [kill_experience, progress, achieved, reward, completed] =
    quest_frames
  assert experience_gained.decode(kill_experience.body)
    |> result.map(fn(gained) { gained.source_kind })
    == Ok(2)
    as "opcode.0x1ac: the first experience is the kill's, kind 2"
  assert progress.body
    == message_support.packed([#(15, 10_518), #(32, 5), #(32, 3)])
    as "opcode.0x361: objective 5 of quest 10518 is at 3 of 3"
  assert quest_state.decode(achieved.body)
    == Ok(QuestState(quest_id: 10_518, state: 2, objective_id: 0))
    as "opcode.0x35c: the quest is Achieved"
  assert experience_gained.decode(reward.body)
    |> result.map(fn(gained) { #(gained.experience, gained.source_kind) })
    == Ok(#(655, 3))
    as "opcode.0x1ac: the quest's experience override 655, kind 3 (a quest), from the completion"
  assert quest_state.decode(completed.body)
    == Ok(QuestState(quest_id: 10_518, state: 3, objective_id: 0))
    as "opcode.0x35c: the server completes the quest, state 3 with objective 0, last"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_placed_target_respawns_at_its_slot_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have, _) = a_medic_at_the_marker_ring(started:, sixth: 0)
  let target = the_target_at_slot_0(frames:)
  let #(_, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  // The respawn time is the row every creature without one of its own takes
  // (death.creature_respawn): the creature kind row 0 of the content.
  let assert Ok(kind) =
    pog.query("select respawn_ms from creature_kind where creature_id = 0")
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(pog.named_connection(started.settings.pool.pool_name))
    as "the default creature kind is read"
  let assert [respawn_ms] = kind.rows
  // The creature sends its news before it starts the corpse's timer, which the
  // advance's barrier waits for.
  driven_time.advance(time:, ms: respawn_ms)
  let #(after, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), target.unit_id)
      && list.any(game_client.creatures_created_in(frames:), fn(unit) {
        unit.unit_id == target.unit_id
      })
    })
  let assert Ok(again) =
    list.find(game_client.creatures_created_in(frames: after), fn(unit) {
      unit.unit_id == target.unit_id
    })
  assert game_client.placed_by_tail(tail: again.tail)
    == game_client.placed_by_tail(tail: target.tail)
    && again.creature_id == 73_492
    as "death.creature_respawn: 0x355, then a new 0x262 with the same unit id at the same place, ring slot 0"
  game_client.close(game:)
  login_support.stop(started)
}

/// The static objects of the Creature2 that stand at the place, within 0.01 on each
/// axis.
fn objects_standing_at(
  objects objects: List(unit_create_static.UnitCreateStatic),
  creature_id creature_id: Int,
  place place: #(Float, Float, Float),
) -> List(unit_create_static.UnitCreateStatic) {
  list.filter(objects, fn(object) {
    let #(x, y, z) = game_client.placed_by_tail(tail: object.tail)
    object.creature_id == creature_id
    && float.absolute_value(x -. place.0) <. 0.01
    && float.absolute_value(y -. place.1) <. 0.01
    && float.absolute_value(z -. place.2) <. 0.01
  })
}

/// The static object of the Creature2 that stands nearest the position (x, z) of
/// the world, or Error(Nil) when none of it is among the objects.
fn nearest_object_of(
  objects objects: List(unit_create_static.UnitCreateStatic),
  creature_id creature_id: Int,
  to to: #(Float, Float),
) -> Result(unit_create_static.UnitCreateStatic, Nil) {
  let apart = fn(object: unit_create_static.UnitCreateStatic) {
    let #(x, _, z) = game_client.placed_by_tail(tail: object.tail)
    let far = x -. to.0
    let deep = z -. to.1
    far *. far +. deep *. deep
  }
  objects
  |> list.filter(fn(object) { object.creature_id == creature_id })
  |> list.sort(fn(a, b) { float.compare(apart(a), apart(b)) })
  |> list.first
}

// ---- a quest bot ----

/// Where the Exile Human starts: WorldLocation2 42074, World 426, WorldZone 648
/// (Northern Wilds), where the quest bot stands and never moves.
const exile_start = #(4098.16, -665.98, -5165.1)

/// A row of the spawn table for World 426 at an offset east (`dx`) and south (`dz`)
/// of the Exile start: the row of an object (entity type 10) or a creature (entity
/// type 0) the quest bot meets, as the planted rows of the other whole-server tests are
/// the test's own, not recorded.
fn northern_wilds_row(
  number number: Int,
  entity_type entity_type: Int,
  creature_id creature_id: Int,
  display_info_id display_info_id: Int,
  outfit_info_id outfit_info_id: Int,
  faction_id faction_id: Int,
  dx dx: Float,
  dz dz: Float,
) -> spawn.Row {
  spawn.Row(
    ..spawn_support.beast_row(number:),
    entity_type:,
    creature_id:,
    world_id: 426,
    area_id: 648,
    x: exile_start.0 +. dx,
    y: exile_start.1,
    z: exile_start.2 +. dz,
    display_info_id:,
    outfit_info_id:,
    faction_id:,
    base_faction_id: faction_id,
  )
}

pub fn a_bot_accepts_uses_and_turns_in_a_northern_wilds_quest_takes_up_another_and_finds_both_after_a_relog_test() -> Nil {
  use <- owned_test.run(120_000)
  // Northern Wilds is the Exile start zone (World 426, WorldZone 35 of Quest2 3886 and
  // 3480). Creature2 11066 gives and receives quest 3886 (questIdGiven01, questIdReceive04),
  // which asks for one use of Creature2 13630 (QuestObjective 5053: type 12, count 1) and
  // three uses of the members of TargetGroup 1460, which is Creature2 13623 (5052: type 14,
  // count 3). Creature2 11061 gives quest 3480 (questIdGiven00), whose first objective asks
  // for three uses of Creature2 11070 (4470: type 12, count 3). Every Creature2 has the activate
  // spell 1817 with an activateSpellCastTime of 2000 ms; the activateSpellMaxRange is 5.0 for
  // 13630 and 11070 and 7.0 for 13623, and the reach to a giver is 6.0 between edges. Each is
  // planted within 4.5 of the Exile start. The giver's faction 171 is friendly to the
  // Exile's 167 (Faction2Relationship 771).
  let time = driven_time.new()
  let giver = 11_066
  let other_giver = 11_061
  let rows = [
    northern_wilds_row(
      number: 1,
      entity_type: 0,
      creature_id: giver,
      display_info_id: 22_825,
      outfit_info_id: 9065,
      faction_id: 171,
      dx: 0.0,
      dz: 4.0,
    ),
    northern_wilds_row(
      number: 2,
      entity_type: 0,
      creature_id: other_giver,
      display_info_id: 22_825,
      outfit_info_id: 9065,
      faction_id: 171,
      dx: 0.0,
      dz: -4.0,
    ),
    northern_wilds_row(
      number: 3,
      entity_type: 0,
      creature_id: 11_070,
      display_info_id: 24_086,
      outfit_info_id: 0,
      faction_id: 219,
      dx: 3.0,
      dz: 0.0,
    ),
    northern_wilds_row(
      number: 4,
      entity_type: 10,
      creature_id: 13_630,
      display_info_id: 23_147,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -3.0,
      dz: 0.0,
    ),
    northern_wilds_row(
      number: 5,
      entity_type: 10,
      creature_id: 13_623,
      display_info_id: 25_210,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -2.0,
      dz: 3.0,
    ),
    northern_wilds_row(
      number: 6,
      entity_type: 10,
      creature_id: 13_623,
      display_info_id: 25_210,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -3.0,
      dz: 3.0,
    ),
    northern_wilds_row(
      number: 7,
      entity_type: 10,
      creature_id: 13_623,
      display_info_id: 25_210,
      outfit_info_id: 0,
      faction_id: 219,
      dx: -4.0,
      dz: 3.0,
    ),
  ]
  let selection =
    spawn.select(
      rows:,
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor_support.stocking(creature_ids: []),
      factions: creature_faction.none(),
    )
  assert selection.refusals == [] as "the rows pass the spawn checks"
  let assert Ok(northern_wilds) = dict.get(selection.worlds, 426)
    as "World 426 has spawns"
  assert dict.size(northern_wilds.by_id) == 3
    && dict.size(northern_wilds.objects) == 4
    as "the three creatures (11066, 11061 and 11070) start and the four objects (13630 and the three 13623) are sent"
  let started =
    login_support.start_with(time:, change: fn(settings) {
      let game = settings.game
      server.Settings(
        ..settings,
        game: server.Served(
          ..game,
          settings: connection_state.Settings(
            ..game.settings,
            game: GameSettings(
              ..game.settings.game,
              camp_countdown_ms: bot_countdown_ms,
            ),
          ),
        ),
        world: server.World(
          ..settings.world,
          spawns: spawn_support.key_in_with_objects(
            world_id: 426,
            spawns: dict.values(northern_wilds.by_id),
            objects: dict.values(northern_wilds.objects),
            respawn_ms: 60_000,
          ),
        ),
      )
    })
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is an Exile"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 426,
    world_zone_id: 648,
    position: exile_start,
  )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.length(static_objects_created_in(frames:)) == 4
      && list.length(game_client.creatures_created_in(frames:)) == 3
    })
  let shown = game_client.creatures_created_in(frames: entry)
  let assert Ok(giving) =
    list.find(shown, fn(unit) { unit.creature_id == giver })
    as "the giver of 3886 is in sight"
  let assert Ok(other_giving) =
    list.find(shown, fn(unit) { unit.creature_id == other_giver })
    as "the giver of 3480 is in sight"
  let assert Ok(attacker) =
    list.find(shown, fn(unit) { unit.creature_id == 11_070 })
    as "Creature2 11070 is in sight"
  let objects = static_objects_created_in(frames: entry)
  let assert Ok(single) =
    list.find(objects, fn(object) { object.creature_id == 13_630 })
    as "the object of objective 5053 is in sight"
  let group =
    list.filter(objects, fn(object) { object.creature_id == 13_623 })
    |> list.sort(fn(a, b) { int.compare(a.checklist_index, b.checklist_index) })
  assert list.map(group, fn(object) { object.checklist_index }) == [0, 1, 2]
    as "opcode.0x262: the three objects of TargetGroup 1460 take the checklist indexes 0, 1 and 2, in spawn order"
  // 1: talks to the giver, which opens its dialog.
  let #(talked, have) = quest_bot.talk(game:, have:, unit_id: giving.unit_id)
  assert list.map(talked.dialogs, fn(opened) { opened.unit_id })
    == [giving.unit_id]
    as "opcode.0x357: the giver's dialog opens for its unit"
  // 2: mentions quest 3886, which carries Quest2 flag 0x400 (needs a mention: the client's
  // CanAcceptQuest refuses it with code 11 until the log holds a state of 4 to 7), then
  // accepts it.
  let #(_, have) = quest_bot.mention(game:, have:, quest_id: 3886)
  let #(accepted, have) = quest_bot.accept(game:, have:, quest_id: 3886)
  assert accepted.states
    == [QuestState(quest_id: 3886, state: 1, objective_id: 0)]
    as "opcode.0x35c: quest 3886 is Accepted"
  // 3: uses the object of objective 5053: the cast is confirmed, and its go after the
  // 2000 ms of activateSpellCastTime counts the objective.
  let #(pressed, have) =
    quest_bot.activate(game:, have:, client_cast_id: 1, unit_id: single.unit_id)
  assert list.length(pressed.confirmed) == 1
    as "opcode.0x7fd: the press is confirmed"
  driven_time.advance(time:, ms: 2000)
  let #(used, have) = quest_bot.went(game:, have:)
  assert used.progress
    == [QuestObjectiveProgress(quest_id: 3886, objective_index: 0, progress: 1)]
    as "opcode.0x361: objective 5053 of quest 3886, index 0, counts 1"
  assert used.states == [] as "the quest has an open objective left"
  // 4: uses the three objects of the group, in the order of their indexes: each go
  // counts its bit of the whole mask (opcode.0x361), and the third achieves the quest.
  let #(have, masks, last) =
    list.index_fold(group, #(have, [], used), fn(done, object, index) {
      let #(have, masks, _) = done
      let #(_, have) =
        quest_bot.activate(
          game:,
          have:,
          client_cast_id: 2 + index,
          unit_id: object.unit_id,
        )
      driven_time.advance(time:, ms: 2000)
      let #(went, have) = quest_bot.went(game:, have:)
      #(have, list.append(masks, went.progress), went)
    })
  assert masks
    == [
      QuestObjectiveProgress(quest_id: 3886, objective_index: 1, progress: 1),
      QuestObjectiveProgress(quest_id: 3886, objective_index: 1, progress: 3),
      QuestObjectiveProgress(quest_id: 3886, objective_index: 1, progress: 7),
    ]
    as "opcode.0x361: objective 5052 of quest 3886, index 1, carries the whole mask: bits 0, 1 and 2 set one by one"
  assert last.states == [QuestState(quest_id: 3886, state: 2, objective_id: 0)]
    as "opcode.0x35c: the third use achieves the quest"
  // 5: turns it in at its receiver with the choice the bot is offered. Of the three
  // choices of Quest2 3886 (Quest2Reward 2192, 2430 and 4767), `equip_requirement.offered`
  // allows a class 4 character with Class 4's startingItemProficiencies 260 only 2430,
  // which gives Item2 13332. The experience is the quest's conLevel 4 XpPerLevel
  // baseQuestXpPerLevel 152 times Quest2Difficulty 4's xpMultiplier 1.5 times the
  // LevelDifferentialAttribute of a difference of 3, 1.0: 228, short of the 655 level 2 asks for.
  let #(talked, have) = quest_bot.talk(game:, have:, unit_id: giving.unit_id)
  assert list.map(talked.dialogs, fn(opened) { opened.unit_id })
    == [giving.unit_id]
    as "opcode.0x357: the receiver's dialog opens"
  let #(turned, have) =
    quest_bot.turn_in(game:, have:, quest_id: 3886, reward_id: 2430)
  assert turned.experience
    == [
      experience_gained.ExperienceGained(
        experience: 228,
        rest_experience_used: 0,
        bonus_experience: 0,
        source_kind: 3,
        source_unit_id: 0,
      ),
    ]
    as "opcode.0x1ac: kind 3, a quest, for 228"
  assert list.any(turned.added, fn(held) { held.item.item_id == 13_332 })
    as "the chosen reward, Item2 13332, is added"
  assert list.last(turned.states)
    == Ok(QuestState(quest_id: 3886, state: 3, objective_id: 0))
    as "opcode.0x35c: the quest is Completed"
  assert list.contains(
    list.take_while(
      list.map(turned.frames, fn(frame) { frame.message_id }),
      fn(id) { id != quest_state.message_id },
    ),
    experience_gained.message_id,
  )
    as "the experience comes before the quest's state"
  // 6: takes up quest 3480 at its giver.
  let #(talked, have) =
    quest_bot.talk(game:, have:, unit_id: other_giving.unit_id)
  assert list.map(talked.dialogs, fn(opened) { opened.unit_id })
    == [other_giving.unit_id]
    as "opcode.0x357: the second giver's dialog opens"
  let #(accepted, have) = quest_bot.accept(game:, have:, quest_id: 3480)
  assert accepted.states
    == [QuestState(quest_id: 3480, state: 1, objective_id: 0)]
    as "opcode.0x35c: quest 3480 is Accepted, its exclusion 3479 not held"
  // 7: uses Creature2 11070 once, of the three objective 4470 asks for.
  let #(pressed_once, have) =
    quest_bot.activate(
      game:,
      have:,
      client_cast_id: 5,
      unit_id: attacker.unit_id,
    )
  assert list.length(pressed_once.confirmed) == 1
    as "opcode.0x7fd: the press at 11070 is confirmed"
  driven_time.advance(time:, ms: 2000)
  let #(once, have) = quest_bot.went(game:, have:)
  assert once.progress
    == [QuestObjectiveProgress(quest_id: 3480, objective_index: 0, progress: 1)]
    as "opcode.0x361: objective 4470 of quest 3480 counts 1 of 3"
  assert once.states == [] as "opcode.0x35c: the quest stays Accepted"
  // 8: camps and plays the same character again.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  let assert [Frame(body: log, ..)] =
    list.filter(second_entry, fn(frame) { frame.message_id == 0x035F })
    as "the entry sends one 0x35f"
  let assert Ok(quest_message.QuestLog(completed:, active:, ..)) =
    quest_message.decode(log)
    as "the client's reader reads the 0x35f"
  assert list.map(completed, fn(done) { done.quest_id }) == [3886]
    as "opcode.0x35f: quest 3886 is among the completed"
  assert list.map(active, fn(entry) {
      #(entry.quest_id, entry.state, entry.progress)
    })
    == [#(3480, 1, [1, 0])]
    as "opcode.0x35f: only quest 3480 is active, Accepted with objective 0 at 1 and objective 1 at 0"
  game_client.close(game:)
  login_support.stop(started)
}

// The tutorial boss, Creature2 73499 (QuestObjective 21296 and 21310, type 2, count 1,
// marker 51744). Marker 51744 is at (429.29544, -388.88251, 253.77565) in World 3460,
// zone 5968 (`table_rows -- WorldLocation2 51744`), and a lone target stands at the
// marker's centre. The Creature2 row gives factionId 219, Friendly to both player
// factions, so the server stands it with faction 233, Hostile to the parent 165 of the
// Dominion 166 and the Exile 167 (Faction2Relationship 746, migration 0027). Quest 10520
// (Quest2 10520, questPlayerFactionEnum 0, the Exile's) holds the kill as its fourth
// objective, index 3 (Quest2 objective03 21296), and opens it once the objectives of
// index 0 and 2 are done (0x140553790: the objectives of index 1 and 4 hold flag 0x21
// and the visit's 0x3; the objective_test header gives the shape).

/// The boss's marker centre.
const marker_51744 = #(429.29544, -388.88251, 253.77565)

/// An Exile Medic of level 30 holding quest 10520 with the objectives of index 0 and 2 done,
/// played into World 3460 12 beyond the boss and facing it, and read until the
/// boss's 0x262 has arrived: the game, the burst's frames and the bytes beyond.
fn an_exile_medic_beside_the_boss(
  started started: login_support.Started,
) -> #(game_client.Game, List(Frame), BitArray) {
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 30,
    )
  let assert Ok(_) =
    pog.query("update character set faction_id = 167 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character is an Exile one (faction 167)"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 10520, 1, 0, true, 5, '{3,0,1,0,0}', 0, '{0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 10520 with the objectives of index 0 (21294) and 2 (21295) done, so the kill of index 3 is open"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: 5968,
    position: #(marker_51744.0 +. 12.0, marker_51744.1, marker_51744.2),
  )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(game_client.creatures_created_in(frames:), fn(creature) {
        creature.creature_id == 73_499
      })
    })
  #(game, frames, have)
}

pub fn an_exile_kills_the_boss_and_objective_21296_counts_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, frames, have) = an_exile_medic_beside_the_boss(started:)
  let assert Ok(boss) =
    list.find(game_client.creatures_created_in(frames:), fn(creature) {
      creature.creature_id == 73_499
    })
    as "the boss is created for the Exile"
  assert is_near(
    left: game_client.placed_by_tail(tail: boss.tail),
    right: marker_51744,
  )
    as "opcode.0x262: a lone target stands at its marker's centre"
  assert boss.tail.faction_id == 233 && boss.tail.base_faction_id == 233
    as "opcode.0x262: the unit stands with faction 233, Hostile to the Exile's parent (Faction2Relationship 746)"
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(
      from: #(marker_51744.0 +. 12.0, marker_51744.2),
      target: #(marker_51744.0, marker_51744.2),
    ),
    clock: 100,
  )
  let assert Ok(#(killed, have)) =
    fight_bot.presses_until_the_target_dies(
      ability: fight_bot.paralytic_surge,
      advance: driven_time.advance(time:, ms: _),
      recharge_ms: 0,
      game:,
      have:,
      target: boss.unit_id,
      cast_id: 1,
      seen: [],
    )
  // The kill's credit comes from the creature after its death is written.
  let #(counted, _) = game_client.read_until_pong(game:, have:, number: 7)
  assert list.filter(list.append(killed, counted), fn(frame) {
      frame.message_id == 0x0361
    })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_520), #(32, 3), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the kill counts objective 21296, the fourth of quest 10520, once: 1 of 1"
  game_client.close(game:)
  login_support.stop(started)
}

/// The quest rows the store holds for the character: each quest and its state, by quest.
fn quest_rows(
  pool pool: pog.Connection,
  character_id character_id: Int,
) -> List(#(Int, Int)) {
  let assert Ok(returned) =
    pog.query(
      "select quest_id, state::int from character_quest where character_id = $1 order by quest_id",
    )
    |> pog.parameter(pog.int(character_id))
    |> pog.returning({
      use quest_id <- decode.field(0, decode.int)
      use state <- decode.field(1, decode.int)
      decode.success(#(quest_id, state))
    })
    |> pog.execute(pool)
    as "the quest rows read"
  returned.rows
}

/// Creates the medic "Zed Qu" on the account of `insert_jim` and plays it into the
/// tutorial world: the connection, the created result, and the entry's frames up to its
/// 0x01BC and its 0x035C, with the bytes beyond them.
fn enter_the_tutorial(
  started: login_support.Started,
) -> #(
  game_client.Game,
  create_character_result.CreateCharacterResult,
  List(Frame),
  BitArray,
) {
  let account = AccountId(login_support.insert_jim(started))
  let game =
    in_select(started:, port: login_support.ports(started).game_port, account:)
  game_client.send_create(
    game:,
    body: character_support.medic_create_request("Zed Qu"),
  )
  let created = created_result(game)
  assert created.result == create_result.CreateOk
    as "opcode.0xdc: a valid request is created"
  send_play(game:, character_id: created.character_id)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      && list.any(frames, fn(frame) { frame.message_id == 0x035C })
    })
  #(game, created, entry, have)
}

pub fn a_bot_creates_an_exile_and_plays_the_tutorial_to_the_northern_wilds_landing_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- on_rows_with_turrets_that_never_deflect()
  let time = driven_time.new()
  let started =
    world_on(
      folder: "test/fixture/world_data_tutorial_path",
      tables:,
      time:,
      tutorial: True,
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, created, entry, have) = enter_the_tutorial(started)
  let entry_ids = list.map(entry, fn(frame) { frame.message_id })
  assert list.filter(entry_ids, fn(id) { id == 0x035F || id == 0x035C })
    == [0x035F, 0x035C]
    as "opcode.0x35f.entry_order: the log, then the one grant after it"
  assert bot_frames.decoded(entry, quest_state.message_id, quest_state.decode)
    == [QuestState(quest_id: 10_513, state: 1, objective_id: 0)]
    as "opcode.0x35c.add_unaccepted: the entry into World 3460 gives 10513 in state 1"
  let assert Ok(played) =
    tutorial_bot.play(
      game:,
      have:,
      entry:,
      env: tutorial_bot.Env(
        advance: fn(ms) { driven_time.advance(time:, ms:) },
        recharge_ms: 0,
        settled: fn(unit_id) {
          character_support.marker_creature_settled(
            settings: started.settings,
            unit_id:,
          )
        },
      ),
    )
    as "the bot plays every step of the tutorial's path"
  let states =
    bot_frames.decoded(
      played.frames,
      quest_state.message_id,
      quest_state.decode,
    )
  assert list.filter_map(states, fn(told) {
      case told.state {
        3 -> Ok(told.quest_id)
        _ -> Error(Nil)
      }
    })
    == [10_513, 10_527, 10_518, 10_529, 10_525, 10_540, 10_519, 10_520]
    as "Quest2's chain from 10513: each quest is Completed in the order the path gives it, the chain's by the server and the turn-ins at 73421, Dorian 73491 and 74812"
  let progress =
    bot_frames.decoded(
      played.frames,
      quest_objective_progress.message_id,
      quest_objective_progress.decode,
    )
  assert list.contains(
      progress,
      QuestObjectiveProgress(quest_id: 10_528, objective_index: 1, progress: 1),
    )
    && list.contains(
      progress,
      QuestObjectiveProgress(quest_id: 10_528, objective_index: 2, progress: 1),
    )
    && list.contains(
      states,
      QuestState(quest_id: 10_528, state: 2, objective_id: 0),
    )
    as "Quest2 10528: the yes at Departures Terminal 73606 counts the travel (index 1) and the Northern Wilds choice (index 2), and the quest is Achieved"
  let assert [entered, ..] =
    list.reverse(bot_frames.decoded(
      played.frames,
      enter_world.message_id,
      enter_world.decode,
    ))
    as "the landing's 0xAD"
  assert entered.world_id == 426
    && entered.position_x == float32.to_bits(4098.16015625)
    && entered.position_y == float32.to_bits(-665.9780883789062)
    && entered.position_z == float32.to_bits(-5165.10009765625)
    as "WorldLocation2 42074, the landing of Departures Terminal 73606: world 426 at (4098.16015625, -665.9780883789062, -5165.10009765625)"
  // The quest log is saved with the player when the save timer fires.
  driven_time.advance(time:, ms: movement.save_period_ms)
  event_wait.until("the store holds the quest log the bot played", fn() {
    quest_rows(pool:, character_id: created.character_id)
    == [
      #(10_513, 3),
      #(10_518, 3),
      #(10_519, 3),
      #(10_520, 3),
      #(10_525, 3),
      #(10_527, 3),
      #(10_528, 2),
      #(10_529, 3),
      #(10_540, 3),
    ]
  })
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_use_of_dorian_leaves_him_in_place_and_10525_is_taken_from_him_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- on_rows_with_turrets_that_never_deflect()
  let time = driven_time.new()
  let started =
    world_on(
      folder: "test/fixture/world_data_tutorial_path",
      tables:,
      time:,
      tutorial: True,
    )
  let #(game, _, entry, have) = enter_the_tutorial(started)
  let assert Ok(bot) =
    tutorial_bot.play_to_the_dorians(
      game:,
      have:,
      entry:,
      env: tutorial_bot.Env(
        advance: fn(ms) { driven_time.advance(time:, ms:) },
        recharge_ms: 0,
        settled: fn(unit_id) {
          character_support.marker_creature_settled(
            settings: started.settings,
            unit_id:,
          )
        },
      ),
    )
    as "the bot plays the tutorial to the Dorians"
  let dorian_creature = 73_491
  let assert Ok(#(giver_a, at_a)) =
    tutorial_bot.nearest(
      units: tutorial_bot.units(bot:),
      from: tutorial_bot.at(bot:),
      creatures: [dorian_creature],
    )
    as "a Dorian is in sight"
  let bot = tutorial_bot.approach_unit(bot:, at: at_a)
  let #(used, have) =
    quest_bot.use_unit(game:, have: tutorial_bot.have(bot:), unit_id: giver_a)
  assert list.contains(
    used.states,
    QuestState(quest_id: 10_529, state: 3, objective_id: 0),
  )
    as "the use of Dorian completes 10529"
  // The map's removal of a released unit is not ordered against the client's answers, so
  // this test cannot prove that none comes; that Dorian is not released is decided by
  // `objective_release_test`. Here the tutorial goes on with the Dorian the player used.
  let #(talked, have) = quest_bot.talk(game:, have:, unit_id: giver_a)
  assert talked.dialogs != [] as "the Dorian the use counted opens his dialog"
  let #(accepted, _) = quest_bot.accept(game:, have:, quest_id: 10_525)
  assert list.map(accepted.states, fn(told) { #(told.quest_id, told.state) })
    == [#(10_525, 1)]
    as "quest.in_reach: the Dorian the use counted gives 10525 in state 1"
  game_client.close(game:)
  login_support.stop(started)
}

/// The creature of this Creature2 that stands at the x and z of the place, within 0.01.
fn creature_standing_at(
  creatures creatures: List(unit_create_creature.UnitCreateCreature),
  creature_id creature_id: Int,
  place place: #(Float, Float),
) -> Result(unit_create_creature.UnitCreateCreature, Nil) {
  list.find(creatures, fn(creature) {
    let #(x, _, z) = game_client.placed_by_tail(tail: creature.tail)
    creature.creature_id == creature_id
    && float.absolute_value(x -. place.0) <. 0.01
    && float.absolute_value(z -. place.1) <. 0.01
  })
}

pub fn rescuing_an_exile_removes_the_trap_and_the_exile_for_another_player_too_then_both_return_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest 6296's objective 9659 (QuestObjective: type 12, data Creature2 27768, the
  // Bramble Trap, count 4) is credited by the go of a use of a trap, which the creature's
  // activateSpellCastTime of 2000 ms and activateSpellMaxRange of 3.0 allow. The world
  // data's rows 10449, 10451, 10453 and 10454 are four of its traps (so the objective
  // counts each unit once, not the same unit again), and rows 10603 to 10606 are the
  // Trapped Mordesh (Creature2 28112) that stand at the traps' x and z, 0.2 to 0.9 below
  // them. The use releases the trap and the Mordesh together, and 30000 ms later both are
  // back (a server choice, `used_object_release_ms`). Another player in sight is told 0x355
  // for both and 0x262 for both again.
  let time = driven_time.new()
  let started =
    start_with_world_data_on(
      folder: "test/fixture/world_data_nature",
      time:,
      adjusted: fn(settings) { settings },
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(first, first_character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 1,
    )
  let #(second, second_character) =
    new_player_at_level(
      started:,
      number: 2,
      character_name: "Ann Qu",
      class_id: 4,
      level: 1,
    )
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 6296, 1, 0, true, 0, '{0,0,0}', 0, '{0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(first_character))
    |> pog.execute(pool)
    as "the first character holds quest 6296 with nothing done"
  // The trap of row 10451 and the Mordesh of row 10604 stand at this x and z.
  let place = #(-467.3149, -2775.65)
  character_support.move_to(
    pool:,
    character_id: first_character,
    world_id: 990,
    world_zone_id: 1415,
    position: #(-465.8149, -991.1788, -2775.65),
  )
  character_support.move_to(
    pool:,
    character_id: second_character,
    world_id: 990,
    world_zone_id: 1415,
    position: #(-467.3149, -991.1788, -2767.65),
  )
  let both_in = fn(frames) {
    let creatures = game_client.creatures_created_in(frames:)
    result.is_ok(creature_standing_at(creatures:, creature_id: 27_768, place:))
    && result.is_ok(creature_standing_at(
      creatures:,
      creature_id: 28_112,
      place:,
    ))
  }
  send_play(game: first, character_id: first_character)
  let #(first_entry, first_have) =
    game_client.read_until(game: first, have: <<>>, found: both_in)
  send_play(game: second, character_id: second_character)
  let #(second_entry, second_have) =
    game_client.read_until(game: second, have: <<>>, found: both_in)
  let seen = fn(frames) {
    let creatures = game_client.creatures_created_in(frames:)
    let assert Ok(trap) =
      creature_standing_at(creatures:, creature_id: 27_768, place:)
    let assert Ok(mordesh) =
      creature_standing_at(creatures:, creature_id: 28_112, place:)
    #(trap.unit_id, mordesh.unit_id)
  }
  let #(trap, mordesh) = seen(first_entry)
  assert seen(second_entry) == #(trap, mordesh)
    as "both players are shown the same units for the trap and the Mordesh"
  let assert Ok(press) =
    cast_activate.encode(CastActivate(client_cast_id: 1, target_unit_id: trap))
    as "the right-click fits the message"
  game_client.send_world(
    game: first,
    message_id: cast_activate.message_id,
    body: press,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  assert list.any(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press on the trap is confirmed"
  // The bar runs 2000 ms (Creature2 27768's activateSpellCastTime), and the spell the trap
  // casts for a character at the start of the quest is Spell4 33673 of Spell4Base 19657,
  // castMethod 5: its go waits for the client's answer, which names the base plus one.
  let assert Ok(confirmed) =
    list.find(pressed, fn(frame) { frame.message_id == 0x07FD })
    as "the confirmation of the press"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed.body)
  driven_time.advance(time:, ms: 2000)
  let assert Ok(answer) =
    client_side_interaction_result.encode(ClientSideInteractionResult(
      cast_id: confirmed.server_cast_id,
      result: interaction_result.Succeeded,
      spell4_base_id_plus_one: 19_658,
    ))
    as "the answer fits the message"
  game_client.send_world(
    game: first,
    message_id: client_side_interaction_result.message_id,
    body: answer,
  )
  let removed_units = fn(frames) {
    game_connection_support.decoded(frames, 0x0355, unit_destroyed.decode)
    |> list.map(fn(destroyed) { destroyed.unit_id })
  }
  let gone = fn(frames) {
    let removed = removed_units(frames)
    list.contains(removed, trap) && list.contains(removed, mordesh)
  }
  let #(went, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      gone(frames) && list.any(frames, fn(frame) { frame.message_id == 0x0361 })
    })
  assert list.filter(went, fn(frame) { frame.message_id == 0x0361 })
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 6296), #(32, 1), #(32, 1)]),
      ),
    ]
    as "opcode.0x361: the go of the use counts one of objective 9659's four, in quest 6296"
  let #(seen_gone, second_have) =
    game_client.read_until(game: second, have: second_have, found: gone)
  assert list.sort(removed_units(seen_gone), int.compare)
    == list.sort([trap, mordesh], int.compare)
    as "opcode.0x355: the player who did not use the trap is told the trap and the Mordesh are gone, each once"
  // The restart timer is the release's 30000 ms, started when the units went.
  driven_time.advance(time:, ms: 30_000)
  let #(back, _) =
    game_client.read_until(game: second, have: second_have, found: both_in)
  let creatures = game_client.creatures_created_in(frames: back)
  assert result.is_ok(creature_standing_at(
      creatures:,
      creature_id: 27_768,
      place:,
    ))
    && result.is_ok(creature_standing_at(
      creatures:,
      creature_id: 28_112,
      place:,
    ))
    as "opcode.0x262: the trap and the Mordesh are created again for the other player after the release time"
  let #(first_back, _) =
    game_client.read_until(game: first, have: first_have, found: both_in)
  assert both_in(first_back)
    as "opcode.0x262: the player who used the trap is shown both again as well"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

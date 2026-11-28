//// Creatures on the whole server: the 0x0262 written for each planted spawn, the world's static
//// objects, a medic and an esper killing a planted beast, a Dagun that chases, fights, kills,
//// leashes and crashes, and the Sim-Turrets of the training simulation.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import cast_support
import character_support
import character_tables
import driven_time
import fight_bot
import fixture_tables
import game_client
import game_wire_support.{
  beast_health_in, beast_place, dagun_attack_interval_ms, dagun_z,
  enters_and_sees_the_beasts, entry_stat, finishes, holds_a_finish, index_where,
  is_near, new_player, new_player_at_level,
  on_rows_with_turrets_that_never_deflect,
  on_rows_without_paralytic_surges_recharge, press_and_fire,
  press_until_dead_reading, read_after_the_map_and_the_creature_took_it,
  send_play, start_with_creatures, start_with_world_data,
  static_objects_created_in, the_dagun_and_its_map, walk_to,
  with_world_data_on_ground, world_on, world_with_a_beast_ahead,
  world_with_a_dagun_on, world_with_beasts,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/connection/registry
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/cast/state as cast_state
import genesis_prime/message/enter_world
import genesis_prime/message/float32
import genesis_prime/message/player_health
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_create_static
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/message/unit_stealth
import genesis_prime/shared/unit_fields
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/system
import login_support
import message_support
import owned_test
import planted_table
import pog
import terrain_support

/// The messages of the Holocrypt's join: an entry burst without 0x25E.
fn holocrypt_burst_length() -> Int {
  list.length(game_client.holocrypt_entry_ids())
}

pub fn a_bot_entering_warfare_woods_is_written_one_0x262_for_each_planted_spawn_and_a_second_bot_sees_the_same_unit_ids_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = start_with_creatures(time:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(first, first_character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  character_support.move_to(
    pool:,
    character_id: first_character,
    world_id: 3460,
    world_zone_id: 5967,
    position: character_tables.exile_circle_centre(),
  )
  send_play(game: first, character_id: first_character)
  let #(_burst, have) = game_client.read_entry_kept(game: first, have: <<>>)
  let #(frames, _) =
    game_client.read_until(game: first, have:, found: fn(frames) {
      list.length(planted_creatures_in(frames:)) >= 54
    })
  let seen = planted_creatures_in(frames:)
  assert list.length(seen) == 54
    as "one 0x262 for each of the 54 spawns: the 27 Virtual Battle Beasts and the 27 Virtual Defense Daguns, all within 1024 units of the characters in Warfare Woods"
  let units = list.map(seen, fn(creature) { creature.unit_id })
  assert list.length(list.unique(units)) == 54
    && list.all(units, fn(unit_id) { unit_id > 0 && unit_id < 1_048_576 })
    as "each unit id is its own, never 0 and below 2^20"
  assert list.count(seen, fn(creature) { creature.creature_id == 73_464 }) == 27
    && list.count(seen, fn(creature) { creature.creature_id == 73_465 }) == 27
    as "opcode.0x262.creature: the Creature2 id of each spawn's creature"
  assert list.all(seen, fn(creature) {
    let values = #(
      creature.tail.display_info_id,
      creature.tail.outfit_info_id,
      creature.tail.faction_id,
      creature.tail.base_faction_id,
    )
    case creature.creature_id {
      73_464 -> values == #(26_565, 0, 1441, 1441)
      _ -> values == #(26_578, 0, 1442, 1442)
    }
  })
    as "each spawn's own values: the Battle Beast's display 26565, faction 1441 and base faction 1441, the Dagun's 26578, 1442 and 1442, and no outfit (the world database's rows and migration 0008's)"
  assert list.all(seen, fn(creature) {
    list.contains(
      creature.tail.stats,
      unit_fields.integer_stat(stat_id: 15, value: 1),
    )
  })
    as "unit.weapon_sheathed: each creature at rest is created sheathed, stat 15 in the integer form"
  let #(second, second_character) =
    new_player(started:, number: 2, character_name: "Ann Qu")
  character_support.move_to(
    pool:,
    character_id: second_character,
    world_id: 3460,
    world_zone_id: 5967,
    position: character_tables.exile_circle_centre(),
  )
  send_play(game: second, character_id: second_character)
  let #(_burst, have) = game_client.read_entry_kept(game: second, have: <<>>)
  let #(frames, _) =
    game_client.read_until(game: second, have:, found: fn(frames) {
      list.length(planted_creatures_in(frames:)) >= 54
    })
  assert list.sort(
      list.map(planted_creatures_in(frames:), fn(creature) { creature.unit_id }),
      int.compare,
    )
    == list.sort(units, int.compare)
    as "two players see one unit id for each creature"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The creatures the frames create that are the planted Virtual Battle Beasts and
/// Virtual Defense Daguns; the creatures a kill objective's marker places in the same
/// world arrive in the same range and are not among them.
fn planted_creatures_in(
  frames frames: List(Frame),
) -> List(unit_create_creature.UnitCreateCreature) {
  list.filter(game_client.creatures_created_in(frames:), fn(creature) {
    creature.creature_id == 73_464 || creature.creature_id == 73_465
  })
}

pub fn the_creatures_of_two_kill_objectives_on_one_marker_are_sent_once_each_on_the_ground_test() -> Nil {
  use <- owned_test.run(60_000)
  // Objectives 4564 and 4565 (quests 3479 and 3480) are type 8, count 8, on markers
  // 12155 to 12158 of World 426 and name Creature2 13117 between them (TargetGroup
  // 7288 holds 1463, whose creatures include 13117 and 13959). Marker 12157's
  // centre is (4049.0889, -735.689, -5470.0864) with radius 78.62, so its two ring
  // slots are (4088.4007, -5470.0864) and (4009.7771, -5470.0864). World 426's
  // retail ground there is -740.371 at the first slot, 4.68 below the centre's
  // height; the planted ground has a chunk for the centre, one for each slot and
  // flat ground elsewhere (raw 10498 is the height -735.71, 10461 is -740.335 and
  // 10480 is -737.96). The player stands 15 from the first slot (the report of the
  // yeti hanging in the air).
  let centre = #(4049.0889, -5470.0864, 10_498)
  let first = #(4088.4007, -5470.0864, 10_461)
  let second = #(4009.7771, -5470.0864, 10_480)
  let time = driven_time.new()
  let started =
    login_support.start_with(
      time:,
      change: with_world_data_on_ground(
        folder: "test/fixture/world_data_yeti",
        terrain: terrain_support.reader_with_chunks(chunks: [
          centre,
          first,
          second,
        ]),
        adjusted: fn(settings) { settings },
      ),
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let #(game, character) =
    new_player(started:, number: 1, character_name: "Zed Qu")
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 426,
    world_zone_id: 651,
    position: #(4083.6, -741.3, -5484.4),
  )
  send_play(game:, character_id: character)
  let started_units =
    dict.size(
      content_spawn.world(key: started.settings.world.spawns, world_id: 426).by_id,
    )
  let #(_burst, have) = game_client.read_entry_kept(game:, have: <<>>)
  let #(frames, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.length(game_client.creatures_created_in(frames:)) >= started_units
    })
  let yetis =
    list.filter(game_client.creatures_created_in(frames:), fn(creature) {
      creature.creature_id == 13_117
    })
    |> list.map(fn(creature) { game_client.placed_by_tail(tail: creature.tail) })
  let at = fn(slot: #(Float, Float, Int)) {
    list.filter(yetis, fn(place) {
      float.absolute_value(place.0 -. slot.0) <. 0.01
      && float.absolute_value(place.2 -. slot.1) <. 0.01
    })
  }
  let assert [on_first] = at(first)
    as "one 0x262 of Creature2 13117 at marker 12157's first ring slot"
  let assert [on_second] = at(second)
    as "one 0x262 of Creature2 13117 at marker 12157's second ring slot"
  assert float.absolute_value(
      on_first.1 -. terrain_support.height(raw: first.2),
    )
    <. 0.01
    as "the first slot's yeti is sent at the ground read there, not at the marker's height"
  assert float.absolute_value(
      on_second.1 -. terrain_support.height(raw: second.2),
    )
    <. 0.01
    as "the second slot's yeti is sent at the ground read there"
  game_client.close(game:)
  login_support.stop(started)
}

/// The Creature2 ids of the static objects the frames create, sorted: the 0x262 of a
/// type 8, 10, 11, 13 or 32 object (`unit_create_static`), as the client reads them.
fn static_objects_in(frames frames: List(Frame)) -> List(Int) {
  list.map(static_objects_created_in(frames:), fn(object) { object.creature_id })
  |> list.sort(int.compare)
}

/// A new character of the faction at the position in World 3460, entered as the
/// player of the account number `number`, and every message the server wrote up to
/// the pong of a ping sent after the 0x262 of each of `anchors`, units that no
/// prerequisite hides from the character. The map writes its objects in one tell,
/// after its reply to the join and from another process than the connection's
/// pong, so the pong alone does not follow them; a creature of the map writes its
/// own 0x262 from its own process, so it too is named among the anchors to be
/// followed. The anchors' 0x262 show the tell has been taken, and the connection
/// writes all of it before it takes the ping.
fn entering_3460_as(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  faction_id faction_id: Int,
  at position: #(Float, Float, Float),
  anchors anchors: List(Int),
) -> List(Frame) {
  let #(game, character_id) = new_player(started:, number:, character_name:)
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(_) =
    pog.query("update character set faction_id = $2 where character_id = $1")
    |> pog.parameter(pog.int(character_id))
    |> pog.parameter(pog.int(faction_id))
    |> pog.execute(pool)
    as "the character took its faction"
  character_support.move_to(
    pool:,
    character_id:,
    world_id: 3460,
    world_zone_id: 6009,
    position:,
  )
  send_play(game:, character_id:)
  let #(burst, have) = game_client.read_entry_kept(game:, have: <<>>)
  let #(until_anchor, have) =
    read_until_objects(game:, have:, creature_ids: anchors, read: burst)
  let #(after, _) = game_client.read_until_pong(game:, have:, number: 1)
  game_client.close(game:)
  list.append(until_anchor, after)
}

/// Reads messages until the 0x262 of a static object with each of these Creature2 ids
/// has been read (an id listed twice, twice), which `read` may already hold.
fn read_until_objects(
  game game: game_client.Game,
  have have: BitArray,
  creature_ids creature_ids: List(Int),
  read read: List(Frame),
) -> #(List(Frame), BitArray) {
  use <- bool.guard(
    when: includes_each(
      read: static_objects_in(frames: read),
      wanted: creature_ids,
    ),
    return: #(read, have),
  )
  let #(frame, rest) = game_client.next(game:, have:)
  read_until_objects(
    game:,
    have: rest,
    creature_ids:,
    read: list.append(read, [frame]),
  )
}

/// Whether `read` holds each of `wanted`, an id listed twice twice.
fn includes_each(read read: List(Int), wanted wanted: List(Int)) -> Bool {
  list.all(wanted, fn(id) {
    list.count(read, fn(seen) { seen == id })
    >= list.count(wanted, fn(listed) { listed == id })
  })
}

/// The tutorial's two Sim-Turrets, each twice: objectives 21288 and 21316 count 2 of
/// Creature2 73494 and 74862, which the world data of this test holds no row of, so the
/// load places both at their markers (WorldLocation2 51671, 52753, 52902 and 52903, all
/// within the sight range of 1024 units of the Start Arrow's row 29054 and past it from
/// the mounts). They start as creatures of unit type 13, and the 0x262 of each is
/// written to a character in sight of them, whatever its faction.
const sim_turrets = [73_494, 73_494, 74_862, 74_862]

/// The tutorial's three mines, each twice: Creature2 73463, 73667 and 73668 each link to
/// an Exile objective (21287, 21340, 21318: markers 51662, 51663, 51664) and a Dominion
/// objective (21313, 21314, 21315: markers 52899, 52900, 52901), and the world data of
/// this test holds no row of them, so the load places each at both of its markers (a
/// click target with no spawn stands at its objective's marker). Every marker is within
/// the sight range of 1024 units of the Start Arrow's row 29054 (the farthest, 51664 at
/// x -119.41, z 424.96, is 924 units off it), and a mine's visibility prerequisite hides
/// none of them from an Exile with no tutorial quest.
const tutorial_mines = [73_463, 73_463, 73_667, 73_667, 73_668, 73_668]

/// The ids with the Sim-Turrets and the mines, sorted as `static_objects_in` sorts them.
fn with_the_sim_turrets_and_mines(ids ids: List(Int)) -> List(Int) {
  list.flatten([ids, sim_turrets, tutorial_mines]) |> list.sort(int.compare)
}

pub fn entering_world_3460_writes_no_start_arrow_and_mount_displays_only_to_an_exile_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started =
    start_with_world_data(folder: "test/fixture/world_data_tutorial", time:)
  let at_the_arrows = #(71.4148, -855.3006, -479.419)
  let at_the_mounts = #(1381.03, -495.32764, 213.793)
  let at_the_arrows_ids = with_the_sim_turrets_and_mines(ids: [73_619])
  let exile =
    static_objects_in(frames: entering_3460_as(
      started:,
      number: 1,
      character_name: "Zed Qu",
      faction_id: 167,
      at: at_the_arrows,
      anchors: at_the_arrows_ids,
    ))
  assert exile == at_the_arrows_ids
    as "an Exile with no tutorial quest at the Start Arrow's row 29054: the hologram 73619 (Creature2 prerequisite 41795, which passes for a player under no cast) is written and the Start Arrow 73707 (prerequisite 41803: neither quest 10527 nor 10532 is open) is not"
  let exile_at_the_mounts =
    static_objects_in(
      frames: entering_3460_as(
        started:,
        number: 2,
        character_name: "Ann Qu",
        faction_id: 167,
        at: at_the_mounts,
        anchors: [74_787],
      ),
    )
  assert exile_at_the_mounts == [74_781, 74_782, 74_783, 74_784, 74_787]
    as "an Exile at the mounts: the four EXILE mount displays are written (Creature2 prerequisite 19, base faction 167), and 74787, which has none"
  let dominion_at_the_mounts =
    static_objects_in(
      frames: entering_3460_as(
        started:,
        number: 3,
        character_name: "Cal Qu",
        faction_id: 166,
        at: at_the_mounts,
        anchors: [74_787],
      ),
    )
  assert dominion_at_the_mounts == [74_787]
    as "a Dominion character at the same place is written 74787, which has no visibility prerequisite, and none of the mount displays (Faction2 166 fails prerequisite 19)"
  login_support.stop(started)
}

/// Plays a new player's character into the world and reads until the Beast's 0x262
/// arrives: the burst and the creature, and the bytes beyond them.
fn enters_and_sees_the_beast(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, List(Frame), BitArray) {
  enters_and_sees_the_beasts(
    started:,
    number:,
    character_name:,
    class_id: 4,
    beasts: 1,
  )
}

pub fn a_medic_kills_a_planted_beast_with_paralytic_surge_and_a_watcher_reads_the_same_fight_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_a_beast_ahead(tables:, time:)
  let #(first, first_frames, first_have) =
    enters_and_sees_the_beast(started:, number: 1, character_name: "Zed Qu")
  let #(second, second_frames, second_have) =
    enters_and_sees_the_beast(started:, number: 2, character_name: "Ann Qu")
  let assert [beast, ..] =
    game_client.creatures_created_in(frames: first_frames)
  let beast_unit = beast.unit_id
  assert list.map(
      game_client.creatures_created_in(frames: second_frames),
      fn(unit) { unit.unit_id },
    )
    == [beast_unit]
    as "both players are shown the same creature"
  let own_place =
    game_client.placed_at(unit: game_client.unit_create_player_in(
      frames: first_frames,
    ))
  let toward =
    game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    ))
  // The caster turns its back on the Beast: the press strikes nothing.
  game_client.face(game: first, yaw: toward +. 3.1415927, clock: 100)
  let #(away, first_have) =
    press_and_fire(
      time:,
      game: first,
      have: first_have,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      cast_id: 1,
    )
  assert holds_a_finish(frames: away)
    as "the press's cast finished once the clock has fired its timer"
  assert list.map(game_client.go_targets_in(frames: away), fn(go) { go.1 })
    == [[]]
    && game_client.health_in(frames: away) == []
    as "a press with its back to the Beast strikes nobody: the go names no target and no 0x937 follows (the facing is the last kind 14 yaw)"
  // Facing the Beast, it presses until the Beast dies.
  game_client.face(game: first, yaw: toward, clock: 200)
  let #(first_have, healths, fight) =
    press_until_dead_reading(
      time:,
      game: first,
      have: first_have,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      lingers_ms: fight_bot.paralytic_surge_lingers_ms,
      beast: beast_unit,
      cast_id: 2,
    )
  assert healths
    == healths_after(
      hits: critical_hits_on(beast_unit, in: fight),
      normal: 14,
      critical: 21,
    )
    as "a Medic of level 1 with the Novice gear (Assault Rating 203.0625, Support Rating 55.6875: Assault Power 50.77, Support Power 13.92): a hit of Paralytic Surge is 0.0935 x 50.77 + 0.0935 x 13.92 = 6.05, rounded to 6, plus 8.14 for the level, 14.14, rounded to 14 (Spell4Effects 96125, 0x140565600); the Beast has 52 health, never deflects, and each hit is 14, or 21 (14 x 1.5, UnitProperty2 127's default) when its combat result is a critical hit (a player's chance is 0.05, CreatureLevel row 101), so the health is 38, 24, 10 and 0 when none is, each 0x937 held until its go"
  let #(watched, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(game_client.deaths_in(frames:), fn(death) {
        death == #(beast_unit, True)
      })
      && list.contains(
        game_client.go_targets_in(frames:),
        #(last_cast_of(frames), [beast_unit]),
      )
    })
  let seen_health =
    list.filter_map(game_client.health_in(frames: watched), fn(health) {
      case health.0 == beast_unit {
        True -> Ok(health.1)
        False -> Error(Nil)
      }
    })
  assert seen_health == healths
    as "the watcher reads the same 0x937 the caster did, then 0x88c"
  assert list.contains(
    game_client.go_targets_in(frames: watched),
    #(last_cast_of(watched), [beast_unit]),
  )
    as "the watcher reads the same 0x7f4, naming the Beast, for the cast it was sent the start of (opcode.0x7ff, opcode.0x7f4)"
  let assert Ok(last) = list.last(game_client.health_in(frames: watched))
  assert last == #(beast_unit, 0, True)
    as "opcode.0x937: health 0 with the dead bit, from the creature itself"
  // The creature stands again after its respawn time, 1000 ms from the kill, which
  // the clock moves on by: 0x355, then a full 0x262. The creature sends its news
  // before it starts the corpse's timer, which the advance's barrier waits for.
  driven_time.advance(time:, ms: 1000)
  let #(after_first, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  let #(after_second, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  list.each([after_first, after_second], fn(frames) {
    assert list.contains(game_client.removals_in(frames:), beast_unit)
      && list.map(game_client.creatures_created_in(frames:), fn(unit) {
        unit.unit_id
      })
      == [beast_unit]
      as "death.creature_respawn: 0x355, then a 0x262 with the same unit id, to each viewer"
  })
  // The picture of the respawned Beast is alive again: a press strikes it.
  let #(_, after_respawn, respawn_hit) =
    press_until_a_hit(
      time:,
      game: first,
      have: first_have,
      bag_index: 2,
      cast_ms: fight_bot.paralytic_surge_cast_ms,
      beast: beast_unit,
      cast_id: 100,
    )
  assert after_respawn == 52 - damage_of_tick(critical: respawn_hit)
    as "the respawned Beast has its 52 health again and was struck for 14, or 21 when the hit was critical (a player's chance is 0.05, CreatureLevel row 101), so the caster's picture holds it alive again: the 0x355 cleared it and the respawn's 0x262 restored it"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn three_ticks_reach_the_client_and_health_falls_three_times_test() -> Nil {
  use <- owned_test.run(120_000)
  // No level-1 ability holds a periodic damage row (the client's level-1 tree spells),
  // so Paralytic Surge's damage row 96125 (targetFlags 4, the Medic's bag index 2) is
  // given a tickTime of 2000 and a durationTime of 6000: three ticks, 2000, 4000 and
  // 6000 ms after the go (`Spell4Effects.effectType.8.periodic`).
  use tables <- fixture_tables.changed(
    table: "Spell4Effects",
    id: 96_125,
    with: [
      #("tickTime", planted_table.Integer(2000)),
      #("durationTime", planted_table.Integer(6000)),
    ],
  )
  let time = driven_time.new()
  let started = world_with_a_beast_ahead(tables:, time:)
  let #(game, frames, have) =
    enters_and_sees_the_beast(started:, number: 1, character_name: "Zed Qu")
  let assert Ok(connection) =
    registry.find_named(started.settings.registry, "zed qu")
  let assert [beast] = game_client.creatures_created_in(frames:)
  let beast_unit = beast.unit_id
  let own_place =
    game_client.placed_at(unit: game_client.unit_create_player_in(frames:))
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    )),
    clock: 100,
  )
  game_client.press_ability(game:, client_cast_id: 1, bag_index: 2, target: 0)
  let #(taken, have) = game_client.read_until_pong(game:, have:, number: 1)
  driven_time.advance(time:, ms: fight_bot.paralytic_surge_cast_ms)
  // The go strikes the Beast as the press is taken, with no timer on the way: the
  // advance's barrier waits for the Beast's answer, the 0x7f4 it lets out and the
  // Beast's 0x937, written before the pong.
  let #(went, have) = game_client.read_until_pong(game:, have:, number: 2)
  let at_go = list.append(taken, went)
  let assert Ok(cast_id) =
    game_client.confirmed_cast_of(frames: at_go, client_cast_id: 1)
    as "opcode.0x7fd: the press is answered with its server cast id"
  assert list.contains(
      game_client.casts_in(frames: at_go),
      game_client.CastWent(cast_id:, phase: 0),
    )
    && !finishes(frames: at_go, cast_id:)
    as "opcode.0x7f4: the press goes off at once (Spell4.42352: no cast time), and its cast does not end with the go"
  assert game_client.ticks_in(frames: at_go) == []
    && list.all(beast_health_in(frames: at_go, beast: beast_unit), fn(health) {
      health == 52
    })
    as "the go strikes no description of the ticking row (the issue's first acceptance check): no 0x7f8, and the Beast keeps its 52 health"
  // The clock fires each tick's timer; the Beast answers the tick's strike on its own
  // process, and the barrier holds the advance until each frame it caused is written.
  let #(rounds, have) =
    list.fold([3, 4, 5], #([], have), fn(so_far, number) {
      let #(rounds, have) = so_far
      driven_time.advance(time:, ms: 2000)
      let #(round, have) = game_client.read_until_pong(game:, have:, number:)
      #(list.append(rounds, [round]), have)
    })
  // Each tick's crit roll is from the connection's random seed, so a tick is a
  // critical hit or not by chance: 14, or 14 x 1.5 = 21 when it is (the player's
  // severity is UnitProperty2 127's default, 1.5, and its chance 0.05, CreatureLevel
  // row 101).
  let tick_damages =
    list.map(rounds, fn(round) {
      let assert [critical] = game_client.critical_ticks_in(frames: round)
        as "one 0x7f8 in each round"
      assert game_client.ticks_in(frames: round)
        == [#(cast_id, 96_125, beast_unit, [damage_of_tick(critical:)])]
        as "opcode.0x7f8: one tick each 2000 ms, naming the go's cast, the row 96125 and the Beast, with one damage description; a hit of Paralytic Surge by a Medic of level 1 with the Novice gear is 14 (Spell4Effects 96125, 0x140565600), or 21 when critical, worked out from the caster at the tick, and the Beast never deflects"
      damage_of_tick(critical:)
    })
  assert list.map(rounds, beast_health_in(frames: _, beast: beast_unit))
    == list.scan(tick_damages, 52, fn(health, damage) { health - damage })
    |> list.map(fn(health) { [health] })
    as "opcode.0x937 after each 0x7f8, from the creature itself: the Beast's 52 health falls by its tick's damage, three times"
  let assert [first_round, second_round, last_round] = rounds
  assert !finishes(frames: first_round, cast_id:)
    && !finishes(frames: second_round, cast_id:)
    as "the cast is held past Paralytic Surge's own end, 2700 ms after the go, while its row still ticks"
  let tick_at =
    index_where(frames: last_round, found: fn(frame) {
      game_client.ticks_in(frames: [frame]) != []
    })
  let finish_at =
    index_where(frames: last_round, found: fn(frame) {
      finishes(frames: [frame], cast_id:)
    })
  assert tick_at >= 0 && finish_at > tick_at
    as "opcode.0x7fe: the cast ends after its last tick's 0x7f8 (cast.miss_after_finish)"
  assert list.filter(
      driven_time.pending_of(time:, owner: connection),
      cast_state.owns,
    )
    == []
    as "no tick timer and no timer of a cast is left on the connection once the cast has ended"
  driven_time.advance(time:, ms: 2000)
  let #(after, _) = game_client.read_until_pong(game:, have:, number: 6)
  assert game_client.ticks_in(frames: after) == []
    && beast_health_in(frames: after, beast: beast_unit) == []
    as "the ticks stop with the row's three: no 0x7f8 and no fall of the Beast's health 2000 ms later"
  game_client.close(game:)
  login_support.stop(started)
}

/// The health a Paralytic Surge tick of the level-1 Medic takes: 14, or 21 when critical.
fn damage_of_tick(critical critical: Bool) -> Int {
  use <- bool.guard(critical, 21)
  14
}

/// How many times the frames start Telekinetic Strike's Psi Point child, 30900, under
/// the spell (0x7ff).
fn psi_children(frames frames: List(Frame)) -> Int {
  list.count(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastStarted(spell4_id: 30_900, parent_spell4_id: 32_893, ..) ->
        True
      game_client.CastStarted(..)
      | game_client.CastRefused(..)
      | game_client.CastConfirmed(..)
      | game_client.CastWent(..)
      | game_client.ThresholdOpened(..)
      | game_client.ThresholdIndex(..)
      | game_client.ThresholdClosed(..)
      | game_client.ThresholdEnded(..)
      | game_client.CastFinished(..) -> False
    }
  })
}

/// The cast time of Telekinetic Strike (Spell4 32893, castTime 1250): its go is that long
/// after the press.
const telekinetic_strike_cast_ms = 1250

/// How long after its go a hit of Telekinetic Strike lasts: none, the cast ends with
/// its go (its effects 62159 and 62204 have no durationTime).
const telekinetic_strike_lingers_ms = 0

pub fn an_espers_telekinetic_strike_hits_only_the_beast_inside_its_never_drawn_telegraph_and_a_watcher_reads_the_same_fight_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_beasts(
      places: [beast_place(x: 1.5, z: 0.5), beast_place(x: 11.5, z: 3.5)],
      tables: character_tables.shared(),
      time:,
    )
  let #(first, first_frames, first_have) =
    enters_and_sees_the_beasts(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 3,
      beasts: 2,
    )
  let #(second, second_frames, second_have) =
    enters_and_sees_the_beasts(
      started:,
      number: 2,
      character_name: "Ann Qu",
      class_id: 4,
      beasts: 2,
    )
  let beast_at_x = fn(frames, x) {
    let assert [beast] =
      list.filter(game_client.creatures_created_in(frames:), fn(unit) {
        game_client.placed_by_tail(tail: unit.tail).0 == x
      })
      as "one Beast stands at this x"
    beast.unit_id
  }
  let ahead = beast_at_x(first_frames, 1.5)
  let beside = beast_at_x(first_frames, 11.5)
  assert beast_at_x(second_frames, 1.5) == ahead
    && beast_at_x(second_frames, 11.5) == beside
    as "both players are shown the same two creatures"
  let own_place =
    game_client.placed_at(unit: game_client.unit_create_player_in(
      frames: first_frames,
    ))
  let toward =
    game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    ))
  // The caster turns its back on the Beasts: the press strikes nothing.
  game_client.face(game: first, yaw: toward +. 3.1415927, clock: 100)
  let #(away, first_have) =
    press_and_fire(
      time:,
      game: first,
      have: first_have,
      bag_index: 0,
      cast_ms: telekinetic_strike_cast_ms,
      cast_id: 1,
    )
  assert holds_a_finish(frames: away)
    as "the press's cast finished once the clock has moved on by its cast time"
  assert list.map(game_client.go_targets_in(frames: away), fn(go) { go.1 })
    == [[]]
    && game_client.health_in(frames: away) == []
    && list.all(game_client.casts_in(frames: away), fn(event) {
      case event {
        game_client.CastStarted(spell4_id:, ..) -> spell4_id == 32_893
        game_client.CastRefused(..)
        | game_client.CastConfirmed(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> True
      }
    })
    as "a press with its back to the Beasts strikes nobody: the go names no target, no 0x937 follows and Telekinetic Strike's Proxy 62204, aimed at the area (targetFlags 4), starts no child"
  // Facing the Beast ahead, it presses until that Beast dies.
  game_client.face(game: first, yaw: toward, clock: 200)
  let #(first_have, healths, fight) =
    press_until_dead_reading(
      time:,
      game: first,
      have: first_have,
      bag_index: 0,
      cast_ms: telekinetic_strike_cast_ms,
      lingers_ms: telekinetic_strike_lingers_ms,
      beast: ahead,
      cast_id: 2,
    )
  assert healths
    == healths_after(
      hits: critical_hits_on(ahead, in: fight),
      normal: 35,
      critical: 53,
    )
    as "an Esper of level 1 with the Novice gear (Assault Rating 203.0625, Assault Power 50.77): a hit of Telekinetic Strike is 0.336 x 50.77 = 17.06, rounded to 17, plus 18.0 for the level, 35 (Spell4Effects 62159, 0x140565600); the Beast has 52 health and never deflects, so the health is 17 and then 0 when no hit is critical; a critical hit is 1.5 times that, 52 or 53, so 53 is used: 52 or more (UnitProperty2 127's default 1.5, a player's chance 0.05, CreatureLevel row 101), which kills at once"
  // Two hits kill it, or one when that hit is critical.
  let hit_count = list.length(healths)
  let #(watched, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(game_client.deaths_in(frames:), fn(death) {
        death == #(ahead, True)
      })
      && list.count(game_client.go_targets_in(frames:), fn(go) {
        go.1 == [ahead]
      })
      == hit_count
      && psi_children(frames:) == hit_count
    })
  // The Beast ahead fights back every 1500 ms with its own attack, Spell4 5649,
  // whose go names the caster; the kill lands 1250 ms after the first hit, before
  // its first 1500 ms tick, so it has not swung yet, and only the casts of
  // Telekinetic Strike are read here.
  let strike_cast_ids =
    list.filter_map(game_client.casts_in(frames: watched), fn(event) {
      case event {
        game_client.CastStarted(cast_id:, spell4_id: 32_893, ..) -> Ok(cast_id)
        game_client.CastStarted(..)
        | game_client.CastRefused(..)
        | game_client.CastConfirmed(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> Error(Nil)
      }
    })
  let strike_goes =
    list.filter(game_client.go_targets_in(frames: watched), fn(go) {
      list.contains(strike_cast_ids, go.0)
    })
  assert strike_goes != []
    && list.all(strike_goes, fn(go) { go.1 == [] || go.1 == [ahead] })
    as "the Beast 10 m to the side is within the area row's 30 m all round but outside the never-drawn telegraph 2169, a rectangle 3 m wide ahead of the caster grown by the Beast's hit radius 3 (Spell4.32893.area): no go of a Telekinetic Strike names it"
  assert list.filter_map(game_client.health_in(frames: watched), fn(health) {
      case health.0 == beside {
        True -> Ok(health.1)
        False -> Error(Nil)
      }
    })
    == []
    && !list.contains(game_client.removals_in(frames: watched), beside)
    as "the Beast to the side is struck by none, shown no health and never removed"
  assert list.filter_map(game_client.health_in(frames: watched), fn(health) {
      case health.0 == ahead {
        True -> Ok(health.1)
        False -> Error(Nil)
      }
    })
    == healths
    as "the watcher reads the same 0x937 the caster did, then 0x88c"
  assert psi_children(frames: watched) == hit_count
    as "Proxy 62204 starts the Psi Point child 30900 on each struck unit (Spell4Effects.targetFlags 4): one child for each hit"
  // The Beast stands again after its respawn time, 1000 ms from the kill, which the
  // clock moves on by: 0x355, then a full 0x262.
  driven_time.advance(time:, ms: 1000)
  let #(after_first, _) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  let #(after_second, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      game_client.removals_in(frames:) != []
      && game_client.creatures_created_in(frames:) != []
    })
  list.each([after_first, after_second], fn(frames) {
    assert game_client.removals_in(frames:) == [ahead]
      && list.map(game_client.creatures_created_in(frames:), fn(unit) {
        unit.unit_id
      })
      == [ahead]
      as "death.creature_respawn: 0x355, then a 0x262 with the same unit id, to each viewer, for the Beast that died only"
  })
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The id of the last cast the frames start (0x7ff).
fn last_cast_of(frames: List(Frame)) -> Int {
  let assert Ok(game_client.CastStarted(cast_id:, ..)) =
    list.filter(game_client.casts_in(frames:), fn(event) {
      case event {
        game_client.CastStarted(..) -> True
        game_client.CastRefused(..)
        | game_client.CastConfirmed(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> False
      }
    })
    |> list.last
    as "the watcher was sent a cast's start"
  cast_id
}

/// Presses the ability of the bag index until a press hits the Beast (a deflected one
/// is shown by a 0x7fb and strikes again), and gives the Beast's health after the hit
/// and whether that hit was critical.
fn press_until_a_hit(
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  bag_index bag_index: Int,
  cast_ms cast_ms: Int,
  beast beast: Int,
  cast_id cast_id: Int,
) -> #(BitArray, Int, Bool) {
  let #(frames, have) =
    press_and_fire(time:, game:, have:, bag_index:, cast_ms:, cast_id:)
  assert game_client.health_in(frames:) != []
    || game_client.missed_in(frames:) != []
    as "the press's hit or miss is written once the clock has fired its timer"
  case
    list.find(game_client.health_in(frames:), fn(health) { health.0 == beast })
  {
    Ok(health) -> {
      let assert [critical] = critical_hits_on(beast, in: frames)
        as "one hit on the Beast"
      #(have, health.1, critical)
    }
    Error(Nil) ->
      press_until_a_hit(
        time:,
        game:,
        have:,
        bag_index:,
        cast_ms:,
        beast:,
        cast_id: cast_id + 1,
      )
  }
}

/// Whether each hit of the frames on the unit was a critical hit, in order.
fn critical_hits_on(unit: Int, in frames: List(Frame)) -> List(Bool) {
  game_client.fight_in(frames:)
  |> list.flat_map(fn(event) {
    case event {
      game_client.Went(targets:, ..) -> targets
      _ -> []
    }
  })
  |> list.filter(fn(target) { target.0 == unit })
  |> list.flat_map(fn(target) { list.map(target.1, fn(blow) { blow.critical }) })
}

/// The Beast's health after each hit, from its 52, a hit being `normal` or, when
/// critical, `critical`, and never below 0.
fn healths_after(
  hits hits: List(Bool),
  normal normal: Int,
  critical critical: Int,
) -> List(Int) {
  list.scan(hits, 52, fn(health, is_critical) {
    int.max(
      health
        - case is_critical {
        True -> critical
        False -> normal
      },
      0,
    )
  })
}

// ------------------------------------------- a creature fights back, on the whole server
//
// Expected values come from the design of step F (the Design artifact of issue
// 367: its CI bot and its process tests 20, 21 and 22) and these places. The
// tests' characters are of the Dominion (faction 166), so the planted creature is
// a Virtual Defense Dagun, hostile to the Dominion (Faction2Relationship 1442-166
// level 0, `Creature2.73465`), with the Battle Beast's 52 health and attack: spell
// 5649's effect 184741 for 12 (`Spell4Effects.184741`) every attack interval of the
// creature kinds (a server choice: migration 0010; `spawn_support.kinds`), its own
// reach 5.0 + 2.0, run speed 10.0 (`0x1405b45e0`). The aggro range
// is 10 and the leash range 55 (migration 0010). A Medic of level 1 has 736 health
// and a shield of 450 (`player.level1_gear_properties`). The 0x908, 0x90a, 0x89a,
// 0x938, 0x92f and 0x638 are read as the client reads them (`opcode.0x908`,
// `opcode.0x90a`, `opcode.0x89a`, `opcode.0x938`, `opcode.0x92f`,
// `movement_command.kind_4`).

/// Returns when the first creature of the map, unit `unit_id`, has taken all it was
/// sent, for a test whose next step is an input, not an advance (an advance waits
/// for the participants itself): a creature's frames are sent before its step's
/// timer is started.
fn the_creature_has_taken_what_it_was_sent(
  started started: login_support.Started,
  unit_id unit_id: Int,
) -> Nil {
  let #(_, creature) = the_dagun_and_its_map(started:, dagun: unit_id)
  driven_time.settled(creature)
}

/// A Medic of level 1 played in, its 0x262 and the Dagun's read, and ready: its
/// client's first 0xF2 sent.
fn a_ready_medic(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, Int, Int, BitArray) {
  let #(game, frames, have) =
    a_ready_player(started:, number:, character_name:, class_id: 4)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let assert [dagun] = game_client.creatures_created_in(frames:)
  #(game, own, dagun.unit_id, have)
}

/// As `a_ready_medic`, a Stalker.
fn a_ready_stalker(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
) -> #(game_client.Game, Int, Int, BitArray) {
  let #(game, frames, have) =
    a_ready_player(started:, number:, character_name:, class_id: 5)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let assert [dagun] = game_client.creatures_created_in(frames:)
  #(game, own, dagun.unit_id, have)
}

/// A player of the class, of level 1, played in, its entry and the Dagun's 0x262
/// read, and ready: its client's first 0xF2 sent. The frames read and the bytes
/// kept.
fn a_ready_player(
  started started: login_support.Started,
  number number: Int,
  character_name character_name: String,
  class_id class_id: Int,
) -> #(game_client.Game, List(Frame), BitArray) {
  let #(game, frames, have) =
    enters_and_sees_the_beasts(
      started:,
      number:,
      character_name:,
      class_id:,
      beasts: 1,
    )
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: 1100))
  game_client.send_world(game:, message_id: terrain_loaded.message_id, body:)
  #(game, frames, have)
}

/// Reads until the fight's frames hold what `found` looks for.
fn read_fight(
  game game: game_client.Game,
  have have: BitArray,
  found found: fn(List(game_client.FightEvent)) -> Bool,
) -> #(List(game_client.FightEvent), BitArray) {
  let #(frames, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      found(game_client.fight_in(frames:))
    })
  #(game_client.fight_in(frames:), have)
}

/// Whether the Dagun has been sent a path among the events: a 0x638 with a kind 4 command.
fn dagun_runs(
  events events: List(game_client.FightEvent),
  dagun dagun: Int,
) -> Bool {
  list.any(game_client.moves_of(events:, unit: dagun), fn(move) {
    list.contains(move.0, 4)
  })
}

/// Whether a 0x638 of `unit` among the events leaves it at z: a path's end, or the
/// place a leash in the instant of the chase puts it at.
fn leaves_unit_at(
  events events: List(game_client.FightEvent),
  unit unit: Int,
  z z: Float,
) -> Bool {
  list.any(game_client.moves_of(events:, unit:), fn(move) {
    move.1 == Some(#(1.5, 2.5, z))
  })
}

pub fn a_bot_entering_a_daguns_ring_is_targeted_and_chased_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // The smoke test of the whole server: the aggro and the chase come at the
  // move, with no tick to wait for. The strike, the shield and the leash are driven
  // with the creature's timers in the test of both rules together
  // (game_connection_fight_test, `a_beasts_aggro_strike_and_leash_...`).
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  // Into the ring: 9 units from the Dagun, beyond its reach of 7.
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(fight, _) =
    read_fight(game:, have:, found: fn(events) {
      dagun_runs(events:, dagun:)
      && list.contains(
        events,
        game_client.InCombat(unit_id: own, in_combat: True),
      )
    })
  assert list.contains(
    fight,
    game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
  )
    as "0x908: the Dagun targets the bot with the aggro threat 1"
  assert list.contains(
      fight,
      game_client.InCombat(unit_id: dagun, in_combat: True),
    )
    && list.contains(fight, game_client.InCombat(unit_id: own, in_combat: True))
    as "both 0x89a: the Dagun's and the bot's own"
  let assert [#(turn_kinds, _), #(kinds, ends_at), ..] =
    game_client.moves_of(events: fight, unit: dagun)
    as "the Dagun turns, then runs"
  assert turn_kinds == [0, 18]
    as "the turn goes before the path: kind 0, then kind 18 naming the bot (a kind 4 path leaves the rotation)"
  assert kinds == [0, 4, 10, 13, 18, 26]
    as "the chase: kind 0, the kind 4 path, then the defaults for the velocity, move and state with kind 18 for the bot in place of kind 21, so the Dagun goes on facing the bot after it stops, and no kind 11 or kind 24"
  let assert [#(1, []), #(1, []), ..] =
    game_client.ground_lift_of(events: fight, unit: dagun)
    as "unit.ground_lift.server_commands: the turn and the run both keep the second bit 1, and neither holds a kind 24, the run's state coming from the state default"
  assert ends_at == Some(#(1.5, 2.5, dagun_z +. 9.0 -. 3.5))
    as "to the bot less half the Dagun's reach of 7 (chase_stop_fraction 0.5)"
  game_client.close(game:)
  login_support.stop(started)
}

/// The Stalker's ability bag index of Stealth, Spell4 46073: its press starts Stealth
/// 38784 and, when the caster is stealthed, its Cancel 38783 (Spell4Effects 107792 and
/// 107793, behind Prerequisites 7050 and 8127).
const stealth_index = 3

/// The recharge of the Stealth toggle out of combat, which a second press waits for
/// (Spell4Effects 159128: dataBits03 is the float 1000.0).
const stealth_recharge_ms = 1000

/// Whether a go of a cast of the unit `caster` names the unit `target` (opcode.0x7f4).
fn struck_by(
  frames frames: List(Frame),
  caster caster: Int,
  target target: Int,
) -> Bool {
  list.any(game_client.go_targets_in(frames:), fn(go) {
    cast_state.caster_of(cast_id: go.0) == caster && list.contains(go.1, target)
  })
}

/// Whether the event is a 0x908 of the unit, whoever it targets and whatever the threat.
fn is_targeted_by(event event: game_client.FightEvent, unit unit: Int) -> Bool {
  case event {
    game_client.Targeted(unit_id:, ..) -> unit_id == unit
    game_client.Threatens(..)
    | game_client.InCombat(..)
    | game_client.LevelIs(..)
    | game_client.ShieldIs(..)
    | game_client.InterruptArmorIs(..)
    | game_client.AbsorptionIs(..)
    | game_client.OwnHealthIs(..)
    | game_client.Moves(..)
    | game_client.Went(..)
    | game_client.Started(..)
    | game_client.HealthIs(..) -> False
  }
}

/// The stealth changes among the frames, each the unit and its stealthed bit, in
/// order (opcode.0x8f5).
fn stealth_changes_in(frames frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == unit_stealth.message_id {
      True -> {
        let assert Ok(change) = unit_stealth.decode(frame.body)
          as "0x8f5 decodes"
        Ok(#(change.unit_id, change.stealthed))
      }
      False -> Error(Nil)
    }
  })
}

pub fn a_stealthed_bot_walking_into_a_daguns_ring_gets_no_aggro_and_pressing_stealth_again_inside_it_is_targeted_and_chased_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // A Stalker pressing its Stealth toggle, Spell4.46073: a first press enters stealth
  // and a second ends it. The toggle recharges in 1000 ms out of combat, so the
  // connections' clock is driven and moved by hand between the presses.
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_stalker(started:, number: 1, character_name: "Zed Qu")
  game_client.press_ability(
    game:,
    client_cast_id: 1,
    bag_index: stealth_index,
    target: 0,
  )
  let #(entered, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      stealth_changes_in(frames:) != []
    })
  assert stealth_changes_in(frames: entered) == [#(own, 1)]
    as "opcode.0x8f5: the press enters stealth"
  // Into the ring: 9 units from the Dagun, beyond its reach of 7.
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(walked, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  let walked = game_client.fight_in(frames: walked)
  assert list.all(walked, fn(event) { !is_targeted_by(event:, unit: dagun) })
    && !list.contains(
      walked,
      game_client.InCombat(unit_id: dagun, in_combat: True),
    )
    && !list.contains(
      walked,
      game_client.InCombat(unit_id: own, in_combat: True),
    )
    && game_client.moves_of(events: walked, unit: dagun) == []
    as "the server's choice: the stealthed bot stands in no ring, so the Dagun sends no 0x908 at all or 0x89a and does not run"
  driven_time.advance(time:, ms: stealth_recharge_ms)
  game_client.press_ability(
    game:,
    client_cast_id: 2,
    bag_index: stealth_index,
    target: 0,
  )
  let #(fight, _) =
    read_fight(game:, have:, found: fn(events) {
      dagun_runs(events:, dagun:)
      && list.contains(
        events,
        game_client.InCombat(unit_id: own, in_combat: True),
      )
    })
  assert list.contains(
    fight,
    game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
  )
    as "leaving stealth inside the ring aggroes as a walk-in does: 0x908 with the aggro threat 1"
  let assert [#(turn_kinds, _), #(kinds, ends_at), ..] =
    game_client.moves_of(events: fight, unit: dagun)
    as "the Dagun turns, then runs"
  assert turn_kinds == [0, 18]
    as "the turn goes before the path: kind 0, then kind 18 naming the bot (a kind 4 path leaves the rotation)"
  assert kinds == [0, 4, 10, 13, 18, 26]
    as "the chase: kind 0, the kind 4 path, then the defaults for the velocity, move and state with kind 18 for the bot in place of kind 21, so the Dagun goes on facing the bot after it stops, and no kind 11 or kind 24"
  assert ends_at == Some(#(1.5, 2.5, dagun_z +. 9.0 -. 3.5))
    as "to the bot less half the Dagun's reach of 7 (chase_stop_fraction 0.5)"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_dagun_fighting_a_bot_that_then_stealths_keeps_striking_it_and_its_landed_blow_ends_the_stealth_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // The same Stalker as above: Stealth 38784's row 83834 (dataBits02 0: damage taken
  // ends it) is the one a press out of combat reaches.
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_stalker(started:, number: 1, character_name: "Zed Qu")
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(_, have) =
    read_fight(game:, have:, found: fn(events) {
      list.contains(events, game_client.InCombat(unit_id: own, in_combat: True))
    })
  the_creature_has_taken_what_it_was_sent(started:, unit_id: dagun)
  game_client.press_ability(
    game:,
    client_cast_id: 1,
    bag_index: stealth_index,
    target: 0,
  )
  let #(entered, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      stealth_changes_in(frames:) != []
    })
  // The map has told the Dagun of the bot's stealth, and the Dagun has taken it,
  // before the clock reaches its attack tick, so the tick meets the Dagun with the
  // stealth on its threat list.
  let #(taken, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  // The Dagun's attack tick, its interval after the aggro: the bot is in its reach
  // by then, and the strike's chain ends in the bot's 0x8f5 of the stealth ending.
  // A blow the bot deflects (0.05, CreatureLevel row 101) ends nothing, so the next
  // interval's is waited for.
  let #(struck, _) =
    blows_until(time:, game:, have:, found: fn(frames) {
      list.contains(stealth_changes_in(frames:), #(own, 0))
    })
  let frames = list.flatten([entered, taken, struck])
  assert stealth_changes_in(frames:) == [#(own, 1), #(own, 0)]
    as "opcode.0x8f5: the press enters stealth, and the Dagun, which keeps fighting the bot it already had on its threat list, strikes it: Spell4Effects.effectType.83 (83834, dataBits02 0) ends the stealth on the damage taken"
  assert struck_by(frames:, caster: dagun, target: own)
    as "the Dagun's strike names the bot: it keeps fighting a player it already had on its threat list (opcode.0x7f4)"
  assert !struck_by(frames:, caster: own, target: dagun)
    as "the bot's own press struck nothing, so the Dagun's threat list held the bot from the walk-in, not from the press"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_dagun_that_crashes_mid_fight_is_gone_and_the_bots_combat_flag_clears_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(_, have) =
    read_fight(game:, have:, found: fn(events) {
      list.contains(events, game_client.InCombat(unit_id: own, in_combat: True))
    })
  let #(_, pid) = the_dagun_and_its_map(started:, dagun:)
  process.kill(pid)
  let #(frames, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.fight_in(frames:),
        game_client.InCombat(unit_id: own, in_combat: False),
      )
    })
  assert list.contains(game_client.removals_in(frames:), dagun)
    as "the map's Gone: the bot's client removes the Dagun"
  game_client.close(game:)
  login_support.stop(started)
}

// ------------------------------------------- death and coming back, on the whole server
//
// Expected values come from the design of step G (issue 368: test 12, the
// coming back's frames of tests 8 and 9) and these places: the client's Death
// addon sends 0x15a {its unit, 1 or 2, 0} for Wake Here and the Holocrypt
// (`lua.GameLib.RezType`); Wake Here writes 0x92f, 0x938, 0x88c, 0x1b3, 0x355,
// 0x636 and 0x247 in that order (`opcode.0x88c`, `opcode.0x1b3`,
// `opcode.0x247.death`), at full health and shield (`death.server_choices`), the
// values the player entered with in its 0x262 (stats 0 and 20); the Holocrypt
// writes the same, then the entry burst at the start of the race and faction in
// the world, else at the place the stay entered at (`death.server_choices`):
// World 1387 holds no Novice start, so the place a new test character stands at.

/// A world with one Dagun whose blow is 100000: planted test data, since the Dagun's own 12
/// every 1500 ms takes some 400 ticks to kill a player of level 1, and the test is of the
/// death and the coming back, not of the number. The fight's sequence is the client's as on
/// the Dagun of `world_with_a_dagun`.
fn world_with_a_lethal_dagun(
  time time: driven_time.Time,
) -> login_support.Started {
  world_with_a_dagun_on(
    tables: character_tables.shared(),
    blow: Some(100_000),
    time:,
  )
}

/// A world with one Dagun, its map's and creature's timers and the connections' on the clock
/// `time`, so the Dagun's attack tick and home timer fire only when the test advances it.
fn world_with_a_dagun(time time: driven_time.Time) -> login_support.Started {
  world_with_a_dagun_on(tables: character_tables.shared(), blow: None, time:)
}

/// The player of the frames' 0x262 walks into the Dagun's ring, the Dagun's aggro
/// is read with its tick on the clock, the clock moves on to the tick (the Dagun runs
/// to within its reach of the bot in less than that), and the player is read until
/// its own 0x88c marks it dead and the death's last frame, the ghost's 0x636, has
/// come: the bytes kept.
fn killed_by_the_dagun(
  time time: driven_time.Time,
  started started: login_support.Started,
  game game: game_client.Game,
  own own: Int,
  dagun dagun: Int,
  have have: BitArray,
) -> BitArray {
  walk_to(game:, z: dagun_z +. 9.0, clock: 100)
  let #(_, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  let #(_, have) =
    blows_until(time:, game:, have:, found: fn(frames) {
      list.contains(game_client.deaths_in(frames:), #(own, True))
      && list.any(frames, fn(frame) { frame.message_id == 0x0636 })
    })
  have
}

/// The clock moves on by one attack interval of the Dagun and the player is read until
/// `found` holds of the frames read, or a blow was deflected (a 0x7fb: a player deflects
/// a blow by chance, 0.05, CreatureLevel row 101); a deflected blow is followed by the
/// next interval's, until `found` holds. The frames of the read that ended it, and the
/// bytes kept.
fn blows_until(
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  found found: fn(List(Frame)) -> Bool,
) -> #(List(Frame), BitArray) {
  driven_time.advance(time:, ms: dagun_attack_interval_ms())
  let #(frames, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      found(frames) || game_client.missed_in(frames:) != []
    })
  case found(frames) {
    True -> #(frames, have)
    False -> blows_until(time:, game:, have:, found:)
  }
}

/// 0x15a for the unit and the choice, with the value 0, sent inside 0x038C.
fn choose(
  game game: game_client.Game,
  own own: Int,
  choice choice: Int,
) -> Nil {
  game_client.send_world(
    game:,
    message_id: 0x015A,
    body: message_support.choice_body(unit_id: own, choice:, value: 0),
  )
}

/// The frames of the coming back among `frames`, in order.
fn coming_back_in(frames frames: List(Frame)) -> List(Frame) {
  list.filter(frames, fn(frame) {
    list.contains(
      [0x092F, 0x0938, 0x088C, 0x01B3, 0x0355, 0x0636, 0x0247],
      frame.message_id,
    )
  })
}

pub fn a_bot_of_each_class_killed_by_a_planted_dagun_comes_back_by_wake_here_over_the_wire_and_the_spellslinger_by_the_holocrypt_test() -> Nil {
  use <- owned_test.run(120_000)
  // The Medic's half of the fight, a creature it kills standing again at its
  // respawn, is `a_medic_kills_a_planted_beast_with_paralytic_surge_and_a_watcher_reads_the_same_fight_test`.
  // Each bot has a world and a clock of its own: the Dagun that has killed one is
  // walking home on a timer, and the next bot's death should not wait on it.
  list.each(
    [
      #(1, "Ann Qu", 1),
      #(2, "Bea Qu", 2),
      #(3, "Cal Qu", 3),
      #(4, "Dee Qu", 4),
      #(5, "Eve Qu", 5),
    ],
    fn(bot) {
      let #(number, character_name, class_id) = bot
      let class = "class " <> int.to_string(class_id)
      let time = driven_time.new()
      let started = world_with_a_lethal_dagun(time:)
      let #(game, entry, have) =
        a_ready_player(started:, number:, character_name:, class_id:)
      let own = game_client.unit_create_player_in(frames: entry).unit_id
      let assert [dagun] = game_client.creatures_created_in(frames: entry)
      let have =
        killed_by_the_dagun(
          time:,
          started:,
          game:,
          own:,
          dagun: dagun.unit_id,
          have:,
        )
      choose(game:, own:, choice: 1)
      let #(frames, _) =
        game_client.read_until(game:, have:, found: fn(frames) {
          list.contains(
            list.map(coming_back_in(frames:), fn(frame) { frame.message_id }),
            0x0247,
          )
        })
      let back = coming_back_in(frames:)
      assert cast_support.ids(frames: back)
        == [0x092F, 0x0938, 0x088C, 0x01B3, 0x0355, 0x0636, 0x0247]
        as { class <> " comes back by Wake Here in the client's order" }
      assert list.contains(game_client.deaths_in(frames: back), #(own, False))
        as { class <> ": 0x88c marks its unit alive" }
      let assert [Frame(body: health, ..)] =
        list.filter(back, fn(frame) { frame.message_id == 0x092F })
      let assert Ok(health) = player_health.decode(health)
      let assert [Frame(body: shield, ..)] =
        list.filter(back, fn(frame) { frame.message_id == 0x0938 })
      let assert Ok(unit_stat_changed.UnitStatChanged(
        change: unit_stat_change.Shield(UnitStatShield(value: shield)),
        ..,
      )) = unit_stat_changed.decode(shield)
        as "the 0x938 is the shield's"
      assert health.health == entry_stat(entry:, stat_id: 0)
        && shield == entry_stat(entry:, stat_id: 20)
        as { class <> ": at the full health and shield it entered with" }
      game_client.close(game:)
      login_support.stop(started)
    },
  )
  // The Spellslinger comes back by the Holocrypt.
  let time = driven_time.new()
  let started = world_with_a_lethal_dagun(time:)
  let #(game, entry, have) =
    a_ready_player(started:, number: 6, character_name: "Fay Qu", class_id: 7)
  let own = game_client.unit_create_player_in(frames: entry).unit_id
  let assert [dagun] = game_client.creatures_created_in(frames: entry)
  let have =
    killed_by_the_dagun(
      time:,
      started:,
      game:,
      own:,
      dagun: dagun.unit_id,
      have:,
    )
  choose(game:, own:, choice: 2)
  let #(frames, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.count(
        list.drop_while(frames, fn(frame) { frame.message_id != 0x00AD }),
        fn(_) { True },
      )
      >= holocrypt_burst_length()
    })
  let burst =
    list.take(
      list.drop_while(frames, fn(frame) { frame.message_id != 0x00AD }),
      holocrypt_burst_length(),
    )
  assert cast_support.ids(frames: burst) == game_client.holocrypt_entry_ids()
    as "the Spellslinger comes back by the Holocrypt: the entry burst, 0xAD first, with no second 0x25E (opcode.0x25e.entry_order)"
  let assert [Frame(body:, ..), ..] = burst
  let assert Ok(entered) = enter_world.decode(body)
  assert entered.world_id == 1387
    && entered.position_x == float32.to_bits(1.5)
    && entered.position_y == float32.to_bits(2.5)
    && entered.position_z == float32.to_bits(3.5)
    as "at the place the stay entered at: World 1387 holds no Novice start"
  game_client.close(game:)
  login_support.stop(started)
}

/// Whether the creature's fight is Returning, read from its process's state: the
/// service shell's `Running` holds the creature's state as its fourth field, whose fifth
/// is its fight, whose second is the fight's status: an atom for Resting, else a tuple
/// tagged by the status.
fn creature_walks_home(creature creature: process.Pid) -> Bool {
  let tag = decode.map(atom.decoder(), atom.to_string)
  let status = decode.one_of(tag, [decode.at([0], tag)])
  let assert Ok(status) =
    decode.run(system.get_state(creature), decode.at([3, 4, 1], status))
    as "the creature's state holds its fight's status"
  status == "returning"
}

pub fn a_bot_killed_by_a_dagun_in_its_ring_is_struck_no_more_the_dagun_rests_at_home_and_waking_in_the_ring_is_aggroed_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  // A report from play: a creature that killed a player kept attacking the body. A
  // creature leashes at the death (0x90a 0, 0x89a (C, 0)) and, standing at its spawn, its
  // home timer fires at once, so a body left in the creature's near set was aggroed
  // again in the same instant. A server choice (the Design of issue 496): a dead unit is
  // struck by nothing (`Spell4ValidTargets.targetBitmask`), so the Dagun rests, and a
  // player that wakes inside its ring is aggroed as a walk-in is.
  let time = driven_time.new()
  let started = world_with_a_lethal_dagun(time:)
  let #(game, own, dagun, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  // Into the ring and within the Dagun's reach: it strikes from home and never runs, so
  // its home timer after the kill has no walk to wait for, and is due when the leash
  // starts it.
  walk_to(game:, z: dagun_z +. 5.0, clock: 100)
  let #(aggro, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(1, 2),
    )
  // The attack tick strikes and kills, and the clock fires the home timer the leash
  // started at the same instant, each after the barrier of the one before it.
  let #(died, have) =
    blows_until(time:, game:, have:, found: fn(frames) {
      list.contains(game_client.deaths_in(frames:), #(own, True))
      && list.any(frames, fn(frame) { frame.message_id == 0x0636 })
      && list.contains(
        game_client.fight_in(frames:),
        game_client.InCombat(unit_id: dagun, in_combat: False),
      )
    })
  assert list.contains(
    game_client.fight_in(frames: died),
    game_client.Threatens(unit_id: dagun, other_unit_id: own, threat: 0),
  )
    as "opcode.0x90a: the Dagun erases the body's threat when it leashes"
  let #(_, creature) = the_dagun_and_its_map(started:, dagun:)
  assert !creature_walks_home(creature:)
    as "the Dagun took its home timer: the clock fired it after the leash"
  let #(settled, have) =
    read_after_the_map_and_the_creature_took_it(
      game:,
      have:,
      started:,
      dagun:,
      pongs: #(3, 4),
    )
  let after_the_leash =
    list.drop(
      list.drop_while(
        game_client.fight_in(frames: list.flatten([aggro, died, settled])),
        fn(event) {
          event != game_client.InCombat(unit_id: dagun, in_combat: False)
        },
      ),
      1,
    )
  assert list.all(after_the_leash, fn(event) {
    case event {
      game_client.Targeted(unit_id:, ..)
      | game_client.Started(caster_unit_id: unit_id, ..) -> unit_id != dagun
      game_client.Went(cast_id:, ..) -> cast_state.caster_of(cast_id:) != dagun
      game_client.Moves(unit_id:, kinds:, ..) ->
        // After the leash the Dagun only turns to its spawn facing, with the blended kind 19
        // turn a creature arriving home makes; it never runs.
        unit_id != dagun || kinds == [0, 19]
      game_client.Threatens(..)
      | game_client.InCombat(..)
      | game_client.LevelIs(..)
      | game_client.ShieldIs(..)
      | game_client.InterruptArmorIs(..)
      | game_client.AbsorptionIs(..)
      | game_client.OwnHealthIs(..)
      | game_client.HealthIs(..) -> True
    }
  })
    as "after the Dagun's leash and its home timer the Dagun names no target, starts no cast, strikes and runs nowhere (the one 0x638 it is sent is kind 0 then kind 14, the leash's turn to its spawn's facing as it stands at home already): the body is in no ring"
  choose(game:, own:, choice: 1)
  let #(woke, _) =
    read_fight(game:, have:, found: fn(events) {
      list.contains(
        events,
        game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
      )
    })
  assert list.contains(
    woke,
    game_client.Targeted(unit_id: dagun, target_unit_id: own, threat: 1),
  )
    as "0x908: the bot that woke inside the ring is aggroed with the aggro threat 1, as a walk-in"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_player_whose_connection_ends_mid_chase_makes_the_dagun_leash_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = world_with_a_dagun(time:)
  let #(watcher, _, dagun, watcher_have) =
    a_ready_medic(started:, number: 2, character_name: "Ann Qu")
  let #(fighter, own, _, have) =
    a_ready_medic(started:, number: 1, character_name: "Zed Qu")
  walk_to(game: fighter, z: dagun_z +. 9.5, clock: 100)
  // The fighter ends once the Dagun runs toward it: mid-chase.
  let #(_, _) =
    read_fight(game: fighter, have:, found: fn(events) {
      list.contains(events, game_client.InCombat(unit_id: own, in_combat: True))
      && game_client.moves_of(events:, unit: dagun) != []
    })
  game_client.close(game: fighter)
  let #(seen, _) =
    read_fight(game: watcher, have: watcher_have, found: fn(events) {
      leaves_unit_at(events:, unit: dagun, z: dagun_z)
    })
  assert list.contains(
      seen,
      game_client.Threatens(unit_id: dagun, other_unit_id: own, threat: 0),
    )
    && list.contains(
      seen,
      game_client.InCombat(unit_id: dagun, in_combat: False),
    )
    && list.contains(game_client.health_of(events: seen, unit: dagun), 52)
    as "the fighter's end is its Unwatched: no threat is left, so the Dagun leashes (0x90a 0, 0x89a (C, 0), a full 0x937) and runs home, which the watcher sees"
  game_client.close(game: watcher)
  login_support.stop(started)
}

// ---- the Sim-Turrets of the Novice training simulation, on the whole server ----
//
// The world database stores the two Exile Sim-Turrets, Creature2 73494, as unit type 13
// rows 29178 and 29179 (`test/fixture/world_data_turrets`), 31.6 apart in World 3460 at
// (-105.661, -864.7596, 502.462) and (-112.69, -864.691, 470.817). Their stored factions
// are not read: migration 0029 stands them with faction 1441, Hostile to the Exile 167
// (Faction2Relationship 2943, level 0). Each charges Spell4 85469 (castTime 8000) every
// 3000 ms after its attack tick: the 0x7ff when the tick opens it, the 0x7f4 and the
// 0x7fe 8000 ms later. Objective 21288 (QuestObjective: type 2, count 2, data 73494,
// flags 0x203) is the fifth objective of quest 10518 (Quest2 objective04), so its
// progress is the 0x361 of index 4 (opcode.0x361), open once the four objectives
// before it are done (0x140553790, as `a_medic_at_the_marker_ring` holds). Paralytic
// Surge reaches 15 (Spell4 42352 targetMaxRange) and a creature's aggro range is 10
// (migration 0010).

/// The first stored turret, row 29178.
const turret_29178 = #(-105.661, -864.7596, 502.462)

/// The second stored turret, row 29179.
const turret_29179 = #(-112.69, -864.691, 470.817)

/// A world on the planted turret rows and the content load, on the clock `time`.
fn world_with_the_turrets(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_on(
    folder: "test/fixture/world_data_turrets",
    tables:,
    time:,
    tutorial: False,
  )
}

/// An Exile Medic of level 30 holding quest 10518 with its first four objectives done,
/// played into World 3460 at `at`, and read until the 0x262 of both turrets has
/// arrived (a player sees every unit within 1024, `sight.range`), and ready: the game,
/// the burst's frames and the bytes beyond.
fn an_exile_medic_near_the_turrets(
  started started: login_support.Started,
  at at: #(Float, Float, Float),
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
    as "the character is an Exile one (faction 167), which faction 1441 is hostile to"
  let assert Ok(_) =
    pog.query(
      "insert into character_quest (character_id, quest_id, state, placeholder_objective_id, tracked, done_mask, progress, quest_ms_left, objective_ms_left, kill_mask) values ($1, 10518, 1, 0, true, 15, '{5,1,1,1,0,0}', 0, '{0,0,0,0,0,0}', '{0,0,0,0,0,0}')",
    )
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the character holds quest 10518 with the objectives of index 0 to 3 done, so the turrets' of index 4 is open"
  character_support.move_to(
    pool:,
    character_id: character,
    world_id: 3460,
    world_zone_id: 5967,
    position: at,
  )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(turrets_in(frames:)) >= 2
    })
  // Ready: the client's first 0xF2 (`terrain_loaded`), which puts the player in the rings.
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: 5967))
  game_client.send_world(game:, message_id: terrain_loaded.message_id, body:)
  #(game, frames, have)
}

/// The Sim-Turrets (Creature2 73494) the frames create, as the client reads them.
fn turrets_in(
  frames frames: List(Frame),
) -> List(unit_create_static.UnitCreateStatic) {
  list.filter(static_objects_created_in(frames:), fn(object) {
    object.creature_id == 73_494
  })
}

/// The unit of the turret the frames create at `place`.
fn the_turret_at(
  frames frames: List(Frame),
  place place: #(Float, Float, Float),
) -> Int {
  let assert Ok(turret) =
    list.find(turrets_in(frames:), fn(turret) {
      is_near(left: game_client.placed_by_tail(tail: turret.tail), right: place)
    })
    as "a Creature2 73494 stands at the place of its stored row"
  turret.unit_id
}

/// How many presses fit in the 15000 ms opening after the press that interrupts, each
/// 2700 ms after the last (`fight_bot.paralytic_surge_lingers_ms`): the presses at 2700 to 13500 ms.
const presses_in_the_opening = 5

/// The medic walks to 8 beyond the turret at `place`, inside its aggro range, faces it and waits
/// for its charge to open; presses Paralytic Surge once, whose stun breaks the charge, and
/// presses on within the 15 s of the opening until the turret is destroyed. It checks the
/// wire of the interrupt on the way and gives every frame read and the bytes beyond.
fn interrupts_and_destroys(
  started started: login_support.Started,
  time time: driven_time.Time,
  game game: game_client.Game,
  have have: BitArray,
  turret turret: Int,
  own own: Int,
  guard_cast guard_cast: Int,
  place place: #(Float, Float, Float),
  clock clock: Int,
  cast_id cast_id: Int,
) -> #(List(Frame), BitArray) {
  let stands = #(place.0 +. 8.0, place.1, place.2)
  game_client.send_world(
    game:,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: clock, commands: [
      game_client.position_command(x: stands.0, y: stands.1, z: stands.2),
    ]),
  )
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(stands.0, stands.2), target: #(
      place.0,
      place.2,
    )),
    clock: clock + 100,
  )
  let #(aggroed, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.fight_in(frames:),
        game_client.Targeted(unit_id: turret, target_unit_id: own, threat: 1),
      )
    })
  // The attack tick, 3000 ms after the aggro, opens the charge.
  driven_time.advance(time:, ms: 3000)
  let #(opened, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      game_client.starts_of(
        events: game_client.casts_in(frames:),
        spell4_id: 85_469,
      )
      != []
    })
  let assert [#(charge_cast, charger)] =
    game_client.starts_of(
      events: game_client.casts_in(frames: opened),
      spell4_id: 85_469,
    )
    as "the tick opens the charge with one 0x7ff of Spell4 85469"
  assert charger == turret
  // The press: Paralytic Surge's damage takes nothing from the guarded turret and its stun
  // (Spell4Effects 96126, 2700 ms) breaks the charge.
  character_support.marker_creature_settled(
    settings: started.settings,
    unit_id: turret,
  )
  game_client.press_ability(
    game:,
    client_cast_id: cast_id,
    bag_index: 2,
    target: 0,
  )
  // The connection's pong orders only its own input, not the creature's sends, so the
  // read waits for every message the assertions below name: the broken charge's 0x7fe, the
  // opening's 0x7ff, the guard's 0x811, the states' 0x87f and the press's 0x247 immunity.
  // The turret sends its news to the connection before it answers the strike, and a process's
  // messages to another arrive in the order sent, so a health the press took would be read
  // before the immunity the answer makes.
  let immunity =
    Frame(
      message_id: 0x0247,
      body: message_support.packed([
        #(6, 18),
        #(32, own),
        #(32, turret),
        #(18, 42_352),
        #(4, 2),
      ]),
    )
  // The interrupt line (type 19, `opcode.0x247.interrupted`): Paralytic Surge 42352 as the
  // interrupting spell, result 11 (SpellInterrupted), the medic as the caster, the turret
  // as the unit interrupted, the charge's Spell4 85469 and the combat result Hit (2).
  let interrupt =
    Frame(
      message_id: 0x0247,
      body: message_support.packed([
        #(6, 19),
        #(18, 42_352),
        #(9, 11),
        #(32, own),
        #(32, turret),
        #(18, 85_469),
        #(4, 2),
      ]),
    )
  let #(interrupted, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.casts_in(frames:),
        game_client.CastFinished(cast_id: charge_cast),
      )
      && list.contains(frames, interrupt)
      && game_client.starts_of(
        events: game_client.casts_in(frames:),
        spell4_id: 85_472,
      )
      != []
      && list.contains(
        game_client.targets_removed_in(frames:),
        #(guard_cast, [turret]),
      )
      && list.any(frames, fn(frame) { frame.message_id == 0x087F })
      && list.contains(frames, immunity)
    })
  let events = game_client.casts_in(frames: interrupted)
  assert game_client.broken_casts_in(frames: interrupted)
    == [#(charge_cast, 11, turret)]
    as "opcode.0x7f9: the charge is broken with result 11 by the turret"
  assert list.contains(events, game_client.CastFinished(cast_id: charge_cast))
    as "opcode.0x7fe: the broken charge's 0x7fe follows"
  let assert [#(_, opener)] = game_client.starts_of(events:, spell4_id: 85_472)
    as "Spell4 85472, the opening, starts once"
  assert opener == turret as "cast by the turret"
  assert game_client.targets_removed_in(frames: interrupted)
    == [#(guard_cast, [turret])]
    as "opcode.0x811: the guard's cast comes off the turret"
  assert !list.any(game_client.health_in(frames: interrupted), fn(health) {
    health.0 == turret
  })
    as "the guarded turret took no damage from the press"
  assert list.contains(interrupted, immunity)
    as "opcode.0x247.immunity: the press's striker is shown the turret's immunity, type 18 with Spell4 42352"
  assert list.any(interrupted, fn(frame) { frame.message_id == 0x087F })
    as "opcode.0x87f: the states of the stun and the opening are told"
  assert list.filter(interrupted, fn(frame) { frame == interrupt })
    == [interrupt]
    as "opcode.0x247.interrupted: the stun's striker is shown the interrupt line once, type 19 with Spell4 42352 interrupting the charge 85469"
  // The opening lasts 15000 ms on the clock from the interrupting press, and a press's hit
  // lingers 2700 ms before the next (Spell4Effects 96126), so the presses at 2700, 5400,
  // 8100, 10800 and 13500 ms fit in it and a sixth, at 16200, would find the guard back.
  // The turret never deflects (`on_rows_with_turrets_that_never_deflect`), so the five presses
  // all hit, whatever the connection's rolls are, and the kill below tells whether their
  // damage takes the turret's health.
  driven_time.advance(time:, ms: fight_bot.paralytic_surge_lingers_ms)
  let #(lingered, have) = game_client.read_until_pong(game:, have:, number: 2)
  let assert Ok(#(killed, have)) =
    fight_bot.presses_at_most(
      ability: fight_bot.paralytic_surge,
      advance: driven_time.advance(time:, ms: _),
      recharge_ms: 0,
      game:,
      have:,
      target: turret,
      cast_id: cast_id + 1,
      seen: [],
      presses: presses_in_the_opening,
    )
  let seen = list.flatten([aggroed, opened, interrupted, lingered, killed])
  assert list.contains(game_client.deaths_in(frames: seen), #(turret, True))
    as "the opened turret takes the presses' damage and is destroyed within its 15 s"
  assert list.filter(seen, fn(frame) { frame == interrupt }) == [interrupt]
    as "no later press interrupts anything: the one line is the stun's"
  #(seen, have)
}

pub fn an_exile_interrupts_and_destroys_both_sim_turrets_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_with_turrets_that_never_deflect()
  let time = driven_time.new()
  let started = world_with_the_turrets(tables:, time:)
  // Enters 14 beyond the first turret, outside its aggro range 10.
  let enters = #(turret_29178.0 +. 14.0, turret_29178.1, turret_29178.2)
  let #(game, frames, have) =
    an_exile_medic_near_the_turrets(started:, at: enters)
  let first = the_turret_at(frames:, place: turret_29178)
  let second = the_turret_at(frames:, place: turret_29179)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let #(arrived, have) = game_client.read_until_pong(game:, have:, number: 1)
  let guards =
    game_client.starts_of(
      events: game_client.casts_in(frames: list.append(frames, arrived)),
      spell4_id: 85_474,
    )
  let assert Ok(#(first_guard, _)) =
    list.find(guards, fn(guard) { guard.1 == first })
    as "Spell4 85474, the guard, is cast by each turret on arrival: the first's"
  let assert Ok(#(second_guard, _)) =
    list.find(guards, fn(guard) { guard.1 == second })
    as "and the second's"
  let #(first_seen, have) =
    interrupts_and_destroys(
      started:,
      time:,
      game:,
      have:,
      turret: first,
      own:,
      guard_cast: first_guard,
      place: turret_29178,
      clock: 100,
      cast_id: 1,
    )
  // The kill's credit comes from the creature after its death is written.
  let #(first_counted, have) =
    game_client.read_until_pong(game:, have:, number: 7)
  let #(second_seen, have) =
    interrupts_and_destroys(
      started:,
      time:,
      game:,
      have:,
      turret: second,
      own:,
      guard_cast: second_guard,
      place: turret_29179,
      clock: 400,
      cast_id: 100,
    )
  let #(second_counted, _) =
    game_client.read_until_pong(game:, have:, number: 14)
  assert list.filter(
      list.flatten([first_seen, first_counted, second_seen, second_counted]),
      fn(frame) { frame.message_id == 0x0361 },
    )
    == [
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 4), #(32, 1)]),
      ),
      Frame(
        message_id: 0x0361,
        body: message_support.packed([#(15, 10_518), #(32, 4), #(32, 2)]),
      ),
    ]
    as "opcode.0x361: each destroyed turret counts objective 21288, the fifth of quest 10518: 1 of 2, then 2 of 2"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_charge_hits_a_player_who_stays_in_its_rectangle_test() -> Nil {
  use <- owned_test.run(120_000)
  // A player deflects a blow by chance (BaseAvoidChance, CreatureLevel row 101's 0.05 at
  // unitPropertyValue01), and a deflected charge gives no health to read; the row holds 0 here,
  // a case no client row holds, so the charge lands on every seed.
  use tables <- fixture_tables.changes(edits: [
    #("Spell4", 42_352, [#("spellCoolDown", planted_table.Integer(0))]),
    #("CreatureLevel", 101, [#("unitPropertyValue01", planted_table.Float(0.0))]),
  ])
  let time = driven_time.new()
  let started = world_with_the_turrets(tables:, time:)
  // Enters 14 beyond the first turret, outside its aggro range 10, then walks in to 8
  // beyond it: inside the range and 30 ahead of its charge's start.
  let enters = #(turret_29178.0 +. 14.0, turret_29178.1, turret_29178.2)
  let #(game, frames, have) =
    an_exile_medic_near_the_turrets(started:, at: enters)
  game_client.send_world(
    game:,
    message_id: 0x0637,
    body: game_client.moves_body(client_clock: 100, commands: [
      game_client.position_command(
        x: turret_29178.0 +. 8.0,
        y: turret_29178.1,
        z: turret_29178.2,
      ),
    ]),
  )
  let turret = the_turret_at(frames:, place: turret_29178)
  let own = game_client.unit_create_player_in(frames:).unit_id
  let health = entry_stat(entry: frames, stat_id: 0)
  let #(aggroed, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.fight_in(frames:),
        game_client.Targeted(unit_id: turret, target_unit_id: own, threat: 1),
      )
    })
  assert list.contains(
    game_client.fight_in(frames: aggroed),
    game_client.Targeted(unit_id: turret, target_unit_id: own, threat: 1),
  )
    as "0x908: the turret fights the player who walked into its aggro range"
  // The attack tick, 3000 ms after the aggro, opens the charge.
  driven_time.advance(time:, ms: 3000)
  let #(opened, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      game_client.starts_of(
        events: game_client.casts_in(frames:),
        spell4_id: 85_469,
      )
      != []
    })
  let assert [#(cast_id, caster_unit_id)] =
    game_client.starts_of(
      events: game_client.casts_in(frames: opened),
      spell4_id: 85_469,
    )
    as "the tick opens the charge with one 0x7ff of Spell4 85469"
  assert caster_unit_id == turret as "opcode.0x7ff: the turret casts it"
  assert game_client.go_targets_in(frames: opened) == []
    as "the 8 s cast has not gone: no 0x7f4 yet"
  // Its cast time passes with the player in the rectangle, once the charge's own
  // timer is on the clock, which the advance's barrier waits for.
  driven_time.advance(time:, ms: 8000)
  let #(went, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(
        game_client.casts_in(frames:),
        game_client.CastFinished(cast_id:),
      )
      && game_client.own_health_of(
        events: game_client.fight_in(frames:),
        unit: own,
      )
      != []
    })
  assert game_client.go_targets_in(frames: went) == [#(cast_id, [own])]
    as "opcode.0x7f4: the go names the player inside the rectangle"
  let assert [game_client.Went(targets: [#(_, [blow])], ..)] =
    list.filter(game_client.fight_in(frames: went), fn(event) {
      case event {
        game_client.Went(cast_id: went_id, ..) -> went_id == cast_id
        game_client.Targeted(..)
        | game_client.Threatens(..)
        | game_client.InCombat(..)
        | game_client.LevelIs(..)
        | game_client.ShieldIs(..)
        | game_client.InterruptArmorIs(..)
        | game_client.AbsorptionIs(..)
        | game_client.OwnHealthIs(..)
        | game_client.Moves(..)
        | game_client.Started(..)
        | game_client.HealthIs(..) -> False
      }
    })
    as "opcode.0x7f4: one go of the charge, with one damage effect for the player"
  // The strike's crit roll is from the connection's random seed, so the blow is a
  // critical hit or not by chance: 400 when not, and 400 x the turret's critical
  // severity when it is. The severity is property 127 at rating 0: CreatureLevel.101
  // unitPropertyValue27 1.5 x Creature2Tier.1 multiplier 0.85 (Creature2 73494, tier 1;
  // `GetCreatureProperty`, `0x1404585c0`), to which GameFormula 1232 adds nothing at
  // rating 0 (intercept 0, `0x140463e80`): 1.275.
  let expected_raw = case blow.critical {
    True -> 510
    False -> 400
  }
  assert blow.effect_id == 224_644 && blow.raw_damage == expected_raw
    as "Spell4Effects 224644: the charge deals the player 400, or 510 (400 x 1.275) when the 0x7f4's combat result is a critical hit"
  // The blow after the glance and the mitigation and absorbs is `adjusted`; the shield
  // takes 0.625 of it (ShieldMitigationMax, property 175,
  // `player.level1_gear_properties`, rounded as `hit.apply` rounds), which the
  // shield held (`entry_stat` 20) covers, and the health takes the rest.
  let adjusted = blow.raw_damage - blow.glance - blow.absorbed
  assert blow.shield_absorbed == float.round(int.to_float(adjusted) *. 0.625)
    as "opcode.0x7f4: the shield takes 0.625 of the adjusted blow"
  assert blow.shield_absorbed <= entry_stat(entry: frames, stat_id: 20)
    as "the shield held what it took"
  let assert [_, ..] as healths =
    game_client.own_health_of(
      events: game_client.fight_in(frames: went),
      unit: own,
    )
    as "opcode.0x92f: the charge's go gives the player's health"
  let assert Ok(now) = list.last(healths)
    as "the last health is the one that stands"
  assert health - now == adjusted - blow.shield_absorbed
    as "opcode.0x92f: the health loses the adjusted blow less the shield's share"
  assert blow.health_damage == adjusted - blow.shield_absorbed
    as "opcode.0x7f4: the description's health damage is the same"
  assert list.any(
    game_client.shield_of(events: game_client.fight_in(frames: went), unit: own),
    fn(shield) { shield < entry_stat(entry: frames, stat_id: 20) },
  )
    as "opcode.0x938: the shield falls with the blow"
  game_client.close(game:)
  login_support.stop(started)
}

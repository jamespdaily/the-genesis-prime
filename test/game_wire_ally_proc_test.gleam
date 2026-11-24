//// A Spellslinger's Healing Salve on an ally, on the whole server: the ally a creature hurts is
//// healed by the Spellslinger's proc, as the two players' clients read it.
//// Every wait is for bytes the server writes or for a message of the one sender it waits
//// for, with a deadline a passing test never reaches. The tree, the logins and the players
//// come from `game_wire_support`.

import client_tables
import driven_time
import game_client
import game_connection_support as connection_support
import game_wire_support.{
  TwoEntered, dagun_attack_interval_ms, dagun_z, health_in,
  read_after_the_map_and_the_creature_took_it, refusals, two_players_enter_after,
  unit_of, walk_to, world_with_a_dagun_on,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/loadout
import genesis_prime/game/player_life
import genesis_prime/game/rating
import genesis_prime/message/spell_started
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/table/id.{ClassId}
import gleam/list
import gleam/option.{Some}
import login_support
import owned_test
import properties_support
import spell_tables
import unitest

/// The Dagun's attack row, Spell4Effects 184741 (Spell4 5649): the row a blow's description of
/// the 0x7f4 names.
const dagun_attack_effect = 184_741

/// Healing Salve's heal, Spell4 39127, and the child 39386 that holds the proc rows and is the
/// root and the parent of each fire.
const heal = 39_127

const salve_child = 39_386

/// Each description the 0x7f4 of the frames lists on `unit`, in order.
fn descriptions_on(
  frames frames: List(Frame),
  unit unit: Int,
) -> List(game_client.Blow) {
  list.flat_map(game_client.fight_in(frames:), fn(event) {
    case event {
      game_client.Went(targets:, ..) ->
        targets
        |> list.filter(fn(target) { target.0 == unit })
        |> list.flat_map(fn(target) { target.1 })
      _ -> []
    }
  })
}

/// The Dagun's blows among the frames, as the target `unit` reads them: each description of the
/// attack row on that unit, in order.
fn blows_on(
  frames frames: List(Frame),
  unit unit: Int,
) -> List(game_client.Blow) {
  list.filter(descriptions_on(frames:, unit:), fn(blow) {
    blow.effect_id == dagun_attack_effect
  })
}

/// How many times each step of the health the frames give `unit` (starting from `start`) falls
/// and rises, in that order.
fn falls_and_rises(
  start start: Int,
  healths healths: List(Int),
) -> #(Int, Int) {
  list.fold(healths, #(start, #(0, 0)), fn(so_far, health) {
    let #(before, #(falls, rises)) = so_far
    case health < before, health > before {
      True, _ -> #(health, #(falls + 1, rises))
      _, True -> #(health, #(falls, rises + 1))
      False, False -> #(health, #(falls, rises))
    }
  }).1
}

/// The primary target, root, parent and caster of each 0x7ff of the heal 39127 among the frames.
fn heal_starts_in(frames frames: List(Frame)) -> List(#(Int, Int, Int, Int)) {
  list.filter_map(
    connection_support.decoded(
      frames,
      spell_started.message_id,
      spell_started.decode,
    ),
    fn(start) {
      case start.spell4_id == heal {
        True ->
          Ok(#(
            start.primary_target_unit_id,
            start.root_spell4_id,
            start.parent_spell4_id,
            start.caster_unit_id,
          ))
        False -> Error(Nil)
      }
    },
  )
}

pub fn a_spellslinger_pressing_healing_salve_has_the_ally_in_range_healed_when_a_creature_hurts_it_once_in_two_seconds_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  // The sources of the count of two (Spell4Effects 86457's window and count, the Dagun's
  // interval, the ally's deflect chance), pinned from the tables before anything runs: blows
  // one interval apart, the first at one interval, fire at the first and the third and not at
  // the second or the fourth.
  let row = spell_tables.effect_row_in(tables:, id: 86_457)
  let interval_ms = dagun_attack_interval_ms()
  assert row.effect_type == 14 && row.data_bits05 == 1
    as "Spell4Effects 86457 is a Proc row that fires once in its window (effectType.14.limits)"
  assert interval_ms < row.data_bits04 && 2 * interval_ms >= row.data_bits04
    as "the Dagun's blows are one interval apart: the second blow is inside the window of the first fire and the third is outside it, so blows 1 and 3 fire and 2 and 4 do not"
  let assert Ok(medic) =
    loadout.of(tables:, class_id: ClassId(4), faction_id: 166)
    as "the tables hold the Medic's Novice set"
  assert player_life.defence(
      properties: properties_support.wearing(loadout: medic),
      level: 10,
      formulas: rating.formulas(tables:),
    ).deflect_chance
    == 0.0
    as "a rating of 0 gives GameFormula 1235's intercept, 0 (rating.to_fraction): the ally deflects no blow, so every blow raises TakesDamage"
  let started = world_with_a_dagun_on(tables:, blow: Some(100), time:)
  let TwoEntered(
    first: caster,
    second: ally,
    first_burst:,
    first_acted:,
    second_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) =
    two_players_enter_after(
      started:,
      first_class: 7,
      level: 10,
      first_acts: fn(game, have) {
        game_client.read_until(game:, have:, found: fn(frames) {
          game_client.creatures_created_in(frames:) != []
        })
      },
    )
  let assert [dagun] = game_client.creatures_created_in(frames: first_acted)
  let caster_unit =
    game_client.unit_create_player_in(frames: first_burst).unit_id
  let ally_unit = unit_of(seen_second)
  let entry_health = health_in(frames: second_burst)
  assert entry_health > 4 * 100
    as "the ally enters with far more health than four planted blows of 100 take"
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: 1100))
  game_client.send_world(
    game: caster,
    message_id: terrain_loaded.message_id,
    body:,
  )
  game_client.send_world(
    game: ally,
    message_id: terrain_loaded.message_id,
    body:,
  )
  // The press: Healing Salve (Spell4 39121, Spell4Base 23468, castTime 1000) with the ally
  // standing beside the caster, inside its 20 m; the go and the ally's own listing of it come
  // before the ally walks, so no blow can fall before the proc rows are held on the ally.
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 7,
      level: 10,
      ability: 23_468,
    )
  game_client.press_ability(
    game: caster,
    client_cast_id: 1,
    bag_index:,
    target: 0,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: caster, have: first_have, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Healing Salve is planned, so the press is not refused"
  driven_time.advance(time:, ms: 1000)
  let #(_, second_have) =
    game_client.read_until(game: ally, have: second_have, found: fn(frames) {
      list.any(game_client.casts_in(frames:), fn(event) {
        case event {
          game_client.CastWent(..) -> True
          _ -> False
        }
      })
    })
  // The ally walks into the Dagun's ring (9 m, inside its aggro range): the Dagun's blows fall
  // at one interval, two, three and four after this moment on the driven clock.
  walk_to(game: ally, z: dagun_z +. 9.0, clock: 100)
  let #(walked, second_have) =
    read_after_the_map_and_the_creature_took_it(
      game: ally,
      have: second_have,
      started:,
      dagun: dagun.unit_id,
      pongs: #(1, 2),
    )
  let #(ally_read, second_have, _) =
    list.fold([1, 2, 3, 4], #(walked, second_have, 0), fn(so_far, blow) {
      let #(read, second_have, _) = so_far
      driven_time.advance(time:, ms: interval_ms)
      let #(more, second_have) =
        game_client.read_until(game: ally, have: second_have, found: fn(frames) {
          list.length(blows_on(
            frames: list.append(read, frames),
            unit: ally_unit,
          ))
          >= blow
        })
      #(list.append(read, more), second_have, blow)
    })
  let blows = blows_on(frames: ally_read, unit: ally_unit)
  assert list.length(blows) == 4
    as "the Dagun strikes the ally at each of its four ticks"
  assert list.all(blows, fn(blow) { blow.health_damage > 0 })
    as "opcode.0x7f4: each blow took health from the ally and none was deflected, so each raised TakesDamage"
  // The caster reads up to the ally's health news of blow 4 falling: the ally's connection
  // sends the news before the event tell of the same blow, so the fall of blow 4 follows the
  // event tell of blow 3 and the caster has by then taken every tell of blows 1 to 3.
  let ally_health_in = fn(frames) {
    falls_and_rises(
      start: health_in(frames: [seen_second]),
      healths: game_client.health_of(
        events: game_client.fight_in(frames:),
        unit: ally_unit,
      ),
    )
  }
  let #(caster_read, _) =
    game_client.read_until(game: caster, have: first_have, found: fn(frames) {
      ally_health_in(frames).0 >= 4
    })
  assert heal_starts_in(frames: caster_read)
    == [
      #(ally_unit, salve_child, salve_child, caster_unit),
      #(ally_unit, salve_child, salve_child, caster_unit),
    ]
    as "opcode.0x7ff: the caster reads exactly two child casts of 39127, one at each of blows 1 and 3, each naming the ally as its primary target and 39386 as its root and parent"
  assert game_client.casts_in(frames: list.append(pressed, caster_read))
    |> list.filter(fn(event) {
      case event {
        game_client.CastConfirmed(..) -> True
        _ -> False
      }
    })
    |> list.length
    == 1
    as "opcode.0x7fd: only the press is answered; a proc's child cast has no press to answer"
  // The ally reads its health rise once for each fire.
  let #(ally_rest, _) =
    game_client.read_until(game: ally, have: second_have, found: fn(frames) {
      let healths =
        game_client.own_health_of(
          events: game_client.fight_in(frames: list.append(ally_read, frames)),
          unit: ally_unit,
        )
      falls_and_rises(start: entry_health, healths:).1 >= 2
    })
  let ally_frames = list.append(ally_read, ally_rest)
  let healths =
    game_client.own_health_of(
      events: game_client.fight_in(frames: ally_frames),
      unit: ally_unit,
    )
  assert falls_and_rises(start: entry_health, healths:) == #(4, 2)
    as "opcode.0x92f: the ally's health fell at each of the four blows and rose at two heals"
  assert list.map(heal_starts_in(frames: ally_frames), fn(start) { start.3 })
    == [caster_unit, caster_unit]
    as "opcode.0x7ff: the ally's client reads each heal as a cast of the Spellslinger"
  let amounts = heal_amounts_on(frames: ally_frames, unit: ally_unit)
  assert list.length(amounts) == 2
    && list.all(amounts, fn(amount) { amount > 0 })
    as "opcode.0x7f4: the ally's client reads the two heals' go each listing an amount above 0"
  game_client.close(game: caster)
  game_client.close(game: ally)
  login_support.stop(started)
}

/// The amount of each description of the heal 39127's go the frames list on `unit`: every
/// description that is not the Dagun's blow.
fn heal_amounts_on(frames frames: List(Frame), unit unit: Int) -> List(Int) {
  descriptions_on(frames:, unit:)
  |> list.filter(fn(blow) { blow.effect_id != dagun_attack_effect })
  |> list.map(fn(blow) { blow.raw_damage })
}

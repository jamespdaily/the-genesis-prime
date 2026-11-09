//// An Engineer's Volatility on the game connection: the Pulse Blast that opens a fight
//// gives 15, and Volatility empties 5000 ms after combat ends, written as 0x935 of the
//// player's own client. Expected values come from these places:
//// - The client: a resource slot is a 32-bit float the server sets by 0x935 (`opcode.0x935`);
////   slot 1 is stat 3 (`opcode.0x262.resource_stats`); Spell4Effects 95337 gives +15 of
////   vital 6 in the hidden 42148 behind prerequisite 903 (`Spell4.42148`); Electrocute
////   costs 8 of vital 6 (Spell4 41276, `Spell4CastResult.vital_cost`: 51 for an empty slot 1).
//// - Jim's decisions of 2026-11-06 (issue 419): the opener gives 15 too, and Volatility
////   empties 5000 ms after the combat flag clears.
//// - The creature's order: its answer to a strike goes before its `Threatened`, and it
////   answers the damage spell's later strikes after both (genesis_prime/world_map/creature
////   `struck`: one sender, one order), so the test lands the first strike, feeds the threat,
////   and lands the rest (`pressed_and_threatened`).

import cast_support
import connection_rule_support as support
import fixture_tables
import game_client
import game_connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/class_resource
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/message/float32
import genesis_prime/message/unit_float_stat_changed.{
  type UnitFloatStatChanged, UnitFloatStatChanged,
}
import genesis_prime/step.{
  type ConnectionStep, type TimerId, CancelTimer, OwnEffect, OwnEvent,
  StartTimer, TimerFired,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/spell4
import gleam/int
import gleam/list
import owned_test
import spell_tables

const pulse_blast_base = 26_468

const electrocute_base = 25_473

/// The creature the Engineer fights, a Beast 3 m ahead (`game_connection_support.beast_appears`).
const beast = 40

/// The 0x935s the steps write, decoded.
fn changes(steps: List(ConnectionStep(Request))) -> List(UnitFloatStatChanged) {
  list.flat_map(steps, fn(taken) {
    list.filter_map(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      fn(frame) {
        case frame.message_id == unit_float_stat_changed.message_id {
          True -> {
            let assert Ok(changed) = unit_float_stat_changed.decode(frame.body)
              as "0x935 decodes"
            Ok(changed)
          }
          False -> Error(Nil)
        }
      },
    )
  })
}

/// The timers of the class resource the steps start, as (timer, after_ms).
fn started(steps: List(ConnectionStep(Request))) -> List(#(TimerId, Int)) {
  list.flat_map(steps, fn(taken) {
    list.filter_map(support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(StartTimer(timer:, after_ms:)) ->
          case class_resource.owns(timer:) {
            True -> Ok(#(timer, after_ms))
            False -> Error(Nil)
          }
        OwnEffect(_)
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | step.Stop -> Error(Nil)
      }
    })
  })
}

/// The timers of the class resource the steps cancel.
fn cancelled(steps: List(ConnectionStep(Request))) -> List(TimerId) {
  list.flat_map(steps, fn(taken) {
    list.filter_map(support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(CancelTimer(timer:)) ->
          case class_resource.owns(timer:) {
            True -> Ok(timer)
            False -> Error(Nil)
          }
        OwnEffect(_)
        | step.Watch(..)
        | step.Unwatch(..)
        | step.Log(..)
        | step.Stop -> Error(Nil)
      }
    })
  })
}

/// The Engineer in the world with a Beast in front of it, Pulse Blast's bag index and
/// Electrocute's.
fn engineer() -> #(game_connection.State, Int, Int, Int) {
  let #(state, unit_id, pulse_blast) =
    game_connection_support.entered_with_server_proxies(
      class_id: 2,
      ability: pulse_blast_base,
      proxies: spell_tables.server_proxies(),
      tables: fixture_tables.shared(),
    )
  let #(_, _, electrocute) =
    game_connection_support.entered_with_server_proxies(
      class_id: 2,
      ability: electrocute_base,
      proxies: spell_tables.server_proxies(),
      tables: fixture_tables.shared(),
    )
  let #(state, _) =
    game_connection_support.at(
      state:,
      ms: 900,
      event: game_connection_support.beast_appears(unit_id: beast),
    )
  #(state, unit_id, pulse_blast, electrocute)
}

/// A press of the bag index at `ms`, and the cast timers it leads to up to `until_ms`, each
/// strike landing, and the creature's `Threatened` following its first answer, as the
/// creature sends them.
fn pressed_and_threatened(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  pressed_with(
    state:,
    bag_index:,
    client_cast_id:,
    ms:,
    until_ms:,
    threatened: False,
  )
}

/// The same for a player the creature already threatens: its `Threatened` was told once and
/// is not told again.
fn pressed_in_combat(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  pressed_with(
    state:,
    bag_index:,
    client_cast_id:,
    ms:,
    until_ms:,
    threatened: True,
  )
}

fn pressed_with(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
  until_ms until_ms: Int,
  threatened threatened: Bool,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  let #(state, _, steps) =
    game_connection_support.pressed_until_answered(
      state:,
      world: threatened,
      bag_index:,
      client_cast_id:,
      ms:,
      until_ms:,
      answer: landed_and_threatened,
    )
  #(state, steps)
}

/// Every strike of the step lands, and the creature's `Threatened` follows the first
/// strike a cast tells while the player is not yet threatened; the world is whether the
/// creature has threatened the player.
fn landed_and_threatened(
  threatened threatened: Bool,
  state state: game_connection.State,
  ms ms: Int,
  taken taken: ConnectionStep(Request),
) -> #(Bool, game_connection.State, List(ConnectionStep(Request))) {
  let #(state, landed) = game_connection_support.landing(state:, ms:, taken:)
  let struck =
    list.any(landed, fn(step) {
      game_connection_support.strikes_told(step) != []
    })
  case struck && !threatened {
    True -> {
      let #(state, told) =
        game_connection_support.at(
          state:,
          ms:,
          event: game_connection_support.foe(strike_tell.Threatened(
            unit_id: beast,
            life: 4,
          )),
        )
      #(True, state, list.append(landed, [told]))
    }
    False -> #(threatened, state, landed)
  }
}

pub fn the_pulse_blast_that_opens_a_fight_gives_15_volatility_and_it_empties_5_seconds_after_combat_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, unit_id, pulse_blast, _) = engineer()
  let #(state, pressed) =
    pressed_and_threatened(
      state:,
      bag_index: pulse_blast,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 2300,
    )
  assert list.flat_map(pressed, game_connection_support.strikes_told) != []
    as "the Beast in front of the Engineer is struck by the damage spell's goes"
  assert changes(pressed)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(15.0)),
    ]
    as "the opener gives 15 (Jim's decision): 42148's +15 of slot 1 (Spell4Effects 95337, behind 903) comes with the damage spell's last go, when the first strike's threat has put the player in combat, one 0x935 of stat 3 to the player's own client"
  assert started(pressed) == [] as "in combat the Volatility waits for nothing"
  let #(state, released) =
    game_connection_support.at(
      state:,
      ms: 3000,
      event: game_connection_support.foe(strike_tell.Released(unit_id: beast)),
    )
  assert started([released]) == [#(class_resource.empty_timer, 5000)]
    as "leaving combat starts the 5000 ms wait (Spell4.34630: 34688 lasts 5000 ms)"
  assert changes([released]) == [] as "nothing is written before the wait ends"
  let #(state, back) =
    game_connection_support.at(
      state:,
      ms: 5000,
      event: game_connection_support.foe(strike_tell.Threatened(
        unit_id: beast,
        life: 4,
      )),
    )
  assert cancelled([back]) == [class_resource.empty_timer]
    as "combat again within the wait stops it: Volatility stays (34630's 11835 gives no drain in combat)"
  let #(state, released_again) =
    game_connection_support.at(
      state:,
      ms: 6000,
      event: game_connection_support.foe(strike_tell.Released(unit_id: beast)),
    )
  assert started([released_again]) == [#(class_resource.empty_timer, 5000)]
    as "leaving again starts a new 5000 ms wait"
  let #(_, emptied) =
    game_connection_support.at(
      state:,
      ms: 11_000,
      event: OwnEvent(TimerFired(timer: class_resource.empty_timer)),
    )
  assert changes([emptied])
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(0.0)),
    ]
    as "5000 ms after combat ended Volatility is 0, one 0x935"
}

pub fn electrocute_is_refused_51_at_0_volatility_and_costs_8_of_the_15_a_pulse_blast_gave_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, unit_id, pulse_blast, electrocute) = engineer()
  let #(refused_state, refusal) =
    game_connection_support.pressed_until(
      state:,
      bag_index: electrocute,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 1000,
    )
  let events =
    game_client.casts_in(
      frames: list.flat_map(refusal, fn(taken) {
        game_connection_support.heard(taken, game_connection_support.keyed())
      }),
    )
  assert events
    == [
      game_client.CastRefused(client_cast_id: 1, spell4_id: 41_276, result: 51),
    ]
    as "an empty slot 1 refuses Electrocute's 8 of vital 6 with 50 + 1 (Spell4 41276 innateCostType0 6, `Spell4CastResult.vital_cost`)"
  let #(state, _) =
    pressed_and_threatened(
      state: refused_state,
      bag_index: pulse_blast,
      client_cast_id: 2,
      ms: 1100,
      until_ms: 2450,
    )
  let #(_, cast) =
    game_connection_support.pressed_until(
      state:,
      bag_index: electrocute,
      client_cast_id: 3,
      ms: 4000,
      until_ms: 6000,
    )
  assert changes(cast)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(7.0)),
    ]
    as "with the 15 a Pulse Blast gave, Electrocute is accepted and its first go pays 8: the slot shows 7"
}

// ---- 6 ----

pub fn seven_in_combat_pulse_blasts_give_15_30_to_90_then_100_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(row) =
    spell4.get(tables: fixture_tables.shared(), id: Spell4Id(42_276))
    as "the client's Spell4 holds Pulse Blast's row 42276"
  assert row.prerequisite_id_caster_persistence == 0
    as "the client's Spell4 row 42276 holds no CasterPersistence prerequisite"
  let #(state, unit_id, pulse_blast, _) = engineer()
  let #(state, _) =
    game_connection_support.at(
      state:,
      ms: 950,
      event: game_connection_support.foe(strike_tell.Threatened(
        unit_id: beast,
        life: 4,
      )),
    )
  let #(_, shown) =
    list.index_fold(list.repeat(Nil, 7), #(state, []), fn(so_far, _, blast) {
      let #(state, shown) = so_far
      let ms = 1000 + blast * 3000
      let #(state, steps) =
        pressed_in_combat(
          state:,
          bag_index: pulse_blast,
          client_cast_id: blast + 1,
          ms:,
          until_ms: ms + 1500,
        )
      #(state, list.append(shown, changes(steps)))
    })
  assert shown
    == list.map([15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 100.0], fn(volatility) {
      UnitFloatStatChanged(
        unit_id:,
        stat_id: 3,
        value: float32.to_bits(volatility),
      )
    })
    as "each blast in combat gives +15 (Spell4Effects 95337), one 0x935 each, and the seventh is clamped to the Engineer's 100 (migration 0011: Volatility's maximum)"
}

// ---- the order the opener rests on ----

/// The cast timers of the steps fired in time order up to `until_ms` with no strike
/// answered: the steps, and the key of each strike told.
fn fired_unanswered(
  state state: game_connection.State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  steps steps: List(ConnectionStep(Request)),
  keys keys: List(strike_tell.Key),
) -> #(
  game_connection.State,
  List(ConnectionStep(Request)),
  List(strike_tell.Key),
) {
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [#(due, timer), ..rest] if due <= until_ms -> {
      let #(state, fired) =
        game_connection_support.at(
          state:,
          ms: due,
          event: OwnEvent(TimerFired(timer:)),
        )
      fired_unanswered(
        state:,
        pending: list.append(
          rest,
          game_connection_support.cast_timers(steps: [fired], ms: due),
        ),
        until_ms:,
        steps: list.append(steps, [fired]),
        keys: list.append(
          keys,
          list.map(game_connection_support.strikes_told(fired), fn(told) {
            told.1
          }),
        ),
      )
    }
    [_, ..] | [] -> #(state, steps, keys)
  }
}

pub fn three_open_rounds_closed_by_answer_1_the_threat_then_answers_2_and_3_give_one_gain_of_15_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, unit_id, pulse_blast, _) = engineer()
  let #(state, pressed) =
    game_connection_support.at(
      state:,
      ms: 1000,
      event: OwnEvent(
        step.Read(game_connection_support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id: 1,
            bag_index: pulse_blast,
            target: 0,
            press: 1,
          ),
        )),
      ),
    )
  let #(state, steps, keys) =
    fired_unanswered(
      state:,
      pending: game_connection_support.cast_timers(steps: [pressed], ms: 1000),
      until_ms: 2300,
      steps: [pressed],
      keys: [],
    )
  assert list.map(keys, fn(key) { key.phase }) == [1, 2, 3]
    as "the damage spell strikes in its goes 1 to 3 (Spell4Effects 79090, 79092, 79093: phaseFlags 2, 4, 8): three rounds are open"
  assert changes(steps) == [] as "nothing is given while the rounds are open"
  let assert [first, second, third] = keys
  let answer = fn(state, key) {
    game_connection_support.at(
      state:,
      ms: 2300,
      event: game_connection_support.landed(key:),
    )
  }
  let #(state, answered_1) = answer(state, first)
  let #(state, threatened) =
    game_connection_support.at(
      state:,
      ms: 2300,
      event: game_connection_support.foe(strike_tell.Threatened(
        unit_id: beast,
        life: 4,
      )),
    )
  let #(state, answered_2) = answer(state, second)
  let #(_, answered_3) = answer(state, third)
  assert changes([answered_1, threatened, answered_2]) == []
    as "rounds close in phase order and the damage spell's last go has not gone"
  assert changes([answered_3])
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(15.0)),
    ]
    as "answer 1, the creature's Threatened and answers 2 and 3 come from one creature in that order: the third round closes with the player in combat, and the gain is one 0x935 of 15"
}

// ---- 9 ----

/// Whether the news is one of a cast's, or the combat flag's, which the creature's threat
/// sets (0x89a).
fn is_cast_or_combat_news(news: client_connection.News) -> Bool {
  case news {
    client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastFinished(..)
    | client_connection.CastMissed(..)
    | client_connection.CastTargetsRemoved(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.CombatState(..) -> True
    client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | client_connection.Removed
    | client_connection.Health(..)
    | client_connection.Died
    | client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged
    | client_connection.CreatureMoved(..)
    | client_connection.CreaturePlaced(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.Shield(..)
    | client_connection.CrowdControlApplied(..)
    | client_connection.CrowdControlEnded(..)
    | client_connection.InterruptArmor(..)
    | client_connection.Absorption(..)
    | client_connection.Level(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..)
    | client_connection.LookChanged(..) -> False
  }
}

pub fn a_viewer_of_the_engineer_is_told_42148s_cast_and_never_the_volatility_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _, pulse_blast, _) = engineer()
  let state = game_connection_support.watched_by(state:, viewers: [2])
  let #(_, steps) =
    pressed_and_threatened(
      state:,
      bag_index: pulse_blast,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 2300,
    )
  let told_viewer =
    list.flat_map(steps, fn(taken) {
      list.filter_map(game_connection_support.peer_tells(taken), fn(tell) {
        case tell.0 == 2 {
          True -> Ok({ tell.1 }.news)
          False -> Error(Nil)
        }
      })
    })
  assert list.any(told_viewer, fn(news) {
    case news {
      client_connection.CastStarted(start:) -> start.spell4_id == 42_148
      client_connection.CastWent(..)
      | client_connection.CastFinished(..)
      | client_connection.CastMissed(..)
      | client_connection.CastTargetsRemoved(..)
      | client_connection.CastStackRemoved(..)
      | client_connection.Appeared(..)
      | client_connection.CreatureAppeared(..)
      | client_connection.Moving(..)
      | client_connection.Removed
      | client_connection.Health(..)
      | client_connection.Died
      | client_connection.CameBack
      | client_connection.DeathLogged
      | client_connection.CameBackLogged
      | client_connection.CreatureMoved(..)
      | client_connection.CreaturePlaced(..)
      | client_connection.Targeting(..)
      | client_connection.Threat(..)
      | client_connection.CombatState(..)
      | client_connection.Shield(..)
      | client_connection.CrowdControlApplied(..)
      | client_connection.CrowdControlEnded(..)
      | client_connection.InterruptArmor(..)
      | client_connection.Absorption(..)
      | client_connection.Level(..)
      | client_connection.PropertiesChanged(..)
      | client_connection.Stealth(..)
      | client_connection.LookChanged(..) -> False
    }
  })
    as "the viewer is told 42148's start, which it writes as 0x7ff for a caster it shows (opcode.0x7ff)"
  assert list.all(told_viewer, is_cast_or_combat_news)
    as "everything the viewer is told of the Engineer's blast is a cast's news or the combat flag's: no news carries a class resource, which 0x935 sets for the player's own client alone (class_resource header)"
  assert list.length(changes(steps)) == 1
    as "the one 0x935 of the run is written to the player's own client"
}

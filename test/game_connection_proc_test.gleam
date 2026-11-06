//// The Stalker's procs on the game connection (`genesis_prime/game/connection`, with the
//// client's own tables): a press of Nano Skin: Lethal enters and leaves stealth, and the
//// passive's Proc rows cast their spells at it; a killing strike in combat leaves combat and
//// dies. Expected values come from these places:
//// - `Spell4Effects.effectType.14.dataBits00.217_218` and `.0_44`: 45057's Proc 147119 (kind
////   217) casts 60724, 147132 and 211002 (kind 218) cast 60769 and 79932, 159136 (kind 44) and
////   202043 (kind 0) cast 63366.
//// - `Spell4.79932`: Empower, BaseCritChance (102) x1.0 + 0.2 and DamageDealtMultiplier (141
////   to 143) x1.08 for 3000 ms, as 0x93a entries with 32-bit floats (`opcode.0x93a`).
//// - `opcode.0x7ff.root_parent`: a proc's cast is a 0x7ff with no 0x7fd.
//// - `Spell4Effects.effectType.73`: 63366 sets the Stealth cooldown to 250 ms, which a press
////   within the 500 ms queue window waits for, where an uncut cooldown refuses it (15).
//// Skipped where the client's tables are not on the machine.

import cast_support
import client_tables
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request, CastStarted, PeerNews}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_started
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_stealth
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import genesis_prime/world_map/map
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test
import unitest

fn written(taken taken: ConnectionStep(Request)) -> List(Frame) {
  connection_support.heard(taken, connection_support.keyed())
}

fn ids(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

fn started_spells(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "a 0x7ff decodes"
        Ok(start.spell4_id)
      }
      False -> Error(Nil)
    }
  })
}

fn stealth_bits(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == 0x08F5 {
      True -> {
        let assert Ok(change) = unit_stealth.decode(frame.body)
          as "a 0x8F5 decodes"
        Ok(change.stealthed)
      }
      False -> Error(Nil)
    }
  })
}

/// A press of the bag index at this monotonic time, as the client sends it.
fn pressed(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(
    state,
    support.input_at_ms(
      ms:,
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id:,
            bag_index:,
            target: 0,
            press: 1,
          ),
        )),
      ),
    ),
  )
}

/// The cast timers a step starts: the cast rule's ids begin at 1000.
fn cast_timers(taken taken: ConnectionStep(Request)) -> List(step.TimerId) {
  list.filter(support.timers_started(taken), fn(timer) {
    let step.TimerId(number) = timer
    number >= 1000
  })
}

/// A timer fired at this monotonic time.
fn fired_at(
  state state: game_connection.State,
  timer timer: step.TimerId,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(
    state,
    support.input_at_ms(ms:, event: OwnEvent(TimerFired(timer))),
  )
}

/// The properties 0x93a entries a step writes, as (property, value bits).
fn property_values(taken taken: ConnectionStep(Request)) -> List(#(Int, Int)) {
  connection_support.decoded(
    written(taken:),
    0x093A,
    unit_properties_changed.decode,
  )
  |> list.flat_map(fn(message: unit_properties_changed.UnitPropertiesChanged) {
    list.map(message.properties, fn(property) {
      #(property.property_id, property.value)
    })
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

/// How many times a step tells viewer 2 the start of the cast `start` names.
fn told_of(
  taken taken: ConnectionStep(Request),
  start start: spell_started.SpellStarted,
) -> Int {
  list.count(connection_support.peer_tells(taken), fn(tell) {
    let PeerNews(news:, ..) = tell.1
    tell.0 == 2 && news == CastStarted(start:)
  })
}

/// The 0x7ff of the cast of this Spell4 that a step writes to the player, decoded.
fn start_of(
  taken taken: ConnectionStep(Request),
  spell4_id spell4_id: Int,
) -> spell_started.SpellStarted {
  let assert Ok(start) =
    list.filter_map(written(taken:), fn(frame) {
      case frame.message_id == spell_started.message_id {
        True -> {
          let assert Ok(start) = spell_started.decode(frame.body)
            as "a 0x7ff decodes"
          case start.spell4_id == spell4_id {
            True -> Ok(start)
            False -> Error(Nil)
          }
        }
        False -> Error(Nil)
      }
    })
    |> list.first
    as "the step writes the cast's 0x7ff"
  start
}

fn stalker_in_world() -> game_connection.State {
  let #(state, _) =
    connection_support.entered_on_the_clients_tables(
      class_id: 5,
      saved_health: None,
    )
  connection_support.watched_by(state:, viewers: [2])
}

/// The frames of the step from the first of this id on.
fn from_id(frames frames: List(Frame), id id: Int) -> List(Int) {
  list.drop_while(ids(frames:), fn(found) { found != id })
}

pub fn a_stalker_pressing_stealth_twice_gets_the_procs_casts_and_empower_for_3_seconds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, entering) =
    pressed(
      state: stalker_in_world(),
      bag_index: 3,
      client_cast_id: 1,
      ms: 1000,
    )
  let frames = written(taken: entering)
  assert stealth_bits(frames:) == [1]
  assert list.take(from_id(frames:, id: 0x08F5), 4)
    == [0x08F5, 0x07FF, 0x07F4, 0x07FE]
    as "0x8f5 {P, 1}, then Proc 147119's cast of 60724: its 0x7ff, 0x7f4 and 0x7fe"
  assert list.last(started_spells(frames:)) == Ok(60_724)
    as "the cast after the 0x8f5 is 60724"
  let #(state, leaving) =
    pressed(state:, bag_index: 3, client_cast_id: 2, ms: 3000)
  let frames = written(taken: leaving)
  assert stealth_bits(frames:) == [0]
  assert list.take(from_id(frames:, id: 0x08F5), 1) == [0x08F5]
  let after_stealth =
    list.drop_while(frames, fn(frame) { frame.message_id != 0x08F5 })
  assert started_spells(frames: after_stealth) == [60_769, 79_932]
    as "Procs 147132 and 211002 cast 60769 and 79932 after the 0x8f5 {P, 0}"
  assert property_values(taken: leaving)
    == [
      #(102, 1_045_220_557),
      #(141, 1_066_024_305),
      #(142, 1_066_024_305),
      #(143, 1_066_024_305),
    ]
    as "Spell4.79932: BaseCritChance 0.2 (0x3e4ccccd) and the three DamageDealtMultipliers 1.08 (0x3f8a3d71)"
  assert told_of(
      taken: entering,
      start: start_of(taken: entering, spell4_id: 60_724),
    )
    == 1
    && told_of(
      taken: leaving,
      start: start_of(taken: leaving, spell4_id: 60_769),
    )
    == 1
    && told_of(
      taken: leaving,
      start: start_of(taken: leaving, spell4_id: 79_932),
    )
    == 1
    as "a second player in sight is told the three procs' casts"
  // 3 s later the modifiers end and Empower's cast ends.
  let #(_, ended) =
    list.fold(cast_timers(taken: leaving), #(state, []), fn(so_far, timer) {
      let #(state, steps) = so_far
      let #(state, taken) = fired_at(state:, timer:, ms: 6001)
      #(state, [taken, ..steps])
    })
  let later = list.flat_map(ended, fn(taken) { written(taken:) })
  assert list.sort(
      list.flat_map(ended, fn(taken) { property_values(taken:) }),
      fn(first, second) { int.compare(first.0, second.0) },
    )
    == [
      #(102, 0),
      #(141, 1_065_353_216),
      #(142, 1_065_353_216),
      #(143, 1_065_353_216),
    ]
    as "after 3000 ms the properties are back at their defaults, 0.0 and 1.0"
  assert list.contains(ids(frames: later), 0x07FE)
    as "and 79932's cast ends with its 0x7fe"
}

pub fn a_stalker_killed_in_combat_gets_63366_twice_and_its_stealth_press_after_the_wake_is_not_refused_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let state = stalker_in_world()
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, entering) =
    pressed(state:, bag_index: 3, client_cast_id: 1, ms: 1000)
  assert stealth_bits(frames: written(taken: entering)) == [1]
  let #(state, death) =
    connection_support.feed(
      state:,
      event: connection_support.a_killing_strike(),
    )
  let frames = written(taken: death)
  assert list.filter(started_spells(frames:), fn(spell4_id) {
      spell4_id == 63_366
    })
    == [63_366, 63_366]
    as "Procs 159136 (kind 44, the combat flag going off) and 202043 (kind 0, the death) each cast 63366"
  assert list.filter(started_spells(frames:), fn(spell4_id) {
      spell4_id == 60_769 || spell4_id == 79_932
    })
    == []
    as "the dead player's stealth ends with no Empower: row 1 refuses a dead caster"
  let finished_ids =
    list.filter_map(frames, fn(frame) {
      case frame.message_id == 0x07FE {
        True -> {
          let assert Ok(finished) = spell_finished.decode(frame.body)
            as "a 0x7fe decodes"
          Ok(finished.cast_id)
        }
        False -> Error(Nil)
      }
    })
  let of_63366 =
    list.filter_map(frames, fn(frame) {
      case frame.message_id == spell_started.message_id {
        True -> {
          let assert Ok(start) = spell_started.decode(frame.body)
            as "a 0x7ff decodes"
          case start.spell4_id == 63_366 {
            True -> Ok(start.cast_id)
            False -> Error(Nil)
          }
        }
        False -> Error(Nil)
      }
    })
  let assert [first_63366, second_63366] = of_63366
  assert list.filter(ids(frames:), fn(id) {
      list.contains(
        [0x0811, 0x08F5, 0x089A, 0x07FF, 0x07F4, 0x07FE, 0x0247],
        id,
      )
    })
    == [
      0x0811,
      0x08F5,
      0x089A,
      0x07FF,
      0x07F4,
      0x07FE,
      0x07FF,
      0x07F4,
      0x07FE,
      0x0247,
    ]
    as "the lethal blow breaks the stealth first (Spell4Effects.effectType.83: dataBits02 0; the blow's damage is taken before the death): the stealth cast's 0x811 and 0x8f5 {P, 0}; then 0x89a; then 63366 for kind 44 and 63366 for kind 0, each with its 0x7ff, 0x7f4 and 0x7fe; then the death's combat log line"
  assert finished_ids == [first_63366, second_63366]
    as "a Normal cast the 0x811 destroys has no 0x7fe, so the two 63366 casts are the only ones to end"
  let #(state, _) =
    connection_support.read(state:, bytes: connection_support.wake_here())
  let #(state, press) =
    pressed(state:, bag_index: 3, client_cast_id: 2, ms: 1000)
  assert !list.contains(ids(frames: written(taken: press)), 0x07FC)
    as "Spell4Effects.effectType.73: 63366 cut the Stealth cooldown to 250 ms, inside the queue window, so the press is held, not refused 15"
  let assert [held] = cast_timers(taken: press)
    as "the held press waits for the cooldown's end"
  let #(_, started) = fired_at(state:, timer: held, ms: 1300)
  assert list.contains(ids(frames: written(taken: started)), 0x07FD)
    as "and starts then, confirmed to the client"
}

pub fn a_stalkers_last_fighter_going_gone_leaves_combat_and_casts_63366_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let state = stalker_in_world()
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, one) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 9, life: 4)),
    )
  assert started_spells(frames: written(taken: one)) == []
  let #(state, first_gone) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(map.Gone(unit_id: 7)),
    )
  assert started_spells(frames: written(taken: first_gone)) == []
    as "a fighter is left: the player is still in combat"
  let #(_, last_gone) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(map.Gone(unit_id: 9)),
    )
  let frames = written(taken: last_gone)
  assert list.filter(ids(frames:), fn(id) { id == 0x089A || id == 0x07FF })
    == [0x089A, 0x07FF]
    as "the map's Gone of the last fighter is its release: 0x89a (P, 0), then Proc 159136's cast"
  assert started_spells(frames:) == [63_366]
    as "Spell4Effects.effectType.14.dataBits00.0_44: leaving combat casts 63366, whether the last fighter released the player or its process went"
}

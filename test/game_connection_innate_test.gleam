//// A player's innate on the game connection (`genesis_prime/game/connection`):
//// the passive the entry starts, the Holocrypt's join that starts it again, and
//// the client's switch 0x16F. The map's answer carries the loadout the client's
//// tables give the class, with the innate (`loadout.of`); the connection's tables
//// are the client's too, which hold the plans. Expected values come from these
//// places.
//// - `Class.spell4IdInnateAbilityPassive00`, `Spell4Effects` of 44926, 45000,
////   45057 and 60724 (`cast_passive_test`): what each passive writes at entry.
//// - `UnitProperty2` 141 to 143: DamageDealtMultiplier Physical, Tech and Magic,
////   default 1.0, so a modifier of x 1.0 + 0 leaves each at its default and
////   `unit_properties` reports a value that did not change as nothing (no 0x93A).
//// - `vector.opcode.0x935` writers: the class resource tells the client its slot
////   changes; the Warrior's Kinetic Energy starts at 0, which -1200 clamps to 0, so
////   nothing changed and nothing is written.
//// - `opcode.0x16f` and `0x1405e7490`: the client sends 0x16F only after switching
////   its own index, never for the index it holds (0, once 0x19F set it), and
////   refuses an index at or above the slots unlocked at its level.
//// Skipped where the client's tables are not on the machine.

import cast_support
import client_tables
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request, FromMap}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/unit_stealth
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import genesis_prime/world_map/map
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import unitest

fn written(taken taken: ConnectionStep(Request)) -> List(Frame) {
  connection_support.heard(taken, connection_support.keyed())
}

fn ids(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

/// The ids of the frames written after the entry's 0x61, in order.
fn after_0x61(frames frames: List(Frame)) -> List(Int) {
  let #(_, rest) = list.split_while(ids(frames:), fn(id) { id != 0x0061 })
  list.drop(rest, 1)
}

/// The timers a step starts for casts: the cast rule's ids begin at 1000.
fn cast_timers_started(
  taken taken: ConnectionStep(Request),
) -> List(step.TimerId) {
  list.filter(support.timers_started(taken), fn(timer) {
    let step.TimerId(number) = timer
    number >= 1000
  })
}

/// The Spell4 ids of the casts the frames start, in order.
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

/// The Spell4Effects ids the go frames list, in id order.
fn listed(frames frames: List(Frame)) -> List(Int) {
  list.filter(frames, fn(frame) { frame.message_id == spell_go.message_id })
  |> list.flat_map(fn(frame) {
    let assert Ok(go) = spell_go.decode(frame.body) as "a go decodes"
    list.flat_map(go.targets, fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
  })
  |> list.sort(int.compare)
}

// ---- the passive at entry ----

pub fn a_warriors_entry_ends_with_its_passives_0x7ff_and_0x7f4_and_no_property_or_resource_news_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(_, taken) =
    connection_support.entered_on_the_clients_tables(
      class_id: 1,
      saved_health: None,
    )
  let frames = written(taken:)
  assert list.take(after_0x61(frames:), 2) == [0x07FF, 0x07F4]
    as "after 0x61 the passive 44926 starts with 0x7ff, and no 0x7fd (no press made it), then its go"
  assert started_spells(frames:) == [44_926]
  assert listed(frames:) == [103_997, 104_001, 112_840, 174_526, 174_527]
    as "Spell4Effects 104001, the three properties and the removal 112840 (cast_passive_test)"
  assert list.all(ids(frames:), fn(id) {
    id != 0x07FD && id != 0x093A && id != 0x0935 && id != 0x07FE && id != 0x0811
  })
    as "UnitProperty2 141 to 143 hold their default 1.0 under x 1.0 + 0, so no 0x93A; Kinetic Energy 0 less 1200 clamps at 0, so no 0x935; nothing ends"
}

pub fn an_engineers_entry_lists_its_three_properties_and_its_conversion_and_starts_46297_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(_, taken) =
    connection_support.entered_on_the_clients_tables(
      class_id: 2,
      saved_health: None,
    )
  let frames = written(taken:)
  assert started_spells(frames:) == [45_000, 46_297]
    as "Proxy 108412 starts 46297 behind Prerequisite 30012, which an Engineer with 0 in slot 1 (Volatility, the start of its resource) and under no cast passes: 29795, the innermost row, wants slot 1 above 29 (cast_passive_test)"
  assert listed(frames:) == [104_980, 177_521, 177_522, 229_304]
  assert list.all(support.logs(taken), fn(line) {
    line.level != step.LogError && line.level != step.LogWarning
  })
    as "the skipped Proxy and row are debug lines, no warning or error"
}

pub fn a_stalkers_passive_starts_60724_50_ms_later_and_that_cast_ends_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, taken) =
    connection_support.entered_on_the_clients_tables(
      class_id: 5,
      saved_health: None,
    )
  let frames = written(taken:)
  assert started_spells(frames:) == [45_057]
    as "the passive 45057 starts; the Proxy to 60724 waits 50 ms"
  assert listed(frames:) == [147_119, 147_132, 159_136, 202_043, 211_002]
    as "the five Proc rows are listed on the holder (Spell4Effects.effectType.14)"
  let cast_timers = cast_timers_started(taken:)
  let assert [timer] = cast_timers as "one cast timer: the 50 ms start of 60724"
  let #(_, later) =
    connection_support.feed(state:, event: OwnEvent(TimerFired(timer)))
  let later_frames = written(taken: later)
  assert ids(frames: later_frames) == [0x07FF, 0x07F4, 0x07FE]
    as "60724 starts, goes with nothing to list (146910 is type 24, not read) and ends"
  assert started_spells(frames: later_frames) == [60_724]
}

pub fn a_class_with_no_passive_starts_no_cast_at_entry_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  list.each([3, 4, 7], fn(class_id) {
    let #(_, taken) =
      connection_support.entered_on_the_clients_tables(
        class_id:,
        saved_health: None,
      )
    assert started_spells(frames: written(taken:)) == []
      as {
        "Class row " <> int.to_string(class_id) <> " names no slot-0 passive"
      }
  })
}

pub fn a_player_saved_dead_starts_its_passive_at_entry_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(_, taken) =
    connection_support.entered_on_the_clients_tables(
      class_id: 1,
      saved_health: Some(0),
    )
  assert started_spells(frames: written(taken:)) == [44_926]
    as "Spell4.44926: the caster condition row 4 holds alive or dead"
}

pub fn the_holocrypts_join_starts_the_passive_again_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, _) =
    connection_support.entered_on_the_clients_tables(
      class_id: 1,
      saved_health: None,
    )
  let #(dead, _) =
    connection_support.killed(
      connection_support.watched_by(state:, viewers: [2]),
    )
  let #(state, taken) =
    connection_support.read(state: dead, bytes: connection_support.holocrypt())
  let #(state, taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(map.Left)),
    )
  let #(_, joined) =
    connection_support.mapped(
      map_state: connection_support.map_after_a_stay(),
      taken:,
    )
  let #(_, joined_taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(connection_support.with_the_clients_loadout(
          joined:,
          class_id: 1,
        )),
      ),
    )
  let frames = written(taken: joined_taken)
  assert started_spells(frames:) == [44_926]
    as "a camp or the Holocrypt dropped the cast, so the next join starts it again, with the innate's item and 0x19F sent as at a play"
  assert list.contains(ids(frames:), 0x019F)
}

// ---- 0x16F ----

/// A 0x16F of the index, inside 0x038C.
fn chosen(index index: Int) -> BitArray {
  connection_support.world_message(message_id: 0x016F, body: <<index:size(8)>>)
}

pub fn a_0x16f_of_index_0_writes_nothing_and_is_a_debug_line_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, _) =
    connection_support.entered_on_the_clients_tables(
      class_id: 1,
      saved_health: None,
    )
  let #(_, taken) = connection_support.read(state:, bytes: chosen(index: 0))
  assert support.writes(taken) == []
    as "opcode.0x16f: the client sent 0 before 0x19F set its index and has switched itself already"
  assert support.asked(taken) == None && !support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: step.LogDebug)) == 1
    as "one debug line says the index was taken"
  assert support.logs_of(step: taken, level: step.LogError) == []
}

pub fn a_0x16f_of_an_index_above_0_ends_the_connection_with_an_error_line_and_nothing_written_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, _) =
    connection_support.entered_on_the_clients_tables(
      class_id: 1,
      saved_health: None,
    )
  list.each([1, 2, 255], fn(index) {
    let #(_, taken) = connection_support.read(state:, bytes: chosen(index:))
    let assert [line] = support.logs_of(step: taken, level: step.LogError)
      as "0x1405e7490: the client refuses an index at or above the slots unlocked at level 1 (one), so it never sends it"
    assert support.says(line, "0x016F")
    assert support.writes(taken) == []
    assert connection_support.ask_request(taken)
      == connection_support.save_asked(1, connection_support.entry_place())
      as "the place is saved as for any refused message, then the connection ends"
  })
}

pub fn a_player_with_no_innate_is_refused_every_index_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each([0, 1, 255], fn(index) {
    let #(_, taken) =
      connection_support.read(
        state: connection_support.in_world(),
        bytes: chosen(index:),
      )
    let assert [line] = support.logs_of(step: taken, level: step.LogError)
      as "the tests' planted Class rows name no innate, so no slot is unlocked (0x1405e7490)"
    assert support.says(line, "0x016F")
    assert support.writes(taken) == []
  })
}

pub fn a_0x16f_before_the_world_is_logged_as_unhandled_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, taken) =
    connection_support.read(
      state: connection_support.in_select(),
      bytes: chosen(index: 0),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x016F))]
    as "routing: 0x016F is taken only with the player in the world"
  assert support.writes(taken) == [] && !support.stops(taken)
}

// ---- the Stalker's stealth and Impale ----

/// A press of the bag index with the target, as the client sends it.
fn pressed(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.read(
    state:,
    bytes: connection_support.world_message(
      message_id: 0x009A,
      body: cast_support.press_body(
        client_cast_id:,
        bag_index:,
        target: 40,
        press: 1,
      ),
    ),
  )
}

pub fn a_stealthed_stalkers_impale_ends_the_stealth_after_its_second_phase_and_not_its_first_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // The client's tables: the Stalker's bag is Shred, Impale 38779, Stagger, then the
  // Nano Skin toggle 46073 (`loadout.of`). Impale holds spellCastStealthChange 1,
  // SpellPhase 3715 and 3716 (a go at 0 and at 300 ms), and its Proxies, behind
  // Prerequisite 38585 (the caster stealthed), and its Fluff child 70775 start in phase 1
  // (phaseFlags 2): `Spell4.spellCastStealthChange.break`, the stealth ends after the
  // cast's effects, so those still see it. The Proxies' target gates 5734 and 5735 are
  // not checked, so no Proxy child starts: the stealth's end is read from the frames.
  let #(state, _) =
    connection_support.entered_on_the_clients_tables(
      class_id: 5,
      saved_health: None,
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.beast_appears(unit_id: 40),
    )
  let #(state, entering) = pressed(state:, bag_index: 3, client_cast_id: 1)
  assert stealth_bits(frames: written(taken: entering)) == [1]
    as "the toggle makes the stealth"
  let #(state, first) = pressed(state:, bag_index: 1, client_cast_id: 2)
  assert stealth_bits(frames: written(taken: first)) == []
    as "Impale's first go ends nothing: its last go is 300 ms later"
  assert !list.contains(ids(frames: written(taken: first)), 0x0811)
  let assert [second_go] = cast_timers_started(taken: first)
    as "one cast timer: the second go"
  let #(_, second) =
    connection_support.feed(state:, event: OwnEvent(TimerFired(second_go)))
  let frames = written(taken: second)
  assert started_spells(frames:) == [39_427, 70_775, 60_769, 79_932]
    as "Impale's Proxy child 39427 (stealthed and behind) and its Fluff child (Spell4Effects 231067) start in the second phase, and once the stealth has ended the passive's procs 147132 and 211002 cast 60769 and 79932"
  assert stealth_bits(frames:) == [0]
  let at = fn(id) {
    let assert Ok(found) =
      list.index_map(ids(frames:), fn(found, index) { #(found, index) })
      |> list.find(fn(entry) { entry.0 == id })
      as "the message is written"
    found.1
  }
  assert at(0x07FF) < at(0x0811) && at(0x0811) < at(0x08F5)
    as "the child's start, then the stealth cast taken off, then the change"
  assert list.take(list.drop(from_id(frames:, id: 0x08F5), 1), 1) == [0x07FF]
    as "the change is followed by the procs' casts alone"
}

/// The message ids of the frames from the first of this id on.
fn from_id(frames frames: List(Frame), id id: Int) -> List(Int) {
  list.drop_while(ids(frames:), fn(found) { found != id })
}

/// The stealthed bits of the 0x8F5 frames, in order.
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

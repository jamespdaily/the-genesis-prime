//// The Stalker's procs on the game connection (`genesis_prime/game/connection`, with the
//// client's own tables): a press of Nano Skin: Lethal enters and leaves stealth, and the
//// passive's Proc rows cast their spells at it; a killing strike in combat leaves combat and
//// dies. Expected values come from these places:
//// - `Spell4Effects.effectType.14.dataBits00.217_218` and `.0_44`: 45057's Proc 147119 (kind
////   217) casts 60724, 147132 and 211002 (kind 218) cast 60769 and 79932, 159136 (kind 44) and
////   202043 (kind 0) cast 63366.
//// - `Spell4.79932`: Empower, BaseCritChance (102) x1.0 + 0.2 and DamageDealtMultiplier (141
////   to 143) x1.08 for 3000 ms, as 0x93a entries with 32-bit floats (`opcode.0x93a`).
//// - `Spell4Effects.effectType.83`: dataBits02 0 of 83834 ends the stealth on a blow, and
////   Spell4.79932's four type 11 rows 210998 and 212528 to 212530 are what a 0x7f4 lists on
////   the caster as Empower.
//// - `opcode.0x7ff.root_parent`: a proc's cast is a 0x7ff with no 0x7fd.
//// - `Spell4Effects.effectType.73`: 63366 sets the Stealth cooldown to 250 ms, which a press
////   within the 500 ms queue window waits for, where an uncut cooldown refuses it (15).
//// Skipped where the client's tables are not on the machine.

import cast_support
import client_tables
import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, CastStarted, Continue, PeerNews,
}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/held_changes
import genesis_prime/game/hit
import genesis_prime/game/lasting
import genesis_prime/game/player_address.{PlayerAddress}
import genesis_prime/game/proc
import genesis_prime/game/shown
import genesis_prime/game/spell_plan
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_properties.{Source}
import genesis_prime/game/world_entry
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/unit_combat_state.{UnitCombatState}
import genesis_prime/message/unit_properties_changed
import genesis_prime/random
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, ConnectionId,
  LogWarning, Now, OwnEvent,
}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/world_map/map
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import map_support
import owned_test
import planted_table
import player_state_support
import spawn_support
import unitest
import world_entry_support

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

/// The properties 0x93a entries a step writes, as (property, value bits).
fn property_values(taken taken: ConnectionStep(Request)) -> List(#(Int, Int)) {
  connection_support.decoded(
    connection_support.written(taken:),
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
    list.filter_map(connection_support.written(taken:), fn(frame) {
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
  let frames = connection_support.written(taken: entering)
  assert connection_support.stealth_bits(frames:) == [1]
  assert list.take(connection_support.from_id(frames:, id: 0x08F5), 5)
    == [0x08F5, 0x07FE, 0x07FF, 0x07F4, 0x07FE]
    as "0x8f5 {P, 1}, the toggle's own 0x7fe, then Proc 147119's cast of 60724 after the input's own effects: its 0x7ff, 0x7f4 and 0x7fe"
  assert list.last(connection_support.started_spells(frames:)) == Ok(60_724)
    as "the cast after the 0x8f5 is 60724"
  let #(state, leaving) =
    pressed(state:, bag_index: 3, client_cast_id: 2, ms: 3000)
  let frames = connection_support.written(taken: leaving)
  assert connection_support.stealth_bits(frames:) == [0]
  assert list.take(connection_support.from_id(frames:, id: 0x08F5), 1)
    == [0x08F5]
  let after_stealth =
    list.drop_while(frames, fn(frame) { frame.message_id != 0x08F5 })
  assert connection_support.started_spells(frames: after_stealth)
    == [60_769, 79_932]
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
      let #(state, taken) =
        connection_support.fired_at(state:, timer:, ms: 6001)
      #(state, [taken, ..steps])
    })
  let later =
    list.flat_map(ended, fn(taken) { connection_support.written(taken:) })
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
  assert list.contains(cast_support.ids(frames: later), 0x07FE)
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
  assert connection_support.stealth_bits(frames: connection_support.written(
      taken: entering,
    ))
    == [1]
  let #(state, death) =
    connection_support.feed(
      state:,
      event: connection_support.a_killing_strike(),
    )
  let frames = connection_support.written(taken: death)
  assert list.filter(connection_support.started_spells(frames:), fn(spell4_id) {
      spell4_id == 63_366
    })
    == [63_366, 63_366]
    as "Procs 159136 (kind 44, the combat flag going off) and 202043 (kind 0, the death) each cast 63366"
  assert list.filter(connection_support.started_spells(frames:), fn(spell4_id) {
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
  assert list.filter(cast_support.ids(frames:), fn(id) {
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
  assert !list.contains(
    cast_support.ids(frames: connection_support.written(taken: press)),
    0x07FC,
  )
    as "Spell4Effects.effectType.73: 63366 cut the Stealth cooldown to 250 ms, inside the queue window, so the press is held, not refused 15"
  let assert [held] = cast_timers(taken: press)
    as "the held press waits for the cooldown's end"
  let #(_, started) = connection_support.fired_at(state:, timer: held, ms: 1300)
  assert list.contains(
    cast_support.ids(frames: connection_support.written(taken: started)),
    0x07FD,
  )
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
  assert connection_support.started_spells(frames: connection_support.written(
      taken: one,
    ))
    == []
  let #(state, first_gone) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(map.Gone(unit_id: 7)),
    )
  assert connection_support.started_spells(frames: connection_support.written(
      taken: first_gone,
    ))
    == []
    as "a fighter is left: the player is still in combat"
  let #(_, last_gone) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(map.Gone(unit_id: 9)),
    )
  let frames = connection_support.written(taken: last_gone)
  assert list.filter(cast_support.ids(frames:), fn(id) {
      id == 0x089A || id == 0x07FF
    })
    == [0x089A, 0x07FF]
    as "the map's Gone of the last fighter is its release: 0x89a (P, 0), then Proc 159136's cast"
  assert connection_support.started_spells(frames:) == [63_366]
    as "Spell4Effects.effectType.14.dataBits00.0_44: leaving combat casts 63366, whether the last fighter released the player or its process went"
}

pub fn a_blow_whose_attack_spell_the_tables_lack_still_ends_the_stealth_and_logs_the_skipped_procs_test() -> Nil {
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
  assert connection_support.stealth_bits(frames: connection_support.written(
      taken: entering,
    ))
    == [1]
    as "the setup: Stealth is accepted in combat"
  // The client's Spell4 table has no row 99999999, so the groups and school of the blow's
  // attack spell cannot be read: its procs are skipped, and the blow, which lowers the
  // shield, ends the stealth as any other blow does (`Spell4Effects.effectType.83`).
  let #(_, struck) =
    connection_support.at(
      state:,
      ms: 5000,
      event: connection_support.a_strike_of(
        striker: strike_tell.CreatureStriker(
          unit_id: 7,
          spell4_id: Spell4Id(99_999_999),
        ),
        offence: spawn_support.beast_attack().offence,
        unit_id: connection_support.own_unit_id,
      ),
    )
  assert connection_support.stealth_bits(frames: connection_support.written(
      taken: struck,
    ))
    == [0]
    as "the blow ends the stealth and the client is told"
  let assert [warning] = support.logs_of(step: struck, level: LogWarning)
    as "one warning says the procs of the blow were skipped"
  assert string.contains(warning.text, "procs of a blow taken skipped")
    as "the warning names what was skipped"
}

/// A creature's strike on the tests' player at this monotonic time: the Beast's own blow,
/// which lowers its shield or health.
fn struck_at(
  state state: game_connection.State,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(
    state,
    support.input_at_ms(
      ms:,
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    ),
  )
}

/// The Spell4Effects ids the 0x7f4 of the cast `cast_id` lists on the unit, sorted.
fn listed_on_unit(
  taken taken: ConnectionStep(Request),
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> List(Int) {
  connection_support.decoded(
    connection_support.written(taken:),
    spell_go.message_id,
    spell_go.decode,
  )
  |> list.filter(fn(go: spell_go.SpellGo) { go.cast_id == cast_id })
  |> list.flat_map(fn(go) { go.targets })
  |> list.filter(fn(target) { target.unit_id == unit_id })
  |> list.flat_map(fn(target) {
    list.map(target.effects, fn(effect) { effect.spell4_effects_id })
  })
  |> list.sort(int.compare)
}

pub fn a_stalker_in_combat_whose_stealth_a_creatures_blow_ends_gets_empower_listed_on_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let state = stalker_in_world()
  let #(state, threatened) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  assert connection_support.decoded(
      connection_support.written(taken: threatened),
      0x089A,
      unit_combat_state.decode,
    )
    == [
      UnitCombatState(unit_id: connection_support.own_unit_id, in_combat: 1),
    ]
    as "the setup: a creature threatening the player puts the player in combat (0x89a)"
  let #(state, entering) =
    pressed(state:, bag_index: 3, client_cast_id: 1, ms: 1000)
  assert connection_support.stealth_bits(frames: connection_support.written(
      taken: entering,
    ))
    == [1]
    as "the setup: Stealth is accepted in combat"
  let #(_, struck) = struck_at(state:, ms: 5000)
  assert connection_support.started_spells(frames: connection_support.written(
      taken: struck,
    ))
    == [60_769, 79_932]
    as "Procs 147132 and 211002 of 45057 cast 60769 and 79932 for leaving stealth, whichever way it ended"
  assert listed_on_unit(
      taken: struck,
      cast_id: start_of(taken: struck, spell4_id: 79_932).cast_id,
      unit_id: connection_support.own_unit_id,
    )
    == [210_998, 212_528, 212_529, 212_530]
    as "Spell4.79932: its four type 11 rows (210998, 212528 to 212530) are listed on the caster in a 0x7f4, which is what the client shows as the buff"
}

pub fn a_stalker_alone_in_sight_gets_empower_listed_on_it_when_a_blow_ends_the_stealth_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, _) =
    connection_support.entered_on_the_clients_tables(
      class_id: 5,
      saved_health: None,
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, entering) =
    pressed(state:, bag_index: 3, client_cast_id: 1, ms: 1000)
  assert connection_support.stealth_bits(frames: connection_support.written(
      taken: entering,
    ))
    == [1]
    as "the setup: Stealth is accepted in combat"
  let #(_, struck) = struck_at(state:, ms: 5000)
  assert connection_support.started_spells(frames: connection_support.written(
      taken: struck,
    ))
    == [60_769, 79_932]
    as "with no viewer, the player's own client still gets both procs' casts"
  assert listed_on_unit(
      taken: struck,
      cast_id: start_of(taken: struck, spell4_id: 79_932).cast_id,
      unit_id: connection_support.own_unit_id,
    )
    == [210_998, 212_528, 212_529, 212_530]
    as "Spell4.79932: its four type 11 rows (210998, 212528 to 212530) are listed on the caster in a 0x7f4 with no viewer in sight"
}

// ---- a hit's proc: the connection's draws and its due timer ----

/// Impale's bag index on the Stalker's bar (Spell4Base 23161).
const impale_bag_index = 1

/// The id of the Proc row `with_hit_proc` adds to the Stalker's passive. A go's
/// `spell4_effects_id` is 19 bits wide, so the id is below 524288.
const hit_proc_id = 400_001

/// The 32 bits of this float, as a Proc row's dataBits02 holds its chance
/// (`Spell4Effects.effectType.14.dataBits02`).
fn float_bits(value value: Float) -> Int {
  let assert <<bits:size(32)>> = <<value:float-size(32)>>
    as "a float32 is 32 bits"
  bits
}

/// Runs the body with a Stalker of the fixture's rows in the world and the Beast unit 40
/// in front of it, on tables whose Nano Skin: Lethal passive 45057 holds one more Proc: a
/// kind 12 (a hit its holder lands) at this chance and delay that casts 63366, copied
/// from its Proc 202043 and limited to 60 fires in 250 ms.
fn with_hit_proc(
  chance chance: Float,
  delay_ms delay_ms: Int,
  body body: fn(game_connection.State) -> a,
) -> a {
  with_proc_of_kind(kind: 12, chance:, delay_ms:, body:)
}

/// `with_hit_proc` for a Proc row of any kind (dataBits00).
fn with_proc_of_kind(
  kind kind: Int,
  chance chance: Float,
  delay_ms delay_ms: Int,
  body body: fn(game_connection.State) -> a,
) -> a {
  with_rows(rows: proc_rows(kind:, chance:, delay_ms:, filter: []), body:)
}

/// The fixture's rows with Proc row `hit_proc_id` added to the Stalker's passive: a copy of
/// Proc 202043 (casting 63366) of this kind, chance and delay, with `filter` as its
/// dataBits07 and dataBits08 cells.
fn proc_rows(
  kind kind: Int,
  chance chance: Float,
  delay_ms delay_ms: Int,
  filter filter: List(#(String, planted_table.Cell)),
) -> fixture_tables.Rows {
  let assert Ok(rows) =
    fixture_tables.add(
      rows: fixture_tables.rows(),
      table: "Spell4Effects",
      copy_of: 202_043,
      id: hit_proc_id,
      with: list.append(
        [
          #("dataBits00", planted_table.Integer(kind)),
          #("dataBits02", planted_table.Integer(float_bits(value: chance))),
          #("dataBits04", planted_table.Integer(250)),
          #("dataBits05", planted_table.Integer(60)),
          #("delayTime", planted_table.Integer(delay_ms)),
        ],
        filter,
      ),
    )
    as "the fixture holds Proc 202043"
  rows
}

/// A Stalker entered on these rows with a Virtual Battle Beast in sight.
fn with_rows(
  rows rows: fixture_tables.Rows,
  body body: fn(game_connection.State) -> a,
) -> a {
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let #(state, _) =
    connection_support.entered_with(
      settings: Settings(..connection_support.settings(), tables:),
      class_id: 5,
      saved_health: None,
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.beast_appears(unit_id: 40),
    )
  body(state)
}

/// A press of Impale at `ms` and the firing, 300 ms later, of the one timer the press
/// starts (the cast's go), whose step tells the Beast's strike.
fn impale_strikes(
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request), ConnectionStep(Request)) {
  let #(state, press) =
    pressed(state:, bag_index: impale_bag_index, client_cast_id:, ms:)
  let assert [go_timer] = cast_timers(taken: press)
    as "the press starts one cast timer"
  let #(state, fired) =
    connection_support.fired_at(state:, timer: go_timer, ms: ms + 300)
  #(state, press, fired)
}

/// The step that answers the strike the step `fired` tells as landed at `ms`.
fn landing_of(
  state state: game_connection.State,
  fired fired: ConnectionStep(Request),
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert [#(40, key)] = connection_support.strikes_told(fired)
    as "the cast's go strikes the Beast"
  connection_support.at(
    state:,
    ms:,
    event: connection_support.landed_with_damage(key:),
  )
}

/// How many times a step writes the start of a cast of this Spell4 to the player.
fn started_count(
  taken taken: ConnectionStep(Request),
  spell4_id spell4_id: Int,
) -> Int {
  list.count(
    connection_support.started_spells(frames: connection_support.written(taken:)),
    fn(spell) { spell == spell4_id },
  )
}

/// The bytes the seed gives draws of these sizes in turn, as a connection that draws
/// nothing else is given them (`random.bytes` of the seed the tests give 1,
/// `game_connection_support.accepted`).
fn drawn_by_seed(draws draws: List(Int)) -> List(BitArray) {
  let #(_, drawn) =
    list.fold(
      draws,
      #(random.new(seed: support.seed(1)), []),
      fn(so_far, count) {
        let #(source, drawn) = so_far
        let #(source, bytes) = random.bytes(source, count)
        #(source, [bytes, ..drawn])
      },
    )
  list.reverse(drawn)
}

/// The rolls of a strike that took these 12 bytes.
fn rolls_of_strike(bytes bytes: BitArray) -> hit.Rolls {
  let assert Ok(rolls) = hit.rolls_of(bytes:)
    as "the draw is the 12 bytes of a strike's rolls"
  rolls
}

pub fn a_go_with_a_chance_proc_draws_exactly_the_draws_the_pending_events_need_test() -> Nil {
  use <- owned_test.run(120_000)
  // Each Impale go draws its strike's 12 bytes of rolls and then 8 bytes of rolls for the
  // gate rows of its go: blocks 0 and 1 of the seed. The landing of the first strike is
  // one pending event and the proc one chance word: a draw of 4 bytes, which takes
  // block 2. The word's fraction is 1438334843 / 2^32 = 0.3349 (`random.fraction`,
  // `random.words`): below a chance of 0.5 and not below 0.25. A draw takes whole
  // 32-byte blocks (`random.bytes`), so the second strike's rolls are block 3 whatever
  // the proc's outcome, and a landing that drew more or less than the word would shift
  // them.
  let assert [first_strike, _gate_rolls, _word, second_strike, _more_gate_rolls] =
    drawn_by_seed(draws: [hit.roll_bytes, 8, 4, hit.roll_bytes, 8])
  let expected_rolls = [
    rolls_of_strike(bytes: first_strike),
    rolls_of_strike(bytes: second_strike),
  ]
  let landing_at = fn(chance) {
    use state <- with_hit_proc(chance:, delay_ms: 0)
    let #(state, _, first) = impale_strikes(state:, client_cast_id: 1, ms: 1000)
    let #(state, landed) = landing_of(state:, fired: first, ms: 1400)
    // Impale recharges long before the second press.
    let #(_, _, second) = impale_strikes(state:, client_cast_id: 2, ms: 100_000)
    #(
      connection_support.strike_rolls([first, second]),
      started_count(taken: landed, spell4_id: 63_366),
    )
  }
  assert landing_at(0.5) == #(expected_rolls, 1)
    as "a chance of 0.5 is above the word's 0.3349: the landing casts 63366 once, and the second strike takes block 3"
  assert landing_at(0.25) == #(expected_rolls, 0)
    as "a chance of 0.25 is not: no cast, and the seed has advanced the same"
}

pub fn an_input_with_nothing_pending_draws_nothing_and_makes_no_second_call_test() -> Nil {
  use <- owned_test.run(120_000)
  // No press, no go and no timer of Impale's cast lands a hit: the first strike is
  // never answered, so nothing is pending in the four inputs. Each go draws its strike's
  // 12 bytes and the 8 bytes of its gate rolls, so the second strike takes block 2.
  let assert [first_strike, _gate_rolls, second_strike, _more_gate_rolls] =
    drawn_by_seed(draws: [hit.roll_bytes, 8, hit.roll_bytes, 8])
  use state <- with_hit_proc(chance: 0.5, delay_ms: 0)
  let #(state, first_press, first) =
    impale_strikes(state:, client_cast_id: 1, ms: 1000)
  let #(_, second_press, second) =
    impale_strikes(state:, client_cast_id: 2, ms: 100_000)
  assert connection_support.strike_rolls([first, second])
    == [
      rolls_of_strike(bytes: first_strike),
      rolls_of_strike(bytes: second_strike),
    ]
    as "the strikes take blocks 0 and 2: none of the four inputs drew for a proc"
  // The two presses are the same input and so are the two goes: with nothing pending
  // no pass of the procs adds or repeats a frame, so each pair writes the same frames.
  let frames = fn(taken) {
    cast_support.ids(frames: connection_support.written(taken:))
  }
  assert frames(second_press) == frames(first_press)
    as "the second press writes what the first did"
  assert frames(second) == frames(first)
    as "the second go writes what the first did"
}

pub fn a_creature_blow_on_the_player_runs_the_proc_pass_with_draws_from_its_seed_test() -> Nil {
  use <- owned_test.run(120_000)
  // A creature's blow on the player draws its strike's 12 bytes of rolls from the player's
  // seed (block 0) and then, for the one pending event of the blow taken, the chance word
  // of the kind 16 proc (block 1); the second blow's rolls are block 2 and its word block 3.
  // A word fires the proc when its fraction is below the chance (`random.fraction`), so a
  // chance between the two words' fractions fires one blow's proc and not the other's, and a
  // blow that drew more or less than the word would shift which.
  let assert [_rolls, first_word, _more_rolls, second_word] =
    drawn_by_seed(draws: [hit.roll_bytes, 4, hit.roll_bytes, 4])
  let assert [first] = random.words(bytes: first_word)
  let assert [second] = random.words(bytes: second_word)
  let first = random.fraction(first)
  let second = random.fraction(second)
  assert float.absolute_value(first -. second) >. 0.01
    as "the seed's two words are told apart by a chance between them"
  let chance = { first +. second } /. 2.0
  use state <- with_proc_of_kind(kind: 16, chance:, delay_ms: 0)
  let #(state, first_blow) = struck_at(state:, ms: 1000)
  let #(_, second_blow) = struck_at(state:, ms: 100_000)
  assert [
      started_count(taken: first_blow, spell4_id: 63_366),
      started_count(taken: second_blow, spell4_id: 63_366),
    ]
    == case first <. second {
      True -> [1, 0]
      False -> [0, 1]
    }
    as "the blow whose word is the lower fires the kind 16 proc, which casts 63366, and the other does not"
}

/// Spell group 134, one of the groups of the Beast's attack Spell4 5649 (`Spell4.5649`:
/// Spell4GroupList 657, whose groups are 6, 9, 134 and 333), as a Proc's filter names it
/// (dataBits07 2, the group in dataBits08).
const beasts_attack_group_filter = [
  #("dataBits07", planted_table.Integer(2)),
  #("dataBits08", planted_table.Integer(134)),
]

/// How many times the player is written the start of 63366, which the Proc rows of `rows`
/// cast (Proc 202043), by this event at 1000 ms.
fn proc_casts_after(
  rows rows: fixture_tables.Rows,
  event event: Event(ConnectionEvent(Message, Answer)),
) -> Int {
  use state <- with_rows(rows:)
  let #(_, struck) =
    game_connection.step(state, support.input_at_ms(ms: 1000, event:))
  started_count(taken: struck, spell4_id: 63_366)
}

pub fn a_creatures_critical_blow_fires_a_kind_146_proc_filtered_to_its_attack_spells_group_test() -> Nil {
  use <- owned_test.run(120_000)
  // The Beast's strike with a crit chance of 1.0 draws a crit roll below it, so the blow
  // is a critical that the 12 damage does not take the shield down for; the proc's group
  // 134 is one of the groups of Spell4 5649, which the connection reads from the tables.
  let rows =
    proc_rows(
      kind: 146,
      chance: 1.0,
      delay_ms: 0,
      filter: beasts_attack_group_filter,
    )
  assert proc_casts_after(
      rows:,
      event: connection_support.a_strike_of(
        striker: spawn_support.beast_striker(),
        offence: hit.Offence(
          ..spawn_support.beast_attack().offence,
          crit_chance: 1.0,
        ),
        unit_id: connection_support.own_unit_id,
      ),
    )
    == 1
    as "a critical blow of a creature on the holder fires the kind 146 proc"
  assert proc_casts_after(
      rows:,
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    )
    == 0
    as "a blow that is no critical does not"
}

pub fn a_creatures_blow_the_player_deflects_fires_a_kind_51_proc_filtered_to_its_attack_spells_group_test() -> Nil {
  use <- owned_test.run(120_000)
  // GameFormula 1235 gives the deflect chance (`rating.formulas`): an intercept of 100 with
  // the knee above it makes it 100% at level 1, so every roll (a fraction below 1.0)
  // deflects the strike.
  let assert Ok(rows) =
    fixture_tables.change(
      rows: proc_rows(
        kind: 51,
        chance: 1.0,
        delay_ms: 0,
        filter: beasts_attack_group_filter,
      ),
      table: "GameFormula",
      id: 1235,
      with: [
        #("dataint0", planted_table.Integer(100)),
        #("datafloat02", planted_table.Integer(float_bits(value: 200.0))),
      ],
    )
    as "the fixture holds GameFormula 1235"
  assert proc_casts_after(
      rows:,
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    )
    == 1
    as "a creature's blow the holder deflects fires the kind 51 proc"
  assert proc_casts_after(
      rows: proc_rows(
        kind: 51,
        chance: 1.0,
        delay_ms: 0,
        filter: beasts_attack_group_filter,
      ),
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    )
    == 0
    as "the same blow landed does not"
}

pub fn a_creatures_blow_that_depletes_the_shield_fires_a_kind_115_proc_filtered_to_its_attack_spells_group_test() -> Nil {
  use <- owned_test.run(120_000)
  // The player's shield holds 450 and takes at most 0.625 of the mitigated blow
  // (`player_life_test`): 3000 Magic damage takes all of it and leaves the health alive,
  // and it is no critical, so it is the shield going to 0 that fires the proc; the 12
  // Physical of the Beast's own blow does not take the shield down.
  let rows =
    proc_rows(
      kind: 115,
      chance: 1.0,
      delay_ms: 0,
      filter: beasts_attack_group_filter,
    )
  assert proc_casts_after(
      rows:,
      event: connection_support.a_creatures_blow(
        unit_id: connection_support.own_unit_id,
        damage_type: 3,
        damage: 3000,
      ),
    )
    == 1
    as "a blow that takes the shield from above 0 to 0 fires the kind 115 proc"
  assert proc_casts_after(
      rows:,
      event: connection_support.a_beast_strike(connection_support.own_unit_id),
    )
    == 0
    as "a blow that leaves the shield above 0 does not"
}

pub fn a_proc_due_timer_starts_the_delayed_cast_test() -> Nil {
  use <- owned_test.run(120_000)
  // The Proc row's delayTime is 1000 ms (`Spell4Effects.delayTime`): the landing starts
  // a timer instead of the cast, and the cast starts when it fires. A chance of 1.0
  // takes no draw.
  use state <- with_hit_proc(chance: 1.0, delay_ms: 1000)
  let #(state, _, fired) = impale_strikes(state:, client_cast_id: 1, ms: 1000)
  let #(state, landed) = landing_of(state:, fired:, ms: 1400)
  assert started_count(taken: landed, spell4_id: 63_366) == 0
    as "the landing does not cast 63366: the delay has not run out"
  let assert [proc_due] = cast_timers(taken: landed)
    as "the landing starts one timer: the proc's"
  let #(_, due) = connection_support.fired_at(state:, timer: proc_due, ms: 2400)
  assert started_count(taken: due, spell4_id: 63_366) == 1
    as "the timer's firing casts 63366 once, as an ordinary cast"
}

/// The ally the caster holds Healing Salve's allies' row on: unit 40 of connection 2 in the
/// stay `map_support` gives it.
const ally_unit = 40

/// A caster in the world that holds Proc row 86457 on the ally (Healing Salve's allies' row:
/// Spell4 39386, kind 16, once or twice in 2000 ms as `limit_count` says, casting Spell4 39127)
/// for the cast `cast_id`, with the ally among its viewers and its picture, and the row's
/// chance `chance`. Only the change on the ally is held, as the cast holds it when the
/// ally's node is gone.
fn caster_holding_an_ally_proc(
  chance chance: Float,
  limit_count limit_count: Int,
) -> state.Session {
  let entered = world_entry_support.entered_after(clock_origin_ms: 600)
  let source =
    Source(cast_id: 2_147_500_000, effect_id: Spell4EffectsId(86_457))
  let address =
    PlayerAddress(
      connection: ConnectionId(2),
      unit_id: ally_unit,
      stay: map_support.stay(count: 2),
    )
  let row =
    spell_plan.ProcRow(
      ..cast_support.held_proc_row(
        id: 86_457,
        holder: spell_plan.HeldByAreaAllies,
        row: lasting.LastingRow(
          delay_ms: 0,
          duration_ms: 12_000,
          until_removed: False,
        ),
      ),
      chance:,
      limit: spell_plan.InWindow(window_ms: 2000, count: limit_count),
    )
  let cast =
    cast_state.State(
      ..entered.cast,
      procs: dict.from_list([
        #(
          cast_state.ProcHold(source:, holder: Some(ally_unit)),
          cast_state.HeldProc(row:, fires_ms: []),
        ),
      ]),
      on_units: dict.from_list([
        #(source.cast_id, [
          cast_state.HeldOnPlayer(
            source:,
            address:,
            sight: held_changes.KeptWhenUnseen,
            spell4_id: Spell4Id(39_386),
            stack: row.spell.stack,
            started_ms: 1000,
          ),
        ]),
      ]),
    )
  connection_support.session_in(status: state.InWorld(
    holder: connection_support.holder(),
    entered: world_entry.Entered(
      ..entered,
      cast:,
      viewers: dict.from_list([
        #(
          ConnectionId(2),
          player_address.Viewer(stay: address.stay, unit_id: ally_unit),
        ),
      ]),
      shown: dict.insert(
        entered.shown,
        ally_unit,
        shown.ShownPlayer(state: player_state_support.a_player()),
      ),
    ),
  ))
}

/// The event an ally's connection tells of a creature's blow on it, `blows` times in one tell.
fn ally_blow_tell(blows blows: Int) -> strike_tell.PlayerEvent {
  strike_tell.PlayerEvent(
    unit_id: ally_unit,
    events: list.repeat(
      proc.Event(
        trigger: spell_plan.TakesDamage,
        other_unit: Some(31),
        spell: Some(proc.EventSpell(
          spell4_id: Spell4Id(5649),
          groups: [6, 9, 134, 333],
          school: 1,
        )),
        holder: None,
      ),
      blows,
    ),
  )
}

/// The times the caster's entry for the ally has fired, and the Spell4 ids of the casts the
/// caster has live.
fn fires_and_casts(session session: state.Session) -> #(List(Int), List(Int)) {
  let assert Some(entered) = state.entered_of(session.status)
    as "the caster is in the world"
  let assert [fired] = dict.values(entered.cast.procs)
    as "the caster holds one entry"
  #(
    fired.fires_ms,
    list.map(dict.values(entered.cast.casts), fn(live) {
      live.spell.spell4_id.value
    })
      |> list.sort(int.compare),
  )
}

pub fn a_tell_of_an_allys_event_draws_its_chance_words_from_the_casters_seed_and_fires_the_entries_whose_word_is_below_the_chance_test() -> Nil {
  use <- owned_test.run(10_000)
  // The session's seed gives the words: a tell draws what its events need in one draw (a block
  // of the seed), and a word fires a chance proc when its fraction is below the chance
  // (`random.fraction`). One tell of two events draws two words, the first event's first, and
  // a later tell of one event draws one word from the next block. The chance
  // between the lowest and the middle of the three fractions fires exactly the event whose
  // word is the lowest, and the chance between the middle and the highest the two lowest, so a
  // word taken for the wrong event, a repeated word or a word not drawn at all changes who
  // fires.
  let source = random.new(seed: <<1>>)
  let #(source, two_words) = random.bytes(source, 8)
  let #(_, one_word) = random.bytes(source, 4)
  let assert [first, second] = random.words(bytes: two_words)
  let assert [third] = random.words(bytes: one_word)
  let #(first, second, third) = #(
    random.fraction(first),
    random.fraction(second),
    random.fraction(third),
  )
  let ordered = list.sort([first, second, third], float.compare)
  let assert [lowest, middle, highest] = ordered
  assert middle -. lowest >. 0.01 && highest -. middle >. 0.01
    as "the seed's three words are told apart by a chance between them"
  let rows = [
    #(
      "a chance between the lowest and the middle fraction",
      { lowest +. middle } /. 2.0,
    ),
    #(
      "a chance between the middle and the highest fraction",
      { middle +. highest } /. 2.0,
    ),
    #(
      "a chance above both words of the first tell",
      { float.max(first, second) +. 1.0 } /. 2.0,
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, chance) = row
    let session = caster_holding_an_ally_proc(chance:, limit_count: 2)
    let assert state.InWorld(entered:, ..) = session.status
    let assert Continue(session, _) =
      casting.ally_event_taken(
        session:,
        now: Now(monotonic_ms: 1500, filetime: 0),
        entered:,
        event: ally_blow_tell(blows: 2),
      )
    let below = fn(fraction) { fraction <. chance }
    let fired_by_the_first_tell =
      list.filter([first, second], below) |> list.map(fn(_) { 1500 })
    assert fires_and_casts(session:).0 == fired_by_the_first_tell
      as {
        reason
        <> ": the first tell's two events take the first two words in order"
      }
    let assert Some(entered) = state.entered_of(session.status)
    let assert Continue(session, _) =
      casting.ally_event_taken(
        session:,
        now: Now(monotonic_ms: 5000, filetime: 0),
        entered:,
        event: ally_blow_tell(blows: 1),
      )
    // A fire at 5000 leaves only itself in the 2000 ms window.
    assert fires_and_casts(session:).0
      == case below(third) {
        True -> [5000]
        False -> fired_by_the_first_tell
      }
      as { reason <> ": the second tell takes the third word" }
  })
  // A tell for an ally the caster holds no entry for draws nothing and fires nothing.
  let session = caster_holding_an_ally_proc(chance: 0.5, limit_count: 2)
  let assert state.InWorld(entered:, ..) = session.status
  let assert Continue(after, effects) =
    casting.ally_event_taken(
      session:,
      now: Now(monotonic_ms: 1500, filetime: 0),
      entered:,
      event: strike_tell.PlayerEvent(..ally_blow_tell(blows: 1), unit_id: 99),
    )
  assert fires_and_casts(session: after) == #([], [])
    as "an event of another unit fires no entry"
  assert effects == [] as "and writes nothing"
  assert client_connection.draw(after.link, 4).1
    == client_connection.draw(session.link, 4).1
    as "and draws nothing from the seed"
}

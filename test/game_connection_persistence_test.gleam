//// A lasting cast's persistence on the game connection
//// (`genesis_prime/game/connection/casting` `persisted`, called after each input of a
//// player in the world): the cast rule ends the casts whose condition stopped holding,
//// and the connection writes what it decided after what the input itself wrote.
//// Expected values come from these places:
//// - `Spell4.47439` (the Spell Surge buff): CasterPersistence 36425, Spell Power (slot 4
////   of the Spellslinger) at least 25 (`Class.spell4IdInnateAbilityActive00.cast_prerequisites`);
////   the client never evaluates it, so ending the buff is the server's
////   (`Spell4.prerequisiteIdCasterPersistence`).
//// - `opcode.0x935`: the class resource's change is written to the player's own client as
////   0x935, and `opcode.0x7f9` then `opcode.0x7fe` end the cast (`cast.target_node_end`).
//// - The server's choices (the cast module's doc): the check runs at the end of each input
////   in the world, so its writes follow the input's own, and none runs with no player in
////   the world. At level 1 no Spellslinger spell lowers Spell Power (every cost is 0), so
////   the tests give the Spellslinger the Esper's wait: its slot goes to 0 ten seconds after
////   combat ends (`class_resource_support`, migration 0012's row of the Esper; the wait is
////   test data, `empty_after_combat_ms`).
//// Skipped where the client's tables are not on the machine.

import cast_support
import class_resource_support
import client_tables
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/class_resource.{Row}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_result
import genesis_prime/message/spell_failed
import genesis_prime/step.{type ConnectionStep, OwnEvent, TimerFired}
import gleam/list
import gleam/option.{None}
import owned_test
import server_proxy_support
import unitest

/// The Spellslinger's class resource with the wait after combat that empties its slot.
fn emptying_after_combat() -> class_resource.Classes {
  let assert Ok(classes) =
    class_resource.select(
      rows: list.append(class_resource_support.rows(), [
        Row(
          class_id: 7,
          name: "empty_after_combat_ms",
          value: 10_000.0,
          unit: "ms",
        ),
      ]),
    )
    as "the planted rows and the wait select"
  classes
}

/// The Spellslinger in the world on the client's tables, its unit id, and the bag
/// index of Spell Surge (the innate, after the three level-1 abilities).
fn spellslinger() -> #(game_connection.State, Int) {
  let #(state, taken) =
    connection_support.entered_with(
      settings: Settings(
        ..connection_support.settings(),
        tables: client_tables.shared(),
        class_resources: emptying_after_combat(),
        server_proxies: server_proxy_support.none(),
      ),
      class_id: 7,
      saved_health: None,
    )
  #(state, connection_support.player_in(taken).unit_id)
}

const spell_surge_bag_index = 3

fn press(
  state state: game_connection.State,
  bag_index bag_index: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.read(
    state:,
    bytes: connection_support.world_message(
      message_id: 0x009A,
      body: cast_support.press_body(
        client_cast_id: 9,
        bag_index:,
        target: 0,
        press: 1,
      ),
    ),
  )
}

fn written(taken taken: ConnectionStep(Request)) -> List(Frame) {
  connection_support.heard(taken, connection_support.keyed())
}

fn ids(taken taken: ConnectionStep(Request)) -> List(Int) {
  list.map(written(taken:), fn(frame) { frame.message_id })
}

/// The connection with the Spell Surge buff on and the player's combat flag set and
/// cleared again, so the resource's wait to empty runs.
fn buff_on_and_out_of_combat() -> #(game_connection.State, Int) {
  let #(state, unit_id) = spellslinger()
  let #(state, pressed) = press(state:, bag_index: spell_surge_bag_index)
  assert list.contains(ids(taken: pressed), 0x07FF)
    as "Spell Surge starts its buff 47439 with a 0x7ff"
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 9, life: 3)),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Released(unit_id: 9)),
    )
  #(state, unit_id)
}

pub fn a_class_resource_timer_that_leaves_spell_power_at_0_writes_0x935_then_ends_the_surge_buff_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, unit_id) = buff_on_and_out_of_combat()
  let #(state, taken) =
    connection_support.feed(
      state:,
      event: OwnEvent(TimerFired(timer: class_resource.empty_timer)),
    )
  assert ids(taken:) == [0x0935, 0x07F9, 0x07FE]
    as "the timer empties the slot (0x935, the input's own write); the check that follows finds Spell Surge's 36425 (slot 4 at least 25) failing and ends the buff with 0x7f9 then 0x7fe, after it"
  let assert [failure] =
    list.filter(written(taken:), fn(frame) {
      frame.message_id == spell_failed.message_id
    })
  let assert Ok(failed) = spell_failed.decode(failure.body)
    as "the 0x7f9 decodes"
  assert cast_result.to_value(failed.result) == 282 && failed.unit_id == unit_id
    as "Prereq_CasterPersistence, naming the player's unit"
  let #(_, later) =
    connection_support.feed(
      state:,
      event: OwnEvent(TimerFired(timer: class_resource.regen_timer)),
    )
  assert !list.contains(ids(taken: later), 0x07F9)
    as "the cast is gone: a later input ends nothing"
}

pub fn a_press_a_combat_change_and_a_timer_end_nothing_while_spell_power_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(state, _) = spellslinger()
  let #(state, pressed) = press(state:, bag_index: spell_surge_bag_index)
  assert !list.contains(ids(taken: pressed), 0x07F9)
    as "a press: Spell Power is full, so 36425 holds"
  let #(state, threatened) =
    connection_support.feed(
      state:,
      event: connection_support.foe(strike_tell.Threatened(unit_id: 9, life: 3)),
    )
  assert !list.contains(ids(taken: threatened), 0x07F9) as "the combat flag set"
  let #(_, ticked) =
    connection_support.feed(
      state:,
      event: OwnEvent(TimerFired(timer: class_resource.regen_timer)),
    )
  assert !list.contains(ids(taken: ticked), 0x07F9)
    as "a class resource timer with the slot full"
}

pub fn a_connection_with_no_player_in_the_world_checks_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    connection_support.feed(
      state: connection_support.in_select(),
      event: OwnEvent(TimerFired(timer: class_resource.empty_timer)),
    )
  assert support.writes(taken) == []
    as "in character select a resource timer is nothing, and so is the check that would follow it"
}

// ---- a planted cast that ends when its player enters combat ----
//
// The planted Pulse Blast 42276 (the Engineer's, a cast time of 1250 ms and a global
// cooldown of 1250 ms) holds the planted CasterPersistence 390, type 28 comparison 2: not
// in combat (`spell_tables.waiver_prerequisite_rows`). Each test gives a different kind
// of input the end of one such cast, and checks the input's own writes come first.

const pulse_blast_base = 26_468

fn engineer() -> #(game_connection.State, Int) {
  let #(state, _, bag_index) =
    connection_support.entered_with_spell_trees(
      class_id: 2,
      ability: pulse_blast_base,
    )
  #(state, bag_index)
}

fn at(
  state state: game_connection.State,
  ms ms: Int,
  event event: step.Event(
    step.ConnectionEvent(client_connection.Message, client_connection.Answer),
  ),
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(state, support.input_at_ms(ms:, event:))
}

fn pressed_at(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  at(
    state:,
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
  )
}

fn threatened_at(
  state state: game_connection.State,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  at(
    state:,
    ms:,
    event: connection_support.foe(strike_tell.Threatened(unit_id: 9, life: 3)),
  )
}

/// What a press of Pulse Blast writes: its 0x7fd and the go of its first phase, which it
/// has at once (a Multiphase spell).
const press_written = [0x07FD, 0x07F4]

const combat_state = 0x089A

const failed_then_finished = [0x07F9, 0x07FE]

pub fn a_press_in_combat_of_a_cast_that_needs_the_player_out_of_it_is_confirmed_then_ended_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, bag_index) = engineer()
  let #(state, _) = threatened_at(state:, ms: 900)
  let #(_, taken) = pressed_at(state:, bag_index:, client_cast_id: 9, ms: 1000)
  assert ids(taken:) == list.append(press_written, failed_then_finished)
    as "the press's own writes, its 0x7fd and its go, come first; then the check, at the end of that input, finds the cast's persistence 390 (not in combat) failing: 0x7f9 then 0x7fe"
}

pub fn the_combat_flag_setting_ends_a_cast_that_needs_the_player_out_of_combat_after_its_own_0x89a_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, bag_index) = engineer()
  let #(state, pressed) =
    pressed_at(state:, bag_index:, client_cast_id: 9, ms: 1000)
  assert ids(taken: pressed) == press_written as "out of combat the cast holds"
  let #(_, taken) = threatened_at(state:, ms: 1100)
  assert ids(taken:) == [combat_state, ..failed_then_finished]
    as "the combat flag's own news, 0x89a, comes first; then 0x7f9 and 0x7fe end the cast"
}

pub fn a_cast_timer_that_starts_a_held_press_in_combat_ends_its_cast_after_the_timers_own_writes_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, bag_index) = engineer()
  let #(state, _) = threatened_at(state:, ms: 900)
  // The first press passes the cast checks, starts the global cooldown of 1250 ms (to
  // 2250) and is ended by the check that follows it.
  let #(state, first) =
    pressed_at(state:, bag_index:, client_cast_id: 9, ms: 1000)
  assert ids(taken: first) == list.append(press_written, failed_then_finished)
  // 350 ms before the cooldown ends, inside the 500 ms queue window: the press waits.
  let #(state, held) =
    pressed_at(state:, bag_index:, client_cast_id: 10, ms: 1900)
  assert ids(taken: held) == []
    as "a press within 500 ms of the cooldown's end is held with nothing written"
  let assert [timer] = list.filter(support.timers_started(held), cast.owns)
    as "its start waits on a timer of the cast rule"
  let #(_, taken) = at(state:, ms: 2250, event: OwnEvent(TimerFired(timer:)))
  assert ids(taken:) == list.append(press_written, failed_then_finished)
    as "the timer starts the held press (its own 0x7fd and go), and the check after the timer ends it"
}

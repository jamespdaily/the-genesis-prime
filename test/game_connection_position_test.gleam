//// A Stalker's Impale on the game connection, over the client's own tables
//// (`genesis_prime/game/connection/casting`): the round closes with the pose each struck
//// creature has in the connection's picture, and the Proxy behind prerequisite 5734 or 5735
//// starts 39427 or 39426 by where the Stalker stands against the creature's facing.
//// Expected values come from these places:
//// - `Spell4Effects.prerequisiteIdTargetApply` and the client's rows (`table_rows --
////   Spell4Effects 83818 83819 85673 85682`, `-- Prerequisite 38585 38587 5734 5735`,
////   `-- PositionalRequirement 53`): 39427 'Stealthed or Behind Damage' starts when the
////   Stalker is stealthed or behind the creature (the 140 degrees behind its facing), 39426
////   'Normal Damage' when it is neither.
//// - `creature.facing`: a creature faces the yaw of its 0x262 and its paths do not turn it,
////   so the Beast standing 3 m ahead of the Stalker (at z less than the Stalker's) with the
////   yaw 0 faces -z, away from the Stalker, who is behind it; with the yaw of a half turn it
////   faces the Stalker; with a quarter turn it faces -x and the Stalker is at its side.
//// Skipped where the client's tables are not on the machine.

import client_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/loadout
import genesis_prime/message/spell_started
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import gleam/bool
import gleam/list
import gleam/option
import owned_test
import unitest

/// Impale's Spell4Base (Spell4 38779).
const impale_base = 23_161

/// The Beast's unit.
const beast = 40

/// The bag index of the ability of this Spell4Base in a level-1 Stalker's bag.
fn bag_index_of(base base: Int) -> Int {
  let assert Ok(set) =
    loadout.of(
      tables: client_tables.shared(),
      class_id: ClassId(5),
      faction_id: 166,
    )
    as "the client's tables hold the Stalker's Novice set"
  let assert Ok(index) =
    list.index_map(loadout.bag(loadout: set), fn(held, index) { #(held, index) })
    |> list.key_find(Spell4BaseId(base))
    as "the Stalker's bag holds the ability"
  index
}

/// A Stalker in the world over the client's tables, with a Beast shown 3 m ahead of it whose
/// 0x262 gave it this yaw.
fn stalker_with_a_beast_facing(yaw yaw: Float) -> game_connection.State {
  let #(state, _) =
    connection_support.entered_with_the_clients_tables(
      class_id: 5,
      saved_health: option.None,
    )
  connection_support.feed(
    state,
    connection_support.beast_appears_facing(unit_id: beast, yaw:),
  ).0
}

/// The 0x7ff of a frame as (Spell4 id, primary target unit) when it starts one of the two
/// children of Impale's four Proxies, 39426 or 39427.
fn impale_child_of(frame frame: Frame) -> Result(#(Int, Int), Nil) {
  use <- bool.guard(
    when: frame.message_id != spell_started.message_id,
    return: Error(Nil),
  )
  let assert Ok(start) = spell_started.decode(frame.body) as "a 0x7ff decodes"
  case start.spell4_id == 39_426 || start.spell4_id == 39_427 {
    True -> Ok(#(start.spell4_id, start.primary_target_unit_id))
    False -> Error(Nil)
  }
}

/// The children of Impale's Proxies the steps start, as (Spell4 id, primary target unit).
fn impale_children(
  steps steps: List(ConnectionStep(Request)),
) -> List(#(Int, Int)) {
  list.flat_map(steps, fn(taken) {
    connection_support.heard(taken, connection_support.keyed())
    |> list.filter_map(fn(frame) { impale_child_of(frame:) })
  })
}

/// Impale pressed at 1000 ms and its phases run until 3000 ms, each strike landing.
fn impale_pressed(
  state state: game_connection.State,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  connection_support.pressed_until(
    state:,
    bag_index: bag_index_of(base: impale_base),
    client_cast_id: 1,
    ms: 1000,
    until_ms: 3000,
  )
}

pub fn impale_at_the_back_of_a_creature_starts_39427_on_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(_, steps) = impale_pressed(state: stalker_with_a_beast_facing(yaw: 0.0))
  assert impale_children(steps:) == [#(39_427, beast)]
    as "the Beast at yaw 0 faces -z, away from the Stalker: the Stalker is in the 140 degrees behind it, so Proxy 85673 starts 39427 on it and 83818 starts nothing"
}

pub fn impale_in_front_of_a_creature_starts_39426_on_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(_, steps) =
    impale_pressed(state: stalker_with_a_beast_facing(yaw: 3.1415927410125732))
  assert impale_children(steps:) == [#(39_426, beast)]
    as "the Beast turned a half turn faces the Stalker: 83818 starts 39426 and 85673 starts nothing"
}

pub fn impale_at_the_side_of_a_creature_starts_39426_on_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let #(_, steps) =
    impale_pressed(state: stalker_with_a_beast_facing(yaw: 1.5707963705062866))
  assert impale_children(steps:) == [#(39_426, beast)]
    as "a quarter turn faces the Beast -x: the Stalker, behind it along z, is outside the arc"
}

pub fn impale_from_stealth_in_front_of_a_creature_starts_39427_on_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let state = stalker_with_a_beast_facing(yaw: 3.1415927410125732)
  // The Stalker's innate toggle (Spell4Base 30075) enters the stealth that caster gate 38585
  // reads. Impale's first go does not end it: the stealth ends after Impale's last go, so
  // the Proxies of phase 1 still see it.
  let #(state, _) =
    connection_support.pressed_until(
      state:,
      bag_index: bag_index_of(base: 30_075),
      client_cast_id: 1,
      ms: 500,
      until_ms: 900,
    )
  let #(_, steps) =
    connection_support.pressed_until(
      state:,
      bag_index: bag_index_of(base: impale_base),
      client_cast_id: 2,
      ms: 1000,
      until_ms: 3000,
    )
  assert impale_children(steps:) == [#(39_427, beast)]
    as "stealthed, 38585 passes and 38587 fails: 83819 starts 39427 on the Beast that faces the Stalker, and 83818 starts nothing"
}

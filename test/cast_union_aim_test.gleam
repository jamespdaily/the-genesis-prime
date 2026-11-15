//// The cast rule (`genesis_prime/game/cast`) for effect rows aimed by a combined flag
//// (`Spell4Effects.targetFlags` 3, 5 and 7): each unit the flag's bits name takes the row
//// once. Expected values come from these places:
//// - `Spell4Effects.targetFlags.combined` (a guess): 3, 5 and 7 hold the union of their
////   bits (1 the caster, 2 the primary target, 4 the area), and a unit the bits name twice
////   is one unit.
//// - `spell_plan.spell_hits_foes` (the server's choice, Jim's decision of 2026-11-15): the
////   area bit is read only in a spell that hits foes.
//// - The client's rows, kept in the fixture (`table_rows -- Spell4Effects <ids>`):
////   - 72210 (Spell4 35662), type 17, flags 7, until the end of 5000 ms; the spell's 72206
////     is a damage row aimed at the area, so it hits foes.
////   - 9717 (Spell4 5425), type 11, flags 3, 240000 ms, property 7 by 1.3.
////   - 123870 (Spell4 52400), type 10, flags 7, in a spell that hits no foes.
////   - 196408 (Spell4 75957), type 26, flags 5, a Proxy to Spell4 40841, in a spell whose
////     196409 is a damage row aimed at the caster and the area.
////   - 49023 (Spell4 28467), type 3, flags 5, a forced move; the spell's 49040 is a crowd
////     control row aimed at the area.
//// - Jim's decision 1 (2026-11-15): a heal reaches each unit its aim names once and heals
////   only the caster; a heal on another unit waits for #570.
//// - `cast` module doc: a press makes the caster its own primary target
////   (`Spell4TargetMechanics.targetType`), so a cast whose primary target is a creature is
////   a child a Proxy starts on a struck unit (`ProxyTarget.OnEachStruck`); the tests of a
////   row aimed at the primary target start the client's spell that way.

import cast_support as support
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/class_resource
import genesis_prime/game/spell_plan.{type Spell, Spell}
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import owned_test
import spell_tables

// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

/// The effect ids each unit's entry of the go lists, by unit, in unit order.
fn listed(effects effects: List(Effect)) -> List(#(Int, List(Int))) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  list.map(decoded.targets, fn(info) {
    #(
      info.unit_id,
      list.map(info.effects, fn(effect) { effect.spell4_effects_id })
        |> list.sort(int.compare),
    )
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

/// The client's spell with the rows the cast rule reads, as a spell of its own base.
fn client_spell(spell4_id spell4_id: Int) -> Spell {
  let real = spell_tables.client_spell(spell4_id:)
  Spell(
    ..support.child(spell4_id:, base: spell4_id),
    lasting: real.lasting,
    modifiers: real.modifiers,
    heals: real.heals,
    proxies: real.proxies,
    forced_moves: real.forced_moves,
    struck_moves: real.struck_moves,
  )
}

/// A press of the client's spell, as the spell of the planted base 3, and the go that
/// the round striking `struck` answers.
fn pressed_and_struck(
  spell spell: Spell,
  struck struck: List(Int),
) -> #(State, List(Effect)) {
  let in_base_3 = Spell(..spell, spell4_base_id: id.Spell4BaseId(3))
  let #(pressed, raw) =
    support.pressed_raw_in(
      plans: support.plans_of([in_base_3]),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, answered) =
    support.answered_by(
      state: pressed,
      effects: raw,
      at: 1000,
      struck: support.hits(struck),
    )
  #(state, list.append(raw, answered))
}

/// The spell started as a child on the creature 20, the unit the press struck, and the go
/// that the round striking `struck` answers for the child: its primary target is the
/// creature 20.
fn started_on_20(
  started started: Spell,
  struck struck: List(Int),
) -> #(State, List(Effect)) {
  let #(pressed, raw) =
    support.pressed_raw_in(
      plans: support.plans_starting_on_each_struck(started:),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, answered) =
    support.answered_each(
      caster: support.caster(),
      state: pressed,
      effects: raw,
      at: 1000,
      struck_of: fn(asked) {
        case asked.spell4_id == started.spell4_id {
          True -> support.hits(struck)
          False -> support.hits([20])
        }
      },
      rolls: [],
      poses: dict.new(),
    )
  #(state, list.append(raw, answered))
}

pub fn union_fluff_lands_on_caster_target_and_struck_units_once_each_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = client_spell(spell4_id: 35_662)
  assert list.map(spell.lasting, fn(row) { row.effect_id })
    == [Spell4EffectsId(72_210)]
    as "the client's spell 35662 holds the Fluff row 72210 aimed by flags 7"
  let #(_, effects) = started_on_20(started: spell, struck: [20, 21, 22])
  assert support.child_go_listing(effects:)
    == [#(7, [72_210]), #(20, [72_210]), #(21, [72_210]), #(22, [72_210])]
    as "the row is listed once on the caster, 7, once on the creature 20, which is both the primary target and struck, and once on each other struck creature"
  let #(_, effects) = started_on_20(started: spell, struck: [21, 22])
  assert support.child_go_listing(effects:)
    == [#(7, [72_210]), #(20, [72_210]), #(21, [72_210]), #(22, [72_210])]
    as "the primary target, 20, takes the row though the round struck it not"
}

pub fn union_property_modifier_changes_the_caster_and_the_target_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = client_spell(spell4_id: 5425)
  // The round of a phase whose change reaches the primary target strikes it
  // (`spell_area.PhaseStrike.strikes_primary_target`), and a change on a creature starts
  // only on a creature the go struck.
  let #(state, effects) = started_on_20(started: spell, struck: [20])
  let assert [#(started_by, cast.Property(modifier: _))] =
    support.caster_change_starts(effects:)
    as "the caster's own property changes once"
  assert started_by.effect_id == Spell4EffectsId(9717)
  let assert [cast.TargetChangeStarts(unit_id: 20, source: target_source, ..)] =
    support.target_changes(effects:)
    as "and the creature 20 the child's primary target takes the same row's change once"
  assert target_source == started_by
    as "both changes are the row 9717 of the one cast, so one timer's end removes each"
  let #(_, fired) =
    support.run_timers_each(
      caster: support.caster(),
      state:,
      effects:,
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  assert list.flat_map(fired, fn(step) {
      support.caster_change_ends(effects: step.1)
    })
    == [started_by]
    as "the caster's change ends once, by the node's timer"
  assert list.map(support.target_timeline(fired:), fn(step) { step.0 })
    == [241_000]
    as "the creature's change ends once, with the node, 240000 ms after the go"
}

pub fn union_heal_reaches_each_unit_once_and_heals_only_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = client_spell(spell4_id: 52_400)
  let #(_, effects) = started_on_20(started: spell, struck: [21])
  assert list.filter(support.caster_change_starts(effects:), fn(start) {
      case start.1 {
        cast.Heal(..) -> True
        _ -> False
      }
    })
    |> list.length
    == 1
    as "the caster is healed once, though flags 7 name it, the creature 20 and the area"
  let assert [#(LogDebug, line)] = support.logs(effects:)
    as "one debug line says the creature 20 is not healed"
  assert string.contains(line, "123870")
    && string.contains(line, "unit 20")
    && string.contains(line, "570")
    as "it names the row, the unit and the issue that will build heals on other units"
  assert support.child_go_listing(effects:) == [#(7, [123_870]), #(21, [])]
    as "the go lists the heal on the caster alone: the creature 20 lands nothing, and struck unit 21 lists none because the area bit is not read in a spell that hits no foes (#834)"
}

pub fn union_proxy_starts_its_child_on_the_caster_and_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let real = spell_tables.client_spell(spell4_id: 75_957)
  let assert [on_caster, on_struck] =
    list.filter(real.proxies, fn(proxy) {
      proxy.effect_id == Spell4EffectsId(196_408)
    })
    as "the client's spell 75957 holds the Proxy 196408 once for each of its two targets"
  assert [on_caster.target, on_struck.target]
    == [spell_plan.OnCaster, spell_plan.OnEachStruck]
  // The plan lifts a struck child's gains onto the Proxy that starts it, so that the go
  // gives them once, not once for each struck unit. The row's own child gives none, so
  // Telekinetic Strike's Proxy 62204 lends the gain (Spell4Effects 56858) to this one.
  let lent =
    list.flat_map(
      spell_plan.tree(spell: spell_tables.fixture_strike(), started: fn(_) {
        True
      }),
      fn(below) { below.proxies },
    )
    |> list.filter(fn(proxy) { proxy.effect_id == Spell4EffectsId(62_204) })
  let assert [lender] = lent as "Telekinetic Strike holds the Proxy 62204"
  let gaining =
    list.map(real.proxies, fn(proxy) {
      case proxy.target {
        spell_plan.OnEachStruck ->
          spell_plan.Proxy(..proxy, gains: lender.gains)
        spell_plan.OnCaster -> proxy
      }
    })
  let spell =
    Spell(..client_spell(spell4_id: 75_957), lasting: [], proxies: gaining)
  let #(_, effects) = pressed_and_struck(spell:, struck: [20, 21])
  let started =
    list.map(
      support.frames_of(message_id: spell_started.message_id, effects:),
      fn(frame) {
        let assert Ok(decoded) = spell_started.decode(frame.body)
        #(decoded.spell4_id, decoded.primary_target_unit_id)
      },
    )
    |> list.filter(fn(one) { one.0 == 40_841 })
    |> list.sort(fn(first, second) { int.compare(first.1, second.1) })
  assert started == [#(40_841, 7), #(40_841, 20), #(40_841, 21)]
    as "one child cast of Spell4 40841 on the caster, 7, and one on each creature the go hit"
  assert support.gains(effects:) == [[class_resource.Gain(slot: 1, amount: 1)]]
    as "the struck child's gain is given once, though two units were struck"
}

pub fn union_forced_move_moves_the_caster_and_the_struck_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = client_spell(spell4_id: 28_467)
  let assert [struck_move] = spell.struck_moves
    as "the client's spell 28467 holds the struck part of row 49023"
  let #(_, effects) = pressed_and_struck(spell:, struck: [21])
  assert support.throws(effects:)
    == [
      cast.ForcedMoveStarts(
        unit_id: 21,
        life: 1,
        struck_at_ms: 0,
        move: struck_move.move,
      ),
    ]
    as "the creature the go hit is thrown once"
  let assert [#(7, caster_effects), #(21, struck_effects)] = listed(effects:)
  assert list.contains(caster_effects, 49_023)
    as "the caster takes the row too: its own part is listed on it"
  assert struck_effects == [49_023]
}

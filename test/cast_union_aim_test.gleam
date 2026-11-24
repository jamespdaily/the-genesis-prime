//// The cast rule (`genesis_prime/game/cast`) for effect rows aimed by a combined flag
//// (`Spell4Effects.targetFlags` 3, 5 and 7): each unit the flag's bits name takes the row
//// once. Expected values come from these places:
//// - `Spell4Effects.targetFlags.combined` (a guess): 3, 5 and 7 hold the union of their
////   bits (1 the caster, 2 the primary target, 4 the area), and a unit the bits name twice
////   is one unit.
//// - `spell_plan.spell_hits_foes` (the server's choice, Jim's decision of 2026-11-15): the
////   area bit is read only in a spell that hits foes, or, for an instant heal, in a spell
////   whose area finds the caster's allies (`spell_plan.area_finds_allies`).
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
import class_resource_support
import genesis_prime/coverage/gaps
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/class_resource
import genesis_prime/game/effect_kind
import genesis_prime/game/held_changes
import genesis_prime/game/spell_plan.{type Spell, Spell}
import genesis_prime/message/spell_started
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import owned_test
import spell_tables
import unitest

// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

/// The client's spell with the rows the cast rule reads, as a spell of its own base.
fn client_spell(spell4_id spell4_id: Int) -> Spell {
  let real = spell_tables.client_spell(spell4_id:)
  support.with_effects(
    spell: support.with_effects(
      spell: support.with_effects(
        spell: support.with_effects(
          spell: support.with_effects(
            spell: support.with_effects(
              spell: support.child(spell4_id:, base: spell4_id),
              kinds: list.map(
                spell_plan.payloads(spell: real, as_kind: spell_plan.as_lasting),
                spell_plan.LastingEffect,
              ),
            ),
            kinds: list.map(
              spell_plan.payloads(spell: real, as_kind: spell_plan.as_modifier),
              spell_plan.ModifierEffect,
            ),
          ),
          kinds: list.map(
            spell_plan.payloads(spell: real, as_kind: spell_plan.as_heal),
            spell_plan.HealEffect,
          ),
        ),
        kinds: list.map(
          spell_plan.payloads(spell: real, as_kind: spell_plan.as_proxy),
          spell_plan.ProxyEffect,
        ),
      ),
      kinds: list.map(
        spell_plan.payloads(spell: real, as_kind: spell_plan.as_forced_move),
        spell_plan.ForcedMoveEffect,
      ),
    ),
    kinds: list.map(
      spell_plan.payloads(spell: real, as_kind: spell_plan.as_struck_move),
      spell_plan.StruckMoveEffect,
    ),
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
      state: cast_state.new(),
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
      state: cast_state.new(),
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
  assert list.map(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_lasting),
      fn(row) { row.effect_id },
    )
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
  let assert [
    #(started_by, cast_state.HeldChange(held_changes.Property(modifier: _))),
  ] = support.caster_change_starts(effects:)
    as "the caster's own property changes once"
  assert started_by.effect_id == Spell4EffectsId(9717)
  let assert [
    cast_state.TargetChangeStarts(unit_id: 20, source: target_source, ..),
  ] = support.target_changes(effects:)
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
  assert list.count(support.caster_change_starts(effects:), fn(start) {
      case start.1 {
        cast_state.Heal(..) -> True
        cast_state.HeldChange(..) | cast_state.Look(..) -> False
      }
    })
    == 1
    as "the caster is healed once, though flags 7 name it, the creature 20 and the area"
  let assert [#(LogDebug, first), #(LogDebug, second)] = support.logs(effects:)
    as "one debug line for each creature the row names and cannot heal"
  assert string.contains(first, "123870")
    && string.contains(first, "unit 20")
    && string.contains(first, "lands nothing here")
    as "the first names the row, the primary target 20 and what is missing"
  assert string.contains(second, "123870")
    && string.contains(second, "unit 21")
    && string.contains(second, "lands nothing here")
    as "the second names the row and the struck unit 21, which the area bit names since the spell's area finds allies"
  assert support.child_go_listing(effects:) == [#(7, [123_870]), #(21, [])]
    as "the go lists the heal on the caster alone: no creature is healed, and struck unit 21 lists none"
}

pub fn union_proxy_starts_its_child_on_the_caster_and_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let real = spell_tables.client_spell(spell4_id: 75_957)
  let assert [on_caster, on_struck] =
    list.filter(
      spell_plan.payloads(spell: real, as_kind: spell_plan.as_proxy),
      fn(proxy) { proxy.effect_id == Spell4EffectsId(196_408) },
    )
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
      fn(below) {
        spell_plan.payloads(spell: below, as_kind: spell_plan.as_proxy)
      },
    )
    |> list.filter(fn(proxy) { proxy.effect_id == Spell4EffectsId(62_204) })
  let assert [lender] = lent as "Telekinetic Strike holds the Proxy 62204"
  let gaining =
    list.map(
      spell_plan.payloads(spell: real, as_kind: spell_plan.as_proxy),
      fn(proxy) {
        case proxy.target {
          spell_plan.OnEachStruck ->
            spell_plan.Proxy(..proxy, gains: lender.gains)
          spell_plan.OnCaster
          | spell_plan.OnPrimaryTarget
          | spell_plan.OnEachAlly -> proxy
        }
      },
    )
  let spell =
    support.with_effects(
      spell: support.without_effects(
        spell: client_spell(spell4_id: 75_957),
        as_kind: spell_plan.as_lasting,
      ),
      kinds: list.map(gaining, spell_plan.ProxyEffect),
    )
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
  let assert [struck_move] =
    spell_plan.payloads(spell:, as_kind: spell_plan.as_struck_move)
    as "the client's spell 28467 holds the struck part of row 49023"
  let #(_, effects) = pressed_and_struck(spell:, struck: [21])
  assert support.throws(effects:)
    == [
      cast_state.ForcedMoveStarts(
        unit_id: 21,
        life: 1,
        struck_at_ms: 0,
        move: struck_move.move,
      ),
    ]
    as "the creature the go hit is thrown once"
  let assert [#(7, caster_effects), #(21, struck_effects)] =
    support.listed_by_unit(effects:)
  assert list.contains(caster_effects, 49_023)
    as "the caster takes the row too: its own part is listed on it"
  assert struck_effects == [49_023]
}

// ---- what a friendly area's Proxy gives the caster ----

const press_ms = 1000

const until_ms = 16_000

/// A caster of the class holding `points` of its resource (`Resource.start`), a full Focus
/// pool as entry gives it, and 1 health of a million, so every heal lands.
fn hurt_caster(class_id class_id: Int, points points: Float) -> Caster {
  let resource =
    class_resource.Resource(
      ..class_resource_support.resource_of(class_id),
      start: points,
    )
  support.hurt(
    caster: cast_state.Caster(
      ..support.caster(),
      resources: class_resource.new(
        resource:,
        properties: class_resource_support.properties_of(
          class_id:,
          changes: [],
          level: 1,
        ),
      ),
    ),
  )
}

/// The press of the client's spell by a caster of the class holding `points`, driven to
/// `until_ms`: the spell, the press's effects and each step, the press first.
fn driven(
  spell4_id spell4_id: Int,
  class_id class_id: Int,
  points points: Float,
) -> #(Spell, List(Effect), List(#(Int, List(Effect)))) {
  let spell = spell_tables.client_spell(spell4_id:)
  let #(effects, steps) =
    support.pressed_and_run(
      spell:,
      caster: hurt_caster(class_id:, points:),
      press_ms:,
      until_ms:,
    )
  #(spell, effects, [#(press_ms, effects), ..steps])
}

/// Every effect of the steps, in order.
fn effects_of(steps steps: List(#(Int, List(Effect)))) -> List(Effect) {
  list.flat_map(steps, fn(step) { step.1 })
}

/// What the steps start on the caster: the time of the step, the row and the change.
fn caster_starts(
  steps steps: List(#(Int, List(Effect))),
) -> List(#(Int, Int, cast_state.CasterChange)) {
  list.flat_map(steps, fn(step) {
    list.map(support.caster_change_starts(effects: step.1), fn(start) {
      #(step.0, { start.0 }.effect_id.value, start.1)
    })
  })
}

/// The spell and every spell below it that a press starts.
fn whole_tree(spell spell: Spell) -> List(Spell) {
  spell_plan.tree(spell:, started: fn(_) { True })
}

/// The heals of health among the starts, as the time and the row; each heals at least a
/// point.
fn heals_of(
  starts starts: List(#(Int, Int, cast_state.CasterChange)),
) -> List(#(Int, Int)) {
  list.filter_map(starts, fn(start) {
    case start.2 {
      cast_state.Heal(vital: effect_kind.Health, amount:) -> {
        assert amount > 0 as "a heal gives at least a point"
        Ok(#(start.0, start.1))
      }
      cast_state.Heal(vital: effect_kind.Shield, ..)
      | cast_state.HeldChange(..)
      | cast_state.Look(..) -> Error(Nil)
    }
  })
}

/// The absorbs among the starts, as the time, the row and the pool's size.
fn absorbs_of(
  starts starts: List(#(Int, Int, cast_state.CasterChange)),
) -> List(#(Int, Int, Int)) {
  list.filter_map(starts, fn(start) {
    case start.2 {
      cast_state.HeldChange(held_changes.Absorb(amount:, ..)) -> {
        assert amount > 0 as "an absorb pool holds at least a point"
        Ok(#(start.0, start.1, amount))
      }
      cast_state.HeldChange(held_changes.Property(..))
      | cast_state.Heal(..)
      | cast_state.Look(..) -> Error(Nil)
    }
  })
}

/// The time and row of each absorb among the starts.
fn absorb_times_and_rows(
  starts starts: List(#(Int, Int, cast_state.CasterChange)),
) -> List(#(Int, Int)) {
  list.map(absorbs_of(starts:), fn(absorb) { #(absorb.0, absorb.1) })
}

/// `count` heals of `row`, the first at `first_ms` and one more every `every_ms`: the
/// client's schedule of a row, written out by hand.
fn every(
  row row: Int,
  first_ms first_ms: Int,
  every_ms every_ms: Int,
  count count: Int,
) -> List(#(Int, Int)) {
  list.repeat(Nil, count)
  |> list.index_map(fn(_, index) { #(first_ms + index * every_ms, row) })
}

pub fn each_ability_with_a_proxy_at_a_friendly_area_gives_its_caster_what_its_text_says_and_nothing_more_with_no_ally_in_sight_test() -> Nil {
  use <- owned_test.run(120_000)
  // Texts: 245408 (Mental Boon heals "yourself and ... hurt allies every 0.5s"), 360845
  // (Mending Probes), 315699 (Runes of Protection), 287485 (Astral Infusion), 389501
  // (Flash restores health "to yourself and N allies"). The allies are the area's: the caster
  // sees none here, so the area selects none and the caster takes what each spell gives it.
  let esper = 3
  let medic = 4
  let spellslinger = 7
  let accepted_and_alone = fn(name, effects, steps) {
    assert support.refusal_results(effects:) == []
      as { name <> ": the press is accepted" }
    assert support.target_changes(effects: effects_of(steps:)) == []
      as { name <> " lands nothing on a creature: no ally is in sight" }
  }

  // Mental Boon: the Esper holds 3 Psi Points and the cast spends all of them, the base
  // cost of 1 (Spell4 33257's innate cost) and 2 above it, which picks the Proxy whose
  // emmValue is 2 (Spell4Effects 76774: EqualTo). Its child heals by row 76784 (Spell4
  // 36623), and the Proxy ticks every 500 ms for 6,000 ms (tickTime 500, durationTime
  // 6000), the first tick 500 ms after the go (text 245408, "every 0.5s").
  let #(_, boon_effects, boon_steps) =
    driven(spell4_id: 33_257, class_id: esper, points: 3.0)
  accepted_and_alone("Mental Boon", boon_effects, boon_steps)
  let boon_starts = caster_starts(steps: boon_steps)
  assert heals_of(starts: boon_starts)
    == every(row: 76_784, first_ms: press_ms + 500, every_ms: 500, count: 12)
    as "twelve heals of row 76784, one each 500 ms from 1,500 ms to 7,000 ms (text 245408), none of another tier's row"
  assert list.length(boon_starts) == 12
    as "Mental Boon gives the caster nothing else: its Nimble lands on no unit, since no ally is in sight"

  // Mending Probes: the ticking heal of its child. Proxy 92693 starts Spell4 41334 at the
  // go; its heal, row 92704, has delay 2000, tickTime 2000 and durationTime 12000. The
  // client has no tick timer, so the ticks are the server's schedule (a guess, `ticking`):
  // tick k lands 2000 + k * 2000 ms after the go, the five within the 12,000 ms life.
  let #(_, probes_effects, probes_steps) =
    driven(spell4_id: 41_333, class_id: medic, points: 4.0)
  accepted_and_alone("Mending Probes", probes_effects, probes_steps)
  let probe_starts = caster_starts(steps: probes_steps)
  assert heals_of(starts: probe_starts)
    == every(
      row: 92_704,
      first_ms: press_ms + 2000 + 2000,
      every_ms: 2000,
      count: 5,
    )
    as "Mending Probes heals the caster by row 92704 every 2,000 ms (text 360845)"
  assert list.length(probe_starts)
    == list.length(heals_of(starts: probe_starts))
    as "and gives it nothing else"

  // Runes of Protection and its Surge alternate: one absorb at the go, the alternate's
  // larger. Their absorbs are rows 206315 (Spell4 78708) and 206334 (Spell4 78721), each
  // lasting 10,000 ms.
  let absorbed = fn(spell4_id, row) {
    let #(_, effects, steps) =
      driven(spell4_id:, class_id: spellslinger, points: 100.0)
    accepted_and_alone("an absorb spell", effects, steps)
    let starts = caster_starts(steps:)
    assert list.length(starts) == list.length(absorbs_of(starts:))
      as "the spell gives the caster an absorb and nothing else"
    assert absorb_times_and_rows(starts:) == [#(press_ms, row)]
      as "one absorb at the go (text 315699)"
    absorbs_of(starts:)
  }
  let assert [#(_, _, runes_amount)] = absorbed(39_092, 206_315)
  let assert [#(_, _, surge_amount)] = absorbed(39_327, 206_334)
  assert surge_amount > runes_amount
    as "the Surge alternate's pool is the larger"

  // Astral Infusion and its Surge alternate: an absorb at the go (rows 204916 and 204935,
  // each 5,000 ms) and a heal (rows 85062 and 129829, tickTime 1000, durationTime 5000)
  // every 1,000 ms from the go.
  list.each(
    [#(35_870, 204_916, 85_062), #(54_717, 204_935, 129_829)],
    fn(astral) {
      let #(spell4_id, absorb_row, heal_row) = astral
      let #(_, effects, steps) =
        driven(spell4_id:, class_id: spellslinger, points: 100.0)
      accepted_and_alone("Astral Infusion", effects, steps)
      let starts = caster_starts(steps:)
      assert absorb_times_and_rows(starts:) == [#(press_ms, absorb_row)]
        as "one absorb at the go (text 287485)"
      assert heals_of(starts:)
        == every(
          row: heal_row,
          first_ms: press_ms + 1000,
          every_ms: 1000,
          count: 5,
        )
        as "and a heal every 1,000 ms"
      assert list.length(starts)
        == list.length(absorbs_of(starts:)) + list.length(heals_of(starts:))
        as "nothing else"
    },
  )

  // Flash: its own heal once, row 94498 (Spell4 41926, tickTime 0), and no detonation of
  // Mending Probes.
  let #(flash, flash_effects, flash_steps) =
    driven(spell4_id: 41_926, class_id: medic, points: 4.0)
  accepted_and_alone("Flash", flash_effects, flash_steps)
  assert list.map(whole_tree(spell: flash), fn(spell) { spell.spell4_id.value })
    == [41_926]
    as "Flash's plan holds no child: Proxy 180600's detonation chain is left out"
  assert list.map(caster_starts(steps: flash_steps), fn(start) {
      #(start.0, start.1)
    })
    == [#(press_ms, 94_498)]
    as "Flash heals the caster once, by row 94498, at the go (text 389501)"
  assert list.flat_map(flash_steps, fn(step) {
      support.started_in(effects: step.1)
    })
    == []
    as "no 0x7ff of another spell: none for 70756, 60221 to 60225 or 77637, whose Fluff would show a 120 s Recently Saved"
}

pub fn mental_boons_nimble_is_planned_and_lands_on_no_unit_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("gaps")
  // Rows 84796, 84798, 84800, 84802 and 84804 (type 11, flags 2, property 39, 550 ms) sit
  // in 33258 and 36622 to 36625. Text 314819 names the Nimble. A flags 2 modifier lands on a
  // creature the go struck (`cast/control`), and a child started on the caster strikes none.
  let #(boon, _, steps) = driven(spell4_id: 33_257, class_id: 3, points: 3.0)
  let rows =
    whole_tree(spell: boon)
    |> list.flat_map(fn(spell) {
      spell_plan.payloads(spell:, as_kind: spell_plan.as_modifier)
    })
    |> list.filter_map(fn(modifier) {
      case modifier.change {
        spell_plan.StruckChange(..) -> Ok(modifier.effect_id.value)
        spell_plan.PropertyChange(..)
        | spell_plan.AbsorbChange(..)
        | spell_plan.LookChange(..) -> Error(Nil)
      }
    })
    |> list.unique
    |> list.sort(int.compare)
  assert rows == [84_796, 84_798, 84_800, 84_802, 84_804]
    as "the plan reads the five Nimble rows as changes of a struck creature"
  assert heals_of(starts: caster_starts(steps:)) != [] as "the heal starts"
  assert support.property_starts(effects: effects_of(steps:)) == []
    && support.target_changes(effects: effects_of(steps:)) == []
    as "this pins the gap: Nimble changes no unit, the caster's heal is all Mental Boon gives"
  assert list.any(gaps.registry(), fn(entry) {
    entry.area == "Casting"
    && string.contains(entry.missing, "Nimble")
    && string.contains(entry.missing, "primary target")
  })
    as "the registry states the gap for the coverage measure"
}

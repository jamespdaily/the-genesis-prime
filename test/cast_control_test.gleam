//// The cast rule (`genesis_prime/game/cast`) for the crowd-control states a go landed:
//// what the go lists, the node the caster's cast keeps for the state's life, and the
//// caster's combat log. The creature's answer is given as it comes back
//// (`cast.Hit`'s `controls`), the spell is planted and the clock is driven. Expected
//// values come from these places:
//// - Kick's CCStateSet row 140382 (`Spell4Effects.140382`): delayTime 166 ms,
////   durationTime 3000 ms, a Knockdown; the creature holds it from its arrival until
////   delay plus duration (`creature_control`), which is the end time the answer carries.
//// - `cc_state.instance_id`: the go's effect info for the state names the instance id
////   the strike gave, which the creature's 0x87f carries too.
//// - `cc_state.end` and `cast.target_node_end`: the client ends no node on time, so the
////   cast's 0x7fe waits until the node's life is over.
//// - `opcode.0x247.cc_state`: combat log type 1 names the state, whether it was removed,
////   the Interrupt Armor it hit, the result and the cast data (caster, target, Spell4,
////   combat result). The coordinator's decision on the issue: the caster writes it with
////   the go (removed 0) and when the state ends (removed 1), and none when the unit left
////   its sight first (`cast.unit_removed`).

import cast_support as support
import crowd_control_support
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/lasting
import genesis_prime/game/spell_plan
import genesis_prime/game/spend
import genesis_prime/message/combat_log
import genesis_prime/message/combat_log_cc_state.{CombatLogCcState}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_result
import genesis_prime/message/crowd_control_state.{Knockdown}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/list
import owned_test

/// Kick's spell, base 3, planted with no effect of its own: what a go lists comes from
/// the creature's answer.
fn kick_plans() -> spell_plan.Plans {
  support.with_spells(plans: support.plans(), spells: [
    support.child(spell4_id: 58_591, base: 3),
  ])
}

const bag_of_base_3 = 11

/// Kick pressed at 1000 whose round closed at `go_ms` having struck unit 20, which took
/// the Knockdown until `ends_at_ms`.
fn kicked(
  go_ms go_ms: Int,
  ends_at_ms ends_at_ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans: kick_plans(),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  support.answered_by(state:, effects:, at: go_ms, struck: [
    cast.Hit(
      unit_id: 20,
      unit: cast.HitCreature(life: 1, struck_at_ms: 0),
      descriptions: [],
      controls: [
        crowd_control_support.kick_landed(ends_at_ms:),
      ],
    ),
  ])
}

fn logged(
  effects effects: List(Effect),
) -> List(combat_log_entry.CombatLogEntry) {
  list.map(
    support.frames_of(message_id: combat_log.message_id, effects:),
    fn(frame) {
      let assert Ok(decoded) = combat_log.decode(frame.body)
        as "a 0x247 the rule wrote decodes"
      decoded.entry
    },
  )
}

fn entry(removed removed: Int) -> combat_log_entry.CombatLogEntry {
  combat_log_entry.CcState(CombatLogCcState(
    state: Knockdown,
    removed:,
    interrupt_armor_hit: 0,
    result: crowd_control_result.Ok,
    diminishing_returns_id: 0,
    caster_unit_id: 7,
    target_unit_id: 20,
    spell4_id: 58_591,
    combat_result: combat_result.Hit,
  ))
}

pub fn a_go_lists_a_state_the_creature_took_with_the_instance_id_its_strike_gave_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = kicked(go_ms: 1000, ends_at_ms: 4166)
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.unit_id == 20
  assert info.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 140_382,
        instance_id: 28_673,
        delay_ms: 166,
        field_4: 0,
        result: spell_effect_result.Bit(SpellEffectBit(field_2: 0)),
      ),
    ]
    as "Spell4Effects.140382's delay 166 and the instance id the strike gave, which the 0x87f carries too (cc_state.instance_id)"
}

pub fn a_creature_that_took_no_state_has_no_effect_listed_for_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.pressed_raw_in(
      plans: kick_plans(),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_by(state:, effects:, at: 1000, struck: [
      cast.Hit(
        unit_id: 20,
        unit: cast.HitCreature(life: 1, struck_at_ms: 0),
        descriptions: [],
        controls: [],
      ),
    ])
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.effects == []
    as "armor above 0 or a dead creature answers Landed with no state: nothing is listed"
  assert logged(effects:) == [] as "and nothing is logged"
}

pub fn the_cast_lingers_until_the_states_own_end_and_then_sends_its_0x7fe_test() -> Nil {
  use <- owned_test.run(5000)
  // The round waited 900 ms for a slow creature: the go is at 1900 and the creature
  // holds the state until 4166 (its arrival at 1000, plus 166, plus 3000).
  let #(state, effects) = kicked(go_ms: 1900, ends_at_ms: 4166)
  assert support.finished_ids(support.writes(effects:)) == []
    as "the cast's 0x7fe waits for the node (cast.target_node_end)"
  let assert [frame, ..] =
    support.frames_of(message_id: spell_cast_confirmed.message_id, effects:)
    as "the press was confirmed"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
  let due =
    list.filter(support.started_timers(effects:), fn(started) {
      started.1 == 2266
    })
  assert list.length(due) == 2
    as "the node and the state's end entry both end at the creature's 4166, 2266 ms after the go and not 3166 ms after it"
  let finished =
    list.flat_map(due, fn(started) {
      let #(_, effects) = support.fired(state:, timer: started.0, at: 4166)
      support.finished_ids(support.writes(effects:))
    })
  assert finished == [confirmed.server_cast_id]
    as "when the node's life is over the cast sends its 0x7fe"
}

pub fn the_caster_logs_the_state_with_its_go_and_again_when_it_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) = kicked(go_ms: 1000, ends_at_ms: 4166)
  assert logged(effects:) == [entry(removed: 0)]
    as "type 1, removed 0, with the go: the caster, the creature and Kick (opcode.0x247.cc_state)"
  let ends =
    list.filter(support.started_timers(effects:), fn(started) {
      started.1 == 3166
    })
  assert list.length(ends) == 2
    as "a timer for the node's end and one for the state's end entry, both at the creature's end"
  let ended =
    list.flat_map(ends, fn(started) {
      let #(_, effects) = support.fired(state:, timer: started.0, at: 4166)
      logged(effects:)
    })
  assert ended == [entry(removed: 1)]
    as "exactly one of the two timers writes the end entry: type 1, removed 1"
}

pub fn a_unit_that_left_the_casters_sight_gets_no_end_entry_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) = kicked(go_ms: 1000, ends_at_ms: 4166)
  let ends =
    list.map(
      list.filter(support.started_timers(effects:), fn(started) {
        started.1 == 3166
      }),
      fn(started) { started.0 },
    )
  let #(state, removed) =
    cast.unit_removed(cast: state, unit_id: 20, now_ms: 2000)
  assert list.any(support.cancelled_timers(effects: removed), fn(timer) {
    list.contains(ends, timer)
  })
    as "the client dropped the unit with its 0x355, so the end entry's timer is cancelled"
  let ended =
    list.flat_map(ends, fn(timer) {
      let #(_, effects) = support.fired(state:, timer:, at: 4166)
      logged(effects:)
    })
  assert ended == [] as "and a timer that fires late writes nothing"
}

pub fn a_later_go_does_not_move_the_nodes_end_past_the_states_own_end_test() -> Nil {
  use <- owned_test.run(5000)
  // A Multiphase spell: its first go lands the Knockdown, held until 4000, and its
  // second go, at 2000, adds a Fluff effect of 100 ms. `lasting.given` arms the Fluff
  // effect again from the second go, but the state ends when the creature says.
  let phased =
    spell_plan.Spell(
      ..support.child(spell4_id: 58_591, base: 3),
      method: spell_plan.Multiphase,
      phase_delays_ms: [0, 1000],
      lasting: [
        spell_plan.Lasting(
          effect_id: Spell4EffectsId(9),
          phase_flags: 2,
          aim: spell_plan.AimsAtArea,
          row: lasting.LastingRow(
            delay_ms: 0,
            duration_ms: 100,
            until_removed: False,
          ),
          condition: spell_plan.Always,
          tag: spend.always,
        ),
      ],
    )
  let plans = support.with_spells(plans: support.plans(), spells: [phased])
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, first) =
    support.answered_by(state:, effects: pressed, at: 1000, struck: [
      cast.Hit(
        unit_id: 20,
        unit: cast.HitCreature(life: 1, struck_at_ms: 0),
        descriptions: [],
        controls: [
          crowd_control_support.kick_landed(ends_at_ms: 4000),
        ],
      ),
    ])
  let assert [#(go, 1000)] =
    list.filter(support.started_timers(effects: first), fn(started) {
      started.1 == 1000
    })
    as "the second go waits 1000 ms"
  let #(state, going) = support.fired_raw(state:, timer: go, at: 2000)
  let #(_, second) =
    support.answered_by(state:, effects: going, at: 2000, struck: [
      cast.Hit(
        unit_id: 20,
        unit: cast.HitCreature(life: 1, struck_at_ms: 0),
        descriptions: [],
        controls: [],
      ),
    ])
  let afters =
    list.map(support.started_timers(effects: second), fn(started) { started.1 })
  assert list.contains(afters, 2000)
    as "the node ends at the state's 4000, 2000 ms after the second go"
  assert !list.contains(afters, 3000)
    as "and not at 2000 + 3000, which re-arming the state as an effect would give"
}

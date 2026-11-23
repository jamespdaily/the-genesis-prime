//// The unit a bag press names as its target: the cast rule judges it by the spell's targeting
//// kind and starts the cast on it (`genesis_prime/game/cast/press` `at_a_unit`), for the
//// press (0x9a), the held key (0x4db), a repeat and a press queued behind the current cast.
//// Expected values come from these places.
//// - `opcode.0x9a` and `opcode.0x4db`: the client sends the target it chose with the press,
////   by the kind of the spell (`Spell4TargetMechanics.targetType`, picker `0x14055bdc0`): the
////   caster itself for kinds 0, 2, 6 and 7, the unit given, the player's target or a nearby
////   unit for kinds 1, 3, 5 and 8, and a refusal 91 when there is none.
//// - `opcode.0x9d.target_checks`: what the client refuses before it sends a cast at a unit:
////   91 for no target, 32 for the caster as its own target unless the mechanics flags let it
////   (bit value 2), 102 for a player when the valid targets' bit 0 is set.
//// - Mind Over Body (Spell4 32820, base 19030): Spell4TargetMechanics row 4 (targetType 1,
////   flags 11: beneficial, may target itself, passes the faction test at a friendly player),
////   Spell4ValidTargets row 1 (bitmask 0), and Spell4Effects 62019, an instant heal aimed at
////   the primary target (targetFlags 2).
//// - Telekinetic Strike (Spell4 32893, base 19102): Spell4TargetMechanics row 6 (targetType 2,
////   the caster's kind).
//// - A hostile Targeted spell has Spell4TargetMechanics row 3 (targetType 1, flags 16), the
////   row of Spatial Shift (base 16454); a Targeted spell the caster may not target itself
////   has row 5 (flags 9); a spell that refuses a player has Spell4ValidTargets row 9
////   (bitmask 1). The tests give the real ability the targeting of those rows, since the
////   fixture holds no ability with them.

import cast_support as support
import class_resource_support
import genesis_prime/game/activate
import genesis_prime/game/cast
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/spell_plan.{type Plans, type Spell, Spell}
import genesis_prime/game/strike_tell
import genesis_prime/game/target_mechanic.{Targeted, Targeting}
import genesis_prime/message/cast_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_effect_result
import genesis_prime/step.{ConnectionId, LogWarning}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import map_support
import owned_test
import prerequisite_support
import spell_tables

const mind_over_body_base = 19_030

/// The Esper's class id (`class_resource_support`).
const esper_class = 3

const telekinetic_strike_base = 19_102

/// The caster's unit, as the default caster has it.
const caster_unit = 7

/// A player in the caster's sight.
const ally = 40

/// A creature in the caster's picture.
const creature = 41

/// A unit the caster's picture does not show.
const stranger = 42

/// The bag indexes of the planted abilities of base 3 and base 2 in the default caster's bag
/// (`cast_support.abilities`).
const bag_of_base_3 = 11

const bag_of_base_2 = 10

/// Mind Over Body as the client's rows plan it (Spell4 32820), which the fixture's starting
/// plans do not hold: it is a level 6 ability.
fn mind_over_body() -> Spell {
  spell_tables.client_spell(spell4_id: 32_820)
}

/// The starting plans with Mind Over Body.
fn plans() -> Plans {
  support.plans_with(spell: mind_over_body())
}

fn ability(base base: Int) -> Spell {
  support.ability_in(plans: plans(), base:)
}

/// What the map's `SeenBy` of the player of that unit would give.
fn address(unit_id unit_id: Int) -> PlayerAddress {
  PlayerAddress(
    connection: ConnectionId(unit_id),
    unit_id:,
    stay: map_support.stay(count: unit_id),
  )
}

fn sight(players players: List(Int)) -> Dict(Int, PlayerAddress) {
  dict.from_list(
    list.map(players, fn(unit_id) { #(unit_id, address(unit_id:)) }),
  )
}

/// The default caster, who sees these players.
fn seeing(players players: List(Int)) -> Caster {
  cast_state.Caster(..support.caster(), players_in_sight: sight(players:))
}

/// The Esper with Mind Over Body at bag index 0 and Telekinetic Strike at 1, holding the
/// Focus Mind Over Body costs (22, `Spell4 32820`), who sees these players.
fn esper_seeing(players players: List(Int)) -> Caster {
  let bag = [
    Spell4BaseId(mind_over_body_base),
    Spell4BaseId(telekinetic_strike_base),
  ]
  cast_state.Caster(
    ..seeing(players:),
    abilities: bag,
    book: bag,
    resources: class_resource_support.resources_with(
      class_id: esper_class,
      changes: [#(5, 100.0)],
      level: 1,
    ),
  )
}

/// What each unit is to the caster: the ally a player, the creature a creature, any other
/// unseen.
fn picture(unit_id: Int) -> activate.Target {
  case unit_id == ally, unit_id == creature {
    True, _ -> activate.AnotherPlayer
    False, True -> support.a_creature()
    False, False -> activate.Unseen
  }
}

/// A 0x9a of the bag index at `target`, with the client's cast id 9, taken by the rule.
fn pressed(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  taken(
    plans:,
    state:,
    caster:,
    message: cast_state.Pressed,
    body: support.press_body(client_cast_id: 9, bag_index:, target:, press: 1),
    at: ms,
  )
}

/// The message taken by the rule on the picture, which stops the test when the rule refuses it.
fn taken(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  message message: cast_state.Message,
  body body: BitArray,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    cast.take(
      cast: state,
      message:,
      body:,
      caster:,
      plans:,
      target_of: picture,
      now: support.at(ms:),
    )
    as "the message fits"
  taken
}

/// A 0x4db of the bag index at `target`, taken by the rule.
fn key_at(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  held held: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  taken(
    plans:,
    state:,
    caster:,
    message: cast_state.KeyHeld,
    body: support.hold_body(bag_index:, target:, held:),
    at: ms,
  )
}

/// The primary target each cast the effects start names in its 0x7ff, in order.
fn started_at(effects effects: List(Effect)) -> List(Int) {
  list.map(support.started_in(effects:), fn(start) {
    start.primary_target_unit_id
  })
}

/// The primary target each 0x7fd the effects write names, in order.
fn confirmed_at(effects effects: List(Effect)) -> List(Int) {
  list.map(support.confirmed_in(effects:), fn(confirmed) {
    confirmed.primary_target_unit_id
  })
}

/// The client cast id and result of each 0x7fc the effects write, in order.
fn refused_as(effects effects: List(Effect)) -> List(#(Int, Int)) {
  list.map(support.refused_in(effects:), fn(refused) {
    #(refused.client_cast_id, cast_result.to_value(refused.result))
  })
}

/// A planted spell of the base given, cast as Mind Over Body is (a beneficial Targeted
/// kind), which goes at once and has the cooldown given.
fn targeted(
  spell4_id spell4_id: Int,
  base base: Int,
  cooldown_ms cooldown_ms: Int,
) -> Spell {
  Spell(
    ..support.child(spell4_id:, base:),
    targeting: mind_over_body().targeting,
    cooldown_ms:,
  )
}

// ---- a heal pressed at an ally ----

pub fn a_heal_pressed_at_another_player_does_not_heal_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = esper_seeing(players: [ally])
  let #(state, pressed) =
    pressed(
      plans: plans(),
      state: cast_state.new(),
      caster:,
      bag_index: 0,
      target: ally,
      at: 1000,
    )
  assert confirmed_at(effects: pressed) == [ally]
    as "opcode.0x9a: Mind Over Body is the Targeted kind (Spell4TargetMechanics row 4), so the cast starts on the ally the press named: the 0x7fd names it as the primary target (a cast the client pressed has no 0x7ff)"
  // The go is at the end of the cast time, 1250 ms (Spell4 32820), and its round strikes nobody.
  let #(_, steps) =
    support.run_timers_each(
      caster:,
      state:,
      effects: pressed,
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  let after = list.flat_map(steps, fn(step) { step.1 })
  assert support.listed_effect_ids(effects: after) == []
    as "Spell4Effects 62019 aims at the primary target, which is the ally: the go lists no heal"
  assert support.caster_change_starts(effects: list.append(pressed, after))
    == []
    as "no heal is carried for the caster: a heal on another unit lands nothing until the target applies it"
  // The ally's connection applied the heal and the go's round names it as a player another
  // player healed.
  let healed =
    cast_state.Hit(
      unit_id: ally,
      unit: cast_state.HitOtherPlayer(heals: [
        strike_tell.HealLanded(
          effect_id: Spell4EffectsId(62_019),
          vital: effect_kind.Health,
          split: heal_split.Split(
            amount: 121,
            shield: 0,
            health: 100,
            overheal: 21,
          ),
        ),
      ]),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    )
  let #(_, answered_steps) =
    support.run_timers_each(
      caster:,
      state:,
      effects: pressed,
      from_ms: 1000,
      struck_of: fn(_) { [healed] },
    )
  let answered = list.flat_map(answered_steps, fn(step) { step.1 })
  assert list.length(support.goes_in(effects: answered)) == 1
    as "the round answered by the ally writes one 0x7f4"
  assert targets_named(effects: answered) == [ally]
    as "the go's 0x7f4 names the ally it healed"
  assert support.listed_on(effects: answered, unit_id: ally)
    == [
      #(
        62_019,
        support.heal_result(amount: 121, kind: damage_type.Heal, overkill: 21),
      ),
    ]
    as "and lists Spell4Effects 62019 on it with the heal the ally applied: a Heal of 121 with 21 overheal, which the client logs as a heal of 121 and an overheal of 21 while the ally's health rose by 100 (`spell.heal_result_log`)"
  assert support.listed_effect_ids(effects: answered) == [62_019]
    as "and lists nothing else"
  assert support.started_timers(effects: answered) == []
    as "the ally's heal arms no timer: the ally applied it itself"
  assert list.contains(support.written_ids(effects: answered), 0x07FE)
    as "the go's step writes the cast's 0x7fe, since the listed heal gives the caster's node no life"
  assert support.caster_change_starts(effects: list.append(pressed, answered))
    == []
    as "the ally's heal is carried for the ally alone: still none for the caster"
  assert cast_heal.ticking_struck(struck: [healed]) == []
    as "a player another player healed arms no periodic row"
  assert cast_proc.hit_events(spell: mind_over_body(), struck: [healed]) == []
    as "and raises no proc event for the healer"
}

/// The unit ids the effects' 0x7f4 names as targets, in order.
fn targets_named(effects effects: List(Effect)) -> List(Int) {
  list.map(support.go_targets(effects:), fn(target) { target.unit_id })
}

/// What the ally's connection answered for one row: the row's id, the vital it raised and
/// the split of its amount.
fn landed(
  effect_id effect_id: Int,
  vital vital: effect_kind.Vital,
  split split: heal_split.Split,
) -> strike_tell.HealLanded {
  strike_tell.HealLanded(effect_id: Spell4EffectsId(effect_id), vital:, split:)
}

/// A round whose one unit is the ally, who answered these heals.
fn ally_answered(
  heals heals: List(strike_tell.HealLanded),
) -> List(cast_state.Struck) {
  [
    cast_state.Hit(
      unit_id: ally,
      unit: cast_state.HitOtherPlayer(heals:),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
  ]
}

/// A Health heal row of Mind Over Body's formula, aimed as given, behind this condition.
fn health_row(
  id id: Int,
  aim aim: spell_plan.Aim,
  condition condition: spell_plan.Condition,
) -> spell_plan.Heal {
  support.heal_row(
    id:,
    vital: effect_kind.Health,
    aim:,
    delay_ms: 0,
    condition:,
    formula: support.mind_over_body_formula(),
  )
}

/// The caster of 500 health of 736 and 400 Support Rating at level 5 (Mind Over Body's
/// formula gives it 121, `cast_heal_test`), who sees the ally.
fn healing_ally_in_sight() -> Caster {
  cast_state.Caster(
    ..support.healing_caster(health: 500),
    players_in_sight: sight(players: [ally]),
  )
}

/// A press of a planted Targeted spell of these heal rows at `target`, whose go is answered
/// with the round given: the press's effects and those of the go.
fn healer_pressed_at(
  rows rows: List(spell_plan.Heal),
  target target: Int,
  struck struck: List(cast_state.Struck),
) -> #(List(Effect), List(Effect)) {
  let spell =
    support.with_effects(
      spell: targeted(spell4_id: 5001, base: 3, cooldown_ms: 0),
      kinds: list.map(rows, spell_plan.HealEffect),
    )
  let plans = support.with_spells(plans: plans(), spells: [spell])
  let caster = healing_ally_in_sight()
  let #(state, pressed) =
    pressed(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_3,
      target:,
      at: 1000,
    )
  let #(_, answered) =
    support.answered_each(
      caster:,
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
    )
  #(pressed, answered)
}

/// One go at an ally whose heals were answered: the rows the spell holds, what the ally
/// answered, and what the go lists on the ally and on the caster and how many heals it
/// carries for the caster.
type Listing {
  Listing(
    why: String,
    rows: List(spell_plan.Heal),
    answered: List(strike_tell.HealLanded),
    on_ally: List(#(Int, spell_effect_result.SpellEffectResult)),
    on_caster: List(#(Int, spell_effect_result.SpellEffectResult)),
    caster_heals: Int,
  )
}

pub fn a_go_lists_each_heal_the_ally_answered_with_the_answers_own_split_in_the_answers_order_test() -> Nil {
  use <- owned_test.run(5000)
  let primary = spell_plan.AimsAtPrimaryTarget
  let health = effect_kind.Health
  list.each(
    [
      Listing(
        why: "one health row answered with 77 of which 50 rose: the go lists the answer's 77 and 27 overheal, not the 121 the caster's own formula gives (round(0.3281 x 400) + 17.51 x 5 = 121), and heals the caster of nothing (Design: what the target applied is authoritative)",
        rows: [
          health_row(id: 62_019, aim: primary, condition: spell_plan.Always),
        ],
        answered: [
          landed(
            effect_id: 62_019,
            vital: health,
            split: heal_split.Split(
              amount: 77,
              shield: 0,
              health: 50,
              overheal: 27,
            ),
          ),
        ],
        on_ally: [
          #(
            62_019,
            support.heal_result(
              amount: 77,
              kind: damage_type.Heal,
              overkill: 27,
            ),
          ),
        ],
        on_caster: [],
        caster_heals: 0,
      ),
      Listing(
        why: "an ally at full health took none of 121: the overheal is the whole amount, which the client logs as nOverheal (`spell.heal_result_log`)",
        rows: [
          health_row(id: 62_019, aim: primary, condition: spell_plan.Always),
        ],
        answered: [
          landed(
            effect_id: 62_019,
            vital: health,
            split: heal_split.Split(
              amount: 121,
              shield: 0,
              health: 0,
              overheal: 121,
            ),
          ),
        ],
        on_ally: [
          #(
            62_019,
            support.heal_result(
              amount: 121,
              kind: damage_type.Heal,
              overkill: 121,
            ),
          ),
        ],
        on_caster: [],
        caster_heals: 0,
      ),
      Listing(
        why: "a shield row and a health row answered in that order are listed in that order, the shield one as HealShields (5) and the health one as Heal (4), each with its own overheal",
        rows: [
          support.heal_row(
            id: 70_001,
            vital: effect_kind.Shield,
            aim: primary,
            delay_ms: 0,
            condition: spell_plan.Always,
            formula: support.mind_over_body_formula(),
          ),
          health_row(id: 70_002, aim: primary, condition: spell_plan.Always),
        ],
        answered: [
          landed(
            effect_id: 70_001,
            vital: effect_kind.Shield,
            split: heal_split.Split(
              amount: 56,
              shield: 50,
              health: 0,
              overheal: 6,
            ),
          ),
          landed(
            effect_id: 70_002,
            vital: health,
            split: heal_split.Split(
              amount: 121,
              shield: 0,
              health: 100,
              overheal: 21,
            ),
          ),
        ],
        on_ally: [
          #(
            70_001,
            support.heal_result(
              amount: 56,
              kind: damage_type.HealShields,
              overkill: 6,
            ),
          ),
          #(
            70_002,
            support.heal_result(
              amount: 121,
              kind: damage_type.Heal,
              overkill: 21,
            ),
          ),
        ],
        on_caster: [],
        caster_heals: 0,
      ),
      Listing(
        why: "a row aimed at the caster and the ally (targetFlags 3): the caster's entry is worked out from the caster's own stats and vitals (121, with no overheal in 236 of room) and carried for the caster once, and the ally's entry is the answer's, which the caster's change does not reach",
        rows: [
          health_row(
            id: 62_019,
            aim: spell_plan.AimsAtCasterAndPrimaryTarget,
            condition: spell_plan.Always,
          ),
        ],
        answered: [
          landed(
            effect_id: 62_019,
            vital: health,
            split: heal_split.Split(
              amount: 121,
              shield: 0,
              health: 100,
              overheal: 21,
            ),
          ),
        ],
        on_ally: [
          #(
            62_019,
            support.heal_result(
              amount: 121,
              kind: damage_type.Heal,
              overkill: 21,
            ),
          ),
        ],
        on_caster: [
          #(
            62_019,
            support.heal_result(
              amount: 121,
              kind: damage_type.Heal,
              overkill: 0,
            ),
          ),
        ],
        caster_heals: 1,
      ),
    ],
    fn(row) {
      let #(pressed, went) =
        healer_pressed_at(
          rows: row.rows,
          target: ally,
          struck: ally_answered(heals: row.answered),
        )
      assert support.listed_on(effects: went, unit_id: ally) == row.on_ally
        as row.why
      assert support.listed_on(
          effects: went,
          unit_id: healing_ally_in_sight().unit_id,
        )
        == row.on_caster
        as { row.why <> ": the caster's entry" }
      assert list.length(
          support.caster_change_starts(effects: list.append(pressed, went)),
        )
        == row.caster_heals
        as { row.why <> ": the heals carried for the caster" }
    },
  )
}

pub fn a_go_lists_the_heals_the_ally_answered_and_no_others_whatever_the_casters_gates_say_at_the_go_test() -> Nil {
  use <- owned_test.run(5000)
  // Mind Over Body's tier 5 (Spell4 54900) holds two heal rows at the primary target:
  // 130852 behind Prerequisite 36008 (type 50, comparison 2: the caster is not under Spell4
  // 77237) and 130899 behind 36007 (comparison 1: it is) (`table_rows -- Spell4Effects
  // 130852 130899`). The caster holds nothing of 77237 when the go is written, though it
  // held it when the strike gated, so row 130852 passes here and row 130899 fails.
  let primary = spell_plan.AimsAtPrimaryTarget
  let under =
    prerequisite_support.single(id: 36_007, condition: #(50, 1, 0, 77_237))
  let not_under =
    prerequisite_support.single(id: 36_008, condition: #(50, 2, 0, 77_237))
  let rows = [
    health_row(
      id: 130_852,
      aim: primary,
      condition: spell_plan.GatedOnCaster(gates: [not_under]),
    ),
    health_row(
      id: 130_899,
      aim: primary,
      condition: spell_plan.GatedOnCaster(gates: [under]),
    ),
  ]
  let heal_of_row = fn(effect_id) {
    landed(
      effect_id:,
      vital: effect_kind.Health,
      split: heal_split.Split(amount: 121, shield: 0, health: 100, overheal: 21),
    )
  }
  list.each(
    [
      #(
        "the answer holds 130899 only: it is listed though its gate fails now, and 130852 is not though its gate passes now",
        ally,
        [heal_of_row(130_899)],
        [130_899],
        0,
      ),
      #(
        "the answer holds 130852 only: it is listed, and 130899 is not though its gate passed when the strike gated it",
        ally,
        [heal_of_row(130_852)],
        [130_852],
        0,
      ),
      #(
        "no ally and no answer (the caster presses at itself): the go keeps its gates, so 130852 alone lands on the caster, once",
        7,
        [],
        [130_852],
        1,
      ),
    ],
    fn(row) {
      let #(why, target, answered, listed, caster_heals) = row
      let #(pressed, went) =
        healer_pressed_at(rows:, target:, struck: case target == ally {
          True -> ally_answered(heals: answered)
          False -> []
        })
      assert list.map(
          support.listed_on(effects: went, unit_id: target),
          fn(entry) { entry.0 },
        )
        == listed
        as why
      assert list.length(
          support.caster_change_starts(effects: list.append(pressed, went)),
        )
        == caster_heals
        as { why <> ": the heals carried for the caster" }
    },
  )
  // A row aimed at the caster and the ally keeps its caster gate at the go, which gates the
  // caster's part, so when that gate fails now the whole row is left out and the ally's heal,
  // which the ally applied, is unlisted (the gap `cast_heal.gaps` states).
  let flips =
    health_row(
      id: 130_899,
      aim: spell_plan.AimsAtCasterAndPrimaryTarget,
      condition: spell_plan.GatedOnCaster(gates: [under]),
    )
  let #(pressed, went) =
    healer_pressed_at(
      rows: [flips],
      target: ally,
      struck: ally_answered(heals: [heal_of_row(130_899)]),
    )
  assert support.listed_effect_ids(effects: went) == []
    && support.caster_change_starts(effects: list.append(pressed, went)) == []
    as "a row aimed at the caster and the ally whose caster gate fails at the go is left out whole, though the ally applied its heal"
}

// ---- the kind of the spell ----

/// What a press comes to.
type Outcome {
  StartsOn(unit_id: Int)
  Refused(result: Int)
}

/// One press at a unit: the ability in the bag, the unit named, the players in sight, the
/// outcome, and the source of the outcome.
type Press {
  Press(
    why: String,
    ability: Spell,
    named: Int,
    sees: List(Int),
    outcome: Outcome,
  )
}

/// Mind Over Body with the targeting of a Spell4TargetMechanics row and a valid-targets
/// bitmask the fixture holds no ability for.
fn mind_over_body_with(flags flags: Int, valid_targets valid: Int) -> Spell {
  Spell(
    ..mind_over_body(),
    targeting: Targeting(
      kind: Targeted,
      mechanics_flags: flags,
      valid_targets: valid,
    ),
  )
}

pub fn a_bag_press_takes_its_primary_target_by_the_kind_of_its_spell_test() -> Nil {
  use <- owned_test.run(5000)
  let mind_over_body = mind_over_body()
  list.each(
    [
      Press(
        "opcode.0x9a: Telekinetic Strike is a Caster kind (row 6, targetType 2), so the client sends the caster itself whoever is named",
        ability(base: telekinetic_strike_base),
        ally,
        [ally],
        StartsOn(caster_unit),
      ),
      Press(
        "opcode.0x9d.target_checks: a Targeted spell with no target is refused 91",
        mind_over_body,
        0,
        [ally],
        Refused(91),
      ),
      Press(
        "a Targeted spell at a unit the picture does not show is refused 91",
        mind_over_body,
        stranger,
        [ally],
        Refused(91),
      ),
      Press(
        "a Targeted spell at a player the connection has no viewer for is refused 91: the picture alone holds no address to tell",
        mind_over_body,
        ally,
        [],
        Refused(91),
      ),
      Press(
        "Spell4TargetMechanics row 4: flags 11 hold the value 2, so Mind Over Body may be cast at the caster itself, and it starts on the caster",
        mind_over_body,
        caster_unit,
        [ally],
        StartsOn(caster_unit),
      ),
      Press(
        "Spell4TargetMechanics row 5: flags 9 lack the value 2, so a press at the caster itself is refused 32 (the caster as its own primary target)",
        mind_over_body_with(flags: 9, valid_targets: 0),
        caster_unit,
        [ally],
        Refused(32),
      ),
      Press(
        "a beneficial Targeted spell at another player in sight starts with that player as the primary target",
        mind_over_body,
        ally,
        [ally],
        StartsOn(ally),
      ),
      Press(
        "Spell4TargetMechanics row 3: flags 16 are not beneficial (Spatial Shift), and a hostile cast at a player is the PvP the server does not build, so it is refused 285",
        mind_over_body_with(flags: 16, valid_targets: 0),
        ally,
        [ally],
        Refused(285),
      ),
      Press(
        "Spell4ValidTargets row 9: bitmask 1 refuses a player, so the press is refused 102 (before the faction test)",
        mind_over_body_with(flags: 11, valid_targets: 1),
        ally,
        [ally],
        Refused(102),
      ),
      Press(
        "a Targeted spell at a creature the picture shows is unchanged: the primary target stays the caster",
        mind_over_body,
        creature,
        [ally],
        StartsOn(caster_unit),
      ),
    ],
    fn(row) {
      let plans =
        dict.insert(plans(), row.ability.spell4_base_id.value, row.ability)
      let bag_index = case
        row.ability.spell4_base_id.value == telekinetic_strike_base
      {
        True -> 1
        False -> 0
      }
      let #(state, pressed) =
        pressed(
          plans:,
          state: cast_state.new(),
          caster: esper_seeing(players: row.sees),
          bag_index:,
          target: row.named,
          at: 1000,
        )
      case row.outcome {
        StartsOn(unit_id:) -> {
          assert support.refusal_results(effects: pressed) == [] as row.why
          assert confirmed_at(effects: pressed) == [unit_id] as row.why
          assert list.all(started_at(effects: pressed), fn(target) {
            target == unit_id
          })
            as row.why
          assert dict.size(state.casts) == 1 as row.why
        }
        Refused(result:) -> {
          assert refused_as(effects: pressed) == [#(9, result)] as row.why
          assert started_at(effects: pressed) == [] as row.why
          assert dict.size(state.casts) == 0 as row.why
        }
      }
    },
  )
}

pub fn a_hostile_press_at_another_player_is_refused_as_not_built_and_logged_once_test() -> Nil {
  use <- owned_test.run(5000)
  let hostile = mind_over_body_with(flags: 16, valid_targets: 0)
  let plans = dict.insert(plans(), mind_over_body_base, hostile)
  let caster = esper_seeing(players: [ally])
  let #(state, first) =
    pressed(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: 0,
      target: ally,
      at: 1000,
    )
  let #(_, second) =
    pressed(plans:, state:, caster:, bag_index: 0, target: ally, at: 2000)
  assert list.length(
      list.filter(support.logs(effects: first), fn(log) { log.0 == LogWarning }),
    )
    == 1
    as "the first refusal is logged once for the spell"
  assert support.logs(effects: second) == []
    as "the second press of the spell is refused again and not logged again"
  assert refused_as(effects: first) == [#(9, 285)]
    && refused_as(effects: second) == [#(9, 285)]
    as "each press is refused 285"
}

// ---- the held key ----

pub fn a_held_key_down_at_another_player_starts_each_cast_at_that_player_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.with_spells(plans: plans(), spells: [
      targeted(spell4_id: 5001, base: 3, cooldown_ms: 2000),
    ])
  let caster = seeing(players: [ally])
  let #(state, down) =
    key_at(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_3,
      target: ally,
      held: 1,
      at: 1000,
    )
  assert started_at(effects: down) == [ally]
    as "opcode.0x4db: the first cast of the hold starts with the ally the key-down named as its primary target"
  assert confirmed_at(effects: down) == []
    as "a held key's cast is not confirmed: the server mints its cast id and writes no 0x7fd"
  let #(state, answered) =
    support.answered_as(
      caster:,
      state:,
      effects: down,
      at: 1000,
      struck: [],
      rolls: [],
    )
  let assert [#(repeat, 2000)] = support.started_timers(effects: answered)
    as "the spell's cooldown of 2000 ms is the one timer the hold waits on"
  let #(_, repeated) =
    support.fired_raw_as(caster:, state:, timer: repeat, at: 3000)
  assert started_at(effects: repeated) == [ally]
    as "cast.hold_repeat: the repeat presses at the same ally"
  let #(held, refused) =
    key_at(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_3,
      target: stranger,
      held: 1,
      at: 1000,
    )
  assert refused_as(effects: refused) == [#(0, 91)]
    && started_at(effects: refused) == []
    as "a key-down naming a unit the picture does not show is refused 91 with the client cast id 0"
  assert option.is_none(held.holding)
    as "cast.hold_stop: the refused key starts no hold"
  let #(held_at_none, refused_at_none) =
    key_at(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_3,
      target: 0,
      held: 1,
      at: 1000,
    )
  assert refused_as(effects: refused_at_none) == [#(0, 91)]
    && started_at(effects: refused_at_none) == []
    as "opcode.0x4db: the client sends a key-down with target 0 without a check of its own, and the server refuses it 91 as the client refuses a 0x9a with no target (CheckCast 0x1403ae8c0)"
  assert option.is_none(held_at_none.holding)
    as "cast.hold_stop: a key-down at no target starts no hold"
}

// ---- a repeat whose target left ----

/// A way the hold's next cast is reached.
type Reach {
  Reach(why: String, cooldown_ms: Int, by: Way)
}

type Way {
  ByTheRepeatTimer
  ByTheAnswerOfTheGo
}

/// The effects of the first go `effects` ask, answered once as a round that struck nobody. A
/// press the answer makes asks its own go, which stays unanswered: a rule that wrongly
/// accepts a repeat with no cooldown shows as a second start, where answering every go
/// would press again without end.
fn first_go_answered(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert [cast_state.Strike(asked:), ..] =
    list.filter(effects, fn(effect) {
      case effect {
        cast_state.Strike(..) -> True
        _ -> False
      }
    })
    as "the key-down asked a go"
  cast.went(
    cast: state,
    caster:,
    now: support.at(ms:),
    cast_id: asked.cast_id,
    phase: asked.phase,
    spell: Error(Nil),
    struck: [],
    poses: dict.new(),
    indexes: dict.new(),
    units: dict.new(),
    rolls: [],
    gates_passed: dict.new(),
  )
}

pub fn a_repeat_whose_target_left_sight_is_refused_91_and_ends_the_hold_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      Reach(
        "the cooldown's repeat timer: the caster has lost the ally when the timer fires",
        2000,
        ByTheRepeatTimer,
      ),
      Reach(
        "the answer of the go (cast.went runs continued): a spell with no cooldown presses again as the answer closes the cast, and the ally is gone",
        0,
        ByTheAnswerOfTheGo,
      ),
    ],
    fn(row) {
      let plans =
        support.with_spells(plans: plans(), spells: [
          targeted(spell4_id: 5001, base: 3, cooldown_ms: row.cooldown_ms),
        ])
      let seen = seeing(players: [ally])
      let gone = seeing(players: [])
      let #(state, down) =
        key_at(
          plans:,
          state: cast_state.new(),
          caster: seen,
          bag_index: bag_of_base_3,
          target: ally,
          held: 1,
          at: 1000,
        )
      let #(state, reached) = case row.by {
        ByTheRepeatTimer -> {
          let #(state, answered) =
            support.answered_as(
              caster: seen,
              state:,
              effects: down,
              at: 1000,
              struck: [],
              rolls: [],
            )
          let assert [#(repeat, _)] = support.started_timers(effects: answered)
            as row.why
          support.fired_raw_as(caster: gone, state:, timer: repeat, at: 3000)
        }
        ByTheAnswerOfTheGo ->
          first_go_answered(caster: gone, state:, effects: down, at: 1000)
      }
      assert refused_as(effects: reached) == [#(0, 91)] as row.why
      assert started_at(effects: reached) == [] as row.why
      assert option.is_none(state.holding) as row.why
    },
  )
}

// ---- a queued press ----

pub fn a_queued_press_is_judged_by_its_target_when_it_is_released_test() -> Nil {
  use <- owned_test.run(5000)
  let blocker =
    Spell(
      ..support.child(spell4_id: 5002, base: 2),
      cast_time_ms: 1000,
      cast_bar: spell_plan.ShowsCastBar,
    )
  let plans =
    support.with_spells(plans: plans(), spells: [
      blocker,
      targeted(spell4_id: 5001, base: 3, cooldown_ms: 0),
    ])
  list.each(
    [
      #(
        "the ally is still in sight when the cast clears: the held press starts on it",
        [ally],
        [ally],
        [],
      ),
      #(
        "the ally has left sight when the cast clears: the held press is refused 91 with the client's cast id",
        [],
        [],
        [#(9, 91)],
      ),
    ],
    fn(row) {
      let #(why, at_release, started, refused) = row
      let seen = seeing(players: [ally])
      // The blocker starts at 1000 and its go, which clears the current cast, is at 2000.
      let #(state, blocking) =
        pressed(
          plans:,
          state: cast_state.new(),
          caster: seen,
          bag_index: bag_of_base_2,
          target: 0,
          at: 1000,
        )
      let assert [#(go, 1000)] = support.started_timers(effects: blocking)
        as why
      let #(state, held) =
        pressed(
          plans:,
          state:,
          caster: seen,
          bag_index: bag_of_base_3,
          target: ally,
          at: 1600,
        )
      assert support.writes(effects: held) == []
        as "a press with 500 ms or less of the current cast left is held and writes nothing (cast.press_queue)"
      let at_release = seeing(players: at_release)
      let #(state, fired) =
        support.fired_raw_as(caster: at_release, state:, timer: go, at: 2000)
      let #(_, released) =
        support.answered_as(
          caster: at_release,
          state:,
          effects: fired,
          at: 2000,
          struck: [],
          rolls: [],
        )
      assert confirmed_at(effects: released) == started as why
      assert refused_as(effects: released) == refused as why
    },
  )
}

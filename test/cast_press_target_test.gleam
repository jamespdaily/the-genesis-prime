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
import genesis_prime/client_connection.{CastTicked}
import genesis_prime/game/activate
import genesis_prime/game/cast
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/effect_kind
import genesis_prime/game/faction_level
import genesis_prime/game/heal_split
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/player_state.{type PlayerState, PlayerState}
import genesis_prime/game/spell_plan.{type Plans, type Spell, Spell}
import genesis_prime/game/spend
import genesis_prime/game/strike_tell
import genesis_prime/game/target_mechanic.{Targeted, Targeting}
import genesis_prime/game/ticking.{Schedule, Ticks}
import genesis_prime/message/cast_result
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription,
}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_effect_tick.{
  type SpellEffectTick, SpellEffectTick,
}
import genesis_prime/message/spell_finished
import genesis_prime/step.{ConnectionId, LogWarning}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import map_support
import owned_test
import player_state_support
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

/// A player in sight at the defaults: alive, out of combat, Friendly, 10 m east.
fn an_ally() -> PlayerState {
  player_state_support.beside_the_caster(east: 10.0, up: 0.0)
}

/// The default caster, who sees these players, each at the defaults (`an_ally`).
fn seeing(players players: List(Int)) -> Caster {
  seeing_states(
    players: list.map(players, fn(unit_id) { #(unit_id, an_ally()) }),
  )
}

/// The default caster, who sees these players in these states.
fn seeing_states(players players: List(#(Int, PlayerState))) -> Caster {
  cast_state.Caster(
    ..support.caster(),
    players_in_sight: sight(players: list.map(players, fn(entry) { entry.0 })),
    other_players: dict.from_list(players),
  )
}

/// The Esper with Mind Over Body at bag index 0 and Telekinetic Strike at 1, holding the
/// Focus Mind Over Body costs (22, `Spell4 32820`), who sees these players at the defaults.
fn esper_seeing(players players: List(Int)) -> Caster {
  esper_of(caster: seeing(players:))
}

/// The same Esper, who sees these players in these states.
fn esper_seeing_states(players players: List(#(Int, PlayerState))) -> Caster {
  esper_of(caster: seeing_states(players:))
}

fn esper_of(caster caster: Caster) -> Caster {
  let bag = [
    Spell4BaseId(mind_over_body_base),
    Spell4BaseId(telekinetic_strike_base),
  ]
  cast_state.Caster(
    ..caster,
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
    target_death: mind_over_body().target_death,
    target_aim: mind_over_body().target_aim,
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
    other_players: dict.from_list([#(ally, an_ally())]),
  )
}

/// A press of a planted Targeted spell of these heal rows at `target`, whose go is answered
/// with the round given: the press's effects and those of the go.
fn healer_pressed_at(
  rows rows: List(spell_plan.Heal),
  target target: Int,
  struck struck: List(cast_state.Struck),
) -> #(List(Effect), List(Effect)) {
  let #(_, pressed, went) =
    healer_scene(rows:, at_go: healing_ally_in_sight(), target:, struck:)
  #(pressed, went)
}

/// The same, with the state the go leaves and the caster the go is written for, who may
/// have lost sight of the target since the press (the press is the caster who sees the ally).
fn healer_scene(
  rows rows: List(spell_plan.Heal),
  at_go at_go: Caster,
  target target: Int,
  struck struck: List(cast_state.Struck),
) -> #(State, List(Effect), List(Effect)) {
  let spell =
    support.with_effects(
      spell: targeted(spell4_id: 5001, base: 3, cooldown_ms: 0),
      kinds: list.map(rows, spell_plan.HealEffect),
    )
  let plans = support.with_spells(plans: plans(), spells: [spell])
  let #(state, pressed) =
    pressed(
      plans:,
      state: cast_state.new(),
      caster: healing_ally_in_sight(),
      bag_index: bag_of_base_3,
      target:,
      at: 1000,
    )
  let #(state, answered) =
    support.answered_each(
      caster: at_go,
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
    )
  #(state, pressed, answered)
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
  // A row aimed at the caster and the area (targetFlags 5) whose area found two allies, pressed
  // with no named target (the caster is its own target). The caster's part is its own, worked
  // out from its stats; each ally's is its answer's, in the answers' order, and an ally whose
  // answer was PlayerDead has no entry in the round. The row's target gate (a prerequisite the
  // allies fail now) is not checked for an ally that answered: the strike gated the row for
  // it once.
  let other_ally = 42
  let heal_of = fn(amount, health, overheal) {
    landed(
      effect_id: 62_019,
      vital: effect_kind.Health,
      split: heal_split.Split(amount:, shield: 0, health:, overheal:),
    )
  }
  let answered_by = fn(unit_id, heals) {
    cast_state.Hit(
      unit_id:,
      unit: cast_state.HitOtherPlayer(heals:),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    )
  }
  let not_held =
    prerequisite_support.single(id: 36_007, condition: #(50, 1, 0, 77_237))
  let area_rows = fn(condition) {
    [
      health_row(id: 62_019, aim: spell_plan.AimsAtCasterAndArea, condition:),
    ]
  }
  let caster_entry = [
    #(
      62_019,
      support.heal_result(amount: 121, kind: damage_type.Heal, overkill: 0),
    ),
  ]
  list.each(
    [
      #(
        "two allies answered: each is listed with its answer's split, in the answers' order, and the caster's own heal is carried once",
        area_rows(spell_plan.Always),
        [
          answered_by(ally, [heal_of(77, 50, 27)]),
          answered_by(other_ally, [heal_of(121, 100, 21)]),
        ],
        [
          #(
            62_019,
            support.heal_result(
              amount: 77,
              kind: damage_type.Heal,
              overkill: 27,
            ),
          ),
        ],
        [
          #(
            62_019,
            support.heal_result(
              amount: 121,
              kind: damage_type.Heal,
              overkill: 21,
            ),
          ),
        ],
        caster_entry,
      ),
      #(
        "the second ally answered PlayerDead, which the round does not hold: only the first is listed",
        area_rows(spell_plan.Always),
        [answered_by(ally, [heal_of(77, 50, 27)])],
        [
          #(
            62_019,
            support.heal_result(
              amount: 77,
              kind: damage_type.Heal,
              overkill: 27,
            ),
          ),
        ],
        [],
        caster_entry,
      ),
      #(
        "an ally the area selected only to start a child on is answered with no heal (a Proxy selected it, no row reached it): it is listed nowhere and gets no heal, gate or roll at the go, and the ally a heal reached is listed as before",
        area_rows(spell_plan.GatedOnTarget(prerequisite: not_held)),
        [
          answered_by(ally, [heal_of(77, 50, 27)]),
          answered_by(other_ally, []),
        ],
        [
          #(
            62_019,
            support.heal_result(
              amount: 77,
              kind: damage_type.Heal,
              overkill: 27,
            ),
          ),
        ],
        [],
        [],
      ),
      #(
        "a target gate the allies fail now is not checked for the answered allies: both are listed, and the caster, whom it gates, is not healed",
        area_rows(spell_plan.GatedOnTarget(prerequisite: not_held)),
        [
          answered_by(ally, [heal_of(77, 50, 27)]),
          answered_by(other_ally, [heal_of(121, 100, 21)]),
        ],
        [
          #(
            62_019,
            support.heal_result(
              amount: 77,
              kind: damage_type.Heal,
              overkill: 27,
            ),
          ),
        ],
        [
          #(
            62_019,
            support.heal_result(
              amount: 121,
              kind: damage_type.Heal,
              overkill: 21,
            ),
          ),
        ],
        [],
      ),
    ],
    fn(row) {
      let #(why, rows, struck, on_ally, on_other_ally, on_caster) = row
      let #(pressed, went) =
        healer_pressed_at(
          rows:,
          target: healing_ally_in_sight().unit_id,
          struck:,
        )
      assert support.listed_on(effects: went, unit_id: ally) == on_ally as why
      assert support.listed_on(effects: went, unit_id: other_ally)
        == on_other_ally
        as why
      // The answer is the unit's: the go draws no roll and checks no gate for it, so the one
      // line it writes for a unit that landed nothing is that the heal lands nothing here.
      assert list.count(support.debug_lines(effects: went), fn(line) {
          string.contains(line, "the unit " <> int.to_string(other_ally))
        })
        <= 1
        as { why <> ": at most the line that a heal lands nothing on the unit" }
      assert !list.any(support.debug_lines(effects: went), fn(line) {
        string.contains(line, "36007")
      })
        as { why <> ": no gate of the row is checked for an answered unit" }
      assert support.listed_on(
          effects: went,
          unit_id: healing_ally_in_sight().unit_id,
        )
        == on_caster
        as { why <> ": the caster's entry" }
      assert list.length(
          support.caster_change_starts(effects: list.append(pressed, went)),
        )
        == list.length(on_caster)
        as { why <> ": the heals carried for the caster" }
    },
  )
  // A row aimed at the area alone (targetFlags 4), pressed with no named target, whose area
  // took the caster as a candidate: the strike gated the row for the caster and let it through
  // (`HitCaster`), so the go lists the caster's heal once, worked out from its own stats and
  // vitals, and carries it for the caster, whatever its gates say at the go. The allies it took
  // are listed by their answers, and the row's target gate (which fails the caster now) is not
  // checked again.
  let caster_took =
    cast_state.Hit(
      unit_id: 7,
      unit: cast_state.HitCaster(heals: [Spell4EffectsId(62_019)]),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    )
  let ally_took = answered_by(ally, [heal_of(77, 50, 27)])
  let ally_entry = [
    #(
      62_019,
      support.heal_result(amount: 77, kind: damage_type.Heal, overkill: 27),
    ),
  ]
  let at_the_area_alone = fn(condition) {
    [health_row(id: 62_019, aim: spell_plan.AimsAtArea, condition:)]
  }
  list.each(
    [
      #(
        "the strike took the caster alone: the caster's heal is listed once and carried once, and no ally is listed",
        at_the_area_alone(spell_plan.Always),
        [caster_took],
        [],
        caster_entry,
      ),
      #(
        "the strike took the ally alone: the ally's answered heal is listed and the caster, not among the units, is not healed",
        at_the_area_alone(spell_plan.Always),
        [ally_took],
        ally_entry,
        [],
      ),
      #(
        "the strike took both: each is listed once, the caster's heal carried once",
        at_the_area_alone(spell_plan.Always),
        [caster_took, ally_took],
        ally_entry,
        caster_entry,
      ),
      #(
        "a target gate the caster fails now is not checked again for the caster the strike let through",
        at_the_area_alone(spell_plan.GatedOnTarget(prerequisite: not_held)),
        [caster_took],
        [],
        caster_entry,
      ),
    ],
    fn(row) {
      let #(why, rows, struck, on_ally, on_caster) = row
      let #(pressed, went) =
        healer_pressed_at(
          rows:,
          target: healing_ally_in_sight().unit_id,
          struck:,
        )
      assert support.listed_on(effects: went, unit_id: ally) == on_ally as why
      assert support.listed_on(
          effects: went,
          unit_id: healing_ally_in_sight().unit_id,
        )
        == on_caster
        as { why <> ": the caster's entry" }
      assert list.length(
          support.caster_change_starts(effects: list.append(pressed, went)),
        )
        == list.length(on_caster)
        as { why <> ": the heals carried for the caster" }
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

// ---- a periodic heal pressed at an ally ----

/// A periodic heal row of Bolster's shape (Spell4Effects 80077: type 10, targetFlags 2, no
/// delay, tickTime 1000, durationTime 8000, no prerequisite) cut to three ticks, aimed as
/// given and of this vital, with Mind Over Body's formula.
fn periodic_row(
  id id: Int,
  vital vital: effect_kind.Vital,
  aim aim: spell_plan.Aim,
  condition condition: spell_plan.Condition,
) -> spell_plan.Heal {
  spell_plan.TickingHeal(
    effect_id: Spell4EffectsId(id),
    vital:,
    phase_flags: -1,
    aim:,
    condition:,
    tag: spend.always,
    formula: support.mind_over_body_formula(),
    schedule: Schedule(
      delay_ms: 0,
      tick_ms: 1000,
      duration_ms: 3000,
      count: Ticks(3),
    ),
  )
}

/// The caster of the scenes, who has lost sight of every player.
fn blind() -> Caster {
  cast_state.Caster(
    ..healing_ally_in_sight(),
    players_in_sight: dict.new(),
    other_players: dict.new(),
  )
}

/// One go of a periodic heal and what it arms: the caster the go is written for, the unit
/// the press named, the ticks armed on the ally and on the caster, the units the go lists
/// with their rows, the delays of the timers it starts, and whether a debug line says a
/// heal lands nothing.
type Arming {
  Arming(
    why: String,
    rows: List(spell_plan.Heal),
    at_go: Caster,
    target: Int,
    ticks_on_ally: Int,
    ticks_on_caster: Int,
    listed: List(#(Int, List(Int))),
    delays: List(Int),
    lands_nothing_logged: Bool,
  )
}

pub fn a_periodic_heal_pressed_at_an_ally_ticks_on_the_ally_and_on_the_caster_only_where_its_aim_names_it_test() -> Nil {
  use <- owned_test.run(5000)
  let primary = spell_plan.AimsAtPrimaryTarget
  let health = effect_kind.Health
  let not_under =
    prerequisite_support.single(id: 36_007, condition: #(50, 1, 0, 77_237))
  list.each(
    [
      Arming(
        why: "the row at the primary target, the ally in sight: the go lists the row on the ally, arms its first tick 1000 ms on and ends its node at the row's 3000 ms (the cast's 0x7fe waits for it), and says nothing about a heal that lands nothing",
        rows: [
          periodic_row(
            id: 80_077,
            vital: health,
            aim: primary,
            condition: spell_plan.Always,
          ),
        ],
        at_go: healing_ally_in_sight(),
        target: ally,
        ticks_on_ally: 1,
        ticks_on_caster: 0,
        listed: [#(ally, [80_077])],
        delays: [1000, 3000],
        lands_nothing_logged: False,
      ),
      Arming(
        why: "the ally left the caster's sight between the press and the go: nothing is armed and the debug line says the row lands nothing (the control)",
        rows: [
          periodic_row(
            id: 80_077,
            vital: health,
            aim: primary,
            condition: spell_plan.Always,
          ),
        ],
        at_go: blind(),
        target: ally,
        ticks_on_ally: 0,
        ticks_on_caster: 0,
        listed: [],
        delays: [],
        lands_nothing_logged: True,
      ),
      Arming(
        why: "a row aimed at the caster and the primary target (targetFlags 3): two schedules, the ally's and the caster's own, and one node-end timer for the cast",
        rows: [
          periodic_row(
            id: 80_077,
            vital: health,
            aim: spell_plan.AimsAtCasterAndPrimaryTarget,
            condition: spell_plan.Always,
          ),
        ],
        at_go: healing_ally_in_sight(),
        target: ally,
        ticks_on_ally: 1,
        ticks_on_caster: 1,
        listed: [#(7, [80_077]), #(ally, [80_077])],
        delays: [1000, 1000, 3000],
        lands_nothing_logged: False,
      ),
      Arming(
        why: "the press at the caster itself: its own schedule alone (the control)",
        rows: [
          periodic_row(
            id: 80_077,
            vital: health,
            aim: primary,
            condition: spell_plan.Always,
          ),
        ],
        at_go: healing_ally_in_sight(),
        target: 7,
        ticks_on_ally: 0,
        ticks_on_caster: 1,
        listed: [#(7, [80_077])],
        delays: [1000, 3000],
        lands_nothing_logged: False,
      ),
      Arming(
        why: "the row's caster gate fails at the go (type 50, comparison 1: the caster is under Spell4 77237 and holds nothing of it): nobody is armed",
        rows: [
          periodic_row(
            id: 80_077,
            vital: health,
            aim: primary,
            condition: spell_plan.GatedOnCaster(gates: [not_under]),
          ),
        ],
        at_go: healing_ally_in_sight(),
        target: ally,
        ticks_on_ally: 0,
        ticks_on_caster: 0,
        listed: [],
        delays: [],
        lands_nothing_logged: False,
      ),
    ],
    fn(row) {
      let #(state, pressed, went) =
        healer_scene(
          rows: row.rows,
          at_go: row.at_go,
          target: row.target,
          struck: [],
        )
      assert support.tick_timers_on(state:, unit_id: ally) == row.ticks_on_ally
        as { row.why <> ": the ticks on the ally" }
      assert support.tick_timers_on(state:, unit_id: 7) == row.ticks_on_caster
        as { row.why <> ": the ticks on the caster" }
      assert list.sort(support.listed_by_unit(effects: went), fn(first, second) {
          int.compare(first.0, second.0)
        })
        == row.listed
        as { row.why <> ": the units the go lists" }
      assert list.sort(support.delays_of(effects: went), int.compare)
        == row.delays
        as { row.why <> ": the timers the go starts" }
      assert support.caster_change_starts(effects: list.append(pressed, went))
        == []
        as { row.why <> ": no heal is carried out at the go" }
      assert list.any(support.logs(effects: went), fn(line) {
          string.contains(line.1, "lands nothing here")
        })
        == row.lands_nothing_logged
        as { row.why <> ": the debug line of a heal that lands nothing" }
    },
  )
}

/// One periodic row pressed at the ally and run to its first tick (1000 ms after the go):
/// the state, the cast id and the effects of the tick's step.
fn first_tick_at_ally(row row: spell_plan.Heal) -> #(State, Int, List(Effect)) {
  let #(state, pressed, went) =
    healer_scene(
      rows: [row],
      at_go: healing_ally_in_sight(),
      target: ally,
      struck: [],
    )
  let #(state, fired) =
    support.run_timers_posed(
      caster: healing_ally_in_sight(),
      state:,
      effects: went,
      from_ms: 1000,
      struck_at: fn(_, _) { [] },
      poses: dict.new(),
      until_ms: Some(2000),
    )
  let assert [tick] = fired as "one timer is due by 2000 ms: the first tick"
  assert tick.at_ms == 2000 as "the first tick is 1000 ms after the go"
  #(state, support.pressed_id(effects: pressed), tick.effects)
}

/// The 0x7f8 the effects write, decoded.
fn ticks_written(effects effects: List(Effect)) -> List(SpellEffectTick) {
  support.frames_of(message_id: spell_effect_tick.message_id, effects:)
  |> list.map(fn(frame) {
    let assert Ok(tick) = spell_effect_tick.decode(frame.body)
    tick
  })
}

/// The viewers told a tick in the effects.
fn ticks_told(effects effects: List(Effect)) -> Int {
  list.count(support.tells(effects:), fn(tell) {
    case tell.1 {
      CastTicked(..) -> True
      _ -> False
    }
  })
}

/// The round of the tick the ally answered with these heals.
fn tick_answered(
  heals heals: List(strike_tell.HealLanded),
) -> option.Option(cast_state.Struck) {
  Some(
    cast_state.Hit(
      unit_id: ally,
      unit: cast_state.HitOtherPlayer(heals:),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
  )
}

/// The description the client reads of a heal of `kind` that took `amount` with `overkill`
/// over.
fn heal_described(
  amount amount: Int,
  overkill overkill: Int,
  kind kind: damage_type.DamageType,
) -> SpellDamageDescription {
  spell_damage_description.SpellDamageDescription(
    ..support.landed_damage(
      amount:,
      killed: 0,
      combat_result: combat_result.Hit,
      damage_type: kind,
    ),
    overkill:,
  )
}

/// A tick of the ally's heal as the cast asks for it and the answer of the ally.
type TickRow {
  TickRow(
    why: String,
    vital: effect_kind.Vital,
    answered: strike_tell.HealLanded,
    described: SpellDamageDescription,
  )
}

pub fn a_tick_on_an_ally_asks_for_it_and_the_0x7f8_lists_what_the_ally_applied_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      TickRow(
        why: "a health row answered with Split(77, 0, 50, 27): the 0x7f8 lists the answer's 77 and 27 overheal as a Heal (4), not the 121 the caster's own formula gives for the row",
        vital: effect_kind.Health,
        answered: landed(
          effect_id: 80_077,
          vital: effect_kind.Health,
          split: heal_split.Split(
            amount: 77,
            shield: 0,
            health: 50,
            overheal: 27,
          ),
        ),
        described: heal_described(
          amount: 77,
          overkill: 27,
          kind: damage_type.Heal,
        ),
      ),
      TickRow(
        why: "a full ally took none of 121: the whole amount is the overheal",
        vital: effect_kind.Health,
        answered: landed(
          effect_id: 80_077,
          vital: effect_kind.Health,
          split: heal_split.Split(
            amount: 121,
            shield: 0,
            health: 0,
            overheal: 121,
          ),
        ),
        described: heal_described(
          amount: 121,
          overkill: 121,
          kind: damage_type.Heal,
        ),
      ),
      TickRow(
        why: "a shield row (type 118) answered with a shield split: a HealShields (5) with the split's amount and overheal",
        vital: effect_kind.Shield,
        answered: landed(
          effect_id: 80_077,
          vital: effect_kind.Shield,
          split: heal_split.Split(
            amount: 56,
            shield: 50,
            health: 0,
            overheal: 6,
          ),
        ),
        described: heal_described(
          amount: 56,
          overkill: 6,
          kind: damage_type.HealShields,
        ),
      ),
    ],
    fn(row) {
      let heal =
        periodic_row(
          id: 80_077,
          vital: row.vital,
          aim: spell_plan.AimsAtPrimaryTarget,
          condition: spell_plan.Always,
        )
      let #(state, cast_id, tick) = first_tick_at_ally(row: heal)
      assert support.tick_strikes(effects: tick)
        == [
          cast_state.TickAsked(
            cast_id:,
            spell4_id: Spell4Id(5001),
            effect_id: Spell4EffectsId(80_077),
            unit_id: ally,
            life: 0,
            go: 1,
            tick: 1,
            what: cast_state.TellHeal(
              vital: row.vital,
              formula: support.mind_over_body_formula(),
              passed_in: None,
            ),
          ),
        ]
        as {
          row.why
          <> ": the tick asks for the ally with the row's vital and formula"
        }
      assert ticks_written(effects: tick) == []
        && support.caster_change_starts(effects: tick) == []
        as {
          row.why <> ": nothing is written or healed before the ally answers"
        }
      assert support.delays_of(effects: tick) == [1000]
        as { row.why <> ": the next tick is armed" }
      let assert [asked] = support.tick_strikes(effects: tick)
      let #(_, closed) =
        cast.ticked(
          cast: state,
          caster: healing_ally_in_sight(),
          now: support.at(ms: 2000),
          asked:,
          struck: tick_answered(heals: [row.answered]),
        )
      assert ticks_written(effects: closed)
        == [
          SpellEffectTick(
            cast_id:,
            spell4_effects_id: 80_077,
            unit_id: ally,
            descriptions: [row.described],
          ),
        ]
        as { row.why <> ": one 0x7f8 to the caster naming the ally" }
      assert ticks_told(effects: closed) == 2
        as { row.why <> ": and told to each viewer of the cast" }
      assert support.caster_change_starts(effects: closed) == []
        as { row.why <> ": the caster is healed of nothing" }
    },
  )
}

pub fn a_heal_tick_with_no_answer_ends_the_ally_ticks_and_its_node_like_a_creatures_test() -> Nil {
  use <- owned_test.run(5000)
  let heal =
    periodic_row(
      id: 80_077,
      vital: effect_kind.Health,
      aim: spell_plan.AimsAtPrimaryTarget,
      condition: spell_plan.Always,
    )
  let #(state, _, tick) = first_tick_at_ally(row: heal)
  let assert [asked] = support.tick_strikes(effects: tick)
  let #(left_out, closed) =
    cast.ticked(
      cast: state,
      caster: healing_ally_in_sight(),
      now: support.at(ms: 3000),
      asked:,
      struck: None,
    )
  assert list.map(support.writes(effects: closed), fn(frame) {
      frame.message_id
    })
    == [spell_finished.message_id]
    as "a tick with no answer writes no 0x7f8, and the node it held ends with the cast's 0x7fe in that step, as for a creature"
  assert support.tick_timers_on(state: left_out, unit_id: ally) == 0
    as "the ally's later ticks are cancelled"
  assert list.length(support.cancelled_timers(effects: closed)) == 2
    as "the next tick's timer and the node's end"
  // The ally the client stopped showing (its 0x355): its node and next tick are dropped,
  // and the tick whose round closes afterwards writes nothing.
  let #(removed, _) =
    cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 2100)
  assert support.tick_timers_on(state: removed, unit_id: ally) == 0
    as "a removed ally's next tick is dropped"
  let #(_, late) =
    cast.ticked(
      cast: removed,
      caster: healing_ally_in_sight(),
      now: support.at(ms: 2200),
      asked:,
      struck: tick_answered(heals: [
        landed(
          effect_id: 80_077,
          vital: effect_kind.Health,
          split: heal_split.Split(
            amount: 77,
            shield: 0,
            health: 50,
            overheal: 27,
          ),
        ),
      ]),
    )
  assert support.writes(effects: late) == [] && ticks_told(effects: late) == 0
    as "the tick whose round closes after the removal writes and tells nothing"
  // Bolster tier 9 (Spell4 52142) holds the heal row 123122 and the Proxy 229005 that casts
  // Spell4 87531, each ticking every 1000 ms (`table_rows -- Spell4Effects 123122 229005`). The
  // ally who answers no heal tick takes the cast's node with it, and the Proxy row of the same
  // cast ticks on that node, so it goes with it (`tick.ticks_dropped`: every path that drops
  // a node calls it): the child of tick 2 starts in the step that asks the heal, before the
  // missing answer, and no later tick starts one.
  let bolster =
    Spell(
      ..spell_tables.client_spell(spell4_id: 52_142),
      spell4_base_id: Spell4BaseId(3),
    )
  let caster =
    cast_state.Caster(
      ..esper_seeing(players: [ally]),
      abilities: support.caster().abilities,
      book: support.caster().book,
    )
  let #(state, pressed) =
    pressed(
      plans: support.with_spells(plans: plans(), spells: [bolster]),
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_3,
      target: ally,
      at: 1000,
    )
  let #(state, went) =
    support.answered_each(
      caster:,
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { [] },
      rolls: [],
      poses: dict.new(),
    )
  let #(state, fired) =
    support.run_timers_posed(
      caster:,
      state:,
      effects: went,
      from_ms: 1000,
      struck_at: fn(_, _) { [] },
      poses: dict.new(),
      until_ms: Some(3000),
    )
  assert support.tick_timers_on(state:, unit_id: ally) == 2
    as "both rows of Bolster tick on the ally"
  let assert Ok(second) = list.last(fired) as "the second tick has fired"
  let assert [asked] = support.tick_strikes(effects: second.effects)
    as "the second tick asks the ally for its heal"
  let #(state, closed) =
    cast.ticked(
      cast: state,
      caster:,
      now: support.at(ms: 3000),
      asked:,
      struck: None,
    )
  assert support.tick_timers(state:) == 0
    as "the heal tick's missing answer drops the Proxy row's timer with the heal row's"
  assert list.length(
      list.filter(
        list.append(
          list.flat_map(fired, fn(step) {
            support.started_in(effects: step.effects)
          }),
          support.started_in(effects: closed),
        ),
        fn(start) { start.spell4_id == 87_531 },
      ),
    )
    == 2
    as "the child started at ticks 1 and 2 and none after the answer"
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
        "Spell4TargetMechanics row 3: flags 16 (Spatial Shift) lack flag 3, so a cast at a Friendly player is refused 99 (0x1403ad540), as a hostile spell at an ally",
        mind_over_body_with(flags: 16, valid_targets: 0),
        ally,
        [ally],
        Refused(99),
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
  // The client tests the spell's valid targets (102) after the caster's own checks
  // (`0x1403b2240` after `CheckCastCaster`): a press of a spell that refuses a player, made
  // during the global cooldown, is the cooldown's result.
  let refusing =
    support.with_spells(plans: plans(), spells: [
      Spell(
        ..support.child(spell4_id: 5002, base: 2),
        global_cooldown: spell_plan.GlobalCooldown(
          refused_while_running: True,
          starts_for_ms: Some(1000),
        ),
      ),
      Spell(
        ..targeted(spell4_id: 5001, base: 3, cooldown_ms: 0),
        targeting: Targeting(
          kind: Targeted,
          mechanics_flags: 11,
          valid_targets: 1,
        ),
        global_cooldown: spell_plan.GlobalCooldown(
          refused_while_running: True,
          starts_for_ms: None,
        ),
      ),
    ])
  let caster = seeing(players: [ally])
  let #(state, _) =
    pressed(
      plans: refusing,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 1000,
    )
  let #(_, during) =
    pressed(
      plans: refusing,
      state:,
      caster:,
      bag_index: bag_of_base_3,
      target: ally,
      at: 1100,
    )
  assert refused_as(effects: during) == [#(9, 14)]
    as "a global cooldown of 1000 ms started at 1000 refuses the press 14, not 102"
}

pub fn a_hostile_press_at_another_player_is_refused_by_the_factions_test() -> Nil {
  use <- owned_test.run(5000)
  let other_faction =
    PlayerState(..an_ally(), disposition: faction_level.Hostile)
  list.each(
    [
      #(
        "flags 16 (flag 4 only) at the same faction: 0x1403ad540 refuses a Friendly target without flag 3, 99",
        16,
        an_ally(),
        99,
      ),
      #(
        "flags 16 at the other faction: the first pass lets flag 4 through and nobody is flagged, 322 (0x1403b4560)",
        16,
        other_faction,
        322,
      ),
      #(
        "flags 17 (flags 0 and 4) at the other faction: 322",
        17,
        other_faction,
        322,
      ),
      #("flags 17 at the same faction: 99", 17, an_ally(), 99),
    ],
    fn(row) {
      let #(why, flags, target, result) = row
      let plans =
        dict.insert(
          plans(),
          mind_over_body_base,
          mind_over_body_with(flags:, valid_targets: 0),
        )
      let caster = esper_seeing_states(players: [#(ally, target)])
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
      assert refused_as(effects: first) == [#(9, result)]
        && refused_as(effects: second) == [#(9, result)]
        as why
      assert support.logs(effects: first) == []
        && support.logs(effects: second) == []
        as "a refusal the server judged is not logged as not built"
    },
  )
}

// ---- the state the connection pictures of the target ----

/// What a press at the ally comes to.
type Judged {
  StartsOnTheAlly
  RefusedWith(result: Int)
}

/// A press (a 0x9a with the client cast id 9, or a 0x4db key down) of Mind Over Body at the
/// ally, who is in the state given.
type Pictured {
  Pictured(why: String, ally: PlayerState, judged: Judged)
}

pub fn a_bag_press_at_another_player_is_refused_by_the_state_the_connection_pictures_of_it_test() -> Nil {
  use <- owned_test.run(5000)
  let hostile = faction_level.Hostile
  list.each(
    [
      Pictured(
        "the control row: a live ally in range of the same faction, not flagged, starts the cast",
        an_ally(),
        StartsOnTheAlly,
      ),
      Pictured(
        "0x1403b2240: Mind Over Body's conditions (value 0) refuse a dead ally 106",
        PlayerState(..an_ally(), alive: False),
        RefusedWith(106),
      ),
      Pictured(
        "an ally 40 m away (edge to edge 37.6, beyond the 35 m maximum and the server's 2 m allowance) is refused 105",
        player_state_support.beside_the_caster(east: 40.0, up: 0.0),
        RefusedWith(105),
      ),
      Pictured(
        "an ally 37 m away (edge to edge 34.6) starts the cast",
        player_state_support.beside_the_caster(east: 37.0, up: 0.0),
        StartsOnTheAlly,
      ),
      Pictured(
        "an ally of the other faction is refused 99 (0x1403ad540: Mind Over Body lacks flag 4), before its life and range are tested",
        PlayerState(
          ..player_state_support.beside_the_caster(east: 60.0, up: 0.0),
          alive: False,
          disposition: hostile,
        ),
        RefusedWith(99),
      ),
    ],
    fn(row) {
      let caster = esper_seeing_states(players: [#(ally, row.ally)])
      let #(state, pressed) =
        pressed(
          plans: plans(),
          state: cast_state.new(),
          caster:,
          bag_index: 0,
          target: ally,
          at: 1000,
        )
      let #(held, key_down) =
        key_at(
          plans: plans(),
          state: cast_state.new(),
          caster:,
          bag_index: 0,
          target: ally,
          held: 1,
          at: 1000,
        )
      case row.judged {
        StartsOnTheAlly -> {
          assert confirmed_at(effects: pressed) == [ally] as row.why
          assert started_at(effects: key_down) == [ally] as row.why
        }
        RefusedWith(result:) -> {
          assert refused_as(effects: pressed) == [#(9, result)] as row.why
          assert state == cast_state.new()
            as "a refused press starts no cast and no cooldown"
          assert refused_as(effects: key_down) == [#(0, result)]
            as "opcode.0x4db: the key down has no client check, so the 0x7fc answers it, with the client cast id 0"
          assert option.is_none(held.holding) && held == cast_state.new()
            as "a refused key down starts no hold"
          assert support.logs(effects: pressed) == []
            && support.logs(effects: key_down) == []
            as "a refusal the server judged is not logged as not built"
        }
      }
    },
  )
  // The caster's own checks come first (`CheckCast` `0x1403ae8c0`): the target block is
  // reached only when the caster passes or the answer is 317, queued. The spell of base 3 is
  // judged as Mind Over Body is; the spell of base 2 starts a global cooldown of 1000 ms.
  let dead_ally = [#(ally, PlayerState(..an_ally(), alive: False))]
  let caster = seeing_states(players: dead_ally)
  let cooldown_plans =
    support.with_spells(plans: plans(), spells: [
      Spell(
        ..support.child(spell4_id: 5002, base: 2),
        global_cooldown: spell_plan.GlobalCooldown(
          refused_while_running: True,
          starts_for_ms: Some(1000),
        ),
      ),
      Spell(
        ..targeted(spell4_id: 5001, base: 3, cooldown_ms: 0),
        global_cooldown: spell_plan.GlobalCooldown(
          refused_while_running: True,
          starts_for_ms: None,
        ),
      ),
    ])
  let #(after_blocker, _) =
    pressed(
      plans: cooldown_plans,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 1000,
    )
  let at_the_dead_ally = fn(state, caster, ms) {
    pressed(
      plans: cooldown_plans,
      state:,
      caster:,
      bag_index: bag_of_base_3,
      target: ally,
      at: ms,
    )
  }
  let #(_, during_cooldown) = at_the_dead_ally(after_blocker, caster, 1100)
  assert refused_as(effects: during_cooldown) == [#(9, 14)]
    as "a global cooldown with more than 500 ms left is 14, not the dead ally's 106"
  let #(_, dead_caster) =
    at_the_dead_ally(
      cast_state.new(),
      cast_state.Caster(..caster, dead: True),
      1000,
    )
  assert refused_as(effects: dead_caster) == [#(9, 57)]
    as "a dead caster is refused with its own result, not the ally's"
  let #(queued, within_window) = at_the_dead_ally(after_blocker, caster, 1700)
  assert refused_as(effects: within_window) == [#(9, 106)]
    as "a cooldown with 500 ms or less left queues the press (317), and the client goes on to the target checks: 106 at once"
  assert option.is_none(queued.held)
    as "the refused press is not held for the cooldown"
  // A press of a spell the server does not build the target rows of is refused 285 and
  // logged once for the spell.
  let unread =
    Spell(
      ..mind_over_body(),
      target_aim: spell_plan.TargetAim(
        ..mind_over_body().target_aim,
        unread: Some("a target vital requirement"),
      ),
    )
  let unread_plans = dict.insert(plans(), mind_over_body_base, unread)
  let seen = esper_seeing(players: [ally])
  let #(state, first) =
    pressed(
      plans: unread_plans,
      state: cast_state.new(),
      caster: seen,
      bag_index: 0,
      target: ally,
      at: 1000,
    )
  let #(_, second) =
    pressed(
      plans: unread_plans,
      state:,
      caster: seen,
      bag_index: 0,
      target: ally,
      at: 2000,
    )
  assert refused_as(effects: first) == [#(9, 285)]
    && refused_as(effects: second) == [#(9, 285)]
    as "each press of a spell with an unread target row is refused 285"
  assert list.length(
      list.filter(support.logs(effects: first), fn(log) { log.0 == LogWarning }),
    )
    == 1
    as "the first refusal is logged once for the spell"
  assert support.logs(effects: second) == [] as "and not again"
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

/// A way the hold's next cast is reached, with the caster's picture when it is and the
/// result the repeat is refused with.
type Reach {
  Reach(why: String, cooldown_ms: Int, by: Way, later: Caster, result: Int)
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
  let dead = PlayerState(..an_ally(), alive: False)
  let far = player_state_support.beside_the_caster(east: 60.0, up: 0.0)
  list.each(
    [
      Reach(
        "the cooldown's repeat timer: the caster has lost the ally when the timer fires",
        2000,
        ByTheRepeatTimer,
        seeing(players: []),
        91,
      ),
      Reach(
        "the answer of the go (cast.went runs continued): a spell with no cooldown presses again as the answer closes the cast, and the ally is gone",
        0,
        ByTheAnswerOfTheGo,
        seeing(players: []),
        91,
      ),
      Reach(
        "the ally died between the two presses: the repeat is judged by the picture of the input that releases it, 106",
        2000,
        ByTheRepeatTimer,
        seeing_states(players: [#(ally, dead)]),
        106,
      ),
      Reach(
        "the ally walked 60 m away between the two presses: the repeat is refused 105",
        2000,
        ByTheRepeatTimer,
        seeing_states(players: [#(ally, far)]),
        105,
      ),
    ],
    fn(row) {
      let plans =
        support.with_spells(plans: plans(), spells: [
          targeted(spell4_id: 5001, base: 3, cooldown_ms: row.cooldown_ms),
        ])
      let seen = seeing(players: [ally])
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
          support.fired_raw_as(
            caster: row.later,
            state:,
            timer: repeat,
            at: 3000,
          )
        }
        ByTheAnswerOfTheGo ->
          first_go_answered(caster: row.later, state:, effects: down, at: 1000)
      }
      assert refused_as(effects: reached) == [#(0, row.result)] as row.why
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
  let far = player_state_support.beside_the_caster(east: 60.0, up: 0.0)
  list.each(
    [
      #(
        "the ally is still in sight when the cast clears: the held press starts on it",
        seeing(players: [ally]),
        [ally],
        [],
      ),
      #(
        "the ally has left sight when the cast clears: the held press is refused 91 with the client's cast id",
        seeing(players: []),
        [],
        [#(9, 91)],
      ),
      #(
        "the ally walked 60 m away while the press waited: the release is refused 105 with the client's cast id",
        seeing_states(players: [#(ally, far)]),
        [],
        [#(9, 105)],
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

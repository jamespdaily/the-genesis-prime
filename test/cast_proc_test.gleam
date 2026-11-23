//// The cast rule's procs (`genesis_prime/game/cast` `State.procs`, `settled`, `died`,
//// `combat_left`): a Proc effect a cast holds on the caster casts its spell at the caster
//// when its trigger happens. The Stalker's passive is the client's own, from the real
//// plans where the client is present; every other holder is planted by hand
//// (`cast_support.child` with a Proc row), on a clock the test drives. Expected values come
//// from these places:
//// - `Spell4Effects.effectType.14.dataBits00.217_218`: the passive 45057 holds Proc 147119
////   (kind 217, enters stealth) casting 60724, 147132 (218, leaves stealth) casting 60769 and
////   211002 (218) casting 79932; `.dataBits00.0_44`: 159136 (kind 44, leaves combat) and 202043
////   (kind 0, dies) cast 63366, whose one effect 159134 is a ModifySpellCooldown that sets the
////   cooldown group 182, the Stealth button's, to 250 ms (`Spell4Effects.effectType.73`).
//// - `Spell4.79932`: Empower, four UnitPropertyModifier rows for 3000 ms on the caster:
////   210998 BaseCritChance (UnitProperty2 102) x1.0 + 0.2 and 212528 to 212530
////   DamageDealtMultiplier (141 to 143) x1.08.
//// - `Spell4Effects.effectType.14.limits`: at most dataBits05 fires in dataBits04 ms.
//// - `Spell4.spell4ConditionsIdCaster` with `cast.dead_player`: Spell4Conditions row 1 (mask 225)
////   refuses a dead caster, row 4 (mask 0) does not; 60724, 60769 and 79932 hold row 1, 63366 row 4.
//// - `opcode.0x7ff.root_parent`: a non-zero parent marks a cast no press made, with no 0x7fd.
//// - `Spell4Effects.effectType.14.lifetime`: a Proc with no durationTime and flags bit 2 lasts
////   until removed; a durationTime gives the caster's node that life.
//// - The server's choices, in the rule's doc and the design of the step (section 5): procs are
////   matched once at the end of each input, after its own work; a proc's own event comes before
////   the stealth change; each fire is under its limit, which a fire at exactly the window's end
////   leaves free; a dead holder's refused fire records none; a camp drops the procs; a death
////   leaves the passive's.
//// Skipped where the client's tables are not on the machine, but for the tests that plant the
//// holder.

import cast_support as support
import character_support
import client_tables
import crowd_control_support
import genesis_prime/client_connection
import genesis_prime/game/cast
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/class_resource
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/hit
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/movement
import genesis_prime/game/proc as event_proc
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{
  type Plans, type ProcRow, type Spell, AliveOrDead, Always, AnySpell, AtHolder,
  BrokenByDamage, Died, EnteredStealth, InWindow, KeepsStealth, KeptOnDamage,
  LeftCombat, LeftStealth, ProcRow, RemoveStealthRow, Spell,
}
import genesis_prime/game/spend
import genesis_prime/game/strike_tell
import genesis_prime/game/ticking
import genesis_prime/game/unit_properties
import genesis_prime/message/cast_result
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_state
import genesis_prime/message/damage_type
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/step.{type Now, type TimerId, ConnectionId, LogDebug}
import genesis_prime/table/id.{
  type Spell4BaseId, Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import place_support
import prerequisite_support
import unitest

// ---- the Stalker, from the client's tables ----

/// A Stalker: its three level-1 abilities (Shred, Impale, Stagger) and its innate, Nano
/// Skin: Lethal, at bag index 3.
fn stalker(in_combat in_combat: Bool) -> Caster {
  cast_state.Caster(
    ..support.caster(),
    abilities: list.map([23_148, 23_161, 23_173, 30_075], Spell4BaseId),
    in_combat:,
  )
}

fn dead(caster caster: Caster) -> Caster {
  cast_state.Caster(..caster, dead: True)
}

fn answered(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
) -> #(State, List(Effect)) {
  support.answered_as(caster:, state:, effects:, at: ms, struck: [], rolls: [])
}

/// The Stalker's passive started at the time, its go answered with no unit struck.
fn joined(caster caster: Caster, at ms: Int) -> #(State, List(Effect)) {
  let #(state, effects) =
    passive_started(
      cast: cast_state.new(),
      caster:,
      plans: support.real_plans(),
      base: Spell4BaseId(29_131),
      now: support.at(ms:),
    )
  answered(caster:, state:, effects:, at: ms)
}

/// A press of the Stalker's innate, Nano Skin: Lethal, with its goes answered.
fn toggled(
  state state: State,
  caster caster: Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.press_as(plans: support.real_plans(), state:, caster:, bag: 3, at: ms)
}

/// A press of the Stalker's first ability, Shred, with its goes answered.
fn shredded(
  state state: State,
  caster caster: Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.press_as(plans: support.real_plans(), state:, caster:, bag: 0, at: ms)
}

// ---- the inputs, each followed by the pass that matches the procs ----

fn then_procs(
  step step: #(State, List(Effect)),
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  support.then_procs(step:, caster:, at: now.monotonic_ms)
}

fn passive_started(
  cast cast: State,
  caster caster: Caster,
  plans plans: Plans,
  base base: Spell4BaseId,
  now now: Now,
) -> #(State, List(Effect)) {
  cast.passive_started(cast:, caster:, plans:, base:, now:)
  |> then_procs(caster:, now:)
}

fn died(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  cast.died(cast:, caster:, now:) |> then_procs(caster:, now:)
}

fn combat_left(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  cast.combat_left(cast:, caster:, now:) |> then_procs(caster:, now:)
}

fn blow_taken(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  blow blow: cast_proc.BlowTaken,
) -> #(State, List(Effect)) {
  cast.blow_taken(cast:, caster:, now:, blow:) |> then_procs(caster:, now:)
}

/// The attack spell of the creature that strikes, as its blow's events carry it.
fn attack(groups groups: List(Int)) -> event_proc.EventSpell {
  event_proc.EventSpell(spell4_id: Spell4Id(5649), groups:, school: 1)
}

/// A blow of creature 31 that landed with these results, by an attack spell of no group.
fn landed(
  lowered lowered: Bool,
  critical critical: Bool,
  shield_depleted shield_depleted: Bool,
) -> cast_proc.BlowTaken {
  cast_proc.BlowLanded(
    striker: 31,
    spell: attack(groups: []),
    lowered:,
    critical:,
    shield_depleted:,
  )
}

/// A blow of creature 31 that lowered the holder's health and was nothing else.
fn lowering() -> cast_proc.BlowTaken {
  landed(lowered: True, critical: False, shield_depleted: False)
}

fn persisted(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  cast.persisted(cast:, caster:, now:) |> then_procs(caster:, now:)
}

// ---- reading what a step did ----

/// The casts the effects start with a 0x7ff, and a press the effects confirm with a 0x7fd
/// (the spell `pressed` names), as (cast id, Spell4 id).
fn casts_of(
  effects effects: List(Effect),
  pressed pressed: Int,
) -> List(#(Int, Int)) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id {
      0x07FF -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "a 0x7ff the rule wrote decodes"
        Ok(#(start.cast_id, start.spell4_id))
      }
      0x07FD -> {
        let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
          as "a 0x7fd the rule wrote decodes"
        Ok(#(confirmed.server_cast_id, pressed))
      }
      _ -> Error(Nil)
    }
  })
}

/// What the steps wrote and decided that matters here, in order, one line each: a cast's
/// start (`start 60724`, a 0x7ff or the press's 0x7fd), its go, its end, a node taken off the
/// caster and the stealth change. A cast is named by its Spell4 id, found among the
/// effects of `earlier` steps and these.
fn trace(
  effects effects: List(Effect),
  earlier earlier: List(List(Effect)),
  pressed pressed: Int,
) -> List(String) {
  let known =
    list.flat_map([effects, ..earlier], fn(step) {
      casts_of(effects: step, pressed:)
    })
    |> dict.from_list
  let named = fn(cast_id) {
    case dict.get(known, cast_id) {
      Ok(spell4_id) -> int.to_string(spell4_id)
      Error(Nil) -> "cast " <> int.to_string(cast_id)
    }
  }
  list.flat_map(effects, fn(effect) {
    case effect {
      cast_state.Send(frame:) ->
        case frame.message_id {
          0x07FF -> {
            let assert Ok(start) = spell_started.decode(frame.body)
              as "a 0x7ff the rule wrote decodes"
            ["start " <> int.to_string(start.spell4_id)]
          }
          0x07FD -> ["start " <> named(support.pressed_id(effects: [effect]))]
          0x07F4 -> {
            let assert Ok(go) = spell_go.decode(frame.body)
              as "a 0x7f4 the rule wrote decodes"
            ["go " <> named(go.cast_id)]
          }
          0x07FE -> ["end " <> named(support.finished_cast_id(frame))]
          0x0811 -> {
            let assert Ok(removed) = spell_targets_removed.decode(frame.body)
              as "a 0x811 the rule wrote decodes"
            ["off " <> named(removed.cast_id)]
          }
          _ -> []
        }
      cast_state.StealthChanged(stealthed: True) -> ["stealth on"]
      cast_state.StealthChanged(stealthed: False) -> ["stealth off"]
      cast_state.Tell(..)
      | cast_state.StartTimer(..)
      | cast_state.CancelTimer(..)
      | cast_state.Strike(..)
      | cast_state.TickStrike(..)
      | cast_state.FindProxyTickUnits(..)
      | cast_state.Log(..)
      | cast_state.Pay(..)
      | cast_state.Gain(..)
      | cast_state.CasterChangeStarts(..)
      | cast_state.CasterChangeEnds(..)
      | cast_state.OtherPlayerChangeStarts(..)
      | cast_state.OtherPlayerChangeEnds(..)
      | cast_state.TargetChangeStarts(..)
      | cast_state.TargetChangeEnds(..)
      | cast_state.ForcedMoveStarts(..)
      | cast_state.CreatureDespawns(..)
      | cast_state.CreatureHoldsUnitStates(..)
      | cast_state.CreatureControlsEnd(..)
      | cast_state.Activated(..)
      | cast_state.ShortcutCast(..)
      | cast_state.QuestAdvanced(..) -> []
    }
  })
}

/// The lines of a trace from the first one equal to `line` on, or none when it never comes.
fn from(lines lines: List(String), line line: String) -> List(String) {
  list.drop_while(lines, fn(found) { found != line })
}

/// The 0x7ff of the cast of `spell4_id` that the effects write, decoded.
fn started_of(
  spell4_id spell4_id: Int,
  effects effects: List(Effect),
) -> spell_started.SpellStarted {
  let assert Ok(start) =
    list.filter_map(support.frames_of(message_id: 0x07FF, effects:), fn(frame) {
      let assert Ok(start) = spell_started.decode(frame.body)
        as "a 0x7ff the rule wrote decodes"
      case start.spell4_id == spell4_id {
        True -> Ok(start)
        False -> Error(Nil)
      }
    })
    |> list.first
    as "the effects start a cast of the spell"
  start
}

/// The effect rows the goes of the effects list on the caster, unit 7, in order.
fn listed_on_the_caster(effects effects: List(Effect)) -> List(Int) {
  list.flat_map(support.goes_in(effects:), fn(go) {
    list.filter(go.targets, fn(target) { target.unit_id == 7 })
    |> list.flat_map(fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
  })
}

fn is_strike(effect effect: Effect) -> Bool {
  case effect {
    cast_state.Strike(..) -> True
    cast_state.Send(..)
    | cast_state.Tell(..)
    | cast_state.StartTimer(..)
    | cast_state.CancelTimer(..)
    | cast_state.Log(..)
    | cast_state.Pay(..)
    | cast_state.Gain(..)
    | cast_state.CasterChangeStarts(..)
    | cast_state.CasterChangeEnds(..)
    | cast_state.OtherPlayerChangeStarts(..)
    | cast_state.OtherPlayerChangeEnds(..)
    | cast_state.TargetChangeStarts(..)
    | cast_state.TargetChangeEnds(..)
    | cast_state.ForcedMoveStarts(..)
    | cast_state.CreatureDespawns(..)
    | cast_state.CreatureHoldsUnitStates(..)
    | cast_state.CreatureControlsEnd(..)
    | cast_state.Activated(..)
    | cast_state.ShortcutCast(..)
    | cast_state.QuestAdvanced(..)
    | cast_state.TickStrike(..)
    | cast_state.FindProxyTickUnits(..)
    | cast_state.StealthChanged(..) -> False
  }
}

/// How many casts of the Spell4 the effects start.
fn starts_of(spell4_id spell4_id: Int, effects effects: List(Effect)) -> Int {
  list.count(trace(effects:, earlier: [], pressed: 0), fn(line) {
    line == "start " <> int.to_string(spell4_id)
  })
}

// ---- the planted holder ----

/// A spell a proc casts: no cast time, no cooldown, and a caster of any life, as 63366's
/// row 4 holds, so a holder's death does not stop it.
fn cast_of_proc(spell4_id spell4_id: Int) -> Spell {
  Spell(
    ..support.child(spell4_id:, base: spell4_id),
    caster_death: AliveOrDead,
    target_death: AliveOrDead,
    stealth_change: KeepsStealth,
  )
}

/// A Proc row of this id as the Stalker's passive holds its rows (until removed, no gate, every
/// phase), with the trigger, the spell it casts and its limit.
fn proc(
  id id: Int,
  trigger trigger: spell_plan.Trigger,
  casts casts: Spell,
  window_ms window_ms: Int,
  count count: Int,
) -> ProcRow {
  ProcRow(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    trigger:,
    spell: casts,
    chance: 1.0,
    limit: InWindow(window_ms:, count:),
    filter: AnySpell,
    aim: AtHolder,
    event_gate: None,
    holder_gate: None,
    delay_ms: 0,
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition: Always,
    tag: spend.always,
  )
}

/// A spell that holds these procs and nothing else.
fn holding(spell4_id spell4_id: Int, procs procs: List(ProcRow)) -> Spell {
  support.with_effects(
    spell: Spell(
      ..support.child(spell4_id:, base: spell4_id),
      stealth_change: KeepsStealth,
    ),
    kinds: list.map(procs, spell_plan.ProcEffect),
  )
}

/// A caster of the planted plans: its bag holds the planted bases 1, 2 and 3 at 8, 10 and 11.
fn planted_caster() -> Caster {
  support.caster()
}

const bag_of_base_1 = 8

const bag_of_base_2 = 10

const bag_of_base_3 = 11

/// The passive `spell`, started at the time on a fresh state and answered.
fn planted_joined(
  plans plans: Plans,
  spell spell: Spell,
  at ms: Int,
) -> #(State, List(Effect)) {
  let caster = planted_caster()
  let #(state, effects) =
    passive_started(
      cast: cast_state.new(),
      caster:,
      plans:,
      base: spell.spell4_base_id,
      now: support.at(ms:),
    )
  answered(caster:, state:, effects:, at: ms)
}

fn planted_press(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.press_as(plans:, state:, caster: planted_caster(), bag:, at: ms)
}

/// The spell of base 1 that holds a stealth damage does not end, as 95774 does.
fn stealthing() -> Spell {
  support.with_effects(
    spell: Spell(
      ..support.child(spell4_id: 38_913, base: 1),
      stealth_change: KeepsStealth,
    ),
    kinds: [
      spell_plan.StealthEffect(support.stealth_row(
        id: 95_774,
        breaks: KeptOnDamage,
      )),
    ],
  )
}

// ---- what the passive's go lists ----

pub fn the_stalkers_passive_lists_its_five_proc_rows_on_the_caster_and_lingers_with_no_0x7fe_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(state, effects) = joined(caster: stalker(in_combat: False), at: 1000)
  assert listed_on_the_caster(effects:)
    == [147_119, 147_132, 159_136, 202_043, 211_002]
    as "Spell4Effects.effectType.14: the go lists each Proc row of the passive on its holder, in row order, as it lists any lasting effect"
  assert support.finished_ids(support.writes(effects:)) == []
    as "a Proc with no durationTime and flags bit 2 lasts until removed (.lifetime), so the passive's node lives and its cast lingers with no 0x7fe"
  assert list.map(support.started_timers(effects:), fn(timer) { timer.1 })
    == [50]
    as "no timer ends the node: only 147125's Proxy to 60724 waits its 50 ms"
  assert cast_state.stealthed(cast: state) == False
}

// ---- entering and leaving stealth ----

pub fn entering_stealth_by_the_innate_press_casts_60724_at_the_player_after_the_0x8f5_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, started) = joined(caster:, at: 1000)
  let #(entered, effects) = toggled(state:, caster:, at: 2000)
  let lines = trace(effects:, earlier: [started], pressed: 46_073)
  assert from(lines:, line: "stealth on")
    |> list.take(4)
    == ["stealth on", "start 60724", "go 60724", "end 60724"]
    as "Spell4Effects.effectType.14.dataBits00.217_218: the toggle's Stealth row ends its go, the 0x8f5 {P, 1} is told, then Proc 147119 casts 60724 and its go and finish follow"
  let start = started_of(spell4_id: 60_724, effects:)
  assert start.caster_unit_id == 7 && start.primary_target_unit_id == 7
    as "dataBits03 1: the cast is at the holder, the player"
  assert start.root_spell4_id == 45_057 && start.parent_spell4_id == 45_057
    as "opcode.0x7ff.root_parent: a cast no press made names the holder's spell as root and parent"
  assert support.frames_of(message_id: 0x07FD, effects:)
    |> list.length
    == 1
    as "only the press is confirmed with a 0x7fd: the proc's cast has none"
  let proc_start = started_of(spell4_id: 60_724, effects:)
  assert list.filter_map(support.tells(effects:), fn(told) {
      case told.1 == client_connection.CastStarted(start: proc_start) {
        True -> Ok(told.0)
        False -> Error(Nil)
      }
    })
    == [ConnectionId(2), ConnectionId(3)]
    as "each viewer is told the start of the proc's cast"
  let #(_, after) = shredded(state: entered, caster:, at: 2100)
  assert support.refusal_results(effects: after) == []
    as "the proc's cast starts no global cooldown (globalCooldownEnum 3, 0x14046afc0), so Shred 100 ms later is not refused 14"
}

/// The effect rows the go of the cast of `spell4_id` lists on the caster, unit 7.
fn listed_by(
  spell4_id spell4_id: Int,
  effects effects: List(Effect),
) -> List(Int) {
  let cast_id = started_of(spell4_id:, effects:).cast_id
  list.flat_map(
    support.frames_of(message_id: spell_go.message_id, effects:),
    fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      case go.cast_id == cast_id {
        True ->
          list.filter(go.targets, fn(target) { target.unit_id == 7 })
          |> list.flat_map(fn(target) {
            list.map(target.effects, fn(effect) { effect.spell4_effects_id })
          })
        False -> []
      }
    },
  )
}

fn modifier(
  property property: Int,
  mode mode: Int,
  multiplier multiplier: Float,
  flat flat: Float,
) -> unit_properties.Modifier {
  unit_properties.Change(
    property: UnitProperty2Id(property),
    mode:,
    multiplier:,
    flat:,
    per_level: 0.0,
  )
}

pub fn leaving_stealth_by_the_second_press_casts_60769_then_79932_and_empower_lasts_3_seconds_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, joined_effects) = joined(caster:, at: 1000)
  let #(state, entered) = toggled(state:, caster:, at: 2000)
  let #(state, effects) = toggled(state:, caster:, at: 3000)
  let lines =
    trace(effects:, earlier: [joined_effects, entered], pressed: 46_073)
  let before = list.take_while(lines, fn(line) { line != "stealth off" })
  assert list.contains(before, "off 38784")
    as "Spell4Effects 83832 of 38783 force-removes 38784: its node leaves the caster (0x811, which destroys a Normal cast: opcode.0x811)"
  assert from(lines:, line: "stealth off")
    |> list.take(6)
    == [
      "stealth off",
      "start 60769",
      "go 60769",
      "end 60769",
      "start 79932",
      "go 79932",
    ]
    as "the 0x8f5 {P, 0} comes after the removal, then Procs 147132 and 211002 cast 60769 and 79932 in row order; 79932's cast lingers for its 3000 ms, so it has no 0x7fe yet"
  assert list.sort(listed_by(spell4_id: 79_932, effects:), int.compare)
    == [210_998, 212_528, 212_529, 212_530]
    as "Spell4.79932: its four UnitPropertyModifier rows are listed on the caster"
  let starts =
    support.property_starts(effects:)
    |> list.map(fn(start) { start.1 })
    |> list.sort(fn(first, second) {
      int.compare(
        unit_properties.changed_property(modifier: first).value,
        unit_properties.changed_property(modifier: second).value,
      )
    })
  assert starts
    == [
      modifier(
        property: 102,
        mode: 3,
        multiplier: 1.0,
        flat: 0.20000000298023224,
      ),
      modifier(
        property: 141,
        mode: 1,
        multiplier: 1.0800000429153442,
        flat: 0.0,
      ),
      modifier(
        property: 142,
        mode: 1,
        multiplier: 1.0800000429153442,
        flat: 0.0,
      ),
      modifier(
        property: 143,
        mode: 1,
        multiplier: 1.0800000429153442,
        flat: 0.0,
      ),
    ]
    as "Spell4.79932: BaseCritChance 102 x1.0 + 0.2 (dataBits02 1065353216, dataBits03 1045220557) and DamageDealtMultiplier 141 to 143 x1.08 (dataBits02 1066024305), as 32-bit floats"
  let #(_, early) =
    support.run_timers_until(state:, effects:, from_ms: 3000, until_ms: 5999)
  assert list.all(early, fn(step) {
    support.caster_change_ends(effects: step.1) == []
  })
    as "nothing ends before the 3000 ms"
  let #(_, later) = support.run_timers(state:, effects:, from_ms: 3000)
  let ended =
    list.filter(later, fn(step) {
      support.caster_change_ends(effects: step.1) != []
    })
  assert list.unique(list.map(ended, fn(step) { step.0 })) == [6000]
    as "Spell4.79932: durationTime 3000 after the go at 3000"
  let ending = list.flat_map(ended, fn(step) { step.1 })
  assert list.map(support.caster_change_ends(effects: ending), fn(source) {
      source.effect_id.value
    })
    |> list.sort(int.compare)
    == [210_998, 212_528, 212_529, 212_530]
  let after = list.flat_map(later, fn(step) { step.1 })
  assert list.contains(
    trace(effects: after, earlier: [effects], pressed: 46_073),
    "end 79932",
  )
    as "and its cast ends with a 0x7fe"
}

pub fn leaving_stealth_by_an_attack_casts_the_procs_after_the_attacks_0x811_0x7fe_and_0x8f5_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, joined_effects) = joined(caster:, at: 1000)
  let #(state, entered) = toggled(state:, caster:, at: 2000)
  let #(_, effects) = shredded(state:, caster:, at: 3000)
  assert support.refusals(effects:) == [] as "the setup: Shred is accepted"
  let lines =
    trace(effects:, earlier: [joined_effects, entered], pressed: 38_765)
  let before = list.take_while(lines, fn(line) { line != "stealth off" })
  assert list.contains(before, "off 38784")
    as "Spell4.spellCastStealthChange.break: Shred ends the stealth after its go's effects (0x811)"
  assert list.any(before, fn(line) { string.starts_with(line, "end ") })
    as "Shred's own 0x7fe comes before the 0x8f5"
  assert from(lines:, line: "stealth off")
    |> list.take(4)
    == ["stealth off", "start 60769", "go 60769", "end 60769"]
    as "then the 0x8f5, and the procs of leaving stealth"
  assert starts_of(spell4_id: 79_932, effects:) == 1
}

pub fn leaving_stealth_by_damage_casts_the_procs_after_the_0x8f5_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, joined_effects) = joined(caster:, at: 1000)
  let #(state, entered) = toggled(state:, caster:, at: 2000)
  let #(state, struck) =
    blow_taken(
      cast: state,
      caster:,
      now: support.at(ms: 2500),
      blow: lowering(),
    )
  let #(_, effects) = answered(caster:, state:, effects: struck, at: 2500)
  assert trace(effects:, earlier: [joined_effects, entered], pressed: 0)
    == [
      "off 38784",
      "stealth off",
      "start 60769",
      "go 60769",
      "end 60769",
      "start 79932",
      "go 79932",
    ]
    as "Spell4Effects.effectType.83: dataBits02 0 of 83834 breaks the stealth on damage; the 0x811, the 0x8f5, then both procs"
}

pub fn a_cancel_that_ends_the_stealth_of_the_other_casts_fires_the_procs_for_leaving_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // A cast of value 1 that a 0x801 stops after one of its goes ends the other casts'
  // stealth as it stops (`Spell4.spellCastStealthChange.break`), so a leave-stealth event
  // can come from a cancel too.
  let two_goes =
    Spell(
      ..support.child(spell4_id: 38_779, base: 2),
      method: spell_plan.Multiphase,
      phase_delays_ms: [0, 500],
      stealth_change: spell_plan.EndsStealthAfterLastGo,
    )
  let left = cast_of_proc(spell4_id: 250_201)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(id: 1, trigger: LeftStealth, casts: left, window_ms: 500, count: 1),
    ])
  let plans = support.plans_of([stealthing(), two_goes, holder])
  let #(state, joined_effects) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, entered) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let caster = planted_caster()
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 2100,
    )
  let #(state, first) = answered(caster:, state:, effects: pressed, at: 2100)
  assert starts_of(spell4_id: 250_201, effects: first) == 0
    as "the first go ends nothing: the cast ends the stealth after its last"
  let assert Ok(#(state, cancelled)) =
    support.cancelled_in(
      plans:,
      state:,
      cast_id: support.pressed_id(effects: first),
      reason: cast_result.from_value(11),
      bit: 1,
      at: 2200,
    )
  let #(_, effects) = answered(caster:, state:, effects: cancelled, at: 2200)
  let lines =
    trace(effects:, earlier: [joined_effects, entered, first], pressed: 38_779)
  assert from(lines:, line: "stealth off")
    == ["stealth off", "start 250201", "go 250201", "end 250201"]
    as "the 0x801 ends the stealth as the cast stops, and the proc for leaving it is cast after the 0x8f5"
}

// ---- the limit ----

pub fn a_proc_fires_again_only_when_its_window_has_passed_a_fire_at_exactly_its_end_is_allowed_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Stalker's own press cannot show the edge: the Stealth cooldown the toggle sets is
  // 1000 ms, above the 500 ms windows, so the holder is planted with the rows' limits.
  let entered = cast_of_proc(spell4_id: 250_201)
  let left = cast_of_proc(spell4_id: 250_202)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(
        id: 1,
        trigger: EnteredStealth,
        casts: entered,
        window_ms: 500,
        count: 1,
      ),
      proc(id: 2, trigger: LeftStealth, casts: left, window_ms: 500, count: 1),
    ])
  let plans = support.plans_of([broken_by_damage_spell(), holder])
  let caster = planted_caster()
  let damaged = fn(state, at) {
    let #(state, effects) =
      blow_taken(
        cast: state,
        caster:,
        now: support.at(ms: at),
        blow: lowering(),
      )
    answered(caster:, state:, effects:, at:)
  }
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, first) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert starts_of(spell4_id: 250_201, effects: first) == 1
  let #(state, first_left) = damaged(state, 2100)
  assert starts_of(spell4_id: 250_202, effects: first_left) == 1
  let #(early, early_effects) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2499)
  assert starts_of(spell4_id: 250_201, effects: early_effects) == 0
    as "Spell4Effects.effectType.14.limits: the 217 proc fired at 2000 with dataBits04 500, so 499 ms later it is held back"
  assert cast_state.stealthed(cast: early) as "the stealth itself is entered"
  let #(_, on_time) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2500)
  assert starts_of(spell4_id: 250_201, effects: on_time) == 1
    as "500 ms after the fire it casts again: the server's choice of the edge"
  let #(_, held_back) = damaged(early, 2599)
  assert starts_of(spell4_id: 250_202, effects: held_back) == 0
    as "the 218 proc fired at 2100: held back 499 ms later"
  let #(_, free) = damaged(early, 2600)
  assert starts_of(spell4_id: 250_202, effects: free) == 1
    as "and free 500 ms after it"
}

fn broken_by_damage_spell() -> Spell {
  support.with_effects(
    spell: Spell(
      ..support.child(spell4_id: 38_914, base: 1),
      stealth_change: KeepsStealth,
    ),
    kinds: [
      spell_plan.StealthEffect(support.stealth_row(
        id: 83_834,
        breaks: BrokenByDamage,
      )),
    ],
  )
}

pub fn two_procs_of_one_trigger_each_keep_their_own_window_test() -> Nil {
  use <- owned_test.run(60_000)
  let short = cast_of_proc(spell4_id: 250_201)
  let long = cast_of_proc(spell4_id: 250_202)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(id: 1, trigger: LeftStealth, casts: short, window_ms: 500, count: 1),
      proc(id: 2, trigger: LeftStealth, casts: long, window_ms: 1000, count: 1),
    ])
  let plans = support.plans_of([broken_by_damage_spell(), holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let cycle = fn(state, at) {
    let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at:)
    let #(state, struck) =
      blow_taken(
        cast: state,
        caster:,
        now: support.at(ms: at + 100),
        blow: lowering(),
      )
    answered(caster:, state:, effects: struck, at: at + 100)
  }
  let #(state, first) = cycle(state, 2000)
  assert starts_of(spell4_id: 250_201, effects: first) == 1
  assert starts_of(spell4_id: 250_202, effects: first) == 1
  let #(_, second) = cycle(state, 2700)
  assert starts_of(spell4_id: 250_201, effects: second) == 1
    as "600 ms after its fire the 500 ms proc is free"
  assert starts_of(spell4_id: 250_202, effects: second) == 0
    as "and the 1000 ms proc, fired at the same time, still waits"
}

pub fn a_proc_with_a_count_above_1_fires_that_often_in_its_window_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.limits: 'Can occur $(eff=129693.data05rawInt) times every
  // $(eff=129693.data04ms)s'.
  let casts = cast_of_proc(spell4_id: 250_201)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(id: 1, trigger: LeftCombat, casts:, window_ms: 1000, count: 2),
    ])
  let plans = support.plans_of([holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 0)
  let leaves = fn(state, at) {
    let #(state, effects) =
      combat_left(cast: state, caster:, now: support.at(ms: at))
    let #(state, effects) = answered(caster:, state:, effects:, at:)
    #(state, starts_of(spell4_id: 250_201, effects:))
  }
  let #(state, first) = leaves(state, 1000)
  let #(state, second) = leaves(state, 1100)
  let #(state, third) = leaves(state, 1200)
  let #(state, fourth) = leaves(state, 2000)
  assert [first, second, third, fourth] == [1, 1, 0, 1]
    as "two fires fit in 1000 ms, the third is refused, and once the first is 1000 ms old a fire fits again"
  let #(_, fifth) = leaves(state, 2050)
  assert fifth == 0 as "the fires at 1100 and 2000 are in the window of 2050"
}

pub fn a_fire_draws_no_roll_and_a_held_proc_changes_no_go_rolls_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  // The passive's go applies the five procs; the stealth go of 38784 is the input that
  // fires 60724.
  let #(held, started) =
    passive_started(
      cast: cast_state.new(),
      caster:,
      plans: support.real_plans(),
      base: Spell4BaseId(29_131),
      now: support.at(ms: 1000),
    )
  let assert [cast_state.Strike(passive_go)] = list.filter(started, is_strike)
  assert cast_gate.rolls_needed(
      cast: held,
      caster: support.caster().unit_id,
      cast_id: passive_go.cast_id,
      phase: passive_go.phase,
      struck: [],
    )
    == 0
    as "Spell4Effects.effectType.14.limits: every read row has chance 1.0, so the go that applies the procs needs no roll"
  let #(held, _) = answered(caster:, state: held, effects: started, at: 1000)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: support.real_plans(),
      state: held,
      caster:,
      bag_index: 3,
      target: 0,
      at: 2000,
    )
  let assert [cast_state.Strike(toggle_go)] = list.filter(pressed, is_strike)
  let #(state, going) =
    support.went(
      cast: state,
      caster:,
      now: support.at(ms: 2000),
      cast_id: toggle_go.cast_id,
      phase: toggle_go.phase,
      struck: [],
    )
  let assert [cast_state.Strike(stealth_go)] = list.filter(going, is_strike)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: stealth_go.cast_id,
      phase: stealth_go.phase,
      struck: [],
    )
    == 0
    as "the go that enters stealth and fires 60724 takes no roll either"
  let #(_, effects) = answered(caster:, state:, effects: going, at: 2000)
  assert starts_of(spell4_id: 60_724, effects:) == 1
    as "the answer carries rolls: [], and the proc still fires"
}

pub fn a_procs_cast_names_the_player_as_its_primary_target_for_every_unit_bit_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, joined_effects) = joined(caster:, at: 1000)
  let #(entered, effects) = toggled(state:, caster:, at: 2000)
  assert started_of(spell4_id: 60_724, effects:).primary_target_unit_id == 7
    as "dataBits03 1 (Spell4Effects.effectType.14.dataBits03)"
  let #(state, dying) =
    died(cast: entered, caster: dead(caster:), now: support.at(ms: 3000))
  let #(_, after) =
    answered(caster: dead(caster:), state:, effects: dying, at: 3000)
  assert started_of(spell4_id: 63_366, effects: after).primary_target_unit_id
    == 7
    as "dataBits03 9 on 202043: the go names the player too"
  assert listed_by(spell4_id: 63_366, effects: after) == [159_134]
    as "63366's go lists 159134 on the player"
  assert joined_effects != []
}

// ---- a dead holder ----

pub fn a_lethal_blow_on_a_stealthed_stalker_casts_neither_218_proc_and_writes_a_debug_line_for_each_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, _) = joined(caster:, at: 1000)
  let #(state, _) = toggled(state:, caster:, at: 2000)
  let #(state, struck) =
    blow_taken(
      cast: state,
      caster: dead(caster:),
      now: support.at(ms: 2100),
      blow: lowering(),
    )
  let #(_, effects) =
    answered(caster: dead(caster:), state:, effects: struck, at: 2100)
  assert starts_of(spell4_id: 60_769, effects:) == 0
  assert starts_of(spell4_id: 79_932, effects:) == 0
    as "Spell4.spell4ConditionsIdCaster: row 1 (mask 225) refuses a dead caster, as the client refuses its press (cast.dead_player)"
  assert list.any(support.logs(effects:), fn(line) {
    line.0 == LogDebug
    && string.contains(line.1, "60769")
    && string.contains(line.1, "the Proc effect 147132")
  })
    as "each refused fire writes a debug line naming the spell and the row"
  assert list.any(support.logs(effects:), fn(line) {
    line.0 == LogDebug
    && string.contains(line.1, "79932")
    && string.contains(line.1, "211002")
  })
}

pub fn a_fire_a_dead_holder_was_refused_holds_back_no_later_fire_test() -> Nil {
  use <- owned_test.run(60_000)
  // The refused fire records no time, so the 500 ms window holds nothing back.
  let left = cast_of_proc(spell4_id: 250_202)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(id: 1, trigger: LeftStealth, casts: left, window_ms: 500, count: 1),
    ])
  let living = Spell(..left, caster_death: spell_plan.CannotBeDead)
  let holder =
    support.with_effects(
      spell: holder,
      kinds: list.map(
        list.map(
          spell_plan.payloads(spell: holder, as_kind: spell_plan.as_proc),
          fn(row) { ProcRow(..row, spell: living) },
        ),
        spell_plan.ProcEffect,
      ),
    )
  let plans = support.plans_of([broken_by_damage_spell(), holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let #(state, struck) =
    blow_taken(
      cast: state,
      caster: dead(caster:),
      now: support.at(ms: 2100),
      blow: lowering(),
    )
  let #(state, refused) =
    answered(caster: dead(caster:), state:, effects: struck, at: 2100)
  assert starts_of(spell4_id: 250_202, effects: refused) == 0
  let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at: 2200)
  let #(state, struck) =
    blow_taken(
      cast: state,
      caster:,
      now: support.at(ms: 2300),
      blow: lowering(),
    )
  let #(_, later) = answered(caster:, state:, effects: struck, at: 2300)
  assert starts_of(spell4_id: 250_202, effects: later) == 1
    as "200 ms after the refused fire the living caster's 218 proc fires"
}

// ---- death and combat left ----

/// The dead player's `died`, its casts' goes answered.
fn dies(
  state state: State,
  caster caster: Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  let dead = dead(caster:)
  let #(state, effects) = died(cast: state, caster: dead, now: support.at(ms:))
  answered(caster: dead, state:, effects:, at: ms)
}

pub fn death_casts_63366_after_the_casts_it_ends_and_cuts_the_stealth_cooldown_to_250_ms_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let in_combat = stalker(in_combat: True)
  let #(state, joined_effects) = joined(caster: in_combat, at: 500)
  let #(state, entered) = toggled(state:, caster: in_combat, at: 1000)
  let #(dead_state, effects) = dies(state:, caster: in_combat, at: 3000)
  let lines =
    trace(effects:, earlier: [joined_effects, entered], pressed: 46_073)
  let before =
    list.take_while(lines, fn(line) { !string.starts_with(line, "start ") })
  assert list.contains(before, "end 38784")
    as "the stealth cast's 0x7fe at the death"
  assert from(lines:, line: "stealth off")
    == ["stealth off", "start 63366", "go 63366", "end 63366"]
    as "Spell4Effects.effectType.14.dataBits00.0_44: 202043 casts 63366 after every cast's 0x7fe and the 0x8f5; 60769 and 79932 are refused for the dead caster"
  assert listed_by(spell4_id: 63_366, effects:) == [159_134]
  // The Stealth button was pressed in combat at 1000, so its cooldown (25000 ms) runs.
  // Spell4Effects.effectType.73: 159134 sets the cooldown group 182 to 250 ms, 150 ms
  // from the press below, which the rule holds as a press within the queue window.
  let woken = stalker(in_combat: False)
  let #(_, press) =
    support.pressed_raw_in(
      plans: support.real_plans(),
      state: dead_state,
      caster: woken,
      bag_index: 3,
      target: 0,
      at: 3100,
    )
  assert support.refusal_results(effects: press) == []
    as "the cooldown left is 150 ms, inside the 500 ms window the client queues"
  let #(without, _) =
    toggled(state: cast_state.new(), caster: in_combat, at: 1000)
  let #(without, _) =
    died(
      cast: without,
      caster: dead(caster: in_combat),
      now: support.at(ms: 3000),
    )
  let #(_, control) =
    support.pressed_raw_in(
      plans: support.real_plans(),
      state: without,
      caster: woken,
      bag_index: 3,
      target: 0,
      at: 3100,
    )
  assert support.refusal_results(effects: control) == [16]
    as "the control: a player who held no passive has 22 s of cooldown left, refused 16: the Stealth button's groups 182 and 248 run too, and an ability press meets the last result (0x1403b14c0)"
}

pub fn leaving_combat_casts_63366_once_a_second_and_cuts_the_stealth_cooldown_to_250_ms_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let in_combat = stalker(in_combat: True)
  let out = stalker(in_combat: False)
  let #(state, _) = joined(caster: in_combat, at: 500)
  let #(state, _) = toggled(state:, caster: in_combat, at: 1000)
  let #(_, before) =
    support.pressed_raw_in(
      plans: support.real_plans(),
      state:,
      caster: out,
      bag_index: 3,
      target: 0,
      at: 5100,
    )
  assert support.refusal_results(effects: before) == [16]
    as "the control: in combat the Stealth button's 25000 ms cooldown stands, and its group 182 with it, whose result 16 an ability press meets (0x1403b14c0)"
  let leaves = fn(state, at) {
    let #(state, effects) =
      combat_left(cast: state, caster: out, now: support.at(ms: at))
    answered(caster: out, state:, effects:, at:)
  }
  let #(state, first) = leaves(state, 5000)
  assert trace(effects: first, earlier: [], pressed: 0)
    == ["start 63366", "go 63366", "end 63366"]
    as "Spell4Effects.effectType.14.dataBits00.0_44: 159136, kind 44, casts 63366"
  let #(_, after) =
    support.pressed_raw_in(
      plans: support.real_plans(),
      state:,
      caster: out,
      bag_index: 3,
      target: 0,
      at: 5100,
    )
  assert support.refusal_results(effects: after) == []
    as "63366 sets the Stealth cooldown to 250 ms (Spell4Effects.effectType.73): 150 ms left at 5100 is held, not refused"
  let #(state, second) = leaves(state, 5999)
  assert starts_of(spell4_id: 63_366, effects: second) == 0
    as "dataBits04 1000: 999 ms after the fire it is held back"
  let #(_, third) = leaves(state, 6000)
  assert starts_of(spell4_id: 63_366, effects: third) == 1
    as "and 1000 ms after it casts again"
}

// ---- event order and matching ----

pub fn a_death_casts_the_died_proc_before_the_proc_for_the_stealth_it_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  let died_cast = cast_of_proc(spell4_id: 250_201)
  let left_cast = cast_of_proc(spell4_id: 250_202)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(
        id: 1,
        trigger: LeftStealth,
        casts: left_cast,
        window_ms: 500,
        count: 1,
      ),
      proc(id: 2, trigger: Died, casts: died_cast, window_ms: 500, count: 1),
    ])
  let plans = support.plans_of([stealthing(), holder])
  let #(state, joined_effects) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, entered) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let caster = dead(caster: planted_caster())
  let #(state, effects) = died(cast: state, caster:, now: support.at(ms: 3000))
  let #(_, effects) = answered(caster:, state:, effects:, at: 3000)
  let lines =
    trace(effects:, earlier: [joined_effects, entered], pressed: 38_913)
  assert list.contains(
    list.take_while(lines, fn(line) { line != "stealth off" }),
    "end 38913",
  )
    as "the casts' 0x7fe come first"
  assert from(lines:, line: "stealth off")
    == [
      "stealth off",
      "start 250201",
      "go 250201",
      "end 250201",
      "start 250202",
      "go 250202",
      "end 250202",
    ]
    as "the input's own event, the death, fires before the stealth change it caused, though the LeftStealth row comes first in the holder"
}

pub fn procs_are_matched_after_the_inputs_work_a_removed_holder_fires_nothing_an_applied_one_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  let left_cast = cast_of_proc(spell4_id: 250_202)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(
        id: 1,
        trigger: LeftStealth,
        casts: left_cast,
        window_ms: 500,
        count: 1,
      ),
    ])
  // A go that removes the holder (a type 80 row) and ends the stealth (a type 84 row).
  let removing =
    support.with_effects(
      spell: support.with_effects(
        spell: Spell(
          ..support.child(spell4_id: 38_783, base: 2),
          stealth_change: KeepsStealth,
        ),
        kinds: [
          spell_plan.RemoveEffect(spell_plan.ForceRemove(
            effect_id: Spell4EffectsId(83_832),
            phase_flags: -1,
            aim: spell_plan.AimsAtCaster,
            selector: lasting.Spell(Spell4Id(250_101)),
            count: 1,
            condition: Always,
            tag: spend.always,
          )),
        ],
      ),
      kinds: [
        spell_plan.RemoveStealthEffect(RemoveStealthRow(
          effect_id: Spell4EffectsId(83_833),
          phase_flags: -1,
          condition: Always,
          tag: spend.always,
        )),
      ],
    )
  let plans = support.plans_of([stealthing(), removing, holder])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let #(state, effects) =
    planted_press(plans:, state:, bag: bag_of_base_2, at: 3000)
  assert list.contains(
    trace(effects:, earlier: [], pressed: 38_783),
    "stealth off",
  )
    as "the setup: the stealth ended in that input"
  assert starts_of(spell4_id: 250_202, effects:) == 0
    as "the proc was removed by the same input's go, so it is not held when the input is matched"
  assert cast_state.stealthed(cast: state) == False
  // A go that applies a holder and enters stealth in one input.
  let applier =
    support.with_effects(
      spell: support.with_effects(
        spell: Spell(
          ..support.child(spell4_id: 38_915, base: 3),
          stealth_change: KeepsStealth,
        ),
        kinds: [
          spell_plan.StealthEffect(support.stealth_row(
            id: 95_775,
            breaks: KeptOnDamage,
          )),
        ],
      ),
      kinds: [
        spell_plan.ProcEffect(proc(
          id: 5,
          trigger: EnteredStealth,
          casts: cast_of_proc(spell4_id: 250_203),
          window_ms: 500,
          count: 1,
        )),
      ],
    )
  let plans = support.plans_of([applier])
  let #(_, entering) =
    planted_press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  assert from(
      lines: trace(effects: entering, earlier: [], pressed: 38_915),
      line: "stealth on",
    )
    == ["stealth on", "start 250203", "go 250203", "end 250203"]
    as "the proc the go applied is held when the input is matched, so its 217 fires"
}

pub fn a_procs_own_cast_fires_procs_so_a_217_proc_whose_spell_ends_stealth_fires_the_218_proc_test() -> Nil {
  use <- owned_test.run(60_000)
  let leaving = cast_of_proc(spell4_id: 250_202)
  let ending =
    support.with_effects(spell: cast_of_proc(spell4_id: 250_201), kinds: [
      spell_plan.RemoveStealthEffect(RemoveStealthRow(
        effect_id: Spell4EffectsId(250_901),
        phase_flags: -1,
        condition: Always,
        tag: spend.always,
      )),
    ])
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(
        id: 1,
        trigger: EnteredStealth,
        casts: ending,
        window_ms: 500,
        count: 1,
      ),
      proc(
        id: 2,
        trigger: LeftStealth,
        casts: leaving,
        window_ms: 500,
        count: 1,
      ),
    ])
  let plans = support.plans_of([stealthing(), holder])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(_, effects) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let lines = trace(effects:, earlier: [], pressed: 38_913)
  assert from(lines:, line: "stealth on")
    == [
      "stealth on",
      "start 250201",
      "go 250201",
      "off 38913",
      "end 250201",
      "stealth off",
      "start 250202",
      "go 250202",
      "end 250202",
    ]
    as "the proc's go is an input like any: its RemoveStealth row ends the stealth, the 0x8f5 follows, and the holder's 218 proc fires in that input"
}

// ---- death keeps the passive's procs, a camp drops them ----

pub fn death_keeps_the_passives_procs_so_the_next_stealth_entry_after_the_wake_fires_60724_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, _) = joined(caster:, at: 1000)
  let #(state, dying) = dies(state:, caster:, at: 2000)
  assert starts_of(spell4_id: 63_366, effects: dying) == 1
    as "the passive's Died proc fires in the death itself"
  let #(_, entering) = toggled(state:, caster:, at: 3000)
  assert starts_of(spell4_id: 60_724, effects: entering) == 1
    as "Class 5's passive has propertyFlags 0x100: the death leaves its nodes, procs among them, and the 217 proc fires after the wake"
}

pub fn a_camp_drops_the_procs_fires_nothing_and_the_next_passive_holds_them_with_no_history_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, _) = joined(caster:, at: 1000)
  let #(state, _) = toggled(state:, caster:, at: 2000)
  let #(state, left) = cast_tick.left(cast: state)
  assert support.writes(effects: left) == []
    as "a camp writes nothing, and leaving stealth is no event"
  assert list.filter(left, is_strike) == []
  let #(state, started) =
    passive_started(
      cast: state,
      caster:,
      plans: support.real_plans(),
      base: Spell4BaseId(29_131),
      now: support.at(ms: 2100),
    )
  let #(state, _) = answered(caster:, state:, effects: started, at: 2100)
  let #(_, entering) = toggled(state:, caster:, at: 3100)
  assert starts_of(spell4_id: 60_724, effects: entering) == 1
    as "the next join's passive holds the procs again, and the 217 proc fires"
}

// ---- a proc's life ----

fn pressable(
  spell4_id spell4_id: Int,
  base base: Int,
  procs procs: List(ProcRow),
) -> Spell {
  Spell(..holding(spell4_id:, procs:), spell4_base_id: Spell4BaseId(base))
}

pub fn a_proc_lasts_as_long_as_its_node_a_timed_one_ends_with_it_and_a_removal_drops_it_at_once_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.lifetime: a durationTime gives the caster's node that life.
  let timed =
    ProcRow(
      ..proc(
        id: 1,
        trigger: LeftCombat,
        casts: cast_of_proc(spell4_id: 250_201),
        window_ms: 500,
        count: 1,
      ),
      row: LastingRow(delay_ms: 0, duration_ms: 3000, until_removed: False),
    )
  let holder = pressable(spell4_id: 250_101, base: 1, procs: [timed])
  let removing =
    support.with_effects(
      spell: Spell(
        ..support.child(spell4_id: 38_783, base: 2),
        stealth_change: KeepsStealth,
      ),
      kinds: [
        spell_plan.RemoveEffect(spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(83_832),
          phase_flags: -1,
          aim: spell_plan.AimsAtCaster,
          selector: lasting.Spell(Spell4Id(250_101)),
          count: 1,
          condition: Always,
          tag: spend.always,
        )),
      ],
    )
  let plans = support.plans_of([holder, removing])
  let caster = planted_caster()
  let #(state, pressed) =
    planted_press(plans:, state: cast_state.new(), bag: bag_of_base_1, at: 0)
  let leaves = fn(state, at) {
    let #(state, effects) =
      combat_left(cast: state, caster:, now: support.at(ms: at))
    let #(state, effects) = answered(caster:, state:, effects:, at:)
    #(state, starts_of(spell4_id: 250_201, effects:))
  }
  let #(_, inside) = leaves(state, 2999)
  assert inside == 1 as "1 ms before the node's end the proc is held"
  let #(ended, timers) =
    support.run_timers(state:, effects: pressed, from_ms: 0)
  assert list.any(timers, fn(step) {
    step.0 == 3000
    && list.contains(
      trace(effects: step.1, earlier: [pressed], pressed: 250_101),
      "end 250101",
    )
  })
    as "the node ends at 3000 ms: the cast, with no other node, ends with its 0x7fe (cast.target_node_end)"
  let #(_, after) = leaves(ended, 3001)
  assert after == 0 as "after the node's end it is gone"
  let #(removed, _) = planted_press(plans:, state:, bag: bag_of_base_2, at: 500)
  let #(_, dropped) = leaves(removed, 600)
  assert dropped == 0 as "a type 80 removal of its holder drops it at once"
}

pub fn a_camp_ends_a_procs_fire_history_with_the_proc_test() -> Nil {
  use <- owned_test.run(60_000)
  let entered = cast_of_proc(spell4_id: 250_201)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(
        id: 1,
        trigger: EnteredStealth,
        casts: entered,
        window_ms: 500,
        count: 1,
      ),
    ])
  let plans = support.plans_of([stealthing(), holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, first) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert starts_of(spell4_id: 250_201, effects: first) == 1
  let #(state, _) = cast_tick.left(cast: state)
  let #(state, started) =
    passive_started(
      cast: state,
      caster:,
      plans:,
      base: holder.spell4_base_id,
      now: support.at(ms: 2100),
    )
  let #(state, _) = answered(caster:, state:, effects: started, at: 2100)
  let #(_, again) = planted_press(plans:, state:, bag: bag_of_base_1, at: 2200)
  assert starts_of(spell4_id: 250_201, effects: again) == 1
    as "Spell4Effects.effectType.14.limits: the fire 200 ms ago left with the camp, so the 217 proc fires at once"
}

pub fn a_stealth_ended_by_a_failing_persistence_fires_the_procs_for_leaving_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Prerequisite 903 (type 28, comparison 1) holds while the caster is in combat; the
  // stealth cast holds it as its caster persistence, so it ends when combat does
  // (`Spell4.prerequisiteIdCasterPersistence`, the cast rule's `persisted`).
  let left = cast_of_proc(spell4_id: 250_202)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(id: 1, trigger: LeftStealth, casts: left, window_ms: 500, count: 1),
    ])
  let bound =
    Spell(
      ..stealthing(),
      caster_persistence: Some(
        prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
      ),
    )
  let plans = support.plans_of([bound, holder])
  let in_combat = cast_state.Caster(..planted_caster(), in_combat: True)
  let out = cast_state.Caster(..planted_caster(), in_combat: False)
  let #(state, joined_effects) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, pressed) =
    support.pressed_in(
      plans:,
      state:,
      caster: in_combat,
      bag_index: bag_of_base_1,
      target: 0,
      at: 2000,
    )
  assert cast_state.stealthed(cast: state)
  let #(state, effects) =
    persisted(cast: state, caster: out, now: support.at(ms: 3000))
  let #(_, effects) = answered(caster: out, state:, effects:, at: 3000)
  let lines =
    trace(effects:, earlier: [joined_effects, pressed], pressed: 38_913)
  assert from(lines:, line: "stealth off")
    == ["stealth off", "start 250202", "go 250202", "end 250202"]
    as "the persistence end drops the stealth source, and the input that did it fires the 218 proc after its 0x8f5"
}

pub fn a_died_proc_of_a_cast_that_is_not_the_innate_passive_is_not_held_and_says_so_test() -> Nil {
  use <- owned_test.run(60_000)
  // A death ends every cast but the innate passive before the procs are matched, so the
  // Died proc of any other holder could never fire.
  let died_cast = cast_of_proc(spell4_id: 250_201)
  let holder =
    pressable(spell4_id: 250_101, base: 1, procs: [
      proc(id: 1, trigger: Died, casts: died_cast, window_ms: 500, count: 1),
    ])
  let plans = support.plans_of([holder])
  let caster = planted_caster()
  let #(state, pressed) =
    planted_press(plans:, state: cast_state.new(), bag: bag_of_base_1, at: 1000)
  assert list.any(support.logs(effects: pressed), fn(line) {
    line.0 == LogDebug && string.contains(line.1, "not the innate passive")
  })
    as "the go says the proc is not held"
  let #(state, dying) =
    died(cast: state, caster: dead(caster:), now: support.at(ms: 2000))
  let #(_, effects) =
    answered(caster: dead(caster:), state:, effects: dying, at: 2000)
  assert starts_of(spell4_id: 250_201, effects:) == 0
}

// ---- the events of the holder's own casts ----

/// The spell of Spell4 250301 that lands the hits: base 2 (bag index 10), no cast time, of
/// this school (`Spell4Base.school`).
const hitter_spell4 = 250_301

fn hitter(school school: Int) -> Spell {
  Spell(..support.child(spell4_id: hitter_spell4, base: 2), school:)
}

/// A proc of this trigger that casts the planted spell `casts` at `aim`, with a limit no
/// test reaches, so what a test shows is the event.
fn firing(
  id id: Int,
  trigger trigger: spell_plan.Trigger,
  casts casts: Int,
  aim aim: spell_plan.ProcAim,
) -> ProcRow {
  ProcRow(
    ..proc(
      id:,
      trigger:,
      casts: cast_of_proc(spell4_id: casts),
      window_ms: 500,
      count: 1,
    ),
    limit: spell_plan.ForLife(count: 1000),
    aim:,
  )
}

/// A hit on the creature in its first life with these blows.
fn creature_hit(
  unit_id unit_id: Int,
  descriptions descriptions: List(hit.Description),
) -> cast_state.Struck {
  cast_state.Hit(
    unit_id:,
    unit: support.first_life,
    descriptions:,
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

/// A hit on the creature in its first life with one plain blow: the damage a go's row lands
/// on it. A hit with no blow (a spell that only selects the unit) raises no event.
fn plain_hit(unit_id unit_id: Int) -> cast_state.Struck {
  creature_hit(unit_id:, descriptions: [
    blow(result: combat_result.Hit, killed: 0),
  ])
}

/// A blow of this combat result that killed its unit when `killed` is 1.
fn blow(
  result result: combat_result.CombatResult,
  killed killed: Int,
) -> hit.Description {
  hit.Description(
    spell4_effects_id: 1,
    delay_ms: 0,
    damage: support.landed_damage(
      amount: 8,
      killed:,
      combat_result: result,
      damage_type: damage_type.Tech,
    ),
  )
}

/// The units the casts of this Spell4 are aimed at, one for each 0x7ff that starts one.
fn starts_at(
  spell4_id spell4_id: Int,
  effects effects: List(Effect),
) -> List(Int) {
  list.filter_map(support.frames_of(message_id: 0x07FF, effects:), fn(frame) {
    let assert Ok(start) = spell_started.decode(frame.body)
      as "a 0x7ff the rule wrote decodes"
    case start.spell4_id == spell4_id {
      True -> Ok(start.primary_target_unit_id)
      False -> Error(Nil)
    }
  })
}

/// The time of each cast of the Spell4 that the steps start.
fn started_when(
  spell4_id spell4_id: Int,
  steps steps: List(#(Int, List(Effect))),
) -> List(Int) {
  list.flat_map(steps, fn(step) {
    list.map(starts_at(spell4_id:, effects: step.1), fn(_) { step.0 })
  })
}

/// What a go of the Spell4 strikes, and nothing else does.
fn only(
  spell4_id spell4_id: Int,
  struck struck: List(cast_state.Struck),
) -> fn(cast_state.GoAsked) -> List(cast_state.Struck) {
  fn(asked: cast_state.GoAsked) {
    case asked.spell4_id == Spell4Id(spell4_id) {
      True -> struck
      False -> []
    }
  }
}

/// A press of the bag index whose go strikes `struck`, every other go striking none.
fn striking(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  by spell4_id: Int,
  struck struck: List(cast_state.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  let caster = planted_caster()
  let #(state, effects) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag,
      target: 0,
      at: ms,
    )
  support.answered_each(
    caster:,
    state:,
    effects:,
    at: ms,
    struck_of: only(spell4_id:, struck:),
    rolls: [],
    poses: dict.new(),
  )
}

/// A press of the hitter whose go strikes `struck`.
fn hit_with(
  plans plans: Plans,
  state state: State,
  struck struck: List(cast_state.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  striking(
    plans:,
    state:,
    bag: bag_of_base_2,
    by: hitter_spell4,
    struck:,
    at: ms,
  )
}

/// The plans of a holder of these procs and a hitter of this school, and the holder's
/// state once its passive is started at 500.
fn holder_and_hitter(
  procs procs: List(ProcRow),
  school school: Int,
) -> #(Plans, State) {
  let holder = holding(spell4_id: 250_101, procs:)
  let plans = support.plans_of([holder, hitter(school:)])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  #(plans, state)
}

pub fn a_kind_12_proc_fires_its_spell_on_every_hit_the_holder_lands_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.client_evaluation: the client reads no Proc row, so the
  // fire is an ordinary cast: a 0x7ff of a non-zero parent and its go, and no 0x7fd.
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        proc(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: cast_of_proc(spell4_id: 250_201),
          window_ms: 500,
          count: 1,
        ),
      ],
      school: 2,
    )
  let #(state, first) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  let lines = trace(effects: first, earlier: [], pressed: hitter_spell4)
  assert list.filter(lines, fn(line) {
      line == "start 250201" || line == "go 250201"
    })
    == ["start 250201", "go 250201"]
    as "the proc's spell starts, then goes"
  assert !list.contains(
    list.take_while(lines, fn(line) { line != "go 250301" }),
    "start 250201",
  )
    as "the fire comes after the go that hit"
  assert list.count(support.written_ids(effects: first), fn(id) { id == 0x07FD })
    == 1
    as "only the press is confirmed with a 0x7fd"
  let start = started_of(spell4_id: 250_201, effects: first)
  assert start.parent_spell4_id == 250_101 && start.root_spell4_id == 250_101
    as "opcode.0x7ff.root_parent: a cast no press made names the holder's spell as root and parent"
  let #(_, second) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 2000)
  assert starts_of(spell4_id: 250_201, effects: second) == 1
    as "1000 ms after the first fire the 500 ms window is free: every hit fires"
}

pub fn a_deflected_or_immune_unit_raises_no_hit_test() -> Nil {
  use <- owned_test.run(60_000)
  // A guess: no client code reads a Proc row, so the server takes a deflected unit and a
  // guarded one as no landed hit.
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let struck = [
    cast_state.Deflected(unit_id: 31),
    cast_state.Immune(
      unit_id: 32,
      unit: support.first_life,
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
    plain_hit(unit_id: 33),
  ]
  let #(_, effects) = hit_with(plans:, state:, struck:, at: 1000)
  assert starts_at(spell4_id: 250_201, effects:) == [33]
    as "only the creature the strike hit raises a hit"
}

pub fn a_hit_by_a_school_1_spell_raises_a_melee_hit_and_one_by_a_school_2_spell_does_not_test() -> Nil {
  use <- owned_test.run(60_000)
  // A guess (Spell4Effects.effectType.14.dataBits00.13_school): kind 13 is a hit by a
  // spell of Spell4Base.school 1, Melee (Spell.CodeEnumSchool).
  let procs = [
    firing(
      id: 1,
      trigger: spell_plan.LandsHit,
      casts: 250_201,
      aim: spell_plan.AtHolder,
    ),
    firing(
      id: 2,
      trigger: spell_plan.LandsMeleeHit,
      casts: 250_202,
      aim: spell_plan.AtHolder,
    ),
  ]
  let hit_by = fn(school) {
    let #(plans, state) = holder_and_hitter(procs:, school:)
    let #(_, effects) =
      hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
    #(
      starts_of(spell4_id: 250_201, effects:),
      starts_of(spell4_id: 250_202, effects:),
    )
  }
  assert hit_by(1) == #(1, 1)
    as "school 1 raises both the hit and the melee hit"
  assert hit_by(2) == #(1, 0) as "school 2 raises the hit alone"
}

pub fn a_go_hitting_two_creatures_raises_one_hit_each_in_selection_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let #(_, effects) =
    hit_with(
      plans:,
      state:,
      struck: [plain_hit(unit_id: 32), plain_hit(unit_id: 31)],
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects:) == [32, 31]
    as "one fire for each creature, in the order the strike round lists them"
}

pub fn each_damage_description_raises_a_hit_and_a_hit_with_none_raises_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let #(_, effects) =
    hit_with(
      plans:,
      state:,
      struck: [
        creature_hit(unit_id: 31, descriptions: [
          blow(result: combat_result.Hit, killed: 0),
          blow(result: combat_result.Hit, killed: 0),
        ]),
        creature_hit(unit_id: 32, descriptions: []),
      ],
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects:) == [31, 31]
    as "a go with two damage rows on creature 31 raises two hits, and creature 32, which the go only selects (no description, as Crush's first spell does), raises none"
}

pub fn a_critical_description_raises_a_critical_and_a_hit_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsCritical,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        ),
        firing(
          id: 2,
          trigger: spell_plan.LandsHit,
          casts: 250_202,
          aim: spell_plan.AtHolder,
        ),
      ],
      school: 2,
    )
  let hit_with_blow = fn(result) {
    let #(_, effects) =
      hit_with(
        plans:,
        state:,
        struck: [
          creature_hit(unit_id: 31, descriptions: [blow(result:, killed: 0)]),
        ],
        at: 1000,
      )
    #(
      starts_of(spell4_id: 250_201, effects:),
      starts_of(spell4_id: 250_202, effects:),
    )
  }
  assert hit_with_blow(combat_result.Critical) == #(1, 1)
    as "a blow whose combat result is a critical raises both"
  assert hit_with_blow(combat_result.Hit) == #(0, 1)
    as "a plain hit raises the hit alone"
}

pub fn a_killing_description_raises_a_kill_at_the_killed_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.Kills,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let #(_, effects) =
    hit_with(
      plans:,
      state:,
      struck: [
        creature_hit(unit_id: 31, descriptions: [
          blow(result: combat_result.Hit, killed: 0),
        ]),
        creature_hit(unit_id: 32, descriptions: [
          blow(result: combat_result.Hit, killed: 1),
        ]),
      ],
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects:) == [32]
    as "the description of killed 1 is the kill, and it is at the creature it killed"
}

// ---- ticks ----

/// Paralytic Surge's damage row ticking every 2000 ms for 6000 ms: three ticks, 2000,
/// 4000 and 6000 ms after the go.
fn periodic() -> List(spell_area.TickingDamage) {
  [
    spell_area.TickingDamage(
      damage: spell_area.DamageEffect(
        effect_id: Spell4EffectsId(96_125),
        damage_type: 2,
        delay_ms: 0,
        phase_flags: -1,
        aim: spell_plan.AimsAtArea,
        formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
          damage.Parameter(kind: 10, value: 8.14),
        ]),
        threat_multiplier: 1.0,
        condition: Always,
        tag: spend.always,
      ),
      schedule: ticking.Schedule(
        delay_ms: 0,
        tick_ms: 2000,
        duration_ms: 6000,
        count: ticking.Ticks(3),
      ),
    ),
  ]
}

/// The strike round of a tick: it lands for 8 health, and kills the creature when
/// `killed` is 1.
fn landed_tick(
  asked asked: cast_state.TickAsked,
  killed killed: Int,
) -> cast_state.Struck {
  support.hit_with(
    unit_id: asked.unit_id,
    unit: cast_state.HitCreature(life: asked.life, struck_at_ms: 0),
    descriptions: [
      hit.Description(
        ..blow(result: combat_result.Hit, killed:),
        spell4_effects_id: asked.effect_id.value,
      ),
    ],
    controls: [],
    ticking: [],
  )
}

/// A step answered: its goes struck as `struck` says, and each tick strike it asks
/// landed on its creature, killing it at `kills_at`.
fn tick_settled(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck struck: List(cast_state.Struck),
  kills_at kills_at: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.answered_each(
      caster:,
      state:,
      effects:,
      at: ms,
      struck_of: only(spell4_id: hitter_spell4, struck:),
      rolls: [],
      poses: dict.new(),
    )
  list.fold(
    support.tick_strikes(effects:),
    #(state, effects),
    fn(so_far, asked) {
      let #(state, done) = so_far
      let killed = case ms == kills_at {
        True -> 1
        False -> 0
      }
      let #(state, round) =
        cast.ticked(
          cast: state,
          caster:,
          now: support.at(ms:),
          asked:,
          struck: Some(landed_tick(asked:, killed:)),
        )
        |> support.then_procs(caster:, at: ms)
      let #(state, round) =
        support.answered_each(
          caster:,
          state:,
          effects: round,
          at: ms,
          struck_of: fn(_) { [] },
          rolls: [],
          poses: dict.new(),
        )
      #(state, list.append(done, round))
    },
  )
}

/// Every timer due by `until` ms fires, earliest first, each step settled as
/// `tick_settled` does; the steps with their times.
fn tick_loop(
  caster caster: Caster,
  state state: State,
  pending pending: List(#(Int, TimerId)),
  steps steps: List(#(Int, List(Effect))),
  struck struck: List(cast_state.Struck),
  kills_at kills_at: Int,
  until until: Int,
) -> List(#(Int, List(Effect))) {
  let #(_, _, fired, _) =
    support.fire_pending(
      context: Nil,
      state:,
      pending:,
      until_ms: until,
      step: fn(_, state, due, timer) {
        let #(state, raw) =
          support.fired_raw_as(caster:, state:, timer:, at: due)
        let #(state, effects) =
          tick_settled(
            caster:,
            state:,
            effects: raw,
            at: due,
            struck:,
            kills_at:,
          )
        support.Step(context: Nil, state:, effects:, record: #(due, effects))
      },
    )
  list.append(steps, fired)
}

pub fn a_periodic_tick_raises_a_hit_and_a_kill_by_a_tick_raises_a_kill_test() -> Nil {
  use <- owned_test.run(60_000)
  // A guess for the hit: no source says a periodic damage tick is a hit for a Proc. The
  // go lands a hit with no blow of its own and ticks at 3000, 5000 and 7000; the last tick
  // kills.
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
        firing(
          id: 2,
          trigger: spell_plan.Kills,
          casts: 250_202,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let caster = planted_caster()
  let struck = [
    cast_state.Hit(
      unit_id: 31,
      unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
      descriptions: [blow(result: combat_result.Hit, killed: 0)],
      controls: [],
      armor_removed: 0,
      ticking: periodic(),
    ),
  ]
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 1000,
    )
  let #(state, first) =
    tick_settled(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck:,
      kills_at: 7000,
    )
  let steps =
    tick_loop(
      caster:,
      state:,
      pending: support.due_of(effects: first, now_ms: 1000),
      steps: [#(1000, first)],
      struck:,
      kills_at: 7000,
      until: 9000,
    )
  assert started_when(spell4_id: 250_201, steps:) == [1000, 3000, 5000, 7000]
    as "the go's hit and each of the three ticks that landed"
  assert started_when(spell4_id: 250_202, steps:) == [7000]
    as "the kill is the last tick's"
}

// ---- heals ----

fn health_formula() -> damage.Formula {
  damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
    damage.Parameter(kind: 13, value: 0.3281),
    damage.Parameter(kind: 10, value: 17.51),
    damage.Parameter(kind: 0, value: 0.0),
    damage.Parameter(kind: 0, value: 0.0),
  ])
}

fn heal(id id: Int, delay_ms delay_ms: Int) -> spell_plan.Heal {
  spell_plan.Heal(
    effect_id: Spell4EffectsId(id),
    vital: effect_kind.Health,
    phase_flags: -1,
    aim: spell_plan.AimsAtCaster,
    condition: Always,
    tag: spend.always,
    formula: health_formula(),
    delay_ms:,
  )
}

fn ticking_heal(id id: Int) -> spell_plan.Heal {
  spell_plan.TickingHeal(
    effect_id: Spell4EffectsId(id),
    vital: effect_kind.Health,
    phase_flags: -1,
    aim: spell_plan.AimsAtCaster,
    condition: Always,
    tag: spend.always,
    formula: health_formula(),
    schedule: ticking.Schedule(
      delay_ms: 0,
      tick_ms: 2000,
      duration_ms: 6000,
      count: ticking.Ticks(3),
    ),
  )
}

/// The caster of level 5 and 400 Support Rating with this much of its 736 health.
fn healer(health health: Int) -> Caster {
  support.healing_caster(health:)
}

/// The steps of a press at 1000 ms of a spell of these heal rows, by a holder of these
/// procs, every timer fired to its end.
fn healed_steps(
  health health: Int,
  rows rows: List(spell_plan.Heal),
  procs procs: List(ProcRow),
) -> List(#(Int, List(Effect))) {
  let holder = holding(spell4_id: 250_101, procs:)
  let healing =
    support.with_effects(
      spell: support.child(spell4_id: 250_303, base: 3),
      kinds: list.map(rows, spell_plan.HealEffect),
    )
  let plans = support.plans_of([holder, healing])
  let caster = healer(health:)
  let #(state, started) =
    passive_started(
      cast: cast_state.new(),
      caster:,
      plans:,
      base: holder.spell4_base_id,
      now: support.at(ms: 500),
    )
  let #(state, _) = answered(caster:, state:, effects: started, at: 500)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, effects) = answered(caster:, state:, effects: raw, at: 1000)
  let #(_, later) =
    support.run_timers_each(
      caster:,
      state:,
      effects:,
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  [#(1000, effects), ..later]
}

pub fn a_heal_at_the_go_on_a_timer_and_at_a_tick_each_raise_a_heal_at_the_holder_test() -> Nil {
  use <- owned_test.run(60_000)
  let steps =
    healed_steps(
      health: 500,
      rows: [
        heal(id: 1, delay_ms: 0),
        heal(id: 2, delay_ms: 500),
        ticking_heal(id: 3),
      ],
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsHeal,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        ),
      ],
    )
  assert started_when(spell4_id: 250_201, steps:)
    == [1000, 1500, 3000, 5000, 7000]
    as "the heal of the go, the one 500 ms on, and the three ticks of the third"
  assert list.all(
    list.flat_map(steps, fn(step) {
      starts_at(spell4_id: 250_201, effects: step.1)
    }),
    fn(unit) { unit == 7 },
  )
    as "each fire is at the holder, who is the unit healed"
}

pub fn a_heal_that_moves_nothing_still_raises_a_heal_test() -> Nil {
  use <- owned_test.run(60_000)
  // A guess: the caster is at full health, so the heal changes nothing, and the Proc
  // still sees a heal landed (the client reads no Proc row to say otherwise).
  let steps =
    healed_steps(health: 736, rows: [heal(id: 1, delay_ms: 0)], procs: [
      firing(
        id: 1,
        trigger: spell_plan.LandsHeal,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  assert started_when(spell4_id: 250_201, steps:) == [1000]
}

pub fn no_critical_heal_is_raised_while_heals_never_crit_test() -> Nil {
  use <- owned_test.run(60_000)
  // The 69 kind-147 rows are read and silent: no heal is rolled a critical until the issue
  // that closes this gap (issue 830), so a heal raises only the plain heal.
  let steps =
    healed_steps(health: 500, rows: [heal(id: 1, delay_ms: 0)], procs: [
      firing(
        id: 1,
        trigger: spell_plan.LandsCriticalHeal,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
      firing(
        id: 2,
        trigger: spell_plan.LandsHeal,
        casts: 250_202,
        aim: spell_plan.AtHolder,
      ),
    ])
  assert started_when(spell4_id: 250_201, steps:) == []
    as "the critical-heal proc never fires"
  assert started_when(spell4_id: 250_202, steps:) == [1000]
    as "the heal proc of the same heal does"
}

// ---- where a fire is aimed, and the creature's gate ----

pub fn a_bit_4_hit_proc_casts_at_the_struck_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Row 208200 has dataBits03 4 (Spell4Effects.effectType.14.dataBits03): its damage is
  // cast at the creature the hit struck; a row without bit 4 casts at the holder.
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
        firing(
          id: 2,
          trigger: spell_plan.LandsHit,
          casts: 250_202,
          aim: spell_plan.AtHolder,
        ),
      ],
      school: 2,
    )
  let #(_, effects) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  assert starts_at(spell4_id: 250_201, effects:) == [31]
  assert starts_at(spell4_id: 250_202, effects:) == [7]
}

pub fn the_208200_gate_passes_only_while_the_holders_79220_holds_a_node_on_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Prerequisite 37038 (`Prerequisite.prerequisiteTypeId.50`): type 50, comparison 1, value
  // 79220: the creature is under the holder's cast of Spell4 79220.
  let assert [stalker_damage] =
    spell_plan.payloads(
      spell: support.real_spell(spell4_id: 79_229),
      as_kind: spell_plan.as_proc,
    )
    as "79229 holds the one Proc row 208200"
  let holder = holding(spell4_id: 250_101, procs: [stalker_damage])
  let marking =
    support.with_effects(
      spell: support.child(spell4_id: 79_220, base: 3),
      kinds: [
        spell_plan.LastingEffect(spell_plan.Lasting(
          effect_id: Spell4EffectsId(250_901),
          phase_flags: -1,
          aim: spell_plan.AimsAtArea,
          row: LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
          condition: Always,
          tag: spend.always,
        )),
      ],
    )
  let striker = Spell(..hitter(school: 2), groups: [463])
  let plans = support.plans_of([holder, marking, striker])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let #(state, bare) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  assert starts_at(spell4_id: 79_221, effects: bare) == []
    as "no 79220 holds a node on the creature: the gate fails"
  let #(state, marked) =
    striking(
      plans:,
      state:,
      bag: bag_of_base_3,
      by: 79_220,
      struck: [plain_hit(unit_id: 31)],
      at: 2000,
    )
  assert starts_at(spell4_id: 79_221, effects: marked) == []
    as "79220 is not in group 463, so its own hit fires nothing"
  assert list.map(cast_state.holds_on(cast: state, unit_id: 31), fn(hold) {
      hold.spell4_id.value
    })
    == [79_220]
    as "79220's go gave its node to the creature it struck"
  let #(state, held) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 3000)
  assert starts_at(spell4_id: 79_221, effects: held) == [31]
    as "while 79220's node is on the creature the proc casts 79221 at it"
  let #(state, other) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 32)], at: 4000)
  assert starts_at(spell4_id: 79_221, effects: other) == []
    as "a creature 79220 does not hold fails"
  let #(state, _) = support.run_timers(state:, effects: marked, from_ms: 2000)
  let #(_, after) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 12_000)
  assert starts_at(spell4_id: 79_221, effects: after) == []
    as "once the node has ended (8000 ms) the gate fails again"
}

// ---- delayed fires ----

pub fn a_proc_with_delay_1000_casts_1_second_after_its_event_test() -> Nil {
  use <- owned_test.run(60_000)
  let delayed =
    ProcRow(
      ..firing(
        id: 1,
        trigger: spell_plan.LandsHit,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
      delay_ms: 1000,
    )
  let #(plans, state) = holder_and_hitter(procs: [delayed], school: 2)
  let #(state, effects) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  assert starts_of(spell4_id: 250_201, effects:) == 0
    as "nothing starts at the event"
  assert list.count(support.started_timers(effects:), fn(started) {
      started.1 == 1000
    })
    == 1
    as "one timer of 1000 ms is armed"
  let #(_, later) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.map(later, fn(step) {
      #(step.0, starts_of(spell4_id: 250_201, effects: step.1))
    })
    == [#(2000, 1)]
    as "the cast starts once, 1000 ms after the event"
}

pub fn a_delayed_fire_counts_against_the_limit_at_its_event_test() -> Nil {
  use <- owned_test.run(60_000)
  let delayed =
    ProcRow(
      ..proc(
        id: 1,
        trigger: spell_plan.LandsHit,
        casts: cast_of_proc(spell4_id: 250_201),
        window_ms: 3000,
        count: 1,
      ),
      delay_ms: 1000,
    )
  let #(plans, state) = holder_and_hitter(procs: [delayed], school: 2)
  let armed = fn(effects) {
    list.count(support.started_timers(effects:), fn(started) {
      started.1 == 1000
    })
  }
  let #(state, first) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  assert armed(first) == 1
  let #(state, second) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1500)
  assert armed(second) == 0
    as "the fire is counted at its event, 1000, so a hit at 1500, before it casts at 2000, is over the limit"
  let #(_, third) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 4000)
  assert armed(third) == 1 as "3000 ms after the event the window is free"
}

pub fn a_delayed_fire_is_dropped_with_its_timer_when_the_procs_node_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  // Design: a delayed fire is dropped, and its timer cancelled, when the proc's node ends,
  // as a pending heal is. The node of the timed row lasts 3000 ms.
  let timed =
    ProcRow(
      ..firing(
        id: 1,
        trigger: spell_plan.LandsHit,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
      row: LastingRow(delay_ms: 0, duration_ms: 3000, until_removed: False),
      delay_ms: 1000,
    )
  let holder = pressable(spell4_id: 250_101, base: 1, procs: [timed])
  let plans = support.plans_of([holder, hitter(school: 2)])
  let caster = planted_caster()
  let #(state, pressed) =
    planted_press(plans:, state: cast_state.new(), bag: bag_of_base_1, at: 0)
  let #(state, hit) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 2500)
  let assert [#(fire_timer, _)] =
    list.filter(support.started_timers(effects: hit), fn(started) {
      started.1 == 1000
    })
    as "the hit arms the delayed fire, due at 3500"
  let assert Ok(#(_, node_end)) =
    list.find(support.due_of(effects: pressed, now_ms: 0), fn(due) {
      due.0 == 3000
    })
    as "the holder's node ends at 3000"
  let #(state, ended) =
    support.fired_raw_as(caster:, state:, timer: node_end, at: 3000)
  assert list.contains(support.cancelled_timers(effects: ended), fire_timer)
    as "the node's end cancels the delayed fire's timer"
  let #(_, stale) =
    support.fired_raw_as(caster:, state:, timer: fire_timer, at: 3500)
  assert starts_of(spell4_id: 250_201, effects: stale) == 0
    as "and a timer that was already on its way casts nothing"
}

pub fn a_delayed_fire_is_dropped_when_the_holder_dies_test() -> Nil {
  use <- owned_test.run(60_000)
  // A pressed holder's casts end with its death, so its delayed fire's timer is cancelled
  // with them (the innate passive's casts stay, and so do its timers).
  let delayed =
    ProcRow(
      ..firing(
        id: 1,
        trigger: spell_plan.LandsHit,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
      delay_ms: 1000,
    )
  let holder = pressable(spell4_id: 250_101, base: 1, procs: [delayed])
  let plans = support.plans_of([holder, hitter(school: 2)])
  let caster = planted_caster()
  let #(state, _) =
    planted_press(plans:, state: cast_state.new(), bag: bag_of_base_1, at: 0)
  let #(state, hit) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  let assert [#(fire_timer, _)] =
    list.filter(support.started_timers(effects: hit), fn(started) {
      started.1 == 1000
    })
    as "the hit arms the delayed fire, due at 2000"
  let #(state, death) = died(cast: state, caster:, now: support.at(ms: 1500))
  assert list.contains(support.cancelled_timers(effects: death), fire_timer)
    as "the holder's death cancels the timer"
  let #(_, stale) =
    support.fired_raw_as(
      caster: dead(caster:),
      state:,
      timer: fire_timer,
      at: 2000,
    )
  assert starts_of(spell4_id: 250_201, effects: stale) == 0
    as "a timer already on its way casts nothing"
}

pub fn a_delayed_fire_of_the_innate_passives_proc_is_dropped_when_its_holder_dies_test() -> Nil {
  use <- owned_test.run(60_000)
  // The passive's cast stays through a death with its other timers, but a fire that waits on
  // its delay is dropped: the holder is gone, so nothing is cast for its hit.
  let delayed =
    ProcRow(
      ..firing(
        id: 1,
        trigger: spell_plan.LandsHit,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
      delay_ms: 1000,
    )
  let #(plans, state) = holder_and_hitter(procs: [delayed], school: 2)
  let #(state, hit) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  let assert [#(fire_timer, _)] =
    list.filter(support.started_timers(effects: hit), fn(started) {
      started.1 == 1000
    })
    as "the hit arms the delayed fire, due at 2000"
  let caster = planted_caster()
  let #(state, death) = died(cast: state, caster:, now: support.at(ms: 1500))
  assert list.contains(support.cancelled_timers(effects: death), fire_timer)
    as "the holder's death cancels the timer"
  let #(_, stale) =
    support.fired_raw_as(
      caster: dead(caster:),
      state:,
      timer: fire_timer,
      at: 2000,
    )
  assert starts_of(spell4_id: 250_201, effects: stale) == 0
    as "a timer already on its way casts nothing"
}

pub fn a_hit_answered_after_the_client_ended_the_cast_still_fires_the_procs_the_cast_lingers_to_hold_test() -> Nil {
  use <- owned_test.run(60_000)
  // The hitter holds a Proc until removed, so its cast lingers when the client cancels it
  // (0x801) while its second round is open; the hit then answered is the holder's hit all
  // the same, and the cast's spell is still known (`holder_of`).
  let lasting =
    support.with_effects(
      spell: Spell(
        ..hitter(school: 2),
        method: spell_plan.Multiphase,
        phase_delays_ms: [0, 500],
      ),
      kinds: [
        spell_plan.ProcEffect(firing(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        )),
      ],
    )
  let plans = support.plans_of([lasting])
  let caster = planted_caster()
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 1000,
    )
  let cast_id = support.pressed_id(effects: pressed)
  let #(state, first) = answered(caster:, state:, effects: pressed, at: 1000)
  let assert [#(second_go, _)] =
    list.filter(support.started_timers(effects: first), fn(started) {
      started.1 == 500
    })
    as "the first go arms the second, due at 1500"
  let #(state, asking) =
    support.fired_raw_as(caster:, state:, timer: second_go, at: 1500)
  let assert [cast_state.Strike(asked)] = list.filter(asking, is_strike)
    as "the second go asks for its targets"
  let assert Ok(#(state, _)) =
    cast.take(
      target_of: support.nothing_shown,
      cast: state,
      message: cast_state.Cancelled,
      body: support.cancel_body(
        cast_id:,
        reason: cast_result.SpellCancelled,
        bit: 1,
      ),
      caster:,
      plans:,
      now: support.at(ms: 1600),
    )
    as "the client ends the cast with reason 6 (opcode.0x801)"
  let #(_, late) =
    support.then_procs(
      step: support.went(
        cast: state,
        caster:,
        now: support.at(ms: 1700),
        cast_id: asked.cast_id,
        phase: asked.phase,
        struck: [plain_hit(unit_id: 31)],
      ),
      caster:,
      at: 1700,
    )
  assert starts_of(spell4_id: 250_201, effects: late) == 1
    as "the lingering cast's own proc fires for the hit it landed"
}

pub fn a_hit_answered_after_the_client_ended_a_cast_that_holds_no_node_still_fires_the_holders_proc_test() -> Nil {
  use <- owned_test.run(60_000)
  // The hitter is a one-phase spell with no lasting row, so its cast is gone from the
  // rule once the client cancels it (0x801) while its round is open; the hit the round
  // then answers is still the holder's hit, and the go names its spell (`GoAsked`).
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let caster = planted_caster()
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 1000,
    )
  let cast_id = support.pressed_id(effects: pressed)
  let assert [cast_state.Strike(asked)] = list.filter(pressed, is_strike)
    as "the press asks for the targets of its one go"
  let assert Ok(#(state, _)) =
    cast.take(
      target_of: support.nothing_shown,
      cast: state,
      message: cast_state.Cancelled,
      body: support.cancel_body(
        cast_id:,
        reason: cast_result.SpellCancelled,
        bit: 1,
      ),
      caster:,
      plans:,
      now: support.at(ms: 1100),
    )
    as "the client ends the cast with reason 6 (opcode.0x801)"
  let #(_, late) =
    support.then_procs(
      step: support.went_of_spell(
        cast: state,
        caster:,
        now: support.at(ms: 1200),
        cast_id: asked.cast_id,
        phase: asked.phase,
        spell: Ok(hitter(school: 2)),
        struck: [plain_hit(unit_id: 31)],
      ),
      caster:,
      at: 1200,
    )
  assert starts_at(spell4_id: 250_201, effects: late) == [31]
    as "the holder's proc fires at the creature the late hit struck"
}

// ---- no cascade, the draws, the order ----

pub fn a_fired_spells_own_hits_fire_procs_only_at_its_own_go_test() -> Nil {
  use <- owned_test.run(60_000)
  // The fire's go is a later input: its hits are matched when it goes, not inside the pass
  // that fired it, so a proc whose spell hits what it hit fires once for each go.
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(
        id: 1,
        trigger: spell_plan.LandsHit,
        casts: cast_of_proc(spell4_id: 250_201),
        window_ms: 1000,
        count: 2,
      ),
    ])
  let plans = support.plans_of([holder, hitter(school: 2)])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 1000,
    )
  let assert [cast_state.Strike(asked)] = list.filter(raw, is_strike)
    as "the press asks for its go"
  let go = fn(state, asked: cast_state.GoAsked) {
    let #(state, went) =
      support.went(
        cast: state,
        caster:,
        now: support.at(ms: 1000),
        cast_id: asked.cast_id,
        phase: asked.phase,
        struck: [plain_hit(unit_id: 31)],
      )
    assert cast_proc.has_pending(cast: state)
      as "the go's hit is waiting to be matched"
    let #(state, fired) =
      support.then_procs(step: #(state, went), caster:, at: 1000)
    assert !cast_proc.has_pending(cast: state)
      as "one pass matches it and the fire raises nothing inside it"
    #(state, fired)
  }
  let #(state, first) = go(state, asked)
  assert starts_of(spell4_id: 250_201, effects: first) == 1
  let assert [cast_state.Strike(own)] = list.filter(first, is_strike)
    as "the fire's go is asked, not answered inside the pass"
  let #(state, second) = go(state, own)
  assert starts_of(spell4_id: 250_201, effects: second) == 1
    as "the fire's own go hit the creature, and that fires the proc a second time"
  let assert [cast_state.Strike(own)] = list.filter(second, is_strike)
  let #(_, third) = go(state, own)
  assert starts_of(spell4_id: 250_201, effects: third) == 0
    as "a third fire is over the limit of 2 in 1000 ms"
}

pub fn proc_draws_needed_is_0_with_nothing_pending_and_counts_each_matching_proc_otherwise_test() -> Nil {
  use <- owned_test.run(60_000)
  let half = fn(id, trigger, casts) {
    ProcRow(
      ..firing(id:, trigger:, casts:, aim: spell_plan.AtHolder),
      chance: 0.5,
    )
  }
  let holder =
    holding(spell4_id: 250_101, procs: [
      half(1, spell_plan.LandsHit, 250_201),
      firing(
        id: 2,
        trigger: spell_plan.LandsHit,
        casts: 250_202,
        aim: spell_plan.AtHolder,
      ),
      half(3, spell_plan.LandsCritical, 250_203),
    ])
  let plans = support.plans_of([holder, hitter(school: 2)])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  assert cast_proc.proc_draws_needed(cast: state) == #(0, 0)
    as "nothing is pending after the passive's own pass"
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag_of_base_2,
      target: 0,
      at: 1000,
    )
  let assert [cast_state.Strike(asked)] = list.filter(raw, is_strike)
  let #(state, went) =
    support.went(
      cast: state,
      caster:,
      now: support.at(ms: 1000),
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [
        creature_hit(unit_id: 31, descriptions: [
          blow(result: combat_result.Hit, killed: 0),
        ]),
        creature_hit(unit_id: 32, descriptions: [
          blow(result: combat_result.Critical, killed: 0),
        ]),
      ],
    )
  assert cast_proc.proc_draws_needed(cast: state) == #(3, 0)
    as "creature 31: a hit, the 0.5 proc takes a word and the 1.0 proc none; creature 32: a hit and a critical, a word each"
  let #(state, _) = support.then_procs(step: #(state, went), caster:, at: 1000)
  assert cast_proc.proc_draws_needed(cast: state) == #(0, 0)
    as "the pass clears what it matched"
}

pub fn the_old_triggers_keep_their_order_after_the_inputs_events_test() -> Nil {
  use <- owned_test.run(60_000)
  // An input's own events come first, then its heals, then its stealth change: a go that
  // hits and enters stealth casts the hit's proc before the stealth's.
  let entering =
    support.with_effects(
      spell: Spell(..hitter(school: 2), stealth_change: KeepsStealth),
      kinds: [
        spell_plan.StealthEffect(support.stealth_row(
          id: 250_902,
          breaks: KeptOnDamage,
        )),
      ],
    )
  let holder =
    holding(spell4_id: 250_101, procs: [
      firing(
        id: 1,
        trigger: EnteredStealth,
        casts: 250_202,
        aim: spell_plan.AtHolder,
      ),
      firing(
        id: 2,
        trigger: spell_plan.LandsHit,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let plans = support.plans_of([holder, entering])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let #(_, effects) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  let lines = trace(effects:, earlier: [], pressed: hitter_spell4)
  assert list.filter(lines, fn(line) {
      line == "start 250201" || line == "start 250202"
    })
    == ["start 250201", "start 250202"]
    as "the hit's proc is cast before the stealth's, whatever order the holder lists them in"
}

pub fn the_stalkers_178239_takes_no_effect_from_its_own_hits_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Spell4Effects.effectType.14.dataBits00: 178239 (Spell4 38784) is kind 16, 'takes
  // damage': it fires on a blow the Stalker takes, not on a hit it lands, so the Stalker's
  // own hit casts nothing of 72838.
  let caster = stalker(in_combat: False)
  let #(state, _) = joined(caster:, at: 1000)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: support.real_plans(),
      state:,
      caster:,
      bag_index: 0,
      target: 0,
      at: 2000,
    )
  let #(state, effects) =
    support.answered_each(
      caster:,
      state:,
      effects: pressed,
      at: 2000,
      struck_of: fn(_) { [plain_hit(unit_id: 31)] },
      rolls: [],
      poses: dict.new(),
    )
  assert starts_of(spell4_id: 72_838, effects:) == 0
  assert !cast_proc.has_pending(cast: state)
}

// ---- part A of the triggers (issue 792) ----
//
// Every reading here is a guess: no client code reads a Proc row, so the kinds rest on the texts of
// `Spell4Effects.effectType.14.dataBits00.fairly_sure`. The tests show what the server does
// with each reading; a retail recording of the event settles it.

/// The press of the bag index, then its go answered with nothing struck: the effects of
/// both steps in order (an answer returns the effects it follows too).
fn pressed_and_answered(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
  at ms: Int,
) -> List(Effect) {
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag,
      target: 0,
      at: ms,
    )
  let #(_, answer) =
    support.answered_as(
      caster:,
      state:,
      effects: pressed,
      at: ms,
      struck: [],
      rolls: [],
    )
  answer
}

/// The lines of the trace that start one of the two planted procs' spells, in order.
fn starts_in_order(effects effects: List(Effect)) -> List(String) {
  list.filter(trace(effects:, earlier: [], pressed: 0), fn(line) {
    string.starts_with(line, "start 2502")
  })
}

// ---- 10: uses an ability ----

pub fn proc_ability_used_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 10 is 'uses an ability'. A press
  // the rule accepts is a use; a press it refuses is not.
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.UsesAbility,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        ),
      ],
      school: 2,
    )
  let #(_, accepted) = hit_with(plans:, state:, struck: [], at: 1000)
  assert starts_at(spell4_id: 250_201, effects: accepted) == [7]
    as "an accepted press fires the proc once, at the holder"
  let #(_, refused) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: dead(caster: planted_caster()),
      bag_index: bag_of_base_2,
      target: 0,
      at: 2000,
    )
  assert support.refusal_results(effects: refused) != []
    as "the hitter cannot be cast by a dead caster, so the press is refused"
  assert starts_of(spell4_id: 250_201, effects: refused) == 0
    as "a refused press fires nothing"
}

// ---- 103: spends a class resource ----

pub fn proc_resource_spent_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 103 is 'spends a class resource'
  // (texts 355762, 760074). A payment the rule takes is a spend; a gain is not.
  let holder =
    holding(spell4_id: 250_101, procs: [
      firing(
        id: 1,
        trigger: spell_plan.SpendsResource,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let spender =
    Spell(..support.child(spell4_id: 250_302, base: 1), costs: [
      spell_plan.SlotCost(slot: 1, amount: 3, result: 51),
    ])
  let gainer =
    support.with_effects(
      spell: support.child(spell4_id: 250_303, base: 3),
      kinds: [
        spell_plan.GainEffect(spell_plan.Gain(
          effect_id: Spell4EffectsId(1),
          gift: spell_plan.SlotPoints(slot: 1, points: 1),
          phase_flags: 1,
          condition: Always,
          tag: spend.always,
        )),
      ],
    )
  let plans = support.plans_of([holder, spender, gainer])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let paying =
    pressed_and_answered(
      plans:,
      state:,
      caster: planted_caster(),
      bag: bag_of_base_1,
      at: 1000,
    )
  assert support.payments(effects: paying)
    == [class_resource.Payment(slot: 1, amount: 3)]
    as "the spender pays 3 of slot 1"
  assert starts_at(spell4_id: 250_201, effects: paying) == [7]
    as "the payment fires the proc once"
  let gaining =
    pressed_and_answered(
      plans:,
      state:,
      caster: planted_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert support.gains(effects: gaining) != []
    as "the gainer gives a point of slot 1"
  assert starts_at(spell4_id: 250_201, effects: gaining) == []
    as "a gain fires nothing"
}

// ---- 21: receives a heal ----

/// The effects of a press of a spell whose child, made on `target`, holds a heal aimed at
/// its primary target, by a healer holding a kind 21 proc; a unit 900 is struck.
fn healed_through_a_child(
  target target: spell_plan.ProxyTarget,
) -> List(Effect) {
  let holder =
    holding(spell4_id: 250_101, procs: [
      firing(
        id: 1,
        trigger: spell_plan.ReceivesHeal,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let child =
    support.with_effects(
      spell: support.child(spell4_id: 90_001, base: 90_001),
      kinds: [
        spell_plan.HealEffect(spell_plan.Heal(
          effect_id: Spell4EffectsId(1),
          vital: effect_kind.Health,
          phase_flags: -1,
          aim: spell_plan.AimsAtPrimaryTarget,
          condition: Always,
          tag: spend.always,
          formula: health_formula(),
          delay_ms: 0,
        )),
      ],
    )
  let parent =
    support.with_effects(
      spell: support.child(spell4_id: 250_303, base: 3),
      kinds: [
        spell_plan.ProxyEffect(
          spell_plan.Proxy(
            period: None,
            effect_id: Spell4EffectsId(90_002),
            delay_ms: 0,
            phase_flags: -1,
            condition: Always,
            tag: spend.always,
            target:,
            spell: child,
            gains: [],
          ),
        ),
      ],
    )
  let plans = support.plans_of([holder, parent])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let caster = healer(health: 500)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_as(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck: support.hits([900]),
      rolls: [],
    )
  effects
}

pub fn proc_heal_received_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 21 is 'receives a heal' (text
  // 569376 'On Taking a Heal'). Only a heal the holder lands on itself counts: a heal aimed
  // at another unit lands nothing (the rule's own answer, issue 570).
  let steps =
    healed_steps(health: 500, rows: [heal(id: 1, delay_ms: 0)], procs: [
      firing(
        id: 1,
        trigger: spell_plan.ReceivesHeal,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  assert started_when(spell4_id: 250_201, steps:) == [1000]
    as "a heal the holder lands on itself fires once"
  assert starts_of(
      spell4_id: 250_201,
      effects: healed_through_a_child(target: spell_plan.OnCaster),
    )
    == 1
    as "control: a child made on the caster heals the caster, and the proc fires"
  assert starts_of(
      spell4_id: 250_201,
      effects: healed_through_a_child(target: spell_plan.OnEachStruck),
    )
    == 0
    as "a heal on the struck unit 900 is another unit's: the holder receives none"
}

// ---- 52: a foe deflects ----

pub fn proc_foe_deflects_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 52 is 'a foe deflects its
  // attack' (texts 364190, 498616). Only the Deflected answer counts; the proc is aimed at
  // the foe that deflected.
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.FoeDeflects,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let struck = [
    cast_state.Deflected(unit_id: 31),
    cast_state.Immune(
      unit_id: 32,
      unit: support.first_life,
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
    plain_hit(unit_id: 33),
  ]
  let #(_, effects) = hit_with(plans:, state:, struck:, at: 1000)
  assert starts_at(spell4_id: 250_201, effects:) == [31]
    as "the deflected unit raises it; the immune and the landed ones do not"
}

// ---- 49: a finisher lands a critical ----

pub fn proc_critical_finisher_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 49 is a critical hit by a
  // Finisher or a Builder (texts 'Landing a Critical Hit with a Finisher'); the row's group
  // filter (dataBits08, `Spell4Effects.effectType.14.dataBits08`) names which. The same
  // critical also raises 145.
  let finisher = Spell(..hitter(school: 2), groups: [333])
  let other = Spell(..support.child(spell4_id: 250_303, base: 3), groups: [444])
  let holder =
    holding(spell4_id: 250_101, procs: [
      ProcRow(
        ..firing(
          id: 1,
          trigger: spell_plan.LandsFinisherCritical,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        ),
        filter: spell_plan.InGroup(group_id: 333),
      ),
    ])
  let plans = support.plans_of([holder, finisher, other])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let critical =
    creature_hit(unit_id: 31, descriptions: [
      blow(result: combat_result.Critical, killed: 0),
    ])
  let #(_, by_finisher) =
    striking(
      plans:,
      state:,
      bag: bag_of_base_2,
      by: hitter_spell4,
      struck: [critical],
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects: by_finisher) == [7]
    as "a critical of a spell in group 333 fires it"
  let #(_, plainly) =
    striking(
      plans:,
      state:,
      bag: bag_of_base_2,
      by: hitter_spell4,
      struck: [plain_hit(unit_id: 31)],
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects: plainly) == []
    as "a hit that is no critical does not"
  let #(_, by_other) =
    striking(
      plans:,
      state:,
      bag: bag_of_base_3,
      by: 250_303,
      struck: [critical],
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects: by_other) == []
    as "a critical of a spell outside group 333 does not"
}

// ---- 182: lands a taunt ----

/// A hit on the creature that puts this state on it.
fn controlling(
  unit_id unit_id: Int,
  tell tell: strike_tell.ControlTell,
) -> cast_state.Struck {
  cast_state.Hit(
    unit_id:,
    unit: support.first_life,
    descriptions: [blow(result: combat_result.Hit, killed: 0)],
    controls: [
      strike_tell.ControlLanded(tell:, ends_at_ms: 6000, interrupted: None),
    ],
    armor_removed: 0,
    ticking: [],
  )
}

pub fn proc_taunt_landed_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 182 is 'lands a taunt' (text
  // 'Landing a Taunt'). A go whose foe answer lists a Taunt state raises it at that foe.
  let #(plans, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.LandsTaunt,
          casts: 250_201,
          aim: spell_plan.AtOtherUnit,
        ),
      ],
      school: 2,
    )
  let struck = [
    controlling(
      unit_id: 31,
      tell: crowd_control_support.holding(
        state: crowd_control_state.Taunt,
        duration_ms: 5000,
        instance_id: 1,
      ),
    ),
    controlling(
      unit_id: 32,
      tell: crowd_control_support.stagger_stun(instance_id: 2),
    ),
  ]
  let #(_, effects) = hit_with(plans:, state:, struck:, at: 1000)
  assert starts_at(spell4_id: 250_201, effects:) == [31]
    as "the taunted foe raises it; the stunned one does not"
}

// ---- 11: starts to move ----

/// The movement state of a character that has just entered, then given these state flags.
fn moving_with(
  state state: movement.State,
  flags flags: Int,
) -> movement.State {
  let assert Ok(next) =
    movement.moved(
      state:,
      moves: movement.Moves(client_clock: 0x1234, commands: [
        movement.StateFlags(flags:),
      ]),
    )
    as "the flags are within the client's 18 bits"
  next
}

/// How many times the kind 11 proc fires when the connection reports the change from one
/// movement state to the next.
fn move_fires(from from: movement.State, to to: movement.State) -> Int {
  let #(_, state) =
    holder_and_hitter(
      procs: [
        firing(
          id: 1,
          trigger: spell_plan.StartsMoving,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        ),
      ],
      school: 2,
    )
  let facts = case movement.started_moving(from:, to:) {
    True -> [cast_state.StartedMoving]
    False -> []
  }
  let #(_, effects) =
    support.then_procs(
      step: #(cast.raised(cast: state, facts:), []),
      caster: planted_caster(),
      at: 2000,
    )
  starts_of(spell4_id: 250_201, effects:)
}

pub fn proc_moving_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 11 is 'it moves' (text
  // 'Whenever the target or an enemy near the target moves'). `movement_command.kind_24`:
  // the client sends flag 0x1 when the velocity is near zero with no move asked and 0x2
  // when a move is asked and the velocity is not near zero, so 0x2 is moving; 0x100 is on
  // the ground.
  let entered =
    movement.entered(
      place: place_support.live_character_place(),
      session_epoch: character_support.epoch(3),
    )
  let still = moving_with(state: entered, flags: 0x1)
  let moving = moving_with(state: still, flags: 0x2)
  let moving_on_ground = moving_with(state: moving, flags: 0x102)
  let stopped = moving_with(state: moving_on_ground, flags: 0x1)
  assert move_fires(from: entered, to: still) == 0
    as "standing to still is not a start"
  assert move_fires(from: still, to: moving) == 1
    as "standing to moving fires once"
  assert move_fires(from: moving, to: moving_on_ground) == 0
    as "a second update while moving does not"
  assert move_fires(from: moving_on_ground, to: stopped) == 0
    as "a stop does not"
}

// ---- 87 and 105: the class resource ----

/// How many times a proc of this kind, gated by the Prerequisite row of one condition set,
/// fires when the connection reports the holder's slot going from `from` to `to`, with the
/// holder then at `to`.
fn resource_fires(
  trigger trigger: spell_plan.Trigger,
  gate_id gate_id: Int,
  conditions conditions: List(#(Int, Int, Int, Int)),
  class_id class_id: Int,
  slot slot: Int,
  from from: Float,
  to to: Float,
) -> Int {
  let gate =
    prerequisite_support.loaded(id: gate_id, rows: [
      prerequisite_support.row(id: gate_id, flags: 0, conditions:),
    ])
  let #(_, state) =
    holder_and_hitter(
      procs: [
        ProcRow(
          ..firing(id: 1, trigger:, casts: 250_201, aim: spell_plan.AtHolder),
          holder_gate: Some(gate),
        ),
      ],
      school: 2,
    )
  let state =
    cast.raised(cast: state, facts: [
      cast_state.ResourceMoved(slot:, from:, to:),
    ])
  let caster =
    support.caster_holding(resources: support.holding(class_id:, value: to))
  assert class_resource.slot(resources: caster.resources) == slot
    as "the class holds the slot the change names"
  let #(_, effects) = support.then_procs(step: #(state, []), caster:, at: 2000)
  starts_of(spell4_id: 250_201, effects:)
}

pub fn proc_resource_crossed_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 87 is 'its class resource
  // crosses a value' (texts 'between # and # Volatility', 'While above # Kinetic Energy').
  // The row's holder gate (dataBits09) says which value: Prerequisite 22338 holds Vital 6,
  // the Warrior's Volatility (slot 1 shown as Vital 6), at least 25 percent of its maximum
  // (type 71, comparison 4) and at most 75 (comparison 6). The Warrior's maximum is 1000.
  // A change is an event whatever its direction; the gate decides on the value the change
  // ends at, so a change that stays inside the range fires too (a guess).
  let fires = fn(from, to) {
    resource_fires(
      trigger: spell_plan.ResourceCrosses,
      gate_id: 22_338,
      conditions: [#(71, 4, 6, 25), #(71, 6, 6, 75)],
      class_id: 1,
      slot: 1,
      from:,
      to:,
    )
  }
  assert fires(100.0, 300.0) == 1
    as "10 percent to 30 percent crosses into the range"
  assert fires(300.0, 900.0) == 0
    as "30 percent to 90 percent leaves it: the gate fails at 90"
  assert fires(100.0, 200.0) == 0 as "10 percent to 20 percent stays below it"
}

pub fn proc_suit_power_drops_fires_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 105 is 'its suit power drops
  // below a value' (text 530326). The Stalker's resource is slot 3, shown as Vital 8; the
  // holder gate Prerequisite 31382 is Vital 8 below 30 percent (type 71, comparison 5) of
  // its maximum, 100. Only a fall is an event.
  let drops = fn(from, to) {
    resource_fires(
      trigger: spell_plan.SuitPowerDrops,
      gate_id: 31_382,
      conditions: [#(71, 5, 8, 30)],
      class_id: 5,
      slot: 3,
      from:,
      to:,
    )
  }
  assert drops(40.0, 20.0) == 1 as "a fall from 40 to 20 ends below 30 percent"
  assert drops(20.0, 40.0) == 0 as "a rise raises nothing"
  assert drops(80.0, 60.0) == 0
    as "a fall that ends above 30 percent fails the gate"
}

// ---- the order inside one step ----

pub fn proc_events_in_order_test() -> Nil {
  use <- owned_test.run(60_000)
  // The design of the step: an input's own events come first, then its heals, then the
  // facts raised as the input ran (a use of an ability, then a payment), then the stealth
  // change. No one input holds all four groups, so two inputs show the order: a press that
  // uses an ability and pays, and a go that hits, heals and enters stealth. Each proc is
  // listed in the reverse of the expected order.
  let spender =
    Spell(..support.child(spell4_id: 250_302, base: 1), costs: [
      spell_plan.SlotCost(slot: 1, amount: 3, result: 51),
    ])
  let paying_holder =
    holding(spell4_id: 250_101, procs: [
      firing(
        id: 1,
        trigger: spell_plan.SpendsResource,
        casts: 250_202,
        aim: spell_plan.AtHolder,
      ),
      firing(
        id: 2,
        trigger: spell_plan.UsesAbility,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let plans = support.plans_of([paying_holder, spender])
  let #(state, _) = planted_joined(plans:, spell: paying_holder, at: 500)
  let #(_, pressed) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: planted_caster(),
      bag_index: bag_of_base_1,
      target: 0,
      at: 1000,
    )
  assert starts_in_order(effects: pressed) == ["start 250201", "start 250202"]
    as "the ability is used before its cost is paid"
  let all_four =
    support.with_effects(
      spell: support.with_effects(
        spell: Spell(..hitter(school: 2), stealth_change: KeepsStealth),
        kinds: [spell_plan.HealEffect(heal(id: 1, delay_ms: 0))],
      ),
      kinds: [
        spell_plan.StealthEffect(support.stealth_row(
          id: 250_902,
          breaks: KeptOnDamage,
        )),
      ],
    )
  let acting_holder =
    holding(spell4_id: 250_101, procs: [
      firing(
        id: 1,
        trigger: EnteredStealth,
        casts: 250_204,
        aim: spell_plan.AtHolder,
      ),
      firing(
        id: 2,
        trigger: spell_plan.ReceivesHeal,
        casts: 250_203,
        aim: spell_plan.AtHolder,
      ),
      firing(
        id: 3,
        trigger: spell_plan.LandsHeal,
        casts: 250_202,
        aim: spell_plan.AtHolder,
      ),
      firing(
        id: 4,
        trigger: spell_plan.LandsHit,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let plans = support.plans_of([acting_holder, all_four])
  let #(state, _) = planted_joined(plans:, spell: acting_holder, at: 500)
  let #(_, went) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  assert starts_in_order(effects: went)
    == ["start 250201", "start 250202", "start 250203", "start 250204"]
    as "the hit, the heal it lands, the heal received, then the stealth"
}

// ---- part B of the triggers: blows taken ----
//
// Every reading here is a guess: no client code reads a Proc row, so the kinds rest on the texts of
// `Spell4Effects.effectType.14.dataBits00.fairly_sure`. A creature's blow on the holder is an event
// whose other unit is the creature and whose spell is the creature's attack spell.

/// The holder's plans, state and caster with these procs, the passive started at 500.
fn holder_of_taken(procs procs: List(ProcRow)) -> #(Plans, State, Caster) {
  let holder = holding(spell4_id: 250_101, procs:)
  let plans = support.plans_of([holder])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  #(plans, state, planted_caster())
}

/// The caster takes this blow at this time, and the procs it raises fire.
fn taking(
  state state: State,
  caster caster: Caster,
  blow blow: cast_proc.BlowTaken,
  at ms: Int,
) -> #(State, List(Effect)) {
  blow_taken(cast: state, caster:, now: support.at(ms:), blow:)
}

/// A blow of the creature `striker` by an attack spell of these groups that lowered the
/// holder's health.
fn lowering_by(
  striker striker: Int,
  groups groups: List(Int),
) -> cast_proc.BlowTaken {
  cast_proc.BlowLanded(
    striker:,
    spell: attack(groups:),
    lowered: True,
    critical: False,
    shield_depleted: False,
  )
}

/// A blow of creature 31 that the holder deflected.
fn deflected() -> cast_proc.BlowTaken {
  cast_proc.BlowDeflected(striker: 31, spell: attack(groups: []))
}

pub fn a_kind_16_proc_fires_when_the_holder_takes_damage_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00: kind 16 is 'takes damage'. 178239 of Spell4
  // 38784 (Nano Skin: Lethal) casts 72838 at the holder (dataBits03 9), chance 1.0, once
  // every 1000 ms (Spell4Effects.effectType.14.limits).
  let #(_, state, caster) =
    holder_of_taken(procs: [
      proc(
        id: 178_239,
        trigger: spell_plan.TakesDamage,
        casts: cast_of_proc(spell4_id: 72_838),
        window_ms: 1000,
        count: 1,
      ),
    ])
  let #(state, first) = taking(state:, caster:, blow: lowering(), at: 1000)
  assert starts_at(spell4_id: 72_838, effects: first) == [7]
    as "a blow that lowered the holder's health casts 72838 at the holder"
  let #(state, early) = taking(state:, caster:, blow: lowering(), at: 1500)
  assert starts_at(spell4_id: 72_838, effects: early) == []
    as "500 ms later the 1000 ms window still holds it"
  let #(state, none) =
    taking(
      state:,
      caster:,
      blow: landed(lowered: False, critical: False, shield_depleted: False),
      at: 2500,
    )
  assert starts_at(spell4_id: 72_838, effects: none) == []
    as "a landed blow that lowered nothing is no damage taken"
  let #(_, later) = taking(state:, caster:, blow: lowering(), at: 2600)
  assert starts_at(spell4_id: 72_838, effects: later) == [7]
    as "1600 ms after its fire a blow fires it again"
}

pub fn a_kind_16_proc_does_not_fire_on_a_deflect_or_on_a_critical_that_lowered_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kind 16 is 'takes damage' (`Spell4Effects.effectType.14.dataBits00`): the deflect of
  // kind 51 and the critical of kind 146 are not it unless the blow also lowered the
  // absorbs, the shield or the health.
  let #(_, state, caster) =
    holder_of_taken(procs: [
      firing(
        id: 1,
        trigger: spell_plan.TakesDamage,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let #(state, refused) = taking(state:, caster:, blow: deflected(), at: 1000)
  assert starts_at(spell4_id: 250_201, effects: refused) == []
    as "a deflected blow takes no damage"
  let #(state, absorbed) =
    taking(
      state:,
      caster:,
      blow: landed(lowered: False, critical: True, shield_depleted: False),
      at: 2000,
    )
  assert starts_at(spell4_id: 250_201, effects: absorbed) == []
    as "a critical that lowered nothing takes no damage"
  let #(_, lowered) =
    taking(
      state:,
      caster:,
      blow: landed(lowered: True, critical: True, shield_depleted: False),
      at: 3000,
    )
  assert starts_at(spell4_id: 250_201, effects: lowered) == [7]
    as "a critical that lowered something does"
}

pub fn a_kind_146_proc_fires_on_a_critical_blow_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 146 is 'suffers a critical'.
  // The blow counts even when the absorbs took all of it, which lowered nothing.
  let #(_, state, caster) =
    holder_of_taken(procs: [
      firing(
        id: 1,
        trigger: spell_plan.SuffersCritical,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let #(state, plain) = taking(state:, caster:, blow: lowering(), at: 1000)
  assert starts_at(spell4_id: 250_201, effects: plain) == []
    as "a blow that is no critical does not fire it"
  let #(state, absorbed) =
    taking(
      state:,
      caster:,
      blow: landed(lowered: False, critical: True, shield_depleted: False),
      at: 2000,
    )
  assert starts_at(spell4_id: 250_201, effects: absorbed) == [7]
    as "a critical the absorbs took all of fires it"
  let #(_, refused) = taking(state:, caster:, blow: deflected(), at: 3000)
  assert starts_at(spell4_id: 250_201, effects: refused) == []
    as "a deflected blow is no critical"
}

pub fn a_kind_51_proc_fires_on_a_deflect_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 51 is 'deflects an attack'.
  let #(_, state, caster) =
    holder_of_taken(procs: [
      firing(
        id: 1,
        trigger: spell_plan.DeflectsAttack,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let #(state, landing) = taking(state:, caster:, blow: lowering(), at: 1000)
  assert starts_at(spell4_id: 250_201, effects: landing) == []
    as "a landed blow is no deflect"
  let #(_, refused) = taking(state:, caster:, blow: deflected(), at: 2000)
  assert starts_at(spell4_id: 250_201, effects: refused) == [7]
    as "a deflected blow fires it at the holder"
}

pub fn a_kind_115_proc_fires_when_the_shield_is_depleted_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits00.fairly_sure: kind 115 is 'shield depleted'.
  let #(_, state, caster) =
    holder_of_taken(procs: [
      firing(
        id: 1,
        trigger: spell_plan.ShieldDepleted,
        casts: 250_201,
        aim: spell_plan.AtHolder,
      ),
    ])
  let #(state, plain) = taking(state:, caster:, blow: lowering(), at: 1000)
  assert starts_at(spell4_id: 250_201, effects: plain) == []
    as "a blow that did not take the shield from above 0 to 0 does not fire it"
  let #(_, depleted) =
    taking(
      state:,
      caster:,
      blow: landed(lowered: True, critical: False, shield_depleted: True),
      at: 2000,
    )
  assert starts_at(spell4_id: 250_201, effects: depleted) == [7]
    as "a blow that took the shield to 0 fires it"
}

pub fn a_bit_4_taken_proc_casts_at_the_striking_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits03: bit 4 casts at the event's other unit, which for
  // a blow taken is the creature that struck; a row without it casts at the holder.
  let #(_, state, caster) =
    holder_of_taken(procs: [
      firing(
        id: 1,
        trigger: spell_plan.TakesDamage,
        casts: 250_201,
        aim: spell_plan.AtOtherUnit,
      ),
      firing(
        id: 2,
        trigger: spell_plan.TakesDamage,
        casts: 250_202,
        aim: spell_plan.AtHolder,
      ),
    ])
  let #(_, effects) = taking(state:, caster:, blow: lowering(), at: 1000)
  assert starts_at(spell4_id: 250_201, effects:) == [31]
  assert starts_at(spell4_id: 250_202, effects:) == [7]
}

pub fn a_taken_proc_filtered_by_group_fires_only_for_an_attack_spell_in_the_group_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.effectType.14.dataBits07: the filter names a spell group
  // (`0x140561d80`: groups from Spell4GroupList); the spell the filter reads is the
  // creature's attack spell.
  let #(_, state, caster) =
    holder_of_taken(procs: [
      ProcRow(
        ..firing(
          id: 1,
          trigger: spell_plan.TakesDamage,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        ),
        filter: spell_plan.InGroup(group_id: 333),
      ),
    ])
  let #(state, outside) =
    taking(
      state:,
      caster:,
      blow: lowering_by(striker: 31, groups: [444]),
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects: outside) == []
    as "an attack spell in another group does not fire it"
  let #(state, none) =
    taking(
      state:,
      caster:,
      blow: lowering_by(striker: 31, groups: []),
      at: 2000,
    )
  assert starts_at(spell4_id: 250_201, effects: none) == []
    as "an attack spell in no group does not"
  let #(_, inside) =
    taking(
      state:,
      caster:,
      blow: lowering_by(striker: 31, groups: [444, 333]),
      at: 3000,
    )
  assert starts_at(spell4_id: 250_201, effects: inside) == [7]
    as "an attack spell in group 333 does"
}

pub fn an_event_gate_on_the_striker_reads_it_as_the_casters_picture_shows_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // Prerequisite 37038 (`Prerequisite.prerequisiteTypeId.50`): the unit is under the
  // holder's cast of Spell4 79220. As the event gate of a proc of blows taken it reads the
  // creature that struck, by the casts the holder holds on it.
  let gate =
    prerequisite_support.single(id: 37_038, condition: #(50, 1, 464, 79_220))
  let holder =
    holding(spell4_id: 250_101, procs: [
      ProcRow(
        ..firing(
          id: 1,
          trigger: spell_plan.TakesDamage,
          casts: 250_201,
          aim: spell_plan.AtHolder,
        ),
        event_gate: Some(gate),
      ),
    ])
  let marking =
    support.with_effects(
      spell: support.child(spell4_id: 79_220, base: 3),
      kinds: [
        spell_plan.LastingEffect(spell_plan.Lasting(
          effect_id: Spell4EffectsId(250_901),
          phase_flags: -1,
          aim: spell_plan.AimsAtArea,
          row: LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
          condition: Always,
          tag: spend.always,
        )),
      ],
    )
  let plans = support.plans_of([holder, marking])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let caster = planted_caster()
  let #(state, bare) =
    taking(
      state:,
      caster:,
      blow: lowering_by(striker: 31, groups: []),
      at: 1000,
    )
  assert starts_at(spell4_id: 250_201, effects: bare) == []
    as "no 79220 holds a node on the creature: the gate fails"
  let #(state, _) =
    striking(
      plans:,
      state:,
      bag: bag_of_base_3,
      by: 79_220,
      struck: [plain_hit(unit_id: 31)],
      at: 2000,
    )
  let #(state, marked) =
    taking(
      state:,
      caster:,
      blow: lowering_by(striker: 31, groups: []),
      at: 3000,
    )
  assert starts_at(spell4_id: 250_201, effects: marked) == [7]
    as "while 79220's node is on the creature that struck, the gate passes"
  let #(_, other) =
    taking(
      state:,
      caster:,
      blow: lowering_by(striker: 32, groups: []),
      at: 4000,
    )
  assert starts_at(spell4_id: 250_201, effects: other) == []
    as "a creature 79220 does not hold fails"
}

pub fn damage_breaks_stealth_only_on_a_lowered_blow_as_before_test() -> Nil {
  use <- owned_test.run(60_000)
  // A source kept off by damage ends on a blow that lowered something, as before; a deflect
  // and a landed blow that lowered nothing leave the stealth, so no proc of leaving it fires.
  let left = cast_of_proc(spell4_id: 250_202)
  let holder =
    holding(spell4_id: 250_101, procs: [
      proc(id: 1, trigger: LeftStealth, casts: left, window_ms: 500, count: 1),
    ])
  let plans = support.plans_of([broken_by_damage_spell(), holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let #(state, refused) = taking(state:, caster:, blow: deflected(), at: 2100)
  assert starts_of(spell4_id: 250_202, effects: refused) == 0
    as "a deflect does not break the stealth"
  let #(state, absorbed) =
    taking(
      state:,
      caster:,
      blow: landed(lowered: False, critical: True, shield_depleted: False),
      at: 2200,
    )
  assert starts_of(spell4_id: 250_202, effects: absorbed) == 0
    as "a landed blow that lowered nothing does not"
  let #(_, lowered) = taking(state:, caster:, blow: lowering(), at: 2300)
  assert starts_of(spell4_id: 250_202, effects: lowered) == 1
    as "a blow that lowered something ends the stealth, and the proc of leaving it fires"
}

pub fn a_proxy_aimed_at_the_primary_target_of_a_proc_cast_at_another_unit_starts_its_child_on_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // A proc cast at the unit a hit struck has that creature as its primary target (`cast`
  // `proc_started`), but only a bag press names a player for a Proxy aimed at the primary
  // target (`spell_plan.OnPrimaryTarget`) to start its child on: the child of the proc's spell
  // starts on the holder, unit 7, as a child of a Proxy aimed at the caster does.
  let child = cast_of_proc(spell4_id: 250_202)
  let fired =
    spell_plan.with_proxies(spell: cast_of_proc(spell4_id: 250_201), proxies: [
      spell_plan.Proxy(
        period: None,
        effect_id: Spell4EffectsId(90_002),
        delay_ms: 0,
        phase_flags: -1,
        condition: Always,
        tag: spend.always,
        target: spell_plan.OnPrimaryTarget,
        spell: child,
        gains: [],
      ),
    ])
  let holder =
    holding(spell4_id: 250_101, procs: [
      ProcRow(
        ..proc(
          id: 1,
          trigger: spell_plan.LandsHit,
          casts: fired,
          window_ms: 500,
          count: 1,
        ),
        aim: spell_plan.AtOtherUnit,
      ),
    ])
  let plans = support.plans_of([holder, hitter(school: 2)])
  let #(state, _) = planted_joined(plans:, spell: holder, at: 500)
  let #(_, effects) =
    hit_with(plans:, state:, struck: [plain_hit(unit_id: 31)], at: 1000)
  assert started_of(spell4_id: 250_201, effects:).primary_target_unit_id == 31
    as "the proc's spell is cast at the creature the hit struck"
  assert started_of(spell4_id: 250_202, effects:).primary_target_unit_id == 7
    as "its Proxy aimed at the primary target starts the child on the holder, not on the creature"
}

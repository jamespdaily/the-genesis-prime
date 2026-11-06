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
import client_tables
import genesis_prime/client_connection
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  type Plans, type ProcRow, type Spell, AliveOrDead, Always, BrokenByDamage,
  Died, EnteredStealth, KeepsStealth, KeptOnDamage, LeftCombat, LeftStealth,
  ProcRow, RemoveStealthRow, Spell, StealthRow,
}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties
import genesis_prime/message/cast_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/step.{ConnectionId, LogDebug}
import genesis_prime/table/id.{
  Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import prerequisite_support
import unitest

// ---- the Stalker, from the client's tables ----

fn real_plans() -> Plans {
  spell_plan.plans(client_tables.shared())
}

/// A Stalker: its three level-1 abilities (Shred, Impale, Stagger) and its innate, Nano
/// Skin: Lethal, at bag index 3.
fn stalker(in_combat in_combat: Bool) -> Caster {
  cast.Caster(
    ..support.caster(),
    abilities: list.map([23_148, 23_161, 23_173, 30_075], Spell4BaseId),
    in_combat:,
  )
}

fn dead(caster caster: Caster) -> Caster {
  cast.Caster(..caster, dead: True)
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
    cast.passive_started(
      cast: cast.new(),
      caster:,
      plans: real_plans(),
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
  let #(state, effects) =
    support.pressed_raw_in(
      plans: real_plans(),
      state:,
      caster:,
      bag_index: 3,
      target: 0,
      at: ms,
    )
  answered(caster:, state:, effects:, at: ms)
}

/// A press of the Stalker's first ability, Shred, with its goes answered.
fn shredded(
  state state: State,
  caster caster: Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans: real_plans(),
      state:,
      caster:,
      bag_index: 0,
      target: 0,
      at: ms,
    )
  answered(caster:, state:, effects:, at: ms)
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
      cast.Send(frame:) ->
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
      cast.StealthChanged(stealthed: True) -> ["stealth on"]
      cast.StealthChanged(stealthed: False) -> ["stealth off"]
      cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Strike(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeStarts(..)
      | cast.CasterChangeEnds(..) -> []
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
  list.flat_map(
    support.frames_of(message_id: spell_go.message_id, effects:),
    fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      list.filter(go.targets, fn(target) { target.unit_id == 7 })
      |> list.flat_map(fn(target) {
        list.map(target.effects, fn(effect) { effect.spell4_effects_id })
      })
    },
  )
}

fn is_strike(effect effect: Effect) -> Bool {
  case effect {
    cast.Strike(..) -> True
    cast.Send(..)
    | cast.Tell(..)
    | cast.StartTimer(..)
    | cast.CancelTimer(..)
    | cast.Log(..)
    | cast.Pay(..)
    | cast.Gain(..)
    | cast.CasterChangeStarts(..)
    | cast.CasterChangeEnds(..)
    | cast.StealthChanged(..) -> False
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
    window_ms:,
    count:,
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition: Always,
    tag: spend.always,
  )
}

/// A spell that holds these procs and nothing else.
fn holding(spell4_id spell4_id: Int, procs procs: List(ProcRow)) -> Spell {
  Spell(
    ..support.child(spell4_id:, base: spell4_id),
    procs:,
    stealth_change: KeepsStealth,
  )
}

fn plans_of(spells: List(Spell)) -> Plans {
  support.with_spells(plans: support.plans(), spells:)
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
    cast.passive_started(
      cast: cast.new(),
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
  answered(caster:, state:, effects:, at: ms)
}

fn stealth_row(
  id id: Int,
  breaks breaks: spell_plan.Breaks,
) -> spell_plan.StealthRow {
  StealthRow(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    breaks:,
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition: Always,
    tag: spend.always,
  )
}

/// The spell of base 1 that holds a stealth damage does not end, as 95774 does.
fn stealthing() -> Spell {
  Spell(
    ..support.child(spell4_id: 38_913, base: 1),
    stealth: [stealth_row(id: 95_774, breaks: KeptOnDamage)],
    stealth_change: KeepsStealth,
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
  assert cast.stealthed(cast: state) == False
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

fn property_starts(
  effects effects: List(Effect),
) -> List(#(unit_properties.Source, unit_properties.Modifier)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.CasterChangeStarts(source:, change: cast.Property(modifier:)) ->
        Ok(#(source, modifier))
      cast.CasterChangeStarts(change: cast.ShieldHeal(..), ..) -> Error(Nil)
      cast.CasterChangeStarts(change: cast.Look(..), ..) -> Error(Nil)
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Strike(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeEnds(..)
      | cast.StealthChanged(..) -> Error(Nil)
    }
  })
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
    property_starts(effects:)
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
    support.property_ends(effects: step.1) == []
  })
    as "nothing ends before the 3000 ms"
  let #(_, later) = support.run_timers(state:, effects:, from_ms: 3000)
  let ended =
    list.filter(later, fn(step) { support.property_ends(effects: step.1) != [] })
  assert list.unique(list.map(ended, fn(step) { step.0 })) == [6000]
    as "Spell4.79932: durationTime 3000 after the go at 3000"
  let ending = list.flat_map(ended, fn(step) { step.1 })
  assert list.map(support.property_ends(effects: ending), fn(source) {
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
    cast.damage_taken(cast: state, caster:, now: support.at(ms: 2500))
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
  let plans = plans_of([stealthing(), two_goes, holder])
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
  let plans = plans_of([broken_by_damage_spell(), holder])
  let caster = planted_caster()
  let damaged = fn(state, at) {
    let #(state, effects) =
      cast.damage_taken(cast: state, caster:, now: support.at(ms: at))
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
  assert cast.stealthed(cast: early) as "the stealth itself is entered"
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
  Spell(
    ..support.child(spell4_id: 38_914, base: 1),
    stealth: [stealth_row(id: 83_834, breaks: BrokenByDamage)],
    stealth_change: KeepsStealth,
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
  let plans = plans_of([broken_by_damage_spell(), holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let cycle = fn(state, at) {
    let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at:)
    let #(state, struck) =
      cast.damage_taken(cast: state, caster:, now: support.at(ms: at + 100))
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
  let plans = plans_of([holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 0)
  let leaves = fn(state, at) {
    let #(state, effects) =
      cast.combat_left(cast: state, caster:, now: support.at(ms: at))
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
    cast.passive_started(
      cast: cast.new(),
      caster:,
      plans: real_plans(),
      base: Spell4BaseId(29_131),
      now: support.at(ms: 1000),
    )
  let assert [cast.Strike(passive_go)] = list.filter(started, is_strike)
  assert cast.rolls_needed(
      cast: held,
      cast_id: passive_go.cast_id,
      phase: passive_go.phase,
      struck: [],
    )
    == 0
    as "Spell4Effects.effectType.14.limits: every read row has chance 1.0, so the go that applies the procs needs no roll"
  let #(held, _) = answered(caster:, state: held, effects: started, at: 1000)
  let #(state, pressed) =
    support.pressed_raw_in(
      plans: real_plans(),
      state: held,
      caster:,
      bag_index: 3,
      target: 0,
      at: 2000,
    )
  let assert [cast.Strike(toggle_go)] = list.filter(pressed, is_strike)
  let #(state, going) =
    support.went(
      cast: state,
      caster:,
      now: support.at(ms: 2000),
      cast_id: toggle_go.cast_id,
      phase: toggle_go.phase,
      struck: [],
    )
  let assert [cast.Strike(stealth_go)] = list.filter(going, is_strike)
  assert cast.rolls_needed(
      cast: state,
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
    cast.died(cast: entered, caster: dead(caster:), now: support.at(ms: 3000))
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
    cast.damage_taken(
      cast: state,
      caster: dead(caster:),
      now: support.at(ms: 2100),
    )
  let #(_, effects) =
    answered(caster: dead(caster:), state:, effects: struck, at: 2100)
  assert starts_of(spell4_id: 60_769, effects:) == 0
  assert starts_of(spell4_id: 79_932, effects:) == 0
    as "Spell4.spell4ConditionsIdCaster: row 1 (mask 225) refuses a dead caster, as the client refuses its press (cast.dead_player)"
  assert list.any(support.logs(effects:), fn(line) {
    line.0 == LogDebug
    && string.contains(line.1, "60769")
    && string.contains(line.1, "147132")
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
    Spell(
      ..holder,
      procs: list.map(holder.procs, fn(row) { ProcRow(..row, spell: living) }),
    )
  let plans = plans_of([broken_by_damage_spell(), holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let #(state, struck) =
    cast.damage_taken(
      cast: state,
      caster: dead(caster:),
      now: support.at(ms: 2100),
    )
  let #(state, refused) =
    answered(caster: dead(caster:), state:, effects: struck, at: 2100)
  assert starts_of(spell4_id: 250_202, effects: refused) == 0
  let #(state, _) = planted_press(plans:, state:, bag: bag_of_base_1, at: 2200)
  let #(state, struck) =
    cast.damage_taken(cast: state, caster:, now: support.at(ms: 2300))
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
  let #(state, effects) =
    cast.died(cast: state, caster: dead, now: support.at(ms:))
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
      plans: real_plans(),
      state: dead_state,
      caster: woken,
      bag_index: 3,
      target: 0,
      at: 3100,
    )
  assert support.refusal_results(effects: press) == []
    as "the cooldown left is 150 ms, inside the 500 ms window the client queues"
  let #(without, _) = toggled(state: cast.new(), caster: in_combat, at: 1000)
  let #(without, _) =
    cast.died(
      cast: without,
      caster: dead(caster: in_combat),
      now: support.at(ms: 3000),
    )
  let #(_, control) =
    support.pressed_raw_in(
      plans: real_plans(),
      state: without,
      caster: woken,
      bag_index: 3,
      target: 0,
      at: 3100,
    )
  assert support.refusal_results(effects: control) == [15]
    as "the control: a player who held no passive has 22 s of cooldown left, refused 15"
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
      plans: real_plans(),
      state:,
      caster: out,
      bag_index: 3,
      target: 0,
      at: 5100,
    )
  assert support.refusal_results(effects: before) == [15]
    as "the control: in combat the Stealth button's 25000 ms cooldown stands"
  let leaves = fn(state, at) {
    let #(state, effects) =
      cast.combat_left(cast: state, caster: out, now: support.at(ms: at))
    answered(caster: out, state:, effects:, at:)
  }
  let #(state, first) = leaves(state, 5000)
  assert trace(effects: first, earlier: [], pressed: 0)
    == ["start 63366", "go 63366", "end 63366"]
    as "Spell4Effects.effectType.14.dataBits00.0_44: 159136, kind 44, casts 63366"
  let #(_, after) =
    support.pressed_raw_in(
      plans: real_plans(),
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
  let plans = plans_of([stealthing(), holder])
  let #(state, joined_effects) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, entered) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  let caster = dead(caster: planted_caster())
  let #(state, effects) =
    cast.died(cast: state, caster:, now: support.at(ms: 3000))
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
    Spell(
      ..support.child(spell4_id: 38_783, base: 2),
      removes: [
        spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(83_832),
          phase_flags: -1,
          aim: spell_plan.AimsAtCaster,
          selector: lasting.Spell(Spell4Id(250_101)),
          count: 1,
          condition: Always,
          tag: spend.always,
        ),
      ],
      remove_stealth: [
        RemoveStealthRow(
          effect_id: Spell4EffectsId(83_833),
          phase_flags: -1,
          condition: Always,
          tag: spend.always,
        ),
      ],
      stealth_change: KeepsStealth,
    )
  let plans = plans_of([stealthing(), removing, holder])
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
  assert cast.stealthed(cast: state) == False
  // A go that applies a holder and enters stealth in one input.
  let applier =
    Spell(
      ..support.child(spell4_id: 38_915, base: 3),
      stealth: [stealth_row(id: 95_775, breaks: KeptOnDamage)],
      procs: [
        proc(
          id: 5,
          trigger: EnteredStealth,
          casts: cast_of_proc(spell4_id: 250_203),
          window_ms: 500,
          count: 1,
        ),
      ],
      stealth_change: KeepsStealth,
    )
  let plans = plans_of([applier])
  let #(_, entering) =
    planted_press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
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
    Spell(..cast_of_proc(spell4_id: 250_201), remove_stealth: [
      RemoveStealthRow(
        effect_id: Spell4EffectsId(250_901),
        phase_flags: -1,
        condition: Always,
        tag: spend.always,
      ),
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
  let plans = plans_of([stealthing(), holder])
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
  let #(state, left) = cast.left(cast: state)
  assert support.writes(effects: left) == []
    as "a camp writes nothing, and leaving stealth is no event"
  assert list.filter(left, is_strike) == []
  let #(state, started) =
    cast.passive_started(
      cast: state,
      caster:,
      plans: real_plans(),
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
    Spell(
      ..support.child(spell4_id: 38_783, base: 2),
      removes: [
        spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(83_832),
          phase_flags: -1,
          aim: spell_plan.AimsAtCaster,
          selector: lasting.Spell(Spell4Id(250_101)),
          count: 1,
          condition: Always,
          tag: spend.always,
        ),
      ],
      stealth_change: KeepsStealth,
    )
  let plans = plans_of([holder, removing])
  let caster = planted_caster()
  let #(state, pressed) =
    planted_press(plans:, state: cast.new(), bag: bag_of_base_1, at: 0)
  let leaves = fn(state, at) {
    let #(state, effects) =
      cast.combat_left(cast: state, caster:, now: support.at(ms: at))
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
  let plans = plans_of([stealthing(), holder])
  let caster = planted_caster()
  let #(state, _) = planted_joined(plans:, spell: holder, at: 1000)
  let #(state, first) =
    planted_press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert starts_of(spell4_id: 250_201, effects: first) == 1
  let #(state, _) = cast.left(cast: state)
  let #(state, started) =
    cast.passive_started(
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
  let plans = plans_of([bound, holder])
  let in_combat = cast.Caster(..planted_caster(), in_combat: True)
  let out = cast.Caster(..planted_caster(), in_combat: False)
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
  assert cast.stealthed(cast: state)
  let #(state, effects) =
    cast.persisted(cast: state, caster: out, now: support.at(ms: 3000))
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
  let plans = plans_of([holder])
  let caster = planted_caster()
  let #(state, pressed) =
    planted_press(plans:, state: cast.new(), bag: bag_of_base_1, at: 1000)
  assert list.any(support.logs(effects: pressed), fn(line) {
    line.0 == LogDebug && string.contains(line.1, "not the innate passive")
  })
    as "the go says the proc is not held"
  let #(state, dying) =
    cast.died(cast: state, caster: dead(caster:), now: support.at(ms: 2000))
  let #(_, effects) =
    answered(caster: dead(caster:), state:, effects: dying, at: 2000)
  assert starts_of(spell4_id: 250_201, effects:) == 0
}

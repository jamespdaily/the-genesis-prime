//// What the two tooltip oracles (`tooltip_oracle_times_test`, `tooltip_oracle_effects_test`)
//// share: the committed rows and plans, the tokens of the planned abilities, the outcome
//// of comparing what a token prints with what the cast rule gives, the gaps a test lists
//// and the verdict on them, and a cast driven on a clock the test owns with the frames it
//// writes read back. It decides nothing about a token: each oracle module reads what its
//// own tokens print and what the rule gives.

import cast_support as support
import fixture_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/hit
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/game/strike_tell
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/step
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/table/loader/store
import genesis_prime/tooltip_token.{type Token}
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_life
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import spell_tables

// ---------------------------------------------------------------- what is asked

/// The rows a test reads: the tables a token prints from and the plans the cast rule is
/// driven with.
pub type Rows {
  Rows(tables: store.Tables, plans: Plans)
}

/// The client's committed rows and the plans built from them.
pub fn shared() -> Rows {
  Rows(tables: fixture_tables.shared(), plans: spell_tables.fixture_plans())
}

/// A token one planned ability's tooltip holds: the ability's Spell4Base id, the text
/// and the token.
pub type Asked {
  Asked(base: Int, text_id: Int, token: Token)
}

/// What a token prints against what the rule gives, or why the rule was not read.
pub type Outcome {
  Compared(asked: Asked, expected: Int, got: Int)
  Unobserved(asked: Asked, why: Unread)
}

/// A difference, as the test reports it: what the token prints and what the rule gives,
/// or why the rule was not read.
pub type Difference {
  Differs(ability: Int, text_id: Int, token: String, expected: Int, got: Int)
  LeftOut(ability: Int, text_id: Int, token: String, why: String)
}

/// A difference the test lists until the issue's work closes it.
pub type Gap {
  Gap(ability: Int, token: String, issue: String)
}

/// The planned abilities, by Spell4Base id.
pub fn planned(rows rows: Rows) -> List(Spell) {
  dict.to_list(rows.plans)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) { entry.1 })
}

/// Every token of every planned ability's tooltips, once for each ability, text and
/// token.
pub fn asked_of(rows rows: Rows) -> List(Asked) {
  let assert Ok(tokens) = tooltip_token.load()
    as "the committed token list loads"
  list.flat_map(planned(rows:), fn(root) {
    tooltip_token.of_spell(
      tables: rows.tables,
      tokens:,
      spell: root.spell4_id.value,
    )
    |> list.map(fn(found) {
      Asked(
        base: root.spell4_base_id.value,
        text_id: found.text_id,
        token: found.token,
      )
    })
  })
  |> list.unique
}

pub fn plan_of(rows rows: Rows, base base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(plans: rows.plans, base: Spell4BaseId(base))
    as "the plans hold the planned ability"
  spell
}

/// The asked tokens of this kind and these fields.
pub fn asked_with(
  asked asked: List(Asked),
  kind kind: tooltip_token.Kind,
  fields fields: List(String),
) -> List(Asked) {
  list.filter(asked, fn(entry) {
    entry.token.kind == kind && list.contains(fields, entry.token.field)
  })
}

/// The differences among the outcomes: a token whose two values differ, and a token the
/// rule was not read for.
pub fn differences(outcomes outcomes: List(Outcome)) -> List(Difference) {
  list.filter_map(outcomes, fn(outcome) {
    case outcome {
      Compared(asked:, expected:, got:) if expected != got ->
        Ok(Differs(
          ability: asked.base,
          text_id: asked.text_id,
          token: tooltip_token.describe(asked.token),
          expected:,
          got:,
        ))
      Compared(..) -> Error(Nil)
      Unobserved(asked:, why:) ->
        Ok(LeftOut(
          ability: asked.base,
          text_id: asked.text_id,
          token: tooltip_token.describe(asked.token),
          why: reason(unread: why),
        ))
    }
  })
}

/// The tokens whose two values were compared.
pub fn compared_count(outcomes outcomes: List(Outcome)) -> Int {
  list.count(outcomes, fn(outcome) {
    case outcome {
      Compared(..) -> True
      Unobserved(..) -> False
    }
  })
}

/// The tokens the rule was not read for.
pub fn left_out_count(outcomes outcomes: List(Outcome)) -> Int {
  list.length(outcomes) - compared_count(outcomes:)
}

/// What a test has to say of the differences: those no gap lists, and the gaps that
/// match no difference.
pub type Verdict {
  Verdict(unlisted: List(Difference), stale: List(Gap))
}

pub fn verdict(
  differences differences: List(Difference),
  gaps gaps: List(Gap),
) -> Verdict {
  let listed = fn(difference: Difference, gap: Gap) {
    difference.ability == gap.ability && difference.token == gap.token
  }
  Verdict(
    unlisted: list.filter(differences, fn(difference) {
      !list.any(gaps, listed(difference, _))
    }),
    stale: list.filter(gaps, fn(gap) { !list.any(differences, listed(_, gap)) }),
  )
}

/// Why a value could not be read: what a token prints or what the rule gives.
pub type Unread {
  NoRow
  UnknownField(field: String)
  Refused(results: List(Int))
  NeverFinished
  NeverApplied
  CastsStarted(count: Int)
  NodeHeldBy(effect_id: Int)
  ModifierChanges(count: Int)
  PressNotHeld
  CooldownNotBracketed
  NoCooldownForMethod
  NotPeriodicProxy
  HeldAs(list: String)
  NotInPlan
}

pub fn reason(unread unread: Unread) -> String {
  case unread {
    NoRow -> "the table has no row of that id"
    UnknownField(field:) -> "unknown field " <> field
    Refused(results:) ->
      "the press is refused "
      <> string.join(list.map(results, int.to_string), ", ")
    NeverFinished -> "the cast never finished"
    NeverApplied -> "no go applies the row to the unit"
    CastsStarted(count:) ->
      "the drive started the spell that holds the row "
      <> int.to_string(count)
      <> " times, not once"
    NodeHeldBy(effect_id:) ->
      "the unit's node lasts as long as the longer row "
      <> int.to_string(effect_id)
    ModifierChanges(count:) ->
      "the cast gave "
      <> int.to_string(count)
      <> " changes of the caster for the row, not a start and an end"
    PressNotHeld ->
      "the press after the cooldown is not held for the rest of it"
    CooldownNotBracketed ->
      "the own cooldown does not end between 1.2 s and 100 s after the release"
    NoCooldownForMethod -> "no cooldown is read for a spell of this method"
    NotPeriodicProxy ->
      "no client fact counts the ticks of a row that is not a periodic Proxy"
    HeldAs(list:) -> "the plan holds the row as a " <> list
    NotInPlan -> "no list of the ability's plan holds the row"
  }
}

// ------------------------------------------------------------------ the cast rule

/// The time a driven press is made at.
pub const start_ms = 1000

/// The unit the cast strikes.
pub const struck_unit = 20

/// A cast driven to its end: the id the rule gave it and the timers it fired, the press
/// first, each at the time it was taken at.
pub type Drive {
  Drive(cast_id: Int, steps: List(support.Fired))
}

/// The units a go asked for at a time strikes.
pub type Strikes =
  fn(Int, cast.GoAsked) -> List(cast.Struck)

/// No go strikes a unit.
pub fn striking_none(_at_ms: Int, _asked: cast.GoAsked) -> List(cast.Struck) {
  []
}

/// A player in combat that holds only this ability, in the bag's first place: a cast
/// condition that asks for combat (Spectral Form's) passes.
pub fn caster_of(base base: Int) -> cast.Caster {
  cast.Caster(
    ..support.caster(),
    abilities: [Spell4BaseId(base)],
    in_combat: True,
  )
}

/// A press of the ability, then every timer the rule starts, fired at its time, until
/// none is left; each go strikes the units `strikes` gives. `Error` holds the results of
/// a refusal.
pub fn drive(
  plans plans: Plans,
  base base: Int,
  strikes strikes: Strikes,
) -> Result(Drive, List(Int)) {
  let caster = caster_of(base:)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: 0,
      target: 0,
      at: start_ms,
    )
  case support.refusal_results(effects: raw) {
    [] -> {
      let #(state, effects) =
        support.answered_each(
          caster:,
          state:,
          effects: raw,
          at: start_ms,
          struck_of: strikes(start_ms, _),
          rolls: [],
          poses: dict.new(),
        )
      let #(_, fired) =
        support.run_timers_asking(
          caster:,
          state:,
          effects:,
          from_ms: start_ms,
          struck_at: strikes,
        )
      Ok(
        Drive(cast_id: support.pressed_id(effects:), steps: [
          support.Fired(
            at_ms: start_ms,
            asked: support.goes_asked(effects: raw),
            effects:,
          ),
          ..fired
        ]),
      )
    }
    results -> Error(results)
  }
}

/// Each go strikes the unit and lands on it the crowd-control rows of the spell the go
/// is of, as `creature_control` lands them on a creature of no armor at the go's time.
pub fn striking_with_states(root root: Spell) -> Strikes {
  fn(at_ms: Int, asked: cast.GoAsked) {
    let controls = case
      list.find(
        spell_plan.tree(spell: root, started: fn(_) { True }),
        fn(spell) { spell.spell4_id == asked.spell4_id },
      )
    {
      Ok(spell) -> landed_of(rows: spell.controls, at_ms:)
      Error(Nil) -> []
    }
    [cast.Hit(unit_id: struck_unit, descriptions: [], controls:)]
  }
}

/// The states a creature of no armor takes from the control rows at the time: what
/// `creature_control` holds it for, as the connection hands it back to the cast.
pub fn landed_of(
  rows rows: List(spell_plan.CrowdControl),
  at_ms at_ms: Int,
) -> List(strike_tell.ControlLanded) {
  let tell =
    strike_tell.Strike(
      key: strike_tell.Key(cast_id: 1, phase: 0, unit_id: struck_unit),
      from: step.Sessions,
      striker: strike_tell.CreatureStriker,
      offence: hit_offence(),
      controls: list.index_map(rows, fn(row, index) {
        strike_tell.ControlTell(
          effect_id: row.effect_id.value,
          instance_id: index + 1,
          row: row.row,
        )
      }),
    )
  creature_control.land(
    state: creature_control.new(),
    tell:,
    armor: creature_life.NoArmor,
    refill_ms: 0,
    now_ms: at_ms,
  ).landed
}

pub fn hit_offence() -> hit.Offence {
  hit.Offence(
    blows: [],
    crit_chance: 0.0,
    crit_severity: 0.0,
    strikethrough: 0.0,
  )
}

/// The frames the cast wrote with this message id, each with the time since the press.
pub fn frames_of(
  drive drive: Drive,
  message_id message_id: Int,
) -> List(#(Int, Frame)) {
  list.flat_map(drive.steps, fn(step) {
    support.frames_of(message_id:, effects: step.effects)
    |> list.map(fn(frame) { #(step.at_ms - start_ms, frame) })
  })
}

/// Every go of the drive, each with the time since the press.
pub fn all_goes(drive drive: Drive) -> List(#(Int, spell_go.SpellGo)) {
  list.map(frames_of(drive:, message_id: spell_go.message_id), fn(entry) {
    let assert Ok(go) = spell_go.decode({ entry.1 }.body)
      as "a 0x7f4 the rule wrote decodes"
    #(entry.0, go)
  })
}

/// The goes of one cast: the time since the press and the go.
pub fn goes_in(
  drive drive: Drive,
  cast_id cast_id: Int,
) -> List(#(Int, spell_go.SpellGo)) {
  list.filter(all_goes(drive:), fn(go) { go.1.cast_id == cast_id })
}

/// The goes of the pressed cast itself.
pub fn goes_of(drive drive: Drive) -> List(#(Int, spell_go.SpellGo)) {
  goes_in(drive:, cast_id: drive.cast_id)
}

/// The casts the drive started, each with the time since the press.
pub fn started_of(
  drive drive: Drive,
) -> List(#(Int, spell_started.SpellStarted)) {
  list.map(frames_of(drive:, message_id: spell_started.message_id), fn(entry) {
    let assert Ok(started) = spell_started.decode({ entry.1 }.body)
      as "a 0x7ff the rule wrote decodes"
    #(entry.0, started)
  })
}

/// The time since the press that the cast finished at.
pub fn finish_in(drive drive: Drive, cast_id cast_id: Int) -> Result(Int, Nil) {
  list.find_map(
    frames_of(drive:, message_id: spell_finished.message_id),
    fn(entry) {
      case support.finished_cast_id(entry.1) == cast_id {
        True -> Ok(entry.0)
        False -> Error(Nil)
      }
    },
  )
}

/// The first time since the press, from a time on, that a 0x811 of the cast names the
/// unit.
pub fn removal_in(
  drive drive: Drive,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  from_ms from_ms: Int,
) -> Result(Int, Nil) {
  list.find_map(
    frames_of(drive:, message_id: spell_targets_removed.message_id),
    fn(entry) {
      case support.removed_targets([entry.1]) {
        [#(removed, units)] ->
          case
            removed == cast_id
            && entry.0 >= from_ms
            && list.contains(units, unit_id)
          {
            True -> Ok(entry.0)
            False -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    },
  )
}

/// One go's listing of a Spell4Effects row on a unit: the time since the press the go
/// was written at, the delay it lists and the unit.
pub type Application {
  Application(at_ms: Int, delay_ms: Int, unit_id: Int)
}

/// Each application of the Spell4Effects row, in the order of the goes of one cast.
pub fn applications(
  drive drive: Drive,
  cast_id cast_id: Int,
  effect_id effect_id: Int,
) -> List(Application) {
  goes_in(drive:, cast_id:)
  |> list.flat_map(fn(go) {
    list.flat_map(go.1.targets, fn(target) {
      list.filter(target.effects, fn(info) {
        info.spell4_effects_id == effect_id
      })
      |> list.map(fn(info) {
        Application(
          at_ms: go.0,
          delay_ms: info.delay_ms,
          unit_id: target.unit_id,
        )
      })
    })
  })
}

/// The casts of the child spell the drive started under the parent spell.
pub fn child_casts(
  drive drive: Drive,
  parent parent: Int,
  child child: Int,
) -> Int {
  list.count(started_of(drive:), fn(entry) {
    entry.1.spell4_id == child && entry.1.parent_spell4_id == parent
  })
}

/// A row a planned ability holds, and the list of the plan it is in.
pub type Held {
  HeldControl(row: spell_plan.CrowdControl)
  HeldLasting(row: spell_plan.Lasting)
  HeldModifier(row: spell_plan.PropertyModifier)
  HeldElsewhere(list: String)
}

/// The spell of the ability's tree that holds the Spell4Effects row, and how.
pub fn holder_of(
  root root: Spell,
  effect_id effect_id: Int,
) -> Result(#(Spell, Held), Nil) {
  list.find_map(
    spell_plan.tree(spell: root, started: fn(_) { True }),
    fn(spell) {
      held_in(spell:, effect_id:)
      |> result.map(fn(held) { #(spell, held) })
    },
  )
}

pub fn held_in(
  spell spell: Spell,
  effect_id effect_id: Int,
) -> Result(Held, Nil) {
  let is = fn(row_id: id.Spell4EffectsId) { row_id.value == effect_id }
  let elsewhere = [
    #("stealth", list.any(spell.stealth, fn(row) { is(row.effect_id) })),
    #("proc", list.any(spell.procs, fn(row) { is(row.effect_id) })),
    #(
      "cooldown modifier",
      list.any(spell.cooldown_modifiers, fn(row) { is(row.effect_id) }),
    ),
    #(
      "shield heal",
      list.any(spell.shield_heals, fn(row) { is(row.effect_id) }),
    ),
    #("gain", list.any(spell.gains, fn(row) { is(row.effect_id) })),
    #(
      "forced move",
      list.any(spell.forced_moves, fn(row) { is(row.effect_id) }),
    ),
    #("removal", list.any(spell.removes, fn(row) { is(row.effect_id) })),
    #("proxy", list.any(spell.proxies, fn(row) { is(row.effect_id) })),
  ]
  case
    list.find(spell.controls, fn(row) { is(row.effect_id) }),
    list.find(spell.lasting, fn(row) { is(row.effect_id) }),
    list.find(spell.modifiers, fn(row) { is(row.effect_id) }),
    list.find(elsewhere, fn(entry) { entry.1 })
  {
    Ok(row), _, _, _ -> Ok(HeldControl(row:))
    _, Ok(row), _, _ -> Ok(HeldLasting(row:))
    _, _, Ok(row), _ -> Ok(HeldModifier(row:))
    _, _, _, Ok(#(name, _)) -> Ok(HeldElsewhere(list: name))
    _, _, _, _ -> Error(Nil)
  }
}

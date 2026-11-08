//// What each planned ability's tooltip says about times and counts, against what the
//// cast rule does with the client's rows. A tooltip token (`$(kind=id.field)`) prints a
//// column of the row it names (`0x1404de8d0` for `eff`, `0x1404df2c0` for `spell`);
//// the cast rule, driven on a clock the test owns with the ability pressed as a player
//// that holds it, gives the outcome of the same row: the goes of a channel, the life of
//// a buff, a state or a modifier on the unit it lands on, the ticks, the go time and the
//// cooldown. One test for each outcome class compares the two for every token the
//// planned abilities' texts hold, and reports a difference as the ability, the text, the
//// token, the value it prints and the value the rule gives.
////
//// Expected values come from the client:
//// - Spell4Effects `durationTime`, `tickTime` and `delayTime` are what `durationMS`,
////   `tickTimeMS` and `delayMS` print (`0x1404de8d0`); Spell4 `tooltipCastTime` (else
////   `castTime`), `spellCoolDown` and the channel columns are what `castTime`, `cd` and
////   `channelPulse`, `channelMax` and `channelDelay` print (`0x1404df2c0`), the channel
////   columns for a Channeled or ChanneledField spell only.
//// - A channel goes at its initial delay and then each pulse time, up to the max time:
////   (max - delay + pulse) / pulse goes (`0x14053d1f0`, `Spell4.channelPulseTime`).
//// - A row's life from its go is its delay plus its duration, or the larger of the two
////   when the spell's Spell4 `propertyFlags` has 0x2000 (`opcode.0x7f4.effect_time`);
////   the unit's node of the cast ends with its longest row.
//// - A Proxy row with dataBits00 0 names its spell in dataBits01 and casts it every
////   tickTime for its life (`Spell4Effects.effectType.26.periodic`), so a text that
////   prints duration over tickTime counts casts of that spell started under the row's
////   spell (0x7ff with that parent). No client fact counts the go's application of the
////   row among the ticks a tooltip prints, so it is not counted; a tick of any other
////   effect type that is a result (HealShields 118) would be a 0x7f8 of its own, and
////   no tick token of the planned abilities names one.
//// - A press whose own cooldown has more than 500 ms left is refused 15, and one with
////   less is held (`0x1403b14c0`).
////
//// A token the rule differs from, or whose outcome the test cannot read, is a gap of
//// the test that names the open issue whose planned work closes it; a listed gap that
//// the rule now matches fails the test. A field of an `eff` or `spell` token that no
//// comparison reads and no list below names fails the test by name.

import cast_support as support
import fixture_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast.{type State}
import genesis_prime/game/hit
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/game/strike_tell
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/step
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import genesis_prime/tooltip_token.{type Token}
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_life
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import owned_test
import planted_table
import spell_tables

// ---------------------------------------------------------------- what is asked

/// The rows a test reads: the tables a token prints from and the plans the cast rule is
/// driven with.
pub type Rows {
  Rows(tables: store.Tables, plans: Plans)
}

/// The client's committed rows and the plans built from them.
fn shared() -> Rows {
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
fn planned(rows rows: Rows) -> List(Spell) {
  dict.to_list(rows.plans)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) { entry.1 })
}

/// Every token of every planned ability's tooltips, once for each ability, text and
/// token.
fn asked_of(rows rows: Rows) -> List(Asked) {
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

fn plan_of(rows rows: Rows, base base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(plans: rows.plans, base: Spell4BaseId(base))
    as "the plans hold the planned ability"
  spell
}

/// The asked tokens of this kind and these fields.
fn asked_with(
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
fn differences(outcomes outcomes: List(Outcome)) -> List(Difference) {
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
fn compared_count(outcomes outcomes: List(Outcome)) -> Int {
  list.count(outcomes, fn(outcome) {
    case outcome {
      Compared(..) -> True
      Unobserved(..) -> False
    }
  })
}

/// The tokens the rule was not read for.
fn left_out_count(outcomes outcomes: List(Outcome)) -> Int {
  list.length(outcomes) - compared_count(outcomes:)
}

/// What a test has to say of the differences: those no gap lists, and the gaps that
/// match no difference.
pub type Verdict {
  Verdict(unlisted: List(Difference), stale: List(Gap))
}

fn verdict(
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

// ------------------------------------------------------------ what a token prints

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

fn reason(unread unread: Unread) -> String {
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

/// The number a token prints, in the unit of its column (milliseconds for a time), as
/// the client's evaluators read it; `Error` for a row the table lacks or a field this
/// reader does not know.
fn printed(
  rows rows: Rows,
  root root: Spell,
  token token: Token,
) -> Result(Int, Unread) {
  case token.kind {
    tooltip_token.Eff -> {
      use row <- result.try(
        spell4_effects.get(tables: rows.tables, id: Spell4EffectsId(token.id))
        |> result.replace_error(NoRow),
      )
      case token.field {
        "durationms" -> Ok(row.duration_time)
        "ticktimems" -> Ok(row.tick_time)
        "delayms" -> Ok(row.delay_time)
        field -> Error(UnknownField(field:))
      }
    }
    tooltip_token.Spell -> {
      use row <- result.try(
        spell4.get(tables: rows.tables, id: Spell4Id(token.id))
        |> result.replace_error(NoRow),
      )
      let channelled = case root.spell4_id.value == token.id, root.method {
        True, spell_plan.Channeled | True, spell_plan.ChanneledField -> True
        True, _ -> False
        False, _ -> True
      }
      let channel = fn(column) {
        case channelled {
          True -> Ok(column)
          False -> Ok(0)
        }
      }
      case token.field {
        "casttime" ->
          Ok(case row.tooltip_cast_time {
            0 -> row.cast_time
            tooltip -> tooltip
          })
        "cd" -> Ok(row.spell_cool_down)
        "channelpulse" | "channelpulsems" -> channel(row.channel_pulse_time)
        "channelmax" | "channelmaxms" -> channel(row.channel_max_time)
        "channeldelay" | "channeldelayms" -> channel(row.channel_initial_delay)
        field -> Error(UnknownField(field:))
      }
    }
    tooltip_token.Cc
    | tooltip_token.Smod
    | tooltip_token.Emod
    | tooltip_token.Thrsh
    | tooltip_token.Gf
    | tooltip_token.Creature
    | tooltip_token.Item
    | tooltip_token.Schematic
    | tooltip_token.Vitem
    | tooltip_token.Achievement
    | tooltip_token.Keybinding
    | tooltip_token.Bindpoint -> Error(UnknownField(field: token.field))
  }
}

// -------------------------------------------------------------- the vocabulary

/// The fields of an `eff` or `spell` token that a comparison below reads.
const read_fields = [
  "durationms", "ticktimems", "delayms", "casttime", "cd", "channelpulse",
  "channelpulsems", "channelmax", "channelmaxms", "channeldelay",
  "channeldelayms",
]

/// The fields that print a time no comparison reads, each until the issue that plans
/// the effects they belong to closes it (#336): the `ms` and `msf` modifiers print an
/// effect's data column as a time (`0x1404de8d0`), and a spell's `lasData` fields are
/// not read by any client fact (`0x1404df2c0`), so what they print is not known to be
/// no time.
const left_out_fields = [
  "data03msf", "data03msfabs", "data04ms", "lasdata00", "lasdata00ms",
  "lasdata00pct", "lasdata00raw", "lasdata00rawint", "lasdata01", "lasdata02",
  "lasdata02pct", "lasdata02raw", "lasdata03msabs", "lasdata07ms", "lasdata09ms",
  "lasdata09pct",
]

/// The fields that print no time: an effect's data column as a number or a percent, an
/// input parameter as a percent (`0x1404de8d0`), a spell's area target count and its
/// name, and the text of another tooltip (`0x1404df2c0`).
const other_fields = [
  "input0pct", "data01rawint", "data02int", "data02pct", "data02pctadd",
  "data02rawint", "data03pct", "data03rawint", "aoetc", "", "ctooltip",
]

/// The tokens of the asked list that are of kind `eff` or `spell` and whose field no
/// comparison reads and no list names: a time such a field printed would go unchecked.
fn unread_fields(asked asked: List(Asked)) -> List(String) {
  list.filter_map(asked, fn(entry) {
    let field = entry.token.field
    case entry.token.kind {
      tooltip_token.Eff | tooltip_token.Spell ->
        case
          list.contains(read_fields, field)
          || list.contains(left_out_fields, field)
          || list.contains(other_fields, field)
        {
          True -> Error(Nil)
          False -> Ok(tooltip_token.describe(entry.token))
        }
      tooltip_token.Cc
      | tooltip_token.Smod
      | tooltip_token.Emod
      | tooltip_token.Thrsh
      | tooltip_token.Gf
      | tooltip_token.Creature
      | tooltip_token.Item
      | tooltip_token.Schematic
      | tooltip_token.Vitem
      | tooltip_token.Achievement
      | tooltip_token.Keybinding
      | tooltip_token.Bindpoint -> Error(Nil)
    }
  })
  |> list.unique
}

// ------------------------------------------------------------------ the cast rule

/// The time a driven press is made at.
const start_ms = 1000

/// The unit the cast strikes.
const struck_unit = 20

/// A cast driven to its end: the id the rule gave it and the timers it fired, the press
/// first, each at the time it was taken at.
pub type Drive {
  Drive(cast_id: Int, steps: List(support.Fired))
}

/// The units a go asked for at a time strikes.
type Strikes =
  fn(Int, cast.GoAsked) -> List(cast.Struck)

/// No go strikes a unit.
fn striking_none(_at_ms: Int, _asked: cast.GoAsked) -> List(cast.Struck) {
  []
}

/// A player in combat that holds only this ability, in the bag's first place: a cast
/// condition that asks for combat (Spectral Form's) passes.
fn caster_of(base base: Int) -> cast.Caster {
  cast.Caster(
    ..support.caster(),
    abilities: [Spell4BaseId(base)],
    in_combat: True,
  )
}

/// A press of the ability, then every timer the rule starts, fired at its time, until
/// none is left; each go strikes the units `strikes` gives. `Error` holds the results of
/// a refusal.
fn drive(
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
fn striking_with_states(root root: Spell) -> Strikes {
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
fn landed_of(
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

fn hit_offence() -> hit.Offence {
  hit.Offence(
    blows: [],
    crit_chance: 0.0,
    crit_severity: 0.0,
    strikethrough: 0.0,
  )
}

/// The frames the cast wrote with this message id, each with the time since the press.
fn frames_of(
  drive drive: Drive,
  message_id message_id: Int,
) -> List(#(Int, Frame)) {
  list.flat_map(drive.steps, fn(step) {
    support.frames_of(message_id:, effects: step.effects)
    |> list.map(fn(frame) { #(step.at_ms - start_ms, frame) })
  })
}

/// Every go of the drive, each with the time since the press.
fn all_goes(drive drive: Drive) -> List(#(Int, spell_go.SpellGo)) {
  list.map(frames_of(drive:, message_id: spell_go.message_id), fn(entry) {
    let assert Ok(go) = spell_go.decode({ entry.1 }.body)
      as "a 0x7f4 the rule wrote decodes"
    #(entry.0, go)
  })
}

/// The goes of one cast: the time since the press and the go.
fn goes_in(
  drive drive: Drive,
  cast_id cast_id: Int,
) -> List(#(Int, spell_go.SpellGo)) {
  list.filter(all_goes(drive:), fn(go) { go.1.cast_id == cast_id })
}

/// The goes of the pressed cast itself.
fn goes_of(drive drive: Drive) -> List(#(Int, spell_go.SpellGo)) {
  goes_in(drive:, cast_id: drive.cast_id)
}

/// The casts the drive started, each with the time since the press.
fn started_of(drive drive: Drive) -> List(#(Int, spell_started.SpellStarted)) {
  list.map(frames_of(drive:, message_id: spell_started.message_id), fn(entry) {
    let assert Ok(started) = spell_started.decode({ entry.1 }.body)
      as "a 0x7ff the rule wrote decodes"
    #(entry.0, started)
  })
}

/// The time since the press that the cast finished at.
fn finish_in(drive drive: Drive, cast_id cast_id: Int) -> Result(Int, Nil) {
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
fn removal_in(
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
fn applications(
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
fn child_casts(
  drive drive: Drive,
  parent parent: Int,
  child child: Int,
) -> Int {
  list.count(started_of(drive:), fn(entry) {
    entry.1.spell4_id == child && entry.1.parent_spell4_id == parent
  })
}

// ------------------------------------------------------------------- the channels

const channel_fields = [
  "channelpulse", "channelpulsems", "channelmax", "channelmaxms", "channeldelay",
  "channeldelayms",
]

const pulse_fields = ["channelpulse", "channelpulsems"]

/// What a channel's token prints against the cast: a pulse is the time between two
/// goes, a delay the time of the first go and the max the time the cast finishes at.
fn channel_outcomes(
  rows rows: Rows,
  asked asked: List(Asked),
) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Spell, fields: channel_fields),
    fn(entry) {
      let root = plan_of(rows:, base: entry.base)
      let assert Ok(expected) = printed(rows:, root:, token: entry.token)
        as "a channel token prints a column"
      case drive(plans: rows.plans, base: entry.base, strikes: striking_none) {
        Error(results) -> Unobserved(asked: entry, why: Refused(results:))
        Ok(driven) -> {
          let times = list.map(goes_of(drive: driven), fn(go) { go.0 })
          let field = entry.token.field
          let got = case times {
            [first, second, ..]
              if field == "channelpulse" || field == "channelpulsems"
            -> Ok(second - first)
            [first, ..]
              if field == "channeldelay" || field == "channeldelayms"
            -> Ok(first)
            _ if field == "channelmax" || field == "channelmaxms" ->
              finish_in(drive: driven, cast_id: driven.cast_id)
            _ -> Error(Nil)
          }
          case got {
            Ok(got) -> Compared(asked: entry, expected:, got:)
            Error(Nil) -> Unobserved(asked: entry, why: NeverFinished)
          }
        }
      }
    },
  )
}

/// The goes a channel's columns make: one at the delay and one each pulse after it, up
/// to the max time.
fn goes_expected(rows rows: Rows, asked asked: Asked) -> Int {
  let root = plan_of(rows:, base: asked.base)
  let column = fn(field) {
    let assert Ok(value) =
      printed(
        rows:,
        root:,
        token: tooltip_token.Token(
          kind: tooltip_token.Spell,
          id: asked.token.id,
          field:,
        ),
      )
      as "the channel's columns print"
    value
  }
  { column("channelmax") - column("channeldelay") + column("channelpulse") }
  / column("channelpulse")
}

/// The pulses of each planned ability a token counts: the goes the cast gave, against
/// the goes the channel's columns make.
fn pulse_outcomes(rows rows: Rows, asked asked: List(Asked)) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Spell, fields: pulse_fields),
    fn(entry) {
      case drive(plans: rows.plans, base: entry.base, strikes: striking_none) {
        Error(results) -> Unobserved(asked: entry, why: Refused(results:))
        Ok(driven) ->
          Compared(
            asked: entry,
            expected: goes_expected(rows:, asked: entry),
            got: list.length(goes_of(drive: driven)),
          )
      }
    },
  )
}

// ------------------------------------------------------------------- buff lives

/// A row a planned ability holds, and the list of the plan it is in.
type Held {
  HeldControl(row: spell_plan.CrowdControl)
  HeldLasting(row: spell_plan.Lasting)
  HeldModifier(row: spell_plan.PropertyModifier)
  HeldElsewhere(list: String)
}

/// The spell of the ability's tree that holds the Spell4Effects row, and how.
fn holder_of(
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

fn held_in(spell spell: Spell, effect_id effect_id: Int) -> Result(Held, Nil) {
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

/// The time from a row's go to the end of its effect on a unit that the client's code
/// gives: its delay plus its duration, or the larger of the two where the spell's Spell4
/// `propertyFlags` has 0x2000 (`opcode.0x7f4.effect_time`).
fn life_after_go(
  rows rows: Rows,
  holder holder: Spell,
  row row: Spell4Effects,
) -> Int {
  let assert Ok(record) = spell4.get(tables: rows.tables, id: holder.spell4_id)
    as "the spell that holds the row has a Spell4 row"
  case int.bitwise_and(record.property_flags, 0x2000) {
    0 -> row.delay_time + row.duration_time
    _ -> int.max(row.delay_time, row.duration_time)
  }
}

/// The cast of the spell in the drive: the pressed cast for the root spell, else the one
/// child cast the drive started of it.
fn cast_of(
  drive drive: Drive,
  root root: Spell,
  spell4_id spell4_id: Int,
) -> Result(Int, Unread) {
  use <- bool.guard(
    when: spell4_id == root.spell4_id.value,
    return: Ok(drive.cast_id),
  )
  case
    list.filter(started_of(drive:), fn(entry) { entry.1.spell4_id == spell4_id })
  {
    [#(_, started)] -> Ok(started.cast_id)
    other -> Error(CastsStarted(count: list.length(other)))
  }
}

/// The time from the last go that applies the row to the end of the node its unit holds
/// of the cast, which ends with the node's longest row, as a 0x811 naming the unit or the
/// cast's 0x7fe. The row is applied by each go of a repeated phase, so its life is taken
/// from the last one before the node ended.
fn node_life_of(
  drive drive: Drive,
  cast_id cast_id: Int,
  effect_id effect_id: Int,
) -> Result(Int, Unread) {
  use last <- result.try(
    list.last(applications(drive:, cast_id:, effect_id:))
    |> result.replace_error(NeverApplied),
  )
  let ends =
    list.filter_map(
      [
        removal_in(drive:, cast_id:, unit_id: last.unit_id, from_ms: last.at_ms),
        finish_in(drive:, cast_id:),
      ],
      fn(end) { end },
    )
  case list.sort(ends, int.compare) {
    [end, ..] -> Ok(end - last.at_ms)
    [] -> Error(NeverFinished)
  }
}

/// The time from the cast's first go to the end of the caster's change a modifier row
/// makes.
fn modifier_life_of(
  drive drive: Drive,
  cast_id cast_id: Int,
  effect_id effect_id: Int,
) -> Result(Int, Unread) {
  let source = support.source_of(cast_id:, effect_id:)
  let changes =
    support.timeline(
      fired: list.map(drive.steps, fn(step) { #(step.at_ms, step.effects) }),
    )
    |> list.filter(fn(change) { change.2 == source })
  case changes, goes_in(drive:, cast_id:) {
    [#(_, "start", _), #(ended, "end", _)], [go, ..] ->
      Ok(ended - start_ms - go.0)
    other, _ -> Error(ModifierChanges(count: list.length(other)))
  }
}

/// Whether the Spell4Effects row of the holder lives longer from its go than a time.
fn outlives(
  rows rows: Rows,
  holder holder: Spell,
  effect_id effect_id: Int,
  expected expected: Int,
) -> Bool {
  case spell4_effects.get(tables: rows.tables, id: Spell4EffectsId(effect_id)) {
    Ok(row) -> life_after_go(rows:, holder:, row:) > expected
    Error(Nil) -> False
  }
}

/// The life of the row on its unit in a drive of the ability.
fn observed_life(
  rows rows: Rows,
  drive drive: Drive,
  root root: Spell,
  holder holder: Spell,
  held held: Held,
  effect_id effect_id: Int,
  expected expected: Int,
) -> Result(Int, Unread) {
  use cast_id <- result.try(cast_of(
    drive:,
    root:,
    spell4_id: holder.spell4_id.value,
  ))
  case held {
    HeldModifier(..) -> modifier_life_of(drive:, cast_id:, effect_id:)
    HeldControl(..) | HeldLasting(..) -> {
      use last <- result.try(
        list.last(applications(drive:, cast_id:, effect_id:))
        |> result.replace_error(NeverApplied),
      )
      let longer =
        list.filter(
          list.append(
            list.map(holder.controls, fn(row) { row.effect_id.value }),
            list.map(holder.lasting, fn(row) { row.effect_id.value }),
          ),
          fn(other) {
            other != effect_id
            && list.any(
              applications(drive:, cast_id:, effect_id: other),
              fn(application) { application.unit_id == last.unit_id },
            )
            && outlives(rows:, holder:, effect_id: other, expected:)
          },
        )
      case longer {
        [other, ..] -> Error(NodeHeldBy(effect_id: other))
        [] -> node_life_of(drive:, cast_id:, effect_id:)
      }
    }
    HeldElsewhere(list:) -> Error(HeldAs(list:))
  }
}

const duration_fields = ["durationms"]

/// What a duration token prints against the life the rule gives the row on its unit, in
/// a drive of the whole ability whose goes strike the unit and land its states.
fn buff_time_outcomes(
  rows rows: Rows,
  asked asked: List(Asked),
) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Eff, fields: duration_fields),
    fn(entry) { buff_time_outcome(rows:, entry:) },
  )
}

/// What one duration token prints against the life the rule gives its row.
fn buff_time_outcome(rows rows: Rows, entry entry: Asked) -> Outcome {
  let root = plan_of(rows:, base: entry.base)
  case
    spell4_effects.get(tables: rows.tables, id: Spell4EffectsId(entry.token.id)),
    holder_of(root:, effect_id: entry.token.id)
  {
    Error(Nil), _ -> Unobserved(asked: entry, why: NoRow)
    Ok(_), Error(Nil) -> Unobserved(asked: entry, why: NotInPlan)
    Ok(row), Ok(#(holder, held)) -> {
      let expected = life_after_go(rows:, holder:, row:)
      let driven =
        drive(
          plans: rows.plans,
          base: entry.base,
          strikes: striking_with_states(root:),
        )
      let got = case driven {
        Error(results) -> Error(Refused(results:))
        Ok(driven) ->
          observed_life(
            rows:,
            drive: driven,
            root:,
            holder:,
            held:,
            effect_id: entry.token.id,
            expected:,
          )
      }
      case got {
        Ok(got) -> Compared(asked: entry, expected:, got:)
        Error(unread) -> Unobserved(asked: entry, why: unread)
      }
    }
  }
}

// ------------------------------------------------- delays, cast times and cooldowns

/// The delay the go lists for the row on the unit it strikes, in a drive of the whole
/// ability.
fn go_delay_of(
  rows rows: Rows,
  root root: Spell,
  holder holder: Spell,
  effect_id effect_id: Int,
) -> Result(Int, Unread) {
  use driven <- result.try(
    drive(
      plans: rows.plans,
      base: root.spell4_base_id.value,
      strikes: striking_with_states(root:),
    )
    |> result.map_error(fn(results) { Refused(results:) }),
  )
  use cast_id <- result.try(cast_of(
    drive: driven,
    root:,
    spell4_id: holder.spell4_id.value,
  ))
  case applications(drive: driven, cast_id:, effect_id:) {
    [first, ..] -> Ok(first.delay_ms)
    [] -> Error(NeverApplied)
  }
}

/// The time since the press of the pressed cast's first go, which a spell's cast time
/// ends in. A Multiphase spell goes once for each phase over its cast time, so its cast
/// time ends at its last go (`0x14053d1f0`).
fn cast_time_of(rows rows: Rows, base base: Int) -> Result(Int, Unread) {
  let root = plan_of(rows:, base:)
  use driven <- result.try(
    drive(plans: rows.plans, base:, strikes: striking_with_states(root:))
    |> result.map_error(fn(results) { Refused(results:) }),
  )
  let go = case root.method {
    spell_plan.Multiphase -> list.last(goes_of(drive: driven))
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.ChargeRelease
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> list.first(goes_of(drive: driven))
  }
  case go {
    Ok(go) -> Ok(go.0)
    Error(Nil) -> Error(NeverApplied)
  }
}

/// A press at a time on a state: the state after it and the effects the rule raised.
type Press =
  fn(State, Int) -> #(State, List(cast.Effect))

/// The time from the go that starts the spell's cooldown to the end of that cooldown.
/// A charged ability's cooldown starts at its release, pressed 100 ms after the first
/// press.
fn cooldown_of(rows rows: Rows, root root: Spell) -> Result(Int, Unread) {
  case root.method {
    spell_plan.ChargeRelease -> {
      let plans =
        support.with_spells(plans: rows.plans, spells: [
          support.without_cooldown_modifiers(spell: root),
        ])
      let caster = caster_of(base: root.spell4_base_id.value)
      let press = fn(state: State, at_ms: Int) {
        support.pressed_raw_in(
          plans:,
          state:,
          caster:,
          bag_index: 0,
          target: 0,
          at: at_ms,
        )
      }
      let release_ms = start_ms + 100
      let state =
        [start_ms, release_ms]
        |> list.fold(cast.new(), fn(state, at_ms) {
          let #(state, raw) = press(state, at_ms)
          support.answered_each(
            caster:,
            state:,
            effects: raw,
            at: at_ms,
            struck_of: fn(_) { [] },
            rolls: [],
            poses: dict.new(),
          ).0
        })
      cooldown_end_after(press:, state:, release_ms:)
    }
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.Multiphase
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> Error(NoCooldownForMethod)
  }
}

/// The time from the release to the end of the cooldown the release's go started,
/// found by pressing again: the press is refused 15 while more than the queue window
/// (500 ms, `0x1403b14c0`) of the own cooldown is left, and held for what is left after
/// that.
fn cooldown_end_after(
  press press: Press,
  state state: State,
  release_ms release_ms: Int,
) -> Result(Int, Unread) {
  let own = fn(at_ms) {
    support.refusal_results(effects: press(state, at_ms).1) == [15]
  }
  let early = release_ms + 1200
  let late = release_ms + 100_000
  case own(early), own(late) {
    True, False -> {
      let open = first_open(own:, refused: early, open: late)
      case support.started_timers(effects: press(state, open).1) {
        [#(_, wait_ms)] -> Ok(open + wait_ms - release_ms)
        [] | [_, _, ..] -> Error(PressNotHeld)
      }
    }
    True, True | False, True | False, False -> Error(CooldownNotBracketed)
  }
}

/// The first time, between a time the press is refused and one it is not, at which it
/// is not.
fn first_open(
  own own: fn(Int) -> Bool,
  refused refused: Int,
  open open: Int,
) -> Int {
  use <- bool.guard(when: open - refused <= 1, return: open)
  let middle = refused + { open - refused } / 2
  case own(middle) {
    True -> first_open(own:, refused: middle, open:)
    False -> first_open(own:, refused:, open: middle)
  }
}

const time_fields = ["casttime", "cd"]

/// What a delay, cast time or cooldown token prints against what the rule gives.
fn timing_outcomes(rows rows: Rows, asked asked: List(Asked)) -> List(Outcome) {
  let delays =
    list.map(
      asked_with(asked:, kind: tooltip_token.Eff, fields: ["delayms"]),
      fn(entry) {
        let root = plan_of(rows:, base: entry.base)
        case printed(rows:, root:, token: entry.token) {
          Error(unread) -> Unobserved(asked: entry, why: unread)
          Ok(expected) ->
            case holder_of(root:, effect_id: entry.token.id) {
              Ok(#(holder, _)) ->
                case
                  go_delay_of(rows:, root:, holder:, effect_id: entry.token.id)
                {
                  Ok(got) -> Compared(asked: entry, expected:, got:)
                  Error(unread) -> Unobserved(asked: entry, why: unread)
                }
              Error(Nil) -> Unobserved(asked: entry, why: NotInPlan)
            }
        }
      },
    )
  let times =
    list.map(
      asked_with(asked:, kind: tooltip_token.Spell, fields: time_fields),
      fn(entry) {
        let root = plan_of(rows:, base: entry.base)
        case printed(rows:, root:, token: entry.token) {
          Error(unread) -> Unobserved(asked: entry, why: unread)
          Ok(expected) -> {
            let got = case entry.token.field {
              "cd" -> cooldown_of(rows:, root:)
              _ -> cast_time_of(rows:, base: entry.base)
            }
            case got {
              Ok(got) -> Compared(asked: entry, expected:, got:)
              Error(unread) -> Unobserved(asked: entry, why: unread)
            }
          }
        }
      },
    )
  list.append(delays, times)
}

// ------------------------------------------------------------------------- ticks

/// What a tick token prints (the row's duration over its tick time) against how many
/// casts of the spell the row names a drive of the ability started under the row's
/// spell. Only a Proxy row (effectType 26) with dataBits00 0 and a tickTime has a
/// client fact that counts its ticks (`Spell4Effects.effectType.26.periodic`).
fn tick_outcomes(rows rows: Rows, asked asked: List(Asked)) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Eff, fields: ["ticktimems"]),
    fn(entry) {
      let root = plan_of(rows:, base: entry.base)
      case
        spell4_effects.get(
          tables: rows.tables,
          id: Spell4EffectsId(entry.token.id),
        )
      {
        Error(Nil) -> Unobserved(asked: entry, why: NoRow)
        Ok(row)
          if row.tick_time > 0 && row.effect_type == 26 && row.data_bits00 == 0
        ->
          case
            drive(
              plans: rows.plans,
              base: entry.base,
              strikes: striking_with_states(root:),
            )
          {
            Ok(driven) ->
              Compared(
                asked: entry,
                expected: row.duration_time / row.tick_time,
                got: child_casts(
                  drive: driven,
                  parent: row.spell_id,
                  child: row.data_bits01,
                ),
              )
            Error(results) -> Unobserved(asked: entry, why: Refused(results:))
          }
        Ok(_) -> Unobserved(asked: entry, why: NotPeriodicProxy)
      }
    },
  )
}

// ------------------------------------------------------------------------- tests

pub fn electrocute_goes_6_times_each_striking_with_the_damage_row_its_text_names_test() -> Nil {
  use <- owned_test.run(30_000)
  let rows = shared()
  let assert Ok(tokens) = tooltip_token.load()
  let electrocute = plan_of(rows:, base: 25_473)
  assert electrocute.spell4_id.value == 41_276
  let token = fn(field) {
    tooltip_token.Token(kind: tooltip_token.Spell, id: 41_276, field:)
  }
  let named = tooltip_token.of_text(tokens:, text_id: 360_105)
  assert list.contains(named, token("channelpulsems"))
    as "text 360105 names Electrocute's channelPulseMS"
  assert list.contains(
    named,
    tooltip_token.Token(kind: tooltip_token.Eff, id: 92_587, field: "input0pct"),
  )
    as "text 360105 names the damage row 92587"
  let assert Ok(pulse) =
    printed(rows:, root: electrocute, token: token("channelpulsems"))
  let assert Ok(delay) =
    printed(rows:, root: electrocute, token: token("channeldelayms"))
  let assert Ok(driven) =
    drive(plans: rows.plans, base: 25_473, strikes: striking_none)
    as "Electrocute is cast by a player that holds it"
  let goes = goes_of(drive: driven)
  assert list.length(goes) == 6
    as "Spell4.41276: channelInitialDelay 500, channelPulseTime 500, channelMaxTime 3000: (3000 - 500 + 500) / 500 goes (0x14053d1f0)"
  assert list.map(goes, fn(go) { go.1.phase }) == [0, 1, 2, 3, 4, 5]
    as "opcode.0x7f4.phase: a go for each pulse"
  assert list.map(goes, fn(go) { go.0 })
    == list.map([0, 1, 2, 3, 4, 5], fn(number) { delay + number * pulse })
    as "the first go comes at the channel's initial delay and the rest each channelPulseMS the text names after it"
  let assert Ok(area) =
    spell_area.of_spell(
      areas: spell_tables.fixture_areas(),
      spell4_id: Spell4Id(41_276),
    )
    as "Electrocute has an area"
  let strikes =
    list.flat_map(driven.steps, fn(step) { step.asked })
    |> list.map(fn(asked) {
      let assert Ok(strike) =
        spell_area.phase(spell: area, phase: asked.phase, spent: asked.spent)
        as "each go asked for is a phase of the spell"
      list.map(strike.damage, fn(damage) { damage.effect_id.value })
    })
  assert strikes == list.repeat([92_587], 6)
    as "each of the six goes strikes with the damage row text 360105 names"
}

/// The duration tokens whose row the rule's cast cannot be read for, each until the
/// issue whose planned work closes it. 210998 is a type 11 property modifier aimed at
/// another unit, which no plan holds (#464); 187681 has no row in the committed tables
/// because no plan reaches its spell 72652, and 178429 is a periodic Proxy the plan does
/// not start (`Spell4Effects.effectType.26.periodic`), both ticking effects (#336).
const buff_gaps = [
  Gap(ability: 30_075, token: "eff=210998.durationms", issue: "#464"),
  Gap(ability: 31_213, token: "eff=187681.durationms", issue: "#336"),
  Gap(ability: 38_012, token: "eff=178429.durationms", issue: "#336"),
]

pub fn every_buff_time_token_on_a_row_a_planned_ability_holds_equals_that_rows_life_on_its_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  let outcomes = buff_time_outcomes(rows:, asked: asked_of(rows:))
  assert verdict(differences: differences(outcomes:), gaps: buff_gaps)
    == Verdict(unlisted: [], stale: [])
  assert compared_count(outcomes:) == 10
    as "ten duration tokens name a row a plan holds, each read on the unit of a drive of the whole ability"
  assert left_out_count(outcomes:) == 3
    as "three name a row no plan of the ability holds, each a gap above"
}

/// The tick tokens whose row the cast rule never ticks, each until the issue that plans
/// ticking effects closes it: the periodic Proxy rows start no casts, and 187681 has no
/// row in the committed tables.
const tick_gaps = [
  Gap(ability: 31_779, token: "eff=121345.ticktimems", issue: "#336"),
  Gap(ability: 31_213, token: "eff=187681.ticktimems", issue: "#336"),
  Gap(ability: 38_012, token: "eff=178429.ticktimems", issue: "#336"),
]

pub fn every_tick_time_token_gives_its_duration_over_its_tick_time_ticks_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  let outcomes = tick_outcomes(rows:, asked: asked_of(rows:))
  assert verdict(differences: differences(outcomes:), gaps: tick_gaps)
    == Verdict(unlisted: [], stale: [])
  assert compared_count(outcomes:) == 3
    as "the periodic Proxy rows 121345 (one text) and 178429 (two texts) print a tick time, each a gap above"
  assert left_out_count(outcomes:) == 1
    as "Spell4Effects 187681 has no row in the table, a gap above"
}

pub fn a_proxy_rows_cast_is_counted_as_a_cast_of_its_spell_and_not_as_the_gos_application_of_the_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  // Telekinetic Strike (base 19102) holds Proxy 62204, which starts Spell4 30900 under
  // its own Spell4 32893.
  let root = plan_of(rows:, base: 19_102)
  let assert Ok(driven) =
    drive(plans: rows.plans, base: 19_102, strikes: striking_with_states(root:))
  assert child_casts(drive: driven, parent: 32_893, child: 30_900) == 1
    as "the cast of Spell4 30900 under Spell4 32893 is one 0x7ff"
  assert applications(drive: driven, cast_id: driven.cast_id, effect_id: 62_204)
    == []
    as "the go never lists the Proxy row as applied to a unit"
}

pub fn every_delay_cast_time_and_cooldown_token_matches_the_rules_go_time_and_cooldown_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  let outcomes = timing_outcomes(rows:, asked: asked_of(rows:))
  assert verdict(differences: differences(outcomes:), gaps: [])
    == Verdict(unlisted: [], stale: [])
  assert compared_count(outcomes:) == 3
    as "one delay (177530), one cast time (Quick Draw) and one cooldown (Charged Shot)"
  assert left_out_count(outcomes:) == 0
}

pub fn a_cast_time_token_is_the_time_of_the_pressed_casts_first_go_and_not_of_its_finish_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  // Base 31779 has a castTime of 0 and holds a 10 s lasting row, so its cast finishes
  // 10 s after the press while its only go is at the press.
  let root = plan_of(rows:, base: 31_779)
  let token =
    tooltip_token.Token(
      kind: tooltip_token.Spell,
      id: root.spell4_id.value,
      field: "casttime",
    )
  let asked = Asked(base: 31_779, text_id: 0, token:)
  let assert Ok(expected) = printed(rows:, root:, token:)
  let assert Ok(driven) =
    drive(plans: rows.plans, base: 31_779, strikes: striking_with_states(root:))
  assert finish_in(drive: driven, cast_id: driven.cast_id) == Ok(10_000)
    as "the cast finishes with its 10 s row"
  assert timing_outcomes(rows:, asked: [asked])
    == [Compared(asked:, expected:, got: 0)]
    as "the token prints the castTime, 0, and the first go is at the press"
  assert expected == 0
}

pub fn a_buff_time_token_that_differs_from_the_rule_is_reported_with_ability_text_token_expected_and_got_test() -> Nil {
  use <- owned_test.run(60_000)
  // The edit is the point of the test: Spell4Effects 83827 (a control row of Spell4
  // 38780, base 23173) holds a durationTime of 2500; the printed side reads 2600, and
  // the rule reads the plans built from the unchanged rows.
  let differing =
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 83_827,
      with: [#("durationTime", planted_table.Integer(2600))],
      body: fn(tables) {
        let rows = Rows(tables:, plans: spell_tables.fixture_plans())
        differences(outcomes: buff_time_outcomes(rows:, asked: asked_of(rows:)))
        |> list.filter(fn(difference) {
          case difference {
            Differs(..) -> True
            LeftOut(..) -> False
          }
        })
      },
    )
  assert differing
    == [
      Differs(
        ability: 23_173,
        text_id: 311_256,
        token: "eff=83827.durationms",
        expected: 2600,
        got: 2500,
      ),
    ]
}

pub fn a_listed_gap_that_now_passes_fails_the_test_naming_the_gap_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  let asked = asked_of(rows:)
  // Control row 83827 of base 23173 agrees with the rule, so a gap listing it is stale.
  let passing =
    Gap(ability: 23_173, token: "eff=83827.durationms", issue: "#336")
  assert verdict(
      differences: differences(outcomes: buff_time_outcomes(rows:, asked:)),
      gaps: [passing, ..buff_gaps],
    )
    == Verdict(unlisted: [], stale: [passing])
  // The tick gaps still differ, so with none listed the test names each difference.
  let ticks = differences(outcomes: tick_outcomes(rows:, asked:))
  assert verdict(differences: ticks, gaps: []).unlisted == ticks
  assert list.length(ticks) == 4
}

pub fn every_planned_ability_with_a_pulses_token_goes_the_pulses_its_channel_makes_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  let asked = asked_of(rows:)
  let outcomes = pulse_outcomes(rows:, asked:)
  assert compared_count(outcomes:) == 2
    as "Electrocute 41276 and Discharge 58832 each name a pulse"
  assert left_out_count(outcomes:) == 0
  assert verdict(differences: differences(outcomes:), gaps: [])
    == Verdict(unlisted: [], stale: [])
  let times = channel_outcomes(rows:, asked:)
  assert compared_count(outcomes: times) == 2
    as "the same two abilities name a channel time"
  assert left_out_count(outcomes: times) == 0
  assert differences(outcomes: times) == []
}

/// A channel's first go comes at its initial delay and the rest each pulse after it, so a
/// delay that is not the pulse shows which of the two the rule used for the first.
pub fn a_channels_first_go_is_due_at_its_initial_delay_and_not_at_its_first_pulse_test() -> Nil {
  use <- owned_test.run(60_000)
  // The edit is the point of the test: Spell4 41276 (Electrocute) holds a
  // channelInitialDelay of 500 equal to its pulse time, which cannot tell the two apart.
  let #(delay, pulse, goes, expected) =
    fixture_tables.changed(
      table: "Spell4",
      id: 41_276,
      with: [#("channelInitialDelay", planted_table.Integer(700))],
      body: fn(tables) {
        let assert Ok(plans) = spell_plan.build(tables:)
          as "the client's rows with a channel delay of 700 build"
        let rows = Rows(tables:, plans:)
        let root = plan_of(rows:, base: 25_473)
        let token = fn(field) {
          tooltip_token.Token(kind: tooltip_token.Spell, id: 41_276, field:)
        }
        let assert Ok(delay) =
          printed(rows:, root:, token: token("channeldelayms"))
        let assert Ok(pulse) =
          printed(rows:, root:, token: token("channelpulsems"))
        let assert Ok(driven) =
          drive(plans: rows.plans, base: 25_473, strikes: striking_none)
        let asked =
          Asked(base: 25_473, text_id: 0, token: token("channelpulsems"))
        #(
          delay,
          pulse,
          list.map(goes_of(drive: driven), fn(go) { go.0 }),
          goes_expected(rows:, asked:),
        )
      },
    )
  assert delay == 700
  assert pulse == 500
  assert expected == 5
    as "(3000 - 700 + 500) / 500 goes (0x14053d1f0), channelMaxTime being 3000"
  assert goes == [700, 1200, 1700, 2200, 2700]
    as "the first go at the delay, each next one a pulse after it"
}

/// The committed rows with each edit made in order, and the plans built from them.
fn with_edits(
  edits edits: List(#(String, Int, List(#(String, planted_table.Cell)))),
  body body: fn(Rows) -> a,
) -> a {
  let edited =
    list.fold(edits, fixture_tables.rows(), fn(rows, edit) {
      let assert Ok(rows) =
        fixture_tables.change(rows:, table: edit.0, id: edit.1, with: edit.2)
        as "the row and its columns are in the committed tables"
      rows
    })
  fixture_tables.on_rows(rows: edited, reaching: [], body: fn(tables) {
    let assert Ok(plans) = spell_plan.build(tables:)
      as "the client's rows with the edits build"
    body(Rows(tables:, plans:))
  })
}

/// A row whose spell has Spell4 `propertyFlags` 0x2000 lives its longer time of delay and
/// duration rather than the two added (`opcode.0x7f4.effect_time`), and the rule does the
/// same to the node the unit holds. No committed row of a planned ability has the flag, so
/// the test plants it on Spell4 42908 of base 30828, whose Spell4Effects 109482 (a lasting
/// row of delay 0 and duration 8000) is the one lasting row the abilities' texts name, and
/// gives that row a delay, since a delay of 0 cannot tell the sum from the larger.
pub fn a_buff_row_of_a_spell_flagged_0x2000_lives_the_longer_of_its_delay_and_duration_test() -> Nil {
  use <- owned_test.run(60_000)
  let asked =
    Asked(
      base: 30_828,
      text_id: 0,
      token: tooltip_token.Token(
        kind: tooltip_token.Eff,
        id: 109_482,
        field: "durationms",
      ),
    )
  let delay = #("Spell4Effects", 109_482, [
    #("delayTime", planted_table.Integer(500)),
  ])
  let assert Ok(before) =
    spell4.get(tables: shared().tables, id: Spell4Id(42_908))
  assert int.bitwise_and(before.property_flags, 0x2000) == 0
  let unflagged =
    with_edits(edits: [delay], body: fn(rows) {
      buff_time_outcomes(rows:, asked: [asked])
    })
  assert unflagged == [Compared(asked:, expected: 8500, got: 8500)]
    as "without the flag the row lives its delay 500 and its duration 8000 added"
  let flagged =
    with_edits(
      edits: [
        delay,
        #("Spell4", 42_908, [
          #(
            "propertyFlags",
            planted_table.Integer(before.property_flags + 0x2000),
          ),
        ]),
      ],
      body: fn(rows) { buff_time_outcomes(rows:, asked: [asked]) },
    )
  assert flagged == [Compared(asked:, expected: 8000, got: 8000)]
    as "with the flag the row lives the larger of 500 and 8000"
}

/// A field the comparisons do not read, and no list names, is not skipped: the test
/// reports the token by name.
pub fn a_token_field_no_comparison_reads_is_reported_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  let token = fn(kind, id, field) { tooltip_token.Token(kind:, id:, field:) }
  let asked =
    list.map(
      [
        token(tooltip_token.Eff, 92_587, "durationh"),
        token(tooltip_token.Eff, 92_587, "auraduration"),
        token(tooltip_token.Spell, 41_276, "cdms"),
        token(tooltip_token.Spell, 41_276, "casttimems"),
        token(tooltip_token.Eff, 92_587, "durationms"),
        token(tooltip_token.Cc, 1, "anything"),
      ],
      fn(token) { Asked(base: 25_473, text_id: 0, token:) },
    )
  assert unread_fields(asked:)
    == [
      "eff=92587.durationh",
      "eff=92587.auraduration",
      "spell=41276.cdms",
      "spell=41276.casttimems",
    ]
  let root = plan_of(rows:, base: 25_473)
  assert printed(
      rows:,
      root:,
      token: token(tooltip_token.Eff, 92_587, "auraduration"),
    )
    == Error(UnknownField(field: "auraduration"))
  assert printed(
      rows:,
      root:,
      token: token(tooltip_token.Spell, 41_276, "casttimems"),
    )
    == Error(UnknownField(field: "casttimems"))
  assert reason(unread: UnknownField(field: "cdms")) == "unknown field cdms"
}

pub fn every_field_of_every_eff_and_spell_token_the_planned_abilities_hold_is_read_or_named_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = shared()
  let asked = asked_of(rows:)
  assert unread_fields(asked:) == []
  let in_left_out = fn(entry: Asked) {
    list.contains(left_out_fields, entry.token.field)
  }
  assert list.count(asked, in_left_out) == 21
    as "the tokens whose eff ms or msf column or spell lasData column no comparison reads, each field named in the list under #336"
}

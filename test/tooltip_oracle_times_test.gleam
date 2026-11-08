//// What each planned ability's tooltip says about times and counts, against what the
//// cast rule does with the client's rows. A tooltip token (`$(kind=id.field)`) prints a
//// column of the row it names (`0x1404de8d0` for `eff`, `0x1404df2c0` for `spell`);
//// the cast rule, driven on a clock the test owns, gives the outcome of the same row:
//// the goes of a channel, the life of a buff, a state or a modifier, the ticks, the go
//// time and the cooldown. One test for each outcome class compares the two for every
//// token the planned abilities' texts hold, and reports a difference as the ability,
//// the text, the token, the value it prints and the value the rule gives.
////
//// Expected values come from the client:
//// - Spell4Effects `durationTime`, `tickTime` and `delayTime` are what `durationMS`,
////   `tickTimeMS` and `delayMS` print (`0x1404de8d0`); Spell4 `tooltipCastTime` (else
////   `castTime`), `spellCoolDown` and the channel columns are what `castTime`, `cd` and
////   `channelPulse`, `channelMax` and `channelDelay` print (`0x1404df2c0`), the channel
////   columns for a Channeled or ChanneledField spell only.
//// - A channel goes at its initial delay and then each pulse time, up to the max time:
////   (max - delay + pulse) / pulse goes (`0x14053d1f0`, `Spell4.channelPulseTime`).
//// - A row's life from its go is its delay plus its duration (`opcode.0x7f4.effect_time`);
////   the printed duration is the life after the delay.
//// - A press whose own cooldown has more than 500 ms left is refused 15, and one with
////   less is held (`0x1403b14c0`).
////
//// A token the rule differs from is a gap of the test that names the open issue whose
//// planned work closes it; a listed gap that the rule now matches fails the test.

import cast_support as support
import fixture_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/hit
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/game/strike_tell
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/step
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
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

/// A token one planned ability's tooltip holds: the ability's Spell4Base id, the text
/// and the token.
pub type Asked {
  Asked(base: Int, text_id: Int, token: Token)
}

/// What a token prints against what the rule gives, or why the rule was not read.
pub type Outcome {
  Compared(asked: Asked, expected: Int, got: Int)
  Unobserved(asked: Asked, why: String)
}

/// A difference, as the test reports it.
pub type Mismatch {
  Mismatch(ability: Int, text_id: Int, token: String, expected: Int, got: Int)
}

/// A difference the test lists until the issue's work closes it.
pub type Gap {
  Gap(ability: Int, token: String, issue: String)
}

/// The planned abilities, by Spell4Base id.
fn planned() -> List(Spell) {
  dict.to_list(spell_tables.fixture_plans())
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) { entry.1 })
}

/// Every token of every planned ability's tooltips, once for each ability, text and
/// token.
fn asked_of(tables tables: store.Tables) -> List(Asked) {
  let assert Ok(tokens) = tooltip_token.load()
    as "the committed token list loads"
  list.flat_map(planned(), fn(root) {
    tooltip_token.of_spell(tables:, tokens:, spell: root.spell4_id.value)
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

fn plan_of(base base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.fixture_plans(),
      base: Spell4BaseId(base),
    )
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

/// The report of a difference.
fn mismatch_of(
  asked asked: Asked,
  expected expected: Int,
  got got: Int,
) -> Mismatch {
  Mismatch(
    ability: asked.base,
    text_id: asked.text_id,
    token: tooltip_token.describe(asked.token),
    expected:,
    got:,
  )
}

/// The differences among the outcomes.
fn mismatches(outcomes outcomes: List(Outcome)) -> List(Mismatch) {
  list.filter_map(outcomes, fn(outcome) {
    case outcome {
      Compared(asked:, expected:, got:) if expected != got ->
        Ok(mismatch_of(asked:, expected:, got:))
      Compared(..) | Unobserved(..) -> Error(Nil)
    }
  })
}

/// The tokens the rule was not read for, with the reason.
fn unobserved(
  outcomes outcomes: List(Outcome),
) -> List(#(Int, String, String)) {
  list.filter_map(outcomes, fn(outcome) {
    case outcome {
      Unobserved(asked:, why:) ->
        Ok(#(asked.base, tooltip_token.describe(asked.token), why))
      Compared(..) -> Error(Nil)
    }
  })
}

/// What a test has to say of the differences: those no gap lists, and the gaps that
/// match nothing.
pub type Verdict {
  Verdict(unlisted: List(Mismatch), stale: List(Gap))
}

fn verdict(
  mismatches mismatches: List(Mismatch),
  gaps gaps: List(Gap),
) -> Verdict {
  let listed = fn(mismatch: Mismatch, gap: Gap) {
    mismatch.ability == gap.ability && mismatch.token == gap.token
  }
  Verdict(
    unlisted: list.filter(mismatches, fn(mismatch) {
      !list.any(gaps, listed(mismatch, _))
    }),
    stale: list.filter(gaps, fn(gap) { !list.any(mismatches, listed(_, gap)) }),
  )
}

// ------------------------------------------------------------ what a token prints

/// The number a token prints, in the unit of its column (milliseconds for a time), as
/// the client's evaluators read it; `Error` for a row the table lacks or a field this
/// reader does not know.
fn printed(
  tables tables: store.Tables,
  root root: Spell,
  token token: Token,
) -> Result(Int, Nil) {
  case token.kind {
    tooltip_token.Eff -> {
      use row <- result.try(spell4_effects.get(
        tables:,
        id: Spell4EffectsId(token.id),
      ))
      case token.field {
        "durationms" -> Ok(row.duration_time)
        "ticktimems" -> Ok(row.tick_time)
        "delayms" -> Ok(row.delay_time)
        _ -> Error(Nil)
      }
    }
    tooltip_token.Spell -> {
      use row <- result.try(spell4.get(tables:, id: Spell4Id(token.id)))
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
        _ -> Error(Nil)
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
    | tooltip_token.Bindpoint -> Error(Nil)
  }
}

// ------------------------------------------------------------------ the cast rule

/// The time a driven press is made at.
const start_ms = 1000

/// One moment of a driven cast: the time, the goes the rule asked for (before they were
/// answered) and the effects its answered form gives.
type Step {
  Step(at_ms: Int, asked: List(cast.GoAsked), effects: List(Effect))
}

/// A cast driven to its end: the id the rule gave it and its steps, the press first.
type Drive {
  Drive(cast_id: Int, steps: List(Step))
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
/// none is left; each go strikes `struck`. `Error` holds the results of a refusal.
fn drive(
  plans plans: Plans,
  base base: Int,
  struck struck: List(cast.Struck),
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
      let #(state, first) =
        settle(caster:, state:, raw:, at_ms: start_ms, struck:)
      let steps =
        run_pending(
          caster:,
          state:,
          pending: due(effects: first.effects, now_ms: start_ms),
          done: [first],
          struck:,
        )
      Ok(Drive(cast_id: support.pressed_id(effects: first.effects), steps:))
    }
    results -> Error(results)
  }
}

fn settle(
  caster caster: cast.Caster,
  state state: State,
  raw raw: List(Effect),
  at_ms at_ms: Int,
  struck struck: List(cast.Struck),
) -> #(State, Step) {
  let #(state, effects) =
    support.answered_each(
      caster:,
      state:,
      effects: raw,
      at: at_ms,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
    )
  #(state, Step(at_ms:, asked: support.goes_asked(effects: raw), effects:))
}

fn due(
  effects effects: List(Effect),
  now_ms now_ms: Int,
) -> List(#(Int, step.TimerId)) {
  list.map(support.started_timers(effects:), fn(started) {
    #(now_ms + started.1, started.0)
  })
}

fn run_pending(
  caster caster: cast.Caster,
  state state: State,
  pending pending: List(#(Int, step.TimerId)),
  done done: List(Step),
  struck struck: List(cast.Struck),
) -> List(Step) {
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [] -> list.reverse(done)
    [#(at_ms, timer), ..rest] -> {
      let #(state, raw) =
        support.fired_raw_as(caster:, state:, timer:, at: at_ms)
      let #(state, fired) = settle(caster:, state:, raw:, at_ms:, struck:)
      let cancelled = support.cancelled_timers(effects: fired.effects)
      run_pending(
        caster:,
        state:,
        pending: list.append(
          list.filter(rest, fn(other) { !list.contains(cancelled, other.1) }),
          due(effects: fired.effects, now_ms: at_ms),
        ),
        done: [fired, ..done],
        struck:,
      )
    }
  }
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

/// The goes of the pressed cast itself: the time since the press and the go.
fn goes_of(drive drive: Drive) -> List(#(Int, spell_go.SpellGo)) {
  list.filter_map(frames_of(drive:, message_id: spell_go.message_id), fn(entry) {
    let assert Ok(go) = spell_go.decode({ entry.1 }.body)
      as "a 0x7f4 the rule wrote decodes"
    case go.cast_id == drive.cast_id {
      True -> Ok(#(entry.0, go))
      False -> Error(Nil)
    }
  })
}

/// The time since the press that the pressed cast finished at.
fn finish_of(drive drive: Drive) -> Result(Int, Nil) {
  list.find_map(
    frames_of(drive:, message_id: spell_finished.message_id),
    fn(entry) {
      case support.finished_cast_id(entry.1) == drive.cast_id {
        True -> Ok(entry.0)
        False -> Error(Nil)
      }
    },
  )
}

/// The delay each application of the Spell4Effects row to a unit carries in the goes of
/// the whole drive.
fn applied_delays(drive drive: Drive, effect_id effect_id: Int) -> List(Int) {
  frames_of(drive:, message_id: spell_go.message_id)
  |> list.flat_map(fn(entry) {
    let assert Ok(go) = spell_go.decode({ entry.1 }.body)
      as "a 0x7f4 the rule wrote decodes"
    list.flat_map(go.targets, fn(target) {
      list.filter(target.effects, fn(info) {
        info.spell4_effects_id == effect_id
      })
      |> list.map(fn(info) { info.delay_ms })
    })
  })
}

/// Why the rule's outcome of a row could not be read.
type Unread {
  Refused(results: List(Int))
  NeverFinished
  ModifierChanges(count: Int)
  RowListed(times: Int)
  PressNotHeld
  CooldownNotBracketed
  NoCooldownForMethod
}

fn reason(unread unread: Unread) -> String {
  case unread {
    Refused(results:) ->
      "the press is refused "
      <> string.join(list.map(results, int.to_string), ", ")
    NeverFinished -> "the cast never finished"
    ModifierChanges(count:) ->
      "the cast gave "
      <> int.to_string(count)
      <> " changes of the caster, not a start and an end"
    RowListed(times:) ->
      "the goes list the row " <> int.to_string(times) <> " times, not once"
    PressNotHeld ->
      "the press after the cooldown is not held for the rest of it"
    CooldownNotBracketed ->
      "the own cooldown does not end between 1.2 s and 100 s after the release"
    NoCooldownForMethod -> "no cooldown is read for a spell of this method"
  }
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
  tables tables: store.Tables,
  asked asked: List(Asked),
) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Spell, fields: channel_fields),
    fn(entry) {
      let root = plan_of(base: entry.base)
      let assert Ok(expected) = printed(tables:, root:, token: entry.token)
        as "a channel token prints a column"
      case
        drive(plans: spell_tables.fixture_plans(), base: entry.base, struck: [])
      {
        Error(results) ->
          Unobserved(asked: entry, why: reason(unread: Refused(results:)))
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
              finish_of(drive: driven)
            _ -> Error(Nil)
          }
          case got {
            Ok(got) -> Compared(asked: entry, expected:, got:)
            Error(Nil) ->
              Unobserved(asked: entry, why: "the cast gave too few goes")
          }
        }
      }
    },
  )
}

/// The goes a channel's columns make: one at the delay and one each pulse after it, up
/// to the max time.
fn goes_expected(tables tables: store.Tables, asked asked: Asked) -> Int {
  let root = plan_of(base: asked.base)
  let column = fn(field) {
    let assert Ok(value) =
      printed(
        tables:,
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
fn pulse_outcomes(
  tables tables: store.Tables,
  asked asked: List(Asked),
) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Spell, fields: pulse_fields),
    fn(entry) {
      case
        drive(plans: spell_tables.fixture_plans(), base: entry.base, struck: [])
      {
        Error(results) ->
          Unobserved(asked: entry, why: reason(unread: Refused(results:)))
        Ok(driven) ->
          Compared(
            asked: entry,
            expected: goes_expected(tables:, asked: entry),
            got: list.length(goes_of(drive: driven)),
          )
      }
    },
  )
}

// ------------------------------------------------------------------- buff lives

/// The Spell4Base id the spell that holds one row alone is planned under.
const reduced_base = 1

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

/// A spell of no cast time, no cost and no cooldown that holds one row of the holder
/// and nothing else, so a cast of it shows the row's own outcome.
fn holding(holder holder: Spell, held held: Held) -> Spell {
  let clean =
    spell_plan.Spell(
      ..support.child(spell4_id: holder.spell4_id.value, base: reduced_base),
      longer_of_delay_and_duration: holder.longer_of_delay_and_duration,
    )
  case held {
    HeldControl(row:) -> spell_plan.Spell(..clean, controls: [row])
    HeldLasting(row:) -> spell_plan.Spell(..clean, lasting: [row])
    HeldModifier(row:) -> spell_plan.Spell(..clean, modifiers: [row])
    HeldElsewhere(..) -> clean
  }
}

/// The state a creature of no armor takes from the control row at the press: what
/// `creature_control` holds it for, as the connection hands it back to the cast.
fn landed_of(
  row row: spell_plan.CrowdControl,
) -> List(strike_tell.ControlLanded) {
  let tell =
    strike_tell.Strike(
      key: strike_tell.Key(cast_id: 1, phase: 0, unit_id: struck_unit),
      from: step.Sessions,
      striker: strike_tell.CreatureStriker,
      offence: hit.Offence(
        blows: [],
        crit_chance: 0.0,
        crit_severity: 0.0,
        strikethrough: 0.0,
      ),
      controls: [
        strike_tell.ControlTell(
          effect_id: row.effect_id.value,
          instance_id: 1,
          row: row.row,
        ),
      ],
    )
  creature_control.land(
    state: creature_control.new(),
    tell:,
    armor: creature_life.NoArmor,
    refill_ms: 0,
    now_ms: start_ms,
  ).landed
}

/// The unit the cast strikes.
const struck_unit = 20

/// A cast of the spell that holds the one row, on a unit it strikes: a control row has
/// landed on the unit, as `creature_control` lands it.
fn drive_holding(
  holder holder: Spell,
  held held: Held,
) -> Result(Drive, List(Int)) {
  let plans =
    support.with_spells(plans: spell_tables.fixture_plans(), spells: [
      holding(holder:, held:),
    ])
  let struck = case held {
    HeldControl(row:) -> [
      cast.Hit(
        unit_id: struck_unit,
        descriptions: [],
        controls: landed_of(row:),
      ),
    ]
    HeldLasting(..) | HeldModifier(..) | HeldElsewhere(..) ->
      support.hits([struck_unit])
  }
  drive(plans:, base: reduced_base, struck:)
}

/// The time since its go that the row's effect lives, after its delay: the cast of a
/// spell that holds the row finishes with its last node, and a property modifier ends
/// on its own timer.
fn life_of(
  holder holder: Spell,
  held held: Held,
  delay_ms delay_ms: Int,
) -> Result(Int, Unread) {
  case drive_holding(holder:, held:) {
    Error(results) -> Error(Refused(results:))
    Ok(driven) ->
      case held {
        HeldModifier(..) -> modifier_life_of(drive: driven)
        HeldControl(..) | HeldLasting(..) | HeldElsewhere(..) ->
          finish_of(drive: driven)
          |> result.map(fn(finished) { finished - delay_ms })
          |> result.replace_error(NeverFinished)
      }
  }
}

/// The time between the start and the end of the caster's change a modifier makes.
fn modifier_life_of(drive drive: Drive) -> Result(Int, Unread) {
  case
    support.timeline(
      fired: list.map(drive.steps, fn(step) {
        #(step.at_ms - start_ms, step.effects)
      }),
    )
  {
    [#(started, "start", _), #(ended, "end", _)] -> Ok(ended - started)
    other -> Error(ModifierChanges(count: list.length(other)))
  }
}

const duration_fields = ["durationms"]

/// The duration tokens of a planned ability's text that name a row no list of that
/// ability's plan holds, so no cast of it has a life to read: the rows of spells no plan
/// of the ability reaches (Spell4Effects 187681 belongs to spell 72652, which is in no
/// plan, and the fixture holds no row of it), and proxy rows.
const buff_rows_no_plan_holds = [
  #(
    30_075,
    "eff=210998.durationms",
    "no list of the ability's plan holds the row",
  ),
  #(31_213, "eff=187681.durationms", "the table has no row of that id"),
  #(
    38_012,
    "eff=178429.durationms",
    "no list of the ability's plan holds the row",
  ),
]

/// What a duration token prints against the life the rule gives the row on its unit.
fn buff_time_outcomes(
  tables tables: store.Tables,
  asked asked: List(Asked),
) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Eff, fields: duration_fields),
    fn(entry) {
      let root = plan_of(base: entry.base)
      let delay =
        printed(
          tables:,
          root:,
          token: tooltip_token.Token(..entry.token, field: "delayms"),
        )
      case printed(tables:, root:, token: entry.token), delay {
        Ok(expected), Ok(delay_ms) ->
          case holder_of(root:, effect_id: entry.token.id) {
            Error(Nil) ->
              Unobserved(
                asked: entry,
                why: "no list of the ability's plan holds the row",
              )
            Ok(#(_, HeldElsewhere(list:))) ->
              Unobserved(
                asked: entry,
                why: "the plan holds the row as a " <> list,
              )
            Ok(#(holder, held)) ->
              case life_of(holder:, held:, delay_ms:) {
                Ok(got) -> Compared(asked: entry, expected:, got:)
                Error(unread) -> Unobserved(asked: entry, why: reason(unread:))
              }
          }
        _, _ -> Unobserved(asked: entry, why: "the table has no row of that id")
      }
    },
  )
}

// ------------------------------------------------- delays, cast times and cooldowns

/// The delay the go lists for the row on the unit it strikes.
fn go_delay_of(
  holder holder: Spell,
  held held: Held,
  effect_id effect_id: Int,
) -> Result(Int, Unread) {
  case drive_holding(holder:, held:) {
    Error(results) -> Error(Refused(results:))
    Ok(driven) ->
      case applied_delays(drive: driven, effect_id:) {
        [delay] -> Ok(delay)
        other -> Error(RowListed(times: list.length(other)))
      }
  }
}

/// The time since the press that a cast of the ability finishes at.
fn cast_time_of(base base: Int) -> Result(Int, Unread) {
  case
    drive(
      plans: spell_tables.fixture_plans(),
      base:,
      struck: support.hits([struck_unit]),
    )
  {
    Error(results) -> Error(Refused(results:))
    Ok(driven) ->
      finish_of(drive: driven) |> result.replace_error(NeverFinished)
  }
}

/// A press at a time on a state: the state after it and the effects the rule raised.
type Press =
  fn(State, Int) -> #(State, List(Effect))

/// The time from the go that starts the spell's cooldown to the end of that cooldown.
/// A charged ability's cooldown starts at its release, pressed 100 ms after the first
/// press.
fn cooldown_of(root root: Spell) -> Result(Int, Unread) {
  case root.method {
    spell_plan.ChargeRelease -> {
      let plans =
        support.with_spells(plans: spell_tables.fixture_plans(), spells: [
          without_cooldown_modifiers(spell: root),
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
          settle(caster:, state:, raw:, at_ms:, struck: []).0
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

/// A spell and the stages and Proxies under it with no cooldown modifier: the plan as
/// if the rows that change a cooldown were not there.
fn without_cooldown_modifiers(spell spell: Spell) -> Spell {
  spell_plan.Spell(
    ..spell,
    cooldown_modifiers: [],
    stages: list.map(spell.stages, fn(stage) {
      spell_plan.Stage(
        ..stage,
        spell: without_cooldown_modifiers(spell: stage.spell),
      )
    }),
    proxies: list.map(spell.proxies, fn(proxy) {
      spell_plan.Proxy(
        ..proxy,
        spell: without_cooldown_modifiers(spell: proxy.spell),
      )
    }),
  )
}

const time_fields = ["casttime", "cd"]

/// What a delay, cast time or cooldown token prints against what the rule gives.
fn timing_outcomes(
  tables tables: store.Tables,
  asked asked: List(Asked),
) -> List(Outcome) {
  let delays =
    list.map(
      asked_with(asked:, kind: tooltip_token.Eff, fields: ["delayms"]),
      fn(entry) {
        let root = plan_of(base: entry.base)
        case printed(tables:, root:, token: entry.token) {
          Error(Nil) ->
            Unobserved(asked: entry, why: "the table has no row of that id")
          Ok(expected) ->
            case holder_of(root:, effect_id: entry.token.id) {
              Ok(#(holder, held)) ->
                case go_delay_of(holder:, held:, effect_id: entry.token.id) {
                  Ok(got) -> Compared(asked: entry, expected:, got:)
                  Error(unread) ->
                    Unobserved(asked: entry, why: reason(unread:))
                }
              Error(Nil) ->
                Unobserved(
                  asked: entry,
                  why: "no list of the ability's plan holds the row",
                )
            }
        }
      },
    )
  let times =
    list.map(
      asked_with(asked:, kind: tooltip_token.Spell, fields: time_fields),
      fn(entry) {
        let root = plan_of(base: entry.base)
        case printed(tables:, root:, token: entry.token) {
          Error(Nil) ->
            Unobserved(asked: entry, why: "the table has no row of that id")
          Ok(expected) -> {
            let got = case entry.token.field {
              "cd" -> cooldown_of(root:)
              _ -> cast_time_of(base: entry.base)
            }
            case got {
              Ok(got) -> Compared(asked: entry, expected:, got:)
              Error(unread) -> Unobserved(asked: entry, why: reason(unread:))
            }
          }
        }
      },
    )
  list.append(delays, times)
}

// ------------------------------------------------------------------------- ticks

/// What a tick token prints (the row's duration over its tick time) against how many
/// times a cast of the ability applies the row to a unit it strikes.
fn tick_outcomes(
  tables tables: store.Tables,
  asked asked: List(Asked),
) -> List(Outcome) {
  list.map(
    asked_with(asked:, kind: tooltip_token.Eff, fields: ["ticktimems"]),
    fn(entry) {
      let root = plan_of(base: entry.base)
      let duration =
        printed(
          tables:,
          root:,
          token: tooltip_token.Token(..entry.token, field: "durationms"),
        )
      case printed(tables:, root:, token: entry.token), duration {
        Ok(tick_ms), Ok(duration_ms) if tick_ms > 0 ->
          case
            drive(
              plans: spell_tables.fixture_plans(),
              base: entry.base,
              struck: support.hits([struck_unit]),
            )
          {
            Ok(driven) ->
              Compared(
                asked: entry,
                expected: duration_ms / tick_ms,
                got: list.length(applied_delays(
                  drive: driven,
                  effect_id: entry.token.id,
                )),
              )
            Error(results) ->
              Unobserved(asked: entry, why: reason(unread: Refused(results:)))
          }
        _, _ ->
          Unobserved(
            asked: entry,
            why: "the table has no ticking row of that id",
          )
      }
    },
  )
}

// ------------------------------------------------------------------------- tests

pub fn electrocute_goes_6_times_each_striking_with_the_damage_row_its_text_names_test() -> Nil {
  use <- owned_test.run(30_000)
  let tables = fixture_tables.shared()
  let assert Ok(tokens) = tooltip_token.load()
  let electrocute = plan_of(base: 25_473)
  assert electrocute.spell4_id.value == 41_276
  let pulse_token =
    tooltip_token.Token(
      kind: tooltip_token.Spell,
      id: 41_276,
      field: "channelpulsems",
    )
  let named = tooltip_token.of_text(tokens:, text_id: 360_105)
  assert list.contains(named, pulse_token)
    as "text 360105 names Electrocute's channelPulseMS"
  assert list.contains(
    named,
    tooltip_token.Token(kind: tooltip_token.Eff, id: 92_587, field: "input0pct"),
  )
    as "text 360105 names the damage row 92587"
  let assert Ok(pulse) = printed(tables:, root: electrocute, token: pulse_token)
  let assert Ok(driven) =
    drive(plans: spell_tables.fixture_plans(), base: 25_473, struck: [])
    as "Electrocute is cast by a player that holds it"
  let goes = goes_of(drive: driven)
  assert list.length(goes) == 6
    as "Spell4.41276: channelInitialDelay 500, channelPulseTime 500, channelMaxTime 3000: (3000 - 500 + 500) / 500 goes (0x14053d1f0)"
  assert list.map(goes, fn(go) { go.1.phase }) == [0, 1, 2, 3, 4, 5]
    as "opcode.0x7f4.phase: a go for each pulse"
  assert list.map(goes, fn(go) { go.0 })
    == list.map([1, 2, 3, 4, 5, 6], fn(number) { number * pulse })
    as "the goes come each channelPulseMS the text names"
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

pub fn every_buff_time_token_on_a_row_a_planned_ability_holds_equals_that_rows_life_on_its_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let outcomes = buff_time_outcomes(tables:, asked: asked_of(tables:))
  assert unobserved(outcomes:) == buff_rows_no_plan_holds
  assert mismatches(outcomes:) == []
  assert list.length(outcomes) - list.length(buff_rows_no_plan_holds) == 10
    as "ten duration tokens name a row a plan holds"
}

/// The tick tokens whose row the cast rule never applies, each until the issue that
/// plans ticking effects closes it.
const tick_gaps = [
  Gap(ability: 31_779, token: "eff=121345.ticktimems", issue: "#336"),
  Gap(ability: 38_012, token: "eff=178429.ticktimems", issue: "#336"),
]

pub fn every_tick_time_token_gives_its_duration_over_its_tick_time_ticks_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let outcomes = tick_outcomes(tables:, asked: asked_of(tables:))
  assert unobserved(outcomes:)
    == [
      #(
        31_213,
        "eff=187681.ticktimems",
        "the table has no ticking row of that id",
      ),
    ]
  assert verdict(mismatches: mismatches(outcomes:), gaps: tick_gaps)
    == Verdict(unlisted: [], stale: [])
}

pub fn every_delay_cast_time_and_cooldown_token_matches_the_rules_go_time_and_cooldown_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let outcomes = timing_outcomes(tables:, asked: asked_of(tables:))
  assert unobserved(outcomes:) == []
  assert mismatches(outcomes:) == []
  assert list.length(outcomes) == 3
    as "one delay (177530), one cast time (Quick Draw) and one cooldown (Charged Shot)"
}

pub fn a_buff_time_token_that_differs_from_the_rule_is_reported_with_ability_text_token_expected_and_got_test() -> Nil {
  use <- owned_test.run(60_000)
  // The edit is the point of the test: Spell4Effects 83827 (a control row of Spell4
  // 38780, base 23173) holds a durationTime of 2500; the printed side reads 2600, and
  // the rule reads the plans built from the unchanged rows.
  let outcomes =
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 83_827,
      with: [#("durationTime", planted_table.Integer(2600))],
      body: fn(tables) { buff_time_outcomes(tables:, asked: asked_of(tables:)) },
    )
  assert mismatches(outcomes:)
    == [
      Mismatch(
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
  let tables = fixture_tables.shared()
  let asked = asked_of(tables:)
  // Control row 83827 of base 23173 agrees with the rule, so a gap listing it is stale.
  let passing =
    Gap(ability: 23_173, token: "eff=83827.durationms", issue: "#336")
  assert verdict(
      mismatches: mismatches(outcomes: buff_time_outcomes(tables:, asked:)),
      gaps: [passing],
    )
    == Verdict(unlisted: [], stale: [passing])
  // The tick gaps still differ, so with none listed the test names each difference.
  let ticks = mismatches(outcomes: tick_outcomes(tables:, asked:))
  assert verdict(mismatches: ticks, gaps: []).unlisted == ticks
  assert list.length(ticks) == 3
}

pub fn every_planned_ability_with_a_pulses_token_goes_the_pulses_its_channel_makes_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let asked = asked_of(tables:)
  let outcomes = pulse_outcomes(tables:, asked:)
  assert list.length(outcomes) >= 2
    as "Electrocute 41276 and Discharge 58832 each name a pulse"
  assert unobserved(outcomes:) == []
  assert verdict(mismatches: mismatches(outcomes:), gaps: [])
    == Verdict(unlisted: [], stale: [])
  let times = channel_outcomes(tables:, asked:)
  assert unobserved(outcomes: times) == []
  assert mismatches(outcomes: times) == []
}

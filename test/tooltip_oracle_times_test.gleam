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
import genesis_prime/game/cast.{type State}
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import genesis_prime/tooltip_token.{type Token}
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import owned_test
import planted_table
import spell_tables
import tooltip_oracle_support.{
  type Asked, type Drive, type Held, type Outcome, type Rows, type Unread, Asked,
  CastsStarted, Compared, CooldownNotBracketed, Differs, Gap, HeldAs,
  HeldControl, HeldElsewhere, HeldLasting, HeldModifier, LeftOut,
  ModifierChanges, NeverApplied, NeverFinished, NoCooldownForMethod, NoRow,
  NodeHeldBy, NotInPlan, NotPeriodicProxy, PressNotHeld, Refused, Rows,
  UnknownField, Unobserved, Verdict, applications, asked_of, asked_with,
  caster_of, child_casts, compared_count, differences, drive, finish_in, goes_in,
  goes_of, holder_of, left_out_count, plan_of, reason, removal_in, shared,
  start_ms, started_of, striking_none, striking_with_states, verdict,
}

// ------------------------------------------------------------ what a token prints

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

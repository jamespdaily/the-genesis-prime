//// What each planned ability's tooltip says about the rows its effects strike and the
//// amounts they change, against what the cast rule does with the client's rows. A token
//// `$(eff=N.fieldK...)` prints a column of the Spell4Effects row N (`0x1404de8d0`): `input`
//// the row's computed value, `dataKrawInt` the bits of its dataBits0K as an integer,
//// `dataKpct` and `dataKpctAdd` the float of those bits as a percent, `dataKmsf` that float
//// as seconds. A token `$(spell=N.aoeTc)` prints the target count of the spell's
//// Spell4AoeTargetConstraints row, `sc` the cap of its Spell4StackGroup row (fact 9286) and
//// `cost0` and `cost1` its two innate costs (`0x1404df2c0`). The cast rule is driven on a
//// clock the test owns, with the ability pressed as a player that holds it, and gives the
//// outcome of the same row: the rows its goes strike, the gain a go makes of a class
//// resource slot, the armor a state removes from a creature, the change a modifier makes to
//// a unit property, the cooldown a modifier leaves, the units an area strikes, the holds a
//// stack group keeps and the payment of a press. One test for each outcome class compares
//// the two for every token the planned abilities' texts hold, and reports a difference as
//// the ability, the text, the token, the value it prints and the value the rule gives.
////
//// Expected values come from the client:
//// - The row each token prints is read from its own column: dataBits0K for `dataK` and
////   Spell4AoeTargetConstraints.targetCount, Spell4StackGroup.stackCap and Spell4
////   innateCost0 and innateCost1 for the spell tokens. No expected value is read from what
////   the test's support feeds the rule.
//// - A gain of effect type 1 gives the caster's slot the row's amount when its prerequisite
////   holds (`Spell4Effects.effectType.1`, migration 0018 for the Pulse Blast row).
//// - A state of effect type 4 takes `dataBits03` points from a creature's Interrupt Armor
////   instead of landing (`Spell4Effects.effectType.4`, `UnitProperty2.InterruptArmor_Threshold`).
//// - Types 11 and 145 change a unit property by the float of dataBits02, 03 and 04 (type 11:
////   multiplier, flat amount, amount for each level) and dataBits02 (type 145: the share)
////   for the row's time (`Spell4Effects.effectType.11.change`).
//// - Type 73 changes the cooldowns its selector picks by the float of dataBits03: the time
////   left times it, no longer than it was (operation 0), times it (1), plus it in
////   milliseconds (2) or set to it in milliseconds (3) (`0x1404e07d0`, the effect class at
////   `0x140b6e0a0`).
//// - A go of an area spell strikes at most Spell4AoeTargetConstraints.targetCount units of
////   those in its range (`Spell4AoeTargetConstraints.targetCount`).
//// - A spell of a stack group of a cap of 1 or more is held at most that many times
////   (`Spell4StackGroup.stackCap`); the client reads a stack group only at load and in
////   tooltips, so which hold the rule takes off at the cap (the oldest, `lasting.pushed_off`)
////   is the server's rule, which the test reports and takes for no client fact.
//// - A cost of a type 5 to 11 is paid from the resource slot that type less 5, and any other
////   type from a slot of the player class that names that vital (`0x1403b3320`,
////   `0x1405e7980`).
////
//// A token the rule differs from, or whose outcome the test cannot read, is a gap of the
//// test that names the open issue whose planned work closes it; a listed gap that the rule
//// now matches fails the test.

import attacker_support
import cast_support as support
import fixture_tables
import genesis_prime/game/area
import genesis_prime/game/cast
import genesis_prime/game/class_resource
import genesis_prime/game/cooldown
import genesis_prime/game/lasting
import genesis_prime/game/shown
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/strike
import genesis_prime/game/unit_properties
import genesis_prime/message/float32
import genesis_prime/message/spell_go
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/class
import genesis_prime/table/id.{
  ClassId, Spell4AoeTargetConstraintsId, Spell4BaseId, Spell4EffectsId, Spell4Id,
  Spell4StackGroupId,
}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import genesis_prime/table/spell4_stack_group
import genesis_prime/tooltip_token
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_life
import genesis_prime/world_map/creature_path
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string
import map_support
import owned_test
import place_support
import planted_table
import properties_support
import spell_tables
import tooltip_oracle_support.{
  type Asked, type Difference, type Drive, type Outcome, type Rows, type Unread,
  Asked, ClassMechanicSlot, Compared, Differs, Gap, HeldAs, HeldControl,
  HeldElsewhere, HeldModifier, LeftOut, ModifierChanges, NeverApplied,
  NeverStruck, NoAreaRow, NoHold, NoPayment, NoRow, NoRuleValue, NotInPlan,
  OutsideTheTypes, Refused, Rows, SlotGainsDiffer, Unobserved, Verdict,
} as oracle

// ------------------------------------------------------------------- the rows read

/// The client's committed rows, and the plans built from them with the server's Proxy row
/// of migration 0018 planted, as the connection plants it.
fn effect_rows() -> Rows {
  Rows(
    tables: fixture_tables.shared(),
    plans: spell_tables.plans_with_server_proxies(),
  )
}

/// The Spell4Effects row a token names.
fn effect_of(
  rows rows: Rows,
  entry entry: Asked,
) -> Result(Spell4Effects, Unread) {
  spell4_effects.get(tables: rows.tables, id: Spell4EffectsId(entry.token.id))
  |> result.replace_error(NoRow)
}

/// The number K of a field `dataK...`.
fn data_index(field field: String) -> Result(Int, Nil) {
  use <- bool.guard(
    when: !string.starts_with(field, "data"),
    return: Error(Nil),
  )
  int.parse(string.slice(field, 4, 2))
}

/// The dataBits0K column of the row (`0x1404de8d0`: an index of 10 or more prints nothing).
fn column(row row: Spell4Effects, index index: Int) -> Result(Int, Unread) {
  case index {
    0 -> Ok(row.data_bits00)
    1 -> Ok(row.data_bits01)
    2 -> Ok(row.data_bits02)
    3 -> Ok(row.data_bits03)
    4 -> Ok(row.data_bits04)
    5 -> Ok(row.data_bits05)
    6 -> Ok(row.data_bits06)
    7 -> Ok(row.data_bits07)
    8 -> Ok(row.data_bits08)
    9 -> Ok(row.data_bits09)
    _ -> Error(NoRuleValue(column: index))
  }
}

/// Two values read, or the reason one was not.
fn outcome(
  entry entry: Asked,
  expected expected: Result(Int, Unread),
  got got: Result(Int, Unread),
) -> Outcome {
  case expected, got {
    Ok(expected), Ok(got) -> Compared(asked: entry, expected:, got:)
    Error(why), _ | _, Error(why) -> Unobserved(asked: entry, why:)
  }
}

/// The `eff` tokens of the asked list that print a data column.
fn data_tokens(asked asked: List(Asked)) -> List(Asked) {
  list.filter(asked, fn(entry) {
    entry.token.kind == tooltip_token.Eff
    && string.starts_with(entry.token.field, "data")
  })
}

/// The `eff` tokens of the asked list that print the row's computed value.
fn input_tokens(asked asked: List(Asked)) -> List(Asked) {
  list.filter(asked, fn(entry) {
    entry.token.kind == tooltip_token.Eff
    && string.starts_with(entry.token.field, "input")
  })
}

/// The first press of the attempt, made by the plain caster and then by a caster of each
/// playable class holding the resource, that the rule does not refuse.
fn first_taken(
  casters casters: List(cast.Caster),
  attempt attempt: fn(cast.Caster) -> Result(Drive, List(Int)),
) -> Result(Drive, Unread) {
  taking(casters:, attempt:, last: NoPayment)
}

/// The first press of the casters the rule does not refuse; else why the last was refused.
fn taking(
  casters casters: List(cast.Caster),
  attempt attempt: fn(cast.Caster) -> Result(Drive, List(Int)),
  last last: Unread,
) -> Result(Drive, Unread) {
  case casters {
    [] -> Error(last)
    [caster, ..rest] ->
      case attempt(caster) {
        Ok(driven) -> Ok(driven)
        Error(results) ->
          taking(casters: rest, attempt:, last: Refused(results:))
      }
  }
}

/// The drives of the whole ability whose goes strike the unit and land its states: one press
/// of an ability that goes at its press, and one release at each charge level of a
/// ChargeRelease ability, since each level casts a stage of its own.
fn whole_drives(
  rows rows: Rows,
  entry entry: Asked,
) -> Result(List(Drive), Unread) {
  let root = oracle.plan_of(rows:, base: entry.base)
  let strikes = oracle.striking_with_states(root:)
  let casters = paying_casters(base: entry.base, amounts: [100])
  let charged = root.method == spell_plan.ChargeRelease && root.stages != []
  let attempts = case charged {
    True ->
      list.index_map(root.stages, fn(_, level) {
        fn(caster) {
          oracle.drive_released(
            caster:,
            plans: rows.plans,
            base: entry.base,
            level:,
            strikes:,
          )
        }
      })
    False ->
      list.map(facings(), fn(poses) {
        fn(caster) {
          oracle.drive_posed(caster:, plans: rows.plans, strikes:, poses:)
        }
      })
  }
  list.try_map(attempts, fn(attempt) { first_taken(casters:, attempt:) })
}

/// The poses the struck unit has in the caster's picture: none, and one facing each way a
/// Proxy's target gate of the plan tells apart, the unit in an arc of prerequisite type 108
/// or outside it (`prerequisite.arc_verdict`).
fn facings() -> List(dict.Dict(Int, area.Pose)) {
  let facing = fn(yaw) {
    let pose = area.Pose(at: area.Point(x: 5.0, z: 0.0), yaw:)
    dict.from_list([#(oracle.struck_unit, pose), #(0, pose)])
  }
  [dict.new(), facing(0.0), facing(1.5707963)]
}

// ------------------------------------------------------------------ rows struck

/// The Spell4Effects ids a drive's goes strike: the damage rows of the phase each go is of,
/// the rows a go lists on a unit, and the rows that change the caster.
fn struck_rows(drive driven: Drive) -> List(Int) {
  let asked = list.flat_map(driven.steps, fn(step) { step.asked })
  let spell_of = fn(go: spell_go.SpellGo) {
    list.find(asked, fn(question) {
      question.cast_id == go.cast_id && question.phase == go.phase
    })
    |> result.map(fn(question) { { question.spell4_id }.value })
    |> result.lazy_or(fn() {
      list.find(oracle.started_of(drive: driven), fn(started) {
        started.1.cast_id == go.cast_id
      })
      |> result.map(fn(started) { started.1.spell4_id })
    })
  }
  let from_goes =
    list.flat_map(oracle.all_goes(drive: driven), fn(timed) {
      let go = timed.1
      let damage =
        spell_of(go)
        |> result.map(damage_rows(spell4_id: _, phase: go.phase))
        |> result.unwrap([])
      let listed =
        list.flat_map(go.targets, fn(target) {
          list.map(target.effects, fn(info) { info.spell4_effects_id })
        })
      list.append(damage, listed)
    })
  let changing =
    list.flat_map(driven.steps, fn(step) {
      list.map(support.caster_change_starts(effects: step.effects), fn(start) {
        { start.0 }.effect_id.value
      })
    })
  list.append(from_goes, changing)
}

/// The damage rows of the phase of the spell's area; none when the spell has no area or the
/// phase has no strike.
fn damage_rows(spell4_id spell4_id: Int, phase phase: Int) -> List(Int) {
  spell_area.of_spell(
    areas: spell_tables.fixture_areas(),
    spell4_id: Spell4Id(spell4_id),
  )
  |> result.try(fn(area_of) {
    spell_area.phase(spell: area_of, phase:, spent: None)
  })
  |> result.map(fn(strike) {
    list.map(strike.damage, fn(damage) { damage.effect_id.value })
  })
  |> result.unwrap([])
}

/// Whether a go of the ability strikes the row: the token's id when it does, else 0.
fn input_outcome(rows rows: Rows, entry entry: Asked) -> Outcome {
  let root = oracle.plan_of(rows:, base: entry.base)
  case effect_of(rows:, entry:) {
    Error(why) -> Unobserved(asked: entry, why:)
    Ok(_) ->
      case whole_drives(rows:, entry:) {
        Error(why) -> Unobserved(asked: entry, why:)
        Ok(drives) ->
          case
            list.any(drives, fn(driven) {
              list.contains(struck_rows(drive: driven), entry.token.id)
            })
          {
            True ->
              Compared(
                asked: entry,
                expected: entry.token.id,
                got: entry.token.id,
              )
            False -> unreached(rows:, entry:, root:)
          }
      }
  }
}

/// A row no go of the drive strikes is no row of the ability's plan, or one the rule never
/// strikes.
fn unreached(rows rows: Rows, entry entry: Asked, root root: Spell) -> Outcome {
  case
    spell4_effects.get(tables: rows.tables, id: Spell4EffectsId(entry.token.id))
  {
    Error(Nil) -> Unobserved(asked: entry, why: NoRow)
    Ok(row) ->
      case
        list.any(
          spell_plan.tree(spell: root, started: fn(_) { True }),
          fn(spell) { spell.spell4_id.value == row.spell_id },
        )
      {
        True -> Compared(asked: entry, expected: entry.token.id, got: 0)
        False -> Unobserved(asked: entry, why: NotInPlan)
      }
  }
}

// ----------------------------------------------------------- gains, control, change

/// Every gain of a class resource the drive made.
fn gains_in(drive driven: Drive) -> List(class_resource.Gain) {
  list.flat_map(driven.steps, fn(step) {
    list.flatten(support.gains(effects: step.effects))
  })
}

/// What the drive gained into the slot, all its gains added, or nothing when it gained none.
fn gained_into(slot slot: Int, drive driven: Drive) -> Result(Int, Nil) {
  case list.filter(gains_in(drive: driven), fn(gain) { gain.slot == slot }) {
    [] -> Error(Nil)
    made -> Ok(int.sum(list.map(made, fn(gain) { gain.amount })))
  }
}

/// What a type 1 token prints against what the drive's gains of the row's slot make. A slot
/// is gained the amounts of all the rows that gain into it, so when the texts of the ability
/// name several of those rows by the same column, the printed amounts are summed.
fn gain_outcome(
  rows rows: Rows,
  entry entry: Asked,
  asked asked: List(Asked),
) -> Outcome {
  let root = oracle.plan_of(rows:, base: entry.base)
  case gain_of(root:, effect_id: entry.token.id) {
    Error(Nil) -> Unobserved(asked: entry, why: NotInPlan)
    Ok(spell_plan.TickingGain(..)) ->
      Unobserved(asked: entry, why: HeldAs(list: "ticking gain"))
    Ok(spell_plan.Gain(slot:, ..)) ->
      outcome(
        entry:,
        expected: printed_total(rows:, entry:, asked:, root:, slot:),
        got: {
          use drives <- result.try(whole_drives(rows:, entry:))
          let totals =
            list.filter_map(drives, gained_into(slot:, drive: _))
            |> list.unique
          case totals {
            [] -> Error(NeverApplied)
            [total] -> Ok(total)
            _ -> Error(SlotGainsDiffer(slot:))
          }
        },
      )
  }
}

/// The sum of the printed column over the distinct rows the ability's texts name by the
/// token's field and that gain into the slot.
fn printed_total(
  rows rows: Rows,
  entry entry: Asked,
  asked asked: List(Asked),
  root root: Spell,
  slot slot: Int,
) -> Result(Int, Unread) {
  use index <- result.try(
    data_index(field: entry.token.field)
    |> result.replace_error(NoRuleValue(column: -1)),
  )
  let gaining = gaining_rows(root:, slot:)
  list.filter_map(asked, fn(other) {
    case
      other.base == entry.base
      && other.token.kind == tooltip_token.Eff
      && other.token.field == entry.token.field
      && list.contains(gaining, other.token.id)
    {
      True -> Ok(other.token.id)
      False -> Error(Nil)
    }
  })
  |> list.unique
  |> list.try_map(fn(id) {
    use row <- result.try(
      spell4_effects.get(tables: rows.tables, id: Spell4EffectsId(id))
      |> result.replace_error(NoRow),
    )
    column(row:, index:)
  })
  |> result.map(int.sum)
}

/// The distinct rows of the ability's plan that gain into the slot, in the spells of its tree
/// and the Proxies of those.
fn gaining_rows(root root: Spell, slot slot: Int) -> List(Int) {
  let into = fn(gains: List(spell_plan.Gain)) {
    list.filter_map(gains, fn(gain) {
      case gain {
        spell_plan.Gain(slot: gained, effect_id:, ..) if gained == slot ->
          Ok(effect_id.value)
        spell_plan.Gain(..) | spell_plan.TickingGain(..) -> Error(Nil)
      }
    })
  }
  spell_plan.tree(spell: root, started: fn(_) { True })
  |> list.flat_map(fn(spell) {
    list.append(
      into(spell.gains),
      list.flat_map(spell.proxies, fn(proxy) { into(proxy.gains) }),
    )
  })
  |> list.unique
}

/// The plan's gain of the row: held by a spell of the tree, or by a Proxy of one when it is
/// given to the units a go struck.
fn gain_of(
  root root: Spell,
  effect_id effect_id: Int,
) -> Result(spell_plan.Gain, Nil) {
  let is = fn(gain: spell_plan.Gain) { gain.effect_id.value == effect_id }
  list.find_map(
    spell_plan.tree(spell: root, started: fn(_) { True }),
    fn(spell) {
      case list.find(spell.gains, is) {
        Ok(gain) -> Ok(gain)
        Error(Nil) ->
          list.find_map(spell.proxies, fn(proxy) { list.find(proxy.gains, is) })
      }
    },
  )
}

/// Whether a go of the drive lists the row on a unit.
fn listed(drive driven: Drive, effect_id effect_id: Int) -> Bool {
  let casts = [
    driven.cast_id,
    ..list.map(oracle.started_of(drive: driven), fn(started) {
      started.1.cast_id
    })
  ]
  list.any(casts, fn(cast_id) {
    oracle.applications(drive: driven, cast_id:, effect_id:) != []
  })
}

/// The points of Interrupt Armor a creature of 1000 loses to the state, which a state of
/// effect type 4 takes in place of landing (`creature_control`).
fn armor_removed(row row: spell_plan.CrowdControl) -> Int {
  let armor = creature_life.Armor(points: 1000)
  let landing = oracle.landing_of(rows: [row], armor:, at_ms: oracle.start_ms)
  case creature_control.armor_now(state: landing.state, armor:) {
    Some(left) -> 1000 - left
    None -> 0
  }
}

/// What a type 4 token prints against the armor the row takes from a creature, once a go of
/// the drive lists the row.
fn control_outcome(
  rows rows: Rows,
  entry entry: Asked,
  row row: Spell4Effects,
) -> Outcome {
  let root = oracle.plan_of(rows:, base: entry.base)
  let expected =
    data_index(field: entry.token.field)
    |> result.replace_error(NoRuleValue(column: -1))
    |> result.try(fn(index) { column(row:, index:) })
  case oracle.holder_of(root:, effect_id: entry.token.id) {
    Error(Nil) -> Unobserved(asked: entry, why: NotInPlan)
    Ok(#(_, HeldControl(row: control))) ->
      outcome(entry:, expected:, got: {
        use drives <- result.try(whole_drives(rows:, entry:))
        case
          list.any(drives, fn(driven) {
            listed(drive: driven, effect_id: entry.token.id)
          })
        {
          True -> Ok(armor_removed(row: control))
          False -> Error(NeverApplied)
        }
      })
    Ok(#(_, HeldElsewhere(list:))) ->
      Unobserved(asked: entry, why: HeldAs(list:))
    Ok(#(_, _)) ->
      Unobserved(asked: entry, why: HeldAs(list: "state that is no control"))
  }
}

/// The value of the rule's modifier that the dataK column names, as a 32-bit float's bits.
fn modifier_bits(
  modifier modifier: unit_properties.Modifier,
  index index: Int,
) -> Result(Int, Unread) {
  let none = Error(NoRuleValue(column: index))
  case modifier {
    unit_properties.Change(multiplier:, flat:, per_level:, ..) ->
      case index {
        2 -> Ok(float32.to_bits(value: multiplier))
        3 -> Ok(float32.to_bits(value: flat))
        4 -> Ok(float32.to_bits(value: per_level))
        _ -> none
      }
    unit_properties.Conversion(share:, ..) ->
      case index {
        2 -> Ok(float32.to_bits(value: share))
        _ -> none
      }
  }
}

/// What a type 11 or 145 token prints against the change the cast starts on the caster.
fn property_outcome(
  rows rows: Rows,
  entry entry: Asked,
  row row: Spell4Effects,
) -> Outcome {
  let root = oracle.plan_of(rows:, base: entry.base)
  let index =
    data_index(field: entry.token.field)
    |> result.replace_error(NoRuleValue(column: -1))
  let expected = {
    use index <- result.try(index)
    use bits <- result.map(column(row:, index:))
    int.bitwise_and(bits, 0xFFFFFFFF)
  }
  case oracle.holder_of(root:, effect_id: entry.token.id) {
    Error(Nil) -> unplanned_property(rows:, entry:, expected:, index:)
    Ok(#(_, HeldModifier(..))) ->
      outcome(
        entry:,
        expected:,
        got: result.try(index, started_bits(rows:, entry:, index: _)),
      )
    Ok(#(_, HeldElsewhere(list:))) ->
      Unobserved(asked: entry, why: HeldAs(list:))
    Ok(#(_, _)) ->
      Unobserved(
        asked: entry,
        why: HeldAs(list: "change that is no property modifier"),
      )
  }
}

/// The Stalker's stealth ability (Spell4Base 30075, Spell4 46073) and its passive (Spell4Base
/// 29131, Spell4 45057): leaving stealth by the second press fires the passive's Proc 211002,
/// which casts Spell4 79932 on the caster, whose rows no spell of the ability's own plan holds
/// (`Spell4Effects` 210998 to 212530 have spellId 79932 and targetFlags 1 or 3).
const stealth_base = 30_075

const stealth_passive_base = 29_131

/// A property-modifier token of a row no spell of the ability's plan holds: the ability with
/// its passive held, pressed twice, as a player out of combat, the second press leaving stealth.
/// The row the token names is then read from the change the second press starts.
fn unplanned_property(
  rows rows: Rows,
  entry entry: Asked,
  expected expected: Result(Int, Unread),
  index index: Result(Int, Unread),
) -> Outcome {
  use <- bool.guard(
    when: entry.base != stealth_base,
    return: Unobserved(asked: entry, why: NotInPlan),
  )
  outcome(entry:, expected:, got: {
    use index <- result.try(index)
    use effects <- result.try(leaving_stealth(rows:))
    bits_started(effects:, entry:, index:)
  })
}

/// The effects of the passive's start and of the two presses of the stealth ability, as the
/// client's player makes them (`cast.passive_started`, two 0x9a presses of the ability's
/// place in the bag), each answered with no unit struck.
fn leaving_stealth(rows rows: Rows) -> Result(List(cast.Effect), Unread) {
  let caster =
    cast.Caster(..oracle.caster_of(base: stealth_base), in_combat: False)
  let #(state, joined) =
    cast.passive_started(
      cast: cast.new(),
      caster:,
      plans: rows.plans,
      base: Spell4BaseId(stealth_passive_base),
      now: support.at(ms: oracle.start_ms),
    )
  let #(state, joined) =
    support.answered_as(
      caster:,
      state:,
      effects: joined,
      at: oracle.start_ms,
      struck: [],
      rolls: [],
    )
  let press = fn(state, ms) {
    let #(state, raw) =
      support.pressed_raw_in(
        plans: rows.plans,
        state:,
        caster:,
        bag_index: 0,
        target: 0,
        at: ms,
      )
    case support.refusal_results(effects: raw) {
      [] ->
        Ok(
          support.answered_as(
            caster:,
            state:,
            effects: raw,
            at: ms,
            struck: [],
            rolls: [],
          ),
        )
      results -> Error(Refused(results:))
    }
  }
  use #(state, entered) <- result.try(press(state, oracle.start_ms + 1000))
  use #(_, left) <- result.map(press(state, oracle.start_ms + 2000))
  list.flatten([joined, entered, left])
}

/// The bits of column `index` of the one property modifier the drives of the ability start
/// from the row.
fn started_bits(
  rows rows: Rows,
  entry entry: Asked,
  index index: Int,
) -> Result(Int, Unread) {
  use drives <- result.try(whole_drives(rows:, entry:))
  let effects =
    list.flat_map(drives, fn(driven) { driven.steps })
    |> list.flat_map(fn(step) { step.effects })
  bits_started(effects:, entry:, index:)
}

/// The bits of column `index` of the one property modifier the effects start from the row.
fn bits_started(
  effects effects: List(cast.Effect),
  entry entry: Asked,
  index index: Int,
) -> Result(Int, Unread) {
  let started =
    support.property_starts(effects:)
    |> list.filter(fn(start) { { start.0 }.effect_id.value == entry.token.id })
    |> list.map(fn(start) { start.1 })
    |> list.unique
  case started {
    [] -> Error(NeverApplied)
    [modifier] -> modifier_bits(modifier:, index:)
    more -> Error(ModifierChanges(count: list.length(more)))
  }
}

// ---------------------------------------------------------------------- cooldowns

/// The ids of a spell that the selector picks.
fn picked_by(selector selector: cooldown.Selector) -> cooldown.Keys {
  case selector {
    cooldown.Base(base) ->
      cooldown.keys(
        spell4_id: Spell4Id(1),
        spell4_base_id: base,
        spell_groups: [],
        cooldown_groups: [],
      )
    cooldown.Spell(spell4_id) ->
      cooldown.keys(
        spell4_id:,
        spell4_base_id: Spell4BaseId(1),
        spell_groups: [],
        cooldown_groups: [],
      )
    cooldown.SpellGroup(group) ->
      cooldown.keys(
        spell4_id: Spell4Id(1),
        spell4_base_id: Spell4BaseId(1),
        spell_groups: [group],
        cooldown_groups: [],
      )
    cooldown.CooldownGroup(group) ->
      cooldown.keys(
        spell4_id: Spell4Id(1),
        spell4_base_id: Spell4BaseId(1),
        spell_groups: [],
        cooldown_groups: [group],
      )
    cooldown.EverySpell(..) ->
      cooldown.keys(
        spell4_id: Spell4Id(1),
        spell4_base_id: Spell4BaseId(1),
        spell_groups: [],
        cooldown_groups: [],
      )
  }
}

/// The cooldown a spell the selector picks has left from a cooldown of 10 s once the
/// modifier is applied to it, in the unit of the modifier's float: milliseconds for an
/// addition or a set time, thousandths of the time left for a factor.
fn cooldown_change(modifier modifier: cooldown.Modifier) -> Int {
  let whole = 10_000
  let keys = picked_by(selector: modifier.selector)
  let book =
    cooldown.start(book: cooldown.new(), keys:, cooldown_ms: whole, now_ms: 0)
  let after =
    cooldown.left_ms(
      book: cooldown.modify(book:, modifier:, now_ms: 0),
      spell4_id: keys_spell4(selector: modifier.selector),
      now_ms: 0,
    )
  case modifier.operation {
    cooldown.NoLonger(..) | cooldown.Multiply(..) -> after * 1000 / whole
    cooldown.AddMs(..) -> after - whole
    cooldown.SetMs(..) -> after
    cooldown.Unchanged(..) -> after - whole
  }
}

/// The Spell4 id `picked_by` gives the keys of the selector.
fn keys_spell4(selector selector: cooldown.Selector) -> id.Spell4Id {
  case selector {
    cooldown.Spell(spell4_id) -> spell4_id
    cooldown.Base(..)
    | cooldown.SpellGroup(..)
    | cooldown.CooldownGroup(..)
    | cooldown.EverySpell(..) -> Spell4Id(1)
  }
}

/// What the row's float prints, in the unit `cooldown_change` gives: thousandths for a
/// factor, milliseconds otherwise, the absolute value for an `abs` field.
fn printed_change(
  operation operation: cooldown.Operation,
  value value: Float,
  field field: String,
) -> Int {
  let shown = case operation {
    cooldown.NoLonger(..) | cooldown.Multiply(..) ->
      float.round(value *. 1000.0)
    cooldown.AddMs(..) | cooldown.SetMs(..) | cooldown.Unchanged(..) ->
      float.round(value)
  }
  case string.contains(field, "abs") {
    True -> int.absolute_value(shown)
    False -> shown
  }
}

/// What a type 73 token prints against the cooldown the plan's modifier leaves.
fn cooldown_outcome(
  rows rows: Rows,
  entry entry: Asked,
  row row: Spell4Effects,
) -> Outcome {
  let root = oracle.plan_of(rows:, base: entry.base)
  case oracle.holder_of(root:, effect_id: entry.token.id) {
    Error(Nil) -> Unobserved(asked: entry, why: NotInPlan)
    Ok(#(holder, _)) ->
      case
        list.find(holder.cooldown_modifiers, fn(planned) {
          planned.effect_id.value == entry.token.id
        })
      {
        Error(Nil) -> Unobserved(asked: entry, why: NotInPlan)
        Ok(planned) -> planned_change(entry:, row:, planned:)
      }
  }
}

/// A type 73 token against the cooldown change of the planned modifier: only column 3, the
/// change itself, has a value the rule gives.
fn planned_change(
  entry entry: Asked,
  row row: Spell4Effects,
  planned planned: spell_plan.CooldownModifier,
) -> Outcome {
  case data_index(field: entry.token.field) {
    Ok(3) ->
      case float32.of_column(number: row.data_bits03) {
        Error(Nil) -> Unobserved(asked: entry, why: NoRuleValue(column: 3))
        Ok(value) -> {
          let changed = cooldown_change(modifier: planned.modifier)
          let got = case string.contains(entry.token.field, "abs") {
            True -> int.absolute_value(changed)
            False -> changed
          }
          Compared(
            asked: entry,
            expected: printed_change(
              operation: planned.modifier.operation,
              value:,
              field: entry.token.field,
            ),
            got:,
          )
        }
      }
    Ok(index) -> Unobserved(asked: entry, why: NoRuleValue(column: index))
    Error(Nil) -> Unobserved(asked: entry, why: NoRuleValue(column: -1))
  }
}

// ---------------------------------------------------------------- the effect classes

/// What every data token of the asked list prints against what the rule does with the row
/// of the type the token names.
fn effect_outcomes(rows rows: Rows, asked asked: List(Asked)) -> List(Outcome) {
  list.map(data_tokens(asked:), fn(entry) {
    case effect_of(rows:, entry:) {
      Error(why) -> Unobserved(asked: entry, why:)
      Ok(row) ->
        case row.effect_type {
          1 -> gain_outcome(rows:, entry:, asked:)
          4 -> control_outcome(rows:, entry:, row:)
          11 | 145 -> property_outcome(rows:, entry:, row:)
          73 -> cooldown_outcome(rows:, entry:, row:)
          effect_type ->
            Unobserved(asked: entry, why: OutsideTheTypes(effect_type:))
        }
    }
  })
}

/// What every input token of the asked list names against the rows the drive strikes.
fn input_outcomes(rows rows: Rows, asked asked: List(Asked)) -> List(Outcome) {
  list.map(input_tokens(asked:), fn(entry) { input_outcome(rows:, entry:) })
}

// -------------------------------------------------------------------- target caps

/// What an `aoeTc` token prints against the units a go of the spell strikes when one more
/// unit than the cap stands in its range, as `strike.select` chooses them: for a cast on the
/// caster itself and for a cast on a foe of the crowd, the larger count.
fn target_cap_outcome(rows rows: Rows, entry entry: Asked) -> Outcome {
  let spell4_id = Spell4Id(entry.token.id)
  let printed = {
    use record <- result.try(
      spell4.get(tables: rows.tables, id: spell4_id)
      |> result.replace_error(NoRow),
    )
    spell4_aoe_target_constraints.get(
      tables: rows.tables,
      id: Spell4AoeTargetConstraintsId(record.spell4_aoe_target_constraints_id),
    )
    |> result.replace_error(NoAreaRow)
    |> result.map(fn(constraints) { constraints.target_count })
  }
  let struck = case
    spell_area.of_spell(areas: spell_tables.fixture_areas(), spell4_id:)
  {
    Error(Nil) -> Error(NotInPlan)
    Ok(spell_area.SpellArea(row: None, ..)) -> Error(NoAreaRow)
    Ok(spell_area.SpellArea(row: Some(row), ..) as spell) ->
      case area_phase(spell:) {
        Error(Nil) -> Error(NeverStruck)
        Ok(phase) ->
          Ok(int.max(
            selected(spell:, row:, phase:, on_a_foe: False),
            selected(spell:, row:, phase:, on_a_foe: True),
          ))
      }
  }
  outcome(entry:, expected: printed, got: struck)
}

/// The first go of the spell that selects units from its area.
fn area_phase(spell spell: spell_area.SpellArea) -> Result(Int, Nil) {
  numbers(count: spell_area.phase_count(spell:))
  |> list.map(fn(number) { number - 1 })
  |> list.find(fn(phase) {
    case spell_area.phase(spell:, phase:, spent: None) {
      Ok(strike) -> strike.selects_area
      Error(Nil) -> False
    }
  })
}

/// The units `strike.select` takes for a go of the phase with one more foe than the area's
/// cap in its range, straight ahead at the middle of its range: the foes stand around the
/// caster for a cast on the caster, and around the foe the cast is on, which stands in the
/// range itself, for a cast on a foe.
fn selected(
  spell spell: spell_area.SpellArea,
  row row: area.Row,
  phase phase: Int,
  on_a_foe on_a_foe: Bool,
) -> Int {
  let caster = 7
  let foe = 21
  let middle = { row.min_range +. row.max_range } /. 2.0
  let foes =
    list.map(numbers(count: row.target_count + 1), fn(n) { n + foe - 1 })
  let primary = case on_a_foe {
    True -> foe
    False -> caster
  }
  let picture =
    list.map(foes, fn(unit_id) {
      let ahead = case unit_id == foe && on_a_foe {
        True -> 1.0
        False -> middle
      }
      let behind = case on_a_foe && unit_id != foe {
        True -> 1.0 +. middle
        False -> 0.0
      }
      #(unit_id, foe_at(z: float.negate(ahead +. behind)))
    })
    |> dict.from_list
  strike.select(
    asked: cast.GoAsked(
      cast_id: 5,
      phase:,
      spell4_id: spell.spell4_id,
      primary_target: primary,
      spent: None,
    ),
    attacker: caster_of_the_go(unit_id: caster),
    picture:,
    areas: spell_tables.fixture_areas(),
    now_ms: 0,
  ).units
  |> list.length
}

/// A foe a player of either faction may attack, standing still at the depth.
fn foe_at(z z: Float) -> shown.Shown {
  shown.ShownCreature(
    path: creature_path.Standing(at: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x: 0.0,
      y: 0.0,
      z:,
    )),
    life: 4,
    alive: True,
    hit_radius: 100.0,
    attackable: creature_life.Attackable(exile: True, dominion: True),
  )
}

/// The player that casts: an Exile at the origin facing the way the foes stand.
fn caster_of_the_go(unit_id unit_id: Int) -> strike.Attacker {
  strike.Attacker(
    unit_id:,
    connection: ConnectionId(2),
    pose: area.Pose(at: area.Point(x: 0.0, z: 0.0), yaw: 0.0),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
    move_seq: 1,
    stay: map_support.stay(count: 1),
    faction: shown.Exile,
    stats: attacker_support.novice(),
    properties: properties_support.fresh(level: 1),
  )
}

/// The numbers 1 to count.
fn numbers(count count: Int) -> List(Int) {
  int.range(from: count, to: 0, with: [], run: list.prepend)
}

/// The `spell` tokens of the asked list that print a target count.
fn target_cap_outcomes(
  rows rows: Rows,
  asked asked: List(Asked),
) -> List(Outcome) {
  list.filter(asked, fn(entry) {
    entry.token.kind == tooltip_token.Spell && entry.token.field == "aoetc"
  })
  |> list.map(fn(entry) { target_cap_outcome(rows:, entry:) })
}

// ------------------------------------------------------------- stacks and payments

/// A spell of a planned ability's tree that the rows put in a stack group of a cap of 1 or
/// more: the ability it is of, the spell as the plan holds it, and the group and cap of its
/// Spell4 and Spell4StackGroup rows (`Spell4.spell4StackGroupId`, `Spell4StackGroup.stackCap`).
type Stacked {
  Stacked(base: Int, spell: Spell, group_id: Int, cap: Int, cast_time_ms: Int)
}

/// The spells of the planned abilities' trees whose rows are in a stack group of a cap of 1 or
/// more, once each. The plan's own stack is not read: a spell the plan gives no cap is chosen
/// the same, and the rule is read for it.
fn stacked_spells(rows rows: Rows) -> List(Stacked) {
  list.flat_map(oracle.planned(rows:), fn(root) {
    spell_plan.tree(spell: root, started: fn(_) { True })
    |> list.filter_map(fn(spell) {
      use record <- result.try(
        spell4.get(tables: rows.tables, id: spell.spell4_id)
        |> result.replace_error(Nil),
      )
      use group <- result.try(
        spell4_stack_group.get(
          tables: rows.tables,
          id: Spell4StackGroupId(record.spell4_stack_group_id),
        )
        |> result.replace_error(Nil),
      )
      case group.stack_cap >= 1 {
        True ->
          Ok(Stacked(
            base: root.spell4_base_id.value,
            spell:,
            group_id: group.id,
            cap: group.stack_cap,
            cast_time_ms: record.cast_time,
          ))
        False -> Error(Nil)
      }
    })
  })
  |> list.unique
}

/// The `sc` token the stack group of the spell would print: no text of the planned
/// abilities holds one, so it is the token the client's evaluator forms for the spell
/// (`0x1404df2c0`).
fn stack_token(stacked stacked: Stacked) -> Asked {
  Asked(
    base: stacked.base,
    text_id: 0,
    token: tooltip_token.Token(
      kind: tooltip_token.Spell,
      id: stacked.spell.spell4_id.value,
      field: "sc",
    ),
  )
}

/// The time between two presses of a spell: longer than the longest cooldown of the planned
/// spells (Spell4.spellCoolDown, 60 s), so no press is refused for one. The rule ends a node
/// only when its timer fires, and the test fires none past a press's go.
const between_presses_ms = 120_000

/// What a unit holds of a stack group after a spell's presses: the holds and whether the
/// oldest of those it held before the last press remains.
type Kept {
  Kept(holds: Int, oldest_kept: Bool)
}

/// The holds of the group (or of the spell) the caster has on itself.
fn group_holds(
  state state: cast.State,
  caster caster: cast.Caster,
  stacked stacked: Stacked,
) -> List(lasting.Hold) {
  cast.holds_on(cast: state, unit_id: caster.unit_id)
  |> list.filter(fn(hold: lasting.Hold) {
    hold.stack.group_id == stacked.group_id
    || hold.spell4_id == stacked.spell.spell4_id
  })
}

/// The caster pressing the spell cap plus one times, each press at its time, its go taken and
/// the timers up to the end of its cast time fired: what the caster holds then, and whether
/// the oldest hold it had before the last press is still among them.
fn kept_after_the_cap_and_one(
  rows rows: Rows,
  stacked stacked: Stacked,
) -> Result(Kept, Unread) {
  let caster = oracle.caster_of(base: stacked.spell.spell4_base_id.value)
  let plans = support.with_spells(plans: rows.plans, spells: [stacked.spell])
  use #(_, before_last, held) <- result.try(
    list.try_fold(
      numbers(count: stacked.cap + 1),
      #(cast.new(), [], []),
      fn(so_far, number) {
        let at_ms = number * between_presses_ms
        use #(state, pressed) <- result.try(
          oracle.pressed_at(
            caster:,
            plans:,
            state: so_far.0,
            at_ms:,
            strikes: oracle.striking_none,
            poses: dict.new(),
          )
          |> result.map_error(fn(results) { Refused(results:) }),
        )
        let #(state, _) =
          support.run_timers_posed(
            caster:,
            state:,
            effects: pressed.effects,
            from_ms: at_ms,
            struck_at: oracle.striking_none,
            poses: dict.new(),
            until_ms: Some(at_ms + stacked.cast_time_ms),
          )
        Ok(#(state, so_far.2, group_holds(state:, caster:, stacked:)))
      },
    ),
  )
  case
    list.sort(before_last, fn(a: lasting.Hold, b: lasting.Hold) {
      int.compare(a.started_ms, b.started_ms)
      |> order.break_tie(int.compare(a.cast_id, b.cast_id))
    })
  {
    [] -> Error(NoHold)
    [oldest, ..] ->
      Ok(Kept(
        holds: list.length(held),
        oldest_kept: list.any(held, fn(hold) { hold.cast_id == oldest.cast_id }),
      ))
  }
}

/// The `sc` tokens of the stacked spells, each with what the caster holds after the cap plus
/// one presses of the spell.
fn stack_kept(
  rows rows: Rows,
) -> List(#(Asked, Stacked, Result(Kept, Unread))) {
  list.map(stacked_spells(rows:), fn(stacked) {
    #(
      stack_token(stacked:),
      stacked,
      kept_after_the_cap_and_one(rows:, stacked:),
    )
  })
}

/// What an `sc` token prints (the cap of the spell's stack group row) against the holds the
/// caster keeps after the cap plus one presses.
fn stack_outcomes(rows rows: Rows) -> List(Outcome) {
  list.map(stack_kept(rows:), fn(entry) {
    let #(asked, stacked, kept) = entry
    outcome(
      entry: asked,
      expected: Ok(stacked.cap),
      got: result.map(kept, fn(kept) { kept.holds }),
    )
  })
}

/// The `sc` tokens of the spells whose oldest hold before the last press the caster still has
/// after it: the rule takes the oldest off (the server's rule, `lasting.pushed_off`).
fn stacks_that_kept_the_oldest(rows rows: Rows) -> List(Asked) {
  list.filter_map(stack_kept(rows:), fn(entry) {
    case entry.2 {
      Ok(Kept(oldest_kept: True, ..)) -> Ok(entry.0)
      Ok(Kept(oldest_kept: False, ..)) | Error(_) -> Error(Nil)
    }
  })
}

/// The casters that may pay a press of the ability: the plain one, then each playable class
/// holding each of the amounts, so the first press that is not refused pays.
fn paying_casters(
  base base: Int,
  amounts amounts: List(Int),
) -> List(cast.Caster) {
  let plain = oracle.caster_of(base:)
  [
    plain,
    ..list.flat_map(class_resource.playable_class_ids(), fn(class_id) {
      list.map(amounts, fn(value) {
        cast.Caster(
          ..plain,
          resources: support.holding(class_id:, value: int.to_float(value)),
        )
      })
    })
  ]
}

/// What the whole cast of the ability pays (a cast with a cast time pays when it finishes, so
/// the payments are those of every step of the drive), by the first caster that is not refused:
/// each playable class holding exactly the token's amount, since a cost that takes every point
/// held takes the amount only from a caster that holds no more, and then the plain caster.
fn payments_of(
  rows rows: Rows,
  base base: Int,
  amount amount: Int,
) -> Result(List(class_resource.Payment), Unread) {
  let plain = oracle.caster_of(base:)
  let casters =
    list.append(
      list.map(class_resource.playable_class_ids(), fn(class_id) {
        cast.Caster(
          ..plain,
          resources: support.holding(class_id:, value: int.to_float(amount)),
        )
      }),
      [plain],
    )
  first_taken(casters:, attempt: fn(caster) {
    oracle.drive_as(caster:, plans: rows.plans, strikes: oracle.striking_none)
  })
  |> result.map(fn(driven) {
    list.flat_map(driven.steps, fn(step) {
      support.payments(effects: step.effects)
    })
  })
}

/// The resource slots the client's cost check reads for a cost type of an ability: the types
/// 5 to 11 are the caster's resource slots 0 to 6 (`CheckInnateCost`, `0x1403b3320`); any other
/// type goes to the class mechanic, which passes at the first of the player class's slots that
/// name that vital (`Class.vitalEnumResource00` to `07`) whose value can pay it, so every such
/// slot may be the one paid (`CheckClassResourceCost`, `0x1405e7980`).
fn client_slots_of(
  rows rows: Rows,
  base base: Int,
  cost_type cost_type: Int,
) -> Result(List(Int), Unread) {
  use <- bool.guard(
    when: cost_type >= 5 && cost_type <= 11,
    return: Ok([cost_type - 5]),
  )
  let assert Ok(base_row) =
    spell4_base.get(tables: rows.tables, id: Spell4BaseId(base))
    as "a planned ability has a Spell4Base row"
  let assert Ok(class_row) =
    class.get(tables: rows.tables, id: ClassId(base_row.class_id_player))
    as "an ability's player class has a Class row"
  let slots =
    [
      class_row.vital_enum_resource00,
      class_row.vital_enum_resource01,
      class_row.vital_enum_resource02,
      class_row.vital_enum_resource03,
      class_row.vital_enum_resource04,
      class_row.vital_enum_resource05,
      class_row.vital_enum_resource06,
      class_row.vital_enum_resource07,
    ]
    |> list.index_map(fn(vital, slot) { #(slot, vital) })
    |> list.filter(fn(pair) { pair.1 == cost_type })
    |> list.map(fn(pair) { pair.0 })
  case slots {
    [] -> Error(ClassMechanicSlot(cost_type:))
    slots -> Ok(slots)
  }
}

/// The slot the press pays from against the slots the client's check may read: the paid slot
/// is the expected one when the client may read it, else the first slot it reads is.
fn slot_outcome(
  entry entry: Asked,
  slots slots: Result(List(Int), Unread),
  got got: Result(Int, Unread),
) -> Outcome {
  let expected =
    result.map(slots, fn(slots) {
      // No slot is -1, so a press that pays nothing is read from none of the slots.
      let paid = result.unwrap(got, -1)
      use <- bool.guard(when: list.contains(slots, paid), return: paid)
      result.unwrap(list.first(slots), -1)
    })
  outcome(entry:, expected:, got:)
}

/// The `cost0` and `cost1` tokens the planned abilities' spells would print: no text of
/// the planned abilities holds one, so each is the token the client's evaluator forms for
/// the spell's innate cost (`0x1404df2c0`). Each cost is compared twice: the amount the token
/// prints with the amount the press pays, and (under the field `cost0slot` or `cost1slot`,
/// which is no token of the client's but names this comparison) the resource slot the client's
/// check reads for the cost's type with the slot the press pays from.
fn cost_outcomes(rows rows: Rows) -> List(Outcome) {
  list.flat_map(oracle.planned(rows:), fn(root) {
    let assert Ok(record) = spell4.get(tables: rows.tables, id: root.spell4_id)
      as "a planned ability has a Spell4 row"
    [
      #("cost0", 0, record.innate_cost0, record.innate_cost_type0),
      #("cost1", 1, record.innate_cost1, record.innate_cost_type1),
    ]
    |> list.filter(fn(place) { place.2 > 0 })
    |> list.flat_map(fn(place) {
      let entry = fn(field) {
        Asked(
          base: root.spell4_base_id.value,
          text_id: 0,
          token: tooltip_token.Token(
            kind: tooltip_token.Spell,
            id: root.spell4_id.value,
            field:,
          ),
        )
      }
      let paid =
        payments_of(rows:, base: root.spell4_base_id.value, amount: place.2)
        |> result.try(fn(payments) {
          case list.drop(payments, place.1) {
            [payment, ..] -> Ok(payment)
            [] -> Error(NoPayment)
          }
        })
      [
        outcome(
          entry: entry(place.0),
          expected: Ok(place.2),
          got: result.map(paid, fn(payment) { payment.amount }),
        ),
        slot_outcome(
          entry: entry(place.0 <> "slot"),
          slots: client_slots_of(
            rows:,
            base: root.spell4_base_id.value,
            cost_type: place.3,
          ),
          got: result.map(paid, fn(payment) { payment.slot }),
        ),
      ]
    })
  })
}

// ------------------------------------------------------------------------- tests

/// The tokens that name rows no go of the ability strikes: 196652 is the surged spell of
/// Quick Draw, which no plan casts until Spell Surge casts it (#520), and 123743 is the
/// damage row of Eradication ExoSuit's spell 52370, started by a Proc of a kind the plan does
/// not read (`ProcKindNotRead`, spell 52371), which ticking and proc effects of #336's work
/// would read.
const input_gaps = [
  Gap(ability: 27_638, token: "eff=196652.input0pct", issue: "#520"),
  Gap(ability: 31_779, token: "eff=123743.input0pct", issue: "#336"),
]

/// The tokens whose row the rule does not read, each until the issue whose planned work
/// closes it. Types 3 (ForcedMove), 14 (Proc) and 24 (ForcedAction) are none of the types
/// this oracle reads, and row 229304 is held by spell 45000, which Proxy 104216 of the unplanned spell 44999
/// casts; #336 names forced moves, crowd control and ticking effects, and no issue names
/// procs or forced actions, so those rows are put to the coordinator with the hand-back.
const effect_gaps = [
  Gap(ability: 20_325, token: "eff=67776.data02int", issue: "#336"),
  Gap(ability: 29_131, token: "eff=146910.data03pct", issue: "#336"),
  Gap(ability: 30_075, token: "eff=146910.data03pct", issue: "#336"),
  Gap(ability: 31_779, token: "eff=229304.data02pct", issue: "#336"),
  Gap(ability: 31_779, token: "eff=123744.data04ms", issue: "#336"),
]

/// The aoeTc token of Eradication ExoSuit's Proc spell 52370, which no plan strikes with
/// until procs are read (#336).
const target_cap_gaps = [
  Gap(ability: 31_779, token: "spell=52370.aoetc", issue: "#336"),
]

pub fn pulse_blast_in_combat_gives_15_of_slot_1_through_the_server_proxy_row_its_text_names_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  let assert Ok(tokens) = tooltip_token.load()
  let token =
    tooltip_token.Token(
      kind: tooltip_token.Eff,
      id: 95_337,
      field: "data02rawint",
    )
  assert list.contains(tooltip_token.of_text(tokens:, text_id: 376_222), token)
    as "text 376222 names the Volatility row's data02rawInt"
  let asked = Asked(base: 26_468, text_id: 376_222, token:)
  let assert Ok(row) = effect_of(rows:, entry: asked)
  assert row.data_bits02 == 15
    as "Spell4Effects 95337, a VitalModifier of vital 6 behind prerequisite 903, holds 15 in dataBits02"
  let root = oracle.plan_of(rows:, base: 26_468)
  let assert Ok(driven) =
    oracle.drive(
      plans: rows.plans,
      base: 26_468,
      strikes: oracle.striking_with_states(root:),
    )
  assert gains_in(drive: driven) == [class_resource.Gain(slot: 1, amount: 15)]
    as "a Pulse Blast in combat gives slot 1 the 15 the text prints, through the server's Proxy row"
  let assert Ok(quiet) =
    oracle.drive_as(
      caster: cast.Caster(..oracle.caster_of(base: 26_468), in_combat: False),
      plans: rows.plans,
      strikes: oracle.striking_with_states(root:),
    )
  assert gains_in(drive: quiet) == []
    as "prerequisite 903 is that the caster is in combat, so out of combat the gain is withheld"
  let without_proxy = Rows(..rows, plans: spell_tables.fixture_plans())
  assert effect_outcomes(rows: without_proxy, asked: [asked])
    == [Unobserved(asked:, why: NotInPlan)]
    as "without the server's Proxy row no plan holds the gain, which is the miss the oracle exists to see"
  assert effect_outcomes(rows:, asked: [asked])
    == [Compared(asked:, expected: 15, got: 15)]
}

pub fn every_input_token_names_a_row_a_go_of_the_ability_strikes_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  let outcomes = input_outcomes(rows:, asked: oracle.asked_of(rows:))
  assert oracle.verdict(
      differences: oracle.differences(outcomes:),
      gaps: input_gaps,
    )
    == Verdict(unlisted: [], stale: [])
  assert oracle.compared_count(outcomes:) == 27
  assert oracle.left_out_count(outcomes:) == 2
}

pub fn every_gain_control_property_and_cooldown_change_token_matches_the_rules_effect_for_its_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  let outcomes = effect_outcomes(rows:, asked: oracle.asked_of(rows:))
  assert oracle.verdict(
      differences: oracle.differences(outcomes:),
      gaps: effect_gaps,
    )
    == Verdict(unlisted: [], stale: [])
  assert oracle.compared_count(outcomes:) == 17
  assert oracle.left_out_count(outcomes:) == 5
}

pub fn every_aoetc_token_caps_the_struck_count_with_one_more_unit_in_range_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  let outcomes = target_cap_outcomes(rows:, asked: oracle.asked_of(rows:))
  assert oracle.verdict(
      differences: oracle.differences(outcomes:),
      gaps: target_cap_gaps,
    )
    == Verdict(unlisted: [], stale: [])
  assert oracle.compared_count(outcomes:) == 16
  assert oracle.left_out_count(outcomes:) == 1
}

pub fn every_sc_and_cost_token_matches_the_stack_count_after_cap_plus_one_casts_and_the_payment_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  let stacks = stack_outcomes(rows:)
  let differences = oracle.differences(outcomes: stacks)
  assert list.filter(differences, is_differs) == []
  assert stacks_that_kept_the_oldest(rows:) == []
  assert oracle.compared_count(outcomes: stacks) == 22
  // The spells the drive reads nothing for: twelve whose cast leaves no hold of their group on
  // the caster (some hold another spell's, such as 41869's, which holds 77116's casts of group
  // 1770), and Spell Surge 47273, whose press the plain caster is refused 151 for (Prerequisite
  // 29484 wants 25 Spell Power).
  assert list.filter_map(differences, left_out_of)
    == [
      #(
        "spell=53865.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=87353.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=30900.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=41869.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=70775.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=38791.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=79229.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=41276.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=60724.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=60868.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #("spell=47273.sc", "the press is refused 151"),
      #(
        "spell=79697.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
      #(
        "spell=60796.sc",
        "the spell's cast leaves no hold of its stack group on the caster",
      ),
    ]
  let costs = cost_outcomes(rows:)
  assert oracle.verdict(
      differences: oracle.differences(outcomes: costs),
      gaps: [],
    )
    == Verdict(unlisted: [], stale: [])
  assert oracle.compared_count(outcomes: costs) == 8
    as "the four costs of the planned abilities, each by its amount and its slot"
}

fn is_differs(difference: Difference) -> Bool {
  case difference {
    Differs(..) -> True
    LeftOut(..) -> False
  }
}

fn left_out_of(difference: Difference) -> Result(#(String, String), Nil) {
  case difference {
    Differs(..) -> Error(Nil)
    LeftOut(token:, why:, ..) -> Ok(#(token, why))
  }
}

pub fn a_stack_group_the_plan_gives_no_cap_is_reported_when_its_row_gives_one_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4StackGroup 2 holds a cap of 0 in the committed rows and the plans are built from
  // them, so the rule keeps one cast of each spell of the group. The edit gives the group's row
  // a cap of 4 that the plans do not have: spell 60947 of ability 18309 (Spell4StackGroupId 2)
  // holds a node on its caster, so the tooltip would print 4 stacks of a spell the rule keeps
  // 1 of.
  let differing =
    fixture_tables.changed(
      table: "Spell4StackGroup",
      id: 2,
      with: [#("stackCap", planted_table.Integer(4))],
      body: fn(tables) {
        let rows =
          Rows(tables:, plans: spell_tables.plans_with_server_proxies())
        oracle.differences(outcomes: stack_outcomes(rows:))
      },
    )
  assert list.contains(
    differing,
    Differs(
      ability: 18_309,
      text_id: 0,
      token: "spell=60947.sc",
      expected: 4,
      got: 1,
    ),
  )
}

pub fn a_cost_type_edited_on_the_heap_is_reported_by_the_slot_the_press_pays_from_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  // The first planned ability whose first cost is of a type the client reads as a fixed
  // resource slot (5 to 11). The edit gives the row the next type, which the client reads as
  // the next slot, while the plans built from the unchanged rows still pay from the old one.
  let assert Ok(#(root, record)) =
    list.find_map(oracle.planned(rows:), fn(root) {
      let assert Ok(record) =
        spell4.get(tables: rows.tables, id: root.spell4_id)
        as "a planned ability has a Spell4 row"
      case
        record.innate_cost0 > 0
        && record.innate_cost_type0 >= 5
        && record.innate_cost_type0 <= 10
      {
        True -> Ok(#(root, record))
        False -> Error(Nil)
      }
    })
    as "a planned ability pays its first cost from a fixed resource slot"
  let differing =
    fixture_tables.changed(
      table: "Spell4",
      id: root.spell4_id.value,
      with: [
        #(
          "innateCostType0",
          planted_table.Integer(record.innate_cost_type0 + 1),
        ),
      ],
      body: fn(tables) {
        let rows =
          Rows(tables:, plans: spell_tables.plans_with_server_proxies())
        oracle.differences(outcomes: cost_outcomes(rows:))
        |> list.filter(is_differs)
      },
    )
  assert differing
    == [
      Differs(
        ability: root.spell4_base_id.value,
        text_id: 0,
        token: "spell=" <> int.to_string(root.spell4_id.value) <> ".cost0slot",
        expected: record.innate_cost_type0 - 4,
        got: record.innate_cost_type0 - 5,
      ),
    ]
}

pub fn an_effect_row_edited_on_the_heap_is_reported_with_ability_text_token_expected_and_got_test() -> Nil {
  use <- owned_test.run(60_000)
  // The edit is the point of the test: Spell4Effects 95337 holds 15 in dataBits02; the
  // printed side reads 16, and the rule reads the plans built from the unchanged rows.
  let differing =
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 95_337,
      with: [#("dataBits02", planted_table.Integer(16))],
      body: fn(tables) {
        let rows =
          Rows(tables:, plans: spell_tables.plans_with_server_proxies())
        oracle.differences(outcomes: effect_outcomes(
          rows:,
          asked: oracle.asked_of(rows:),
        ))
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
        ability: 26_468,
        text_id: 376_222,
        token: "eff=95337.data02rawint",
        expected: 16,
        got: 15,
      ),
    ]
}

pub fn a_listed_effect_gap_that_now_passes_fails_the_test_naming_the_gap_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  let outcomes = effect_outcomes(rows:, asked: oracle.asked_of(rows:))
  // Pulse Blast's gain of 15 agrees with the rule, so a gap listing it is stale.
  let passing =
    Gap(ability: 26_468, token: "eff=95337.data02rawint", issue: "#336")
  assert oracle.verdict(differences: oracle.differences(outcomes:), gaps: [
      passing,
      ..effect_gaps
    ])
    == Verdict(unlisted: [], stale: [passing])
  assert oracle.verdict(differences: oracle.differences(outcomes:), gaps: []).unlisted
    == oracle.differences(outcomes:)
}

pub fn a_slot_gained_by_two_rows_is_compared_with_the_sum_of_the_amounts_the_texts_print_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = effect_rows()
  // Ability 18309's plan holds two rows that gain into slot 1; its text 240824 names one of
  // them. Naming the other as well, in the same column, adds its amount to what is printed.
  let named =
    Asked(
      base: 18_309,
      text_id: 240_824,
      token: tooltip_token.Token(
        kind: tooltip_token.Eff,
        id: 127_603,
        field: "data02rawint",
      ),
    )
  let root = oracle.plan_of(rows:, base: 18_309)
  let assert [other_id] =
    gaining_rows(root:, slot: 1)
    |> list.filter(fn(id) { id != 127_603 })
    as "the plan holds exactly one other row that gains into slot 1"
  let other =
    Asked(..named, token: tooltip_token.Token(..named.token, id: other_id))
  let assert Ok(named_row) = effect_of(rows:, entry: named)
  let assert Ok(other_row) = effect_of(rows:, entry: other)
  assert named_row.effect_type == 1 && other_row.effect_type == 1
    as "both are gains of a class resource"
  let assert Compared(expected: printed_alone, got: made, ..) =
    gain_outcome(rows:, entry: named, asked: [named])
  let assert Compared(expected: printed_together, got: made_together, ..) =
    gain_outcome(rows:, entry: named, asked: [named, other])
  assert printed_alone == named_row.data_bits02
    as "with one row named, the printed amount is that row's"
  assert printed_together == named_row.data_bits02 + other_row.data_bits02
    as "with both named, the printed amounts are summed"
  assert made_together == made
    as "what the drive gains does not depend on what the text names"
}

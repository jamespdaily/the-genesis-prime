//// The plan and the coverage measure take one decision about each effect row
//// (`genesis_prime/game/spell_plan` `read_row`); this plans every Spell4 row of the client's
//// tables alone and checks that decision against the plan, which guards the one way the
//// two can still drift: a refusal added to the plan's load outside `read_row`.
////
//// The expected agreement is the rule itself, with the plan as the evidence:
//// - a spell that loads holds in its lists exactly the rows `read_row` reads `Applied` or
////   `Held`, and the rows in no list read `LeftOut` or, for a damage row, `ReadByArea`;
//// - a spell the load refuses with an error that names an effect row gives that row the
////   same error from `read_row` (a heal, armor or absorb on a struck unit: the same row and
////   kind, whichever Proxy starts the child);
//// - a spell refused with a missing table row or a cycle of prerequisites, which a row's
////   own columns can also cause, gives some row of the spell's tree the same error from
////   `read_row`; with none it is a refusal of a spell column, unless only effect rows read
////   the table (a display), which is a disagreement;
//// - the place of a row is the one the measure computes for its spell
////   (`genesis_prime/coverage/effect_row` `places`), except that the spell planned alone is
////   no Proxy's child: its own rows are read where nothing starts it on each struck unit;
//// - a spell refused for a column of its own (a cost, a requirement, a cycle of Proxies, a
////   stealth condition, a phase or a threshold) is listed by its error and not compared:
////   each of its rows is counted by its own columns.

import client_tables
import genesis_prime/coverage/effect_row
import genesis_prime/game/effect_kind
import genesis_prime/game/spell_plan.{
  type PlanError, type RowReading, type Spell, Applied, Held, LeftOut,
  ReadByArea,
}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import genesis_prime/table/spell4_thresholds
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

/// One row the plan and `read_row` take differently: the spell planned, the row and each
/// side's verdict.
pub type Disagreement {
  Disagreement(spell4_id: Int, effect_id: Int, plan: String, read_row: String)
}

fn describe_reading(reading: Result(RowReading, PlanError)) -> String {
  case reading {
    Ok(Applied(..)) -> "Applied"
    Ok(Held(..)) -> "Held"
    Ok(LeftOut(..)) -> "LeftOut"
    Ok(ReadByArea) -> "ReadByArea"
    Error(error) -> "refused: " <> spell_plan.describe(error:)
  }
}

/// What a refusal of a spell's load names: an effect row, or a column of the spell, a table
/// row the tree names or a cycle.
type Refusal {
  NamesARow(effect_id: Int)
  /// A heal, armor or absorb on a struck unit, which the Proxy that starts the child does
  /// not tell apart.
  NamesAStruckRow(effect_id: Int, kind: String)
  /// An error a row of the tree or a column of a spell can cause; `only_rows_read_it` when
  /// no column of a spell reads the table.
  MayNameARow(kind: String, only_rows_read_it: Bool)
  NamesNoRow(kind: String)
}

fn effect_row_of(error: PlanError) -> Refusal {
  case error {
    spell_plan.NoRow(table:, ..) ->
      MayNameARow(
        kind: "a table row the tree names",
        only_rows_read_it: list.contains(
          ["ItemDisplay", "Item2Type", "ItemSlot"],
          table,
        ),
      )
    spell_plan.ProxyCycle(..) -> NamesNoRow("a cycle of Proxies")
    spell_plan.UnreadCost(..) -> NamesNoRow("a cost")
    spell_plan.UnreadRequirement(..) -> NamesNoRow("a requirement")
    spell_plan.ChannelWithoutPulse(..) -> NamesNoRow("a channel")
    spell_plan.NoThresholdTime(..) -> NamesNoRow("a threshold")
    spell_plan.StealthConditionNotRead(..) -> NamesNoRow("a stealth condition")
    spell_plan.StealthChangeNotRead(..) -> NamesNoRow("a stealth change")
    spell_plan.InnateFailed(..) -> NamesNoRow("an innate")
    spell_plan.PrerequisiteCycle(..) ->
      MayNameARow(kind: "a cycle of prerequisites", only_rows_read_it: False)
    spell_plan.ShieldHealOnStruckUnit(effect_id:, ..) ->
      NamesAStruckRow(effect_id:, kind: "a heal")
    spell_plan.InterruptArmorOnStruckUnit(effect_id:, ..) ->
      NamesAStruckRow(effect_id:, kind: "Interrupt Armor")
    spell_plan.AbsorptionOnStruckUnit(effect_id:, ..) ->
      NamesAStruckRow(effect_id:, kind: "an absorb")
    spell_plan.ProxyAimNotRead(effect_id:, ..)
    | spell_plan.GainAimNotRead(effect_id:, ..)
    | spell_plan.GainVitalNotRead(effect_id:, ..)
    | spell_plan.GainTargetPrerequisiteNotRead(effect_id:, ..)
    | spell_plan.SpendComparisonNotRead(effect_id:, ..)
    | spell_plan.ForceRemoveSelectorNotRead(effect_id:, ..)
    | spell_plan.ForceRemoveCountsDiffer(effect_id:, ..)
    | spell_plan.LastingAimNotRead(effect_id:, ..)
    | spell_plan.ControlStateNotRead(effect_id:, ..)
    | spell_plan.ControlAimNotRead(effect_id:, ..)
    | spell_plan.ControlPrerequisiteNotRead(effect_id:, ..)
    | spell_plan.ModifierPropertyHasNoRow(effect_id:, ..)
    | spell_plan.ModifierNumberNotFinite(effect_id:, ..)
    | spell_plan.CooldownNumberNotFinite(effect_id:, ..)
    | spell_plan.StealthAimNotRead(effect_id:, ..)
    | spell_plan.StealthTargetPrerequisiteNotRead(effect_id:, ..)
    | spell_plan.StealthTimedNotRead(effect_id:, ..)
    | spell_plan.StealthBreaksNotRead(effect_id:, ..)
    | spell_plan.ShieldHealParameterNotRead(effect_id:, ..)
    | spell_plan.ShieldHealNumberNotFinite(effect_id:, ..)
    | spell_plan.InterruptArmorTakeBackNotRead(effect_id:, ..)
    | spell_plan.AbsorptionParameterNotRead(effect_id:, ..)
    | spell_plan.AbsorptionNumberNotFinite(effect_id:, ..)
    | spell_plan.AbsorptionAmountNotRead(effect_id:, ..)
    | spell_plan.AbsorptionPeriodic(effect_id:, ..)
    | spell_plan.AbsorptionHasNoLifetime(effect_id:, ..)
    | spell_plan.ProcKindNotRead(effect_id:, ..)
    | spell_plan.ProcNotRead(effect_id:, ..)
    | spell_plan.DisguiseNotRead(effect_id:, ..) -> NamesARow(effect_id:)
  }
}

/// Where the plans of every spell disagree with `read`, and how many spells each kind of
/// spell-column refusal accounts for.
type Comparison {
  Comparison(
    disagreements: List(Disagreement),
    loaded: Int,
    refused_by_row: Int,
    refused_for_a_spell_column: Dict(String, Int),
  )
}

/// Plans each of `spell4_ids` with `plan` and compares it with `read`, over the rows of
/// `effects`.
fn compare(
  spell4_ids spell4_ids: List(Int),
  effects effects: List(Spell4Effects),
  children children: fn(Int) -> List(Int),
  plan plan: fn(Int) -> Result(Spell, PlanError),
  read read: fn(Spell4Effects, Int) -> Result(RowReading, PlanError),
) -> Comparison {
  let by_spell = list.group(effects, fn(effect) { effect.spell_id })
  let by_id =
    list.map(effects, fn(effect) { #(effect.id, effect) }) |> dict.from_list
  list.fold(
    spell4_ids,
    Comparison(
      disagreements: [],
      loaded: 0,
      refused_by_row: 0,
      refused_for_a_spell_column: dict.new(),
    ),
    fn(found, spell4_id) {
      case plan(spell4_id) {
        Ok(spell) ->
          Comparison(
            ..found,
            disagreements: list.append(
              found.disagreements,
              loaded_disagreements(
                spell4_id:,
                spell:,
                own: result.unwrap(dict.get(by_spell, spell4_id), []),
                read:,
              ),
            ),
            loaded: found.loaded + 1,
          )
        Error(error) ->
          refused(
            found:,
            spell4_id:,
            error:,
            by_id:,
            tree: tree_rows(root: spell4_id, children:, by_spell:),
            read:,
          )
      }
    },
  )
}

/// The rows of a spell that loads whose list or no list the reading disagrees with.
fn loaded_disagreements(
  spell4_id spell4_id: Int,
  spell spell: Spell,
  own own: List(Spell4Effects),
  read read: fn(Spell4Effects, Int) -> Result(RowReading, PlanError),
) -> List(Disagreement) {
  let listed = spell_tables.listed_effect_ids(spell:)
  list.filter_map(own, fn(effect) {
    let reading = read(effect, spell4_id)
    let in_a_list = list.contains(listed, effect.id)
    case agrees(in_a_list:, reading:) {
      True -> Error(Nil)
      False ->
        Ok(Disagreement(
          spell4_id:,
          effect_id: effect.id,
          plan: case in_a_list {
            True -> "in a list"
            False -> "in no list"
          },
          read_row: describe_reading(reading),
        ))
    }
  })
}

/// Whether a row's reading says what its spell's lists say: `Applied` and `Held` are in a
/// list, `LeftOut` and `ReadByArea` are in none.
fn agrees(
  in_a_list in_a_list: Bool,
  reading reading: Result(RowReading, PlanError),
) -> Bool {
  case reading {
    Ok(Applied(..)) | Ok(Held(..)) -> in_a_list
    Ok(LeftOut(..)) | Ok(ReadByArea) -> !in_a_list
    Error(..) -> False
  }
}

/// The rows of a spell and of every spell below it, by the spells its Proxies, Procs and
/// thresholds name (`children`).
fn tree_rows(
  root root: Int,
  children children: fn(Int) -> List(Int),
  by_spell by_spell: Dict(Int, List(Spell4Effects)),
) -> List(Spell4Effects) {
  walk([root], set.new(), children, by_spell, [])
}

fn walk(
  pending: List(Int),
  seen: Set(Int),
  children: fn(Int) -> List(Int),
  by_spell: Dict(Int, List(Spell4Effects)),
  rows: List(Spell4Effects),
) -> List(Spell4Effects) {
  case pending {
    [] -> rows
    [spell4_id, ..rest] ->
      case set.contains(seen, spell4_id) {
        True -> walk(rest, seen, children, by_spell, rows)
        False ->
          walk(
            list.append(children(spell4_id), rest),
            set.insert(seen, spell4_id),
            children,
            by_spell,
            list.append(rows, result.unwrap(dict.get(by_spell, spell4_id), [])),
          )
      }
  }
}

/// Whether `read` refuses a row with what the plan refused the spell with: the same error,
/// or for a heal, armor or absorb on a struck unit the same row and kind.
fn same_refusal(plan plan: PlanError, read read: PlanError) -> Bool {
  case effect_row_of(plan) {
    NamesAStruckRow(..) as struck -> effect_row_of(read) == struck
    NamesARow(..) | MayNameARow(..) | NamesNoRow(..) -> plan == read
  }
}

/// A spell the load refuses, counted by the row its error names, which `read` must refuse
/// the same way, by a row of its tree that gives the same error when the error can come
/// from a row or from a column of the spell, or by the kind of its error when it names no
/// row.
fn refused(
  found found: Comparison,
  spell4_id spell4_id: Int,
  error error: PlanError,
  by_id by_id: Dict(Int, Spell4Effects),
  tree tree: List(Spell4Effects),
  read read: fn(Spell4Effects, Int) -> Result(RowReading, PlanError),
) -> Comparison {
  case effect_row_of(error) {
    NamesNoRow(kind:) -> in_a_spell_column(found:, kind:)
    MayNameARow(kind:, only_rows_read_it:) ->
      case
        list.any(tree, fn(effect) { read(effect, spell4_id) == Error(error) }),
        only_rows_read_it
      {
        True, _ -> Comparison(..found, refused_by_row: found.refused_by_row + 1)
        False, False -> in_a_spell_column(found:, kind:)
        False, True ->
          Comparison(
            ..found,
            disagreements: list.append(found.disagreements, [
              Disagreement(
                spell4_id:,
                effect_id: 0,
                plan: "refused: " <> spell_plan.describe(error:),
                read_row: "no row of the spell's tree gives the error, and only effect rows read that table",
              ),
            ]),
          )
      }
    NamesARow(effect_id:) | NamesAStruckRow(effect_id:, ..) -> {
      let reading =
        dict.get(by_id, effect_id)
        |> result.map(read(_, spell4_id))
      let agreed = case reading {
        Ok(Error(refusal)) -> same_refusal(plan: error, read: refusal)
        Ok(Ok(..)) | Error(Nil) -> False
      }
      Comparison(
        ..found,
        refused_by_row: found.refused_by_row + 1,
        disagreements: case agreed {
          True -> found.disagreements
          False ->
            list.append(found.disagreements, [
              Disagreement(
                spell4_id:,
                effect_id:,
                plan: "refused: " <> spell_plan.describe(error:),
                read_row: case reading {
                  Ok(reading) -> describe_reading(reading)
                  Error(Nil) -> "the refusal names a row the table lacks"
                },
              ),
            ])
        },
      )
    }
  }
}

fn in_a_spell_column(found found: Comparison, kind kind: String) -> Comparison {
  Comparison(
    ..found,
    refused_for_a_spell_column: dict.upsert(
      found.refused_for_a_spell_column,
      kind,
      fn(count) { option.unwrap(count, 0) + 1 },
    ),
  )
}

fn report(disagreements disagreements: List(Disagreement)) -> String {
  string.join(
    list.map(disagreements, fn(disagreement) {
      "spell "
      <> int.to_string(disagreement.spell4_id)
      <> " row "
      <> int.to_string(disagreement.effect_id)
      <> ": the plan has it "
      <> disagreement.plan
      <> ", read_row gives "
      <> disagreement.read_row
    }),
    "\n",
  )
}

/// The spells a spell starts: those its Proxies and Procs name and its thresholds cast.
fn children_of(
  tables tables: store.Tables,
  effects effects: List(Spell4Effects),
) -> fn(Int) -> List(Int) {
  let named =
    list.group(effects, fn(effect) { effect.spell_id })
    |> dict.map_values(fn(_, rows) {
      list.filter_map(rows, fn(effect) {
        case effect_kind.kind_of(effect.effect_type) {
          effect_kind.Proxy -> Ok(effect.data_bits00)
          effect_kind.Proc -> Ok(effect.data_bits01)
          effect_kind.Damage
          | effect_kind.VitalModifier
          | effect_kind.Fluff
          | effect_kind.ForceRemove
          | effect_kind.CrowdControl
          | effect_kind.PropertyModifier
          | effect_kind.ForcedMove
          | effect_kind.CooldownModifier
          | effect_kind.Stealth
          | effect_kind.RemoveStealth
          | effect_kind.ShieldHeal
          | effect_kind.ShieldOverload
          | effect_kind.InterruptArmor
          | effect_kind.Scale
          | effect_kind.RavelSignal
          | effect_kind.PropertyConversion
          | effect_kind.DisguiseOutfit
          | effect_kind.Absorption
          | effect_kind.Unread(..) -> Error(Nil)
        }
      })
    })
  let cast =
    list.group(spell4_thresholds.all(tables), fn(threshold) {
      threshold.spell4_id_parent
    })
    |> dict.map_values(fn(_, rows) {
      list.map(rows, fn(threshold) { threshold.spell4_id_to_cast })
    })
  fn(spell4_id) {
    list.append(
      result.unwrap(dict.get(named, spell4_id), []),
      result.unwrap(dict.get(cast, spell4_id), []),
    )
  }
}

pub fn every_planned_spell_holds_exactly_the_rows_read_row_keeps_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let effects = spell4_effects.all(tables)
  let place_of = effect_row.places(tables:, effects:)
  let spell_groups = spell_plan.spell_groups(tables:)
  let spell4_ids = list.map(spell4.all(tables), fn(row) { row.id })
  let compared =
    compare(
      spell4_ids:,
      effects:,
      children: children_of(tables:, effects:),
      plan: fn(spell4_id) {
        spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
      },
      read: fn(effect, planned) {
        let place = place_of(effect.spell_id)
        spell_plan.read_row(
          tables:,
          spell_groups:,
          place: case effect.spell_id == planned {
            True -> spell_plan.RowPlace(..place, struck_by: None)
            False -> place
          },
          effect:,
        )
      },
    )
  assert compared.disagreements == []
    as { "the plan and read_row disagree:\n" <> report(compared.disagreements) }
  assert list.length(spell4_ids) == 66_591
    as "`table_rows -- Spell4`: 66,591 spells"
  assert compared.loaded
    + compared.refused_by_row
    + list.fold(dict.values(compared.refused_for_a_spell_column), 0, int.add)
    == 66_591
    as "every spell loads, is refused for a row read_row refuses too, or is listed by its refusal of a spell column"
}

pub fn the_agreement_test_reports_a_spell_the_plan_refuses_for_a_row_read_row_reads_test() -> Nil {
  use <- owned_test.run(60_000)
  // A spell whose load refuses a row outside `read_row`: the planner here refuses the
  // Fluff row 90001 of spell 32893 with a gain's error, which no decision of `read_row`
  // makes, and the planted row is one `read_row` reads.
  let fluff =
    spell_tables.effect_row_with(
      id: 90_001,
      effect_type: 17,
      target_flags: 1,
      columns: [#("durationTime", Integer(5000))],
    )
  let rows =
    spell_tables.Rows(
      ..spell_tables.fixture_rows(),
      spell4_effects: spell_tables.sorted_by_id([
        fluff,
        ..spell_tables.fixture_rows().spell4_effects
      ]),
    )
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows:,
    body: fn(tables) {
      let sources = spell_plan.sources_of(tables:)
      let effects = spell4_effects.all(tables)
      let refused =
        spell_plan.GainAimNotRead(
          spell4_id: 32_893,
          effect_id: 90_001,
          target_flags: 1,
        )
      let compared =
        compare(
          spell4_ids: [32_893],
          effects:,
          children: fn(_) { [] },
          plan: fn(spell4_id) {
            case spell4_id {
              32_893 -> Error(refused)
              other ->
                spell_plan.spell_alone(
                  tables:,
                  sources:,
                  spell4_id: other,
                  chain: [],
                )
            }
          },
          read: fn(effect, _planned) {
            spell_plan.read_row(
              tables:,
              spell_groups: spell_plan.spell_groups(tables:),
              place: spell_tables.pressed,
              effect:,
            )
          },
        )
      assert compared.disagreements
        == [
          Disagreement(
            spell4_id: 32_893,
            effect_id: 90_001,
            plan: "refused: " <> spell_plan.describe(error: refused),
            read_row: "Applied",
          ),
        ]
        as "the test names the spell, the row and both verdicts"
      let listed =
        compare(
          spell4_ids: [32_893],
          effects:,
          children: fn(_) { [] },
          plan: fn(spell4_id) {
            let assert Ok(spell) =
              spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
              as "the planted strike loads"
            Ok(spell_plan.Spell(..spell, lasting: []))
          },
          read: fn(effect, _planned) {
            spell_plan.read_row(
              tables:,
              spell_groups: spell_plan.spell_groups(tables:),
              place: spell_tables.pressed,
              effect:,
            )
          },
        )
      assert list.any(listed.disagreements, fn(disagreement) {
        disagreement.effect_id == 90_001
        && disagreement.plan == "in no list"
        && disagreement.read_row == "Applied"
      })
        as "a row read_row applies that the plan holds in no list is reported too"
    },
  )
}

/// The planted strike with this Fluff row 90001 added, compared where the planner refuses
/// its spell with `refusal`, with the tree of the strike alone.
fn refused_with(
  fluff_columns fluff_columns: List(#(String, planted_table.Cell)),
  refusal refusal: PlanError,
) -> Comparison {
  let rows =
    spell_tables.Rows(
      ..spell_tables.fixture_rows(),
      spell4_effects: spell_tables.sorted_by_id([
        spell_tables.effect_row_with(
          id: 90_001,
          effect_type: 17,
          target_flags: 1,
          columns: fluff_columns,
        ),
        ..spell_tables.fixture_rows().spell4_effects
      ]),
    )
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 647)],
    rows:,
    body: fn(tables) {
      compare(
        spell4_ids: [32_893],
        effects: spell4_effects.all(tables),
        children: fn(_) { [] },
        plan: fn(_) { Error(refusal) },
        read: fn(effect, _planned) {
          spell_plan.read_row(
            tables:,
            spell_groups: spell_plan.spell_groups(tables:),
            place: spell_tables.pressed,
            effect:,
          )
        },
      )
    },
  )
}

pub fn a_missing_table_row_is_matched_to_a_row_of_the_tree_that_gives_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Fluff row 90001 names Prerequisite 99, which the planted table lacks: `read_row`
  // gives the same NoRow the plan's load gives, so the spell is refused for a row.
  let missing = spell_plan.NoRow(table: "Prerequisite", id: 99)
  let compared =
    refused_with(
      fluff_columns: [
        #("durationTime", Integer(5000)),
        #("prerequisiteIdCasterApply", Integer(99)),
      ],
      refusal: missing,
    )
  assert compared.disagreements == []
  assert compared.refused_by_row == 1
    as "a row of the tree gives the same error: it is no refusal of a spell column"
  assert dict.size(compared.refused_for_a_spell_column) == 0
  let unmatched = refused_with(fluff_columns: [], refusal: missing)
  assert unmatched.disagreements == []
  assert dict.to_list(unmatched.refused_for_a_spell_column)
    == [#("a table row the tree names", 1)]
    as "with no row that gives it, the same NoRow is a refusal of a spell column (a Spell4Conditions or Prerequisite column of the spell)"
}

pub fn a_missing_display_row_no_row_of_the_tree_gives_is_a_disagreement_test() -> Nil {
  use <- owned_test.run(60_000)
  // Only a DisguiseOutfit row reads ItemDisplay (`display_slot`): a refusal naming one that
  // no row of the tree gives is outside `read_row`.
  let compared =
    refused_with(
      fluff_columns: [#("durationTime", Integer(5000))],
      refusal: spell_plan.NoRow(table: "ItemDisplay", id: 9999),
    )
  assert list.map(compared.disagreements, fn(disagreement) {
      #(disagreement.spell4_id, disagreement.plan)
    })
    == [
      #(
        32_893,
        "refused: "
          <> spell_plan.describe(error: spell_plan.NoRow(
          table: "ItemDisplay",
          id: 9999,
        )),
      ),
    ]
    as "the test names the spell and the refusal"
}

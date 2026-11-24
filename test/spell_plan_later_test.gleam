//// The abilities a class gains above level 1 and the plans of them
//// (`genesis_prime/game/spell_plan` `unplanned`, `is_unbuilt`; `genesis_prime/game/loadout`).
//// Expected values come from these places.
//// - `SpellLevel.spell4Id.no_prerequisite`: each of the six classes has 27 rows with no
////   prerequisite, 3 at level 1 and 24 above it, 162 in all, none naming a class's innate
////   base; `table_rows -- SpellLevel prerequisiteId=0`.
//// - The rows the cases edit: SpellLevel 929 (Warrior, level 6) names Spell4 57694 (base
////   37245), whose one effect row is Spell4Effects 138014; SpellLevel 919 (Warrior, level 1)
////   names Spell4 32078 (base 18309); Class 1's first innate is Spell4 46867.
//// - A load refuses a row the data faults on (a Spell4 row that is not there, a number that is
////   no number, an innate that is also an ability), and goes on for an ability whose effect or
////   rule the server does not build (issue #1003 builds them); `is_unbuilt` is the one place
////   that says which.

import client_tables
import fixture_tables
import genesis_prime/game/area
import genesis_prime/game/effect_kind
import genesis_prime/game/effect_row_read
import genesis_prime/game/forced_move
import genesis_prime/game/innate
import genesis_prime/game/loadout
import genesis_prime/game/spell_area
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type PlanError}
import genesis_prime/table/id.{
  type Spell4BaseId, ClassId, Spell4BaseId, Spell4EffectsId, Spell4Id,
  TelegraphDamageId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/spell_level
import genesis_prime/table/telegraph_damage
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import planted_table.{type Cell, Float, Integer}
import spell_tables
import unitest

/// The Warrior's level 6 row, whose Spell4 and effect the cases edit, and the Spell4 of its
/// level 1 row.
const later_row = 929

const later_spell = 57_694

/// Row 138014 is a damage row with two parameter factors; a case that makes it a type 11
/// row zeroes them, since a modifier row with a parameter factor is not read
/// (`ParameterNotRead`) and the case is about another refusal.
const later_effect = 138_014

const level_one_spell = 32_078

/// The load of the committed rows with a row added to SpellLevel and the edits to other
/// rows: the tables, or the load's refusal.
fn loaded(
  added added: List(#(String, Cell)),
  changed changed: List(#(String, Int, List(#(String, Cell)))),
) -> Result(table_store.Tables, table_store.LoadError) {
  let rows = fixture_tables.rows()
  let assert Ok(rows) = case added {
    [] -> Ok(rows)
    _ ->
      fixture_tables.add(
        rows:,
        table: "SpellLevel",
        copy_of: later_row,
        id: 99_001,
        with: added,
      )
  }
    as "the committed rows hold SpellLevel 929"
  let assert Ok(rows) = fixture_tables.change_all(rows:, edits: changed)
    as "the committed rows hold the rows the case edits"
  fixture_tables.load(rows: fixture_tables.closure(rows:, roots: []))
}

/// The refusal's sentence, or the empty text for a load that went on.
fn refusal(
  loaded loaded: Result(table_store.Tables, table_store.LoadError),
) -> String {
  case loaded {
    Ok(_) -> ""
    Error(error) -> table_store.describe(error)
  }
}

type Refused {
  Refused(
    why: String,
    added: List(#(String, Cell)),
    changed: List(#(String, Int, List(#(String, Cell)))),
    names: List(String),
  )
}

fn refused_cases() -> List(Refused) {
  [
    Refused(
      "a later row whose Spell4 row is missing fails the load, naming the table and the row",
      [#("spell4Id", Integer(999_999))],
      [],
      ["Spell4", "999999"],
    ),
    Refused(
      "a later row whose base is the class's innate fails the load: the bag holds one item of a base",
      [#("spell4Id", Integer(46_867))],
      [],
      ["30828"],
    ),
    Refused(
      "a level-1 row with a cost type no check was read for still fails the load",
      [],
      [
        #("Spell4", level_one_spell, [
          #("innateCostType0", Integer(2)),
          #("innateCost0", Integer(10)),
        ]),
      ],
      ["32078", "type 2"],
    ),
    Refused(
      "a later row that names a property no UnitProperty2 row holds fails the load",
      [],
      [
        #("Spell4Effects", later_effect, [
          #("effectType", Integer(11)),
          #("targetFlags", Integer(1)),
          #("dataBits00", Integer(99_999)),
          #("parameterValue00", Float(0.0)),
          #("parameterValue01", Float(0.0)),
        ]),
      ],
      ["UnitProperty2", "99999"],
    ),
    Refused(
      "a later row with a modifier number that is no number fails the load",
      [],
      [
        #("Spell4Effects", later_effect, [
          #("effectType", Integer(11)),
          #("targetFlags", Integer(1)),
          #("dataBits00", Integer(102)),
          #("dataBits02", Integer(2_143_289_344)),
          #("parameterValue00", Float(0.0)),
          #("parameterValue01", Float(0.0)),
        ]),
      ],
      ["138014", "dataBits02"],
    ),
    Refused(
      "a later row with a forced move whose distance is no number fails the load: a data fault, not a move the server does not build",
      [],
      [
        #("Spell4Effects", later_effect, [
          #("effectType", Integer(3)),
          #("targetFlags", Integer(2)),
          #("dataBits00", Integer(4)),
          #("dataBits01", Integer(2_143_289_344)),
        ]),
      ],
      ["138014", "dataBits01"],
    ),
    Refused(
      "a later row whose Spell4 names an area row the table lacks fails the load, naming the table and the row",
      [],
      [
        #("Spell4", later_spell, [
          #("spell4AoeTargetConstraintsId", Integer(999_999)),
        ]),
      ],
      ["Spell4AoeTargetConstraints", "999999"],
    ),
  ]
}

pub fn a_later_ability_whose_row_is_missing_fails_the_load_but_an_unread_effect_does_not_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(refused_cases(), fn(case_) {
    let sentence =
      refusal(loaded: loaded(added: case_.added, changed: case_.changed))
    assert sentence != "" as case_.why
    assert list.all(case_.names, string.contains(sentence, _))
      as { case_.why <> ": " <> sentence }
  })
  // A later row whose Spell4 has a cost type no check was read for: the load goes on, and the
  // row is listed as not planned with the error that says why.
  let assert Ok(tables) =
    loaded(added: [], changed: [
      #("Spell4", later_spell, [
        #("innateCostType0", Integer(2)),
        #("innateCost0", Integer(10)),
      ]),
    ])
    as "an unread cost on a later ability does not fail the load"
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  assert list.map(left_out, fn(one) { one.spell4_id })
    |> list.contains(later_spell)
    as "the ability is listed as not planned"
  assert list.any(left_out, fn(one) {
    one.spell4_id == later_spell
    && one.error == spell_plan.UnreadCost(spell4_id: later_spell, cost_type: 2)
  })
    as "its error is UnreadCost with the Spell4 and the cost type"
  assert dict.get(spell_plan.plans_with_later(tables:), 37_245) == Error(Nil)
    as "no plan holds its base, so a press of it is refused unknown"
  let set = case loadout.of(tables:, class_id: ClassId(1), faction_id: 166) {
    Ok(set) -> set
    Error(Nil) -> panic as "the load gives the Warrior a loadout"
  }
  assert list.any(set.later, fn(unlock) { unlock.base.value == 37_245 })
    as "the ability is still granted: the loadout holds it"
}

/// Every error name the plan can fail with, and whether the load goes on for it: `is_unbuilt`
/// is an exhaustive match, so a new error forces the choice at compile time, and this table
/// pins today's.
fn errors() -> List(#(PlanError, Bool)) {
  [
    #(spell_plan.ProxyAimNotRead(1, 2, 3), True),
    #(spell_plan.ProxyCycle([1]), True),
    #(spell_plan.UnreadCost(1, 2), True),
    #(spell_plan.UnreadRequirement(1, 2), True),
    #(spell_plan.GainAimNotRead(1, 2, 3), True),
    #(spell_plan.GainVitalNotRead(1, 2, 3), True),
    #(spell_plan.GainShareNotRead(1, 2, 3, 4), True),
    #(spell_plan.ApplyPrerequisiteNotRead(1, 2, 3), True),
    #(spell_plan.TargetPrerequisiteReadsStruckUnit(1, 2, 3), True),
    #(spell_plan.ControlHelperNotRead(1, 2, 3), True),
    #(spell_plan.SpendComparisonNotRead(1, 2, 3), True),
    #(spell_plan.ForceRemoveSelectorNotRead(1, 2, 3), True),
    #(spell_plan.ForceRemoveCountsDiffer(1, 2, 3, 4), True),
    #(spell_plan.LastingAimNotRead(1, 2, 3), True),
    #(spell_plan.ControlStateNotRead(1, 2, 3), True),
    #(spell_plan.ControlAimNotRead(1, 2, 3), True),
    #(spell_plan.FriendlyAreaNotRead(1, 2, 3), True),
    #(spell_plan.ControlPersistenceNotRead(1, 2), True),
    #(spell_plan.StealthAimNotRead(1, 2, 3), True),
    #(spell_plan.StealthTimedNotRead(1, 2), True),
    #(spell_plan.StealthBreaksNotRead(1, 2, 3), True),
    #(spell_plan.StealthConditionNotRead(1, 2), True),
    #(spell_plan.StealthChangeNotRead(1, 2), True),
    #(spell_plan.ParameterNotRead(1, 2, spell_plan.ModifierRow, 3), True),
    #(spell_plan.ParameterNotRead(1, 2, spell_plan.HealRow, 3), True),
    #(spell_plan.HealUntilRemovedNotRead(1, 2), True),
    #(spell_plan.HealNoTick(1, 2, 3, 4), True),
    #(spell_plan.HealOnStruckUnit(1, 2, 3), True),
    #(spell_plan.InterruptArmorTakeBackNotRead(1, 2, 3), True),
    #(spell_plan.InterruptArmorOnStruckUnit(1, 2, 3), True),
    #(spell_plan.ParameterNotRead(1, 2, spell_plan.AbsorptionRow, 3), True),
    #(spell_plan.AbsorptionAmountNotRead(1, 2), True),
    #(spell_plan.AbsorptionPeriodic(1, 2, 3), True),
    #(spell_plan.AbsorptionHasNoLifetime(1, 2), True),
    #(spell_plan.AbsorptionOnStruckUnit(1, 2, 3), True),
    #(spell_plan.ProcKindNotRead(1, 2, 3), True),
    #(spell_plan.StruckMoveNotRead(1, 2, forced_move.UnknownKind(2, 16)), True),
    #(
      spell_plan.StruckMoveNotRead(1, 2, forced_move.NotAFloat(2, "dataBits01")),
      False,
    ),
    #(spell_plan.DisguiseNotRead(1, 2, spell_plan.NamesNoDisplay), True),
    #(spell_plan.AreaNotBuilt(1, "an area"), True),
    #(spell_plan.NoRow("Spell4", 1), False),
    #(spell_plan.ModifierPropertyHasNoRow(1, 2, 3), False),
    #(spell_plan.ModifierNumberNotFinite(1, 2, "dataBits02"), False),
    #(spell_plan.CooldownNumberNotFinite(1, 2), False),
    #(spell_plan.HealNumberNotFinite(1, 2), False),
    #(spell_plan.AbsorptionNumberNotFinite(1, 2), False),
    #(spell_plan.ChannelWithoutPulse(1), False),
    #(spell_plan.NoThresholdTime(1), False),
    #(spell_plan.ProcNotRead(1, 2, "dataBits02", 3), False),
    #(spell_plan.PrerequisiteCycle([1]), False),
    #(spell_plan.AreaDataFault(1, "an area"), False),
    #(spell_plan.InnateFailed(innate.NoSpell(1, 2)), False),
  ]
}

pub fn every_plan_error_is_a_skip_or_a_load_failure_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(errors(), fn(case_) {
    assert spell_plan.is_unbuilt(error: case_.0) == case_.1
      as {
        spell_plan.describe(error: case_.0)
        <> case case_.1 {
          True ->
            " is an effect or rule the server does not build yet: the ability is left out"
          False -> " is a missing row or a fault of the data: the load fails"
        }
      }
  })
}

pub fn every_no_prerequisite_row_is_planned_or_listed_unplanned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  let rows =
    spell_level.all(tables)
    |> list.filter(fn(row) { loadout.is_class_ability(row:) })
  assert list.length(rows) == 162
    as "SpellLevel.spell4Id.no_prerequisite: 27 rows for each of the six classes"
  assert list.all(left_out, fn(one) {
    spell_plan.describe(error: one.error) != ""
    && list.any(rows, fn(row) {
      row.spell4_id == one.spell4_id && row.character_level > 1
    })
  })
    as "each unplanned ability is a row above level 1 with a sentence that says why"
  assert list.all(rows, fn(row) {
    let left = list.any(left_out, fn(one) { one.spell4_id == row.spell4_id })
    let planned = case
      spell_plan.in_plans(
        plans: spell_plan.plans_with_later(tables:),
        base: base_of(tables:, spell4_id: row.spell4_id),
      )
    {
      Ok(_) -> True
      Error(Nil) -> False
    }
    left != planned
  })
    as "every row is planned or listed unplanned, never both and never neither"
}

fn base_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Spell4BaseId {
  let assert Ok(row) = spell4.get(tables:, id: Spell4Id(spell4_id))
    as "a SpellLevel row names a Spell4 row"
  Spell4BaseId(row.spell4_base_id_base_spell)
}

/// The row's id when it is one of the `left_out_rows` and the plan leaves it out as aimed at
/// other units; `Error(Nil)` when it is read, which every other row must be.
fn read_or_left_out(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  place place: spell_plan.RowPlace,
  effect effect: spell4_effects.Spell4Effects,
  left_out_rows left_out_rows: List(Int),
) -> Result(Int, Nil) {
  let name =
    int.to_string(effect.id) <> " of " <> int.to_string(effect.spell_id)
  case list.contains(left_out_rows, effect.id) {
    True -> {
      assert spell_plan.read_row(tables:, sources:, place:, effect:)
        == Ok(spell_plan.LeftOut(why: spell_plan.AimedAtOtherUnits))
        as { "the row " <> name <> " is left out as aimed at other units" }
      Ok(effect.id)
    }
    False -> {
      assert effect_row_read.is_read(tables:, sources:, place:, effect:)
        as {
          "a freed ability that plans and does nothing is a silent wrong result: the row "
          <> name
          <> " is read"
        }
      Error(Nil)
    }
  }
}

/// Each ability (a Spell4 id) is a class ability's SpellLevel row, is not listed unplanned, is held
/// by the plans, and every effect row of its tree and of its alternate's tree is read
/// (`effect_row_read.is_read`) except the `left_out_rows` (Spell4Effects ids), which are the rows
/// left out as aimed at other units and no others. A freed ability that plans and does nothing
/// is a silent wrong result, so every freed ability passes this check. The abilities as planned
/// are returned, in the order given.
fn freed_and_read(
  tables tables: table_store.Tables,
  spell4_ids spell4_ids: List(Int),
  left_out_rows left_out_rows: List(Int),
) -> List(spell_plan.Spell) {
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  let unplanned = list.map(left_out, fn(one) { one.spell4_id })
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  let planned =
    list.map(spell4_ids, fn(spell4_id) {
      assert list.any(spell_level.all(tables), fn(row) {
        row.spell4_id == spell4_id && loadout.is_class_ability(row:)
      })
        as "the id is a class ability's SpellLevel row"
      assert !list.contains(unplanned, spell4_id)
        as "the ability is built, so it is not listed"
      let assert Ok(ability) =
        spell_plan.in_plans(
          plans: spell_plan.plans_with_later(tables:),
          base: base_of(tables:, spell4_id:),
        )
        as "the plans hold the ability"
      ability
    })
  let left_out_seen =
    list.flat_map(planned, fn(ability) {
      let alternate_tree = case ability.alternate {
        Some(alternate) ->
          spell_plan.tree(spell: alternate, started: fn(_) { True })
        None -> []
      }
      list.append(
        spell_plan.tree(spell: ability, started: fn(_) { True }),
        alternate_tree,
      )
      |> list.flat_map(fn(spell) {
        spell_plan.effects_of(sources:, spell4_id: spell.spell4_id.value)
        |> list.filter_map(fn(effect) {
          read_or_left_out(
            tables:,
            sources:,
            place: place_of(effect.spell_id),
            effect:,
            left_out_rows:,
          )
        })
      })
    })
  assert list.unique(left_out_seen) |> list.sort(int.compare)
    == list.sort(left_out_rows, int.compare)
    as "each row named as left out is found in the abilities' trees"
  planned
}

pub fn the_abilities_held_back_only_by_a_flag_8_hit_row_are_planned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  let unplanned = list.map(left_out, fn(one) { one.spell4_id })
  freed_and_read(
    tables:,
    spell4_ids: spell_tables.flag_8_abilities,
    left_out_rows: [],
  )
  let assert Ok(miasma) =
    list.find(left_out, fn(one) { one.spell4_id == 41_484 })
    as "Unsteady Miasma stays listed"
  assert string.contains(
    spell_plan.describe(error: miasma.error),
    "periodic damage effect 229624 that lasts until removed",
  )
    as {
      "its child 41491's only damage row, 229624 (tickTime 1000, flags 514), lasts until removed, which no schedule ends, so the sentence names it: "
      <> spell_plan.describe(error: miasma.error)
    }
  list.each([57_978, 39_157, 42_676], fn(spell4_id) {
    assert !list.contains(unplanned, spell4_id)
      as "Smackdown, Whiplash and Pounce are planned before and after"
  })
}

/// The TelegraphDamage rows of a spell by Spell4Telegraph, read through the table readers.
fn telegraph_rows_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> List(telegraph_damage.TelegraphDamage) {
  spell4_telegraph.all(tables)
  |> list.filter(fn(link) { link.spell4_id == spell4_id })
  |> list.filter_map(fn(link) {
    telegraph_damage.get(
      tables:,
      id: TelegraphDamageId(link.telegraph_damage_id),
    )
  })
}

pub fn the_abilities_held_back_only_by_a_flag_0_or_2_hit_row_are_planned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  list.each(
    freed_and_read(
      tables:,
      spell4_ids: spell_tables.flag_0_or_2_abilities,
      left_out_rows: [],
    ),
    fn(ability) {
      let tree = spell_plan.tree(spell: ability, started: fn(_) { True })
      assert list.any(tree, fn(spell) {
        list.any(
          telegraph_rows_of(tables:, spell4_id: spell.spell4_id.value),
          fn(row) { row.target_type_flags == 0 || row.target_type_flags == 2 },
        )
      })
        as "a spell of its tree holds a hit row with targetTypeFlags 0 or 2"
    },
  )
  list.each(
    [
      #(
        32_814,
        "periodic damage effect 62036 that lasts until removed",
        "Telekinetic Storm: row 1888 is built, its spell 32828's damage row 62036 (tickTime 1000, flags 514) lasts until removed",
      ),
      #(
        36_821,
        "periodic damage effect 100978 that lasts until removed",
        "Pyrokinetic Flame: the torch's damage row 100978 (tickTime, flags bit 2) lasts until removed, which no schedule ends; its heal 181759 reaches the allies its area Proxy 77845 starts 71014 on",
      ),
      #(
        33_181,
        "placed on another unit or drawn another way",
        "Reverie: the rows 195 (flags 0) and 1217 (flags 1) are placed apart",
      ),
      #(
        38_860,
        "placed on another unit or drawn another way",
        "Tether Mine: the rows 1962 (flags 2) and 10894 (flags 1) are placed apart",
      ),
      #(41_543, "of shape 1", "Mortar Strike: row 2867 is of shape 1"),
      #(
        41_398,
        "has a Proxy effect 92875 that casts the Spell4 row 77068 every tickTime on the allies in its area",
        "Field Probes: its Proxy 92875 (effectType 26, dataBits01 77068, Spell4 \"Medic - Field Probes - Buff - Tier 1\", mechanic 4 flags 11: beneficial) would cast a buff on the allies in its field, whom the server does not find",
      ),
    ],
    fn(row) {
      let #(spell4_id, sentence, reason) = row
      let assert Ok(one) =
        list.find(left_out, fn(one) { one.spell4_id == spell4_id })
        as reason
      assert string.contains(spell_plan.describe(error: one.error), sentence)
        as reason
    },
  )
}

pub fn the_five_abilities_the_orders_free_are_planned_and_every_row_of_their_trees_is_read_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  // Collapse 39372 (Furthest), Crisis Wave 41382, Soothe 33140 and Vitality Burst 39132
  // (heals ordered by health) and Dual Fire 39068 (a heal by health beside a Closest damage
  // child): `table_rows -- Spell4Effects spellId=39068 spellId=53286`. Dual Fire's row 84876 and
  // the row 126516 of its Surge alternate 53286 have flags 4, the area alone, which an area that
  // finds the caster's allies reads (the Proxy 126517 to the damage child 53297 is read too).
  let abilities =
    freed_and_read(
      tables:,
      spell4_ids: [39_372, 41_382, 33_140, 39_132, 39_068],
      left_out_rows: [],
    )
  let assert [collapse, ..] = abilities as "Collapse is the first ability"
  let collapse_rows =
    list.flat_map(
      spell_plan.tree(spell: collapse, started: fn(_) { True }),
      fn(spell) {
        spell_plan.effects_of(sources:, spell4_id: spell.spell4_id.value)
        |> list.map(fn(effect) { effect.id })
      },
    )
  list.each([86_110, 141_664, 86_112, 145_055], fn(row) {
    assert list.contains(collapse_rows, row)
      as "Collapse's tree holds the row, which the loop above found read"
  })
}

/// Every row of the abilities' trees (and of their alternates') that `effect_row_read.is_read`
/// refuses, as the row and what `read_row` makes of it, for the abilities with these Spell4 ids,
/// which the plans hold (the innates among them).
fn unread_rows_of(
  tables tables: table_store.Tables,
  spell4_ids spell4_ids: List(Int),
) -> List(#(Int, Result(spell_plan.RowReading, PlanError))) {
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  list.flat_map(spell4_ids, fn(spell4_id) {
    let assert Ok(ability) =
      spell_plan.in_plans(
        plans: spell_plan.plans_with_later(tables:),
        base: base_of(tables:, spell4_id:),
      )
      as "the plans hold the ability"
    let alternate_tree = case ability.alternate {
      Some(alternate) ->
        spell_plan.tree(spell: alternate, started: fn(_) { True })
      None -> []
    }
    list.append(
      spell_plan.tree(spell: ability, started: fn(_) { True }),
      alternate_tree,
    )
    |> list.flat_map(fn(spell) {
      spell_plan.effects_of(sources:, spell4_id: spell.spell4_id.value)
      |> list.filter(fn(effect) {
        !effect_row_read.is_read(
          tables:,
          sources:,
          place: place_of(effect.spell_id),
          effect:,
        )
      })
      |> list.map(fn(effect) {
        #(
          effect.id,
          spell_plan.read_row(
            tables:,
            sources:,
            place: place_of(effect.spell_id),
            effect:,
          ),
        )
      })
    })
  })
}

pub fn every_row_of_the_abilities_with_a_timed_caster_proxy_is_read_but_the_rows_with_a_named_gap_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // The Engineer's stance 47866 (Proxy 121345), the Esper's Spectral Form 58586 (178429),
  // Plasma Wall 38787 (228473) and Nano Field 39180 (85298): a tree whose Proxy ticks and
  // whose other rows are left out is a silent wrong result, so each row the trees leave is
  // named (`table_rows -- Spell4Effects spellId=<id>` of every spell of the trees).
  let unread =
    unread_rows_of(tables:, spell4_ids: [47_866, 58_586, 38_787, 39_180])
  let by_row = list.sort(unread, fn(a, b) { int.compare(a.0, b.0) })
  assert list.map(by_row, fn(row) { row.0 })
    == [85_311, 85_327, 123_744, 228_474]
    as "47866's Proc 123744 sits behind a persistence prerequisite, 38787's Proc 228474 waits for an event the server does not raise and 39180's rows 85311 (Spell4 39185) and 85327 (Spell4 39189) are of effect type 5, which no rule reads"
  let assert [first_type_5, second_type_5, persisted, waiting] = by_row
  assert first_type_5.1 == Ok(spell_plan.LeftOut(why: spell_plan.TypeNotRead))
  assert second_type_5.1 == Ok(spell_plan.LeftOut(why: spell_plan.TypeNotRead))
  assert persisted.1
    == Ok(spell_plan.LeftOut(why: spell_plan.ProcBehindPersistence))
  let assert Ok(spell_plan.LeftOut(why: spell_plan.ProcKindWaits(..))) =
    waiting.1
    as "the Proc row 228474 is left out as a kind that waits"
  Nil
}

pub fn the_nine_abilities_refused_only_for_valid_targets_are_planned_and_the_one_whose_child_is_centred_on_an_ally_stays_listed_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  let plans = spell_plan.plans_with_later(tables:)
  // Each ability's valid targets held a bit the load refused: Defense Grid 54475, Emergency
  // Reserves 32358, Volatile Injection 41756, Empowering Probes 41533 and Extricate 42241
  // (Spell4ValidTargets row 3, bitmask 16), Recursive Matrix 42572 (row 13, 128), Energy
  // Auger 34426 (row 5, 4), Triage 29888 and Regenerative Pulse 39646 (row 12, 256).
  let planned = [
    54_475, 32_358, 41_756, 42_572, 34_426, 29_888, 41_533, 42_241, 39_646,
  ]
  list.each(planned, fn(spell4_id) {
    assert !list.any(left_out, fn(one) { one.spell4_id == spell4_id })
      as {
        int.to_string(spell4_id)
        <> " is built, so it is not listed unplanned ("
        <> int.to_string(list.length(left_out))
        <> " abilities remain listed)"
      }
    assert result.is_ok(spell_plan.in_plans(
      plans:,
      base: base_of(tables:, spell4_id:),
    ))
      as { "the plans hold the ability of Spell4 " <> int.to_string(spell4_id) }
  })
  // Warden 33392 (the most injured ally) is refused for its child's hit row: the area ordered
  // by health is built, and its child 36660 is centred on the ally
  // it is started on, which the picture does not place.
  let assert Ok(one) = list.find(left_out, fn(one) { one.spell4_id == 33_392 })
    as "Warden is refused for its child's hit row"
  let sentence = spell_plan.describe(error: one.error)
  assert string.contains(sentence, "is started on each ally")
    as { "the sentence names its next gate: " <> sentence }
  assert !string.contains(sentence, "valid targets")
    as { "the valid targets are not the refusal: " <> sentence }
}

pub fn the_five_abilities_refused_only_for_a_friendly_area_proxy_are_planned_and_the_one_with_another_gate_stays_refused_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  // Mental Boon 33257, Mending Probes 41333, Astral Infusion 35870, Runes of Protection
  // 39092 and Flash 41926 held a Proxy aimed by flags 5 in a spell that hits no foes and no
  // other refusal; the tables name the Surge alternates 39327 and 54717
  // (`Spell4.spell4IdMechanicAlternateSpell`). 78081 (Barrier) is refused for its own gate: its
  // child 41369 is centred on the ally it is started on (`spell_area`).
  let freed = [33_257, 41_333, 35_870, 39_092, 41_926]
  let still_refused = [#(78_081, "is started on each ally")]
  list.each(freed, fn(spell4_id) {
    assert !list.any(left_out, fn(one) { one.spell4_id == spell4_id })
      as {
        int.to_string(spell4_id)
        <> " is built, so it is not listed unplanned ("
        <> int.to_string(list.length(left_out))
        <> " abilities remain listed)"
      }
    let assert Ok(ability) =
      spell_plan.in_plans(
        plans: spell_plan.plans_with_later(tables:),
        base: base_of(tables:, spell4_id:),
      )
      as "the plans hold the ability"
    let assert Ok(row) = spell4.get(tables:, id: Spell4Id(spell4_id))
      as "a class ability is a Spell4 row"
    case row.spell4_id_mechanic_alternate_spell {
      0 -> {
        assert ability.alternate == None as "an ability with no alternate"
      }
      named -> {
        let assert Some(alternate) = ability.alternate
          as "the ability's Surge alternate is planned with it"
        assert alternate.spell4_id == Spell4Id(named)
          as "the alternate is the one the Spell4 row names"
      }
    }
  })
  list.each(still_refused, fn(refused) {
    let #(spell4_id, words) = refused
    let assert Ok(one) =
      list.find(left_out, fn(one) { one.spell4_id == spell4_id })
      as "the ability is refused for a gate of its own"
    assert string.contains(spell_plan.describe(error: one.error), words)
      as { "the sentence names its own gate: " <> words }
  })
  assert list.all(left_out, fn(one) {
    case one.error {
      spell_plan.FriendlyAreaNotRead(effect_id:, ..) -> {
        let assert Ok(effect) =
          spell4_effects.get(tables:, id: Spell4EffectsId(effect_id))
          as "a refusal names a row of the table"
        effect_kind.kind_of(effect_type: effect.effect_type)
        != effect_kind.Proxy
      }
      _ -> True
    }
  })
    as "no refusal for the friendly area names a Proxy row: a Proxy reads as the caster"
  // Every row of the freed trees is read, but two: 228666 (type 55, in 87375 behind a gate)
  // and 180600 (Flash's detonation Proxy).
  let unread =
    unread_rows_of(tables:, spell4_ids: freed)
    |> list.unique
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  assert list.map(unread, fn(row) { row.0 }) == [180_600, 228_666]
    as "table_rows -- Spell4Effects spellId=<each spell of the trees>"
  let assert [detonation, type_55] = unread
  assert detonation.1
    == Ok(spell_plan.LeftOut(why: spell_plan.ProxyStartsTiersNoChoice))
  assert type_55.1 == Ok(spell_plan.LeftOut(why: spell_plan.TypeNotRead))
  Nil
}

/// The Proxy payloads of an ability's tree and its alternate's, the targets of each row.
fn proxy_targets_of(
  ability ability: spell_plan.Spell,
) -> List(#(Int, spell_plan.ProxyTarget)) {
  let alternate_tree = case ability.alternate {
    Some(alternate) ->
      spell_plan.tree(spell: alternate, started: fn(_) { True })
    None -> []
  }
  list.append(
    spell_plan.tree(spell: ability, started: fn(_) { True }),
    alternate_tree,
  )
  |> list.flat_map(fn(spell) {
    spell_plan.payloads(spell:, as_kind: spell_plan.as_proxy)
  })
  |> list.map(fn(proxy) { #(proxy.effect_id.value, proxy.target) })
}

pub fn the_abilities_that_hold_a_proxy_at_a_friendly_area_start_their_child_on_each_ally_and_the_two_it_frees_are_planned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(left_out) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  let plans = spell_plan.plans_with_later(tables:)
  // The Proxy rows with the area's bit in a spell that hits no foes and finds allies, in the
  // planned abilities: Mental Boon 33257 (36562 and its tiers: 76609, 76778 to 76781), Mending
  // Probes 41333 (92693), Empowering Probes 41533 (93341), Recursive Matrix 42572 (125421),
  // Runes of Protection 39092 (206357, 206358), Astral Infusion 35870 (229155, 229164) and
  // Affinity 39063 (207513, flags 4: "yourself and an ally" is its text, but its row aims at the
  // area alone). Flash 41926 holds 180600, which starts tiers with no choice.
  let on_each_ally_and_the_caster = [
    76_609, 76_778, 76_779, 76_780, 76_781, 92_693, 93_341, 125_421, 206_357,
    206_358, 229_155, 229_164,
  ]
  let targets =
    list.flat_map(
      [33_257, 41_333, 41_533, 42_572, 39_092, 35_870, 39_063],
      fn(spell4_id) {
        let assert Ok(ability) =
          spell_plan.in_plans(plans:, base: base_of(tables:, spell4_id:))
          as "the plans hold the ability"
        proxy_targets_of(ability:)
      },
    )
  let targets_of = fn(row: Int) {
    list.filter_map(targets, fn(found) {
      case found.0 == row {
        True -> Ok(found.1)
        False -> Error(Nil)
      }
    })
    |> list.unique
  }
  list.each(on_each_ally_and_the_caster, fn(row) {
    assert targets_of(row) == [spell_plan.OnCaster, spell_plan.OnEachAlly]
      as {
        "row "
        <> int.to_string(row)
        <> " starts its child on the caster and on each ally"
      }
  })
  assert targets_of(207_513) == [spell_plan.OnEachAlly]
    as "Affinity's row 207513 (flags 4) starts its child on each ally alone"
  assert targets_of(180_600) == []
    as "Flash's row 180600 starts no child: it names tiers with no choice"
  let sources = spell_plan.sources_of(tables:)
  let assert Ok(flash_row) =
    spell4_effects.get(tables:, id: Spell4EffectsId(180_600))
  assert spell_plan.read_row(
      tables:,
      sources:,
      place: effect_row_read.places(
        tables:,
        effects: spell4_effects.all(tables),
      )(flash_row.spell_id),
      effect: flash_row,
    )
    == Ok(spell_plan.LeftOut(why: spell_plan.ProxyStartsTiersNoChoice))
  // Sentinel 54395 and Mending Banner 33345 held a Proxy at the area (a Guard on the party
  // member missing the most health; "the most injured ally within 35 m", texts 483043, 246918)
  // and are planned.
  list.each([54_395, 33_345], fn(spell4_id) {
    assert !list.any(left_out, fn(one) { one.spell4_id == spell4_id })
      as {
        int.to_string(spell4_id)
        <> " is built, so it is not listed unplanned ("
        <> int.to_string(list.length(left_out))
        <> " abilities remain listed)"
      }
    assert result.is_ok(spell_plan.in_plans(
      plans:,
      base: base_of(tables:, spell4_id:),
    ))
      as { "the plans hold the ability of Spell4 " <> int.to_string(spell4_id) }
  })
  // Warden 33392 and Barrier 78081 are centred on the ally their child is started on, which
  // the picture does not place; Pyrokinetic Flame, Voidspring (its area 653 is ordered by the
  // lowest health, which no friendly area builds, so its Proxy starts on a creature) and
  // Field Probes keep their own sentences, and Projected Spirit's Proxy 77150 fires at each of
  // the five gos of spell 36696 (phaseFlags -1) while its texts (292646, 488045: "restoring ...
  // health to yourself and N allies") say the health is restored once.
  list.each(
    [
      #(
        33_392,
        "has a hit telegraph placed on the cast's target and is started on each ally",
      ),
      #(
        78_081,
        "has a hit telegraph placed on the cast's target and is started on each ally",
      ),
      #(
        36_233,
        "Proxy effect 77150 that starts a child on each ally in its area at 5 gos",
      ),
      #(36_821, "periodic damage effect 100978 that lasts until removed"),
      #(
        39_134,
        "Proxy effect 85651 that starts a child on each struck unit, which holds the Heal or HealShields effect 85652",
      ),
      #(41_398, "every tickTime on the allies in its area"),
    ],
    fn(row) {
      let #(spell4_id, sentence) = row
      let assert Ok(one) =
        list.find(left_out, fn(one) { one.spell4_id == spell4_id })
        as { int.to_string(spell4_id) <> " stays listed unplanned" }
      assert string.contains(spell_plan.describe(error: one.error), sentence)
        as { "its sentence: " <> spell_plan.describe(error: one.error) }
    },
  )
}

pub fn every_proxy_row_with_no_ticktime_aimed_at_the_area_of_an_ally_finding_spell_starts_its_child_on_each_ally_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  // Every Proxy row of the table (effectType 26) with no tickTime and the area's bit
  // (targetFlags 4), in a spell whose area finds the caster's allies (`RowPlace.finds_allies`),
  // is read as a child on each ally and never on each struck unit: the units of a friendly
  // area are the caster's allies, players. A row that is not read that way is left out (it names
  // no spell, or tiers with no choice) or has an aim the plan does not read (bit 8).
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let rows = spell4_effects.all(tables)
  let place_of = effect_row_read.places(tables:, effects: rows)
  let proxies =
    list.filter(rows, fn(row) {
      row.effect_type == 26
      && row.tick_time == 0
      && int.bitwise_and(row.target_flags, 4) != 0
      && place_of(row.spell_id).finds_allies
    })
  assert proxies != []
    as "the table holds Proxy rows at the area of a spell that finds allies"
  list.each(proxies, fn(row) {
    let reading =
      spell_plan.read_row(
        tables:,
        sources:,
        place: place_of(row.spell_id),
        effect: row,
      )
    let why =
      "Proxy row "
      <> int.to_string(row.id)
      <> " of Spell4 "
      <> int.to_string(row.spell_id)
    case reading {
      Ok(spell_plan.Applied(spell_plan.ReadProxy(targets:, ..)))
      | Ok(spell_plan.Held(spell_plan.ReadProxy(targets:, ..))) -> {
        assert list.contains(targets, spell_plan.OnEachAlly)
          as { why <> " starts a child on each ally" }
        assert !list.contains(targets, spell_plan.OnEachStruck)
          as { why <> " starts no child on a struck unit" }
      }
      Ok(spell_plan.LeftOut(..)) | Error(spell_plan.ProxyAimNotRead(..)) -> Nil
      Ok(_) -> panic as { why <> " is read as another kind" }
      Error(error) ->
        panic as { why <> " is refused: " <> spell_plan.describe(error:) }
    }
  })
}

pub fn no_planned_proxy_starts_its_child_on_each_ally_at_more_than_one_go_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  // The texts of a Proxy at the allies of an area ("yourself and N allies") say the child acts
  // once on each ally, so a Proxy whose phaseFlags name two or more gos of its spell, which
  // would act on an ally at each, is refused (`ProxyOnEachAllyAtSeveralGos`).
  let tables = client_tables.shared()
  let several =
    dict.values(spell_plan.plans_with_later(tables:))
    |> list.flat_map(fn(plan) {
      spell_plan.tree(spell: plan, started: fn(_) { True })
    })
    |> list.flat_map(fn(spell) {
      spell_plan.payloads(spell:, as_kind: spell_plan.as_proxy)
      |> list.filter(fn(proxy) { proxy.target == spell_plan.OnEachAlly })
      |> list.filter(fn(proxy) {
        list.count(
          spell_plan.go_numbers(go_count: spell_plan.go_count(spell:)),
          fn(go) {
            spell_effect.names_phase(phase_flags: proxy.phase_flags, phase: go)
          },
        )
        > 1
      })
      |> list.map(fn(proxy) { #(spell.spell4_id.value, proxy.effect_id.value) })
    })
  assert several == []
    as "no planned Proxy at the allies of an area fires at two gos or more of its spell"
}

pub fn every_row_of_nullifiers_tree_is_read_and_its_ability_is_planned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // Nullifier 70757: Proxy 180619 starts the field 58868, whose Fluff 175305 (flags 2) holds
  // its node until removed; Proxy 141450 is periodic and aimed at the area, so the field casts
  // the Affliction 77099 on the foes inside it each second
  // (`table_rows -- Spell4Effects spellId=70757 spellId=58868`).
  let assert [nullifier] =
    freed_and_read(tables:, spell4_ids: [70_757], left_out_rows: [])
    as "Nullifier is planned, is not listed unplanned and every row of its tree is read"
  assert nullifier.spell4_id == Spell4Id(70_757)
  assert unread_rows_of(tables:, spell4_ids: [70_757]) == []
    as "every row of the tree is read, the area Proxy 141450 among them"
  let sources = spell_plan.sources_of(tables:)
  assert list.any(
    spell_plan.tree(spell: nullifier, started: fn(_) { True }),
    fn(spell) {
      list.any(
        spell_plan.effects_of(sources:, spell4_id: spell.spell4_id.value),
        fn(effect) { effect.id == 175_305 },
      )
    },
  )
    as "the tree holds the field's Fluff 175305, which the aura ends"
}

pub fn restrictors_field_over_the_clients_rows_reads_every_row_and_the_ability_is_planned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  // Restrictor 38279: the ForcedMove 81851 (the blink back) and the once Proxy 82064 to the
  // field 38287, whose Fluff 175028 holds its node and whose periodic Proxy 131274 casts
  // Snare 77118, holding the CCStateSet 200476
  // (`table_rows -- Spell4Effects spellId=38279 spellId=38287 spellId=77118`). The field's
  // area row 391 is Random, 10 units within 15 m, and its telegraph a box 15 by 6 starting 1
  // m ahead (`table_rows -- Spell4AoeTargetConstraints 391`).
  let assert [restrictor] =
    freed_and_read(tables:, spell4_ids: [38_279], left_out_rows: [])
    as "Restrictor is planned, is not listed unplanned and every row of its tree is read"
  assert unread_rows_of(tables:, spell4_ids: [38_279]) == []
    as "no row of the tree is left out or held"
  let tree = spell_plan.tree(spell: restrictor, started: fn(_) { True })
  assert list.map(tree, fn(spell) { spell.spell4_id.value })
    |> list.unique
    |> list.sort(int.compare)
    == [38_279, 38_287, 77_118]
    as "the tree is the press, the field and the Snare child"
  assert list.flat_map(tree, fn(spell) {
      list.map(
        spell_plan.effects_of(sources:, spell4_id: spell.spell4_id.value),
        fn(effect) { effect.id },
      )
    })
    |> list.unique
    |> list.sort(int.compare)
    == [81_851, 82_064, 131_274, 175_028, 200_476]
    as "the rows read are exactly the five the tree holds"
  let assert Ok(field) =
    spell_area.of_spell(
      areas: spell_area.areas(tables:),
      spell4_id: Spell4Id(38_287),
    )
    as "the field is in the areas"
  assert field.row
    == Some(area.Row(
      min_range: 0.0,
      max_range: 15.0,
      degrees: 360.0,
      target_count: 10,
      order: area.Random,
    ))
    as "Random 10 within 15 m"
  assert spell_area.inside(spell: field, phase: 0)
    == Some(
      area.InsideShapes(placements: [
        area.Placement(
          shape: area.Box(width: 15.0, length: 6.0),
          ahead: 1.0,
          aside: 0.0,
          turn_degrees: 0.0,
        ),
      ]),
    )
    as "the box 15 by 6, 1 m ahead"
  assert field.anchor == area.FixedAtCaster
    as "the field stays where the press began"
}

pub fn augmented_blades_tree_is_read_in_full_and_its_ability_is_planned_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // Augmented Blade 46935 (ability 30896): its Proxies start 79753 (whose open Proxy 210304
  // casts a Kinetic Rage stack, 79757, each second, whose own Proxy 210337 casts 79758 each
  // 250 ms) and, when it is turned off, 57357 (which starts the removal 82838, whose open
  // Proxy 217944 casts 82839) (`table_rows -- Spell4Effects spellId=46935 spellId=57357
  // spellId=79753 spellId=79757 spellId=82838 spellId=82839`).
  let assert [ability] =
    freed_and_read(tables:, spell4_ids: [46_935], left_out_rows: [])
    as "Augmented Blade is planned, is not listed unplanned and every row of its tree is read"
  assert unread_rows_of(tables:, spell4_ids: [46_935]) == []
    as "no row of the tree is left out or held"
  assert list.map(
      spell_plan.tree(spell: ability, started: fn(_) { True }),
      fn(spell) { spell.spell4_id.value },
    )
    |> list.unique
    |> list.sort(int.compare)
    == [46_935, 57_357, 79_753, 79_757, 79_758, 82_838, 82_839]
    as "the tree is the seven spells the Proxies reach"
}

pub fn the_proxies_of_the_three_targeted_root_abilities_start_the_five_counted_children_on_the_press_target_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  // The three abilities whose root is a Targeted beneficial kind and whose Proxy rows aim at
  // the primary target (Spell4Effects.targetFlags 2): 19030 Mind Over Body, 19031 Bolster
  // and 19033 Phantasmal Armor (`table_rows -- Spell4Effects spellId=ID` for each tier
  // spell). Each Proxy row counts once, whatever tiers and trees reach it.
  let abilities = [19_030, 19_031, 19_033]
  let proxies =
    list.filter(spell4.all(tables), fn(row) {
      list.contains(abilities, row.spell4_base_id_base_spell)
    })
    |> list.flat_map(fn(row) {
      let assert Ok(tier) =
        spell_plan.spell_alone(tables:, sources:, spell4_id: row.id, chain: [])
        as "each tier of the three abilities plans alone"
      spell_plan.tree(spell: tier, started: fn(_) { True })
      |> list.flat_map(fn(spell) {
        spell_plan.payloads(spell:, as_kind: spell_plan.as_proxy)
      })
    })
    |> list.unique
  let on_the_press_target =
    list.filter(proxies, fn(proxy) {
      proxy.target == spell_plan.OnPrimaryTarget
    })
  assert list.length(on_the_press_target) == 26
    as "26 Proxy rows aim at the primary target: 19033 15, 19031 10, 19030 1"
  assert list.all(on_the_press_target, fn(proxy) {
    proxy.condition == spell_plan.Always
  })
    as "each of them has no gate"
  let children =
    list.map(on_the_press_target, fn(proxy) { proxy.spell.spell4_id.value })
  assert list.map(list.unique(children), fn(child) {
      #(child, list.count(children, fn(other) { other == child }))
    })
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    == [#(54_912, 1), #(76_766, 14), #(77_864, 1), #(82_438, 9), #(87_531, 1)]
    as "the five children are 54912 (1 row), 76766 (14), 77864 (1), 82438 (9) and 87531 (1)"
  assert !list.any(proxies, fn(proxy) {
    proxy.target == spell_plan.OnEachStruck
  })
    as "no Proxy of the three abilities' trees is aimed at each struck unit"
  // The periodic one is Bolster tier 9's Spell4Effects 229005: tickTime 1000, durationTime
  // 8000, casting 87531 (`table_rows -- Spell4Effects 229005`).
  let periodic =
    list.filter(on_the_press_target, fn(proxy) { option.is_some(proxy.period) })
  assert list.map(periodic, fn(proxy) {
      #(proxy.effect_id.value, proxy.spell.spell4_id.value)
    })
    == [#(229_005, 87_531)]
    as "exactly one of the 26 rows ticks: 229005, which casts 87531"
  let assert [Some(spell_plan.Periodic(schedule:, ..))] =
    list.map(periodic, fn(proxy) { proxy.period })
    as "the periodic row has a schedule"
  assert schedule.tick_ms == 1000 && schedule.duration_ms == 8000
    as "every 1000 ms for 8000"
  // No child holds a Proxy row of its own, so no grandchild is started on a player the press
  // named, and `start_placed` reads a Proxy aimed at the primary target as on the caster
  // safely: the one child with a hit row, 54912's TelegraphDamage 1392, is a circle with no
  // offset, which the stricter reading of a spell started on a struck unit builds too
  // (`table_rows -- TelegraphDamage 1392`).
  let child_spells =
    list.unique(list.map(on_the_press_target, fn(proxy) { proxy.spell }))
  assert list.all(child_spells, fn(child) {
    spell_plan.payloads(spell: child, as_kind: spell_plan.as_proxy) == []
  })
    as "none of the five children holds a Proxy row"
  let links = spell_area.telegraph_links_by_spell(tables:)
  let with_a_hit_row =
    list.filter_map(child_spells, fn(child) {
      let assert Ok(shapes) =
        spell_area.hit_shapes_of(
          tables:,
          links:,
          id: child.spell4_id.value,
          reading: spell_area.PlayerReading,
        )
        as "each child's hit rows are built for a player"
      case shapes {
        [] -> Error(Nil)
        [_, ..] -> Ok(#(child.spell4_id.value, shapes))
      }
    })
  assert list.map(with_a_hit_row, fn(found) { found.0 }) == [54_912]
    as "only 54912 has a hit row"
  list.each(with_a_hit_row, fn(found) {
    assert spell_area.start_placed(
      anchor: area.FixedAtTarget,
      start: spell_plan.Proxied(target: spell_plan.OnEachStruck),
      shapes: found.1,
    )
      as "its hit shapes are built even where a struck unit's yaw is not known"
  })
}

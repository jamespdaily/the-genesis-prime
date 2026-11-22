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
import genesis_prime/game/effect_row_read
import genesis_prime/game/forced_move
import genesis_prime/game/innate
import genesis_prime/game/loadout
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{type PlanError}
import genesis_prime/table/id.{
  type Spell4BaseId, ClassId, Spell4BaseId, Spell4Id, TelegraphDamageId,
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
  let assert Ok(rows) =
    list.try_fold(changed, rows, fn(rows, edit) {
      fixture_tables.change(rows:, table: edit.0, id: edit.1, with: edit.2)
    })
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
  assert list.contains(unplanned, 34_426)
    as "Energy Auger stays listed: its valid targets are bitmask 4"
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
        "Pyrokinetic Flame: row 10864 is built, its spell 43973's damage row 100978 (tickTime 1000, flags 514) lasts until removed",
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
        "with no spell in dataBits00 and the Spell4 row 77068 in dataBits01",
        "Field Probes: its Proxy 92875 (effectType 26, dataBits00 0, dataBits01 77068, Spell4 \"Medic - Field Probes - Buff - Tier 1\") starts nothing the plan reads, so the ability would be planned and apply nothing",
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

pub fn the_five_abilities_the_orders_free_are_planned_and_every_row_of_their_trees_is_read_but_the_allies_heal_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  // Collapse 39372 (Furthest), Crisis Wave 41382, Soothe 33140 and Vitality Burst 39132
  // (heals ordered by health) and Dual Fire 39068 (a heal by health beside a Closest damage
  // child): `table_rows -- Spell4Effects spellId=39068 spellId=53286`. Dual Fire's row 84876 and
  // the row 126516 of its Surge alternate 53286 have flags 4, the area alone, which the plan
  // leaves out: each heal reaches nobody (the alternate's other rows, the Proxy 126517 to the
  // damage child 53297, are read), and the heals of flags 5 reach the caster alone. The gaps
  // `spell_plan` "Spell areas" (the caster's allies in a spell that hits no foes) and
  // `cast/heal` "Casting" (a heal aimed at another unit lands nothing) state both.
  let abilities =
    freed_and_read(
      tables:,
      spell4_ids: [39_372, 41_382, 33_140, 39_132, 39_068],
      left_out_rows: [84_876, 126_516],
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

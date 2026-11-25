//// The spells the AMPs of a playable class put on a player who holds them, as roots of the plans
//// (`genesis_prime/game/amp_spec` `roots`, `genesis_prime/game/spell_plan` `amp_plans`).
//// Expected values come from these places.
//// - `EldanAugmentation.spell4IdAugment`: AMP 863 (class 5) names 59436, 770 names 56845, 220
////   (class 7) names 57379; the class 0 AMP 20 names 59052; the class 16 AMPs 1 to 12 name
////   Spell4 4 or 33, and class 16 has no Class row (`table_rows -- EldanAugmentation`).
//// - The AMPs of class 5 and 3 whose spells share a Spell4Base with a class ability: 938 (39642,
////   base 23955), 939 (39497, 23829), 941 (33366, 19362), 942 (33272, 19273) and 937 (38973,
////   23337).
//// - `Prerequisite.prerequisiteTypeId.15` and `.50`: a gate reads a live cast of its Spell4 on
////   the unit; Prerequisite 37037 names 59436.

import cast_support as support
import client_tables
import fixture_tables
import genesis_prime/game/amp_spec
import genesis_prime/game/cast
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/effect_row_read
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan
import genesis_prime/table/id.{EldanAugmentationId, Spell4BaseId, Spell4Id}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import unitest

type Row {
  Row(spell4_id: Int, root: Bool, why: String)
}

fn rows() -> List(Row) {
  [
    Row(59_436, True, "AMP 863 of class 5 names it"),
    Row(56_845, True, "AMP 770 of class 5 names it"),
    Row(57_379, True, "AMP 220 of class 7 names it"),
    Row(
      59_052,
      False,
      "only AMP 20 of class 0, which has no Class row, names it",
    ),
    Row(33, False, "only the AMPs of class 16, which has no Class row, name it"),
    Row(
      39_642,
      True,
      "AMP 938 of class 5 names it, though its base is a class ability's",
    ),
    Row(
      39_497,
      True,
      "AMP 939 of class 5 names it, though its base is a class ability's",
    ),
    Row(
      33_366,
      True,
      "AMP 941 of class 3 names it, though its base is a class ability's",
    ),
    Row(
      33_272,
      True,
      "AMP 942 of class 3 names it, though its base is a class ability's",
    ),
    Row(
      38_973,
      True,
      "AMP 937 of class 5 names it, though its base is a class ability's",
    ),
  ]
}

pub fn which_amp_spells_are_standing_roots_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let assert Ok(roots) = amp_spec.roots(tables:)
  list.each(rows(), fn(row) {
    assert list.contains(roots, row.spell4_id) == row.root
      as {
        "Spell4 "
        <> int.to_string(row.spell4_id)
        <> case row.root {
          True -> " is a root: "
          False -> " is not a root: "
        }
        <> row.why
      }
  })
  assert roots == list.unique(roots) && roots == list.sort(roots, int.compare)
    as "each root is listed once, lowest Spell4 id first"
  assert list.length(roots) == 303
    as "the 522 AMP rows of the six playable classes name 303 spells (EldanAugmentation)"
  // The five AMP spells are the Spell4 of class abilities (SpellLevel 984, 1065, 1071, 1159 and
  // 1174, level 16, each behind a Prerequisite), which the plans of the book do not hold: the
  // AMP plans are by Spell4 id and take nothing from the book's plans by base.
  let book = spell_plan.plans_with_later(tables)
  let amp_plans = spell_plan.amp_plans(tables)
  let left_out = spell_plan.unplanned_amps(tables)
  list.each(
    [
      #(23_955, 39_642),
      #(23_829, 39_497),
      #(19_362, 33_366),
      #(19_273, 33_272),
      #(23_337, 38_973),
    ],
    fn(shared) {
      let #(base, amp_spell) = shared
      let spell = int.to_string(amp_spell)
      assert spell_plan.in_plans(plans: book, base: Spell4BaseId(base))
        == Error(Nil)
        as {
          "the class ability of Spell4 "
          <> spell
          <> " is in no plan of the book"
        }
      assert dict.has_key(amp_plans, amp_spell)
        != list.any(left_out, fn(one) { one.spell4_id == amp_spell })
        as { "Spell4 " <> spell <> " is planned by its Spell4 id or left out" }
    },
  )
  let edit = fn(amp_id) {
    let assert Ok(rows) =
      fixture_tables.change_all(rows: fixture_tables.rows(), edits: [
        #("EldanAugmentation", amp_id, [#("spell4IdAugment", Integer(999_001))]),
      ])
    rows
  }
  let assert Error(load_error) =
    fixture_tables.load(
      rows: fixture_tables.closure(rows: edit(863), roots: []),
    )
    as "the load of a playable AMP naming no Spell4 fails"
  let message = table_store.describe(load_error)
  assert string.contains(message, "EldanAugmentation 863")
    && string.contains(message, "999001")
    as { "the message names the AMP and the spell: " <> message }
  let assert Ok(tables) =
    fixture_tables.edited(
      rows: edit(863),
      entries: server_table.entries(),
      requirements: [],
      derivations: [],
    )
  assert amp_spec.roots(tables:)
    == Error(amp_spec.AmpSpellNotRead(
      id: EldanAugmentationId(863),
      spell4_id: Spell4Id(999_001),
    ))
  let assert Ok(tables) =
    fixture_tables.edited(
      rows: edit(20),
      entries: server_table.entries(),
      requirements: [],
      derivations: [],
    )
  let assert Ok(roots) = amp_spec.roots(tables:)
    as "AMP 20 is of class 0: no root, so its spell is never read"
  assert !list.contains(roots, 999_001)
}

/// The AMP spells that a kept condition of type 15 or 50 of a Prerequisite names, among the
/// Prerequisites a Spell4Effects row uses as a gate: its apply, persistence and suspend
/// columns and a Proxy's dataBits06 gate.
fn gate_named(tables tables: table_store.Tables) -> List(Int) {
  let assert Ok(roots) = amp_spec.roots(tables:)
  let gates =
    list.flat_map(spell4_effects.all(tables), fn(effect) {
      [
        effect.prerequisite_id_caster_apply,
        effect.prerequisite_id_target_apply,
        effect.prerequisite_id_caster_persistence,
        effect.prerequisite_id_target_persistence,
        effect.prerequisite_id_target_suspend,
        ..case effect.effect_type {
          26 -> [effect.data_bits06]
          _ -> []
        }
      ]
    })
    |> set.from_list
  prerequisite_table.all(tables)
  |> list.filter(fn(row) { set.contains(gates, row.id) })
  |> list.flat_map(prerequisite.live_cast_spells)
  |> list.map(fn(spell4_id) { spell4_id.value })
  |> list.unique
  |> list.filter(fn(spell4_id) { list.contains(roots, spell4_id) })
  |> list.sort(int.compare)
}

/// Whether a planned AMP spell holds a node on the player once it stands, with its go answered:
/// the spell as `cast.standing_changed` starts it.
fn holds_a_node(spell spell: spell_plan.Spell) -> Bool {
  let caster = support.caster()
  let #(state, effects) =
    cast.standing_changed(
      cast: cast_state.new(),
      caster:,
      wanted: support.without_item(spells: [spell]),
      now: support.at(ms: 1000),
    )
  let #(state, _) =
    support.answered_as(
      caster:,
      state:,
      effects:,
      at: 1000,
      struck: [],
      rolls: [],
    )
  list.any(cast_state.holds_on(cast: state, unit_id: caster.unit_id), fn(hold) {
    hold.spell4_id == spell.spell4_id
  })
}

pub fn every_amp_spell_a_gate_names_stands_with_a_node_on_the_player_or_the_plans_leave_a_row_of_it_out_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let named = gate_named(tables:)
  assert list.contains(named, 59_436)
    as "Prerequisite 37037 names AMP 863's spell, a type 15 condition"
  let planned = spell_plan.amp_plans(tables)
  let left_out = spell_plan.unplanned_amps(tables)
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  let waiting =
    list.filter_map(named, fn(spell4_id) {
      let name = int.to_string(spell4_id)
      case dict.get(planned, spell4_id) {
        Error(Nil) -> {
          assert list.any(left_out, fn(one) { one.spell4_id == spell4_id })
            as { "AMP spell " <> name <> " is neither planned nor left out" }
          Ok(#(spell4_id, "the plans leave it out"))
        }
        Ok(spell) ->
          case
            holds_a_node(spell:),
            effect_row_read.first_unplayed(tables:, sources:, place_of:, spell:)
          {
            True, _ -> Error(Nil)
            False, Some(why) -> Ok(#(spell4_id, why))
            False, None ->
              panic as {
                "AMP spell "
                <> name
                <> " holds no node on the player and no row of it is named as one the server does not play"
              }
          }
      }
    })
  io.println(
    "AMP spells a gate names that wait: "
    <> string.join(
      list.map(waiting, fn(entry) {
        int.to_string(entry.0) <> " (" <> entry.1 <> ")"
      }),
      "; ",
    ),
  )
}

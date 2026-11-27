//// The spells the AMPs of a playable class put on a player who holds them, as roots of the plans
//// (`genesis_prime/shared/amp_spec` `roots`, `genesis_prime/shared/spell_plan` `amp_plans`).
//// Expected values come from these places.
//// - `EldanAugmentation.spell4IdAugment`: AMP 863 (class 5) names 59436, 770 names 56845, 220
////   (class 7) names 57379; the class 0 AMP 20 names 59052; the class 16 AMPs 1 to 12 name
////   Spell4 4 or 33, and class 16 has no Class row (`table_rows -- EldanAugmentation`).
//// - `Prerequisite.prerequisiteTypeId.227` (`table_rows -- Prerequisite prerequisiteTypeId0=227`):
////   18 rows, each one condition naming an AMP id in objectId0 (comparison 1): 937 to 942 (class 5
////   and 3, the spells of 39642, 39497, 33366, 33272 and 38973 among them, each the spell of a
////   class ability of SpellLevel 984, 1065, 1071, 1159 and 1174 behind that Prerequisite), 40, 66,
////   98, 196, 254, 424, 470, 520, 552, 643, 675 and 708. The client reads the condition as "the
////   player holds the AMP in the active set" (`0x14049d760`).
//// - `Prerequisite.prerequisiteTypeId.15` and `.50`: a gate reads a live cast of its Spell4 on
////   the unit; Prerequisite 37037 names 59436.

import cast_support as support
import client_tables
import fixture_tables
import genesis_prime/game/cast
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/effect_row_read
import genesis_prime/shared/amp_spec
import genesis_prime/shared/prerequisite
import genesis_prime/shared/spell_plan
import genesis_prime/table/id.{EldanAugmentationId, Spell4Id}
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
      False,
      "AMP 938 names it and Prerequisite 24736 (type 227) names AMP 938: it unlocks a class ability",
    ),
    Row(
      39_497,
      False,
      "AMP 939 names it and Prerequisite 24737 (type 227) names AMP 939: it unlocks a class ability",
    ),
    Row(
      33_366,
      False,
      "AMP 941 names it and Prerequisite 24740 (type 227) names AMP 941: it unlocks a class ability",
    ),
    Row(
      33_272,
      False,
      "AMP 942 names it and Prerequisite 24741 (type 227) names AMP 942: it unlocks a class ability",
    ),
    Row(
      38_973,
      False,
      "AMP 937 names it and Prerequisite 24735 (type 227) names AMP 937: it unlocks a class ability",
    ),
  ]
}

/// The AMP ids the type 227 conditions of the Prerequisite rows name, read from the first
/// condition's own columns (every one of the client's 18 rows holds one condition).
fn amps_a_type_227_names(tables tables: table_store.Tables) -> List(Int) {
  prerequisite_table.all(tables)
  |> list.filter(fn(row) { row.prerequisite_type_id0 == 227 })
  |> list.map(fn(row) { row.object_id0 })
  |> list.sort(int.compare)
}

/// The fixture's rows with Prerequisite `id`'s objectId0 changed to `amp_id`, loaded without
/// derivations.
fn naming(
  prerequisite_id prerequisite_id: Int,
  amp_id amp_id: Int,
) -> table_store.Tables {
  let assert Ok(rows) =
    fixture_tables.change_all(rows: fixture_tables.rows(), edits: [
      #("Prerequisite", prerequisite_id, [#("objectId0", Integer(amp_id))]),
    ])
  let assert Ok(tables) =
    fixture_tables.edited(
      rows:,
      entries: server_table.entries(),
      requirements: [],
      derivations: [],
    )
  tables
}

pub fn which_amp_spells_are_standing_roots_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let assert Ok(found) = amp_spec.roots(tables:)
  let roots = found.spells
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
  // The AMPs a type 227 condition names are the ones left out as unlocking, read from the
  // table's own columns, and each of their spells is an unlocking AMP's, not a root's.
  let unlocking_ids =
    list.map(found.unlocking, fn(unlocking) { unlocking.id.value })
  assert unlocking_ids == amps_a_type_227_names(tables:)
    as "an AMP is left out as unlocking exactly when a type 227 condition names it"
  assert list.length(unlocking_ids) == 18
    as "the client's 18 type 227 Prerequisite rows name 18 AMPs (Prerequisite)"
  assert list.all(found.unlocking, fn(unlocking) {
    !list.contains(roots, unlocking.spell4_id.value)
  })
    as "an unlocking AMP's spell is no root, as no other AMP names it"
  assert list.length(roots)
    + list.length(
      list.unique(
        list.map(found.unlocking, fn(unlocking) { unlocking.spell4_id.value }),
      ),
    )
    == 303
    as "the 522 AMP rows of the six playable classes name 303 spells, each a root or an unlocking AMP's (EldanAugmentation)"
  // The five spells above are of class abilities; the plans leave their AMPs out with the
  // reason, and the plans of the book hold none of those abilities, since the ability's own
  // Prerequisite names a type the server does not read (type 227).
  let amp_plans = spell_plan.amp_plans(tables)
  let left_out = spell_plan.unplanned_amps(tables)
  list.each([39_642, 39_497, 33_366, 33_272, 38_973], fn(amp_spell) {
    let spell = int.to_string(amp_spell)
    assert !dict.has_key(amp_plans, amp_spell)
      as { "Spell4 " <> spell <> " is not an AMP plan" }
  })
  let assert Ok(reason) =
    list.find(left_out, fn(one) { one.spell4_id == 39_497 })
    as "Spell4 39497 is listed as left out"
  assert spell_plan.describe(error: reason.error)
    == "EldanAugmentation 939 unlocks a class ability, not built"
    as "the reason is stated"
  assert spell_plan.refusal_of(error: reason.error).outcome
    == spell_plan.LeavesOut
    as "and it leaves the spell out, not fails the load"
  // A type 227 condition that names another AMP makes that one unlocking, and the one it left
  // is a root again.
  let assert Ok(changed) =
    amp_spec.roots(tables: naming(prerequisite_id: 24_737, amp_id: 863))
  assert !list.contains(changed.spells, 59_436)
    as "AMP 863 named by a type 227 condition is no root"
  assert list.contains(changed.spells, 39_497)
    as "AMP 939, named by no type 227 condition now, is a root"
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
  let assert Ok(found) = amp_spec.roots(tables:)
    as "AMP 20 is of class 0: no root, so its spell is never read"
  assert !list.contains(found.spells, 999_001)
}

/// The AMP spells that a kept condition of type 15 or 50 of a Prerequisite names, among the
/// Prerequisites a Spell4Effects row uses as a gate: its apply, persistence and suspend
/// columns and a Proxy's dataBits06 gate.
fn gate_named(tables tables: table_store.Tables) -> List(Int) {
  let assert Ok(found) = amp_spec.roots(tables:)
  let roots = found.spells
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

//// The spells the worn items put on their wearers: for each equip spell root of the client's
//// items, whether the plans hold it, and when not, or when its tree holds a row no cast plays,
//// why. The measure asks the plans themselves (`spell_plan.standing_plans`,
//// `spell_plan.standing_unplanned`, `effect_row_read.first_unplayed`), so it cannot disagree
//// with them.
////
//// ```
//// Item2 (takes a slot) ─▶ ItemSpecial.spell4IdOnEquip ─▶ planned, every row played
////                                                      ─▶ planned, stands only in part: the first row no cast plays
////                                                      ─▶ left out: the error that names what the server does not build
//// ```
////
//// - A planned root whose tree holds a row no rule reads stands with the rows that are read,
////   as a later ability does, and is listed with that row.

import genesis_prime/game/effect_row_read
import genesis_prime/game/equip_spell
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/table/loader/store
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// What the measure found.
pub type Report {
  Report(
    /// How many equip spell roots the client's items name.
    roots: Int,
    /// How many of them the plans hold.
    planned: Int,
    /// The roots the plans leave out, by Spell4 id, with the sentence that says why.
    left_out: List(#(Int, String)),
    /// The planned roots with a row no cast plays, by Spell4 id, with the first such row.
    in_part: List(#(Int, String)),
  )
}

/// The measure over the loaded tables, or why the plans cannot be built.
pub fn measure(
  tables tables: store.Tables,
) -> Result(Report, spell_plan.PlanError) {
  use left_out <- result.map(spell_plan.standing_unplanned(
    tables:,
    area_checked: spell_area.checker,
  ))
  let planned = spell_plan.standing_plans(tables:)
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  Report(
    roots: list.length(equip_spell.roots(tables:)),
    planned: dict.size(planned),
    left_out: list.map(left_out, fn(one) {
      #(one.spell4_id, spell_plan.describe(error: one.error))
    }),
    in_part: dict.to_list(planned)
      |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
      |> list.filter_map(fn(entry) {
        case
          effect_row_read.first_unplayed(
            tables:,
            sources:,
            place_of:,
            spell: entry.1,
          )
        {
          Some(why) -> Ok(#(entry.0, why))
          None -> Error(Nil)
        }
      }),
  )
}

/// The measure's lines.
pub fn render(report report: Report) -> String {
  string.join(
    list.flatten([
      [
        "Standing spells of worn items: "
        <> int.to_string(report.roots)
        <> " equip spells; "
        <> int.to_string(report.planned)
        <> " are planned, "
        <> int.to_string(list.length(report.in_part))
        <> " of them standing only in part (a row no cast plays), and "
        <> int.to_string(list.length(report.left_out))
        <> " are left out, so a worn item with one puts nothing on its wearer:",
      ],
      list.map(report.in_part, fn(entry) {
        "- Spell4 "
        <> int.to_string(entry.0)
        <> " stands only in part: "
        <> entry.1
      }),
      list.map(report.left_out, fn(entry) {
        "- Spell4 " <> int.to_string(entry.0) <> " is left out: " <> entry.1
      }),
    ]),
    "\n",
  )
}

/// The measure, or the sentence for why the plans cannot be built.
pub fn report_of(tables tables: store.Tables) -> String {
  case measure(tables:) {
    Ok(report) -> render(report:)
    Error(error) ->
      "Standing spells of worn items: not listed, "
      <> spell_plan.describe(error:)
  }
}

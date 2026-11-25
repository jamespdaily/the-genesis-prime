//// The spells that stand on a player: for each equip spell root of the client's items and each
//// AMP spell, whether the plans hold it, and when not, or when its tree holds a row no cast
//// plays, why. The measure asks the plans themselves (`spell_plan.standing_plans`,
//// `spell_plan.standing_unplanned`, `spell_plan.amp_plans`, `spell_plan.unplanned_amps`,
//// `effect_row_read.first_unplayed`), so it cannot disagree with them.
////
//// ```
//// Item2 (takes a slot) ─▶ ItemSpecial.spell4IdOnEquip ─┐
//// EldanAugmentation (playable class) ─▶ spell4IdAugment ─┴▶ planned, every row played
////                                                         ─▶ planned, stands only in part: the first row no cast plays
////                                                         ─▶ left out: the error that names what the server does not build
//// ```
////
//// - A planned root whose tree holds a row no rule reads stands with the rows that are read,
////   as a later ability does, and is listed with that row.

import genesis_prime/game/effect_row_read
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

/// Where a standing spell comes from.
pub type Source {
  /// The equip spell of a worn item.
  WornItems
  /// The spell of an AMP a player holds.
  PickedAmps
}

/// What the measure found.
pub type Report {
  Report(
    source: Source,
    /// How many equip spell roots the client's items name: the planned ones and the left-out ones.
    roots: Int,
    /// How many of them the plans hold.
    planned: Int,
    /// The roots the plans leave out, by Spell4 id, with the sentence that says why.
    left_out: List(#(Int, String)),
    /// The planned roots with a row no cast plays, by Spell4 id, with the first such row.
    in_part: List(#(Int, String)),
  )
}

/// The measure of the equip spells over the loaded tables, or why the plans cannot be built.
pub fn measure(
  tables tables: store.Tables,
) -> Result(Report, spell_plan.PlanError) {
  use left_out <- result.map(spell_plan.standing_unplanned(
    tables:,
    area_checked: spell_area.checker,
  ))
  measured(
    tables:,
    source: WornItems,
    planned: spell_plan.standing_plans(tables:),
    left_out:,
  )
}

/// The measure of the AMP spells over the loaded tables.
pub fn measure_amps(tables tables: store.Tables) -> Report {
  measured(
    tables:,
    source: PickedAmps,
    planned: spell_plan.amp_plans(tables:),
    left_out: spell_plan.unplanned_amps(tables:),
  )
}

fn measured(
  tables tables: store.Tables,
  source source: Source,
  planned planned: dict.Dict(Int, spell_plan.Spell),
  left_out left_out: List(spell_plan.Unplanned),
) -> Report {
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  Report(
    source:,
    roots: dict.size(planned) + list.length(left_out),
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
        case report.source {
          WornItems -> "Standing spells of worn items: "
          PickedAmps -> "Standing spells of picked AMPs: "
        }
        <> int.to_string(report.roots)
        <> case report.source {
          WornItems -> " equip spells; "
          PickedAmps -> " AMP spells; "
        }
        <> int.to_string(report.planned)
        <> " are planned, "
        <> int.to_string(list.length(report.in_part))
        <> " of them standing only in part (a row no cast plays), and "
        <> int.to_string(list.length(report.left_out))
        <> case report.source {
          WornItems ->
            " are left out, so a worn item with one puts nothing on its wearer:"
          PickedAmps ->
            " are left out, so a player who picks the AMP has no spell stand for it:"
        },
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

/// The measures of the equip spells and of the AMP spells, or the sentence for why the plans
/// cannot be built.
pub fn report_of(tables tables: store.Tables) -> String {
  let amps = render(report: measure_amps(tables:))
  case measure(tables:) {
    Ok(report) -> render(report:) <> "\n" <> amps
    Error(error) ->
      "Standing spells of worn items: not listed, "
      <> spell_plan.describe(error:)
      <> "\n"
      <> amps
  }
}

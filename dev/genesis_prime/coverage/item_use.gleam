//// What the client's items do when they are used: for each Item2 with a spell, whether the
//// server plays the spell, and when not, why. The measure asks the rules that decide a use
//// (`shortcut_spell.item_spell_of`, `activate.planned_of`), so it cannot disagree with them.
////
//// ```
//// Item2 ─▶ ItemSpecial.spell4IdOnActivate ─▶ no Spell4 row      ─▶ refused: the client sends nothing
////                                           ─▶ cast on the user ─▶ played, or refused with its reason
////                                           ─▶ cast at a unit   ─▶ played by the activate cast, or refused
//// ```
////
//// - A refusal is counted by its reason with the row's id left out, so one line is one kind of
////   row (`reason_of`).
//// - The type 18 line counts the spells whose Heal, HealShields or Absorption row holds a
////   type 18 parameter, which the plan reads since the passed-in value is built: how many are
////   item spells, and the rest, which only an ability or an objective that names them makes
////   a change of.

import genesis_prime/game/activate
import genesis_prime/game/item_use
import genesis_prime/game/shortcut_spell
import genesis_prime/shared/damage
import genesis_prime/shared/effect_kind
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/set
import gleam/string

/// What the measure found.
pub type Report {
  Report(
    /// The Item2 rows whose ItemSpecial names a spell.
    items_with_a_spell: Int,
    /// How many of them the server plays.
    played: Int,
    /// How many are refused, by reason, most first.
    refused: List(#(String, Int)),
    /// The spells with a Heal, HealShields or Absorption row holding a type 18 parameter.
    passed_in_spells: Int,
    /// How many of those an item casts.
    passed_in_item_spells: Int,
  )
}

/// The measure over the loaded tables.
pub fn measure(tables tables: store.Tables) -> Report {
  let shortcuts = shortcut_spell.shortcuts(tables:)
  let activations = activate.activations(tables:)
  let spell_ids =
    list.filter_map(item2.all(tables), fn(row) {
      item_use.spell_of(tables:, row:)
      |> result.map(fn(spell4_id) { spell4_id.value })
      |> result.replace_error(Nil)
    })
  let outcomes =
    list.map(spell_ids, fn(spell4_id) {
      outcome_of(tables:, shortcuts:, activations:, spell4_id:)
    })
  let refused =
    list.filter_map(outcomes, fn(outcome) {
      case outcome {
        Played -> Error(Nil)
        Refused(reason:) -> Ok(reason)
      }
    })
    |> list.group(fn(reason) { reason })
    |> dict.to_list
    |> list.map(fn(entry) { #(entry.0, list.length(entry.1)) })
    |> list.sort(fn(first, second) {
      int.compare(second.1, first.1)
      |> order.break_tie(string.compare(first.0, second.0))
    })
  let passed_in = passed_in_spells(tables:)
  Report(
    items_with_a_spell: list.length(spell_ids),
    played: list.length(spell_ids)
      - list.fold(refused, 0, fn(sum, entry) { sum + entry.1 }),
    refused:,
    passed_in_spells: set.size(passed_in),
    passed_in_item_spells: list.count(list.unique(spell_ids), fn(spell4_id) {
      set.contains(passed_in, spell4_id)
    }),
  )
}

type Outcome {
  Played
  Refused(reason: String)
}

fn outcome_of(
  tables tables: store.Tables,
  shortcuts shortcuts: shortcut_spell.Shortcuts,
  activations activations: activate.Activations,
  spell4_id spell4_id: Int,
) -> Outcome {
  case spell4.get(tables:, id: Spell4Id(spell4_id)) {
    Error(Nil) -> Refused(reason: "no Spell4 row: the client sends nothing")
    Ok(_) ->
      case shortcut_spell.item_spell_of(shortcuts:, spell4_id:) {
        shortcut_spell.PlayedOnUser(..) -> Played
        shortcut_spell.NotBuilt(why:) -> Refused(reason: reason_of(why:))
        shortcut_spell.OnAUnit ->
          case activate.planned_of(activations:, spell4_id:) {
            Ok(activate.Planned(..)) -> Played
            Ok(activate.NoSpell4Row)
            | Ok(activate.CannotBePlanned(..))
            | Error(Nil) ->
              Refused(
                reason: "cast at a unit and not planned by the activate cast",
              )
          }
      }
  }
}

/// A refusal's reason with the ids of its rows left out: each run of digits that is not a
/// row's effect type (the number after "type") is replaced by `N`.
fn reason_of(why why: String) -> String {
  let #(kept, _) =
    string.split(why, " ")
    |> list.fold(#([], False), fn(so_far, word) {
      let #(words, after_type) = so_far
      let is_number =
        word != ""
        && int.parse(string.replace(word, ")", "") |> string.replace(",", ""))
        |> result.is_ok
      case is_number && !after_type {
        True -> #([replace_number(word), ..words], False)
        False -> #([word, ..words], word == "(type")
      }
    })
  string.join(list.reverse(kept), " ")
}

fn replace_number(word: String) -> String {
  use <- bool.guard(when: string.ends_with(word, ","), return: "N,")
  "N"
}

/// The spells with a Heal (10), HealShields (118) or Absorption (29) row that holds a type 18
/// parameter with a factor.
fn passed_in_spells(tables tables: store.Tables) -> set.Set(Int) {
  spell4_effects.all(tables)
  |> list.filter(fn(effect) {
    heals_or_absorbs(effect:) && damage.holds_passed_in(effect:)
  })
  |> list.map(fn(effect) { effect.spell_id })
  |> set.from_list
}

fn heals_or_absorbs(effect effect: spell4_effects.Spell4Effects) -> Bool {
  let kind = effect_kind.kind_of(effect_type: effect.effect_type)
  kind == effect_kind.Heal(vital: effect_kind.Health)
  || kind == effect_kind.Heal(vital: effect_kind.Shield)
  || kind == effect_kind.Absorption
}

/// The measure's lines.
pub fn render(report report: Report) -> String {
  let refused = list.fold(report.refused, 0, fn(sum, entry) { sum + entry.1 })
  string.join(
    list.flatten([
      [
        "Item use: "
        <> int.to_string(report.items_with_a_spell)
        <> " Item2 rows cast a spell when used; "
        <> int.to_string(report.played)
        <> " are played and "
        <> int.to_string(refused)
        <> " refused:",
      ],
      list.map(report.refused, fn(entry) {
        "- " <> int.to_string(entry.1) <> " " <> entry.0
      }),
      [
        "Type 18 (the passed-in value): "
        <> int.to_string(report.passed_in_spells)
        <> " spells hold a Heal, HealShields or Absorption row with the parameter, "
        <> int.to_string(report.passed_in_item_spells)
        <> " of them an item's; the others change only where an ability or an objective names them.",
      ],
    ]),
    "\n",
  )
}

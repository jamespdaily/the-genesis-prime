//// The gaps the server has, as the coverage measure prints them.
////
//// ```
//// each module's `gaps()`  ──▶  registry  ──▶  render  ──▶  "Gaps the server has"
//// ```
////
//// - The registry calls `gaps()` of every module that declares it, in the order of the
////   list below; `test/code_rule/gap_registry` fails a module that declares `gaps` and is
////   not called here.
//// - The section holds the gaps no other section of the measure prints: the engine
////   checklists, the later abilities, the press report, the items' uses and the left-out
////   parts keep printing what they print.
//// - The render groups the entries by area in the order each area is first met, and keeps
////   the entries' order within an area.

import genesis_prime/game/ability_points
import genesis_prime/game/activate
import genesis_prime/game/cast
import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/press as cast_press
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/communicator
import genesis_prime/game/interaction
import genesis_prime/game/item_price
import genesis_prime/game/item_property
import genesis_prime/game/item_use
import genesis_prime/game/objective
import genesis_prime/game/prerequisite
import genesis_prime/game/quest
import genesis_prime/game/quest_turn_in
import genesis_prime/game/random_stat
import genesis_prime/game/target_group
import genesis_prime/game/vendor_purchase
import genesis_prime/game/vendor_sale
import genesis_prime/game/world_entry
import genesis_prime/gap.{type Entry}
import gleam/int
import gleam/list
import gleam/string

/// Every module's entries, in the order the modules are listed.
pub fn registry() -> List(Entry) {
  list.flatten([
    quest.gaps(),
    quest_turn_in.gaps(),
    communicator.gaps(),
    objective.gaps(),
    prerequisite.gaps(),
    item_property.gaps(),
    item_price.gaps(),
    item_use.gaps(),
    random_stat.gaps(),
    target_group.gaps(),
    interaction.gaps(),
    vendor_purchase.gaps(),
    vendor_sale.gaps(),
    world_entry.gaps(),
    cast_press.gaps(),
    activate.gaps(),
    ability_points.gaps(),
    cast.gaps(),
    cast_control.gaps(),
    cast_cost.gaps(),
    cast_heal.gaps(),
    cast_proc.gaps(),
  ])
}

/// The section: a first line with the counts, then each area with a bullet for each of
/// its entries, or "no gaps" when the list is empty.
pub fn render(entries entries: List(Entry)) -> String {
  let heading = "Gaps the server has: "
  case entries {
    [] -> heading <> "no gaps"
    [_, ..] -> {
      let areas = list.unique(list.map(entries, fn(entry) { entry.area }))
      string.join(
        [
          heading
            <> int.to_string(list.length(entries))
            <> " entries in "
            <> int.to_string(list.length(areas))
            <> " areas",
          ..list.map(areas, fn(area) { area_lines(entries:, area:) })
        ],
        "\n",
      )
    }
  }
}

/// An area's heading and a bullet for each of its entries.
fn area_lines(entries entries: List(Entry), area area: String) -> String {
  let bullets =
    list.filter_map(entries, fn(entry) {
      case entry.area == area {
        True -> Ok("- " <> entry.missing)
        False -> Error(Nil)
      }
    })
  string.join([area <> ":", ..bullets], "\n")
}

/// The words a change-log sentence uses, which a sentence of what the code does leaves out.
const change_log_words = ["now", "yet", "no longer", "used to", "so far"]

/// What is wrong with the entries, one line each: an area or a sentence that is empty or
/// only white space, a sentence that holds a change-log word, and an entry listed twice. A
/// breach stops the measure with exit code 1.
pub fn breaches(entries entries: List(Entry)) -> List(String) {
  let blank =
    list.filter_map(entries, fn(entry) {
      case string.trim(entry.area) == "" || string.trim(entry.missing) == "" {
        True -> Ok("a gap with no area or no sentence: " <> describe(entry))
        False -> Error(Nil)
      }
    })
  let change_log =
    list.filter_map(entries, fn(entry) {
      case
        list.any(change_log_words, fn(word) {
          words_contain(sentence: entry.missing, phrase: word)
        })
      {
        True -> Ok("a gap sentence with a change-log word: " <> describe(entry))
        False -> Error(Nil)
      }
    })
  let repeated =
    list.filter_map(list.unique(entries), fn(entry) {
      case list.count(entries, fn(other) { other == entry }) > 1 {
        True -> Ok("a gap listed twice: " <> describe(entry))
        False -> Error(Nil)
      }
    })
  list.flatten([blank, change_log, repeated])
}

/// Whether the sentence holds the phrase as whole words.
fn words_contain(sentence sentence: String, phrase phrase: String) -> Bool {
  let words = fn(text) {
    text
    |> string.lowercase
    |> string.replace(",", " ")
    |> string.replace(";", " ")
    |> string.replace(":", " ")
    |> string.replace(".", " ")
    |> string.split(" ")
    |> list.filter(fn(word) { word != "" })
    |> string.join(" ")
  }
  string.contains(" " <> words(sentence) <> " ", " " <> words(phrase) <> " ")
}

fn describe(entry: Entry) -> String {
  entry.area <> ": " <> entry.missing
}

/// The section over the real registry.
pub fn report() -> String {
  render(entries: registry())
}

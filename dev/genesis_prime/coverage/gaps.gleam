//// What the server leaves undone, as the coverage measure prints it.
////
//// ```
//// each module's `gaps()`  ──▶  registry  ──▶  render  ──▶  the measure's section
//// ```
////
//// - The registry calls `gaps()` of every module that declares it, in the order of the
////   list below; `test/code_rule/gap_registry` fails a module that declares `gaps` and is
////   not called here.
//// - The section holds the entries no other section of the measure prints: the engine
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
import genesis_prime/game/click_objective
import genesis_prime/game/communicator
import genesis_prime/game/cooldown
import genesis_prime/game/dev_command
import genesis_prime/game/dropped
import genesis_prime/game/forced_move
import genesis_prime/game/hello_reply
import genesis_prime/game/hit
import genesis_prime/game/interaction
import genesis_prime/game/item_price
import genesis_prime/game/item_property
import genesis_prime/game/item_use
import genesis_prime/game/kill_objective
import genesis_prime/game/limited_action_set
import genesis_prime/game/look
import genesis_prime/game/movement
import genesis_prime/game/objective
import genesis_prime/game/prerequisite
import genesis_prime/game/quest
import genesis_prime/game/quest_turn_in
import genesis_prime/game/random_stat
import genesis_prime/game/routing
import genesis_prime/game/server_proxy
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/strike
import genesis_prime/game/target_group
import genesis_prime/game/ticking
import genesis_prime/game/unit_properties
import genesis_prime/game/vendor_purchase
import genesis_prime/game/vendor_sale
import genesis_prime/game/world_entry
import genesis_prime/gap.{type Entry}
import genesis_prime/message/movement_kind_4
import genesis_prime/message/movement_path
import genesis_prime/message/movement_timed_path
import genesis_prime/message/quest_log
import genesis_prime/message/reward_property_integer
import genesis_prime/message/shared_item
import genesis_prime/message/spell_damage_description
import genesis_prime/message/spell_missed
import genesis_prime/message/spell_started
import genesis_prime/message/vendor_items
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_control
import genesis_prime/world_map/creature_fight
import genesis_prime/world_map/creature_special
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
    dev_command.gaps(),
    routing.gaps(),
    hello_reply.gaps(),
    dropped.gaps(),
    vendor_sale.gaps(),
    world_entry.gaps(),
    spell_plan.gaps(),
    spell_area.gaps(),
    ticking.gaps(),
    forced_move.gaps(),
    unit_properties.gaps(),
    creature_control.gaps(),
    creature.gaps(),
    creature_fight.gaps(),
    creature_special.gaps(),
    movement.gaps(),
    movement_kind_4.gaps(),
    movement_path.gaps(),
    movement_timed_path.gaps(),
    quest_log.gaps(),
    reward_property_integer.gaps(),
    shared_item.gaps(),
    spell_damage_description.gaps(),
    spell_missed.gaps(),
    spell_started.gaps(),
    vendor_items.gaps(),
    server_proxy.gaps(),
    cooldown.gaps(),
    look.gaps(),
    hit.gaps(),
    strike.gaps(),
    click_objective.gaps(),
    kill_objective.gaps(),
    cast_press.gaps(),
    activate.gaps(),
    ability_points.gaps(),
    limited_action_set.gaps(),
    cast.gaps(),
    cast_control.gaps(),
    cast_cost.gaps(),
    cast_heal.gaps(),
    cast_proc.gaps(),
  ])
}

/// The section: a first line with the counts, then each area with a bullet for each of
/// its entries, or a line saying there are none when the list is empty.
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

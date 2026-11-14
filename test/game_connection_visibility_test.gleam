//// The end-of-step check of a player's visibility prerequisites on the game connection
//// (`genesis_prime/game/connection/visibility_check`): a step that changes the set of
//// prerequisites that fail for the player tells the player's map once, and a step that
//// leaves it as it was tells nothing. Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.116`: comparison 2 passes for a unit that is not
////   stealthed and fails for one that is. The planted prerequisite is type 116,
////   comparison 2.
//// - The Stalker's Stealth (`game_connection_stealth_test`): the press at bag index 3
////   makes the player stealthed, and a second press cancels it.
//// - The tell is the map's `VisibilityChanged` (`client_connection.TellVisibilityChanged`),
////   told once per change, so a step of a move that changes nothing tells nothing.

import game_connection_support as support
import genesis_prime/client_connection.{TellVisibilityChanged}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/item_delete
import genesis_prime/message/item_place
import genesis_prime/step.{type ConnectionStep, OwnEffect}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId, PrerequisiteId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/set.{type Set}
import owned_test
import prerequisite_support
import world_entry_support

/// The number of the planted prerequisite, which no Prerequisite row of the client has.
const planted = 900_001

/// The tests' settings, with a planted prerequisite for World 3460 that fails while
/// the player is stealthed.
fn settings() -> game_connection.Settings {
  connection_state.Settings(
    ..support.settings(),
    visibility: dict.from_list([
      #(3460, [
        prerequisite_support.single(id: planted, condition: #(116, 2, 0, 0)),
      ]),
    ]),
  )
}

/// The hidden sets the step tells its map, in order, as prerequisite numbers.
fn visibility_told(
  taken taken: ConnectionStep(client_connection.Request),
) -> List(List(Int)) {
  list.filter_map(support.told_the_map(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(request: TellVisibilityChanged(hidden:, ..), ..)) ->
        Ok(numbers(hidden:))
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

fn numbers(hidden hidden: Set(id.PrerequisiteId)) -> List(Int) {
  list.map(set.to_list(hidden), fn(found) {
    let PrerequisiteId(number) = found
    number
  })
  |> list.sort(by: int.compare)
}

/// The number of the planted prerequisite on a held item.
const planted_on_item = 900_002

pub fn an_item_change_rechecks_the_creatures_it_gates_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Stalker's first novice item is held at location 0 from the entry.
  let character = Character(..support.world_character(), class_id: ClassId(5))
  let assert [item, ..] = world_entry_support.novice_items(character:)
    as "the Stalker's novice set holds an item"
  // Type 246, comparison 2, passes while the checker does not hold the Item2 in locations
  // 0, 1, 2, 8, 9 or 10 (`Prerequisite.prerequisiteTypeId.246`).
  let settings =
    connection_state.Settings(
      ..support.settings(),
      visibility: dict.from_list([
        #(3460, [
          prerequisite_support.single(id: planted_on_item, condition: #(
            246,
            2,
            0,
            item.item2_id.value,
          )),
        ]),
      ]),
    )
  let #(state, entered) =
    support.entered_with(settings:, class_id: 5, saved_health: None)
  assert visibility_told(taken: entered) == [[planted_on_item]]
    as "the Join's set came from the world-entry check, which holds no checker and reads the condition as not decided, so the creature was shown; the entry's end-of-step check holds the checker, finds the item at location 0 and hides the creature: one tell"
  let assert Ok(body) =
    item_delete.encode(
      item_delete.ItemDelete(place: item_place.ItemPlace(
        location: item.location,
        bag_index: item.bag_index,
      )),
    )
    as "a delete fits the message"
  let #(_, deleted) =
    support.item_change_saved(
      state:,
      ms: 2000,
      message: support.world_message(message_id: item_delete.message_id, body:),
    )
  assert visibility_told(taken: deleted) == [[]]
    as "the delete's answer leaves the player not holding the item, so the condition passes again: one tell of the empty set"
}

pub fn a_step_that_changes_the_hidden_set_tells_the_map_once_and_a_move_tells_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, entered) =
    support.entered_with(settings: settings(), class_id: 5, saved_health: None)
  assert visibility_told(taken: entered) == []
    as "the entry's set is the Join's (the planted prerequisite passes for a player that is not stealthed), so the join's answer tells the map nothing"
  let #(state, steps) =
    support.pressed_until(
      state: support.watched_by(state:, viewers: [2, 3]),
      bag_index: support.stealth_bag_index,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 3000,
    )
  assert list.flat_map(steps, fn(taken) { visibility_told(taken:) })
    == [[planted]]
    as "the press makes the player stealthed, so the planted prerequisite fails: one tell of the set, and no later step of the cast tells the same set again"
  let #(state, moved) = support.read(state:, bytes: support.a_move(5.0))
  assert visibility_told(taken: moved) == []
    as "a move leaves the set as it was and tells nothing"
  let #(_, cancelled) =
    support.press_stealth_again(state:, client_cast_id: 2, ms: 4000)
  assert visibility_told(taken: cancelled) == [[]]
    as "a second press cancels the stealth, so the planted prerequisite passes again: one tell of the empty set"
}

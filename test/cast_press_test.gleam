//// What a press the server cannot build says: the refusal's log names what is missing
//// and no issue, a press is logged once for its key, and the gaps the press module
//// lists are the five cases a refusal can name.
////
//// - A refused right-click is answered with its result and logged once for its key
////   (`cast_press.not_built_refusal`); the key's family says which cast it was.
//// - The press's own path for an ability is `cast_test`'s
////   `a_non_normal_ability_is_refused_285_and_logged_once_test`.

import cast_support as support
import genesis_prime/game/cast/press as cast_press
import genesis_prime/game/cast/state as cast_state
import genesis_prime/message/cast_result
import genesis_prime/step.{LogWarning}
import gleam/list
import gleam/string
import owned_test

/// One family of `Unbuilt` key: the key for Spell4 100, and the log its first press writes.
type Family {
  Family(name: String, key: cast_state.Unbuilt, first_log: String)
}

pub fn a_press_the_server_cannot_build_is_refused_and_logged_once_with_what_is_missing_test() -> Nil {
  use <- owned_test.run(5000)
  let why =
    "has a cast condition of the PrerequisiteType 118, which the server does not read"
  list.each(
    [
      Family(
        "a quest button's shortcut cast",
        cast_state.UnbuiltShortcut(spell4_id: 100),
        "the shortcut cast of Spell4 100 " <> why <> ": it is refused with 285",
      ),
      Family(
        "the use of an item's spell",
        cast_state.UnbuiltItemSpell(spell4_id: 100),
        "the use of an item whose spell is Spell4 100 "
          <> why
          <> ": it is refused with 285",
      ),
      Family(
        "an activate cast",
        cast_state.UnbuiltSpell(spell4_id: 100),
        "the activate cast of Spell4 100 " <> why <> ": it is refused with 285",
      ),
    ],
    fn(family) {
      let refuse = fn(state) {
        let assert Ok(taken) =
          cast_press.not_built_refusal(
            cast: state,
            client_cast_id: 7,
            spell4_id: 100,
            key: family.key,
            result: cast_result.IllegalSpellCast,
            why:,
          )
          as family.name
        taken
      }
      let #(state, first) = refuse(cast_state.new())
      assert support.logs(effects: first) == [#(LogWarning, family.first_log)]
        as family.name
      assert support.refusal_results(effects: first) == [285] as family.name
      let #(_, second) = refuse(state)
      assert support.logs(effects: second) == [] as family.name
      assert support.refusal_results(effects: second)
        == support.refusal_results(effects: first)
        as family.name
      assert !string.contains(string.lowercase(family.first_log), "issue")
        && !string.contains(family.first_log, "#")
        as family.name
    },
  )
}

pub fn the_cast_gaps_list_the_five_cases_the_issue_type_named_test() -> Nil {
  use <- owned_test.run(5000)
  let entries = cast_press.gaps()
  assert list.length(entries) == 5 as "one entry for each of the five cases"
  list.each(
    [
      #("another player's unit", "an effect cast at another player"),
      #("prerequisite type", "the unread prerequisite types"),
      #("cannot plan", "spells in depth"),
      #("activate cast", "the activate cast's checks"),
      #("until removed", "the states that last until removed"),
    ],
    fn(case_) {
      let #(word, name) = case_
      assert list.count(entries, fn(entry) {
          string.contains(entry.missing, word)
        })
        == 1
        as name
    },
  )
  assert list.all(entries, fn(entry) {
    entry.area == "Casting"
    && !string.contains(string.lowercase(entry.missing), "issue")
    && !string.contains(entry.missing, "#")
  })
    as "each is in the area Casting and names no issue"
}

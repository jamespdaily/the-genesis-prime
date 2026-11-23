//// The gaps the cast modules state reach the coverage measure: every limit a comment of
//// the casting modules states is one entry of its module's `gaps()`, in the registry the
//// section prints (`genesis_prime/coverage/gaps`). The registry's own layout is
//// `coverage_gaps_test`.

import genesis_prime/coverage/gaps
import genesis_prime/game/ability_points
import genesis_prime/game/activate
import genesis_prime/game/cast
import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/press as cast_press
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/connection/landing as connection_landing
import genesis_prime/game/strike
import genesis_prime/gap.{type Entry}
import gleam/list
import gleam/string
import owned_test
import unitest

/// A limit the code states: the entries of the module that lists it, the area it is in,
/// the words its one entry holds, and what the limit is.
type Limit {
  Limit(entries: List(Entry), area: String, words: List(String), limit: String)
}

fn limits() -> List(Limit) {
  [
    Limit(
      cast_press.gaps(),
      "Casting",
      ["another player's unit", "does not land"],
      "a cast at another player is refused",
    ),
    Limit(
      cast_press.gaps(),
      "Casting",
      ["prerequisite type the server does not read"],
      "a prerequisite type the server does not read refuses a press",
    ),
    Limit(
      cast_press.gaps(),
      "Casting",
      ["cannot plan", "cast method is not built"],
      "a spell the server cannot plan or cast is refused",
    ),
    Limit(
      cast_press.gaps(),
      "Casting",
      ["until removed", "dropped"],
      "a crowd-control state that lasts until removed is dropped",
    ),
    Limit(
      cast_press.gaps(),
      "Casting",
      ["zone", "vital"],
      "a press at a creature does not test its zone or vital state",
    ),
    Limit(
      cast_press.gaps(),
      "Casting",
      ["Channeled", "Normal"],
      "an activate cast of a mismatched Channeled spell is cast as a Normal one",
    ),
    Limit(
      activate.gaps(),
      "Casting",
      ["crowd-control state", "fight state"],
      "an activate cast does not test the target's crowd-control or fight state",
    ),
    Limit(
      activate.gaps(),
      "Casting",
      ["strikes no unit", "refused"],
      "an activate cast strikes no unit, so a spell with a strike effect is refused",
    ),
    Limit(
      activate.gaps(),
      "Casting",
      ["Heal", "RavelSignal", "DespawnUnit", "UnitStateSet", "drops"],
      "an activate cast drops the target and area effects it cannot apply",
    ),
    Limit(
      activate.gaps(),
      "Casting",
      ["QuestAdvanceObjective", "advances nothing"],
      "a quest advance aimed at the target alone advances nothing",
    ),
    Limit(
      activate.gaps(),
      "Casting",
      ["vertical offset"],
      "the client's per-unit vertical offset is not modelled",
    ),
    Limit(
      activate.gaps(),
      "Casting",
      ["0x6c", "0x148"],
      "the creature words that make the client pick no spell are not read",
    ),
    Limit(
      ability_points.gaps(),
      "Abilities",
      ["tier", "dropped"],
      "tier spending is not built: the tier changes of the builder's save are dropped",
    ),
    Limit(
      cast_proc.gaps(),
      "Casting",
      ["critical heal"],
      "no heal is a critical heal",
    ),
    Limit(
      cast.gaps(),
      "Casting",
      ["hoverboard", "mount"],
      "the hoverboard's ride ends in the input of its own go",
    ),
    Limit(
      cast_cost.gaps(),
      "Casting",
      ["request word"],
      "the cast request word is read as 0 for every press",
    ),
    Limit(
      cast_heal.gaps(),
      "Casting",
      ["unit other than the caster"],
      "a heal on another unit lands nothing",
    ),
    Limit(
      cast_control.gaps(),
      "Casting",
      ["stack", "different casters"],
      "the modifiers of different casters on one creature do not stack",
    ),
    Limit(
      connection_landing.gaps(),
      "Casting",
      ["LandsHeal", "ReceivesHeal"],
      "a heal told to a player raises neither the healer's LandsHeal nor the healed player's ReceivesHeal",
    ),
    Limit(
      connection_landing.gaps(),
      "Casting",
      ["round", "closed"],
      "a heal told to a player is applied also after the caster's round has closed",
    ),
    Limit(
      strike.gaps(),
      "Casting",
      ["answer", "dropped"],
      "a healed player's answer is dropped by the connection it is told to",
    ),
  ]
}

pub fn the_cast_gaps_list_the_five_cases_the_issue_type_named_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage"])
  let printed = list.map(gaps.registry(), fn(entry) { entry.missing })
  list.each(
    [
      #("another player's unit", "an effect cast at another player"),
      #(
        "prerequisite type the server does not read",
        "the unread prerequisite types",
      ),
      #("cannot plan", "a spell the server cannot plan"),
      #("strikes no unit", "the activate cast's checks and effects"),
      #(
        "crowd-control state on another unit that lasts until removed",
        "a state that lasts until removed",
      ),
    ],
    fn(named) {
      let #(words, name) = named
      assert list.count(printed, string.contains(_, words)) == 1 as name
    },
  )
}

pub fn each_limit_the_cast_modules_state_is_one_entry_of_its_module_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage"])
  list.each(limits(), fn(limit) {
    let matching =
      list.filter(limit.entries, fn(entry) {
        list.all(limit.words, string.contains(entry.missing, _))
      })
    assert list.length(matching) == 1 as limit.limit
    let assert [entry] = matching
    assert entry.area == limit.area as limit.limit
    assert !string.contains(string.lowercase(entry.missing), "issue")
      && !string.contains(entry.missing, "#")
      as limit.limit
    assert list.contains(gaps.registry(), entry)
      as { limit.limit <> ": the registry prints it" }
  })
}

/// A press at a creature is refused for a held invulnerable or immune-to-beneficial state
/// (`cast.aimed_at_a_creature` runs `press.unit_state_refusal` first), so the entry names
/// only the states the press does not test.
pub fn the_press_entry_names_only_the_creature_states_a_press_does_not_test_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage"])
  assert list.contains(
    cast_press.gaps(),
    gap.Entry(
      area: "Casting",
      missing: "A press at a creature is not refused for a zone or vital state of its target that the server does not hold.",
    ),
  )
}

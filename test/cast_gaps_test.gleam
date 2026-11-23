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
import genesis_prime/game/heal_split
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
      ["press of an ability at another player", "accepted without"],
      "a press at another player is accepted without the target's life, combat, crowd-control state, range, faction and group",
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
      ["creature", "another player", "delay", "caster gate", "in sight"],
      "a heal aimed at a creature, or at another player with a delay, lands nothing, a periodic one at another player in sight ticks on it, and a row aimed at the caster and another player is listed on that player only while its caster gate passes",
    ),
    Limit(
      cast.gaps(),
      "Casting",
      ["delay", "lasts until removed"],
      "a row aimed at another player with a delay or lasting until removed lands nothing",
    ),
    Limit(
      cast.gaps(),
      "Casting",
      ["dead player", "refuses"],
      "a row aimed at a dead player is listed and told, and the player refuses it",
    ),
    Limit(
      cast.gaps(),
      "Casting",
      ["Mental Boon's Nimble", "has no press target"],
      "a child a Proxy starts on the caster (a primary target that is the caster, a creature or a proc's unit) lands none of its rows aimed at the primary target",
    ),
    Limit(
      cast.gaps(),
      "Casting",
      ["periodic Proxy aimed at the primary target", "lands on the caster"],
      "a periodic Proxy aimed at the primary target ticks on the caster, so Bolster's absorb lands on the caster",
    ),
    Limit(
      cast.gaps(),
      "Casting",
      ["target apply prerequisite", "picture"],
      "a target gate on an absorb or modifier row aimed at another player reads what the caster's picture shows of it",
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
      ["LandsHeal", "ReceivesHeal", "23414"],
      "a heal told to a player raises neither the healer's LandsHeal nor the healed player's ReceivesHeal, and three abilities hold ReceivesHeal procs that would fire",
    ),
    Limit(
      connection_landing.gaps(),
      "Casting",
      ["round", "closed"],
      "a heal told to a player is applied also after the caster's round has closed",
    ),
    Limit(
      connection_landing.gaps(),
      "Casting",
      ["0x262", "from another player"],
      "a cast held on a player by another player is not listed in the 0x262 a later viewer is sent",
    ),
    Limit(
      connection_landing.gaps(),
      "Casting",
      ["sight notice", "dropped"],
      "a change told before the player's sight notice of its caster is dropped",
    ),
    Limit(
      connection_landing.gaps(),
      "Casting",
      ["death", "stack group"],
      "a held change ends at its holder's death as a guess, is not scaled by the holder's stats, and two casters sharing a stack group both apply",
    ),
    Limit(
      connection_landing.gaps(),
      "Casting",
      ["another player", "icon", "kept"],
      "a viewer of the ally other than the ally loses the buff icon of a kept cast when the caster leaves its sight, and a cast that holds a change on two players the ally sees ends in the ally's client with the ally's end",
    ),
    Limit(
      strike.gaps(),
      "Casting",
      ["target gate", "another player", "not read"],
      "a target gate on a heal row told to another player reads what the caster holds of it, not the player's own state",
    ),
    Limit(
      strike.gaps(),
      "Casting",
      ["periodic", "another player", "first tick"],
      "a periodic heal on another player ends at the first tick with no answer, a dead player or a player gone from the caster's picture, and does not resume",
    ),
    Limit(
      heal_split.gaps(),
      "Casting",
      ["HealToShieldConversion", "above 1", "guess"],
      "a share above 1 caps the shield part at the heal, while the client shows the uncapped part",
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
  assert list.all(connection_landing.gaps(), fn(entry) {
    list.any(limits(), fn(limit) {
      limit.entries == connection_landing.gaps()
      && list.all(limit.words, string.contains(entry.missing, _))
    })
  })
    as "each gap the landing module states has a row above, held changes and heals alike"
  assert list.all(gaps.registry(), fn(entry) {
    !string.contains(entry.missing, "no description of what the heal applied")
  })
    as "the go lists the heal a player applied with its description, so no entry says the go lists a told player without one"
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
